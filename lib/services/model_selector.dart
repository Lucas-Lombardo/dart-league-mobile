import 'dart:async';
import 'dart:math';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../utils/storage_service.dart';
import 'detection_parsing.dart';
import 'heavy_capability_probe.dart';

/// One bundled AI scorer model: the asset to load and the output contract to
/// parse it with.
///
/// [key] is the wire name, shared with the backend (AI_MODEL_KEYS) in both
/// directions — it is what the admin's rollout names and what the telemetry
/// reports back. Renaming one detaches the stats already collected under the
/// old name, so keys are added, never renamed.
///
/// [layout] is per-model and NOT guessable from the tensor: class order and
/// box units are invisible in the output, and pairing a model with the wrong
/// layout raises no error anywhere — darts get read as calibration points and
/// the homography silently goes absurd. It belongs next to the asset for
/// exactly that reason.
class AiModel {
  const AiModel({
    required this.key,
    required this.asset,
    required this.layout,
    this.iosDelegate = 'auto',
  });

  final String key;
  final String asset;
  final DetectionLayout layout;

  /// iOS delegate to pin for THIS model ('auto' | 'cpu' | 'xnnpack' |
  /// 'metal' | 'coreml'). Per-model for the same reason [layout] is: the
  /// winning delegate is a property of the GRAPH, not of the app, and the
  /// bundled graphs do not agree. Measured on the v10 float16 o2o export —
  /// the closest relative of [v13] — iPhone xnnpack 106ms vs coreml 297ms,
  /// while the DartsMind anchor models go the other way (light: coreml 56ms
  /// vs xnnpack 133ms). One global constant would therefore hand one of the
  /// two a 3x penalty and make the rollout's own telemetry blame the model.
  ///
  /// 'auto' = the plugin's CoreML -> Metal -> CPU cascade, the historical
  /// behaviour. Fill a real value in from lib/dev/delegate_bench.dart; never
  /// predict one.
  final String iosDelegate;

  /// Model name without path/extension (what the iOS plugin expects).
  String get modelName => asset.split('/').last.replaceAll('.tflite', '');
}

/// The AI scorer's model configuration: ONE model per device per app run,
/// resolved once by [init] at startup — no mid-match switching.
///
/// Which model that is comes from two places, in order:
///  1. the admin's remote rollout, if this install drew into it and carries
///     the model it names ([applyRemoteConfig]);
///  2. otherwise the device probe below — heavy on capable phones, v13 on
///     weak/unknown ones — which is what it falls back to whenever anything
///     is off. (Until 2026-09-06 the weak-phone pick was DartsMind light,
///     since retired: v13 is cheaper on every compute path measured, and
///     the rollout had already put it on every install.)
///
/// "Capable" is decided differently per platform. iOS: the chip generation
/// (A14 and up), a reliable proxy because heavy runs on the Neural Engine
/// there. Android: MEASURED — RAM only says whether heavy is worth trying,
/// and phones that clear it still span a 10x range on the GPU that actually
/// runs the graph (a 7.6 GB Redmi 13C: 826 ms a frame). See
/// [HeavyCapabilityProbe]; until its verdict is in, the phone is v13.
class ModelSelector {
  ModelSelector._();

  /// DartsMind heavy model (12.8 MB), the same architecture scaled up — more
  /// accurate, ~3x the weights. NOT benched per device: the capability
  /// thresholds below are heuristics, not measurements.
  static const heavy = AiModel(
    key: 'heavy',
    asset: 'assets/models/dart-rival-ia-heavy.tflite',
    layout: DetectionLayout.anchorDartLast,
  );

  /// Dart Rivals v13 (5.0 MB, quantized o2o export). Same anchor tensor as
  /// [heavy] ([1, 13, 21504]) and the same float32 in/out, but the OTHER
  /// conventions on both axes the tensor cannot reveal: dart at class 0, boxes
  /// in canvas pixels — read off the file, 2026-08-28, and matching the v10
  /// o2o export.
  ///
  /// The pick whenever the device is weak, unknown, or the probe fails: the
  /// cheapest model the app has shipped, 59ms on the same frame and CPU
  /// against heavy's 208ms and the retired light's 68ms (Mac, xnnpack, 4
  /// threads, 2026-08-28). It also found the board on 304/304 frames of a
  /// real leg, with its weakest kept control point at 0.86 against the 0.80
  /// floor — quantization costs a few points of confidence, and none of it
  /// came near the edge.
  ///
  /// Those are RATIOS, not phone numbers: the delegate ranking is a property
  /// of the graph and has flipped between models before, so the numbers that
  /// decide anything are the ones the rollout collects from real devices.
  ///
  /// [iosDelegate] is PINNED to xnnpack, measured 2026-08-28 on iPhone de
  /// Lucas (thermal=1 throughout): xnnpack median 112ms / load 27ms against
  /// CoreML 312ms / load 2611ms — 2.8x, the same verdict the v10 float16 o2o
  /// export got, and the reason this field is per-model at all. The two
  /// delegates AGREE numerically (identical scores 9/9 frames, mean tip
  /// distance 0.0px, worst class-confidence delta 0.0071), so this is a pure
  /// speed choice with no accuracy cost.
  ///
  /// The same run's layout probe independently confirmed the class order and
  /// box units: dart=first + canvasPixels yields p1..p8 once each with tip=3
  /// on a 3-dart frame, while dart=last yields p1 twice with tip=1.
  static const v13 = AiModel(
    key: 'v13',
    asset: 'assets/models/dart-rivals-v13.tflite',
    layout: DetectionLayout.anchorPixelsDartFirst,
    iosDelegate: 'xnnpack',
  );

  /// Every model this build carries. A remote choice naming anything else is
  /// ignored — that is what lets the backend switch on a model before every
  /// install has shipped with it.
  static const List<AiModel> all = [heavy, v13];

  static AiModel? byKey(String? key) {
    for (final model in all) {
      if (model.key == key) return model;
    }
    return null;
  }

  /// The model this app run uses. Stays [v13] until [init] resolves — every
  /// load path sits behind user navigation (camera setup, match start), so in
  /// practice the probe from main() has long finished.
  static AiModel get current => _current;
  static AiModel _current = v13;

  static String get currentAsset => _current.asset;
  static String get currentModelName => _current.modelName;
  static String get currentModelKey => _current.key;
  static DetectionLayout get currentLayout => _current.layout;
  static String get currentIosDelegate => _current.iosDelegate;

  /// What the device probe alone would pick, ignoring any rollout — the
  /// fallback for every install the rollout does not reach.
  static AiModel _deviceModel = v13;

  /// Whether this phone clears the heavy-model bar. The rollout can be
  /// restricted to capable devices, and the backend never sees the probe, so
  /// that filter has to be applied here.
  static bool _capable = false;

  /// The rollout as last told (from storage at startup, from the wire
  /// after), kept so the choice can be re-made when the device verdict
  /// arrives late — the Android probe lands seconds after [init].
  static String? _rolloutModel;
  static int _rolloutPercent = 100;
  static bool _rolloutCapableOnly = false;

  /// The Android heavy measurement in flight, if any. Null once it has
  /// reported, on iOS, and on phones the RAM floor already ruled out.
  static HeavyCapabilityProbe? _probe;
  static Future<void>? _probeDone;

  static bool _initialized = false;

  /// Set once a model has actually been handed to an interpreter. After that
  /// a remote change is persisted for the NEXT launch but not applied: the
  /// parser's layout and the loaded weights must not disagree, and a model
  /// swap mid-session would do exactly that.
  static bool _loaded = false;

  /// Set by [debugForceModel]. Nothing may overwrite a forced choice — not
  /// [init] finishing its storage reads, not a rollout arriving from the
  /// network. Both of those land SECONDS after main() starts (the secure
  /// storage read alone took 4.6s on a cold Redmi 13C), which is long after
  /// the bench has forced its model and begun measuring: the 2026-08-28
  /// Android run measured v13 on the GPU and then heavy on the CPU, and
  /// reported both as v13.
  static bool _forced = false;

  static void markModelLoaded() => _loaded = true;

  /// This install's stable draw for percentage rollouts, 0-99. Drawn once and
  /// kept, so a player does not flip between models from launch to launch —
  /// which would make every per-model number a mix of both.
  static int _bucket = 0;

  /// Android floor for even TRYING the heavy model, in MB of physical RAM —
  /// meant as "nominal 6 GB and up". physicalRamSize lands under the
  /// marketing number (a "6 GB" phone reports ~5.6–5.9k MB), hence 5500
  /// rather than 6144. Below it the phone is v13 without a measurement: a
  /// 4 GB phone should not load a 12.8 MB model to learn it is slow. Above
  /// it the measurement decides — RAM does not (see [HeavyCapabilityProbe]).
  static const int _androidHeavyRamMb = 5500;

  /// How long a real model load waits for an in-flight probe before
  /// cancelling it. Far above a normal probe (a load plus four inferences,
  /// under 5 s even on the Redmi) and under the load's own 30 s bound, so a
  /// wedged probe costs the camera screen one wait, not two.
  static const Duration _probeWait = Duration(seconds: 20);

  /// Probe the device, then apply whatever rollout the last launch saw.
  /// Called from main() before anything can loadModel; later calls are
  /// no-ops. A failed probe or an unrecognized device keeps [v13] — safe on
  /// every phone.
  static Future<void> init() async {
    if (_initialized || kIsWeb) return;
    _initialized = true;
    try {
      final plugin = DeviceInfoPlugin();
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
          final info = await plugin.androidInfo;
          final ramOk = !info.isLowRamDevice &&
              info.physicalRamSize >= _androidHeavyRamMb;
          debugPrint('[ModelSelector] android ram=${info.physicalRamSize}MB '
              'lowRam=${info.isLowRamDevice} ramOk=$ramOk');
          _capable = ramOk && await _androidHeavyVerdict();
          break;
        case TargetPlatform.iOS:
          final machine = (await plugin.iosInfo).utsname.machine;
          _capable = _iosHeavyCapable(machine);
          debugPrint('[ModelSelector] ios machine=$machine capable=$_capable');
          break;
        default:
          _capable = false; // Desktop dev builds keep v13.
          break;
      }
    } catch (e) {
      _capable = false;
      debugPrint('[ModelSelector] device probe failed ($e)');
    }
    _deviceModel = _capable ? heavy : v13;

    // The rollout the last launch was told about, replayed before the first
    // frame. Reading it from storage rather than waiting on the network is
    // the point: /app/version-config only lands once the home screen asks,
    // which is after the camera setup screen can already have loaded a model.
    try {
      _bucket = await _readBucket();
      _rolloutModel = await StorageService.getAiModelChoice();
      _rolloutPercent = await StorageService.getAiModelRolloutPercent();
      _rolloutCapableOnly = await StorageService.getAiModelCapableOnly();
      final resolved =
          _resolve(_rolloutModel, _rolloutPercent, _rolloutCapableOnly);
      // The awaits above can outlast a debugForceModel that landed while they
      // were in flight; _initialized alone does not protect it, because this
      // call is already PAST that guard.
      if (!_forced) _current = resolved;
    } catch (e) {
      // flutter_secure_storage throws on a corrupted Android keystore. The
      // device probe already ran, so fall back to it rather than to v13.
      if (!_forced) _current = _deviceModel;
      debugPrint('[ModelSelector] stored rollout unreadable ($e)');
    }
    debugPrint('[ModelSelector] using $currentModelKey ($currentModelName)');
  }

  /// Android: the stored heavy verdict if it still holds, else start
  /// measuring in the background and answer "not capable" for now. The
  /// phone runs v13 until the measurement says otherwise — for this launch
  /// if it lands before the first model load, for the next one after.
  static Future<bool> _androidHeavyVerdict() async {
    final appVersion = await _appVersion();
    HeavyProbeVerdict? stored;
    try {
      stored = HeavyProbeVerdict.decode(await StorageService.getAiHeavyProbe());
    } catch (e) {
      debugPrint('[ModelSelector] stored heavy verdict unreadable ($e)');
    }
    if (stored != null && stored.isValidFor(appVersion)) {
      debugPrint('[ModelSelector] heavy verdict from storage: $stored');
      return stored.capable;
    }
    final probe = HeavyCapabilityProbe();
    _probe = probe;
    _probeDone = probe
        .run(modelAsset: heavy.asset, appVersion: appVersion)
        .then(_applyHeavyVerdict)
        .catchError((Object e) {
          debugPrint('[ModelSelector] heavy probe crashed ($e)');
        })
        .whenComplete(() {
          if (identical(_probe, probe)) {
            _probe = null;
            _probeDone = null;
          }
        });
    return false;
  }

  /// The probe's verdict: persist it, then adopt it now if nothing has
  /// loaded a model yet — the same freeze rule as a rollout arriving from
  /// the wire. Null (cancelled) changes nothing and stores nothing.
  static Future<void> _applyHeavyVerdict(HeavyProbeVerdict? verdict) async {
    if (verdict == null) return;
    try {
      await StorageService.saveAiHeavyProbe(verdict.encode());
    } catch (e) {
      debugPrint('[ModelSelector] heavy verdict not persisted ($e)');
    }
    _capable = verdict.capable;
    _deviceModel = _capable ? heavy : v13;
    if (_loaded || _forced) return;
    final resolved =
        _resolve(_rolloutModel, _rolloutPercent, _rolloutCapableOnly);
    if (resolved.key == _current.key) return;
    _current = resolved;
    debugPrint('[ModelSelector] heavy verdict applied -> $currentModelKey');
  }

  /// Block a real model load until the Android measurement has reported,
  /// bounded by [_probeWait]. Past the bound the probe is cancelled — its
  /// verdict would be taken on whatever model the load swaps in — and the
  /// phone keeps v13 for this run. No-op everywhere else.
  static Future<void> waitForHeavyProbe() async {
    final pending = _probeDone;
    if (pending == null) return;
    try {
      await pending.timeout(_probeWait);
    } on TimeoutException {
      debugPrint('[ModelSelector] heavy probe still running after '
          '${_probeWait.inSeconds}s — cancelled, v13 for this run');
      _probe?.cancel();
    }
  }

  static Future<String> _appVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return '${info.version}+${info.buildNumber}';
    } catch (e) {
      debugPrint('[ModelSelector] app version unavailable ($e)');
      return 'unknown';
    }
  }

  /// Apply the rollout carried by /app/version-config: persist it for the next
  /// launch, and adopt it now if no model has been loaded yet.
  ///
  /// Deliberately tolerant. A model key this build does not carry, a percent
  /// the install did not draw into, a capability filter it fails — all resolve
  /// to the device probe. The worst outcome of any bad or unknown value is
  /// that the phone keeps running the model it would have run anyway.
  static Future<void> applyRemoteConfig({
    required String? model,
    required int rolloutPercent,
    required bool capableOnly,
  }) async {
    try {
      await StorageService.saveAiModelRollout(
        model: model,
        percent: rolloutPercent,
        capableOnly: capableOnly,
      );
    } catch (e) {
      debugPrint('[ModelSelector] rollout not persisted ($e)');
    }
    _rolloutModel = model;
    _rolloutPercent = rolloutPercent;
    _rolloutCapableOnly = capableOnly;
    // Never swap the weights under a live interpreter, and never override a
    // bench that asked for a specific model.
    if (_loaded || _forced) return;
    final resolved = _resolve(model, rolloutPercent, capableOnly);
    if (resolved.key == _current.key) return;
    _current = resolved;
    debugPrint('[ModelSelector] rollout applied -> $currentModelKey');
  }

  /// The rollout's verdict for THIS install. Pure, so it is testable and so
  /// the same rule runs at startup (from storage) and on the wire.
  static AiModel _resolve(String? model, int rolloutPercent, bool capableOnly) {
    final override = byKey(model);
    if (override == null) return _deviceModel; // 'auto', unknown, or absent
    if (capableOnly && !_capable) return _deviceModel;
    if (_bucket >= rolloutPercent.clamp(0, 100)) return _deviceModel;
    return override;
  }

  /// The install's rollout draw, minted on first use and never re-drawn.
  static Future<int> _readBucket() async {
    final stored = await StorageService.getAiRolloutBucket();
    if (stored != null && stored >= 0 && stored < 100) return stored;
    final drawn = Random().nextInt(100);
    await StorageService.saveAiRolloutBucket(drawn);
    return drawn;
  }

  /// iOS tiering off the hardware identifier ("iPhone14,2"): the major
  /// number tracks the chip generation, and 13 is the A14 line (iPhone 12 /
  /// iPad Air 4, 2020) — that generation and up takes the heavy model.
  /// Simulators report the host arch and count as capable. RAM is no proxy
  /// here: device_info_plus 13.x doesn't expose it on iOS, and the chip tier
  /// predicts inference speed better anyway.
  static bool _iosHeavyCapable(String machine) {
    if (machine == 'arm64' || machine == 'x86_64') return true; // simulator
    final m = RegExp(r'^(?:iPhone|iPad)(\d+),').firstMatch(machine);
    return m != null && int.parse(m.group(1)!) >= 13;
  }

  /// DEV ONLY — force a model for this app run, bypassing both the probe and
  /// the rollout. The delegate bench is the only caller: it has to measure a
  /// model the device would not otherwise select, and it runs behind its own
  /// DELEGATE_BENCH build flag. Returns false for a key this build lacks.
  ///
  /// Must run BEFORE any loadModel — after that the weights are already in an
  /// interpreter and only the parse layout would move.
  static bool debugForceModel(String key) {
    final model = byKey(key);
    if (model == null) return false;
    // A probe still measuring would share the native thread with the
    // bench and time whichever model was loaded last.
    _probe?.cancel();
    _current = model;
    _initialized = true;
    _forced = true;
    debugPrint('[ModelSelector] FORCED to $key (dev build)');
    return true;
  }

  /// Test seam: re-run [init]'s decision with a known device verdict and
  /// rollout draw, without touching device_info_plus or secure storage.
  @visibleForTesting
  /// Undo [debugForceModel] — tests only, so one case cannot leak into the
  /// next through the static.
  @visibleForTesting
  static void debugClearForce() => _forced = false;

  static AiModel debugResolve({
    required bool capable,
    required int bucket,
    required String? model,
    required int rolloutPercent,
    required bool capableOnly,
  }) {
    final savedCapable = _capable;
    final savedBucket = _bucket;
    final savedDevice = _deviceModel;
    _capable = capable;
    _bucket = bucket;
    _deviceModel = capable ? heavy : v13;
    final resolved = _resolve(model, rolloutPercent, capableOnly);
    _capable = savedCapable;
    _bucket = savedBucket;
    _deviceModel = savedDevice;
    return resolved;
  }
}
