import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../utils/app_theme.dart';
import '../../widgets/design_system.dart';
import '../../widgets/home_tiles.dart';
import '../progression/progression_format.dart';
import '../progression/today_section.dart';
import 'league_models.dart';
import 'league_screen.dart';
import 'league_store.dart';

const Color kLeagueMuted = Color(0xFF94A3B8);
const Color kLeagueAccentSoft = Color(0xFF7DD3FC);

/// "Ligue Acier · fin dim. 22 h" helpers, in the device's time zone.
String leagueEndsLabel(AppLocalizations l10n, DateTime? endsAt, {bool long = false}) {
  if (endsAt == null) return '';
  final day = long ? l10n.leagueWeekdayLong(endsAt.weekday) : l10n.leagueWeekdayShort(endsAt.weekday);
  return l10n.leagueEndsOn(day, l10n.leagueHour(endsAt.hour));
}

/// The six bars of the ladder (mockups Ligue and LigueLundi): leagues below
/// the current one in blue, the current one highlighted, the ones above grey.
class LeagueLadder extends StatelessWidget {
  final List<LeagueTier> ladder;
  final String? currentId;
  /// The current league's bar; the soft blue of the mockup by default, the
  /// league's own colour on the Monday screen.
  final Color? currentColor;

  const LeagueLadder({super.key, required this.ladder, required this.currentId, this.currentColor});

  @override
  Widget build(BuildContext context) {
    if (ladder.isEmpty) return const SizedBox.shrink();
    final current = ladder.indexWhere((t) => t.id == currentId);
    return Row(
      children: [
        for (var i = 0; i < ladder.length; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          Expanded(
            child: Column(
              children: [
                Container(
                  height: 6,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    color: i < current
                        ? AppTheme.primaryLight
                        : i == current
                            ? (currentColor ?? kLeagueAccentSoft)
                            : AppTheme.surfaceLight,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  ladder[i].name.resolve(context),
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                  style: AppTheme.caption.copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: i == current ? AppTheme.textPrimary : kLeagueMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// "Ta première ligue commence lundi" / "Ta ligue reprend lundi".
String leagueWaitingTitle(AppLocalizations l10n, LeagueSnapshot s) =>
    s.firstWeek ? l10n.leagueFirstTitle : l10n.leagueBackTitle;

/// The league row of the home "Today" block (mockup Accueil). Hidden until
/// the league API answers, and on a server without league.
class LeagueTodayRow extends StatelessWidget {
  const LeagueTodayRow({super.key});

  /// Whether the row has something to show — so the home block does not
  /// draw an empty row (and its divider) while the API is silent.
  static bool isVisible() => LeagueStore.instance.visible != null;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: LeagueStore.instance,
      builder: (context, _) {
        final s = LeagueStore.instance.visible;
        if (s == null) return const SizedBox.shrink();
        final l10n = AppLocalizations.of(context);
        final name = s.league?.name.resolve(context) ?? '';
        final now = DateTime.now();
        String subtitle;
        Widget? trailing;
        if (s.inGroup && s.myPosition != null) {
          final parts = [
            l10n.leaguePlace(s.myPosition!),
            l10n.leaguePoints(formatXp(s.myPoints)),
            if (s.state == LeagueWeekState.open && s.endsAt != null && s.endsAt!.isAfter(now))
              l10n.leagueTimeLeft(formatRemaining(l10n, s.endsAt!.difference(now)))
            else
              l10n.leagueWeekOver,
          ];
          subtitle = parts.join(' · ');
          trailing = _ZoneMark(snapshot: s);
        } else {
          subtitle = leagueWaitingTitle(l10n, s);
        }
        return TodayRow(
          icon: Icons.leaderboard_outlined,
          accent: s.inGroup,
          title: l10n.leagueName(name),
          subtitle: subtitle,
          trailing: trailing,
          onTap: () => LeagueScreen.open(context),
        );
      },
    );
  }
}

/// The « Ligue … » tile of the home's « Aujourd'hui » (mockup AccFinal): the
/// place and the XP that place pays at the end of the week (defs.league →
/// xpByPosition, through [xpForPosition]); before the first point, the
/// points; outside a group, « Ta ligue reprend lundi ».
class LeagueTodayTile extends StatelessWidget {
  /// The XP of a place, null when the content has no league settings.
  final int? Function(int position)? xpForPosition;
  const LeagueTodayTile({super.key, this.xpForPosition});

  static bool isVisible() => LeagueTodayRow.isVisible();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: LeagueStore.instance,
      builder: (context, _) {
        final s = LeagueStore.instance.visible;
        if (s == null) return const SizedBox.shrink();
        final l10n = AppLocalizations.of(context);
        final name = s.league?.name.resolve(context) ?? '';
        var detail = leagueWaitingTitle(l10n, s);
        String? xp;
        final position = s.myPosition;
        if (s.inGroup && position != null) {
          detail = l10n.leaguePlace(position);
          // The server pays nothing without a single point: the points then.
          final gain = s.myPoints > 0 ? xpForPosition?.call(position) : null;
          if (gain != null && gain > 0) {
            xp = l10n.homeXpGain(gain);
          } else {
            detail = '$detail · ${l10n.leaguePoints(formatXp(s.myPoints))}';
          }
        }
        return HomeTodayTile(
          icon: Icons.leaderboard_outlined,
          title: l10n.leagueName(name),
          detail: detail,
          xp: xp,
          onTap: () => LeagueScreen.open(context),
        );
      },
    );
  }
}

/// A chevron when the player sits in the promotion or relegation zone.
class _ZoneMark extends StatelessWidget {
  final LeagueSnapshot snapshot;
  const _ZoneMark({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final g = snapshot.group;
    final pos = snapshot.myPosition;
    if (g == null || pos == null || snapshot.myPoints <= 0) return const SizedBox.shrink();
    if (g.promoteTo != null && pos <= g.promoteCount) {
      return const Icon(Icons.keyboard_arrow_up_rounded, color: AppTheme.primaryLight, size: 22);
    }
    if (g.relegateTo != null && g.relegateCount > 0 && pos >= g.relegateFrom) {
      return const Icon(Icons.keyboard_arrow_down_rounded, color: kLeagueMuted, size: 22);
    }
    return const SizedBox.shrink();
  }
}

/// The league card of the Progression screen: ladder, league, place.
class LeagueProgressionCard extends StatefulWidget {
  const LeagueProgressionCard({super.key});

  @override
  State<LeagueProgressionCard> createState() => _LeagueProgressionCardState();
}

class _LeagueProgressionCardState extends State<LeagueProgressionCard> {
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
        final s = LeagueStore.instance.visible;
        if (s == null) return const SizedBox.shrink();
        final l10n = AppLocalizations.of(context);
        final name = s.league?.name.resolve(context) ?? '';
        final line = s.inGroup && s.myPosition != null
            ? '${l10n.leaguePlace(s.myPosition!)} ${l10n.leagueOutOf(s.group!.size)} · ${l10n.leaguePoints(formatXp(s.myPoints))}'
            : leagueWaitingTitle(l10n, s);
        return Padding(
          padding: const EdgeInsets.only(top: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.leagueWeeklyTitle, style: AppTheme.sectionTitle),
              const SizedBox(height: 8),
              DsCard(
                onTap: () => LeagueScreen.open(context),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            l10n.leagueName(name),
                            style: AppTheme.titleLarge.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded, color: kLeagueMuted),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(line, style: AppTheme.caption.copyWith(fontSize: 13)),
                    const SizedBox(height: 12),
                    LeagueLadder(ladder: s.ladder, currentId: s.league?.id),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
