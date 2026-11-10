import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../utils/app_theme.dart';
import '../../widgets/design_system.dart';
import '../../widgets/progression/progression_widgets.dart';
import '../progression/progression_format.dart';
import 'league_models.dart';
import 'league_store.dart';
import 'league_widgets.dart';

/// "Weekly league" (mockup ecrans/Ligue.dc.html): the ladder, my group's
/// standings with the promotion and relegation lines, and what scores.
class LeagueScreen extends StatefulWidget {
  const LeagueScreen({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LeagueScreen()));

  @override
  State<LeagueScreen> createState() => _LeagueScreenState();
}

class _LeagueScreenState extends State<LeagueScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) LeagueStore.instance.refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: LeagueStore.instance,
      builder: (context, _) {
        final l10n = AppLocalizations.of(context);
        final store = LeagueStore.instance;
        final s = store.visible;
        final title = s?.league == null ? l10n.leagueWeeklyTitle : l10n.leagueName(s!.league!.name.resolve(context));
        final trailing = s == null
            ? null
            : !s.inGroup
                ? null
                : s.state == LeagueWeekState.closed
                    ? l10n.leagueResultsMonday
                    : leagueEndsLabel(l10n, s.endsAt);
        return Scaffold(
          backgroundColor: AppTheme.background,
          body: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
                  child: DsScreenHeader(
                    title: title,
                    showBack: true,
                    actions: [
                      if (trailing != null && trailing.isNotEmpty)
                        Text(trailing, style: AppTheme.caption.copyWith(fontSize: 13, fontWeight: FontWeight.w700)),
                      IconButton(
                        tooltip: l10n.leagueHistoryTooltip,
                        icon: const Icon(Icons.history_rounded, color: kLeagueMuted),
                        onPressed: () => LeagueHistorySheet.show(context),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: RefreshIndicator(
                    color: AppTheme.primary,
                    onRefresh: store.refresh,
                    child: s == null
                        ? _Placeholder(failed: store.failed && !store.isLoading)
                        : ListView(
                            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                            children: [
                              LeagueLadder(ladder: s.ladder, currentId: s.league?.id),
                              const SizedBox(height: 14),
                              if (s.inGroup) ...[
                                if (s.state == LeagueWeekState.closed) ...[
                                  _Note(text: l10n.leagueClosedBody),
                                  const SizedBox(height: 10),
                                ],
                                LeagueStandingsList(group: s.group!),
                              ] else
                                _WaitingCard(snapshot: s),
                              const SizedBox(height: 14),
                              if (s.pointRules.isNotEmpty) LeagueRulesCard(rules: s.pointRules),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Placeholder extends StatelessWidget {
  final bool failed;
  const _Placeholder({required this.failed});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 80),
        if (failed) ...[
          Text(l10n.leagueLoadFailed, textAlign: TextAlign.center, style: AppTheme.bodyMedium),
          const SizedBox(height: 12),
          Center(
            child: TextButton(onPressed: LeagueStore.instance.refresh, child: Text(l10n.leagueRetry)),
          ),
        ] else
          const Center(child: CircularProgressIndicator(color: AppTheme.primary)),
      ],
    );
  }
}

class _Note extends StatelessWidget {
  final String text;
  const _Note({required this.text});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(AppTheme.radiusRow)),
        child: Text(text, style: AppTheme.bodyMedium.copyWith(fontSize: 13, color: const Color(0xFFCBD5E1))),
      );
}

/// Not in a group this week: the first league (or the next one) starts Monday.
class _WaitingCard extends StatelessWidget {
  final LeagueSnapshot snapshot;
  const _WaitingCard({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final next = snapshot.nextStartsAt;
    final now = DateTime.now();
    return DsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(leagueWaitingTitle(l10n, snapshot), style: AppTheme.titleLarge.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(
            snapshot.firstWeek ? l10n.leagueFirstBody : l10n.leagueBackBody,
            style: AppTheme.bodyMedium.copyWith(fontSize: 13, color: const Color(0xFFCBD5E1)),
          ),
          if (next != null && next.isAfter(now)) ...[
            const SizedBox(height: 10),
            Text(
              l10n.leagueStartsIn(formatRemaining(l10n, next.difference(now))),
              style: AppTheme.caption.copyWith(fontSize: 13, fontWeight: FontWeight.w700, color: kLeagueAccentSoft),
            ),
          ],
        ],
      ),
    );
  }
}

/// The standings, with the "go up" line after the promotion zone and the
/// "go down" line before the relegation zone.
class LeagueStandingsList extends StatelessWidget {
  final LeagueGroup group;
  const LeagueStandingsList({super.key, required this.group});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final rows = group.standings;
    final showUp = group.promoteTo != null && group.promoteCount > 0 && rows.length > group.promoteCount;
    final showDown = group.relegateTo != null && group.relegateCount > 0 && group.relegateFrom > 1;
    final children = <Widget>[];
    for (final r in rows) {
      if (showDown && r.position == group.relegateFrom) {
        children.add(_ZoneLine(
          up: false,
          text: l10n.leagueRelegateZone(group.relegateFrom, group.size, group.relegateTo!.name.resolve(context)),
        ));
      }
      children.add(LeagueStandingRow(standing: r));
      if (showUp && r.position == group.promoteCount) {
        children.add(_ZoneLine(up: true, text: l10n.leaguePromoteZone(group.promoteTo!.name.resolve(context))));
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }
}

class _ZoneLine extends StatelessWidget {
  final bool up;
  final String text;
  const _ZoneLine({required this.up, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      // The label keeps its natural width (up to 85 %), the rule fills the rest.
      child: LayoutBuilder(
        builder: (context, constraints) => Row(
          children: [
            if (up) ...[
              const Icon(Icons.keyboard_arrow_up_rounded, size: 16, color: AppTheme.primaryLight),
              const SizedBox(width: 6),
            ],
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.85 - (up ? 22 : 0)),
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.caption.copyWith(fontWeight: FontWeight.w700, color: up ? kLeagueAccentSoft : kLeagueMuted),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Container(height: 1, color: up ? AppTheme.primaryLight.withValues(alpha: 0.4) : AppTheme.surfaceLight),
            ),
          ],
        ),
      ),
    );
  }
}

class LeagueStandingRow extends StatelessWidget {
  final LeagueStanding standing;
  const LeagueStandingRow({super.key, required this.standing});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final me = standing.isMe;
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: me
          ? BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.primaryLight, width: 1.5),
            )
          : null,
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: Text(
              '${standing.position}',
              style: AppTheme.labelLarge.copyWith(
                fontWeight: FontWeight.w700,
                color: kLeagueMuted,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(width: 8),
          FramedAvatar(rank: standing.rank, cosmetics: standing.cosmetics, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              me ? l10n.leagueYou : standing.username,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.rowTitle.copyWith(fontWeight: me ? FontWeight.w800 : FontWeight.w700),
            ),
          ),
          Text(
            formatXp(standing.points),
            style: AppTheme.labelLarge.copyWith(
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// "Everything counts: ranked series 30 (+20 if won) · challenge 40 · …"
class LeagueRulesCard extends StatelessWidget {
  final List<LeaguePointRule> rules;
  const LeagueRulesCard({super.key, required this.rules});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final parts = rules.where((r) => r.label != null).map((r) {
      final base = '${r.label!.resolve(context)} ${r.points}';
      return r.winBonus > 0 ? '$base (${l10n.leagueRuleWinBonus(r.winBonus)})' : base;
    }).toList();
    if (parts.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(AppTheme.radiusRow)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.leagueEverythingCounts, style: AppTheme.labelLarge.copyWith(fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(
            parts.join(' · '),
            style: AppTheme.bodyMedium.copyWith(fontSize: 13, height: 1.5, color: const Color(0xFFCBD5E1)),
          ),
        ],
      ),
    );
  }
}

/// My finished weeks, newest first.
class LeagueHistorySheet extends StatelessWidget {
  const LeagueHistorySheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        backgroundColor: AppTheme.surface,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (_) => const LeagueHistorySheet(),
      );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
        child: FutureBuilder<LeagueHistory>(
          future: LeagueApi.getHistory(),
          builder: (context, snap) {
            final h = snap.data;
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(l10n.leagueHistoryTitle, style: AppTheme.titleLarge),
                  if (h?.best != null) ...[
                    const SizedBox(height: 4),
                    Text(l10n.leagueBest(h!.best!.name.resolve(context)), style: AppTheme.caption.copyWith(fontSize: 13)),
                  ],
                  const SizedBox(height: 12),
                  if (snap.connectionState != ConnectionState.done)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator(color: AppTheme.primary)),
                    )
                  else if (snap.hasError)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(l10n.leagueLoadFailed, style: AppTheme.bodyMedium, textAlign: TextAlign.center),
                    )
                  else if (h == null || h.weeks.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(l10n.leagueHistoryEmpty, style: AppTheme.bodyMedium, textAlign: TextAlign.center),
                    )
                  else
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: [for (final w in h.weeks) _HistoryRow(week: w)],
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  final LeagueHistoryWeek week;
  const _HistoryRow({required this.week});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final (icon, color, label) = switch (week.outcome) {
      LeagueOutcome.promoted => (Icons.keyboard_arrow_up_rounded, AppTheme.primaryLight, l10n.leagueOutcomeUp),
      LeagueOutcome.relegated => (Icons.keyboard_arrow_down_rounded, kLeagueMuted, l10n.leagueOutcomeDown),
      LeagueOutcome.stayed => (Icons.remove_rounded, kLeagueMuted, l10n.leagueOutcomeStay),
    };
    final league = week.league?.name.resolve(context) ?? '';
    return DsListRow(
      leading: Icon(icon, color: color),
      title: '${l10n.leagueHistoryWeek(week.weekNumber)} · ${l10n.leagueName(league)}',
      subtitle: '${l10n.leaguePlace(week.position)} ${l10n.leagueOutOf(week.groupSize)} · '
          '${l10n.leaguePoints(formatXp(week.points))} · $label',
      trailing: week.xp > 0
          ? Text('+${formatXp(week.xp)} XP', style: AppTheme.caption.copyWith(color: kLeagueAccentSoft, fontWeight: FontWeight.w700))
          : null,
    );
  }
}
