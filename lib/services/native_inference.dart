import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'dart_detection_service_stub.dart'
    if (dart.library.io) 'dart_detection_service.dart';
import 'detection_parsing.dart';
import 'model_selector.dart';
import 'output_parse_isolate.dart';

/// Wraps the native iOS/Android TFLite inference plugin.
///
/// The full preprocess + inference pipeline runs on a native background thread
/// (GCD on iOS, ExecutorService on Android). Flutter only parses the output (< 1ms).
class NativeInference {
  static const _channel = MethodChannel('com.dartrivals/native_inference');

  /// Per-frame timing logs (channelRoundTrip/parse). Off by default — these
  /// fire every frame and flood the log. Flip on only to profile inference.
  static bool verboseTiming = false;

  /// iOS delegate for the native interpreter ('auto' | 'cpu' | 'xnnpack' |
  /// 'metal' | 'coreml'). 'auto' = the plugin's CoreML → Metal → CPU
  /// cascade; any other value pins that rung (which is also how delegates
  /// get benchmarked against each other on-device — see
  /// lib/dev/delegate_bench.dart).
  ///
  /// Now read PER MODEL from [AiModel.iosDelegate] rather than being one
  /// constant, because the ranking is a property of the GRAPH and the bundled
  /// graphs disagree: the DartsMind anchor models want CoreML (light: 56ms vs
  /// 133ms xnnpack, 2026-08-10) while the o2o export family wants xnnpack
  /// (v10 float16: 106ms vs 297ms coreml, 2026-08-13). Re-bench any new
  /// model, never predict.
  static String get iosDelegate => ModelSelector.currentIosDelegate;

  // Both native plugins run everything on ONE serial thread (dvExecutor on
  // Android, inferenceQueue on iOS). A single wedged GPU/CoreML inference —
  // typical under thermal throttling — therefore blocks every later call on
  // the channel, including the next match's loadModel, and the awaiting UI
  // ("Chargement du score auto…") span forever. These bounds turn a native
  // wedge into the normal failure path (retry / error frame) instead.
  // Values are far above the normal case (inference ≤ ~1s; a cold load is a
  // few seconds). The load bound must clear a LEGITIMATE slow delegate build:
  // first-launch GPU shader compilation on some Android devices and the
  // CoreML delegate compilation on a hot/throttled iPhone both exceed 15s —
  // the old bound — which misread them as wedges and rebuilt a working
  // engine into a CPU-only one. Genuine load wedges are almost always queued
  // behind a hung analyze, which the (unchanged) 10s analyze bound catches.
  static const Duration _loadTimeout = Duration(seconds: 30);
  static const Duration _analyzeTimeout = Duration(seconds: 10);

  bool _loaded = false;
  bool get isLoaded => _loaded;

  /// Pure model-invoke time (ms) of the last successful analyze, measured on
  /// the native side — excludes preprocess, channel marshaling and Dart-side
  /// parsing. Null until the first successful frame.
  int? lastNativeInferMs;

  /// True when the last analyze call failed at the ENGINE level: model not
  /// loaded, channel timeout/BUSY, invoke error, or an unparseable response.
  /// This is the ONLY reliable "engine is broken" signal — ScoringResult.error
  /// alone is NOT one: the parser also sets it on perfectly normal frames
  /// ('No darts detected' on every empty board, 'Need 4 control points'
  /// whenever the player blocks the camera), which carry real calibration
  /// data and must keep flowing through the scoring pipeline.
  bool lastAnalyzeFailed = false;

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

  /// Parse + NMS on the worker isolate when available (the ~194k-float tensor
  /// scan used to run on the UI isolate every inference), inline as fallback —
  /// scoring must never stall on the worker's health.
  Future<ScoringResult> _parseResponse(
    Uint8List outputBytes,
    double xScale,
    double yScale,
    int imageWidth,
    int imageHeight,
  ) async {
    // Native returns bare bytes without the tensor shape — reconstruct it
    // from the float count (anchor head [1,13,~21504] vs e2e head [1,~300,6],
    // see deriveOutputShape). The parse isolate dispatches on that shape.
    final shape = deriveOutputShape(outputBytes.lengthInBytes ~/ 4);
    final dets = await OutputParseIsolate.instance.tryParse(
      outputBytes,
      numChannels: shape[1],
      numElements: shape[2],
      xScale: xScale,
      yScale: yScale,
      layout: _parser.layout,
    );
    if (dets != null) {
      return _parser.scoreParsedDetections(dets, imageWidth, imageHeight);
    }
    return _parser.parseRawOutput(
      _outputFloats(outputBytes), xScale, yScale, imageWidth, imageHeight,
    );
  }

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

  /// True while the engine is being rebuilt + reloaded after a wedge. The
  /// capture loop uses this to NOT count the transient "Model not loaded"
  /// error frames of a recovery window toward its own dead-engine trip.
  bool get isRecovering => _recovering;

  void _noteAnalyzeSuccess() {
    lastAnalyzeFailed = false;
    _sawAnalyzeTimeout = false;
    _failuresSinceTimeout = 0;
  }

  void _noteAnalyzeFailure(Object e) {
    lastAnalyzeFailed = true;
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

  /// Abandon the native engine unconditionally so the NEXT loadModel rebuilds
  /// it from scratch (CPU-only first, delegates again on the load after).
  ///
  /// The automatic wedge detector above only reacts to TIMEOUT/BUSY. When an
  /// engine fails persistently with anything else (INVOKE_ERROR from a
  /// poisoned delegate, NOT_LOADED after a failed recovery reload), the
  /// capture loop trips its dead-engine counter and calls this — without it,
  /// the reload that follows would hit the native "same model — reusing"
  /// shortcut and hand the broken interpreter straight back.
  Future<void> invalidateEngine() async {
    _loaded = false;
    try {
      await _channel
          .invokeMethod('rebuildEngine')
          .timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('[NativeInference] invalidateEngine failed: $e');
    }
  }

  Future<void> loadModel() async {
    try {
      // Per-device model, resolved once by ModelSelector.init(). Native
      // reuses the interpreter when the model file is unchanged, so reloads
      // after a recovery are cheap.
      //
      // Freeze the choice for the rest of the app run: from here on a rollout
      // change landing mid-session is persisted for the next launch but not
      // adopted. The parse layout is a property of the LOADED weights, and
      // swapping one without the other reads darts as calibration points.
      ModelSelector.markModelLoaded();
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
            .invokeMethod('loadModel', {
              'modelName': ModelSelector.currentModelName,
              'delegate': iosDelegate,
            })
            .timeout(_loadTimeout);
        _loaded = result == true;
      }
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
      lastAnalyzeFailed = true;
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
      lastNativeInferMs = (response['inferenceMs'] as num?)?.toInt();

      sw.reset();
      final outputBytes = response['output'] as Uint8List;
      final xScale = (response['xScale'] as num).toDouble();
      final yScale = (response['yScale'] as num).toDouble();
      final imageWidth = response['imageWidth'] as int;
      final imageHeight = response['imageHeight'] as int;

      final result = await _parseResponse(
        outputBytes, xScale, yScale, imageWidth, imageHeight,
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
    if (!_loaded) {
      lastAnalyzeFailed = true;
      return _error('Model not loaded');
    }

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
      lastNativeInferMs = (response['inferenceMs'] as num?)?.toInt();

      sw.reset();
      final outputBytes = response['output'] as Uint8List;
      final xScale = (response['xScale'] as num).toDouble();
      final yScale = (response['yScale'] as num).toDouble();
      final imageWidth = response['imageWidth'] as int;
      final imageHeight = response['imageHeight'] as int;

      final result = await _parseResponse(
        outputBytes, xScale, yScale, imageWidth, imageHeight,
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
    if (!_loaded) {
      lastAnalyzeFailed = true;
      return _error('Model not loaded');
    }

    try {
      final response = await _channel
          .invokeMethod<Map>('analyzeFile', filePath)
          .timeout(_analyzeTimeout);
      _noteAnalyzeSuccess();
      if (response == null) return _error('Null response from native');
      lastNativeInferMs = (response['inferenceMs'] as num?)?.toInt();

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
