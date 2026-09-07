import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/season.dart';
import '../../providers/season_provider.dart';
import '../../utils/app_navigator.dart';
import '../../utils/app_theme.dart';
import '../../utils/rank_translation.dart';
import '../../utils/rank_utils.dart';
import '../../utils/season_format.dart';
import '../../widgets/design_system.dart';
import '../../widgets/loading_widget.dart';
import '../../widgets/trophy_image.dart';

/// Every season as a flat card, newest first: "Saison N" + state pill, the
/// period, then the prize, who leads (or the champion) and your own line as
/// caption rows, and a "Classement ›" link. Tapping a card pops with its
/// number so the caller selects that ladder (system D — the posters, the
/// gradient and the page dots are gone).
class SeasonsScreen extends StatefulWidget {
  /// Season to bring into view on open; defaults to the active one.
  final int? initialNumber;

  const SeasonsScreen({super.key, this.initialNumber});

  @override
  State<SeasonsScreen> createState() => _SeasonsScreenState();
}

class _SeasonsScreenState extends State<SeasonsScreen> {
  final _keys = <int, GlobalKey>{};
  bool _scrolled = false;

  List<Season> _seasonsOf(SeasonProvider provider) {
    final list = [...provider.seasons]..sort((a, b) => b.number.compareTo(a.number));
    if (list.isEmpty && provider.activeSeason != null) list.add(provider.activeSeason!);
    return list;
  }

  /// Once the list is known, scroll the requested season into view (a no-op
  /// when everything already fits).
  void _scrollToInitial(List<Season> seasons, SeasonProvider provider) {
    if (_scrolled || seasons.isEmpty) return;
    _scrolled = true;
    final target = widget.initialNumber ?? provider.activeSeason?.number;
    final key = _keys[target];
    if (key == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = key.currentContext;
      if (ctx == null || !mounted) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.1,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final provider = context.watch<SeasonProvider>();
    final seasons = _seasonsOf(provider);
    for (final season in seasons) {
      _keys.putIfAbsent(season.number, GlobalKey.new);
    }
    _scrollToInitial(seasons, provider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(l10n.seasonsTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => AppNavigator.back(context),
        ),
      ),
      body: seasons.isEmpty
          ? const LoadingWidget()
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              itemCount: seasons.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final season = seasons[i];
                return KeyedSubtree(
                  key: _keys[season.number],
                  child: _SeasonCard(
                    season: season,
                    me: season.isActive ? provider.current?.me : season.myStanding,
                    timeLeft: season.isActive ? provider.timeLeft : null,
                    previousEnd: season.isScheduled ? provider.activeSeason?.endAt : null,
                    // "Standings ›": pop with the season number so the caller
                    // selects that chip. Nothing to show for a scheduled one.
                    onStandings: season.isScheduled
                        ? null
                        : () => AppNavigator.back(context, season.number),
                  ),
                );
              },
            ),
    );
  }
}

/// One season card: number + state pill, the period, then the prize, the
/// leader / champion and your line as caption rows, and the link.
class _SeasonCard extends StatelessWidget {
  final Season season;
  final SeasonStanding? me;
  final Duration? timeLeft;
  /// For a scheduled season: the active season's end = this one's start.
  final DateTime? previousEnd;
  final VoidCallback? onStandings;

  const _SeasonCard({
    required this.season,
    required this.me,
    required this.timeLeft,
    required this.previousEnd,
    required this.onStandings,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final person = season.champion;
    final total = season.playersCount ?? 0;
    final period = _period(context, l10n);

    return DsCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      onTap: onStandings,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.seasonN(season.number),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.sectionTitle,
                ),
              ),
              const SizedBox(width: 10),
              _statePill(l10n),
            ],
          ),
          if (period.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              period,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.caption,
            ),
          ],
          const SizedBox(height: 14),
          _InfoRow(leading: _prizeLeading(), text: _prizeLine(context, l10n)),
          if (person != null) ...[
            const SizedBox(height: 8),
            _InfoRow(
              leading: const Icon(
                Icons.workspace_premium_outlined,
                size: 16,
                color: AppTheme.textSecondary,
              ),
              text: dsSentence(season.isActive ? l10n.seasonLeader : l10n.seasonChampion),
              emphasis: person.username,
              detail: '${person.elo}',
            ),
          ],
          if (me != null) ...[
            const SizedBox(height: 8),
            _InfoRow(
              leading: RankUtils.getRankBadge(me!.rank, size: 24),
              text: dsSentence(l10n.seasonYou),
              emphasis: '#${me!.position}${total > 0 ? ' ${l10n.seasonOf(total)}' : ''}',
              detail: '${me!.elo} · ${RankTranslation.translate(l10n, me!.rank)}',
            ),
          ] else if (season.isClosed) ...[
            const SizedBox(height: 8),
            _InfoRow(
              leading: const Icon(
                Icons.person_outline_rounded,
                size: 16,
                color: AppTheme.textSecondary,
              ),
              text: l10n.seasonNotRanked,
            ),
          ],
          if (onStandings != null) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  season.isClosed ? l10n.seasonFinalStandings : l10n.seasonStandings,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primaryLight,
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: AppTheme.primaryLight,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _statePill(AppLocalizations l10n) {
    if (season.isActive) {
      return DsPill(label: l10n.seasonInProgress, color: AppTheme.primaryLight, dot: true);
    }
    if (season.isClosed) {
      return DsPill(label: l10n.seasonEnded, color: AppTheme.textSecondary);
    }
    return DsPill(label: l10n.seasonUpcoming, color: AppTheme.textTertiary);
  }

  /// "Du 1er août au 31 août 2026 · 84 j" (active), the period (closed),
  /// the start day (scheduled). Empty when nothing is known.
  String _period(BuildContext context, AppLocalizations l10n) {
    final start = season.startedAt;
    final end = season.endAt;
    if (season.isScheduled) {
      final startsAt = previousEnd == null ? null : seasonStartAfter(previousEnd!);
      return startsAt != null
          ? formatSeasonDayLong(context, startsAt)
          : l10n.seasonAfterSeason(season.number - 1);
    }
    if (end == null) {
      if (!season.isActive) return '';
      return start != null
          ? '${formatSeasonDay(context, start)} · ${l10n.seasonEndToBeAnnounced}'
          : l10n.seasonEndToBeAnnounced;
    }
    final range = start == null
        ? l10n.seasonFromLaunchTo(formatSeasonDate(context, end))
        : l10n.seasonPeriod(formatSeasonDay(context, start), formatSeasonDate(context, end));
    if (season.isActive) {
      return '$range · ${formatSeasonCountdown(l10n, timeLeft ?? season.timeLeft())}';
    }
    return range;
  }

  String _prizeLine(BuildContext context, AppLocalizations l10n) {
    if (!season.hasReward) return l10n.seasonNoReward;
    if (season.isScheduled) return l10n.seasonPrizeUpForGrabs;
    final end = season.endAt;
    if (season.isActive && end != null) {
      return '${l10n.seasonPrize} · ${l10n.seasonPrizeFor1stOn(formatSeasonDay(context, end))}';
    }
    return '${l10n.seasonPrize} · ${l10n.seasonPrizeFor1stShort}';
  }

  /// The physical trophy render when the admin picked one, else the icon.
  Widget _prizeLeading() {
    const icon = Icon(Icons.emoji_events_outlined, size: 16, color: AppTheme.textSecondary);
    if (!season.hasReward || !season.hasTrophyImage) return icon;
    return TrophyImage(url: season.trophyThumbUrl, size: 24, fallback: icon);
  }
}

/// A 24 px leading (icon or badge) and one caption line:
/// "Vous · #14 sur 312 · 1486 · Or".
class _InfoRow extends StatelessWidget {
  final Widget leading;
  final String text;
  final String? emphasis;
  final String? detail;

  const _InfoRow({
    required this.leading,
    required this.text,
    this.emphasis,
    this.detail,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 24, height: 24, child: Center(child: leading)),
        const SizedBox(width: 10),
        Expanded(
          child: Text.rich(
            TextSpan(
              style: AppTheme.caption.copyWith(fontSize: 13),
              children: [
                TextSpan(text: text),
                if (emphasis != null) ...[
                  const TextSpan(text: ' · '),
                  TextSpan(
                    text: emphasis,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                if (detail != null) TextSpan(text: ' · $detail'),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
