import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/stats_summary.dart';
import '../../../utils/app_navigator.dart';
import '../../../utils/app_theme.dart';
import '../../../utils/haptic_service.dart';
import '../../profile/match_history_screen.dart';
import 'stats_widgets.dart';

/// The four sub-tab pages. Each is a view over the same `StatsSummary`, so
/// switching tabs never touches the network, and each one puts a single number
/// at the top with the rest of the page explaining it.

String _num(double value) =>
    value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toStringAsFixed(1);

/// Highlights the strongest and weakest rows of a breakdown. Applied to both the
/// checkout bands and the double ladder so the same colour always means the same
/// thing across the Finishing page.
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

class StatsFormPage extends StatelessWidget {
  final StatsSummary summary;

  const StatsFormPage({super.key, required this.summary});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final form = summary.form;
    final children = <Widget>[];

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

    // The three headline numbers of the other sub-tabs, repeated here. The most
    // frequent visit is "where am I at", and it should cost no navigation.
    final glance = <Widget>[
      if (summary.scoring != null)
        StatsRow(label: l10n.avgThreeDart, value: _num(summary.scoring!.average)),
      if (summary.finishing != null)
        StatsRow(label: l10n.statsCheckout, value: '${_num(summary.finishing!.checkoutPct)} %'),
      if (summary.consistency?.dartsToWinLeg != null)
        StatsRow(
          label: l10n.statsDartsToWinLeg,
          value: _num(summary.consistency!.dartsToWinLeg!),
        ),
    ];
    if (glance.isNotEmpty) {
      children.add(StatsCard(label: l10n.statsAtAGlance, children: glance));
    }

    children.add(_RecordsCard(records: summary.records));
    // The old stats screen ended on this button; the Matches tab keeps it so
    // match history stays one tap from where a player reads their numbers.
    children.add(const _MatchHistoryButton());
    return _PageBody(children: children);
  }

  Widget _divider() => Container(width: 1, height: 38, color: AppTheme.surfaceLight);
}

class StatsScoringPage extends StatelessWidget {
  final StatsSummary summary;

  const StatsScoringPage({super.key, required this.summary});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scoring = summary.scoring;
    if (scoring == null) return _PageBody(children: [StatsBlockEmpty(l10n.statsNoDataForFilter)]);

    final maxCount = scoring.buckets.fold<int>(0, (m, b) => b.count > m ? b.count : m);

    return _PageBody(
      children: [
        StatsCard(
          children: [
            StatsHero(value: _num(scoring.average), caption: l10n.avgThreeDart),
            const SizedBox(height: 10),
            if (scoring.first9 != null)
              StatsRow(label: l10n.statsFirstNine, value: _num(scoring.first9!)),
            if (scoring.trebleTwentyRate != null)
              StatsRow(
                label: l10n.statsTrebleTwentyRate,
                value: '${_num(scoring.trebleTwentyRate!)} %',
              ),
            if (scoring.bestVisit > 0)
              StatsRow(
                label: l10n.statsBestVisit,
                value: '${scoring.bestVisit}',
                valueColor: AppTheme.gold,
              ),
          ],
        ),
        if (scoring.buckets.isNotEmpty)
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
        StatsExplainer(title: l10n.statsHowCalculated, body: l10n.statsAverageExplainer),
      ],
    );
  }
}

class StatsFinishingPage extends StatelessWidget {
  final StatsSummary summary;

  const StatsFinishingPage({super.key, required this.summary});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final finishing = summary.finishing;
    if (finishing == null) return _PageBody(children: [StatsBlockEmpty(l10n.statsNoDataForFilter)]);

    // Both breakdowns are scaled to their own best row rather than to 100 %:
    // at these rates a fixed ceiling would leave every bar nearly empty.
    double scale(List<StatsRate> rates, StatsRate rate) {
      final best = rates.map((r) => r.pct).reduce((a, b) => a > b ? a : b);
      return best <= 0 ? 0 : rate.pct / best;
    }

    return _PageBody(
      children: [
        StatsCard(
          children: [
            StatsHero(
              value: _num(finishing.checkoutPct),
              unit: '%',
              caption: l10n.statsCheckoutAttempts(finishing.hits, finishing.attempts),
            ),
            const SizedBox(height: 10),
            if (finishing.best != null)
              StatsRow(
                label: l10n.bestCheckout,
                value: '${finishing.best}',
                valueColor: AppTheme.gold,
              ),
            if (finishing.average != null)
              StatsRow(label: l10n.avgCheckout, value: _num(finishing.average!)),
          ],
        ),
        if (finishing.bands.isNotEmpty)
          StatsCard(
            label: l10n.statsByRemaining,
            children: [
              for (final band in finishing.bands)
                StatsBar(
                  label: band.label.replaceAll('-', '–'),
                  fraction: scale(finishing.bands, band),
                  value: '${_num(band.pct)} %',
                  color: _rateColor(band, finishing.bands),
                ),
            ],
          ),
        if (finishing.doubles.isNotEmpty)
          StatsCard(
            label: l10n.statsDoubleLadder,
            children: [
              for (final rate in finishing.doubles)
                StatsBar(
                  label: rate.label,
                  fraction: scale(finishing.doubles, rate),
                  value: '${_num(rate.pct)} %',
                  color: _rateColor(rate, finishing.doubles),
                ),
            ],
          ),
        StatsExplainer(title: l10n.statsHowCalculated, body: l10n.statsCheckoutExplainer),
      ],
    );
  }
}

class StatsConsistencyPage extends StatelessWidget {
  final StatsSummary summary;

  const StatsConsistencyPage({super.key, required this.summary});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final consistency = summary.consistency;
    if (consistency == null) {
      return _PageBody(children: [StatsBlockEmpty(l10n.statsNoDataForFilter)]);
    }

    return _PageBody(
      children: [
        StatsCard(
          children: [
            if (consistency.dartsToWinLeg != null)
              StatsHero(
                value: _num(consistency.dartsToWinLeg!),
                caption: l10n.statsDartsToWinLeg,
              )
            else
              // Plain text, not a StatsBlockEmpty: that widget is itself a card
              // and would nest one inside another.
              Text(
                l10n.statsNoRecordsYet,
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 13,
                  height: 1.45,
                ),
              ),
            const SizedBox(height: 10),
            if (consistency.bestLeg != null)
              StatsRow(
                label: l10n.statsBestLeg,
                value: l10n.statsDartsUnit('${consistency.bestLeg}'),
                valueColor: AppTheme.gold,
              ),
            if (consistency.bustRate != null)
              StatsRow(
                label: l10n.statsBustRate,
                value: '${_num(consistency.bustRate!)} %',
                valueColor: AppTheme.error,
              ),
          ],
        ),
      ],
    );
  }
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

  const _RecordsCard({required this.records});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (records.isEmpty) {
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
