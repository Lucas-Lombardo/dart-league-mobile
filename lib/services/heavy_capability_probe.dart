import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'bundled_asset_file.dart';

/// What the probe concluded about heavy on THIS phone, and when.
///
/// Persisted, because the measurement is not free (a 12.8 MB model load
/// plus a few inferences). Every verdict dies with the app version it was
/// measured on — a new build ships new native code and possibly a new
/// model, either of which moves the number. Within a version, how long it
/// holds depends on what it is ([validFor]):
///  - capable: for good;
///  - measured too slow: [retryAfter], because a capable phone that was hot
///    or busy on first launch must get another chance without a release;
///  - not measured at all — the load threw, an inference errored —
///    [retryFailureAfter], short: that is a bug or a bad moment, not a
///    number, and it must not park a flagship on v13 for a week;
///  - wedged (a native call timed out): [retryAfter] — re-wedging the
///    native thread at every launch would cost every match that follows.
@immutable
class HeavyProbeVerdict {
  const HeavyProbeVerdict({
    required this.capable,
    required this.medianMs,
    required this.appVersion,
    required this.at,
    required this.reason,
    required this.validFor,
  });

  final bool capable;

  /// Median pure-invoke time of the timed samples, null when nothing could
  /// be measured (load failure, no timing in the response).
  final int? medianMs;
  final String appVersion;
  final DateTime at;

  /// Free text for the log: which rule decided.
  final String reason;

  /// How long this verdict decides for its app version; null = as long as
  /// the version lives.
  final Duration? validFor;

  static const Duration retryAfter = Duration(days: 7);
  static const Duration retryFailureAfter = Duration(days: 1);

  /// The bar heavy has to clear, as a median of pure model-invoke time.
  ///
  /// The capture loop runs at up to 5 fps and the scoring guards count in
  /// FRAMES (a confirmation needs 3 in a row), so 250 ms is the point where
  /// heavy still confirms a dart in under a second. Measured 2026-08-28:
  /// Redmi 13C heavy on its Mali-G52 GPU = 826 ms (fails by 3x); the flagship
  /// Adreno/Mali-G7x class sits around 100-170 ms (passes with room). v13
  /// costs ~0.3x heavy on every compute path, so a phone that fails here
  /// runs v13 at roughly the budget instead — which is the whole point.
  static const int heavyBudgetMs = 250;

  /// One sample this far over the budget settles it without the rest — on a
  /// Redmi 13C that is the difference between a 4 s and an 8 s first launch.
  static const int earlyExitMs = heavyBudgetMs * 2;

  /// Pure decision off the timed samples (warm-ups already dropped).
  factory HeavyProbeVerdict.fromSamples(
    List<int> samples, {
    required String appVersion,
    DateTime? now,
  }) {
    if (samples.isEmpty) {
      return HeavyProbeVerdict.notCapable(
        appVersion,
        reason: 'no timed sample',
        now: now,
      );
    }
    final sorted = [...samples]..sort();
    final median = sorted[sorted.length ~/ 2];
    final capable = median <= heavyBudgetMs;
    return HeavyProbeVerdict(
      capable: capable,
      medianMs: median,
      appVersion: appVersion,
      at: now ?? DateTime.now(),
      reason: 'median ${median}ms ${capable ? '<=' : '>'} ${heavyBudgetMs}ms '
          '(${sorted.length} sample${sorted.length > 1 ? 's' : ''})',
      validFor: capable ? null : retryAfter,
    );
  }

  /// Heavy did not run to a number. [wedged] = a native call timed out.
  factory HeavyProbeVerdict.notCapable(
    String appVersion, {
    required String reason,
    bool wedged = false,
    DateTime? now,
  }) =>
      HeavyProbeVerdict(
        capable: false,
        medianMs: null,
        appVersion: appVersion,
        at: now ?? DateTime.now(),
        reason: reason,
        validFor: wedged ? retryAfter : retryFailureAfter,
      );

  /// Whether this verdict still decides for [appVersion] at [now].
  bool isValidFor(String appVersion, {DateTime? now}) {
    if (this.appVersion != appVersion) return false;
    final ttl = validFor;
    if (ttl == null) return true;
    return (now ?? DateTime.now()).difference(at) < ttl;
  }

  Map<String, Object?> toJson() => {
        'capable': capable,
        'medianMs': medianMs,
        'appVersion': appVersion,
        'at': at.toIso8601String(),
        'reason': reason,
        'validForMs': validFor?.inMilliseconds,
      };

  String encode() => jsonEncode(toJson());

  /// Null for anything that is not a verdict this build wrote — the caller
  /// then measures again, which is the safe reading of a corrupt value.
  static HeavyProbeVerdict? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw);
      if (map is! Map) return null;
      final capable = map['capable'];
      final version = map['appVersion'];
      final at = DateTime.tryParse(map['at'] as String? ?? '');
      // validForMs is present-but-null for "the version's lifetime"; a
      // record without the key predates the field and is re-measured.
      if (capable is! bool ||
          version is! String ||
          at == null ||
          !map.containsKey('validForMs')) {
        return null;
      }
      final validForMs = (map['validForMs'] as num?)?.toInt();
      return HeavyProbeVerdict(
        capable: capable,
        medianMs: (map['medianMs'] as num?)?.toInt(),
        appVersion: version,
        at: at,
        reason: map['reason'] as String? ?? '',
        validFor: validForMs == null ? null : Duration(milliseconds: validForMs),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  String toString() =>
      'HeavyProbeVerdict(${capable ? 'capable' : 'not capable'}, '
      '$reason, v$appVersion, $at)';
}

/// Measures whether THIS Android phone can afford the heavy model, by running
/// it.
///
/// The RAM threshold ModelSelector used to decide this with does not measure
/// what matters: a Redmi 13C reports 7.6 GB and clears it, then runs heavy at
/// 826 ms a frame on its entry-level GPU — 5.2 s if the GPU delegate drops
/// out. Whether the SoC can run the graph is only knowable by running the
/// graph, so this loads heavy into the native plugin exactly as a match
/// would (same file, same GPU-first build with its self-test) and times a
/// few inferences on the bundled reference photo. The verdict is persisted;
/// see [HeavyProbeVerdict] for how long it holds.
///
/// Runs in the background right after startup, before the first camera
/// screen can ask for a model — NativeInference.loadModel waits for it
/// (bounded) so the measurement is never taken on a model a match swapped
/// in underneath. The interpreter it leaves behind is heavy: a capable phone
/// then hits native's "same path — reusing" shortcut on its first real load,
/// a weak one rebuilds with v13 (the normal model switch).
class HeavyCapabilityProbe {
  HeavyCapabilityProbe();

  static const _channel = MethodChannel('com.dartrivals/native_inference');

  /// The frame the Android plugin's own GPU self-test uses — a real board,
  /// bundled, so every phone is timed on the same picture.
  static const String referenceAsset = 'assets/models/check_inference.jpg';

  /// The first inference after a load carries shader compilation and is not
  /// steady state; dropped, never judged.
  static const int _warmups = 1;
  static const int _samples = 3;

  // Same bounds as NativeInference: a wedged native thread must end the
  // probe, not the app.
  static const Duration _loadTimeout = Duration(seconds: 30);
  static const Duration _analyzeTimeout = Duration(seconds: 10);

  bool _cancelled = false;

  /// Abandon the measurement: whatever comes back after this is discarded,
  /// not persisted. Called when a real model load cannot wait any longer, or
  /// when a dev bench forces a model of its own.
  void cancel() => _cancelled = true;

  /// Null when cancelled; otherwise a verdict, with every failure mode
  /// folded into `notCapable` — a load that throws, a delegate that wedges,
  /// a response without timing: on this phone, today, heavy did not run.
  Future<HeavyProbeVerdict?> run({
    required String modelAsset,
    required String appVersion,
  }) async {
    final sw = Stopwatch()..start();
    try {
      final model = await bundledAssetToTempFile(modelAsset);
      final frame = await bundledAssetToTempFile(referenceAsset);
      if (_cancelled) return null;

      final ok = await _channel
          .invokeMethod('loadModelFile', model.path)
          .timeout(_loadTimeout);
      if (_cancelled) return null;
      if (ok != true) {
        return HeavyProbeVerdict.notCapable(appVersion,
            reason: 'load returned $ok');
      }
      final loadMs = sw.elapsedMilliseconds;

      final samples = <int>[];
      for (var i = 0; i < _warmups + _samples; i++) {
        final response = await _channel
            .invokeMethod<Map>('analyzeFile', frame.path)
            .timeout(_analyzeTimeout);
        if (_cancelled) return null;
        final ms = (response?['inferenceMs'] as num?)?.toInt();
        if (ms == null) {
          return HeavyProbeVerdict.notCapable(appVersion,
              reason: 'analyze returned no inferenceMs');
        }
        if (i < _warmups) continue;
        samples.add(ms);
        if (ms >= HeavyProbeVerdict.earlyExitMs) break;
      }
      final verdict =
          HeavyProbeVerdict.fromSamples(samples, appVersion: appVersion);
      debugPrint('[HeavyProbe] $verdict — load ${loadMs}ms, '
          'total ${sw.elapsedMilliseconds}ms');
      return verdict;
    } catch (e) {
      if (_cancelled) return null;
      final wedged = e is TimeoutException;
      debugPrint('[HeavyProbe] ${wedged ? 'wedged' : 'failed'} after '
          '${sw.elapsedMilliseconds}ms: $e');
      return HeavyProbeVerdict.notCapable(appVersion,
          reason: '$e', wedged: wedged);
    }
  }
}
