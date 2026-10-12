import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/stats_impacts.dart';
import '../../../utils/app_theme.dart';
import '../../../widgets/impact_board.dart';
import 'stats_widgets.dart';

/// Two boards side by side: where the darts land while scoring, and where they
/// land when a double is on. The same two phases the level card splits the
/// average into, shown as the grouping behind each figure.
///
/// [self] only changes the card's label ("your" / "their" impacts).
class ImpactsCard extends StatelessWidget {
  final StatsImpacts impacts;
  final bool self;

  const ImpactsCard({super.key, required this.impacts, required this.self});

  static const double _gap = 22;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final trebles = impacts.scoring.where((d) => d.good).length;
    final hits = impacts.doubles.where((d) => d.good).length;

    return StatsCard(
      label: self ? l10n.impactsYours : l10n.impactsTheirs,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final size = ((constraints.maxWidth - _gap) / 2).floorToDouble();
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Board(
                  size: size,
                  impacts: impacts.scoring,
                  title: l10n.impactsScoring,
                  caption: impacts.scoring.isEmpty
                      ? l10n.impactsNone
                      : l10n.impactsTrebles(trebles, impacts.scoring.length),
                ),
                const SizedBox(width: _gap),
                _Board(
                  size: size,
                  impacts: impacts.doubles,
                  title: l10n.impactsDoubles,
                  caption: impacts.doubles.isEmpty
                      ? l10n.impactsNone
                      : l10n.impactsDoublesHit(hits, impacts.doubles.length),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _Board extends StatelessWidget {
  final double size;
  final List<DartImpact> impacts;
  final String title;
  final String caption;

  const _Board({
    required this.size,
    required this.impacts,
    required this.title,
    required this.caption,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SizedBox(
      width: size,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ImpactBoard(
            impacts: impacts,
            size: size,
            semanticsLabel: '$title, $caption',
            replayHint: l10n.impactsReplay,
          ),
          const SizedBox(height: 10),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            caption,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.caption,
          ),
        ],
      ),
    );
  }
}
