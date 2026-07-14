import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'dart_detection_service_stub.dart'
    if (dart.library.io) 'dart_detection_service.dart';
import 'model_selector.dart';

/// Wraps the native iOS/Android TFLite inference plugin.
///
/// The full preprocess + inference pipeline runs on a native background thread
/// (GCD on iOS, ExecutorService on Android). Flutter only parses the output (< 1ms).
class NativeInference {
  static const _channel = MethodChannel('com.dartrivals/native_inference');

  /// Per-frame timing logs (channelRoundTrip/parse). Off by default — these
  /// fire every frame and flood the log. Flip on only to profile inference.
  static bool verboseTiming = false;

  // Both native plugins run everything on ONE serial thread (dvExecutor on
  // Android, inferenceQueue on iOS). A single wedged GPU/CoreML inference —
  // typical under thermal throttling — therefore blocks every later call on
  // the channel, including the next match's loadModel, and the awaiting UI
  // ("Chargement du score auto…") span forever. These bounds turn a native
  // wedge into the normal failure path (retry / error frame) instead.
  // Values are far above the normal case (inference ≤ ~1s; a cold load is a
  // few seconds, but first-launch GPU shader compilation on some Android
  // devices can legitimately take >10s — hence the more generous load bound).
  static const Duration _loadTimeout = Duration(seconds: 15);
  static const Duration _analyzeTimeout = Duration(seconds: 10);

  bool _loaded = false;
  bool get isLoaded => _loaded;

  // Reused buffer for the rare case where the channel bytes aren't 4-byte
  // aligned. The common path returns a zero-copy Float32List VIEW over the
  // channel bytes, so we avoid allocating a fresh ~1.1MB buffer every frame
  // (which was a major source of the Android GC thrashing).
  Uint8List? _alignScratch;

  /// View the model-output channel bytes as Float32 without copying when
  /// possible. MethodChannel byte arrays are normally 8-byte aligned at offset
  /// 0, so the view is free; only a misaligned buffer falls back to a single
  /// copy into a reused scratch (still no per-frame allocation).
  Float32List _outputFloats(Uint8List bytes) {
    if (bytes.offsetInBytes % 4 == 0) {
      return bytes.buffer
          .asFloat32List(bytes.offsetInBytes, bytes.lengthInBytes ~/ 4);
    }
    if (_alignScratch == null || _alignScratch!.length != bytes.lengthInBytes) {
      _alignScratch = Uint8List(bytes.lengthInBytes);
    }
    _alignScratch!.setAll(0, bytes);
    return _alignScratch!.buffer.asFloat32List();
  }

  /// Parser instance — reuses calibration cache across frames.
  final DartDetectionService _parser = DartDetectionService(useNativeDecode: false);

  // ---- Wedge recovery ------------------------------------------------------
  // A hung GPU/CoreML call leaves the single native inference thread blocked
  // forever: the first analyze after the wedge times out, and every later one
  // is rejected instantly with BUSY (the native in-progress flag never
  // clears). Users discovered that killing and reopening the app fixes it —
  // a fresh process gets a fresh thread + interpreter. rebuildEngine
  // simulates that restart in-process: native abandons the wedged
  // executor/interpreter (deliberate leak) and the model is reloaded on a
  // fresh thread, CPU-only so the stuck GPU driver is not touched again.
  // Slower inference, but the AI comes back mid-match on its own.
  bool _sawAnalyzeTimeout = false;
  int _failuresSinceTimeout = 0;
  static const int _rebuildFailureThreshold = 3;
  DateTime? _lastRebuildRequest;
  static const Duration _rebuildMinInterval = Duration(seconds: 45);
  bool _recovering = false;

  void _noteAnalyzeSuccess() {
    _sawAnalyzeTimeout = false;
    _failuresSinceTimeout = 0;
  }

  void _noteAnalyzeFailure(Object e) {
    final isTimeout = e is TimeoutException;
    final isBusy = e is PlatformException && e.code == 'BUSY';
    if (isTimeout) _sawAnalyzeTimeout = true;
    // Only a timeout followed by more timeouts/BUSY (no success in between)
    // is the wedge signature — isolated BUSY errors are normal contention.
    if (!_sawAnalyzeTimeout || !(isTimeout || isBusy)) return;
    _failuresSinceTimeout++;
    if (_failuresSinceTimeout < _rebuildFailureThreshold) return;
    _sawAnalyzeTimeout = false;
    _failuresSinceTimeout = 0;
    // Fire-and-forget: while the engine is rebuilt + reloaded the capture
    // loop keeps getting fast error frames, then detections resume.
    unawaited(_rebuildAndReload());
  }

  /// Ask native to abandon the wedged engine. Rate-limited so repeated
  /// failures can't loop the rebuild.
  Future<bool> _requestRebuild() async {
    final now = DateTime.now();
    if (_lastRebuildRequest != null &&
        now.difference(_lastRebuildRequest!) < _rebuildMinInterval) {
      return false;
    }
    _lastRebuildRequest = now;
    debugPrint('[NativeInference] engine appears wedged — requesting rebuild '
        '(in-process app-restart equivalent)');
    try {
      await _channel
          .invokeMethod('rebuildEngine')
          .timeout(const Duration(seconds: 5));
      return true;
    } catch (e) {
      debugPrint('[NativeInference] rebuildEngine failed: $e');
      return false;
    }
  }

  Future<void> _rebuildAndReload() async {
    if (_recovering) return;
    _recovering = true;
    try {
      if (!await _requestRebuild()) return;
      _loaded = false;
      await loadModel();
      debugPrint('[NativeInference] engine rebuilt, model reloaded (CPU-only)');
    } catch (e) {
      debugPrint('[NativeInference] engine rebuild/reload failed: $e');
    } finally {
      _recovering = false;
    }
  }

  Future<void> loadModel() async {
    try {
      // Adaptive model ladder (DartsMind changeAIModelIfNeed port): small
      // model by default, big model on devices whose persisted profile is
      // fast enough. Native reuses the interpreter when the model is
      // unchanged and rebuilds when the selector picked a different one.
      await ModelSelector.ensureInitialized();
      final asset = ModelSelector.currentAsset;
      if (Platform.isAndroid) {
        // Android: extract model to temp file via rootBundle (always works),
        // then pass the file path to native. This bypasses all Android
        // AssetManager path resolution and compression issues.
        final modelData = await rootBundle.load(asset);
        final tempDir = await getTemporaryDirectory();
        final modelFile = File('${tempDir.path}/${asset.split('/').last}');
        if (!modelFile.existsSync()) {
          await modelFile.writeAsBytes(
            modelData.buffer.asUint8List(),
            flush: true,
          );
        }
        final result = await _channel
            .invokeMethod('loadModelFile', modelFile.path)
            .timeout(_loadTimeout);
        _loaded = result == true;
      } else {
        // iOS: load from bundle assets directly (works fine)
        final result = await _channel
            .invokeMethod('loadModel',
                {'modelName': ModelSelector.currentModelName})
            .timeout(_loadTimeout);
        _loaded = result == true;
      }
      if (_loaded) ModelSelector.markLoaded(asset);
      debugPrint('[NativeInference] loadModel: model=$asset loaded=$_loaded platform=${Platform.isAndroid ? "android" : "ios"}');
    } catch (e) {
      debugPrint('[NativeInference] loadModel error: $e');
      _loaded = false;
      if (e is TimeoutException) {
        // The load is queued behind a wedged call on the native inference
        // thread. Abandon that engine so the caller's retry loads a fresh
        // (CPU-only) interpreter instead of queueing behind the wedge again.
        await _requestRebuild();
      }
      rethrow;
    }
  }

  /// Send RGBA frame to native for preprocess + inference.
  /// Returns a [ScoringResult] with detections and scores.
  Future<ScoringResult> analyzeRgba(Uint8List rgba, int width, int height,
      {bool isBgra = false}) async {
    if (!_loaded) {
      return _error('Model not loaded');
    }

    try {
      final sw = Stopwatch()..start();
      final response = await _channel.invokeMethod<Map>('analyze', {
        'rgba': rgba,
        'width': width,
        'height': height,
        'isBgra': isBgra,
      }).timeout(_analyzeTimeout);
      _noteAnalyzeSuccess();
      final channelMs = sw.elapsedMilliseconds;

      if (response == null) return _error('Null response from native');

      sw.reset();
      final outputBytes = response['output'] as Uint8List;
      final xScale = (response['xScale'] as num).toDouble();
      final yScale = (response['yScale'] as num).toDouble();
      final imageWidth = response['imageWidth'] as int;
      final imageHeight = response['imageHeight'] as int;

      final outputFloats = _outputFloats(outputBytes);

      final result = _parser.parseRawOutput(
        outputFloats, xScale, yScale, imageWidth, imageHeight,
      );
      final parseMs = sw.elapsedMilliseconds;
      if (verboseTiming) {
        debugPrint(
            '[NativeInference] Dart: channelRoundTrip=${channelMs}ms parse=${parseMs}ms rgbaSize=${rgba.length}');
      }
      return result;
    } catch (e) {
      _noteAnalyzeFailure(e);
      debugPrint('[NativeInference] analyzeRgba error: $e');
      return _error('Native inference error: $e');
    }
  }

  /// Send raw YUV420 planes to native for DartsMind-style processing.
  /// Android only: YUV → NV21 → Bitmap → rotation → preprocess → inference.
  /// Matches DartsMind's ZLVideoCapture → Detector.detectVideoBuffer pipeline.
  Future<ScoringResult> analyzeYuv({
    required Uint8List yPlane,
    required Uint8List uPlane,
    required Uint8List vPlane,
    required int width,
    required int height,
    required int yRowStride,
    required int uvRowStride,
    required int uvPixelStride,
    required int rotation,
  }) async {
    if (!_loaded) return _error('Model not loaded');

    try {
      final sw = Stopwatch()..start();
      final response = await _channel.invokeMethod<Map>('analyzeYuv', {
        'yPlane': yPlane,
        'uPlane': uPlane,
        'vPlane': vPlane,
        'width': width,
        'height': height,
        'yRowStride': yRowStride,
        'uvRowStride': uvRowStride,
        'uvPixelStride': uvPixelStride,
        'rotation': rotation,
      }).timeout(_analyzeTimeout);
      _noteAnalyzeSuccess();
      final channelMs = sw.elapsedMilliseconds;

      if (response == null) return _error('Null response from native');

      sw.reset();
      final outputBytes = response['output'] as Uint8List;
      final xScale = (response['xScale'] as num).toDouble();
      final yScale = (response['yScale'] as num).toDouble();
      final imageWidth = response['imageWidth'] as int;
      final imageHeight = response['imageHeight'] as int;

      final outputFloats = _outputFloats(outputBytes);

      final result = _parser.parseRawOutput(
        outputFloats, xScale, yScale, imageWidth, imageHeight,
      );
      final parseMs = sw.elapsedMilliseconds;
      if (verboseTiming) {
        debugPrint(
            '[NativeInference] YUV: channelRoundTrip=${channelMs}ms parse=${parseMs}ms');
      }
      return result;
    } catch (e) {
      _noteAnalyzeFailure(e);
      debugPrint('[NativeInference] analyzeYuv error: $e');
      return _error('Native YUV inference error: $e');
    }
  }

  /// Analyze an image file (JPEG/PNG). Native reads and decodes the file,
  /// then runs preprocess + inference. Used by camera setup screen.
  Future<ScoringResult> analyzeFile(String filePath) async {
    if (!_loaded) return _error('Model not loaded');

    try {
      final response = await _channel
          .invokeMethod<Map>('analyzeFile', filePath)
          .timeout(_analyzeTimeout);
      _noteAnalyzeSuccess();
      if (response == null) return _error('Null response from native');

      final outputBytes = response['output'] as Uint8List;
      final xScale = (response['xScale'] as num).toDouble();
      final yScale = (response['yScale'] as num).toDouble();
      final imageWidth = response['imageWidth'] as int;
      final imageHeight = response['imageHeight'] as int;

      final aligned = Uint8List.fromList(outputBytes);
      final outputFloats = aligned.buffer.asFloat32List();

      return _parser.parseRawOutput(
        outputFloats, xScale, yScale, imageWidth, imageHeight,
      );
    } catch (e) {
      _noteAnalyzeFailure(e);
      debugPrint('[NativeInference] analyzeFile error: $e');
      return _error('Native inference error: $e');
    }
  }

  /// Normalized device thermal level: 0 = normal, 1 = elevated (device warm,
  /// OS starting to throttle), 2 = severe (heavy throttling). Maps
  /// PowerManager.THERMAL_STATUS_* (Android) and ProcessInfo.thermalState
  /// (iOS), which happen to share the same cut-offs on their raw scales.
  /// Natively answered on the platform thread (never the inference executor),
  /// so it stays responsive even when inference is wedged. Returns 0 on any
  /// error so callers never throttle by accident.
  Future<int> thermalLevel() async {
    try {
      final raw = await _channel
          .invokeMethod<int>('thermalStatus')
          .timeout(const Duration(seconds: 2));
      if (raw == null || raw <= 1) return 0;
      return raw >= 3 ? 2 : 1;
    } catch (_) {
      return 0;
    }
  }

  void dispose() {
    _parser.dispose();
    _loaded = false;
  }

  static ScoringResult _error(String msg) => ScoringResult(
    calibrationPoints: [],
    dartTips: [],
    scores: [],
    totalScore: 0,
    error: msg,
  );
}
