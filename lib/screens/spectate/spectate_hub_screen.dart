import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../services/spectate_service.dart';
import '../../utils/app_theme.dart';
import '../../utils/rank_utils.dart';
import '../../utils/round_labels.dart';
import '../../widgets/game_turn_ui.dart' show LiveBadge;
import 'spectator_match_screen.dart';

/// "En direct" hub: every live ranked series and tournament match one can
/// spectate right now, with a Watch button per match.
class SpectateHubScreen extends StatefulWidget {
  const SpectateHubScreen({super.key});

  @override
  State<SpectateHubScreen> createState() => _SpectateHubScreenState();
}

class _SpectateHubScreenState extends State<SpectateHubScreen> {
  SpectateLive? _live;
  bool _loading = true;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _load();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _load(silent: true),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) setState(() => _loading = true);
    final live = await SpectateService.fetchLive();
    if (!mounted) return;
    setState(() {
      _live = live ?? _live;
      _loading = false;
    });
  }

  void _openRanked(LiveRankedSeries series) {
    final l10n = AppLocalizations.of(context);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => SpectatorMatchScreen(
          matchId: series.matchId,
          title: l10n.spectateRankedSection,
          seedRanked: series,
        ),
      ),
    );
  }

  void _openTournament(LiveTournamentMatch match) {
    final l10n = AppLocalizations.of(context);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => SpectatorMatchScreen(
          matchId: match.matchId,
          title: localizedRoundLabelRaw(l10n, match.roundName, match.roundNumber)
              .toUpperCase(),
          seedTournament: match,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final live = _live;
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Row(
                children: [
                  InkWell(
                    onTap: () => Navigator.of(context).maybePop(),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppTheme.surfaceLight.withValues(alpha: 0.5),
                        ),
                      ),
                      child: const Icon(Icons.arrow_back_ios_new,
                          size: 16, color: AppTheme.textPrimary),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      l10n.spectateLiveTitle,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                  if (live != null && live.liveCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppTheme.opponentPink,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            l10n.spectateMatchCountBadge(live.liveCount),
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.2,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => _load(silent: true),
                color: AppTheme.primary,
                child: _buildBody(l10n, live),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(AppLocalizations l10n, SpectateLive? live) {
    if (_loading && live == null) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primary),
      );
    }
    if (live == null || live.liveCount == 0) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 120),
          Icon(Icons.live_tv_outlined,
              size: 44, color: AppTheme.textSecondary.withValues(alpha: 0.6)),
          const SizedBox(height: 14),
          Center(
            child: Text(
              l10n.spectateNoLiveMatches,
              style: const TextStyle(
                fontSize: 14,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
        ],
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      children: [
        if (live.ranked.isNotEmpty) ...[
          _sectionHeader(l10n.spectateRankedSection),
          const SizedBox(height: 12),
          for (final series in live.ranked) ...[
            _RankedCard(series: series, onWatch: () => _openRanked(series)),
            const SizedBox(height: 10),
          ],
        ],
        if (live.tournaments.isNotEmpty) ...[
          const SizedBox(height: 12),
          _sectionHeader(l10n.spectateTournamentsSection),
          for (final group in live.tournaments) ...[
            const SizedBox(height: 12),
            Text.rich(
              TextSpan(
                text: group.name,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textPrimary,
                ),
                children: [
                  TextSpan(
                    text:
                        ' · ${localizedRoundLabelRaw(l10n, group.matches.first.roundName, group.matches.first.roundNumber).toLowerCase()}',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            for (final match in group.matches) ...[
              _TournamentCard(
                match: match,
                onWatch: () => _openTournament(match),
              ),
              const SizedBox(height: 8),
            ],
          ],
        ],
      ],
    );
  }

  Widget _sectionHeader(String label) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
            color: AppTheme.textSecondary,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            height: 1,
            color: AppTheme.surfaceLight.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }
}

class _LegsScore extends StatelessWidget {
  final int player1Legs;
  final int player2Legs;
  final double fontSize;

  const _LegsScore({
    required this.player1Legs,
    required this.player2Legs,
    this.fontSize = 18,
  });

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$player1Legs',
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
              color: AppTheme.playerBlue,
            ),
          ),
          TextSpan(
            text: ' – ',
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
              color: AppTheme.textSecondary.withValues(alpha: 0.6),
            ),
          ),
          TextSpan(
            text: '$player2Legs',
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
              color: AppTheme.opponentPink,
            ),
          ),
        ],
      ),
    );
  }
}

class _WatchFooter extends StatelessWidget {
  final int spectatorCount;
  final VoidCallback onWatch;

  const _WatchFooter({required this.spectatorCount, required this.onWatch});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        const LiveBadge(),
        const SizedBox(width: 10),
        const Icon(Icons.visibility_outlined,
            size: 13, color: AppTheme.textSecondary),
        const SizedBox(width: 5),
        Text(
          '$spectatorCount',
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: AppTheme.textSecondary,
          ),
        ),
        const Spacer(),
        InkWell(
          onTap: onWatch,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppTheme.primary, AppTheme.primaryDark],
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              l10n.spectateWatch,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _RankedCard extends StatelessWidget {
  final LiveRankedSeries series;
  final VoidCallback onWatch;

  const _RankedCard({required this.series, required this.onWatch});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return InkWell(
      onTap: onWatch,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.primary.withValues(alpha: 0.6)),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _PlayerBlock(player: series.player1, alignEnd: false),
                ),
                Column(
                  children: [
                    _LegsScore(
                      player1Legs: series.player1LegsWon,
                      player2Legs: series.player2LegsWon,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${l10n.legNumber(series.legNumber).toUpperCase()} · BO${series.bestOf}',
                      style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
                Expanded(
                  child: _PlayerBlock(player: series.player2, alignEnd: true),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              height: 1,
              color: AppTheme.surfaceLight.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 9),
            _WatchFooter(
              spectatorCount: series.spectatorCount,
              onWatch: onWatch,
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayerBlock extends StatelessWidget {
  final SpectatorPlayer player;
  final bool alignEnd;

  const _PlayerBlock({required this.player, required this.alignEnd});

  @override
  Widget build(BuildContext context) {
    final name = Column(
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(
          player.username,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w800,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          '${player.elo} ELO',
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppTheme.textSecondary,
          ),
        ),
      ],
    );
    final badge = RankUtils.getRankBadge(player.rank, size: 36);
    return Row(
      mainAxisAlignment:
          alignEnd ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: alignEnd
          ? [Flexible(child: name), const SizedBox(width: 9), badge]
          : [badge, const SizedBox(width: 9), Flexible(child: name)],
    );
  }
}

class _TournamentCard extends StatelessWidget {
  final LiveTournamentMatch match;
  final VoidCallback onWatch;

  const _TournamentCard({required this.match, required this.onWatch});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return InkWell(
      onTap: onWatch,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.primary.withValues(alpha: 0.6)),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    localizedRoundLabelRaw(
                            l10n, match.roundName, match.roundNumber)
                        .toUpperCase(),
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${match.player1.username} vs ${match.player2.username}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
                _LegsScore(
                  player1Legs: match.player1LegsWon,
                  player2Legs: match.player2LegsWon,
                  fontSize: 14,
                ),
              ],
            ),
            const SizedBox(height: 9),
            _WatchFooter(
              spectatorCount: match.spectatorCount,
              onWatch: onWatch,
            ),
          ],
        ),
      ),
    );
  }
}
