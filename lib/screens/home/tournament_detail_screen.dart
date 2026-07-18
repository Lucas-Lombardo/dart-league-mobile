import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/tournament_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/subscription_provider.dart';
import '../../models/tournament.dart';
import '../../services/tournament_service.dart';
import '../../utils/app_theme.dart';
import '../../utils/haptic_service.dart';
import '../../utils/tournament_registration_gate.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/round_labels.dart';
import '../tournament/tournament_camera_setup_screen.dart';

String _localizedTournamentStatus(AppLocalizations l10n, String status) {
  switch (status) {
    case 'upcoming':
      return l10n.tournamentStatusUpcoming;
    case 'registration_open':
      return l10n.tournamentStatusRegistrationOpen;
    case 'registration_closed':
      return l10n.tournamentStatusRegistrationClosed;
    case 'in_progress':
      return l10n.tournamentStatusInProgress;
    case 'completed':
      return l10n.tournamentStatusCompleted;
    case 'cancelled':
      return l10n.tournamentStatusCancelled;
    default:
      return status;
  }
}

Color _tournamentStatusColor(String status) {
  switch (status) {
    case 'registration_open':
      return AppTheme.success;
    case 'in_progress':
      return AppTheme.primary;
    case 'completed':
      return AppTheme.textSecondary;
    case 'cancelled':
      return AppTheme.error;
    default:
      return AppTheme.accent;
  }
}

String _initials(String? username) {
  final name = (username ?? '').trim();
  if (name.isEmpty) return '?';
  return name.length >= 2 ? name.substring(0, 2).toUpperCase() : name.toUpperCase();
}

class TournamentDetailScreen extends StatefulWidget {
  final String tournamentId;

  const TournamentDetailScreen({super.key, required this.tournamentId});

  @override
  State<TournamentDetailScreen> createState() => _TournamentDetailScreenState();
}

class _TournamentDetailScreenState extends State<TournamentDetailScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool? _isRegistered;

  /// Round the user tapped in the chips row; null = follow the live round.
  int? _selectedRound;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final provider = context.read<TournamentProvider>();
    await provider.loadTournament(widget.tournamentId);
    // The hero card's join/resume CTA is driven by these two.
    await provider.loadPendingMatches();
    await provider.loadActiveMatch();
    _checkRegistration();
  }

  Future<void> _checkRegistration() async {
    final provider = context.read<TournamentProvider>();
    final isRegistered = await provider.isRegisteredForTournament(widget.tournamentId);
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
            return const _DetailScaffold(body: Center(child: CircularProgressIndicator()));
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
                        hasError ? l10n.tournamentLoadError : l10n.tournamentNotFound,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 16),
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

        return _DetailScaffold(
          tournament: tournament,
          body: Column(
            children: [
              _CompactHeader(
                tournament: tournament,
                isRegistered: _isRegistered,
                onRegistrationChanged: _checkRegistration,
              ),
              _SegmentedTabs(controller: _tabController),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    RefreshIndicator(
                      onRefresh: _loadData,
                      child: _BracketTab(
                        tournament: tournament,
                        bracket: provider.currentBracket,
                        selectedRound: _selectedRound,
                        onRoundSelected: (round) {
                          HapticService.lightImpact();
                          setState(() => _selectedRound = round);
                        },
                        onReturnedFromMatch: _loadData,
                      ),
                    ),
                    RefreshIndicator(
                      onRefresh: _loadData,
                      child: _ParticipantsTab(tournamentId: widget.tournamentId),
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

/// App bar shared by all states of the screen: tournament name as the title
/// (falls back to the generic label while loading) and the status pill.
class _DetailScaffold extends StatelessWidget {
  final Tournament? tournament;
  final Widget body;

  const _DetailScaffold({this.tournament, required this.body});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = tournament;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        titleSpacing: 0,
        title: Text(
          t?.name ?? l10n.tournamentDetails,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        actions: [
          if (t != null)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _tournamentStatusColor(t.status).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: _tournamentStatusColor(t.status).withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(
                    _localizedTournamentStatus(l10n, t.status),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: _tournamentStatusColor(t.status),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: body,
    );
  }
}

/// Replaces the old full-screen info card: description (2 lines max), a
/// horizontally scrollable chips row, a round progress line while the
/// tournament runs, and the registration button when it applies.
class _CompactHeader extends StatelessWidget {
  final Tournament tournament;
  final bool? isRegistered;
  final VoidCallback onRegistrationChanged;

  const _CompactHeader({
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
    final isPremium = context.select<SubscriptionProvider, bool>(
      (p) => p.isPremiumActive,
    );

    final feeText = tournament.isFree
        ? l10n.freeLabel
        : tournament.hasPremiumDiscount(isPremium: isPremium)
            ? tournament.formattedDiscountedPrice(isPremium: true)
            : tournament.formattedPrice;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (tournament.description != null && tournament.description!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(
              tournament.description!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
            ),
          ),
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
                text: '${tournament.currentParticipants}/${tournament.maxParticipants}',
              ),
              _InfoChip(
                icon: Icons.star,
                text: '+${tournament.winnerEloReward} ELO',
                color: AppTheme.accent,
              ),
              if (tournament.hasPrize)
                _InfoChip(
                  icon: Icons.emoji_events,
                  text: tournament.formattedPrize,
                  color: AppTheme.accent,
                ),
              _InfoChip(
                icon: tournament.isFree ? Icons.card_giftcard : Icons.payment,
                text: feeText,
                color: tournament.isFree ? AppTheme.success : AppTheme.primary,
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
        if (tournament.isInProgress && tournament.totalRounds > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Row(
              children: [
                Text(
                  l10n.roundProgress(tournament.currentRound, tournament.totalRounds),
                  style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: tournament.currentRound / tournament.totalRounds,
                      minHeight: 4,
                      backgroundColor: AppTheme.surfaceLight,
                      valueColor: const AlwaysStoppedAnimation(AppTheme.primary),
                    ),
                  ),
                ),
              ],
            ),
          ),
        if ((tournament.isRegistrationOpen || tournament.isUpcoming) && isRegistered != null)
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

class _SegmentedTabs extends StatelessWidget {
  final TabController controller;

  const _SegmentedTabs({required this.controller});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.surfaceLight.withValues(alpha: 0.5)),
      ),
      child: TabBar(
        controller: controller,
        indicator: BoxDecoration(
          gradient: LinearGradient(
            colors: [AppTheme.primary, AppTheme.primary.withValues(alpha: 0.8)],
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primary.withValues(alpha: 0.4),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        labelColor: Colors.white,
        unselectedLabelColor: AppTheme.textSecondary,
        labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
        dividerColor: Colors.transparent,
        splashBorderRadius: BorderRadius.circular(12),
        tabs: [
          Tab(
            height: 40,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.account_tree_outlined, size: 18),
                const SizedBox(width: 8),
                Text(l10n.bracket),
              ],
            ),
          ),
          Tab(
            height: 40,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.people_outline, size: 18),
                const SizedBox(width: 8),
                Text(l10n.participants),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Round-focused bracket: chips select one round, the user's own match is
/// pinned on top as a hero card with a join/resume CTA, other matches follow.
class _BracketTab extends StatelessWidget {
  final Tournament tournament;
  final List<TournamentMatch> bracket;
  final int? selectedRound;
  final ValueChanged<int> onRoundSelected;
  final Future<void> Function() onReturnedFromMatch;

  const _BracketTab({
    required this.tournament,
    required this.bracket,
    required this.selectedRound,
    required this.onRoundSelected,
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

    final matchesByRound = <int, List<TournamentMatch>>{};
    for (final match in bracket) {
      matchesByRound.putIfAbsent(match.roundNumber, () => []).add(match);
    }
    final rounds = matchesByRound.keys.toList()..sort();

    // Default to the round being played: the first one with an unfinished
    // match, or the last round once everything is settled.
    final activeRound = rounds.firstWhere(
      (r) => matchesByRound[r]!.any((m) => !m.isCompleted),
      orElse: () => rounds.last,
    );
    final round = (selectedRound != null && rounds.contains(selectedRound))
        ? selectedRound!
        : activeRound;

    final roundMatches = List<TournamentMatch>.from(matchesByRound[round]!)
      ..sort((a, b) => a.matchNumber.compareTo(b.matchNumber));

    final currentUserId = context.read<AuthProvider>().currentUser?.id;
    final myMatchIndex = currentUserId == null
        ? -1
        : roundMatches.indexWhere(
            (m) => m.player1Id == currentUserId || m.player2Id == currentUserId);
    final myMatch = myMatchIndex >= 0 ? roundMatches[myMatchIndex] : null;
    final otherMatches = [
      for (var i = 0; i < roundMatches.length; i++)
        if (i != myMatchIndex) roundMatches[i],
    ];

    final hasFrozenMatch = currentUserId != null &&
        bracket.any((m) =>
            m.isDisputed &&
            (m.player1Id == currentUserId || m.player2Id == currentUserId));

    final isFinalRound = round == rounds.last;
    final showChampion = isFinalRound && tournament.winnerId != null;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        _RoundChips(
          rounds: rounds,
          matchesByRound: matchesByRound,
          selected: round,
          lastRound: rounds.last,
          onSelected: onRoundSelected,
        ),
        const SizedBox(height: 12),
        // Persistent explanation for a player whose own match is frozen by a
        // dispute — without it they have no way to understand why they haven't
        // advanced (the one-time dialog at refusal time is long gone, and the
        // opponent never saw one at all).
        if (hasFrozenMatch) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.accent.withValues(alpha: 0.5)),
            ),
            child: Row(
              children: [
                const Icon(Icons.gavel, color: AppTheme.accent, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l10n.disputedMatchBanner,
                    style: const TextStyle(
                      color: AppTheme.accent,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (showChampion) ...[
          _ChampionCard(tournament: tournament),
          const SizedBox(height: 12),
        ],
        if (myMatch != null) ...[
          _YourMatchCard(
            match: myMatch,
            currentUserId: currentUserId!,
            onReturnedFromMatch: onReturnedFromMatch,
          ),
          const SizedBox(height: 16),
          if (otherMatches.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                l10n.otherMatchesLabel.toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: AppTheme.textSecondary.withValues(alpha: 0.8),
                ),
              ),
            ),
        ],
        ...otherMatches.map(
          (m) => _MatchCard(match: m, currentUserId: currentUserId),
        ),
      ],
    );
  }
}

class _RoundChips extends StatelessWidget {
  final List<int> rounds;
  final Map<int, List<TournamentMatch>> matchesByRound;
  final int selected;
  final int lastRound;
  final ValueChanged<int> onSelected;

  const _RoundChips({
    required this.rounds,
    required this.matchesByRound,
    required this.selected,
    required this.lastRound,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: rounds.map((round) {
          final isSelected = round == selected;
          final isFinal = round == lastRound;
          final done = matchesByRound[round]!.every((m) => m.isCompleted);

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Material(
              color: isSelected ? AppTheme.primary : AppTheme.surface,
              borderRadius: BorderRadius.circular(999),
              child: InkWell(
                onTap: () => onSelected(round),
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: isSelected
                          ? Colors.transparent
                          : AppTheme.surfaceLight.withValues(alpha: 0.7),
                    ),
                  ),
                  child: Row(
                    children: [
                      if (isFinal) ...[
                        Icon(
                          Icons.emoji_events,
                          size: 14,
                          color: isSelected ? Colors.white : AppTheme.accent,
                        ),
                        const SizedBox(width: 5),
                      ] else if (done) ...[
                        Icon(
                          Icons.check,
                          size: 14,
                          color: isSelected ? Colors.white : AppTheme.success,
                        ),
                        const SizedBox(width: 5),
                      ],
                      Text(
                        localizedRoundLabel(l10n, matchesByRound[round]!.first),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isSelected ? Colors.white : AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// The signed-in player's match for the selected round, promoted to a hero
/// card with a direct join/resume CTA — the screen's whole job during a
/// tournament is answering "when do I play, against whom, and let me go".
class _YourMatchCard extends StatelessWidget {
  final TournamentMatch match;
  final String currentUserId;
  final Future<void> Function() onReturnedFromMatch;

  const _YourMatchCard({
    required this.match,
    required this.currentUserId,
    required this.onReturnedFromMatch,
  });

  void _openMatch(BuildContext context, {String? rejoinGameMatchId}) {
    if (match.player1Id == null || match.player2Id == null) return;
    HapticService.mediumImpact();

    final isPlayer1 = match.player1Id == currentUserId;
    final opponentId = isPlayer1 ? match.player2Id : match.player1Id;
    final opponentUsername =
        isPlayer1 ? match.player2Username : match.player1Username;

    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (context) => TournamentCameraSetupScreen(
              matchId: match.id,
              tournamentId: match.tournamentId,
              tournamentName: match.tournamentName ??
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
        .then((_) => onReturnedFromMatch());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final provider = context.watch<TournamentProvider>();

    final isPlayer1 = match.player1Id == currentUserId;
    final myScore = isPlayer1 ? match.player1Score : match.player2Score;
    final oppScore = isPlayer1 ? match.player2Score : match.player1Score;
    final myUsername = isPlayer1 ? match.player1Username : match.player2Username;
    final oppUsername = isPlayer1 ? match.player2Username : match.player1Username;

    // Join: the backend invited us and the match hasn't started (mirrors the
    // play-screen banner). Resume: a live leg exists to reconnect to.
    final joinable = match.isWaitingForPlayers &&
        match.player1Id != null &&
        match.player2Id != null &&
        provider.pendingMatches.any((m) => m.id == match.id);
    final active = provider.activeMatch;
    final resumable = active != null &&
        active.id == match.id &&
        active.isInProgress &&
        active.lastGameId != null;

    final won = match.isCompleted && match.winnerId == currentUserId;
    final lost = match.isCompleted && match.winnerId != null && !won;
    final isFinal = match.roundName == 'final' || match.nextMatchId == null;

    String statusText;
    Color statusColor = AppTheme.primary;
    if (match.isDisputed) {
      statusText = l10n.underReviewBadge;
      statusColor = AppTheme.accent;
    } else if (won && isFinal) {
      statusText = l10n.tournamentChampion;
      statusColor = AppTheme.accent;
    } else if (won) {
      statusText = l10n.youAdvanceTitle;
      statusColor = AppTheme.success;
    } else if (lost) {
      statusText = l10n.eliminatedTitle;
      statusColor = AppTheme.error;
    } else if (match.isInProgress) {
      statusText = l10n.matchStatusInProgress;
    } else if (joinable) {
      statusText = l10n.matchStatusWaitingPlayers;
    } else if (match.player1Id == null || match.player2Id == null) {
      statusText = l10n.startsAfterPreviousRound;
      statusColor = AppTheme.textSecondary;
    } else {
      statusText = l10n.matchStatusUpcoming;
      statusColor = AppTheme.textSecondary;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.primary.withValues(alpha: 0.16),
            AppTheme.surface,
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.yourMatchTag,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                    color: AppTheme.primary,
                  ),
                ),
              ),
              Text(
                statusText,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: statusColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _HeroPlayer(
                  username: myUsername ?? l10n.tbdLabel,
                  isMe: true,
                  isWinner: won,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Column(
                  children: [
                    Text(
                      '$myScore – $oppScore',
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    if (match.bestOf > 1)
                      Text(
                        'BO${match.bestOf}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: _HeroPlayer(
                  username: oppUsername ?? l10n.tbdLabel,
                  isMe: false,
                  isWinner: lost,
                ),
              ),
            ],
          ),
          if (joinable || resumable) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: Material(
                borderRadius: BorderRadius.circular(12),
                child: Ink(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppTheme.primary, AppTheme.primary.withValues(alpha: 0.8)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _openMatch(
                      context,
                      rejoinGameMatchId: resumable ? active.lastGameId : null,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            resumable ? Icons.play_arrow : Icons.sports_esports,
                            size: 20,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            resumable ? l10n.resumeTournamentMatch : l10n.joinTournamentMatch,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HeroPlayer extends StatelessWidget {
  final String username;
  final bool isMe;
  final bool isWinner;

  const _HeroPlayer({
    required this.username,
    required this.isMe,
    required this.isWinner,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Column(
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppTheme.surfaceLight, AppTheme.surface],
            ),
            border: Border.all(
              color: isMe
                  ? AppTheme.primary
                  : AppTheme.textSecondary.withValues(alpha: 0.3),
              width: isMe ? 2 : 1,
            ),
          ),
          child: Center(
            child: Text(
              _initials(username),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isWinner) ...[
              const Icon(Icons.emoji_events, size: 13, color: AppTheme.accent),
              const SizedBox(width: 3),
            ],
            Flexible(
              child: Text(
                username,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: isMe ? AppTheme.primary : AppTheme.textPrimary,
                ),
              ),
            ),
          ],
        ),
        if (isMe)
          Text(
            l10n.you,
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: AppTheme.primary,
            ),
          ),
      ],
    );
  }
}

/// Compact match card for the rest of the round: status stripe, one row per
/// player with leg dots, and a one-line status footer.
class _MatchCard extends StatelessWidget {
  final TournamentMatch match;
  final String? currentUserId;

  const _MatchCard({required this.match, this.currentUserId});

  Color get _stripeColor {
    if (match.isDisputed) return AppTheme.accent;
    if (match.isCompleted) return AppTheme.success;
    if (match.isInProgress) return AppTheme.primary;
    return AppTheme.surfaceLight;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    String footer;
    Color footerColor = AppTheme.textSecondary;
    IconData footerIcon = Icons.schedule;
    if (match.isDisputed) {
      footer = l10n.underReviewBadge;
      footerColor = AppTheme.accent;
      footerIcon = Icons.gavel;
    } else if (match.isCompleted) {
      footer = l10n.matchStatusCompleted;
      footerColor = AppTheme.success;
      footerIcon = Icons.check;
    } else if (match.isInProgress) {
      footer = l10n.matchStatusInProgress;
      footerColor = AppTheme.primary;
      footerIcon = Icons.sports_esports;
    } else if (match.player1Id == null || match.player2Id == null) {
      footer = l10n.startsAfterPreviousRound;
    } else if (match.isWaitingForPlayers) {
      footer = l10n.matchStatusWaitingPlayers;
    } else {
      footer = l10n.matchStatusUpcoming;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.surfaceLight.withValues(alpha: 0.6)),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 3,
              decoration: BoxDecoration(
                color: _stripeColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(14),
                  bottomLeft: Radius.circular(14),
                ),
              ),
            ),
            Expanded(
              child: Column(
                children: [
                  _PlayerRow(
                    username: match.player1Username,
                    score: match.player1Score,
                    bestOf: match.bestOf,
                    isWinner: match.winnerId != null && match.winnerId == match.player1Id,
                    isLoser: match.winnerId != null && match.winnerId == match.player2Id,
                    isCurrentUser: currentUserId != null && currentUserId == match.player1Id,
                    showScore: match.isCompleted || match.isInProgress,
                  ),
                  Divider(
                    height: 1,
                    thickness: 1,
                    color: AppTheme.surfaceLight.withValues(alpha: 0.4),
                  ),
                  _PlayerRow(
                    username: match.player2Username,
                    score: match.player2Score,
                    bestOf: match.bestOf,
                    isWinner: match.winnerId != null && match.winnerId == match.player2Id,
                    isLoser: match.winnerId != null && match.winnerId == match.player1Id,
                    isCurrentUser: currentUserId != null && currentUserId == match.player2Id,
                    showScore: match.isCompleted || match.isInProgress,
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Row(
                      children: [
                        Icon(footerIcon, size: 12, color: footerColor),
                        const SizedBox(width: 5),
                        Text(
                          footer,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: footerColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayerRow extends StatelessWidget {
  final String? username;
  final int score;
  final int bestOf;
  final bool isWinner;
  final bool isLoser;
  final bool isCurrentUser;
  final bool showScore;

  const _PlayerRow({
    required this.username,
    required this.score,
    required this.bestOf,
    required this.isWinner,
    required this.isLoser,
    required this.isCurrentUser,
    required this.showScore,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isTbd = username == null;
    final legsToWin = bestOf ~/ 2 + 1;

    return Opacity(
      opacity: isLoser ? 0.55 : 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isTbd ? AppTheme.background : AppTheme.surfaceLight,
                border: Border.all(
                  color: isCurrentUser
                      ? AppTheme.primary
                      : AppTheme.textSecondary.withValues(alpha: 0.25),
                  width: isCurrentUser ? 1.5 : 1,
                ),
              ),
              child: Center(
                child: Text(
                  _initials(username),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isTbd ? AppTheme.textSecondary : AppTheme.textPrimary,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            if (isWinner) ...[
              const Icon(Icons.emoji_events, size: 14, color: AppTheme.accent),
              const SizedBox(width: 4),
            ],
            Expanded(
              child: Text(
                username ?? l10n.tbdLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontStyle: isTbd ? FontStyle.italic : FontStyle.normal,
                  fontWeight: isWinner || isCurrentUser ? FontWeight.w700 : FontWeight.w500,
                  color: isTbd
                      ? AppTheme.textSecondary
                      : isCurrentUser
                          ? AppTheme.primary
                          : AppTheme.textPrimary,
                ),
              ),
            ),
            if (isCurrentUser)
              Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  l10n.you,
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primary,
                  ),
                ),
              ),
            if (showScore && bestOf > 1) ...[
              Row(
                children: List.generate(legsToWin, (i) {
                  final wonLeg = i < score;
                  return Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.only(right: 3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: wonLeg ? AppTheme.success : AppTheme.surfaceLight,
                    ),
                  );
                }),
              ),
              const SizedBox(width: 6),
            ],
            SizedBox(
              width: 20,
              child: Text(
                showScore ? '$score' : '–',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: isWinner
                      ? AppTheme.success
                      : showScore
                          ? AppTheme.textPrimary
                          : AppTheme.textSecondary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Gold celebration card shown on the final's page once the tournament has a
/// winner.
class _ChampionCard extends StatelessWidget {
  final Tournament tournament;

  const _ChampionCard({required this.tournament});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppTheme.accent.withValues(alpha: 0.16),
            AppTheme.surface,
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.45)),
      ),
      child: Column(
        children: [
          const Icon(Icons.emoji_events, size: 36, color: AppTheme.accent),
          const SizedBox(height: 8),
          Text(
            l10n.championCrowned(tournament.winnerUsername ?? l10n.winner),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '+${tournament.winnerEloReward} ELO',
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
      final allowed = await TournamentRegistrationGate.run(context, widget.tournament);
      if (!allowed || !mounted) return;
    }

    setState(() => _isLoading = true);
    HapticService.lightImpact();

    final provider = context.read<TournamentProvider>();
    bool success;

    if (widget.isRegistered) {
      success = await provider.unregisterFromTournament(widget.tournament.id);
    } else {
      success = await provider.registerForTournament(widget.tournament.id, tournament: widget.tournament);
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
          border: Border.all(color: AppTheme.textSecondary.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.schedule, size: 18, color: AppTheme.textSecondary.withValues(alpha: 0.8)),
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
                colors: [AppTheme.primary, AppTheme.primary.withValues(alpha: 0.8)],
              ),
        color: widget.isRegistered ? AppTheme.success.withValues(alpha: 0.15) : null,
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
                        widget.isRegistered ? Icons.check_circle : Icons.add_circle_outline,
                        size: 20,
                        color: widget.isRegistered ? AppTheme.success : Colors.white,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        widget.isRegistered ? l10n.unregister : l10n.registerNow,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: widget.isRegistered ? AppTheme.success : Colors.white,
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

class _ParticipantsTab extends StatefulWidget {
  final String tournamentId;

  const _ParticipantsTab({required this.tournamentId});

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
      final regs = await TournamentService.getRegistrations(widget.tournamentId);
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

  Color _getRankColor(String? rank) {
    switch (rank) {
      case 'master':
        return const Color(0xFFFF4081);
      case 'diamond':
        return const Color(0xFF00BCD4);
      case 'platinum':
        return const Color(0xFF9C27B0);
      case 'gold':
        return const Color(0xFFFFD700);
      case 'silver':
        return const Color(0xFFC0C0C0);
      case 'bronze':
        return const Color(0xFFCD7F32);
      default:
        return AppTheme.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final authProvider = context.read<AuthProvider>();
    final currentUserId = authProvider.currentUser?.id;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_registrations == null || _registrations!.isEmpty) {
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
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 16,
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: _registrations!.length,
      itemBuilder: (context, index) {
        final reg = _registrations![index];
        final isCurrentUser = reg.userId == currentUserId;
        final rankColor = _getRankColor(reg.rank);

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppTheme.surface,
                AppTheme.surfaceLight.withValues(alpha: 0.3),
              ],
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isCurrentUser
                  ? AppTheme.primary.withValues(alpha: 0.5)
                  : AppTheme.surfaceLight.withValues(alpha: 0.3),
              width: isCurrentUser ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: rankColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: rankColor,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        reg.username ?? 'Unknown',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: isCurrentUser ? AppTheme.primary : AppTheme.textPrimary,
                        ),
                      ),
                    ),
                    if (isCurrentUser) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          l10n.you,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: rankColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: rankColor.withValues(alpha: 0.3)),
                ),
                child: Text(
                  reg.rankDisplay,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: rankColor,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
