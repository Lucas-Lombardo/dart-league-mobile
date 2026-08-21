import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/stats_summary.dart';
import '../../../utils/app_navigator.dart';
import '../../../utils/app_theme.dart';
import '../../../utils/haptic_service.dart';
import '../../profile/match_history_screen.dart';
import 'comparison_section.dart';
import 'stats_widgets.dart';

/// The stats page: one scroll, no sub-tabs.
///
/// It reads top-down as one argument. The standing comes first — where the
/// player sits among comparable players — because "is that good" is the
/// question none of their own figures can answer. Then their form, their
/// record, and the two breakdowns that tell them what to actually practise.
///
/// The four sub-tabs this replaces split the same figures across screens
/// nobody visited, and repeated the three headline numbers on the landing one
/// for want of anything better to put there.

String _num(double value) =>
    value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toStringAsFixed(1);

/// Highlights the strongest and weakest rows of a breakdown, so the same colour
/// always means the same thing.
Color _rateColor(StatsRate rate, List<StatsRate> all) {
  if (all.length < 3) return AppTheme.primary;
  final pcts = all.map((r) => r.pct);
  final best = pcts.reduce((a, b) => a > b ? a : b);
  final worst = pcts.reduce((a, b) => a < b ? a : b);
  // All equal means there is no best and no worst — colouring every row green
  // would claim a strength that isn't there.
  if (best == worst) return AppTheme.primary;
  if (rate.pct == best) return AppTheme.success;
  if (rate.pct == worst) return AppTheme.error;
  return AppTheme.primary;
}

class StatsOverviewPage extends StatelessWidget {
  final StatsSummary summary;

  /// Sits between the standing and the filtered figures — the filter above it
  /// governs everything below and nothing above.
  final Widget filterBar;

  const StatsOverviewPage({
    super.key,
    required this.summary,
    required this.filterBar,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final children = <Widget>[
      // Unfiltered: the standing is drawn from its own 90-day window, which is
      // why it sits ABOVE the filter rather than under it.
      const ComparisonSection(),
      filterBar,
    ];

    final form = summary.form;
    if (form != null) {
      children.add(
        StatsCard(
          label: l10n.statsLastNLegs(form.sampleLegs),
          children: [
            StatsHero(
              value: _num(form.average),
              caption: form.previousAverage != null
                  ? l10n.statsPreviousBlock(_num(form.previousAverage!))
                  : l10n.avgThreeDart,
              trailing: form.delta != null ? StatsDelta(form.delta!) : null,
            ),
            const SizedBox(height: 14),
            if (form.hasCurve)
              StatsCurve(points: form.curve, baseline: form.previousAverage)
            else
              _UnlockCurve(remaining: form.legsUntilCurve),
          ],
        ),
      );
    }

    final record = summary.record;
    if (record != null) {
      children.add(
        StatsCard(
          children: [
            Row(
              children: [
                Expanded(child: _Tally(label: l10n.wins, value: '${record.wins}', color: AppTheme.success)),
                _divider(),
                Expanded(child: _Tally(label: l10n.losses, value: '${record.losses}', color: AppTheme.error)),
                _divider(),
                Expanded(
                  child: _Tally(
                    label: l10n.winRate,
                    value: '${_num(record.winRate)} %',
                    color: AppTheme.primary,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    // The two breakdowns worth keeping. Everything else the old sub-tabs held
    // — first nine, treble-20 rate, darts to win a leg, bust rate — is already
    // on the standing above, WITH what it is worth against other players.
    final scoring = summary.scoring;
    if (scoring != null && scoring.buckets.isNotEmpty) {
      final maxCount = scoring.buckets.fold<int>(0, (m, b) => b.count > m ? b.count : m);
      children.add(
        StatsCard(
          label: l10n.statsVisitBreakdown(scoring.totalVisits),
          children: [
            for (final bucket in scoring.buckets)
              StatsBar(
                label: bucket.label,
                fraction: maxCount == 0 ? 0 : bucket.count / maxCount,
                value: '${bucket.count}',
                color: switch (bucket.label) {
                  '180' => AppTheme.gold,
                  '<60' => AppTheme.error,
                  _ => AppTheme.primary,
                },
              ),
          ],
        ),
      );
    }

    // The single most actionable card in the app: the double you miss most is
    // the one to go and practise tonight.
    final finishing = summary.finishing;
    if (finishing != null && finishing.doubles.isNotEmpty) {
      final best = finishing.doubles.map((r) => r.pct).reduce((a, b) => a > b ? a : b);
      children.add(
        StatsCard(
          label: l10n.statsDoubleLadder,
          children: [
            for (final rate in finishing.doubles)
              StatsBar(
                label: rate.label,
                fraction: best <= 0 ? 0 : rate.pct / best,
                value: '${_num(rate.pct)} %',
                color: _rateColor(rate, finishing.doubles),
              ),
          ],
        ),
      );
    }

    children.add(
      _RecordsCard(
        records: summary.records,
        bestVisit: scoring != null && scoring.bestVisit > 0 ? scoring.bestVisit : null,
      ),
    );
    children.add(const _MatchHistoryButton());
    children.add(
      StatsExplainer(title: l10n.statsHowCalculated, body: l10n.statsAverageExplainer),
    );
    return _PageBody(children: children);
  }

  Widget _divider() => Container(width: 1, height: 38, color: AppTheme.surfaceLight);
}

class _MatchHistoryButton extends StatelessWidget {
  const _MatchHistoryButton();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ElevatedButton.icon(
      onPressed: () {
        HapticService.lightImpact();
        AppNavigator.toScreen(context, const MatchHistoryScreen());
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: AppTheme.surfaceLight,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 18),
      ),
      icon: const Icon(Icons.history_rounded),
      label: Text(l10n.viewFullMatchHistory),
    );
  }
}

class _PageBody extends StatelessWidget {
  final List<Widget> children;

  const _PageBody({required this.children});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
      itemCount: children.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) => children[index],
    );
  }
}

class _UnlockCurve extends StatelessWidget {
  final int remaining;

  const _UnlockCurve({required this.remaining});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // 5 legs is the threshold the backend uses; a two-point curve says nothing.
    final progress = remaining <= 0 ? 1.0 : ((5 - remaining) / 5).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: Stack(
            children: [
              Container(height: 8, color: AppTheme.surfaceLight.withValues(alpha: 0.45)),
              FractionallySizedBox(
                widthFactor: progress,
                child: Container(height: 8, color: AppTheme.primary),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.statsUnlockCurve(remaining),
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12, height: 1.4),
        ),
      ],
    );
  }
}

class _Tally extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _Tally({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label.toUpperCase(),
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 5),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: color),
          ),
        ),
      ],
    );
  }
}

class _RecordsCard extends StatelessWidget {
  final List<StatsRecord> records;

  /// Highest single visit of the window. It carries no opponent or date — the
  /// backend reports it as an aggregate, not as a dated record — so it rides
  /// here as a plain row rather than pretending to be one.
  final int? bestVisit;

  const _RecordsCard({required this.records, this.bestVisit});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (records.isEmpty && bestVisit == null) {
      return StatsCard(
        label: l10n.statsRecords,
        children: [
          Text(
            l10n.statsNoRecordsYet,
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.45),
          ),
        ],
      );
    }

    return StatsCard(
      label: l10n.statsRecords,
      children: [
        for (var i = 0; i < records.length; i++) ...[
          if (i > 0) const Divider(height: 18, color: AppTheme.surfaceLight),
          _RecordLine(record: records[i]),
        ],
        if (bestVisit != null) ...[
          if (records.isNotEmpty) const Divider(height: 18, color: AppTheme.surfaceLight),
          StatsRow(
            label: l10n.statsBestVisit,
            value: '$bestVisit',
            valueColor: AppTheme.gold,
          ),
        ],
      ],
    );
  }
}

class _RecordLine extends StatelessWidget {
  final StatsRecord record;

  const _RecordLine({required this.record});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final title = switch (record.key) {
      StatsRecordKey.bestCheckout => l10n.statsRecordBestCheckout,
      StatsRecordKey.bestLeg => l10n.statsRecordBestLeg,
      StatsRecordKey.bestLegAverage => l10n.statsRecordBestLegAverage,
      StatsRecordKey.longestWinStreak => l10n.statsRecordLongestStreak,
      StatsRecordKey.unknown => '',
    };
    if (title.isEmpty) return const SizedBox.shrink();

    final value = switch (record.key) {
      StatsRecordKey.bestLeg => l10n.statsDartsUnit(_num(record.value)),
      StatsRecordKey.longestWinStreak => '${_num(record.value)} ${l10n.wins.toLowerCase()}',
      _ => _num(record.value),
    };

    // A record only becomes tellable once it carries a date and a name.
    final subtitle = [
      if (record.opponentUsername != null) l10n.statsVersus(record.opponentUsername!),
      if (record.playedAt != null) _formatDate(record.playedAt!),
    ].join(' · ');

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(color: Colors.white, fontSize: 14)),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 12),
        Text(
          value,
          style: const TextStyle(
            color: AppTheme.gold,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}
