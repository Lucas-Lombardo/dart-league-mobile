// Stub for web — dart_detection_service uses dart:io and tflite_flutter
// which don't work on web. This stub provides the same API but does nothing.

import 'dart:typed_data';
import 'dart_detection_types.dart';
export 'dart_detection_types.dart';

class DartDetectionService {
  DartDetectionService({bool useNativeDecode = true});

  bool get isLoaded => false;

  Future<void> loadModel({bool cpuOnly = false}) async {}

  void dispose() {}

  Future<ScoringResult> analyzeRgba(Uint8List rgba, int imgW, int imgH) async {
    return ScoringResult(
      calibrationPoints: [],
      dartTips: [],
      scores: [],
      totalScore: 0,
      error: 'Auto-scoring not supported on web',
    );
  }

  Future<ScoringResult> analyzeImage(String imagePath) async {
    return ScoringResult(
      calibrationPoints: [],
      dartTips: [],
      scores: [],
      totalScore: 0,
      error: 'Auto-scoring not supported on web',
    );
  }
}
