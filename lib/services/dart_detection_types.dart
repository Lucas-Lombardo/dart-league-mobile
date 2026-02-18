import 'dart_scoring_service.dart';

class Detection {
  final int classId; // 0 = dart_tip, 1 = calibration_point
  final double x; // normalized center x [0,1]
  final double y; // normalized center y [0,1]
  final double width; // normalized width [0,1]
  final double height; // normalized height [0,1]
  final double confidence;

  Detection({
    required this.classId,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.confidence,
  });
}

class ScoringResult {
  final List<Detection> calibrationPoints;
  final List<Detection> dartTips;
  final List<DartScore> scores;
  final int totalScore;
  final String? error;
  final int imageWidth;
  final int imageHeight;

  ScoringResult({
    required this.calibrationPoints,
    required this.dartTips,
    required this.scores,
    required this.totalScore,
    this.error,
    this.imageWidth = 1,
    this.imageHeight = 1,
  });
}
