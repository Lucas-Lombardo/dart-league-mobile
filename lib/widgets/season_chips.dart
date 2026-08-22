import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/season.dart';
import '../utils/app_theme.dart';

/// `S0 · S1 EN COURS · S2 🔒` + the Friends icon on the right — replaces
/// the old Global | Friends toggle on the Rankings tab. Closed seasons open
/// their frozen ladder, the active one its live ladder; the scheduled one
/// is locked until it starts.
class SeasonChips extends StatelessWidget {
  final List<Season> seasons;
  /// The season whose ladder is shown (ignored while [friendsOnly]).
  final int? selectedNumber;
  final bool friendsOnly;
  final ValueChanged<int> onSeasonSelected;
  final VoidCallback onFriendsSelected;

  const SeasonChips({
    super.key,
    required this.seasons,
    required this.selectedNumber,
    required this.friendsOnly,
    required this.onSeasonSelected,
    required this.onFriendsSelected,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final ordered = [...seasons]..sort((a, b) => a.number.compareTo(b.number));

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: Row(
                children: [
                  for (final season in ordered) ...[
                    _SeasonChip(
                      season: season,
                      selected: !friendsOnly && season.number == selectedNumber,
                      label: l10n.seasonShort(season.number),
                      inProgressLabel: l10n.seasonInProgressCaps,
                      onTap: season.isScheduled
                          ? null
                          : () => onSeasonSelected(season.number),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          _IconChip(
            icon: Icons.people_outline,
            selected: friendsOnly,
            tooltip: l10n.friends,
            onTap: onFriendsSelected,
          ),
        ],
      ),
    );
  }
}

class _SeasonChip extends StatelessWidget {
  final Season season;
  final bool selected;
  final String label;
  final String inProgressLabel;
  final VoidCallback? onTap;

  const _SeasonChip({
    required this.season,
    required this.selected,
    required this.label,
    required this.inProgressLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textStyle = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: selected ? Colors.white : AppTheme.textSecondary,
    );

    Widget child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (season.isClosed) ...[
          Icon(
            Icons.inventory_2_outlined,
            size: 14,
            color: selected ? Colors.white : AppTheme.textSecondary,
          ),
          const SizedBox(width: 6),
        ],
        Text(label, style: textStyle),
        if (season.isActive) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: selected
                  ? Colors.white.withValues(alpha: 0.2)
                  : AppTheme.primary.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              inProgressLabel,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : AppTheme.primary,
              ),
            ),
          ),
        ],
        if (season.isScheduled) ...[
          const SizedBox(width: 6),
          const Icon(Icons.lock_outline, size: 13, color: AppTheme.textSecondary),
        ],
      ],
    );

    final padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 7);
    if (season.isScheduled) {
      // Dashed outline, not tappable: it has not started yet.
      child = CustomPaint(
        painter: _DashedRRectPainter(
          color: AppTheme.textSecondary.withValues(alpha: 0.5),
          radius: 10,
        ),
        child: Padding(padding: padding, child: child),
      );
      return Semantics(button: false, child: child);
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Ink(
          padding: padding,
          decoration: BoxDecoration(
            color: selected ? AppTheme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: selected
                ? null
                : Border.all(color: AppTheme.surfaceLight.withValues(alpha: 0.8)),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: AppTheme.primary.withValues(alpha: 0.4),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: child,
        ),
      ),
    );
  }
}

class _IconChip extends StatelessWidget {
  final IconData icon;
  final bool selected;
  final String tooltip;
  final VoidCallback onTap;

  const _IconChip({
    required this.icon,
    required this.selected,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: selected ? AppTheme.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: selected
                  ? null
                  : Border.all(color: AppTheme.surfaceLight.withValues(alpha: 0.8)),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: AppTheme.primary.withValues(alpha: 0.4),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: Icon(
              icon,
              size: 17,
              color: selected ? Colors.white : AppTheme.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// Dashed rounded rectangle (Flutter has no dashed BorderStyle).
class _DashedRRectPainter extends CustomPainter {
  final Color color;
  final double radius;
  final double dash;
  final double gap;
  final double strokeWidth;

  const _DashedRRectPainter({
    required this.color,
    required this.radius,
    this.dash = 4,
    this.gap = 3,
    this.strokeWidth = 1,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    final rect = Rect.fromLTWH(
      strokeWidth / 2,
      strokeWidth / 2,
      size.width - strokeWidth,
      size.height - strokeWidth,
    );
    final path = Path()..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
    for (final metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final end = (distance + dash).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRRectPainter old) =>
      old.color != color || old.radius != radius;
}

/// Exposed for the seasons screen's upcoming poster.
class DashedRRectBorder extends StatelessWidget {
  final Widget child;
  final Color color;
  final double radius;
  final double strokeWidth;

  const DashedRRectBorder({
    super.key,
    required this.child,
    required this.color,
    required this.radius,
    this.strokeWidth = 1.5,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedRRectPainter(
        color: color,
        radius: radius,
        dash: 6,
        gap: 5,
        strokeWidth: strokeWidth,
      ),
      child: child,
    );
  }
}
