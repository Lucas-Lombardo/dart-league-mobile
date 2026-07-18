import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/subscription_provider.dart';
import '../../providers/match_invite_provider.dart';
import '../../providers/placement_provider.dart';
import '../../providers/tournament_provider.dart';
import '../../widgets/recent_matches_widget.dart';
import '../../services/user_service.dart';
import '../../services/match_service.dart';
import '../../services/tournament_service.dart';
import '../../models/match.dart';
import '../../models/tournament.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/round_labels.dart';
import '../../utils/haptic_service.dart';
import '../../utils/app_theme.dart';
import '../../utils/rank_utils.dart';
import '../matchmaking/camera_setup_screen.dart';
import '../matchmaking/friend_select_screen.dart';
import '../local_match/local_match_setup_screen.dart';
import 'play_mode_sheet.dart';
import '../placement/placement_hub_screen.dart';
import '../tournament/tournament_camera_setup_screen.dart';
import '../profile/match_history_screen.dart';
import '../settings/subscription_screen.dart';
import '../training/training_select_screen.dart';

class PlayScreen extends StatefulWidget {
  final ValueNotifier<int>? refreshNotifier;
  const PlayScreen({super.key, this.refreshNotifier});

  @override
  State<PlayScreen> createState() => _PlayScreenState();
}


class _PlayScreenState extends State<PlayScreen> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  List<Match> _recentMatches = [];
  bool _loadingMatches = false;
  Map<String, dynamic>? _activeMatch;
  TournamentMatch? _pendingTournamentMatch;
  TournamentMatch? _activeTournamentLeg;
  TournamentProvider? _tournamentProvider;
  bool _inActiveTournament = false;
  String? _activeTournamentName;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeInOut,
      ),
    );
    
    _loadRecentMatches();
    _checkActiveMatch();
    _checkPendingTournamentMatch();
    _checkActiveTournamentStatus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshSubscription();
      // Live tournament state: the provider is refreshed by its 30s poll,
      // socket events and push taps — following it here means the Join /
      // Resume button flips while the user idles on this tab.
      if (!mounted) return;
      _loadPlacementStatusIfUnranked();
      _tournamentProvider = context.read<TournamentProvider>();
      _tournamentProvider!.addListener(_syncFromTournamentProvider);
      _syncFromTournamentProvider();
    });

    widget.refreshNotifier?.addListener(_onRefresh);
  }

  void _syncFromTournamentProvider() {
    final tp = _tournamentProvider;
    if (tp == null || !mounted) return;
    final pending = tp.pendingMatches.isNotEmpty ? tp.pendingMatches.first : null;
    final activeLeg = (tp.activeMatch?.isInProgress ?? false) ? tp.activeMatch : null;
    if (pending?.id == _pendingTournamentMatch?.id &&
        activeLeg?.id == _activeTournamentLeg?.id) {
      return;
    }
    setState(() {
      _pendingTournamentMatch = pending;
      _activeTournamentLeg = activeLeg;
    });
  }

  void _onRefresh() {
    _loadRecentMatches();
    _checkActiveMatch();
    _checkPendingTournamentMatch();
    _checkActiveTournamentStatus();
    _refreshSubscription();
    _loadPlacementStatusIfUnranked();
  }

  /// Feeds the placement-progress ring; only relevant while unranked.
  void _loadPlacementStatusIfUnranked() {
    if (!mounted) return;
    final rank = context.read<AuthProvider>().currentUser?.rank;
    if (rank?.toLowerCase() == 'unranked') {
      context.read<PlacementProvider>().loadStatus();
    }
  }

  Future<void> _refreshSubscription() async {
    if (!mounted) return;
    await context.read<SubscriptionProvider>().refresh();
  }

  /// Opens the play-mode selector, then routes to the ranked queue or the
  /// friend picker depending on the choice.
  Future<void> _onPlayTapped() async {
    HapticService.mediumImpact();
    final mode = await showPlayModeSheet(context);
    if (mode == null || !mounted) return;
    switch (mode) {
      case PlayMode.competitive:
        // Free users who've already used their daily ranked match are nudged
        // to Premium instead of entering the queue.
        if (context.read<SubscriptionProvider>().hasReachedDailyLimit) {
          _showDailyLimitDialog();
          return;
        }
        _startCompetitive();
        break;
      case PlayMode.friend:
        // Friendly matches are premium-gated inside FriendlyMatchLauncher,
        // which shows the upgrade popup for non-premium users on invite.
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => const FriendSelectScreen(),
          ),
        ).then((_) {
          if (mounted) _refreshSubscription();
        });
        break;
      case PlayMode.local:
        // Hot-seat 1v1 — fully local, no stats, no backend. Free for everyone.
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => const LocalMatchSetupScreen(),
          ),
        );
        break;
    }
  }

  /// Ranked path — unchanged from before: camera gate, then matchmaking queue.
  void _startCompetitive() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const CameraSetupScreen(),
      ),
    ).then((_) {
      if (!mounted) return;
      setState(() => _activeMatch = null);
      _checkActiveMatch();
      _checkPendingTournamentMatch();
      _checkActiveTournamentStatus();
      _refreshSubscription();
    });
  }

  /// Shown when a free user who has used their daily ranked match tries to
  /// start another competitive match. Offers an upgrade path to Premium.
  void _showDailyLimitDialog() {
    final l10n = AppLocalizations.of(context);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text(l10n.dailyLimitReachedShort,
            style: const TextStyle(color: Colors.white)),
        content: Text(l10n.goPremiumUnlimited,
            style: const TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.cancel,
                style: const TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SubscriptionScreen()),
              ).then((_) => _refreshSubscription());
            },
            child: Text(l10n.upgrade),
          ),
        ],
      ),
    );
  }

  Future<void> _checkActiveMatch() async {
    try {
      final auth = context.read<AuthProvider>();
      if (auth.currentUser?.id != null) {
        final result = await MatchService.getActiveMatch(auth.currentUser!.id);
        if (mounted) {
          setState(() {
            _activeMatch = (result['active'] == true) ? result : null;
          });
        }
      }
    } catch (e) {
      // Failed to check for active match
    }
  }

  Future<void> _checkPendingTournamentMatch() async {
    try {
      // Route through the provider: its listener sync (above) updates the
      // local fields, and every other refresher (poll, sockets, push taps)
      // flows through the same state.
      final tp = context.read<TournamentProvider>();
      await Future.wait([tp.loadPendingMatches(), tp.loadActiveMatch()]);
    } catch (e) {
      // Failed to check for pending tournament match
    }
  }

  Future<void> _checkActiveTournamentStatus() async {
    try {
      final status = await TournamentService.getActiveTournamentStatus();
      if (mounted) {
        setState(() {
          _inActiveTournament = status['inActiveTournament'] as bool? ?? false;
          _activeTournamentName = status['tournamentName'] as String?;
        });
      }
    } catch (e) {
      // Failed to check tournament status
    }
  }

  // Re-enter a live tournament leg after an app kill: camera first, then the
  // game screen re-joins the match room and the server re-syncs state.
  void _resumeTournamentLeg() {
    final match = _activeTournamentLeg;
    if (match == null || match.lastGameId == null) return;

    HapticService.mediumImpact();
    final auth = context.read<AuthProvider>();
    final currentUserId = auth.currentUser?.id;
    final isPlayer1 = currentUserId == match.player1Id;
    final opponentUsername = isPlayer1
        ? (match.player2Username ?? 'Opponent')
        : (match.player1Username ?? 'Opponent');
    final opponentId = isPlayer1 ? (match.player2Id ?? '') : (match.player1Id ?? '');

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => TournamentCameraSetupScreen(
          matchId: match.id,
          tournamentId: match.tournamentId,
          tournamentName: match.tournamentName ?? 'Tournament',
          roundName: match.roundName,
          opponentUsername: opponentUsername,
          opponentId: opponentId,
          player1Id: match.player1Id ?? '',
          player2Id: match.player2Id ?? '',
          bestOf: match.bestOf,
          inviteSentAt: match.inviteSentAt,
          rejoinGameMatchId: match.lastGameId,
        ),
      ),
    ).then((_) {
      if (mounted) _checkPendingTournamentMatch();
    });
  }

  Future<void> _rejoinMatch() async {
    if (_activeMatch == null) return;

    HapticService.mediumImpact();

    final matchId = _activeMatch!['matchId'] as String?;
    final opponentId = _activeMatch!['opponentId'] as String?;
    final opponentUsername = _activeMatch!['opponentUsername'] as String?;

    if (matchId == null) return;

    // Clear optimistically — re-check on return in case it's still active
    setState(() => _activeMatch = null);

    if (mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => CameraSetupScreen(
            rejoinMatchId: matchId,
            rejoinOpponentId: opponentId,
            rejoinOpponentUsername: opponentUsername,
          ),
        ),
      ).then((_) {
        _checkActiveMatch();
        _loadRecentMatches();
      });
    }
  }

  Future<void> _loadRecentMatches() async {
    setState(() => _loadingMatches = true);
    try {
      final auth = context.read<AuthProvider>();
      if (auth.currentUser?.id != null) {
        final matches = await UserService.getUserMatches(auth.currentUser!.id, limit: 3);
        if (mounted) {
          setState(() {
            _recentMatches = matches;
            _loadingMatches = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingMatches = false);
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkActiveMatch();
      _checkPendingTournamentMatch();
      _checkActiveTournamentStatus();
      _refreshSubscription();
    }
  }

  Widget _buildFreeTierHint(SubscriptionProvider subscription) {
    final l10n = AppLocalizations.of(context);
    final remaining = subscription.matchesRemainingToday ?? 0;
    final mainLine = remaining > 0 ? l10n.freeTierMatchAvailable : l10n.freeTierMatchUsed;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () {
        HapticService.lightImpact();
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const SubscriptionScreen()),
        ).then((_) => _refreshSubscription());
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFEAB308).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: const Color(0xFFEAB308).withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.workspace_premium, color: Color(0xFFEAB308), size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    mainLine,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    l10n.tapToUpgradeForUnlimited,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Color(0xFFEAB308)),
          ],
        ),
      ),
    );
  }

  /// Celebratory banner shown while the weekly Free Play window is live
  /// (Sat 20:00–00:00 Europe/Paris): unlimited ranked + free friend matches.
  Widget _buildFreePlayBanner() {
    final l10n = AppLocalizations.of(context);
    const green = Color(0xFF22C55E);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: green.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: green.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.celebration, color: green, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.freePlayBannerTitle,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  l10n.freePlayBannerSubtitle,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUnrankedFreeTierHint() {
    final l10n = AppLocalizations.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () {
        HapticService.lightImpact();
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const SubscriptionScreen()),
        ).then((_) => _refreshSubscription());
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFEAB308).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: const Color(0xFFEAB308).withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline, color: Color(0xFFEAB308), size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.unrankedFreeTierHint,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    l10n.tapToLearnAboutPremium,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Color(0xFFEAB308)),
          ],
        ),
      ),
    );
  }

  /// The big action card when a friend invite is pending. Mirrors the tournament
  /// "Join match" card; tapping it asks the player to accept or decline.
  Widget _buildFriendInviteButton(IncomingInvite invite, AppLocalizations l10n) {
    return ScaleTransition(
      scale: _pulseAnimation,
      child: GestureDetector(
        onTap: () => _onFriendInviteTapped(invite),
        child: Container(
          height: 180,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF10B981), Color(0xFF059669)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF10B981).withValues(alpha: 0.4),
                blurRadius: 20,
                spreadRadius: 2,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                right: -20,
                top: -20,
                child: Icon(
                  Icons.group,
                  size: 150,
                  color: Colors.white.withValues(alpha: 0.1),
                ),
              ),
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.sports_esports,
                        size: 48,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      l10n.joinMatch,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        l10n.invitedYouToMatch
                            .replaceAll('{username}', invite.inviterUsername),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Accept/decline a friend invite. Accept routes through the same camera gate
  /// as ranked/tournament, then sends accept_invite; the global FriendMatchGate
  /// handles the friendly_match_found → GameScreen navigation.
  Future<void> _onFriendInviteTapped(IncomingInvite invite) async {
    HapticService.mediumImpact();
    final l10n = AppLocalizations.of(context);
    final inviteProvider = context.read<MatchInviteProvider>();
    final navigator = Navigator.of(context);

    final choice = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text(l10n.matchInviteTitle,
            style: const TextStyle(color: Colors.white)),
        content: Text(
          l10n.invitedYouToMatch
              .replaceAll('{username}', invite.inviterUsername),
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.declineInvite,
                style: const TextStyle(color: AppTheme.error)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.joinMatch),
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (choice == true) {
      final ready = await navigator.push<bool>(
        MaterialPageRoute(
          builder: (_) => CameraSetupScreen(
            actionLabel: l10n.joinMatch,
            confirmAndPop: true,
          ),
        ),
      );
      if (ready == true) inviteProvider.accept(invite.inviteId);
    } else if (choice == false) {
      inviteProvider.decline(invite.inviteId);
    }
    // choice == null (dismissed) → leave the invite pending; the button stays.
  }

  @override
  void dispose() {
    widget.refreshNotifier?.removeListener(_onRefresh);
    _tournamentProvider?.removeListener(_syncFromTournamentProvider);
    WidgetsBinding.instance.removeObserver(this);
    _pulseController.dispose();
    super.dispose();
  }

  String _getNextRank(String currentRank) {
    switch (currentRank.toLowerCase()) {
      case 'bronze':
        return 'Silver';
      case 'silver':
        return 'Gold';
      case 'gold':
        return 'Platinum';
      case 'platinum':
        return 'Diamond';
      case 'diamond':
        return 'Master';
      case 'master':
        return 'Master';
      default:
        return 'Bronze';
    }
  }

  Map<String, int> get _rankThresholds => {
    'bronze': 0,
    'silver': 1000,
    'gold': 1500,
    'platinum': 2000,
    'diamond': 2500,
    'master': 3000,
  };

  int _getEloNeededForNextRank(String currentRank, int currentElo) {
    final nextRank = _getNextRank(currentRank).toLowerCase();
    final threshold = _rankThresholds[nextRank] ?? 1400;
    return threshold - currentElo;
  }

  /// Last five results as win/loss chips (oldest → newest) plus the current
  /// win streak when there is one.
  Widget _buildFormRow(String userId, AppLocalizations l10n) {
    final dots = _recentMatches.take(5).toList().reversed.toList();
    var streak = 0;
    for (final match in _recentMatches) {
      if (match.isWinner(userId)) {
        streak++;
      } else {
        break;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.surfaceLight.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          Text(
            l10n.formLabel,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(width: 12),
          ...dots.map((match) {
            final won = match.isWinner(userId);
            return Container(
              width: 22,
              height: 22,
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                color: (won ? AppTheme.success : AppTheme.error).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Center(
                child: Text(
                  won ? l10n.formWinLetter : l10n.formLossLetter,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: won ? AppTheme.success : AppTheme.error,
                  ),
                ),
              ),
            );
          }),
          if (streak >= 2)
            Expanded(
              child: Text(
                l10n.winStreak(streak),
                textAlign: TextAlign.right,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.success,
                ),
              ),
            ),
        ],
      ),
    );
  }

  double _getRankProgress(String currentRank, int currentElo) {
    final currentThreshold = _rankThresholds[currentRank.toLowerCase()] ?? 1200;
    final nextRank = _getNextRank(currentRank).toLowerCase();
    final nextThreshold = _rankThresholds[nextRank] ?? 1400;
    
    if (currentRank.toLowerCase() == 'master' && currentElo >= nextThreshold) {
      return 1.0;
    }
    
    final rangeSize = nextThreshold - currentThreshold;
    final progress = (currentElo - currentThreshold) / rangeSize;
    return progress.clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;
    final subscription = context.watch<SubscriptionProvider>();
    final matchInvite = context.watch<MatchInviteProvider>();
    final l10n = AppLocalizations.of(context);

    if (user == null) {
      return Center(
        child: Text(l10n.userNotFound),
      );
    }

    final eloNeeded = _getEloNeededForNextRank(user.rank, user.elo);
    final currentRank = user.rank;
    final nextRank = _getNextRank(user.rank);
    final progress = _getRankProgress(user.rank, user.elo);

    final isUnranked = user.rank.toLowerCase() == 'unranked';

    return RefreshIndicator(
      color: AppTheme.primary,
      onRefresh: () async {
        await Future.wait([
          _loadRecentMatches(),
          _checkActiveMatch(),
          _checkPendingTournamentMatch(),
          _checkActiveTournamentStatus(),
        ]);
      },
      child: SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isUnranked)
            // Unranked: the unranked badge inside a gold placement-progress
            // ring — same hero language as the ranked ELO ring (B2 redesign).
            _PlacementRingHero(
              matchesPlayed:
                  context.watch<PlacementProvider>().status?.matchesPlayed ?? 0,
            )
          else
            // Ranked: the rank badge inside an ELO progress ring (B2 redesign)
            _RankRingHero(
              rank: currentRank,
              elo: user.elo,
              nextRank: nextRank,
              eloNeeded: eloNeeded,
              progress: progress,
            ),
          const SizedBox(height: 20),
          if (matchInvite.incoming != null)
            // Friend invite — the whole Play button becomes "Join the match".
            // Highest priority: the inviter is actively waiting and the invite
            // is short-lived. (The backend refuses to invite a busy player, so
            // this can't collide with an active-match rejoin.)
            _buildFriendInviteButton(matchInvite.incoming!, l10n)
          else if (isUnranked) ...[
            // Placement bar — same CTA language as the ranked play bar, in
            // gold (B2 redesign). The explanation lives in the hero above.
            ScaleTransition(
              scale: _pulseAnimation,
              child: GestureDetector(
                onTap: () {
                  HapticService.mediumImpact();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const PlacementHubScreen(),
                    ),
                  ).then((_) {
                    if (!mounted) return;
                    // Reload matches and user data after returning
                    _loadRecentMatches();
                    context.read<AuthProvider>().checkAuthStatus();
                    context.read<PlacementProvider>().loadStatus();
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 17),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFEAB308), Color(0xFFF59E0B)],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFEAB308).withValues(alpha: 0.35),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.emoji_events, size: 22, color: Colors.white),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          l10n.placementMatches.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (!subscription.isPremiumActive) ...[
              const SizedBox(height: 12),
              _buildUnrankedFreeTierHint(),
            ],
          ]
          else if (_activeTournamentLeg?.lastGameId != null)
            // A tournament leg is LIVE for this player (app was killed
            // mid-match) — resuming outranks everything: the disconnect grace
            // timer is running server-side.
            ScaleTransition(
              scale: _pulseAnimation,
              child: GestureDetector(
                onTap: _resumeTournamentLeg,
                child: Container(
                  height: 180,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF7C3AED), Color(0xFF9333EA)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF7C3AED).withValues(alpha: 0.4),
                        blurRadius: 20,
                        spreadRadius: 2,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        right: -20,
                        top: -20,
                        child: Icon(
                          Icons.emoji_events,
                          size: 150,
                          color: Colors.white.withValues(alpha: 0.1),
                        ),
                      ),
                      Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.replay_rounded,
                                size: 48,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              l10n.resumeTournamentMatch,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 2,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${_activeTournamentLeg!.tournamentName ?? 'Tournament'} — ${localizedRoundLabel(AppLocalizations.of(context), _activeTournamentLeg!)}',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.8),
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else if (_pendingTournamentMatch != null)
            // Join Tournament Match button (highest priority after placement)
            ScaleTransition(
              scale: _pulseAnimation,
              child: GestureDetector(
                onTap: () {
                  HapticService.mediumImpact();
                  final match = _pendingTournamentMatch!;
                  final auth = context.read<AuthProvider>();
                  final currentUserId = auth.currentUser?.id;
                  final isPlayer1 = currentUserId == match.player1Id;
                  final opponentUsername = isPlayer1 ? (match.player2Username ?? 'Opponent') : (match.player1Username ?? 'Opponent');
                  final opponentId = isPlayer1 ? (match.player2Id ?? '') : (match.player1Id ?? '');

                  if (context.mounted) {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => TournamentCameraSetupScreen(
                          matchId: match.id,
                          tournamentId: match.tournamentId,
                          tournamentName: match.tournamentName ?? 'Tournament',
                          roundName: match.roundName,
                          opponentUsername: opponentUsername,
                          opponentId: opponentId,
                          player1Id: match.player1Id ?? '',
                          player2Id: match.player2Id ?? '',
                          bestOf: match.bestOf,
                          inviteSentAt: match.inviteSentAt,
                        ),
                      ),
                    );
                  }
                },
                child: Container(
                  height: 180,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF7C3AED), Color(0xFF9333EA)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF7C3AED).withValues(alpha: 0.4),
                        blurRadius: 20,
                        spreadRadius: 2,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        right: -20,
                        top: -20,
                        child: Icon(
                          Icons.emoji_events,
                          size: 150,
                          color: Colors.white.withValues(alpha: 0.1),
                        ),
                      ),
                      Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.play_arrow_rounded,
                                size: 48,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              l10n.joinMatch,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 2,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${_pendingTournamentMatch!.tournamentName ?? 'Tournament'} — ${localizedRoundLabel(AppLocalizations.of(context), _pendingTournamentMatch!)}',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.8),
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else if (_activeMatch != null)
            // Rejoin active ranked match
            ScaleTransition(
              scale: _pulseAnimation,
              child: GestureDetector(
                onTap: _rejoinMatch,
                child: Container(
                  height: 180,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFF6B00), Color(0xFFFF9500)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFF6B00).withValues(alpha: 0.4),
                        blurRadius: 20,
                        spreadRadius: 2,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        right: -20,
                        top: -20,
                        child: Icon(
                          Icons.refresh,
                          size: 150,
                          color: Colors.white.withValues(alpha: 0.1),
                        ),
                      ),
                      Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.arrow_forward_rounded,
                                size: 48,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              l10n.play,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 2,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${l10n.rejoinVs} ${_activeMatch!['opponentUsername']}',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.8),
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else if (_inActiveTournament)
            // Blocked: In active tournament
            Container(
              height: 180,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppTheme.surfaceLight.withValues(alpha: 0.8),
                    AppTheme.surface,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppTheme.surfaceLight),
              ),
              child: Stack(
                children: [
                  Positioned(
                    right: -20,
                    top: -20,
                    child: Icon(
                      Icons.block,
                      size: 150,
                      color: Colors.white.withValues(alpha: 0.05),
                    ),
                  ),
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppTheme.accent.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.emoji_events,
                            size: 40,
                            color: AppTheme.accent,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          l10n.rankedLocked,
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${l10n.activeTournament}: ${_activeTournamentName ?? l10n.tournament}',
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 13,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )
          else ...[
            // The play button is always shown for free users now; the
            // daily-match hint stays visible (it reads "match used" once the
            // free match is spent) and tapping Play surfaces the upgrade popup.
            // During Free Play, the upsell hint is replaced by a celebratory
            // "it's free tonight" banner.
            if (subscription.freePlayActive) ...[
              _buildFreePlayBanner(),
              const SizedBox(height: 12),
            ] else if (!subscription.isPremiumActive &&
                subscription.matchesRemainingToday != null) ...[
              _buildFreeTierHint(subscription),
              const SizedBox(height: 12),
            ],
            // Play bar — full-width CTA; mode choice stays in the sheet
            // opened by _onPlayTapped (B2 redesign).
            ScaleTransition(
              scale: _pulseAnimation,
              child: GestureDetector(
                onTap: _onPlayTapped,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 17),
                  decoration: BoxDecoration(
                    gradient: AppTheme.primaryGradient,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primary.withValues(alpha: 0.35),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.track_changes, size: 22, color: Colors.white),
                      const SizedBox(width: 10),
                      Text(
                        l10n.play.toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          GestureDetector(
            onTap: () {
              HapticService.mediumImpact();
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const TrainingSelectScreen(),
                ),
              );
            },
            child: Container(
              height: 84,
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: AppTheme.surfaceLight.withValues(alpha: 0.6),
                ),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 16),
                  Container(
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: AppTheme.accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.fitness_center,
                      color: AppTheme.accent,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          l10n.trainingPlayCardTitle,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          l10n.trainingPlayCardSubtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: AppTheme.textSecondary),
                  const SizedBox(width: 12),
                ],
              ),
            ),
          ),
          if (_recentMatches.isNotEmpty && user.rank.toLowerCase() != 'unranked') ...[
            const SizedBox(height: 12),
            _buildFormRow(user.id, l10n),
          ],
          const SizedBox(height: 28),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                l10n.recentMatches,
                style: AppTheme.titleLarge,
              ),
              if (!_loadingMatches)
                TextButton(
                  onPressed: () {
                    HapticService.lightImpact();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const MatchHistoryScreen(),
                      ),
                    );
                  },
                  child: Text(l10n.viewAll),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (_loadingMatches)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32.0),
                child: CircularProgressIndicator(color: AppTheme.primary),
              ),
            )
          else if (_recentMatches.isNotEmpty)
            RecentMatchesWidget(
              matches: _recentMatches,
              userId: user.id,
            )
          else
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.surfaceLight),
              ),
              child: Column(
                children: [
                  const Icon(Icons.history, size: 48, color: AppTheme.textSecondary),
                  const SizedBox(height: 16),
                  Text(
                    l10n.noMatchesYet,
                    style: AppTheme.bodyLarge.copyWith(color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.playFirstGameToSeeHistory,
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppTheme.surfaceLight.withValues(alpha: 0.5),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.tips_and_updates_outlined, color: AppTheme.primary),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.proTipLabel,
                        style: const TextStyle(
                          color: AppTheme.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l10n.proTips[DateTime.now().weekday % l10n.proTips.length],
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 14,
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

/// Rank badge inside a circular ELO progress ring, with the points needed for
/// the next rank underneath (home B2 redesign).
class _RankRingHero extends StatelessWidget {
  final String rank;
  final int elo;
  final String nextRank;
  final int eloNeeded;
  final double progress;

  const _RankRingHero({
    required this.rank,
    required this.elo,
    required this.nextRank,
    required this.eloNeeded,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isMaxRank = rank.toLowerCase() == 'master';
    final percent = (progress * 100).round();

    return Column(
      children: [
        SizedBox(
          width: 176,
          height: 176,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 176,
                height: 176,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppTheme.accent.withValues(alpha: 0.12),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.78],
                  ),
                ),
              ),
              CustomPaint(
                size: const Size(152, 152),
                painter: _EloRingPainter(isMaxRank ? 1.0 : progress),
              ),
              RankUtils.getRankBadge(rank, size: 92),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              '$elo',
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 5),
            const Text(
              'ELO',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        if (isMaxRank)
          Text(
            l10n.maxRankReached,
            style: const TextStyle(
              fontSize: 12.5,
              color: AppTheme.textSecondary,
            ),
          )
        else
          Text.rich(
            TextSpan(
              style: const TextStyle(
                fontSize: 12.5,
                color: AppTheme.textSecondary,
              ),
              children: [
                TextSpan(text: '$nextRank ${l10n.nextRankConnector} '),
                TextSpan(
                  text: '+${math.max(eloNeeded, 0)} pts',
                  style: const TextStyle(
                    color: AppTheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                TextSpan(text: ' · $percent %'),
              ],
            ),
          ),
      ],
    );
  }
}

class _EloRingPainter extends CustomPainter {
  final double progress;
  final Color color;

  const _EloRingPainter(this.progress, {this.color = AppTheme.primary});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.width - 10) / 2;

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..color = const Color(0xFF233046);
    canvas.drawCircle(center, radius, track);

    final clamped = progress.clamp(0.0, 1.0);
    if (clamped <= 0) return;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final sweep = 2 * math.pi * clamped;

    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: 0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawArc(rect, -math.pi / 2, sweep, false, glow);

    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(rect, -math.pi / 2, sweep, false, arc);
  }

  @override
  bool shouldRepaint(_EloRingPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}

/// Unranked twin of [_RankRingHero]: the unranked badge inside a gold ring
/// tracking placement progress (X of 4 matches played).
class _PlacementRingHero extends StatelessWidget {
  final int matchesPlayed;

  /// Mirrors the backend's TOTAL_PLACEMENT_MATCHES (and the 4 hardcoded in
  /// PlacementHubScreen).
  static const int _totalMatches = 4;

  const _PlacementRingHero({required this.matchesPlayed});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final played = matchesPlayed.clamp(0, _totalMatches);

    return Column(
      children: [
        SizedBox(
          width: 176,
          height: 176,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 176,
                height: 176,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppTheme.accent.withValues(alpha: 0.12),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.78],
                  ),
                ),
              ),
              CustomPaint(
                size: const Size(152, 152),
                painter: _EloRingPainter(
                  played / _totalMatches,
                  color: AppTheme.accent,
                ),
              ),
              RankUtils.getRankBadge('unranked', size: 92),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              '$played / $_totalMatches',
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              l10n.placementMatches.toUpperCase(),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            l10n.completePlacementToUnlock,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12.5,
              color: AppTheme.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}
