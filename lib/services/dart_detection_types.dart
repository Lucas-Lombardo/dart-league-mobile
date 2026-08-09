import 'dart_scoring_service.dart';

/// Required on-screen board size ("spread" — extent of the projected board
/// circle as a fraction of the image, see BoardFraming). ONE shared pair:
/// the camera-setup gate and the in-game zoom hints both require exactly
/// this zone, so what passes setup never warns in game and vice-versa.
///
/// The floor is calibrated on the reference framing (≈1.7× on Lucas's rig,
/// board edge-to-edge ≈ 0.78 spread) with working margin; the measured
/// model-blindness floor is far lower (0.50 — below it the detector missed
/// up to 19% of frames on the 2026-08-09 test leg), so the zone keeps a
/// comfortable safety cushion. 0.85 is the crop ceiling.
const double kZoomSpreadMin = 0.68;
const double kZoomSpreadMax = 0.85;

/// Semantic camera-framing hint produced by the scorer / setup analysis.
/// UI layers map it to a localized string — the service must never emit
/// display text (the old hardcoded English leaked into the match pill).
enum ZoomHint { dartboardNotDetected, boardNotFullyVisible, zoomIn, zoomOut }

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

  /// True when [calibrationPoints] came from the last-good-calibration CACHE
  /// (the frame itself showed < 4 points — hand occlusion, over-zoom). Fine
  /// for scoring mid-turn, but framing logic (setup gate, zoom hints) must
  /// treat such a frame as "board not fully visible": the cache once let a
  /// 2.5×, half-out-of-frame board pass the setup gate as valid.
  final bool calibrationFromCache;

  ScoringResult({
    required this.calibrationPoints,
    required this.dartTips,
    required this.scores,
    required this.totalScore,
    this.error,
    this.imageWidth = 1,
    this.imageHeight = 1,
    this.calibrationFromCache = false,
  });
}
