import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import '../services/dart_detection_service.dart';
import '../services/model_selector.dart';

/// On-device TFLite delegate bench (iOS + Android) — dev tool, never part
/// of the app. 2026-08-10 results, dart-rival-ia-light: iPhone de Lucas
/// coreml 56ms vs xnnpack 133ms (71 vs 215 at thermal=2), 9/9 identical
/// scores; Pixel 8 gpu 54ms (self-test 9/9 OK) vs forced-cpu 426ms, 8/8
/// identical scores; Galaxy S21 Ultra (Adreno 660) gpu 57ms (self-test 9/9
/// OK) vs forced-cpu 643ms median / 1098ms max — the CPU block alone pushed
/// thermal 1→2. A silent GPU→CPU fallback costs 8-11× and is invisible
/// today: surfacing the effective delegate in telemetry is the follow-up.
///
/// Launched with:
///   flutter run --profile --dart-define=DELEGATE_BENCH=true
/// after UNCOMMENTING the assets/dev_bench entries in pubspec.yaml (they
/// stay commented so the ~2.3 MB never ships in a real build; the bench
/// aborts loudly when they're missing).
///
/// Why it exists: NativeInference.iosDelegate pinned 'xnnpack' on the
/// strength of a 2026-08-09 bench made on the (since removed) v7/YOLO26
/// graph. The delegate ranking is a property of the graph, so the current
/// model (dart-rival-ia-light) needs its own numbers (thermal audit
/// 2026-08-10 — at equal speed the Neural Engine heats far less than 4 CPU
/// threads at ~90% duty).
///
/// Two phases, all in ONE app launch (the plugin rebuilds the interpreter
/// whenever the `delegate` override changes — see NativeInferencePlugin.swift
/// loadModel):
///  A. SPEED — timed invokes on a real 720p frame; `inferenceMs` is the
///     native pure-invoke time. 2026-08-10 result: coreml ~56ms median vs
///     xnnpack ~133ms.
///  B. ACCURACY — the same REAL match frames (assets/dev_bench, dumped by
///     DebugFrameDumpService on 2026-08-09) analyzed under each delegate,
///     then parsed with the app's own pipeline; the report compares control
///     points, tip positions and dart scores between delegates. This is the
///     measured stand-in for "throw darts at a real board and look".
///
/// 'metal' is deliberately absent: its delegate build dropped the device
/// connection on the 2026-08-10 run, and it was already beaten (~980ms on
/// the old graph, slower than both candidates here).
class DelegateBench {
  DelegateBench._();

  // Dart-side prints never reach the devicectl console (only native NSLog
  // does), and flutter run's VM-service attach was flaky on this device —
  // so the report is also written to Documents/delegate_bench_report.txt
  // and pulled over USB:
  //   xcrun devicectl device copy from --device <udid> \
  //     --domain-type appDataContainer \
  //     --domain-identifier com.llombardo.dartrivals \
  //     --source Documents/delegate_bench_report.txt --destination out.txt
  static final List<String> _report = [];

  static void _log(String line) {
    debugPrint('[DelegateBench] $line');
    _report.add(line);
  }

  static Future<void> _writeReport() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/delegate_bench_report.txt');
      await file.writeAsString('${_report.join('\n')}\n', flush: true);
    } catch (e) {
      debugPrint('[DelegateBench] report write failed: $e');
    }
  }

  static const _channel = MethodChannel('com.dartrivals/native_inference');

  /// iOS: real delegate overrides of the plugin's loadModel. Android: the
  /// plugin has no delegate arg — 'gpu-auto' is the normal load (GPU with
  /// the check_inference self-test, silent CPU fallback), 'cpu-forced'
  /// rides rebuildEngine's forceCpuOnce so the next load builds CPU-only
  /// (4 threads) — measuring exactly what a silent fallback would cost.
  /// Which delegate the GPU load actually retained is only visible in
  /// logcat (tag NativeInference: self-test verdict / delegate build).
  static final List<String> _delegates = Platform.isAndroid
      ? ['gpu-auto', 'cpu-forced']
      : ['xnnpack', 'coreml'];
  static const _warmups = 3;
  static const _samples = 10;

  static const _realFrames = [
    'assets/dev_bench/f000039.jpg', // 0 darts
    'assets/dev_bench/f000091.jpg', // 0 darts
    'assets/dev_bench/f000141.jpg', // 1 dart
    'assets/dev_bench/f000147.jpg', // 1 dart
    'assets/dev_bench/f000168.jpg', // 2 darts
    'assets/dev_bench/f000213.jpg', // 2 darts
    'assets/dev_bench/f000234.jpg', // 3 darts
    'assets/dev_bench/f000283.jpg', // 3 darts
    'assets/models/check_inference.jpg', // Android self-test reference shot
  ];

  static Future<void> run() async {
    // Let the engine/plugins finish booting; the app keeps starting normally.
    await Future.delayed(const Duration(seconds: 2));
    _report.clear();
    _log('===== START ===== '
        'model=${ModelSelector.currentModelName} delegates=$_delegates');

    final speedSummaries = <String>[];
    final results = <String, List<ScoringResult?>>{};
    final decoded = await _decodeRealFrames();
    // Fail LOUDLY on a partial bundle instead of producing an
    // authoritative-looking verdict over 1-2 frames: the dev_bench assets
    // ship commented out in pubspec.yaml (so they never reach a real build)
    // and MUST be uncommented for a bench build.
    if (decoded.length < _realFrames.length) {
      _log('ABORT: only ${decoded.length}/${_realFrames.length} bench frames '
          'bundled — uncomment the assets/dev_bench entries in pubspec.yaml '
          'and rebuild.');
      await _writeReport();
      return;
    }

    // Speed frame: a REAL portrait frame — Android's RGBA analyze path
    // overruns on landscape inputs (index just past 1024×768×4, latent bug
    // in that near-dead path; the game rides analyzeYuv), which killed a
    // synthetic 1280×720 landscape frame on the Pixel 8 run. Timing is
    // data-independent, so a real frame measures the same thing.
    final first = decoded.first;
    final speedFrame = (rgba: first.rgba, w: first.w, h: first.h);

    for (final delegate in _delegates) {
      final line = await _benchSpeed(delegate, speedFrame);
      speedSummaries.add(line);
      // Accuracy pass rides the same load as the speed pass — the delegate
      // is still the loaded one here.
      results[delegate] = await _analyzeRealFrames(delegate, decoded);
      // Partial write after each delegate: a crash mid-bench still leaves
      // the completed blocks readable.
      await _writeReport();
      await Future.delayed(const Duration(seconds: 2));
    }

    _log('===== SPEED =====');
    for (final line in speedSummaries) {
      _log(line);
    }
    _log('===== ACCURACY =====');
    _compare(decoded, results[_delegates[0]]!, results[_delegates[1]]!);
    _log('===== DONE =====');
    await _writeReport();
  }

  // ---- Phase A: speed on a real frame --------------------------------------

  static Future<String> _benchSpeed(
      String delegate, ({Uint8List rgba, int w, int h}) frame) async {
    final thermalBefore = await _thermal();
    _log('--- $delegate (thermal=$thermalBefore) ---');

    final loadSw = Stopwatch()..start();
    try {
      final ok = await _loadDelegate(delegate);
      if (ok != true) return '$delegate: LOAD FAILED (returned $ok)';
    } catch (e) {
      return '$delegate: LOAD FAILED ($e)';
    }
    final loadMs = loadSw.elapsedMilliseconds;

    final times = <int>[];
    for (var i = 0; i < _warmups + _samples; i++) {
      try {
        final response = await _channel.invokeMethod<Map>('analyze', {
          'rgba': frame.rgba,
          'width': frame.w,
          'height': frame.h,
          'isBgra': false,
        }).timeout(const Duration(seconds: 30));
        final ms = (response?['inferenceMs'] as num?)?.toInt();
        if (ms == null) return '$delegate: analyze returned no inferenceMs';
        if (i >= _warmups) times.add(ms);
      } catch (e) {
        return '$delegate: analyze #$i FAILED ($e)';
      }
    }

    times.sort();
    final median = times[times.length ~/ 2];
    final mean = times.reduce((a, b) => a + b) / times.length;
    final thermalAfter = await _thermal();
    return '$delegate: median=${median}ms mean=${mean.toStringAsFixed(0)}ms '
        'min=${times.first}ms max=${times.last}ms load=${loadMs}ms '
        'thermal $thermalBefore→$thermalAfter';
  }

  /// Platform-specific model load for [delegate] (see [_delegates]).
  static Future<Object?> _loadDelegate(String delegate) async {
    if (!Platform.isAndroid) {
      // CoreML compiles the graph on first build — give it room.
      return _channel.invokeMethod('loadModel', {
        'modelName': ModelSelector.currentModelName,
        'delegate': delegate,
      }).timeout(const Duration(seconds: 120));
    }
    if (delegate == 'cpu-forced') {
      // forceCpuOnce: the NEXT load builds CPU-only (and drops the
      // "already loaded — reusing" shortcut).
      await _channel
          .invokeMethod('rebuildEngine')
          .timeout(const Duration(seconds: 5));
    }
    // Same extraction as NativeInference.loadModel, but ALWAYS rewritten —
    // the app's existsSync shortcut can serve a stale temp file.
    final asset = ModelSelector.currentAsset;
    final modelData = await rootBundle.load(asset);
    final tempDir = await getTemporaryDirectory();
    final modelFile = File('${tempDir.path}/${asset.split('/').last}');
    await modelFile.writeAsBytes(modelData.buffer.asUint8List(), flush: true);
    return _channel
        .invokeMethod('loadModelFile', modelFile.path)
        .timeout(const Duration(seconds: 120));
  }

  // ---- Phase B: accuracy on real match frames ------------------------------

  static Future<List<({String name, Uint8List rgba, int w, int h})>>
      _decodeRealFrames() async {
    final out = <({String name, Uint8List rgba, int w, int h})>[];
    for (final asset in _realFrames) {
      try {
        final bytes = await rootBundle.load(asset);
        final im = img.decodeJpg(bytes.buffer.asUint8List());
        if (im == null) {
          _log('$asset: decode failed, skipped');
          continue;
        }
        out.add((
          name: asset.split('/').last,
          rgba: im.getBytes(order: img.ChannelOrder.rgba),
          w: im.width,
          h: im.height,
        ));
      } catch (e) {
        _log('$asset: $e — skipped');
      }
    }
    _log('decoded ${out.length}/${_realFrames.length} real frames');
    return out;
  }

  static Future<List<ScoringResult?>> _analyzeRealFrames(
    String delegate,
    List<({String name, Uint8List rgba, int w, int h})> frames,
  ) async {
    // Fresh parser per delegate: its last-good-calibration cache must not
    // leak one delegate's calibration into the other's scoring.
    final parser = DartDetectionService(useNativeDecode: false);
    final out = <ScoringResult?>[];
    for (final f in frames) {
      try {
        final response = await _channel.invokeMethod<Map>('analyze', {
          'rgba': f.rgba,
          'width': f.w,
          'height': f.h,
          'isBgra': false,
        }).timeout(const Duration(seconds: 30));
        final outputBytes = response!['output'] as Uint8List;
        final aligned = Uint8List.fromList(outputBytes);
        out.add(parser.parseRawOutput(
          aligned.buffer.asFloat32List(),
          (response['xScale'] as num).toDouble(),
          (response['yScale'] as num).toDouble(),
          response['imageWidth'] as int,
          response['imageHeight'] as int,
        ));
      } catch (e) {
        _log('$delegate ${f.name}: analyze failed ($e)');
        out.add(null);
      }
    }
    parser.dispose();
    return out;
  }

  static void _compare(
    List<({String name, Uint8List rgba, int w, int h})> frames,
    List<ScoringResult?> a,
    List<ScoringResult?> b,
  ) {
    var identicalScores = 0;
    var comparable = 0;
    final tipDistances = <double>[];
    for (var i = 0; i < frames.length; i++) {
      final ra = a[i];
      final rb = b[i];
      final name = frames[i].name;
      if (ra == null || rb == null) {
        _log('$name: INCOMPARABLE (analyze failed)');
        continue;
      }
      comparable++;
      final calA = _classes(ra.calibrationPoints);
      final calB = _classes(rb.calibrationPoints);
      final calDist = _meanDistancePx(
          ra.calibrationPoints, rb.calibrationPoints, frames[i].w, frames[i].h);
      final tipDist = _meanDistancePx(
          ra.dartTips, rb.dartTips, frames[i].w, frames[i].h);
      if (tipDist != null) tipDistances.add(tipDist);
      final scoresA = ra.scores.map((s) => s.formatted).join(',');
      final scoresB = rb.scores.map((s) => s.formatted).join(',');
      final sameScores = scoresA == scoresB &&
          ra.dartTips.length == rb.dartTips.length &&
          ra.totalScore == rb.totalScore;
      if (sameScores) identicalScores++;
      _log('$name: '
          '${sameScores ? "MATCH" : "DIFF"} | '
          'cal ${_delegates[0]}=$calA ${_delegates[1]}=$calB '
          'dist=${calDist?.toStringAsFixed(1) ?? "n/a"}px | '
          'tips ${ra.dartTips.length}vs${rb.dartTips.length} '
          'dist=${tipDist?.toStringAsFixed(1) ?? "n/a"}px | '
          'scores [$scoresA] vs [$scoresB] '
          '(total ${ra.totalScore} vs ${rb.totalScore})');
    }
    final meanTipDist = tipDistances.isEmpty
        ? 'n/a'
        : (tipDistances.reduce((x, y) => x + y) / tipDistances.length)
            .toStringAsFixed(1);
    _log('VERDICT: identical scores on '
        '$identicalScores/$comparable frames, mean tip distance '
        '${meanTipDist}px');
  }

  static String _classes(List<Detection> dets) {
    final names = dets.map((d) => d.className).toList()..sort();
    return names.join('+');
  }

  /// Mean distance (px) between same-class detections of the two results;
  /// null when nothing matches. Tips (all same class) pair greedily by
  /// nearest neighbour.
  static double? _meanDistancePx(
      List<Detection> a, List<Detection> b, int w, int h) {
    if (a.isEmpty || b.isEmpty) return null;
    final remaining = List<Detection>.of(b);
    final dists = <double>[];
    for (final da in a) {
      Detection? best;
      var bestDist = double.infinity;
      for (final db in remaining) {
        if (db.className != da.className) continue;
        final dx = (da.x - db.x) * w;
        final dy = (da.y - db.y) * h;
        final d = sqrt(dx * dx + dy * dy);
        if (d < bestDist) {
          bestDist = d;
          best = db;
        }
      }
      if (best != null) {
        remaining.remove(best);
        dists.add(bestDist);
      }
    }
    if (dists.isEmpty) return null;
    return dists.reduce((x, y) => x + y) / dists.length;
  }

  /// Raw ProcessInfo.thermalState (0 nominal … 3 critical); -1 on failure.
  static Future<int> _thermal() async {
    try {
      final raw = await _channel
          .invokeMethod<int>('thermalStatus')
          .timeout(const Duration(seconds: 2));
      return raw ?? -1;
    } catch (_) {
      return -1;
    }
  }
}
