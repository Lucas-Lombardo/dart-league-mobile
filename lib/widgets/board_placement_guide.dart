import 'package:flutter/material.dart';

import '../utils/app_theme.dart';

/// Which way the user should move/aim the phone (side of the frame where the
/// board currently sits). Null = no direction to show.
enum GuideDirection { left, right, up, down }

/// State of the placement guide: grey (board cut / not found) → amber
/// (centering / servo sizing) → green lock.
enum GuideState { searching, cut, offCenter, sizing, locked }

/// Camera-placement guide overlay: big pulsing double-chevrons on the frame
/// edge pointing at the board when it sticks out or sits off-center, and a
/// prominent status label telling the user to put the board in the middle of
/// the screen. Pure guidance — decisions come from BoardFraming upstream.
class BoardPlacementGuide extends StatefulWidget {
  final GuideState state;
  final GuideDirection? direction;
  final String statusText;

  const BoardPlacementGuide({
    super.key,
    required this.state,
    required this.statusText,
    this.direction,
  });

  @override
  State<BoardPlacementGuide> createState() => _BoardPlacementGuideState();
}

class _BoardPlacementGuideState extends State<BoardPlacementGuide>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locked = widget.state == GuideState.locked;
    return Stack(
      children: [
        if (widget.direction != null && !locked)
          _Chevron(direction: widget.direction!, pulse: _pulse),

        // ── Status label (bottom center) — the single source of guidance ──
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
                  if (widget.state == GuideState.sizing) ...[
                    const SizedBox(
                      width: 13,
                      height: 13,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.accent,
                      ),
                    ),
                    const SizedBox(width: 9),
                  ] else if (locked) ...[
                    const Icon(Icons.check_circle,
                        color: AppTheme.success, size: 17),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: Text(
                      widget.statusText.toUpperCase(),
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

/// Big pulsing double-chevron hugging the frame edge the board sits on.
class _Chevron extends StatelessWidget {
  final GuideDirection direction;
  final Animation<double> pulse;

  const _Chevron({required this.direction, required this.pulse});

  @override
  Widget build(BuildContext context) {
    final icon = switch (direction) {
      GuideDirection.left => Icons.keyboard_double_arrow_left,
      GuideDirection.right => Icons.keyboard_double_arrow_right,
      GuideDirection.up => Icons.keyboard_double_arrow_up,
      GuideDirection.down => Icons.keyboard_double_arrow_down,
    };
    final child = FadeTransition(
      opacity: Tween(begin: 0.35, end: 1.0).animate(pulse),
      child: ScaleTransition(
        scale: Tween(begin: 0.9, end: 1.08).animate(pulse),
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: AppTheme.gameBackground.withValues(alpha: 0.55),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: AppTheme.accent, size: 54, shadows: const [
            Shadow(color: Colors.black87, blurRadius: 8),
          ]),
        ),
      ),
    );
    return switch (direction) {
      GuideDirection.left => Positioned(
          left: 6, top: 0, bottom: 0, child: Center(child: child)),
      GuideDirection.right => Positioned(
          right: 6, top: 0, bottom: 0, child: Center(child: child)),
      GuideDirection.up => Positioned(
          top: 6, left: 0, right: 0, child: Center(child: child)),
      GuideDirection.down => Positioned(
          bottom: 52, left: 0, right: 0, child: Center(child: child)),
    };
  }
}
