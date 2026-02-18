// Stub for web — dart_detection_service uses dart:io and tflite_flutter
// which don't work on web. This stub provides the same API but does nothing.

import 'dart_detection_types.dart';
export 'dart_detection_types.dart';

class DartDetectionService {
  bool get isLoaded => false;

  Future<void> loadModel() async {
    // No-op on web
  }

  void dispose() {
    // No-op on web
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
