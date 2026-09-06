import 'dart:math' as math;

import 'dart_detection_types.dart';
import 'dart_scoring_service.dart';

/// Geometric answer to "is the board framed correctly?", measured on the
/// PROJECTED board-edge circle instead of the calibration-point extents.
///
/// The old extent-based spread lied as soon as the board overflowed the
/// frame: the visible points under-estimate the board and a 2.5×, cut-off
/// board read as "in zone". The homography (already computed for scoring)
/// projects the full board circle into image space — including the parts
/// OUTSIDE the frame — so size, visibility and centering become three plain
/// geometric tests that cannot be fooled.
class BoardFraming {
  /// Projected board diameter: max of the circle's x/y extents, as a
  /// fraction of the image dimension. Can exceed 1.0 when the board
  /// overflows the frame — that IS the honest measure.
  final double spread;

  /// Projected board centre, as fractions of the image dimensions.
  final double centerX;
  final double centerY;

  /// The circle's x / y extents as fractions of the image width / height —
  /// what [spread] is the max of. Kept separately for the board crop, which
  /// needs the board's size in PIXELS on a frame whose aspect is not 1.
  final double extentX;
  final double extentY;

  /// Whether the whole projected circle fits inside the frame (small margin).
  final bool fullyVisible;

  /// Clockwise angle (degrees, [0, 360)) by which the board appears rotated
  /// in the analyzed frame — 0 means the 20 points straight up. Measured on
  /// the projected centre→20 axis, aspect-corrected when the caller passes
  /// the frame dimensions. Null when that projection degenerates.
  final double? tiltDegrees;

  const BoardFraming({
    required this.spread,
    required this.centerX,
    required this.centerY,
    required this.fullyVisible,
    this.tiltDegrees,
    double? extentX,
    double? extentY,
  })  : extentX = extentX ?? spread,
        extentY = extentY ?? spread;

  static const double _edgeMargin = 0.01;
  static const double _centerTolerance = 0.18;
  static const int _samples = 16;

  bool get centered =>
      (centerX - 0.5).abs() <= _centerTolerance &&
      (centerY - 0.5).abs() <= _centerTolerance;

  bool get inZone => spread >= kZoomSpreadMin && spread <= kZoomSpreadMax;

  /// Everything the setup gate needs: whole board in frame, roughly
  /// centered, at a size the model is reliable at.
  bool get locked => fullyVisible && centered && inZone;

  /// Null when no valid homography can be built (< 4 points, degenerate set)
  /// or the projection is implausible. [imageWidth]/[imageHeight] are the
  /// analyzed frame's pixel dimensions, used only to aspect-correct
  /// [tiltDegrees] (the normalized-space measures don't need them).
  static BoardFraming? compute(
    List<Detection> calibrationPoints, {
    int imageWidth = 1,
    int imageHeight = 1,
  }) {
    if (calibrationPoints.length < 4) return null;
    final DartScoringService scorer;
    try {
      scorer = DartScoringService(calibrationPoints
          .take(4)
          .map((c) => [c.x, c.y, c.flag.toDouble()])
          .toList());
    } catch (_) {
      return null; // collinear / duplicate points
    }

    double minX = double.infinity, maxX = -double.infinity;
    double minY = double.infinity, maxY = -double.infinity;
    var inside = true;
    try {
      for (var i = 0; i < _samples; i++) {
        final angle = i * 2 * math.pi / _samples;
        final p = scorer.boardToImage(
          kBoardR + kBoardR * math.cos(angle),
          kBoardR + kBoardR * math.sin(angle),
        );
        final x = p[0], y = p[1];
        if (!x.isFinite || !y.isFinite) return null;
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
        if (x < -_edgeMargin ||
            x > 1 + _edgeMargin ||
            y < -_edgeMargin ||
            y > 1 + _edgeMargin) {
          inside = false;
        }
      }
      final center = scorer.boardToImage(kBoardR, kBoardR);
      if (!center[0].isFinite || !center[1].isFinite) return null;
      final extentX = maxX - minX, extentY = maxY - minY;
      final spread = extentX > extentY ? extentX : extentY;
      // A wildly implausible projection (near-degenerate homography blowing
      // the circle up) is noise, not a measurement.
      if (spread <= 0.01 || spread > 5.0) return null;
      // Board tilt: project the canonical centre→20 axis into the image and
      // take its clockwise angle from "up" (y-down screen coords).
      double? tilt;
      final top = scorer.boardToImage(kBoardR, 0);
      if (top[0].isFinite && top[1].isFinite) {
        final dx = (top[0] - center[0]) * imageWidth;
        final dy = (top[1] - center[1]) * imageHeight;
        tilt = math.atan2(dx, -dy) * 180 / math.pi;
        if (tilt < 0) tilt += 360;
      }
      return BoardFraming(
        spread: spread,
        centerX: center[0],
        centerY: center[1],
        fullyVisible: inside,
        tiltDegrees: tilt,
        extentX: extentX,
        extentY: extentY,
      );
    } catch (_) {
      return null;
    }
  }
}
