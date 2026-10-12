import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/stats_summary.dart';
import '../../../utils/app_theme.dart';
import 'stats_widgets.dart';

/// Success on each double, most played first. The single most actionable card
/// of the page: the double you miss most is the one to go and practise tonight.
///
/// Bars are relative to the best double of the list, not to 100 % — nobody
/// hits doubles at 100 %, and a fixed ceiling would flatten every row.
class DoubleLadderCard extends StatelessWidget {
  final List<StatsRate> doubles;

  /// Rows shown. The list is ordered by attempts, so the cut drops the doubles
  /// the player rarely shoots at.
  final int? limit;

  const DoubleLadderCard({super.key, required this.doubles, this.limit});

  String _num(double value) =>
      value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final rows = limit == null ? doubles : doubles.take(limit!).toList();
    if (rows.isEmpty) return const SizedBox.shrink();

    final pcts = rows.map((r) => r.pct);
    final best = pcts.reduce((a, b) => a > b ? a : b);
    final worst = pcts.reduce((a, b) => a < b ? a : b);

    // Highlights the strongest and weakest rows. With fewer than three rows,
    // or all of them equal, there is no best and no worst worth colouring.
    Color colorOf(StatsRate rate) {
      if (rows.length < 3 || best == worst) return AppTheme.primary;
      if (rate.pct == best) return AppTheme.success;
      if (rate.pct == worst) return AppTheme.error;
      return AppTheme.primary;
    }

    return StatsCard(
      label: l10n.statsDoubleLadder,
      children: [
        for (final rate in rows)
          StatsBar(
            label: rate.label,
            fraction: best <= 0 ? 0 : rate.pct / best,
            value: '${_num(rate.pct)} %',
            color: colorOf(rate),
          ),
      ],
    );
  }
}
