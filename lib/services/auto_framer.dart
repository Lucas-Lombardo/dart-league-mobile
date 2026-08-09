import 'dart:async';

import 'dart_detection_types.dart';

/// Outcome of an [AutoFramer.run] pass.
enum AutoFrameResult {
  /// Spread landed inside the reliable zone.
  framed,

  /// The board stopped being detected (out of frame, occluded).
  boardLost,

  /// Zoom hit its hardware bound while the spread was still out of zone —
  /// the phone itself has to move.
  zoomLimit,

  /// Cancelled by the caller (screen left, camera gone).
  cancelled,
}

/// Servo loop that drives the camera zoom until the board's measured spread
/// (largest x/y extent of the 4 calibration points — the same value behind
/// the zoom hints) lands inside [kZoomSpreadMin, kZoomSpreadMax].
///
/// Spread scales ~linearly with optical zoom, so each step aims straight at
/// [_target] and re-measures. Steps are clamped (±35%/25%) so one noisy
/// measurement can't overshoot, and the settle delay covers a full inference
/// cycle so a step never reacts to the pre-zoom frame.
///
/// Used by the camera-setup screen ("Cadrer auto" button) and the in-match
/// AUTO chip — one implementation so their behavior cannot diverge.
class AutoFramer {
  AutoFramer._();

  // Aim below the zone's midpoint: over-zooming crops the board (worse than
  // a little margin), and the hysteresis bounds keep a framed result from
  // immediately re-triggering the hint.
  static const double _target = 0.62;
  static const double _inLo = kZoomSpreadMin + 0.02;
  static const double _inHi = kZoomSpreadMax - 0.02;
  static const Duration _settle = Duration(milliseconds: 500);
  static const int _maxSteps = 10;
  static const int _maxMisses = 4;

  static Future<AutoFrameResult> run({
    required double? Function() readSpread,
    required double Function() readZoom,
    required Future<void> Function(double zoom) setZoom,
    required double minZoom,
    required double maxZoom,
    bool Function()? isCancelled,
  }) async {
    var misses = 0;
    for (var step = 0; step < _maxSteps; step++) {
      await Future.delayed(_settle);
      if (isCancelled?.call() ?? false) return AutoFrameResult.cancelled;

      final spread = readSpread();
      if (spread == null || spread <= 0) {
        if (++misses >= _maxMisses) return AutoFrameResult.boardLost;
        continue;
      }
      misses = 0;

      if (spread >= _inLo && spread <= _inHi) return AutoFrameResult.framed;

      final zoom = readZoom();
      final next = (zoom * (_target / spread))
          .clamp(zoom * 0.75, zoom * 1.35)
          .clamp(minZoom, maxZoom);
      if ((next - zoom).abs() < 0.02) {
        // Pinned against a zoom bound and still out of zone.
        return AutoFrameResult.zoomLimit;
      }
      await setZoom(next);
    }
    return AutoFrameResult.zoomLimit;
  }
}
