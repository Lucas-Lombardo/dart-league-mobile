import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/player_percentiles.dart';
import '../../../utils/app_theme.dart';
import '../../../utils/rank_translation.dart';
import '../../../widgets/design_system.dart';

/// The five figures a darts player is judged on, each with where it sits among
/// comparable players.
///
/// The three-dart average leads, and the four rows under it are what explains
/// it: a player who scores at 68 and averages 60 is losing the difference on
/// the finish, and seeing "scoring" and "finishing" side by side says so
/// without a sentence. A bar's fill IS the share of the cohort beaten, so the
/// median always sits on the halfway mark.
///
/// Shared by the Stats tab and a player's page. A figure that cannot be placed
/// yet keeps its value and simply loses its bar.
class LevelCard extends StatelessWidget {
  final PlayerPercentiles data;

  const LevelCard({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final level = data.level;
    if (level == null || level.metrics.isEmpty) return const SizedBox.shrink();

    final hero = level.entry(LevelMetric.average) ?? level.metrics.first;
    final rows = level.metrics.where((m) => m.key != hero.key).toList();
    final top = level.topPercent;
    final cohort = data.cohort;
    final rank = cohort.byRank && cohort.rank != null
        ? RankTranslation.translate(l10n, cohort.rank!)
        : null;

    final beats = hero.beatsPercent;
    final heroCaption = [
      levelLabel(l10n, hero.key),
      if (beats != null)
        rank != null ? l10n.levelBeatsRank(beats, rank) : l10n.levelBeatsAll(beats),
    ].join(' · ');

    final String footnote;
    if (!level.isPlaced) {
      footnote = l10n.levelWindowOnly(cohort.windowDays);
    } else if (rank != null) {
      footnote = l10n.levelFootnoteRank(cohort.size, rank, cohort.windowDays);
    } else {
      footnote = l10n.levelFootnoteAll(cohort.size, cohort.windowDays);
    }

    return DsCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    formatLevel(hero),
                    style: AppTheme.displayLarge.copyWith(fontSize: 44, letterSpacing: -1),
                  ),
                ),
              ),
              if (top != null) ...[
                const SizedBox(width: 12),
                DsPill(label: l10n.comparisonTopPercent(top)),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text(heroCaption, style: AppTheme.caption.copyWith(height: 1.35)),
          if (hero.percentile != null) ...[
            const SizedBox(height: 10),
            _LevelBar(percentile: hero.percentile!),
          ],
          if (rows.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Divider(height: 1),
            ),
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) const SizedBox(height: 14),
              _LevelRow(entry: rows[i]),
            ],
          ],
          const SizedBox(height: 14),
          Text(footnote, style: AppTheme.caption.copyWith(height: 1.35)),
        ],
      ),
    );
  }
}

String levelLabel(AppLocalizations l10n, LevelMetric metric) => switch (metric) {
  LevelMetric.average => l10n.avgThreeDart,
  LevelMetric.first9 => l10n.levelFirst9,
  LevelMetric.scoringAverage => l10n.levelScoring,
  LevelMetric.finishingAverage => l10n.levelFinishing,
  LevelMetric.checkoutPct => l10n.levelDoubles,
};

/// One decimal throughout, so the column of figures lines up; only the doubles
/// carry a unit.
String formatLevel(LevelEntry entry) {
  final value = entry.value.toStringAsFixed(1);
  return entry.key == LevelMetric.checkoutPct ? '$value %' : value;
}

class _LevelRow extends StatelessWidget {
  final LevelEntry entry;

  const _LevelRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final beats = entry.beatsPercent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Text(
                levelLabel(l10n, entry.key),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              formatLevel(entry),
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            if (beats != null)
              // A fixed column, so the figures to its left stay aligned from
              // one row to the next whatever the percentage reads.
              SizedBox(
                width: 94,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    l10n.comparisonBeatsPercent(beats),
                    style: AppTheme.caption.copyWith(fontSize: 11),
                  ),
                ),
              ),
          ],
        ),
        if (entry.percentile != null) ...[
          const SizedBox(height: 7),
          _LevelBar(percentile: entry.percentile!),
        ],
      ],
    );
  }
}

/// Fill = share of the cohort beaten. The mark at the middle is the median,
/// and it overhangs the bar so it stays visible once the fill has passed it.
class _LevelBar extends StatelessWidget {
  final double percentile;

  const _LevelBar({required this.percentile});

  @override
  Widget build(BuildContext context) {
    final fraction = (percentile / 100).clamp(0.0, 1.0);
    return SizedBox(
      height: 12,
      child: LayoutBuilder(
        builder: (context, constraints) => Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              top: 3,
              left: 0,
              right: 0,
              child: DsProgressBar(value: fraction, height: 6),
            ),
            Positioned(
              left: constraints.maxWidth / 2 - 1,
              top: 0,
              child: Container(
                width: 2,
                height: 12,
                decoration: BoxDecoration(
                  color: AppTheme.textSecondary,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
