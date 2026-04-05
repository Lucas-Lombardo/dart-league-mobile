// Stub for web — DetectionIsolate uses dart:isolate and tflite_flutter
// which don't work on web. This stub provides the same API but does nothing.

import 'dart:typed_data';
import 'dart_detection_types.dart';

class DetectionIsolate {
  bool get isReady => false;

  Future<void> start() async {}

  Future<ScoringResult> analyze(String imagePath) async {
    return ScoringResult(
      calibrationPoints: [],
      dartTips: [],
      scores: [],
      totalScore: 0,
      error: 'Auto-scoring not supported on web',
    );
  }

  Future<ScoringResult> analyzeRgba(Uint8List rgba, int w, int h) async {
    return ScoringResult(
      calibrationPoints: [],
      dartTips: [],
      scores: [],
      totalScore: 0,
      error: 'Auto-scoring not supported on web',
    );
  }

  void dispose() {}
}
