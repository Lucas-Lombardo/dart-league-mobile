import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

import '../utils/storage_service.dart';

/// Two-model speed/accuracy ladder, ported from DartsMind
/// (Detector.changeAIModelIfNeed + DVSpeedChecker persistence).
///
/// - Default is the SMALL model (t225 — DartsMind's MODEL_SMALLER strategy).
/// - The mean of the last [windowSize] real inference times decides switches:
///   small → big when the mean is ≤ [upgradeAtMs] (device can afford accuracy),
///   big → small when the mean is > [downgradeAtMs] (device can't keep up /
///   is cooking). The 261–500ms band is a dead zone that prevents flapping.
/// - The small-model speed profile is persisted with a best-ever ratchet
///   (like DartsMind's checkInferenceAvgTime_t201) so the next session starts
///   on the right model immediately.
///
/// Divergence from DartsMind, on purpose: UPGRADES are deferred to the next
/// model load (match start / setup screen) instead of applied mid-match —
/// on iOS a model rebuild re-runs the multi-second CoreML delegate
/// compilation, which would freeze the AI mid-turn. DOWNGRADES are immediate
/// on Android only (file-based reload, fast): on iOS they are deferred too,
/// because the downgrade fires precisely when the device is hot/throttled —
/// the moment a CoreML recompile is slowest and most likely to blow the load
/// timeout, cascading into an engine rebuild and a CPU-only session. The
/// thermal throttle (AutoScoringService) protects a struggling iPhone until
/// the next match load applies the switch.
///
/// Times fed in are the native-measured PURE invoke cost when available
/// (see NativeInference.lastNativeInferMs) — the same measure DartsMind's
/// 260/500ms cut-offs were tuned for. The end-to-end fallback (preprocess +
/// channel + parse) sits well above it and made downgrades fire too early.
class ModelSelector {
  ModelSelector._();

  static const String smallModelAsset = 'assets/models/t225.tflite';
  static const String bigModelAsset = 'assets/models/t223.tflite';
  static const int upgradeAtMs = 260; // DartsMind: ≤260 → MODEL_BETTER
  static const int downgradeAtMs = 500; // DartsMind: >500 → MODEL_SMALLER
  static const int windowSize = 16; // DartsMind: inferenceTimeArray >= 16

  static String _currentAsset = smallModelAsset;
  static String? _runningAsset;
  static bool _initialized = false;
  static bool _switchPending = false;
  static final List<int> _window = <int>[];

  /// The asset every loader should use for its next load.
  static String get currentAsset => _currentAsset;

  /// Model name without path/extension (what the iOS plugin expects).
  static String get currentModelName =>
      _currentAsset.split('/').last.replaceAll('.tflite', '');

  /// Resolve the initial model from the persisted device profile.
  /// Idempotent; cheap after the first call.
  static Future<void> ensureInitialized() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final profileMs = await StorageService.getAiSmallModelAvgMs();
      if (profileMs != null && profileMs <= upgradeAtMs) {
        _currentAsset = bigModelAsset;
      }
      debugPrint('[ModelSelector] profile=${profileMs}ms → '
          'start on $currentModelName');
    } catch (e) {
      debugPrint('[ModelSelector] profile read failed ($e) — '
          'starting on $currentModelName');
    }
  }

  /// Tell the selector which model a loader actually has running.
  static void markLoaded(String asset) {
    _runningAsset = asset;
    _window.clear();
    _switchPending = false;
  }

  /// Feed one per-frame cost. Every [windowSize] samples, re-evaluate the
  /// ladder (DartsMind evaluates on the same cadence, forever).
  static void recordInferenceMs(int ms) {
    if (_runningAsset == null) return;
    _window.add(ms);
    if (_window.length < windowSize) return;
    final mean = _window.reduce((a, b) => a + b) ~/ _window.length;
    _window.clear();

    if (_runningAsset == smallModelAsset) {
      _persistSmallProfile(mean);
      if (mean <= upgradeAtMs && _currentAsset != bigModelAsset) {
        // Deferred: takes effect on the next loadModel (see class comment).
        _currentAsset = bigModelAsset;
        debugPrint('[ModelSelector] small mean=${mean}ms ≤ $upgradeAtMs — '
            'next load upgrades to $currentModelName');
      }
    } else if (_runningAsset == bigModelAsset && mean > downgradeAtMs) {
      _currentAsset = smallModelAsset;
      if (!kIsWeb && Platform.isAndroid) {
        _switchPending = true;
        debugPrint('[ModelSelector] big mean=${mean}ms > $downgradeAtMs — '
            'downgrading to $currentModelName now');
      } else {
        // iOS: deferred like upgrades (see class comment) — a mid-match
        // switch means a CoreML recompile on an already-throttled device.
        debugPrint('[ModelSelector] big mean=${mean}ms > $downgradeAtMs — '
            'next load downgrades to $currentModelName');
      }
    }
  }

  /// True once when an immediate (downgrade) switch is due. The caller
  /// reloads the model, which calls [markLoaded] and clears the flag.
  static bool takePendingSwitch() {
    if (!_switchPending) return false;
    _switchPending = false;
    return true;
  }

  /// Best-ever ratchet, like DartsMind: only overwrite with a faster time,
  /// so one hot/throttled session can't permanently lock out the big model.
  static Future<void> _persistSmallProfile(int mean) async {
    try {
      final stored = await StorageService.getAiSmallModelAvgMs();
      if (stored == null || mean < stored) {
        await StorageService.saveAiSmallModelAvgMs(mean);
      }
    } catch (e) {
      debugPrint('[ModelSelector] profile write failed: $e');
    }
  }
}
