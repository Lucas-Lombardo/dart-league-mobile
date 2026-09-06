import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/widgets.dart';

/// What the opponent-turn dart zoom asks of the video: a scale about a focus
/// point (normalized in the DISPLAYED frame). [VideoZoomState.none] is the
/// plain, untouched video.
class VideoZoomState {
  final double scale;
  final double focusX;
  final double focusY;

  /// A typed score: the point is a bed centre, not a detected tip (the label
  /// says so; the video itself is zoomed the same way).
  final bool manual;

  const VideoZoomState({
    required this.scale,
    required this.focusX,
    required this.focusY,
    required this.manual,
  });

  static const none = VideoZoomState(
    scale: 1,
    focusX: 0.5,
    focusY: 0.5,
    manual: false,
  );

  bool get isIdle => scale <= 1.0005;
}

/// Owned by the match screen, driven by the dart flash, read by the remote
/// video — so the animation lives in one place and the video only paints.
class VideoZoomController extends ValueNotifier<VideoZoomState> {
  VideoZoomController() : super(VideoZoomState.none);
}

/// Where [BoardSafeVideo] puts the video box inside its panel at scale 1:
/// size, and origin relative to the panel's top-left.
({double width, double height, double left, double top}) boardSafeVideoBox({
  required double sourceWidth,
  required double sourceHeight,
  required double panelWidth,
  required double panelHeight,
  double topInset = 0,
}) {
  final areaH = math.max(0.0, panelHeight - topInset);
  final scale = math.min(panelWidth, areaH) / math.min(sourceWidth, sourceHeight);
  final w = sourceWidth * scale, h = sourceHeight * scale;
  return (
    width: w,
    height: h,
    left: (panelWidth - w) / 2,
    top: topInset + (areaH - h) / 2,
  );
}

/// The translation (in the video box's own pixels) that goes with a [scale]
/// about the focus point so that the focus stays put on screen AND the
/// scaled video keeps covering the panel — a dart in the double ring must
/// never pull a black band into view. [boxLeft]/[boxTop] is where the box
/// sits in the panel at scale 1 (see [boardSafeVideoBox]).
///
/// Per axis, with the box at origin o, size b, in a panel of size p:
/// scaling about F maps a box point P to P·s + F·(1 − s), so "keep F still"
/// is a translation of F·(1 − s), then clamped so the scaled box covers
/// [0, p]. While the scaled box is still SMALLER than the panel on an axis
/// (a square feed in a tall panel, early in the zoom-in) it glides from its
/// rest position towards the panel's centre, reaching it exactly when it
/// becomes big enough to cover — so the two regimes meet without a jump,
/// and scale 1 is the identity.
({double dx, double dy}) videoZoomTranslation({
  required double scale,
  required double focusX,
  required double focusY,
  required double boxWidth,
  required double boxHeight,
  required double panelWidth,
  required double panelHeight,
  required double boxLeft,
  required double boxTop,
}) {
  double axis(double focus, double box, double panel, double origin) {
    final scaled = box * scale;
    if (scaled >= panel) {
      final wanted = focus * box * (1 - scale);
      final minT = panel - origin - scaled; // right/bottom edge ≥ panel edge
      final maxT = -origin; // left/top edge ≤ 0
      return wanted.clamp(math.min(minT, maxT), maxT);
    }
    // scaled < panel ⇒ box < panel (scale ≥ 1): glide towards the centre.
    final k = ((scale - 1) / (panel / box - 1)).clamp(0.0, 1.0);
    return k * ((panel - scaled) / 2 - origin);
  }

  return (
    dx: axis(focusX, boxWidth, panelWidth, boxLeft),
    dy: axis(focusY, boxHeight, panelHeight, boxTop),
  );
}

/// Fits a video into its box so that the largest CENTERED SQUARE of the source
/// is always fully visible, and everything outside it fills the box as far as
/// it goes.
///
/// The two stock fits both fail this screen. `cover` cut the dartboard off as
/// soon as the sender's orientation and the panel's disagreed. `contain` keeps
/// every pixel but pays for a portrait feed in a landscape panel with half the
/// panel in black bars, and the board ends up tiny (2026-08-14). What actually
/// has to survive is the board: a centred circle. The square that inscribes it
/// is therefore the invariant, and the rest of the frame — ceiling, floor,
/// wall — is croppable.
///
/// The scale is always between contain's and cover's, and it IS cover whenever
/// the source and the box lean the same way. So every same-orientation case
/// (portrait feed in the portrait panel, landscape feed in the landscape
/// panel) is pixel-for-pixel what it was before.
///
/// A sender that crops on its board (2026-09-06) streams a SQUARE: the rule
/// then shows it whole, at the panel's short side, with the panel's own
/// background on the two sides it does not fill — the same picture in
/// portrait and in landscape. The box is laid out at its exact size on
/// purpose (a Positioned child, never an OverflowBox inheriting the panel's
/// tight minimums): the first device build showed the square stretched to
/// the panel and `cover` then cropping the board's sides.
///
/// [topInset] keeps the fitted box below the panel's badge row so the top of
/// the board is never under the live badge and the controls.
///
/// [zoom], when given, is the opponent-turn dart zoom: the video is scaled
/// about the focus point (see [videoZoomTranslation]).
class BoardSafeVideo extends StatelessWidget {
  /// Displayed size of the video source, in whatever unit — only the ratio and
  /// which side is shorter matter.
  final double sourceWidth;
  final double sourceHeight;
  final Widget child;
  final ValueListenable<VideoZoomState>? zoom;
  final double topInset;

  const BoardSafeVideo({
    super.key,
    required this.sourceWidth,
    required this.sourceHeight,
    required this.child,
    this.zoom,
    this.topInset = 0,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final boxW = constraints.maxWidth;
        final boxH = constraints.maxHeight;
        // Unbounded or not-yet-known: nothing to compute, let the child fit
        // itself rather than render at a garbage scale.
        if (!boxW.isFinite ||
            !boxH.isFinite ||
            boxW <= 0 ||
            boxH <= 0 ||
            sourceWidth <= 0 ||
            sourceHeight <= 0) {
          return child;
        }
        final box = boardSafeVideoBox(
          sourceWidth: sourceWidth,
          sourceHeight: sourceHeight,
          panelWidth: boxW,
          panelHeight: boxH,
          topInset: topInset,
        );
        final zoom = this.zoom;
        return ClipRect(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: box.left,
                top: box.top,
                width: box.width,
                height: box.height,
                child: zoom == null
                    ? child
                    : _ZoomedVideo(
                        zoom: zoom,
                        videoWidth: box.width,
                        videoHeight: box.height,
                        boxLeft: box.left,
                        boxTop: box.top,
                        panelWidth: boxW,
                        panelHeight: boxH,
                        child: child,
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ZoomedVideo extends StatelessWidget {
  final ValueListenable<VideoZoomState> zoom;
  final double videoWidth;
  final double videoHeight;
  final double boxLeft;
  final double boxTop;
  final double panelWidth;
  final double panelHeight;
  final Widget child;

  const _ZoomedVideo({
    required this.zoom,
    required this.videoWidth,
    required this.videoHeight,
    required this.boxLeft,
    required this.boxTop,
    required this.panelWidth,
    required this.panelHeight,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<VideoZoomState>(
      valueListenable: zoom,
      // The video stays the same widget in the same slot whatever the zoom
      // does (an identity transform when idle): re-parenting a platform
      // texture view on every dart is exactly the flicker to avoid.
      child: child,
      builder: (context, z, video) {
        final t = videoZoomTranslation(
          scale: z.scale,
          focusX: z.focusX,
          focusY: z.focusY,
          boxWidth: videoWidth,
          boxHeight: videoHeight,
          panelWidth: panelWidth,
          panelHeight: panelHeight,
          boxLeft: boxLeft,
          boxTop: boxTop,
        );
        return Transform(
          transform: Matrix4.identity()
            ..translateByDouble(t.dx, t.dy, 0, 1)
            ..scaleByDouble(z.scale, z.scale, 1, 1),
          child: video,
        );
      },
    );
  }
}
