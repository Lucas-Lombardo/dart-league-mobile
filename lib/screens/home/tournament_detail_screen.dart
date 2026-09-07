import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/tournament_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/subscription_provider.dart';
import '../../models/tournament.dart';
import '../../services/tournament_service.dart';
import '../../utils/app_theme.dart';
import '../../utils/haptic_service.dart';
import '../../utils/rank_utils.dart';
import '../../utils/tournament_bracket_logic.dart';
import '../../utils/tournament_registration_gate.dart';
import '../../utils/tournament_round.dart';
import '../../utils/tournament_status.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/round_labels.dart';
import '../../services/socket_service.dart';
import '../../services/spectate_service.dart';
import '../../widgets/tournament_bracket_tree.dart';
import '../../widgets/trophy_image.dart';
import '../spectate/spectator_match_screen.dart';
import '../tournament/tournament_camera_setup_screen.dart';

String _initials(String? username) {
  final name = (username ?? '').trim();
  if (name.isEmpty) return '?';
  return name.length >= 2
      ? name.substring(0, 2).toUpperCase()
      : name.toUpperCase();
}

Color get _hairline => AppTheme.surfaceLight.withValues(alpha: 0.45);

const TextStyle _sectionLabelStyle = TextStyle(
  fontSize: 11,
  fontWeight: FontWeight.w700,
  letterSpacing: 1.2,
  color: AppTheme.textSecondary,
);

/// Opens the camera setup for one of the signed-in player's matches (join an
/// invite, or reconnect to a live leg when [rejoinGameMatchId] is given).
void _openTournamentMatch(
  BuildContext context,
  TournamentMatch match,
  String currentUserId, {
  String? rejoinGameMatchId,
  required Future<void> Function() onReturned,
}) {
  if (match.player1Id == null || match.player2Id == null) return;
  HapticService.mediumImpact();

  final isPlayer1 = match.player1Id == currentUserId;
  final opponentId = isPlayer1 ? match.player2Id : match.player1Id;
  final opponentUsername = isPlayer1
      ? match.player2Username
      : match.player1Username;

  Navigator.of(context)
      .push(
        MaterialPageRoute(
          builder: (context) => TournamentCameraSetupScreen(
            matchId: match.id,
            tournamentId: match.tournamentId,
            tournamentName:
                match.tournamentName ??
                context.read<TournamentProvider>().currentTournament?.name ??
                '',
            roundName: match.roundName,
            opponentUsername: opponentUsername ?? '',
            opponentId: opponentId ?? '',
            player1Id: match.player1Id!,
            player2Id: match.player2Id!,
            bestOf: match.bestOf,
            inviteSentAt: match.inviteSentAt,
            rejoinGameMatchId: rejoinGameMatchId,
          ),
        ),
      )
      .then((_) => onReturned());
}

void _spectate(BuildContext context, LiveTournamentMatch match) {
  final l10n = AppLocalizations.of(context);
  HapticService.lightImpact();
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (context) => SpectatorMatchScreen(
        matchId: match.matchId,
        title: localizedRoundLabelRaw(
          l10n,
          match.roundName,
          match.roundNumber,
        ).toUpperCase(),
        seedTournament: match,
      ),
    ),
  );
}

class TournamentDetailScreen extends StatefulWidget {
  final String tournamentId;

  const TournamentDetailScreen({super.key, required this.tournamentId});

  @override
  State<TournamentDetailScreen> createState() => _TournamentDetailScreenState();
}

class _TournamentDetailScreenState extends State<TournamentDetailScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late TabController _tabController;
  bool? _isRegistered;

  // Held for dispose(): context.read() is not allowed there.
  TournamentProvider? _provider;

  /// Live matches of this tournament from /spectate/live — feeds the tree's
  /// live scores, the focus card's "watch" button and the live list. Empty
  /// against a backend without the endpoint.
  List<LiveTournamentMatch> _live = const [];
  Timer? _liveTimer;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    // Keep the bracket live while this screen is open: the provider refreshes
    // currentTournament/currentBracket on every tournament socket event and
    // poll tick. Without it the join button never appeared for a player whose
    // match was still "pending" when they opened the screen.
    _provider = context.read<TournamentProvider>()
      ..watchTournament(widget.tournamentId);
    WidgetsBinding.instance.addObserver(this);
    _loadData();
    _startLivePolling();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _liveTimer?.cancel();
    _provider?.unwatchTournament(widget.tournamentId);
    _tabController.dispose();
    super.dispose();
  }

  // No point polling the live feed while the app is in the background.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startLivePolling();
      _loadLive();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _liveTimer?.cancel();
      _liveTimer = null;
    }
  }

  void _startLivePolling() {
    _liveTimer ??= Timer.periodic(
      const Duration(seconds: 30),
      (_) => _loadLive(),
    );
  }

  Future<void> _loadData() async {
    final provider = context.read<TournamentProvider>();
    await provider.loadTournament(widget.tournamentId);
    // The focus card's join/resume CTA is driven by these two.
    await provider.loadPendingMatches();
    await provider.loadActiveMatch();
    if (!mounted) return;
    _checkRegistration();
    // The first live fetch waited for the tournament to be known.
    _loadLive();
  }

  Future<void> _refresh() => _loadData();

  Future<void> _loadLive() async {
    // Only a running tournament has matches to watch: registration pages,
    // upcoming and finished tournaments never hit the endpoint.
    final tournament = _provider?.currentTournament;
    if (!mounted || tournament == null || !tournament.isInProgress) return;
    // Same gate as the home pill: never poll a backend without the endpoint.
    try {
      await SocketService.ensureAuthenticated();
    } catch (_) {}
    if (!SocketService.supportsSpectate) return;
    final live = await SpectateService.fetchLive();
    if (!mounted) return;
    final group = live?.tournaments
        .where((t) => t.tournamentId == widget.tournamentId)
        .toList();
    setState(() {
      _live = (group == null || group.isEmpty) ? const [] : group.first.matches;
    });
  }

  Future<void> _checkRegistration() async {
    if (!mounted) return;
    final provider = context.read<TournamentProvider>();
    final isRegistered = await provider.isRegisteredForTournament(
      widget.tournamentId,
    );
    if (mounted) {
      setState(() => _isRegistered = isRegistered);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Consumer<TournamentProvider>(
      builder: (context, provider, _) {
        if (provider.isLoading && provider.currentTournament == null) {
          return const _DetailScaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final tournament = provider.currentTournament;
        if (tournament == null) {
          final hasError = provider.error != null;
          return _DetailScaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      hasError ? Icons.cloud_off : Icons.search_off,
                      size: 56,
                      color: AppTheme.textSecondary.withValues(alpha: 0.6),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      hasError
                          ? l10n.tournamentLoadError
                          : l10n.tournamentNotFound,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed: () {
                        provider.clearError();
                        _loadData();
                      },
                      icon: const Icon(Icons.refresh, size: 18),
                      label: Text(l10n.retry),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final bracket = provider.currentBracket;
        final currentUserId = context.read<AuthProvider>().currentUser?.id;

        return _DetailScaffold(
          tournament: tournament,
          bestOf: bracket.isEmpty ? null : bracket.first.bestOf,
          body: Column(
            children: [
              _HeaderExtras(
                tournament: tournament,
                isRegistered: _isRegistered,
                onRegistrationChanged: _checkRegistration,
              ),
              _UnderlineTabs(controller: _tabController),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    RefreshIndicator(
                      onRefresh: _refresh,
                      child: TournamentBracketTab(
                        tournament: tournament,
                        bracket: bracket,
                        live: _live,
                        currentUserId: currentUserId,
                        onReturnedFromMatch: _refresh,
                      ),
                    ),
                    RefreshIndicator(
                      onRefresh: _refresh,
                      child: _ParticipantsTab(
                        tournamentId: widget.tournamentId,
                        bracket: bracket,
                        currentUserId: currentUserId,
                      ),
                    ),
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

/// App bar shared by all states of the screen: tournament name and a one-line
/// summary as the title (the generic label while loading), status pill on the
/// right — a live dot while the tournament runs.
class _DetailScaffold extends StatelessWidget {
  final Tournament? tournament;
  final int? bestOf;
  final Widget body;

  const _DetailScaffold({this.tournament, this.bestOf, required this.body});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = tournament;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        titleSpacing: 0,
        centerTitle: false,
        title: t == null
            ? Text(
                l10n.tournamentDetails,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  _MetaLine(tournament: t, bestOf: bestOf),
                ],
              ),
        actions: [
          if (t != null)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(child: _StatusPill(status: t.status)),
            ),
        ],
      ),
      body: body,
    );
  }
}

/// "8 joueurs · BO3 · +500 ELO · Gratuit" under the title.
class _MetaLine extends StatelessWidget {
  final Tournament tournament;
  final int? bestOf;

  const _MetaLine({required this.tournament, required this.bestOf});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isPremium = context.select<SubscriptionProvider, bool>(
      (p) => p.isPremiumActive,
    );
    final feeText = tournament.isFree
        ? l10n.freeLabel
        : tournament.hasPremiumDiscount(isPremium: isPremium)
        ? tournament.formattedDiscountedPrice(isPremium: true)
        : tournament.formattedPrice;
    final parts = <String>[
      '${tournament.currentParticipants} ${l10n.players}',
      if (bestOf != null && bestOf! > 1) 'BO$bestOf',
      '+${tournament.winnerEloReward} ${l10n.eloLabel}',
      feeText,
    ];
    return Text(
      parts.join(' · '),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: AppTheme.textSecondary,
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String status;

  const _StatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (status == 'in_progress') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppTheme.secondary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const LiveDot(size: 6),
            const SizedBox(width: 6),
            Text(
              l10n.tournamentStatusInProgress.toUpperCase(),
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
                color: AppTheme.secondary,
              ),
            ),
          ],
        ),
      );
    }
    final color = tournamentStatusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        localizedTournamentStatus(l10n, status),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}

/// What sits between the app bar and the tabs. While the tournament runs the
/// title line says it all and the bracket gets the room; before it (and once
/// it's over) the description, the info chips, the prize and the registration
/// button come back.
class _HeaderExtras extends StatelessWidget {
  final Tournament tournament;
  final bool? isRegistered;
  final VoidCallback onRegistrationChanged;

  const _HeaderExtras({
    required this.tournament,
    required this.isRegistered,
    required this.onRegistrationChanged,
  });

  String _formatDate(DateTime date) {
    final hh = date.hour.toString().padLeft(2, '0');
    final mm = date.minute.toString().padLeft(2, '0');
    return '${date.day}/${date.month}/${date.year} · $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final showDetails = !tournament.isInProgress;
    final showRegistration =
        (tournament.isRegistrationOpen || tournament.isUpcoming) &&
        isRegistered != null;

    if (!showDetails && !showRegistration) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showDetails &&
            tournament.description != null &&
            tournament.description!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Text(
              tournament.description!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
        if (showDetails && tournament.hasTrophyImage)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: _TrophyPrizeCard(tournament: tournament),
          ),
        if (showDetails)
          SizedBox(
            height: 46,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
              children: [
                _InfoChip(
                  icon: Icons.calendar_today,
                  text: _formatDate(tournament.scheduledDate),
                ),
                _InfoChip(
                  icon: Icons.people,
                  text:
                      '${tournament.currentParticipants}/${tournament.maxParticipants}',
                ),
                // The prize card above already shows the trophy — the chip only
                // remains for cash prizes and trophies without a picked model.
                if (tournament.hasPrize && !tournament.hasTrophyImage)
                  _InfoChip(
                    icon: Icons.emoji_events,
                    text: tournament.formattedPrize,
                    color: AppTheme.accent,
                  ),
                if (tournament.premiumRequired)
                  _InfoChip(
                    icon: Icons.workspace_premium,
                    text: l10n.tournamentPremiumRequired,
                    color: AppTheme.accent,
                  ),
                if (tournament.hasRankRequirement)
                  _InfoChip(
                    icon: Icons.shield,
                    text: tournament.rankRequirementLabel,
                    color: AppTheme.primary,
                  ),
              ],
            ),
          ),
        if (showRegistration)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: _RegistrationButton(
              tournament: tournament,
              isRegistered: isRegistered!,
              canRegister: tournament.isRegistrationOpen,
              onChanged: onRegistrationChanged,
            ),
          ),
      ],
    );
  }
}

/// "À gagner" banner for tournaments awarding a physical trophy. Shows the
/// render of the actual prize and nothing about the object itself (no model
/// name, no specs) — the picture does the selling; the admin's
/// prizeDescription, when set, is the only text besides the shipping note.
class _TrophyPrizeCard extends StatelessWidget {
  final Tournament tournament;

  const _TrophyPrizeCard({required this.tournament});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final description = tournament.prizeDescription;
    final title = (description != null && description.isNotEmpty)
        ? description
        : l10n.trophyLabel;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [AppTheme.accent.withValues(alpha: 0.10), AppTheme.surface],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.prizeToWin.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: AppTheme.accent,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  l10n.trophyShippedToWinner,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          TrophyImage(
            url: tournament.trophyThumbUrl,
            size: 84,
            fallback: const SizedBox(
              width: 84,
              height: 84,
              child: Icon(Icons.emoji_events, size: 40, color: AppTheme.accent),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? color;

  const _InfoChip({required this.icon, required this.text, this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.surfaceLight.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 13, color: color ?? AppTheme.textSecondary),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color ?? AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _UnderlineTabs extends StatelessWidget {
  final TabController controller;

  const _UnderlineTabs({required this.controller});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: _hairline)),
      ),
      child: TabBar(
        controller: controller,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        labelPadding: const EdgeInsets.only(right: 24),
        indicatorColor: AppTheme.primary,
        indicatorSize: TabBarIndicatorSize.label,
        indicatorWeight: 2,
        dividerColor: Colors.transparent,
        labelColor: AppTheme.textPrimary,
        unselectedLabelColor: AppTheme.textSecondary,
        labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        unselectedLabelStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        tabs: [
          Tab(height: 40, text: l10n.bracket),
          Tab(height: 40, text: l10n.participants),
        ],
      ),
    );
  }
}

/// The bracket as a tree, then the one card that concerns the signed-in
/// player (next match, invite to join, elimination…), then the other live
/// matches one can watch. Public so the preview test can render it alone.
class TournamentBracketTab extends StatelessWidget {
  final Tournament tournament;
  final List<TournamentMatch> bracket;
  final List<LiveTournamentMatch> live;
  final String? currentUserId;
  final Future<void> Function() onReturnedFromMatch;

  const TournamentBracketTab({
    super.key,
    required this.tournament,
    required this.bracket,
    required this.live,
    required this.currentUserId,
    required this.onReturnedFromMatch,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    if (bracket.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 80),
          Icon(
            Icons.account_tree_outlined,
            size: 48,
            color: AppTheme.textSecondary.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.bracketNotGenerated,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
          ),
        ],
      );
    }

    final provider = context.watch<TournamentProvider>();
    final index = BracketIndex(bracket);
    final focus = resolveTournamentFocus(
      index: index,
      userId: currentUserId,
      pendingMatches: provider.pendingMatches,
      activeMatch: provider.activeMatch,
    );

    final liveById = <String, LiveTournamentMatch>{
      for (final m in live) m.tournamentMatchId: m,
    };
    final liveInfo = <String, BracketLiveInfo>{
      for (final m in live)
        m.tournamentMatchId: BracketLiveInfo(
          legs1: m.player1LegsWon,
          legs2: m.player2LegsWon,
          spectators: m.spectatorCount,
        ),
    };

    String? markerLabel;
    Color markerColor = AppTheme.primary;
    switch (focus.kind) {
      case TournamentFocusKind.ready:
      case TournamentFocusKind.resumable:
      case TournamentFocusKind.inProgress:
      case TournamentFocusKind.disputed:
      case TournamentFocusKind.waiting:
        markerLabel = l10n.bracketYouAreHere;
      case TournamentFocusKind.eliminated:
      case TournamentFocusKind.notPlayed:
        markerLabel = l10n.bracketEliminatedHere;
        markerColor = AppTheme.surfaceLight;
      case TournamentFocusKind.champion:
        markerLabel = l10n.bracketChampionMarker;
        markerColor = AppTheme.accent;
      case TournamentFocusKind.qualified:
      case TournamentFocusKind.none:
        markerLabel = null;
    }

    // Live matches not already surfaced by the focus card (mine, and the one
    // my next match waits for) — everyone else's, to watch.
    final surfaced = <String>{
      if (focus.match != null) focus.match!.id,
      if (focus.dependency != null) focus.dependency!.id,
    };
    final otherLive = live
        .where(
          (m) =>
              !surfaced.contains(m.tournamentMatchId) &&
              m.player1.id != currentUserId &&
              m.player2.id != currentUserId,
        )
        .toList();

    void onTapMatch(TournamentMatch match) {
      final mine =
          currentUserId != null &&
          (match.player1Id == currentUserId ||
              match.player2Id == currentUserId);
      final liveMatch = liveById[match.id];
      if (!mine) {
        // Someone else's live match: watch it. Never spectate your own —
        // that one is resumed through the join flow.
        if (match.isInProgress && liveMatch != null) {
          _spectate(context, liveMatch);
        }
        return;
      }
      if (focus.match?.id != match.id) return;
      if (focus.kind == TournamentFocusKind.ready) {
        _openTournamentMatch(
          context,
          match,
          currentUserId!,
          onReturned: onReturnedFromMatch,
        );
      } else if (focus.kind == TournamentFocusKind.resumable) {
        _openTournamentMatch(
          context,
          match,
          currentUserId!,
          rejoinGameMatchId: provider.activeMatch?.lastGameId,
          onReturned: onReturnedFromMatch,
        );
      }
    }

    // The tournament row's winner can lag the bracket by a poll tick; the
    // final itself is authoritative for the celebration card.
    final finalMatches = index.byRound[index.lastRound]!;
    final finalMatch = finalMatches.length == 1 ? finalMatches.first : null;
    final championName =
        tournament.winnerUsername ??
        (finalMatch != null && finalMatch.isCompleted
            ? (finalMatch.winnerId == finalMatch.player1Id
                  ? finalMatch.player1Username
                  : finalMatch.winnerId == finalMatch.player2Id
                  ? finalMatch.player2Username
                  : null)
            : null);
    final showChampion = tournament.winnerId != null || championName != null;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(0, 14, 0, 24),
      children: [
        if (showChampion) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _ChampionCard(
              tournament: tournament,
              championName: championName,
            ),
          ),
          const SizedBox(height: 16),
        ],
        TournamentBracketTree(
          index: index,
          currentUserId: currentUserId,
          focusMatchId: markerLabel == null ? null : focus.match?.id,
          markerLabel: markerLabel,
          markerColor: markerColor,
          joinableMatchIds: {
            if (focus.kind == TournamentFocusKind.ready) focus.match!.id,
          },
          liveByMatchId: liveInfo,
          onTapMatch: onTapMatch,
        ),
        if (!focus.isNone &&
            focus.kind != TournamentFocusKind.champion &&
            currentUserId != null) ...[
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _FocusCard(
              focus: focus,
              index: index,
              currentUserId: currentUserId!,
              liveById: liveById,
              otherLive: otherLive,
              onJoin: (match, rejoinGameMatchId) => _openTournamentMatch(
                context,
                match,
                currentUserId!,
                rejoinGameMatchId: rejoinGameMatchId,
                onReturned: onReturnedFromMatch,
              ),
              onWatch: (m) => _spectate(context, m),
            ),
          ),
        ],
        if (otherLive.isNotEmpty) ...[
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _LiveNowList(
              matches: otherLive,
              onWatch: (m) => _spectate(context, m),
            ),
          ),
        ],
      ],
    );
  }
}

/// The one card under the tree that speaks to the signed-in player: join
/// now, resume, wait for a named match (and watch it), eliminated, disputed…
class _FocusCard extends StatelessWidget {
  final TournamentFocus focus;
  final BracketIndex index;
  final String currentUserId;
  final Map<String, LiveTournamentMatch> liveById;
  final List<LiveTournamentMatch> otherLive;
  final void Function(TournamentMatch match, String? rejoinGameMatchId) onJoin;
  final ValueChanged<LiveTournamentMatch> onWatch;

  const _FocusCard({
    required this.focus,
    required this.index,
    required this.currentUserId,
    required this.liveById,
    required this.otherLive,
    required this.onJoin,
    required this.onWatch,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final match = focus.match;
    if (match == null) return const SizedBox.shrink();

    final isPlayer1 = match.player1Id == currentUserId;
    final mySlot = isPlayer1 ? 0 : 1;
    final oppSlot = 1 - mySlot;
    final myName = isPlayer1 ? match.player1Username : match.player2Username;
    final oppId = isPlayer1 ? match.player2Id : match.player1Id;
    final oppName = isPlayer1 ? match.player2Username : match.player1Username;
    final myScore = isPlayer1 ? match.player1Score : match.player2Score;
    final oppScore = isPlayer1 ? match.player2Score : match.player1Score;
    final roundUpper = localizedRoundName(match.roundName, l10n).toUpperCase();

    final me = _VsSide(
      name: myName ?? l10n.tbdLabel,
      sub: l10n.you,
      subColor: AppTheme.primary,
      isMe: true,
    );
    final opponent = oppId == null
        ? _VsSide(
            name: l10n.tbdLabel,
            sub: placeholderForSlot(l10n, index, match, oppSlot),
            tbd: true,
          )
        : _VsSide(name: oppName ?? l10n.tbdLabel);

    switch (focus.kind) {
      case TournamentFocusKind.ready:
        final deadline = match.inviteSentAt?.add(TournamentProvider.joinWindow);
        return _FocusShell(
          border: AppTheme.primary.withValues(alpha: 0.6),
          tag: '${l10n.yourMatchTag} · $roundUpper',
          tagColor: AppTheme.primary,
          trailing: deadline == null
              ? null
              : _InviteCountdown(deadline: deadline),
          children: [
            _VsRow(left: me, right: opponent),
            const SizedBox(height: 14),
            _PrimaryButton(
              icon: Icons.sports_esports,
              label: l10n.joinTournamentMatch,
              onTap: () => onJoin(match, null),
            ),
            const SizedBox(height: 8),
            _Note(l10n.tournamentInvitePromptForfeitWarning),
          ],
        );

      case TournamentFocusKind.resumable:
      case TournamentFocusKind.inProgress:
        final liveMatch = liveById[match.id];
        final mine = liveMatch == null
            ? myScore
            : (isPlayer1 ? liveMatch.player1LegsWon : liveMatch.player2LegsWon);
        final theirs = liveMatch == null
            ? oppScore
            : (isPlayer1 ? liveMatch.player2LegsWon : liveMatch.player1LegsWon);
        final activeMatch = context.read<TournamentProvider>().activeMatch;
        return _FocusShell(
          border: AppTheme.primary.withValues(alpha: 0.6),
          tag: '${l10n.yourMatchTag} · $roundUpper',
          tagColor: AppTheme.primary,
          trailing: _LiveLabel(text: l10n.matchStatusInProgress),
          children: [
            _VsRow(left: me, right: opponent, center: '$mine – $theirs'),
            if (focus.kind == TournamentFocusKind.resumable) ...[
              const SizedBox(height: 14),
              _PrimaryButton(
                icon: Icons.play_arrow,
                label: l10n.resumeTournamentMatch,
                onTap: () => onJoin(match, activeMatch?.lastGameId),
              ),
            ],
          ],
        );

      case TournamentFocusKind.disputed:
        return _FocusShell(
          border: AppTheme.accent.withValues(alpha: 0.4),
          tag: '${l10n.yourMatchTag} · $roundUpper',
          tagColor: AppTheme.accent,
          trailing: Text(
            l10n.underReviewBadge,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppTheme.accent,
            ),
          ),
          children: [
            _VsRow(left: me, right: opponent, center: '$myScore – $oppScore'),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.gavel, size: 16, color: AppTheme.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.disputedMatchBanner,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.3,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        );

      case TournamentFocusKind.waiting:
        final dep = focus.dependency;
        final depLive = dep == null ? null : liveById[dep.id];
        return _FocusShell(
          border: AppTheme.primary.withValues(alpha: 0.35),
          tag: '${l10n.nextMatchTag} · $roundUpper',
          tagColor: AppTheme.primary,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.schedule,
                size: 12,
                color: AppTheme.textSecondary,
              ),
              const SizedBox(width: 5),
              Text(
                l10n.bracketWaiting,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
          children: [
            _VsRow(left: me, right: opponent),
            if (dep != null) ...[
              const SizedBox(height: 12),
              _DependencyLine(match: dep, live: depLive, index: index),
              if (depLive != null) ...[
                const SizedBox(height: 12),
                _OutlineButton(
                  icon: Icons.play_arrow,
                  label: l10n.bracketWatchThisMatch,
                  onTap: () => onWatch(depLive),
                ),
              ],
            ],
            const SizedBox(height: 8),
            _Note(l10n.bracketNotifyWhenReady),
          ],
        );

      case TournamentFocusKind.qualified:
        return _FocusShell(
          border: AppTheme.success.withValues(alpha: 0.4),
          tag: l10n.yourMatchTag,
          tagColor: AppTheme.success,
          trailing: Text(
            l10n.youAdvanceTitle,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppTheme.success,
            ),
          ),
          children: [
            _VsRow(left: me, right: opponent, center: '$myScore – $oppScore'),
            const SizedBox(height: 10),
            _Note(l10n.bracketQualifiedWaiting),
          ],
        );

      case TournamentFocusKind.eliminated:
        final firstLive = otherLive.isEmpty ? null : otherLive.first;
        return _FocusShell(
          border: _hairline,
          tag: l10n.bracketEliminatedIn(roundUpper),
          tagColor: AppTheme.textSecondary,
          trailing: Text(
            l10n.bracketLostScore(myScore, oppScore),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          children: [
            _VsRow(
              left: me,
              right: _VsSide(
                name: oppName ?? l10n.tbdLabel,
                sub: l10n.winner.toUpperCase(),
                subColor: AppTheme.success,
                winner: true,
              ),
              center: '$myScore – $oppScore',
            ),
            if (firstLive != null) ...[
              const SizedBox(height: 12),
              _LiveMatchLine(match: firstLive),
              const SizedBox(height: 12),
              _OutlineButton(
                icon: Icons.play_arrow,
                label: l10n.bracketWatchThisMatch,
                onTap: () => onWatch(firstLive),
              ),
            ],
            const SizedBox(height: 8),
            _Note(l10n.bracketThanksFollowLive),
          ],
        );

      case TournamentFocusKind.notPlayed:
        return _FocusShell(
          border: AppTheme.error.withValues(alpha: 0.4),
          tag: '${l10n.matchStatusNotPlayed.toUpperCase()} · $roundUpper',
          tagColor: AppTheme.error,
          children: [
            _VsRow(left: me, right: opponent),
            const SizedBox(height: 10),
            _Note(l10n.matchNotPlayedBody),
          ],
        );

      case TournamentFocusKind.champion:
      case TournamentFocusKind.none:
        return const SizedBox.shrink();
    }
  }
}

class _FocusShell extends StatelessWidget {
  final Color border;
  final String tag;
  final Color tagColor;
  final Widget? trailing;
  final List<Widget> children;

  const _FocusShell({
    required this.border,
    required this.tag,
    required this.tagColor,
    this.trailing,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  tag,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _sectionLabelStyle.copyWith(color: tagColor),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

class _VsSide {
  final String name;
  final String? sub;
  final Color subColor;
  final bool isMe;
  final bool tbd;
  final bool winner;

  const _VsSide({
    required this.name,
    this.sub,
    this.subColor = AppTheme.textSecondary,
    this.isMe = false,
    this.tbd = false,
    this.winner = false,
  });
}

class _VsRow extends StatelessWidget {
  final _VsSide left;
  final _VsSide right;

  /// Replaces the "vs" — a legs score once the match has started.
  final String? center;

  const _VsRow({required this.left, required this.right, this.center});

  Widget _side(_VsSide side, {required bool alignEnd}) {
    final nameStyle = TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w700,
      fontStyle: side.tbd ? FontStyle.italic : FontStyle.normal,
      color: side.tbd ? AppTheme.textSecondary : AppTheme.textPrimary,
    );
    return Expanded(
      child: Column(
        crossAxisAlignment: alignEnd
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: alignEnd
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            children: [
              if (side.winner && !alignEnd) ...[
                const Icon(
                  Icons.emoji_events,
                  size: 13,
                  color: AppTheme.accent,
                ),
                const SizedBox(width: 4),
              ],
              Flexible(
                child: Text(
                  side.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: nameStyle,
                ),
              ),
              if (side.winner && alignEnd) ...[
                const SizedBox(width: 4),
                const Icon(
                  Icons.emoji_events,
                  size: 13,
                  color: AppTheme.accent,
                ),
              ],
            ],
          ),
          if (side.sub != null)
            Text(
              side.sub!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: side.isMe || side.winner ? 9 : 11,
                fontWeight: side.isMe || side.winner
                    ? FontWeight.w800
                    : FontWeight.w400,
                letterSpacing: side.isMe || side.winner ? 0.6 : 0,
                color: side.subColor,
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        _Avatar(name: left.name, size: 36, isMe: left.isMe, tbd: left.tbd),
        const SizedBox(width: 10),
        _side(left, alignEnd: false),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            center ?? l10n.vs,
            style: TextStyle(
              fontSize: center == null ? 12 : 18,
              fontWeight: FontWeight.w800,
              color: center == null
                  ? AppTheme.textSecondary
                  : AppTheme.textPrimary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        _side(right, alignEnd: true),
        const SizedBox(width: 10),
        _Avatar(name: right.name, size: 36, isMe: right.isMe, tbd: right.tbd),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  final String name;
  final double size;
  final bool isMe;
  final bool tbd;

  const _Avatar({
    required this.name,
    required this.size,
    this.isMe = false,
    this.tbd = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: tbd
            ? Colors.transparent
            : isMe
            ? AppTheme.primary
            : AppTheme.surfaceLight,
        border: tbd
            ? Border.all(
                color: AppTheme.textSecondary.withValues(alpha: 0.5),
                width: 1.5,
              )
            : null,
      ),
      child: Center(
        child: Text(
          tbd ? '?' : _initials(name),
          style: TextStyle(
            fontSize: size * 0.38,
            fontWeight: FontWeight.bold,
            color: tbd
                ? AppTheme.textSecondary
                : isMe
                ? Colors.white
                : AppTheme.textPrimary,
          ),
        ),
      ),
    );
  }
}

/// "● T20QUEEN – BULLSEYE_MAX · 1 – 1 · 3 spectateurs" for the match my next
/// one waits for, or a quiet "En attente de demi 2 · A vs B" when it hasn't
/// started.
class _DependencyLine extends StatelessWidget {
  final TournamentMatch match;
  final LiveTournamentMatch? live;
  final BracketIndex index;

  const _DependencyLine({
    required this.match,
    required this.live,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final p1 =
        match.player1Username ?? placeholderForSlot(l10n, index, match, 0);
    final p2 =
        match.player2Username ?? placeholderForSlot(l10n, index, match, 1);
    final isLive = match.isInProgress;
    final legs1 = live?.player1LegsWon ?? match.player1Score;
    final legs2 = live?.player2LegsWon ?? match.player2Score;

    final children = <InlineSpan>[
      TextSpan(
        text: '$p1 – $p2',
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          color: AppTheme.textPrimary,
        ),
      ),
      if (isLive) ...[
        const TextSpan(text: ' · '),
        TextSpan(
          text: '$legs1 – $legs2',
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        if (live != null)
          TextSpan(text: ' · ${l10n.bracketSpectators(live!.spectatorCount)}'),
      ],
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: AppTheme.background.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isLive)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                l10n.bracketDependsOn(
                  tinyRoundLabel(l10n, match.roundName, match.roundNumber),
                  match.matchNumber,
                ),
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: AppTheme.textSecondary,
                ),
              ),
            ),
          Row(
            children: [
              if (isLive) ...[
                const LiveDot(size: 6),
                const SizedBox(width: 8),
              ] else ...[
                const Icon(
                  Icons.schedule,
                  size: 12,
                  color: AppTheme.textSecondary,
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text.rich(
                  TextSpan(children: children),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One live match, as a line: "● A – B · 1 – 1 · 3 spectateurs".
class _LiveMatchLine extends StatelessWidget {
  final LiveTournamentMatch match;

  const _LiveMatchLine({required this.match});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: AppTheme.background.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const LiveDot(size: 6),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text:
                        '${match.player1.username} – ${match.player2.username}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const TextSpan(text: ' · '),
                  TextSpan(
                    text: '${match.player1LegsWon} – ${match.player2LegsWon}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  TextSpan(
                    text: ' · ${l10n.bracketSpectators(match.spectatorCount)}',
                  ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveLabel extends StatelessWidget {
  final String text;

  const _LiveLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const LiveDot(size: 6),
        const SizedBox(width: 6),
        Text(
          text,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppTheme.secondary,
          ),
        ),
      ],
    );
  }
}

/// mm:ss left on an invite, gold then red under two minutes (same rule as the
/// full-screen invite prompt).
class _InviteCountdown extends StatefulWidget {
  final DateTime deadline;

  const _InviteCountdown({required this.deadline});

  @override
  State<_InviteCountdown> createState() => _InviteCountdownState();
}

class _InviteCountdownState extends State<_InviteCountdown> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var left = widget.deadline.difference(DateTime.now());
    if (left.isNegative) left = Duration.zero;
    final mm = left.inMinutes.toString().padLeft(2, '0');
    final ss = (left.inSeconds % 60).toString().padLeft(2, '0');
    final color = left.inMinutes < 2 ? AppTheme.error : AppTheme.accent;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.timer_outlined, size: 12, color: color),
        const SizedBox(width: 4),
        Text(
          '$mm:$ss',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: color,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _PrimaryButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ElevatedButton.icon(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
        icon: Icon(icon, size: 20),
        label: Text(label),
      ),
    );
  }
}

class _OutlineButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _OutlineButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: OutlinedButton.icon(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.primary,
          side: BorderSide(
            color: AppTheme.primary.withValues(alpha: 0.6),
            width: 1.5,
          ),
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
        icon: Icon(icon, size: 18),
        label: Text(label),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  final String text;

  const _Note(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontSize: 11,
        height: 1.3,
        color: AppTheme.textSecondary,
      ),
    );
  }
}

/// "EN CE MOMENT" — the other live matches of this tournament, watchable in
/// one tap.
class _LiveNowList extends StatelessWidget {
  final List<LiveTournamentMatch> matches;
  final ValueChanged<LiveTournamentMatch> onWatch;

  const _LiveNowList({required this.matches, required this.onWatch});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.spectateLiveNow, style: _sectionLabelStyle),
        const SizedBox(height: 10),
        for (final match in matches) ...[
          _LiveNowRow(match: match, onWatch: () => onWatch(match)),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _LiveNowRow extends StatelessWidget {
  final LiveTournamentMatch match;
  final VoidCallback onWatch;

  const _LiveNowRow({required this.match, required this.onWatch});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onWatch,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppTheme.secondary.withValues(alpha: 0.35),
            ),
          ),
          child: Row(
            children: [
              const LiveDot(size: 6),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${match.player1.username} vs ${match.player2.username}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '${match.player1LegsWon}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: AppTheme.playerBlue,
                            ),
                          ),
                          TextSpan(
                            text: ' – ',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: AppTheme.textSecondary.withValues(
                                alpha: 0.6,
                              ),
                            ),
                          ),
                          TextSpan(
                            text: '${match.player2LegsWon}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: AppTheme.opponentPink,
                            ),
                          ),
                          TextSpan(
                            text:
                                '  ·  ${localizedRoundLabelRaw(l10n, match.roundName, match.roundNumber)}'
                                '  ·  ${l10n.bracketSpectators(match.spectatorCount)}',
                          ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  l10n.spectateWatch,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Gold celebration card shown above the tree once the tournament has a
/// winner.
class _ChampionCard extends StatelessWidget {
  final Tournament tournament;
  final String? championName;

  const _ChampionCard({required this.tournament, this.championName});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppTheme.accent.withValues(alpha: 0.16), AppTheme.surface],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.45)),
      ),
      child: Column(
        children: [
          const Icon(Icons.emoji_events, size: 36, color: AppTheme.accent),
          const SizedBox(height: 8),
          Text(
            l10n.championCrowned(championName ?? l10n.winner),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '+${tournament.winnerEloReward} ${l10n.eloLabel}',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppTheme.accent,
            ),
          ),
        ],
      ),
    );
  }
}

class _RegistrationButton extends StatefulWidget {
  final Tournament tournament;
  final bool isRegistered;
  final bool canRegister;
  final VoidCallback onChanged;

  const _RegistrationButton({
    required this.tournament,
    required this.isRegistered,
    this.canRegister = true,
    required this.onChanged,
  });

  @override
  State<_RegistrationButton> createState() => _RegistrationButtonState();
}

class _RegistrationButtonState extends State<_RegistrationButton> {
  bool _isLoading = false;

  Future<void> _toggleRegistration() async {
    if (_isLoading || !widget.canRegister) return;

    if (!widget.isRegistered) {
      // Product spec: the button is always visible; a blocked attempt
      // (app outdated, email unverified, full, premium/rank) explains why in
      // a popup. Backend enforces everything again.
      final allowed = await TournamentRegistrationGate.run(
        context,
        widget.tournament,
      );
      if (!allowed || !mounted) return;
    }

    setState(() => _isLoading = true);
    HapticService.lightImpact();

    final provider = context.read<TournamentProvider>();
    bool success;

    if (widget.isRegistered) {
      success = await provider.unregisterFromTournament(widget.tournament.id);
    } else {
      success = await provider.registerForTournament(
        widget.tournament.id,
        tournament: widget.tournament,
      );
    }

    if (success) {
      widget.onChanged();
    } else {
      final error = provider.error;
      if (error != null && mounted) {
        TournamentRegistrationGate.showRegistrationError(context, error);
        provider.clearError();
      }
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    // If registration is not open yet, show info message
    if (!widget.canRegister) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: AppTheme.surfaceLight.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppTheme.textSecondary.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.schedule,
              size: 18,
              color: AppTheme.textSecondary.withValues(alpha: 0.8),
            ),
            const SizedBox(width: 8),
            Text(
              l10n.registrationOpensSoon,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppTheme.textSecondary.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
      );
    }

    // Product spec: the register button stays VISIBLE even when the user
    // doesn't meet the conditions — tapping it explains why in a popup (see
    // TournamentRegistrationGate). Replacing the button with a banner here
    // also mis-blocked genuinely premium users whose subscription state was
    // stale, with no way to let the server decide.

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: widget.isRegistered
            ? null
            : LinearGradient(
                colors: [
                  AppTheme.primary,
                  AppTheme.primary.withValues(alpha: 0.8),
                ],
              ),
        color: widget.isRegistered
            ? AppTheme.success.withValues(alpha: 0.15)
            : null,
        borderRadius: BorderRadius.circular(14),
        border: widget.isRegistered
            ? Border.all(color: AppTheme.success.withValues(alpha: 0.5))
            : null,
        boxShadow: widget.isRegistered
            ? null
            : [
                BoxShadow(
                  color: AppTheme.primary.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _isLoading ? null : _toggleRegistration,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: _isLoading
                ? const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        widget.isRegistered
                            ? Icons.check_circle
                            : Icons.add_circle_outline,
                        size: 20,
                        color: widget.isRegistered
                            ? AppTheme.success
                            : Colors.white,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        widget.isRegistered
                            ? l10n.unregister
                            : l10n.registerNow,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: widget.isRegistered
                              ? AppTheme.success
                              : Colors.white,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// Where each registered player stands, derived from the bracket.
class _ParticipantStanding {
  final TournamentRegistration registration;
  final String? label;
  final Color color;
  final bool live;
  final bool alive;
  final bool champion;
  final int roundReached;

  const _ParticipantStanding({
    required this.registration,
    required this.label,
    required this.color,
    required this.live,
    required this.alive,
    required this.champion,
    required this.roundReached,
  });

  static _ParticipantStanding of(
    AppLocalizations l10n,
    BracketIndex? index,
    TournamentRegistration reg,
  ) {
    if (index == null || index.isEmpty) {
      return _ParticipantStanding(
        registration: reg,
        label: null,
        color: AppTheme.textSecondary,
        live: false,
        alive: false,
        champion: false,
        roundReached: 0,
      );
    }
    TournamentMatch? open;
    TournamentMatch? last;
    for (final round in index.rounds) {
      for (final m in index.byRound[round]!) {
        if (m.player1Id != reg.userId && m.player2Id != reg.userId) continue;
        last = m;
        if (!m.isCompleted) open ??= m;
      }
    }
    if (open != null) {
      final round = localizedRoundName(open.roundName, l10n).toLowerCase();
      return _ParticipantStanding(
        registration: reg,
        label: l10n.bracketInRound(round),
        color: open.isInProgress ? AppTheme.secondary : AppTheme.primary,
        live: open.isInProgress,
        alive: true,
        champion: false,
        roundReached: open.roundNumber,
      );
    }
    if (last == null) {
      return _ParticipantStanding(
        registration: reg,
        label: null,
        color: AppTheme.textSecondary,
        live: false,
        alive: false,
        champion: false,
        roundReached: 0,
      );
    }
    if (last.winnerId == reg.userId && index.isFinal(last)) {
      return _ParticipantStanding(
        registration: reg,
        label: l10n.bracketChampionMarker,
        color: AppTheme.accent,
        live: false,
        alive: true,
        champion: true,
        roundReached: last.roundNumber + 1,
      );
    }
    if (last.winnerId == reg.userId) {
      // Won the last match; the next one isn't drawn yet.
      return _ParticipantStanding(
        registration: reg,
        label: l10n.bracketQualifiedShort,
        color: AppTheme.success,
        live: false,
        alive: true,
        champion: false,
        roundReached: last.roundNumber + 1,
      );
    }
    return _ParticipantStanding(
      registration: reg,
      label: last.winnerId == null
          ? l10n.matchStatusNotPlayed
          : l10n.bracketEliminatedAt(localizedRoundName(last.roundName, l10n)),
      color: AppTheme.textSecondary,
      live: false,
      alive: false,
      champion: false,
      roundReached: last.roundNumber,
    );
  }
}

class _ParticipantsTab extends StatefulWidget {
  final String tournamentId;
  final List<TournamentMatch> bracket;
  final String? currentUserId;

  const _ParticipantsTab({
    required this.tournamentId,
    required this.bracket,
    required this.currentUserId,
  });

  @override
  State<_ParticipantsTab> createState() => _ParticipantsTabState();
}

class _ParticipantsTabState extends State<_ParticipantsTab> {
  List<TournamentRegistration>? _registrations;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRegistrations();
  }

  Future<void> _loadRegistrations() async {
    try {
      final regs = await TournamentService.getRegistrations(
        widget.tournamentId,
      );
      if (mounted) {
        setState(() {
          _registrations = regs;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading registrations: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final regs = _registrations;
    if (regs == null || regs.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 80),
          Icon(
            Icons.people_outline,
            size: 48,
            color: AppTheme.textSecondary.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.noParticipantsYet,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 16),
          ),
        ],
      );
    }

    final index = widget.bracket.isEmpty ? null : BracketIndex(widget.bracket);
    final seedOf = <String, int>{
      for (var i = 0; i < regs.length; i++)
        regs[i].id: regs[i].seed > 0 ? regs[i].seed : i + 1,
    };
    final standings = [
      for (final reg in regs) _ParticipantStanding.of(l10n, index, reg),
    ];
    if (index != null) {
      // Champion, then players still in (deepest round first, live first),
      // then the eliminated (latest exit first); seed order inside a group.
      int rank(_ParticipantStanding s) {
        if (s.champion) return 0;
        if (s.alive) return 1;
        return 2;
      }

      standings.sort((a, b) {
        final byGroup = rank(a).compareTo(rank(b));
        if (byGroup != 0) return byGroup;
        final byRound = b.roundReached.compareTo(a.roundReached);
        if (byRound != 0) return byRound;
        if (a.live != b.live) return a.live ? -1 : 1;
        return seedOf[a.registration.id]!.compareTo(seedOf[b.registration.id]!);
      });
    }
    final alive = standings.where((s) => s.alive).length;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                index == null
                    ? '${regs.length} ${l10n.players}'.toUpperCase()
                    : l10n
                          .bracketPlayersAlive(regs.length, alive)
                          .toUpperCase(),
                style: _sectionLabelStyle,
              ),
            ),
            Text(
              l10n.seedLabel,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        for (final s in standings)
          _ParticipantRow(
            standing: s,
            seed: seedOf[s.registration.id]!,
            isMe: s.registration.userId == widget.currentUserId,
            showElo: index == null,
          ),
      ],
    );
  }
}

class _ParticipantRow extends StatelessWidget {
  final _ParticipantStanding standing;
  final int seed;
  final bool isMe;
  final bool showElo;

  const _ParticipantRow({
    required this.standing,
    required this.seed,
    required this.isMe,
    required this.showElo,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final reg = standing.registration;
    final name = reg.username ?? l10n.tbdLabel;
    final dim = standing.label != null && !standing.alive;
    final elo = reg.elo;

    return Opacity(
      opacity: dim ? 0.6 : 1,
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: _hairline)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 16,
              child: Text(
                '$seed',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textSecondary,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(width: 12),
            _Avatar(name: name, size: 34, isMe: isMe),
            const SizedBox(width: 12),
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: isMe ? AppTheme.primary : AppTheme.textPrimary,
                      ),
                    ),
                  ),
                  if (isMe) ...[
                    const SizedBox(width: 6),
                    Text(
                      l10n.you,
                      style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                        color: AppTheme.primary,
                      ),
                    ),
                  ],
                  const SizedBox(width: 6),
                  RankUtils.getRankBadge(reg.rank ?? 'unranked', size: 22),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (standing.label != null)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (standing.live) ...[
                    const LiveDot(size: 5),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    standing.label!,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: standing.color,
                    ),
                  ),
                ],
              )
            else if (showElo && elo != null)
              Text(
                '$elo ${l10n.eloLabel}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
