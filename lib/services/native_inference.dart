import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'dart_detection_service_stub.dart'
    if (dart.library.io) 'dart_detection_service.dart';

/// Wraps the native iOS/Android TFLite inference plugin.
///
/// The full preprocess + inference pipeline runs on a native background thread
/// (GCD on iOS, ExecutorService on Android). Flutter only parses the output (< 1ms).
class NativeInference {
  static const _channel = MethodChannel('com.dartrivals/native_inference');

  /// Per-frame timing logs (channelRoundTrip/parse). Off by default — these
  /// fire every frame and flood the log. Flip on only to profile inference.
  static bool verboseTiming = false;

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

  Future<void> loadModel() async {
    try {
      if (Platform.isAndroid) {
        // Android: extract model to temp file via rootBundle (always works),
        // then pass the file path to native. This bypasses all Android
        // AssetManager path resolution and compression issues.
        final modelData = await rootBundle.load('assets/models/t223.tflite');
        final tempDir = await getTemporaryDirectory();
        final modelFile = File('${tempDir.path}/t223.tflite');
        if (!modelFile.existsSync()) {
          await modelFile.writeAsBytes(
            modelData.buffer.asUint8List(),
            flush: true,
          );
        }
        final result = await _channel.invokeMethod('loadModelFile', modelFile.path);
        _loaded = result == true;
      } else {
        // iOS: load from bundle assets directly (works fine)
        final result = await _channel.invokeMethod('loadModel');
        _loaded = result == true;
      }
      debugPrint('[NativeInference] loadModel: model=t223.tflite loaded=$_loaded platform=${Platform.isAndroid ? "android" : "ios"}');
    } catch (e) {
      debugPrint('[NativeInference] loadModel error: $e');
      _loaded = false;
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
      });
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
      });
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
      debugPrint('[NativeInference] analyzeYuv error: $e');
      return _error('Native YUV inference error: $e');
    }
  }

  /// Analyze an image file (JPEG/PNG). Native reads and decodes the file,
  /// then runs preprocess + inference. Used by camera setup screen.
  Future<ScoringResult> analyzeFile(String filePath) async {
    if (!_loaded) return _error('Model not loaded');

    try {
      final response = await _channel.invokeMethod<Map>('analyzeFile', filePath);
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
