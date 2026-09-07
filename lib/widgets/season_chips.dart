import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/season.dart';
import '../utils/app_theme.dart';
import '../utils/haptic_service.dart';

/// "Saison 1 · En cours" · "Saison 0" · "🔒 Saison 2" text chips, with an
/// "All ›" link at the right end. Closed seasons open their frozen ladder,
/// the active one its live ladder; the scheduled one is locked until it
/// starts. The friends scope lives in the screen header: the row only knows
/// it through [friendsOnly] (no chip is highlighted while it is on).
class SeasonChips extends StatelessWidget {
  final List<Season> seasons;
  /// The season whose ladder is shown (ignored while [friendsOnly]).
  final int? selectedNumber;
  final bool friendsOnly;
  final ValueChanged<int> onSeasonSelected;
  /// "All ›" — opens the seasons screen. The link is hidden when null.
  final VoidCallback? onSeeAll;

  const SeasonChips({
    super.key,
    required this.seasons,
    required this.selectedNumber,
    required this.friendsOnly,
    required this.onSeasonSelected,
    this.onSeeAll,
  });

  /// The live season first, then the archive newest first, the upcoming
  /// (locked) one last.
  static List<Season> _ordered(List<Season> seasons) {
    int weight(Season s) => s.isActive ? 0 : (s.isClosed ? 1 : 2);
    final list = [...seasons];
    list.sort((a, b) {
      final w = weight(a).compareTo(weight(b));
      return w != 0 ? w : b.number.compareTo(a.number);
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final ordered = _ordered(seasons);

    return SizedBox(
      height: 32,
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < ordered.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    _SeasonChip(
                      season: ordered[i],
                      selected: !friendsOnly && ordered[i].number == selectedNumber,
                      label: ordered[i].isActive
                          ? '${l10n.seasonN(ordered[i].number)} · ${l10n.seasonInProgress}'
                          : l10n.seasonN(ordered[i].number),
                      onTap: ordered[i].isScheduled
                          ? null
                          : () => onSeasonSelected(ordered[i].number),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (onSeeAll != null) ...[
            const SizedBox(width: 10),
            _SeeAllLink(label: l10n.leaderboardAllSeasons, onTap: onSeeAll!),
          ],
        ],
      ),
    );
  }
}

/// 32 px pill. Active: tinted primary + primaryLight hairline and text;
/// inactive: surface + hairline; scheduled: locked, tertiary, not tappable.
class _SeasonChip extends StatelessWidget {
  final Season season;
  final bool selected;
  final String label;
  final VoidCallback? onTap;

  const _SeasonChip({
    required this.season,
    required this.selected,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final locked = season.isScheduled;
    final fg = selected
        ? AppTheme.primaryLight
        : (locked ? AppTheme.textTertiary : AppTheme.textSecondary);
    final background =
        selected ? AppTheme.primary.withValues(alpha: 0.14) : AppTheme.surface;
    final border =
        selected ? AppTheme.primaryLight.withValues(alpha: 0.4) : AppTheme.border;

    final content = Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.center,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (season.isClosed) ...[
            Icon(Icons.inventory_2_outlined, size: 14, color: fg),
            const SizedBox(width: 6),
          ],
          if (locked) ...[
            Icon(Icons.lock_outline_rounded, size: 14, color: fg),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: fg,
              height: 1,
            ),
          ),
        ],
      ),
    );

    return Material(
      color: background,
      shape: StadiumBorder(side: BorderSide(color: border)),
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? content
          : InkWell(
              onTap: onTap,
              child: content,
            ),
    );
  }
}

/// "Toutes ›" — 12 / 600 primaryLight link with a chevron.
class _SeeAllLink extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _SeeAllLink({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () {
        HapticService.lightImpact();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.primaryLight,
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              size: 14,
              color: AppTheme.primaryLight,
            ),
          ],
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
