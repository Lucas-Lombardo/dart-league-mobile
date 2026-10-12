import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/player_percentiles.dart';
import '../../../services/stats_service.dart';
import '../../../utils/app_theme.dart';
import '../../../widgets/design_system.dart';
import 'level_card.dart';
import 'stats_widgets.dart';

/// Where the player stands among comparable players — the top of the Stats
/// screen.
///
/// Every other block on that screen answers "what are my numbers"; this one
/// answers "is that good", which a number on its own never settles. So nothing
/// here is shown without the cohort it was measured against: the level card
/// names it twice, and the backend widens the cohort from the player's rank to
/// everyone whenever that rank holds too few players to draw a percentile from.
///
/// Loads on its own rather than through the Matches tab's single request: the
/// standing comes from nightly snapshots, on a different cadence and a
/// different window than the filter bar above it, and folding it into that
/// request would tie a 90-day figure to a filter that reads "30 days ranked".
class ComparisonSection extends StatefulWidget {
  const ComparisonSection({super.key});

  @override
  State<ComparisonSection> createState() => _ComparisonSectionState();
}

class _ComparisonSectionState extends State<ComparisonSection> {
  PlayerPercentiles? _data;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await StatsService.getPercentiles();
      if (!mounted) return;
      setState(() => _data = data);
    } catch (_) {
      // A standing is the best thing on this page, never the reason it exists:
      // if the request fails the rest of the stats still render.
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    if (_failed || data == null) return const SizedBox.shrink();
    return ComparisonCards(data: data);
  }
}

/// The standing, laid out from an already-loaded response. Split from the
/// loader so it can be rendered without the network.
class ComparisonCards extends StatelessWidget {
  final PlayerPercentiles data;

  const ComparisonCards({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    // Short of legs, or no crowd to compare against yet: say so rather than
    // show five figures with nothing to measure them by.
    if (!data.eligible) return _NotEnoughLegsCard(data: data);
    return LevelCard(data: data);
  }
}

class _NotEnoughLegsCard extends StatelessWidget {
  final PlayerPercentiles data;

  const _NotEnoughLegsCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final remaining = data.legsUntilEligible;
    // Two different reasons land here and they must not be mixed. Short of
    // legs: a progress bar and how many are left. Enough legs but no crowd to
    // compare against yet: no bar at all — nothing is progressing, the group
    // is simply still being built.
    final waitingOnCohort = remaining <= 0;
    final progress = data.cohort.minLegs > 0
        ? (data.legs / data.cohort.minLegs).clamp(0.0, 1.0)
        : 0.0;

    return StatsCard(
      label: l10n.comparisonTitle,
      children: [
        Text(
          waitingOnCohort
              ? l10n.comparisonLegsToGo(0)
              : l10n.comparisonNotEnoughLegs,
          style: AppTheme.bodyMedium.copyWith(fontSize: 13),
        ),
        if (!waitingOnCohort) ...[
          const SizedBox(height: 14),
          DsProgressBar(value: progress, height: 6),
          const SizedBox(height: 8),
          Text(l10n.comparisonLegsToGo(remaining), style: AppTheme.caption),
        ],
      ],
    );
  }
}
