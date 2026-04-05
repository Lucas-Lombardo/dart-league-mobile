import 'dart_scoring_service.dart';

class Detection {
  final int classId; // 0-7 = p1-p8 (board control points), 8 = tip (dart tip)
  final String className; // "p1"-"p8" or "tip"
  final double x; // normalized center x [0,1]
  final double y; // normalized center y [0,1]
  final double width; // normalized width [0,1]
  final double height; // normalized height [0,1]
  final double confidence;

  Detection({
    required this.classId,
    required this.className,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.confidence,
  });

  /// Control point flag (1-8) for calibration, or 0 if this is a tip.
  int get flag => classId < 8 ? classId + 1 : 0;

  /// Whether this detection is a board control point (p1-p8).
  bool get isControlPoint => classId < 8;

  /// Whether this detection is a dart tip.
  bool get isTip => classId == 8;
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
