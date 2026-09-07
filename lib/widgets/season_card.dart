import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/season.dart';
import '../utils/app_theme.dart';
import '../utils/season_format.dart';
import 'design_system.dart';
import 'trophy_image.dart';

/// The season card of the Rankings tab: what the #1 wins, how long is left
/// and how far along the season is. A flat surface card (system D) — the
/// season number itself is carried by the chips above it.
///
/// Three states: an end date → countdown + time bar framed by the start and
/// end dates; no end date yet → "end to be announced", no bar; no season at
/// all → the caller does not render the card (older backend / error).
class SeasonCard extends StatelessWidget {
  final Season season;
  /// Time left, recomputed by the provider every minute. Null = no end set.
  final Duration? timeLeft;
  final VoidCallback? onTap;
  /// Injectable "now" for the time bar (tests).
  final DateTime? now;

  const SeasonCard({
    super.key,
    required this.season,
    this.timeLeft,
    this.onTap,
    this.now,
  });

  static const _countdownStyle = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w700,
    color: AppTheme.textPrimary,
    height: 1,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static const _dateStyle = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    color: AppTheme.textTertiary,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final today = now ?? DateTime.now();
    final start = season.startedAt;
    final end = season.endAt;
    final progress = season.progress(today);
    final title = season.hasReward ? l10n.seasonPrize : l10n.seasonN(season.number);
    final subtitle = season.hasReward ? l10n.seasonPrizeFor1st : l10n.seasonNoReward;

    return DsCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.sectionTitle,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.caption,
                    ),
                  ],
                ),
              ),
              if (season.hasReward && season.hasTrophyImage) ...[
                const SizedBox(width: 10),
                TrophyImage(
                  url: season.trophyThumbUrl,
                  size: 40,
                  fallback: const Icon(
                    Icons.emoji_events_outlined,
                    size: 24,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
              const SizedBox(width: 12),
              if (end != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.schedule_outlined,
                      size: 15,
                      color: AppTheme.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      formatSeasonCountdown(l10n, timeLeft ?? season.timeLeft(today)),
                      style: _countdownStyle,
                    ),
                  ],
                )
              else
                Text(l10n.seasonEndToBeAnnounced, style: AppTheme.caption),
            ],
          ),
          if (start != null && end != null && progress != null) ...[
            const SizedBox(height: 14),
            DsProgressBar(value: progress),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(formatSeasonDayShort(context, start), style: _dateStyle),
                const Spacer(),
                Text(formatSeasonDayShort(context, end), style: _dateStyle),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
