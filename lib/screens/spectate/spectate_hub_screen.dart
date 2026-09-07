import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../services/spectate_service.dart';
import '../../utils/app_theme.dart';
import '../../utils/round_labels.dart';
import '../../widgets/design_system.dart';
import 'spectator_match_screen.dart';

/// "En direct" hub: every live ranked series and tournament match one can
/// spectate right now. One row per match — a pulsing live dot, "A vs B", the
/// context caption, the legs score and the "Regarder" link.
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
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: DsScreenHeader(
                title: l10n.spectateLiveTitle,
                showBack: true,
                actions: [
                  if (live != null && live.liveCount > 0)
                    DsPill(
                      label: dsSentence(l10n.spectateMatchCountBadge(live.liveCount)),
                      color: AppTheme.secondary,
                      dot: true,
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
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        children: [
          const SizedBox(height: 80),
          DsCard(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const Icon(Icons.live_tv_outlined,
                    size: 28, color: AppTheme.textTertiary),
                const SizedBox(height: 12),
                Text(
                  l10n.spectateNoLiveMatches,
                  textAlign: TextAlign.center,
                  style: AppTheme.rowTitle,
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.spectateHubEmptyHint,
                  textAlign: TextAlign.center,
                  style: AppTheme.caption,
                ),
              ],
            ),
          ),
        ],
      );
    }

    // Tournament matches read as one flat list: the tournament name lives in
    // each row's caption, so the per-tournament heading is redundant.
    final tournamentRows = [
      for (final group in live.tournaments)
        for (final match in group.matches)
          _TournamentRow(group: group, match: match),
    ];

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      children: [
        if (live.ranked.isNotEmpty) ...[
          DsSectionHeader(title: dsSentence(l10n.spectateRankedSection)),
          const SizedBox(height: 10),
          for (var i = 0; i < live.ranked.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            _LiveMatchRow(
              title:
                  '${live.ranked[i].player1.username} ${l10n.vs} ${live.ranked[i].player2.username}',
              caption:
                  '${dsSentence(l10n.spectateRankedSection)} · BO${live.ranked[i].bestOf}',
              player1Legs: live.ranked[i].player1LegsWon,
              player2Legs: live.ranked[i].player2LegsWon,
              onWatch: () => _openRanked(live.ranked[i]),
            ),
          ],
        ],
        if (tournamentRows.isNotEmpty) ...[
          if (live.ranked.isNotEmpty) const SizedBox(height: 28),
          DsSectionHeader(title: dsSentence(l10n.spectateTournamentsSection)),
          const SizedBox(height: 10),
          for (var i = 0; i < tournamentRows.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            _LiveMatchRow(
              title:
                  '${tournamentRows[i].match.player1.username} ${l10n.vs} ${tournamentRows[i].match.player2.username}',
              caption: tournamentRows[i].caption(l10n),
              player1Legs: tournamentRows[i].match.player1LegsWon,
              player2Legs: tournamentRows[i].match.player2LegsWon,
              onWatch: () => _openTournament(tournamentRows[i].match),
            ),
          ],
        ],
      ],
    );
  }
}

/// A tournament match plus the tournament it belongs to — the pair the row's
/// caption is built from.
class _TournamentRow {
  final LiveTournamentGroup group;
  final LiveTournamentMatch match;

  const _TournamentRow({required this.group, required this.match});

  String caption(AppLocalizations l10n) =>
      '${localizedRoundLabelRaw(l10n, match.roundName, match.roundNumber)} · ${group.name}';
}

/// One live match, 72 px: the pulsing rose dot, "A vs B" over its context
/// line, the legs score and the "Regarder" link. Tapping anywhere watches.
class _LiveMatchRow extends StatelessWidget {
  final String title;
  final String caption;
  final int player1Legs;
  final int player2Legs;
  final VoidCallback onWatch;

  const _LiveMatchRow({
    required this.title,
    required this.caption,
    required this.player1Legs,
    required this.player2Legs,
    required this.onWatch,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SizedBox(
      height: 72,
      child: DsCard(
        radius: AppTheme.radiusRow,
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
        onTap: onWatch,
        child: Row(
          children: [
            const _PulsingLiveDot(),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.caption,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '$player1Legs–$player2Legs',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppTheme.textPrimary,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 12),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.play_arrow_rounded,
                    size: 16, color: AppTheme.primaryLight),
                const SizedBox(width: 3),
                Text(
                  dsSentence(l10n.spectateWatch),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primaryLight,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The 8 px rose dot that says "this is happening right now" — the only place
/// the secondary colour appears outside a match.
class _PulsingLiveDot extends StatefulWidget {
  const _PulsingLiveDot();

  @override
  State<_PulsingLiveDot> createState() => _PulsingLiveDotState();
}

class _PulsingLiveDotState extends State<_PulsingLiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Respect the OS "reduce motion" setting: a steady dot instead.
    if (MediaQuery.of(context).disableAnimations) {
      _controller.stop();
      _controller.value = 1;
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.35, end: 1).animate(_controller),
      child: Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(
          color: AppTheme.secondary,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
