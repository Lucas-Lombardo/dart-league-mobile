import 'package:flutter/material.dart';

import '../utils/app_theme.dart';

/// Framing state of the setup camera: grey (board not found / cut) → amber
/// (zoom in / zoom out instruction) → green lock. Zoom is the only guidance —
/// position checks nagged users to "move" on Android's sensor-oriented
/// frames and were dropped.
enum GuideState { searching, cut, tooFar, tooClose, locked }

/// Status pill overlay for the camera-setup preview: one clear instruction
/// per state, bottom center. Pure display — decisions come from the
/// projected-circle framing (BoardFraming) upstream.
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
    return Stack(
      children: [
        Positioned(
          left: 16,
          right: 16,
          bottom: 14,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.gameBackground.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: locked ? AppTheme.success : AppTheme.accent,
                  width: 1.4,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (locked) ...[
                    const Icon(Icons.check_circle,
                        color: AppTheme.success, size: 17),
                    const SizedBox(width: 8),
                  ] else if (state == GuideState.tooFar) ...[
                    const Icon(Icons.zoom_in,
                        color: AppTheme.accent, size: 17),
                    const SizedBox(width: 8),
                  ] else if (state == GuideState.tooClose) ...[
                    const Icon(Icons.zoom_out,
                        color: AppTheme.accent, size: 17),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: Text(
                      statusText.toUpperCase(),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: locked ? AppTheme.success : AppTheme.accent,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
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
