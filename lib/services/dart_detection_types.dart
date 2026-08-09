import 'dart_scoring_service.dart';

/// Acceptable on-screen board size, as the largest x/y extent of the 4
/// calibration points in normalized image coords ("spread"). Shared by the
/// in-game zoom hint (AutoScoringService._updateZoomHint) and the camera
/// setup screen so they cannot drift apart.
///
/// The 0.50 floor is measured, not aesthetic: on the 2026-08-09 test leg,
/// v7 below 0.50 spread went completely blind on up to 19% of frames
/// (14 consecutive frames with 3 planted darts unseen), while at >= 0.50 it
/// missed none. An earlier relaxation of setup to 0.35 "because the AI
/// scores fine" was exactly wrong — it admitted the blind zone.
const double kZoomSpreadMin = 0.50;
const double kZoomSpreadMax = 0.85;

/// Comfort floor used by the SETUP gate and the AutoFramer target band:
/// 0.50 is where the model stops going blind, but a board locked near the
/// floor still looks under-zoomed — setup keeps sizing until the board
/// fills at least this much. Calibrated against Lucas's reference framing
/// (1.7× on his rig ≈ 0.78 spread, board edge-to-edge with the surround
/// cropped). Match hints keep the 0.50 floor (no comfort churn mid-game).
const double kZoomSpreadComfortMin = 0.68;

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
  /// for scoring mid-turn, but framing logic (setup gate, zoom hints/gauge,
  /// AutoFramer) must treat such a frame as "board not fully visible": the
  /// cache once let a 2.5×, half-out-of-frame board pass the setup gate with
  /// a green gauge, and fed the servo a fictional spread.
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
