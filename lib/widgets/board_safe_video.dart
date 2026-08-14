import 'dart:math' as math;

import 'package:flutter/widgets.dart';

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
class BoardSafeVideo extends StatelessWidget {
  /// Displayed size of the video source, in whatever unit — only the ratio and
  /// which side is shorter matter.
  final double sourceWidth;
  final double sourceHeight;
  final Widget child;

  const BoardSafeVideo({
    super.key,
    required this.sourceWidth,
    required this.sourceHeight,
    required this.child,
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
        final scale =
            math.min(boxW, boxH) / math.min(sourceWidth, sourceHeight);
        return ClipRect(
          child: OverflowBox(
            maxWidth: double.infinity,
            maxHeight: double.infinity,
            child: SizedBox(
              width: sourceWidth * scale,
              height: sourceHeight * scale,
              child: child,
            ),
          ),
        );
      },
    );
  }
}
