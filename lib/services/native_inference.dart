import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

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
      final result = await _channel.invokeMethod('loadModel');
      _loaded = result == true;
      debugPrint('[NativeInference] loadModel: loaded=$_loaded');
    } catch (e) {
      debugPrint('[NativeInference] loadModel error: $e');
      _loaded = false;
      rethrow;
    }
  }

  /// Send RGBA frame to native for preprocess + inference.
  /// Returns a [ScoringResult] with detections and scores.
  Future<ScoringResult> analyzeRgba(Uint8List rgba, int width, int height) async {
    if (!_loaded) {
      return _error('Model not loaded');
    }

    try {
      final sw = Stopwatch()..start();
      final response = await _channel.invokeMethod<Map>('analyze', {
        'rgba': rgba,
        'width': width,
        'height': height,
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
      debugPrint('[NativeInference] Dart: channelRoundTrip=${channelMs}ms parse=${parseMs}ms rgbaSize=${rgba.length}');
      return result;
    } catch (e) {
      debugPrint('[NativeInference] analyzeRgba error: $e');
      return _error('Native inference error: $e');
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
