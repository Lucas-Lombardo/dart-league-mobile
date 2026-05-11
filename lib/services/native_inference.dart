import 'dart:io';
import 'dart:typed_data';

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

  bool _loaded = false;
  bool get isLoaded => _loaded;

  /// Parser instance — reuses calibration cache across frames.
  final DartDetectionService _parser = DartDetectionService(useNativeDecode: false);

  Future<void> loadModel() async {
    try {
      if (Platform.isAndroid) {
        // Android: extract model to temp file via rootBundle (always works),
        // then pass the file path to native. This bypasses all Android
        // AssetManager path resolution and compression issues.
        final modelData = await rootBundle.load('assets/models/t201.tflite');
        final tempDir = await getTemporaryDirectory();
        final modelFile = File('${tempDir.path}/t201.tflite');
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
      debugPrint('[NativeInference] loadModel: loaded=$_loaded');
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

      final aligned = Uint8List.fromList(outputBytes);
      final outputFloats = aligned.buffer.asFloat32List();

      final result = _parser.parseRawOutput(
        outputFloats, xScale, yScale, imageWidth, imageHeight,
      );
      final parseMs = sw.elapsedMilliseconds;
      if (kDebugMode) {
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

      final aligned = Uint8List.fromList(outputBytes);
      final outputFloats = aligned.buffer.asFloat32List();

      final result = _parser.parseRawOutput(
        outputFloats, xScale, yScale, imageWidth, imageHeight,
      );
      final parseMs = sw.elapsedMilliseconds;
      if (kDebugMode) {
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
