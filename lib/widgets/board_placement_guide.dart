import 'package:flutter/material.dart';

import '../utils/app_theme.dart';
import 'design_system.dart';

/// Framing state of the setup camera: quiet (board not found / cut / zoom
/// in / zoom out instruction) → green lock. Zoom is the only guidance —
/// position checks nagged users to "move" on Android's sensor-oriented
/// frames and were dropped.
enum GuideState { searching, cut, tooFar, tooClose, locked }

/// Status pill overlay for the camera-setup preview: one clear instruction
/// per state, bottom center. Pure display — decisions come from the
/// projected-circle framing (BoardFraming) upstream.
///
/// System D look: 34 px pill on the page background at 92 %, 13 / 700
/// sentence-case label. Locked = success border + text + check; every
/// adjusting state = hairline border + secondary text (no amber).
class BoardPlacementGuide extends StatelessWidget {
  final GuideState state;
  final String statusText;

  const BoardPlacementGuide({
    super.key,
    required this.state,
    required this.statusText,
  });

  @override
  Widget build(BuildContext context) {
    final locked = state == GuideState.locked;
    final color = locked ? AppTheme.success : AppTheme.textSecondary;
    final IconData? icon = switch (state) {
      GuideState.locked => Icons.check_rounded,
      GuideState.tooFar => Icons.zoom_in_rounded,
      GuideState.tooClose => Icons.zoom_out_rounded,
      _ => null,
    };
    return Stack(
      children: [
        Positioned(
          left: 16,
          right: 16,
          bottom: 14,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: AppTheme.background.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: locked
                      ? AppTheme.success.withValues(alpha: 0.5)
                      : Colors.white.withValues(alpha: 0.14),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, color: color, size: 16),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: Text(
                      dsSentence(statusText),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: color,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        height: 1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
