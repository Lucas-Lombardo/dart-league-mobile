import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;

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

  // Aim at the reference framing (board edge-to-edge, surround cropped —
  // ≈ 0.78 spread) while keeping margin below the 0.85 crop ceiling. The
  // satisfaction band starts just above the comfort floor so the servo
  // doesn't stop at the first barely-acceptable measurement.
  static const double _target = 0.78;
  static const double _inLo = kZoomSpreadComfortMin + 0.02;
  static const double _inHi = kZoomSpreadMax - 0.02;
  static const Duration _settle = Duration(milliseconds: 500);
  // Enough steps for the worst path: miss-limit → reset to 1× → re-acquire
  // → walk the zoom back into the zone.
  static const int _maxSteps = 14;
  static const int _maxMisses = 4;

  /// [resetToMinOnLost]: when the board can't be measured (over-zoomed past
  /// its calibration points, servo lost it), drop the zoom back to [minZoom]
  /// ONCE and keep going — at 1× the whole board is back in frame and the
  /// normal zoom-in path takes over. Setup screens want this (nobody stands
  /// in front of the board); match screens must NOT (a player pulling darts
  /// occludes the board constantly — resetting zoom there would churn).
  ///
  /// [readAnalysisSeq]: monotonically increasing count of completed AI
  /// analyses. When provided, each servo step waits for TWO analyses that
  /// happened AFTER its zoom change before re-measuring — without this the
  /// loop reacted to frames captured before the zoom applied (analysis
  /// ~300ms + tick delay > the settle), double-corrected, and oscillated
  /// too-big / too-small forever.
  static Future<AutoFrameResult> run({
    required double? Function() readSpread,
    required double Function() readZoom,
    required Future<void> Function(double zoom) setZoom,
    required double minZoom,
    required double maxZoom,
    bool Function()? isCancelled,
    bool resetToMinOnLost = false,
    int Function()? readAnalysisSeq,
  }) async {
    var misses = 0;
    var resetTried = !resetToMinOnLost;

    Future<bool> waitFreshMeasure() async {
      if (readAnalysisSeq == null) {
        await Future.delayed(_settle);
        return !(isCancelled?.call() ?? false);
      }
      final baseline = readAnalysisSeq();
      final sw = Stopwatch()..start();
      while (readAnalysisSeq() < baseline + 2 &&
          sw.elapsed < const Duration(seconds: 3)) {
        await Future.delayed(const Duration(milliseconds: 100));
        if (isCancelled?.call() ?? false) return false;
      }
      return true;
    }

    for (var step = 0; step < _maxSteps; step++) {
      if (!await waitFreshMeasure()) return AutoFrameResult.cancelled;

      final spread = readSpread();
      final zoom = readZoom();
      if (spread == null || spread <= 0) {
        debugPrint('[AutoFramer] step $step zoom=${zoom.toStringAsFixed(2)} '
            'spread=none (miss ${misses + 1}/$_maxMisses)');
        if (++misses >= _maxMisses) {
          if (!resetTried && zoom > minZoom + 0.01) {
            resetTried = true;
            misses = 0;
            debugPrint('[AutoFramer] board lost while zoomed — reset to 1×');
            await setZoom(minZoom);
            continue;
          }
          return AutoFrameResult.boardLost;
        }
        continue;
      }
      misses = 0;

      if (spread >= _inLo && spread <= _inHi) {
        debugPrint('[AutoFramer] framed: zoom=${zoom.toStringAsFixed(2)} '
            'spread=${spread.toStringAsFixed(3)}');
        return AutoFrameResult.framed;
      }

      // 0.8 damping on the proportional correction: with measurement noise a
      // full-gain step can cross the zone and bounce; slightly under-aiming
      // converges in one extra step instead.
      final ratio = 1 + 0.8 * (_target / spread - 1);
      final next = (zoom * ratio)
          .clamp(zoom * 0.75, zoom * 1.35)
          .clamp(minZoom, maxZoom);
      debugPrint('[AutoFramer] step $step zoom=${zoom.toStringAsFixed(2)} '
          'spread=${spread.toStringAsFixed(3)} → zoom=${next.toStringAsFixed(2)}');
      if ((next - zoom).abs() < 0.02) {
        // Pinned against a zoom bound and still out of zone.
        return AutoFrameResult.zoomLimit;
      }
      await setZoom(next);
    }
    debugPrint('[AutoFramer] out of steps — giving up');
    return AutoFrameResult.zoomLimit;
  }
}
