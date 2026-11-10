import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/subscription_provider.dart';
import '../../providers/match_invite_provider.dart';
import '../../providers/placement_provider.dart';
import '../../providers/tournament_provider.dart';
import '../../providers/season_provider.dart';
import '../../providers/progression_provider.dart';
import '../progression/locker_screen.dart';
import '../progression/progression_format.dart';
import '../ghost/ghost_play_row.dart';
import 'home_other_modes.dart';
import '../league/league_store.dart';
import '../challenge/challenge_api.dart';
import '../challenge/challenge_entry.dart';
import '../league/league_widgets.dart';
import '../../widgets/recent_matches_widget.dart';
import '../../widgets/design_system.dart';
import '../../widgets/home_tiles.dart';
import '../../widgets/progression/metal.dart';
import '../../widgets/progression/player_showcase_card.dart';
import '../../services/socket_service.dart';
import '../../services/spectate_service.dart';
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
import '../../utils/rank_translation.dart';
import '../matchmaking/camera_setup_screen.dart';
import '../matchmaking/friend_select_screen.dart';
import '../local_match/local_match_entry_screen.dart';
import '../../models/user.dart';
import '../../models/progression.dart';
import '../placement/placement_hub_screen.dart';
import '../onboarding/onboarding_home_card.dart';
import '../onboarding/onboarding_provider.dart';
import '../tournament/tournament_camera_setup_screen.dart';
import '../profile/match_history_screen.dart';
import '../settings/subscription_screen.dart';
import '../training/training_select_screen.dart';
import 'competitive_card.dart';
import 'home_quest_strip.dart';

class PlayScreen extends StatefulWidget {
  final ValueNotifier<int>? refreshNotifier;
  const PlayScreen({super.key, this.refreshNotifier});

  @override
  State<PlayScreen> createState() => _PlayScreenState();
}


class _PlayScreenState extends State<PlayScreen> with WidgetsBindingObserver {
  List<Match> _recentMatches = [];
  bool _loadingMatches = false;
  Map<String, dynamic>? _activeMatch;
  TournamentMatch? _pendingTournamentMatch;
  TournamentMatch? _activeTournamentLeg;
  TournamentProvider? _tournamentProvider;
  bool _inActiveTournament = false;
  String? _activeTournamentName;
  /// Live matches (ranked + tournament) and live ranked series alone, for
  /// the strip at the bottom of Compétitif.
  int _liveCount = 0;
  int _liveRanked = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadRecentMatches();
    _checkActiveMatch();
    _checkPendingTournamentMatch();
    _checkActiveTournamentStatus();
    _loadLiveCount();
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
    _loadLiveCount();
  }

  /// Feeds the live strip of Compétitif; 0 (no capability, error, nothing
  /// live) shows its quiet line. Gated on the handshake's supportsSpectate so
  /// a pre-spectate backend is never polled (guaranteed 404 otherwise).
  Future<void> _loadLiveCount() async {
    try {
      await SocketService.ensureAuthenticated();
    } catch (_) {}
    if (!SocketService.supportsSpectate) {
      if (mounted && (_liveCount != 0 || _liveRanked != 0)) {
        setState(() => _liveCount = _liveRanked = 0);
      }
      return;
    }
    final live = await SpectateService.fetchLive();
    if (mounted) {
      setState(() {
        _liveCount = live?.liveCount ?? 0;
        _liveRanked = live?.ranked.length ?? 0;
      });
    }
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

  /// Quiet hint row (free tier, free play, unranked): icon, up to two lines,
  /// optional secondary line, chevron when tappable.
  Widget _hintRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    VoidCallback? onTap,
  }) {
    return DsCard(
      radius: AppTheme.radiusRow,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, size: 20, color: iconColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                    height: 1.3,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.caption,
                  ),
                ],
              ],
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded,
                size: 20, color: AppTheme.textTertiary),
          ],
        ],
      ),
    );
  }

  void _openPremium() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const SubscriptionScreen()))
        .then((_) {
      if (mounted) _refreshSubscription();
    });
  }

  /// Free tier: one ranked match a day. Gold is the premium color, the one
  /// place it is allowed outside the crown.
  Widget _buildFreeTierHint(SubscriptionProvider subscription) {
    final l10n = AppLocalizations.of(context);
    final remaining = subscription.matchesRemainingToday ?? 0;
    return _hintRow(
      icon: Icons.workspace_premium_rounded,
      iconColor: AppTheme.accent,
      title: remaining > 0 ? l10n.freeTierMatchAvailable : l10n.freeTierMatchUsed,
      subtitle: l10n.tapToUpgradeForUnlimited,
      onTap: _openPremium,
    );
  }

  Widget _buildFreePlayBanner() {
    final l10n = AppLocalizations.of(context);
    return _hintRow(
      icon: Icons.celebration_outlined,
      iconColor: AppTheme.success,
      title: l10n.freePlayBannerTitle,
      subtitle: l10n.freePlayBannerSubtitle,
    );
  }

  /// Compétitif: free users who've already used their daily ranked match land
  /// straight on the paywall instead of entering the queue.
  void _onCompetitiveTapped() {
    if (context.read<SubscriptionProvider>().hasReachedDailyLimit) {
      _openPremium();
      return;
    }
    _startCompetitive();
  }

  /// Friendly matches need premium (or the Free Play window): the gated tile
  /// opens the paywall directly, instead of walking the user through picking a
  /// friend only to hit the upgrade popup on invite.
  void _openFriendMatch() {
    if (!context.read<SubscriptionProvider>().canPlayFriendMatch) {
      _openPremium();
      return;
    }
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const FriendSelectScreen()))
        .then((_) {
      if (mounted) _refreshSubscription();
    });
  }

  /// Hot-seat 1v1 — fully local, no stats, no backend. Free for everyone.
  void _openLocalMatch() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LocalMatchEntryScreen()),
    );
  }

  void _openTraining() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const TrainingSelectScreen()),
    );
  }

  void _openPlacement() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const PlacementHubScreen()))
        .then((_) {
      if (!mounted) return;
      // Reload matches and user data after returning
      _loadRecentMatches();
      context.read<AuthProvider>().checkAuthStatus();
      context.read<PlacementProvider>().loadStatus();
    });
  }

  /// Join a pending tournament match: camera gate first, then the game.
  void _joinTournamentMatch(TournamentMatch match) {
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
        ),
      ),
    );
  }

  /// "CRICKET · SCORE" chip for a cricket invite (dialog + bar hint).
  Widget _inviteModeChip(IncomingInvite invite, AppLocalizations l10n) {
    final variant = invite.gameMode == 'cricket_noscore'
        ? l10n.cricketNoScoreLabel
        : l10n.cricketScoreLabel;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.success.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: AppTheme.success.withValues(alpha: 0.5)),
      ),
      child: Text(
        '${invite.isCricket ? '${l10n.cricketLabel} · $variant' : '501'} · BO${invite.bestOf}'.toUpperCase(),
        style: const TextStyle(
          color: AppTheme.success,
          fontSize: 10,
          letterSpacing: 1.2,
          fontWeight: FontWeight.w800,
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
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...[
              _inviteModeChip(invite, l10n),
              const SizedBox(height: 10),
            ],
            Text(
              l10n.invitedYouToMatch
                  .replaceAll('{username}', invite.inviterUsername),
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
          ],
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
    super.dispose();
  }

  /// My progression cosmetics: the live summary when loaded, else the copy
  /// the profile endpoint carried. Null on an old server.
  PublicCosmetics? _myCosmetics(User user) =>
      maybeWatchProgression(context)?.summary?.cosmetics ?? user.cosmetics;

  void _openLocker() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LockerScreen()));
  }

  /// The player card (S1) with, on the home only, the XP bar and the quest
  /// strip under it. Its « Modifier » opens the locker.
  Widget _buildShowcase(User user, bool isPremium) {
    final cosmetics = _myCosmetics(user);
    return PlayerShowcaseCard(
      username: user.username,
      rank: user.rank,
      cosmetics: cosmetics,
      isPremium: isPremium,
      level: maybeWatchProgression(context)?.summary?.level ?? cosmetics?.level,
      onEdit: _openLocker,
      footer: HomeQuestStrip.fromProvider(context),
    );
  }

  /// « Aujourd'hui »: the daily challenge and the weekly league, side by
  /// side (one alone takes the width); nothing until one of them answers.
  Widget _buildToday(AppLocalizations l10n, ProgressionContent? content) {
    return ListenableBuilder(
      listenable: Listenable.merge([LeagueStore.instance, ChallengeStore.instance]),
      builder: (context, _) {
        final tiles = <Widget>[
          if (ChallengeTodayTile.isVisible(context)) ChallengeTodayTile(xp: content?.xp?.challenge),
          if (LeagueTodayTile.isVisible()) LeagueTodayTile(xpForPosition: content?.leagueXpFor),
        ];
        if (tiles.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              HomeSectionTitle(l10n.questsToday),
              HomeTileRow(children: tiles),
            ],
          ),
        );
      },
    );
  }

  /// « Jouer autrement »: 3 tiles of the same size (friend and local, then
  /// training across), each with the XP it pays (server constants: GET
  /// /progression/content → xp). No ghost tile: the ghost is the ranked
  /// queue's fallback (CONTRACT §14.12).
  Widget _buildOtherModes(SubscriptionProvider subscription, XpRules? xp) {
    return HomeOtherModes(
      xp: xp,
      friendLocked: !subscription.canPlayFriendMatch,
      onFriend: _openFriendMatch,
      onLocal: _openLocalMatch,
      onTraining: _openTraining,
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;
    final subscription = context.watch<SubscriptionProvider>();
    final matchInvite = context.watch<MatchInviteProvider>();
    final l10n = AppLocalizations.of(context);

    if (user == null) {
      return Center(child: Text(l10n.userNotFound));
    }

    final isUnranked = user.rank.toLowerCase() == 'unranked';
    final seasonProvider = context.watch<SeasonProvider>();
    final isPremium = subscription.isPremiumActive;
    final content = watchProgressionContent(context);

    return RefreshIndicator(
      color: AppTheme.primary,
      onRefresh: () async {
        await Future.wait([
          _loadRecentMatches(),
          _checkActiveMatch(),
          _checkPendingTournamentMatch(),
          _checkActiveTournamentStatus(),
          _loadLiveCount(),
          context.read<ProgressionProvider>().bootstrap(),
          ?maybeReadOnboarding(context)?.refresh(),
          ChallengeStore.instance.refresh(userId: user.id),
          LeagueStore.instance.refresh(),
          GhostHomeStore.instance.load(),
        ]);
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildShowcase(user, isPremium),
            const SizedBox(height: 12),
            ..._buildCompetitive(l10n, subscription, matchInvite, seasonProvider, user, isUnranked, content?.xp),
            // "Your first 7 days" (Agent 2b): replaces « Aujourd'hui » while
            // the journey runs; renders nothing otherwise.
            const OnboardingHomeCard(topSpacing: 12),
            if (!(maybeWatchOnboarding(context)?.isActive ?? false)) _buildToday(l10n, content),
            // Daily challenge pushes (18:00 reminder, verified n°1) → screens.
            const ChallengeHomeHooks(),
            const SizedBox(height: 12),
            _buildOtherModes(subscription, content?.xp),
            // A ghost match to resume, the ghost owner's digest (and the
            // ghost's push hooks).
            const GhostHomeRows(),
            const SizedBox(height: 16),
            DsSectionHeader(
              title: l10n.recentMatches,
              actionLabel: _loadingMatches ? null : l10n.viewAll,
              onAction: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const MatchHistoryScreen()),
                );
              },
            ),
            const SizedBox(height: 12),
            if (_loadingMatches)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator(color: AppTheme.primary)),
              )
            else if (_recentMatches.isNotEmpty)
              RecentMatchesWidget(matches: _recentMatches, userId: user.id)
            else
              DsCard(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const Icon(Icons.history_rounded, size: 32, color: AppTheme.textTertiary),
                    const SizedBox(height: 10),
                    Text(l10n.noMatchesYet, textAlign: TextAlign.center, style: AppTheme.rowTitle),
                    const SizedBox(height: 4),
                    Text(
                      l10n.playFirstGameToSeeHistory,
                      textAlign: TextAlign.center,
                      style: AppTheme.caption,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Compétitif (K1) and the hints above it. CTA priority, unchanged: live
  /// tournament leg → pending tournament join → friend invite → placement →
  /// active match rejoin → tournament lock → Compétitif (with the free-tier
  /// hint, or the Free Play banner, above it). Every state keeps the block's
  /// geometry; the live strip stays at its bottom.
  List<Widget> _buildCompetitive(
    AppLocalizations l10n,
    SubscriptionProvider subscription,
    MatchInviteProvider matchInvite,
    SeasonProvider seasonProvider,
    User user,
    bool isUnranked,
    XpRules? xp,
  ) {
    CompetitiveCard event({
      required IconData icon,
      required String label,
      required String title,
      required String caption,
      required String action,
      required VoidCallback onTap,
    }) =>
        CompetitiveCard(
          leading: CompetitiveCard.iconDisc(icon),
          label: label,
          value: title,
          largeValue: false,
          caption: caption,
          actionLabel: action,
          onTap: onTap,
          liveRanked: _liveRanked,
          liveTotal: _liveCount,
        );

    final liveLeg = _activeTournamentLeg;
    if (liveLeg?.lastGameId != null) {
      // A tournament leg is LIVE for this player (app was killed mid-match) —
      // resuming outranks everything: the disconnect grace timer is running
      // server-side.
      return [
        event(
          icon: Icons.replay_rounded,
          label: '${l10n.tournament} · ${localizedRoundLabel(l10n, liveLeg!)}',
          title: liveLeg.tournamentName ?? l10n.tournament,
          caption: l10n.homeTournamentLiveCaption,
          action: l10n.homeResume,
          onTap: _resumeTournamentLeg,
        ),
      ];
    }
    final pending = _pendingTournamentMatch;
    if (pending != null) {
      // A tournament commitment outranks friend invites and placement.
      return [
        event(
          icon: Icons.emoji_events_outlined,
          label: '${l10n.tournament} · ${localizedRoundLabel(l10n, pending)}',
          title: pending.tournamentName ?? l10n.tournament,
          caption: l10n.homeTournamentReadyCaption,
          action: l10n.homeJoin,
          onTap: () => _joinTournamentMatch(pending),
        ),
      ];
    }
    final invite = matchInvite.incoming;
    if (invite != null) {
      // The inviter is actively waiting and the invite is short-lived. (The
      // backend refuses to invite a busy player, so this can't collide with
      // an active-match rejoin.)
      return [
        event(
          icon: Icons.sports_esports_outlined,
          label: l10n.matchInviteTitle,
          title: invite.inviterUsername,
          caption: '${invite.isCricket ? l10n.cricketLabel : '501'} · BO${invite.bestOf}',
          action: l10n.homeJoin,
          onTap: () => _onFriendInviteTapped(invite),
        ),
      ];
    }
    if (isUnranked) {
      // Mirrors the backend's TOTAL_PLACEMENT_MATCHES (and the 4 hardcoded in
      // PlacementHubScreen).
      const total = 4;
      final played = (context.watch<PlacementProvider>().status?.matchesPlayed ?? 0).clamp(0, total);
      return [
        CompetitiveCard(
          leading: CompetitiveCard.rankImage(RankUtils.getRankIcon('unranked')),
          label: '${l10n.competitiveModeTitle} · ${l10n.homePlacementLabel}',
          value: '$played / $total',
          progress: played / total,
          caption: played < total ? l10n.homePlacementLeft(total - played) : l10n.completePlacementToUnlock,
          actionLabel: l10n.play,
          onTap: _openPlacement,
          liveRanked: _liveRanked,
          liveTotal: _liveCount,
        ),
      ];
    }

    final rank = user.rank;
    final isMaxRank = rank.toLowerCase() == 'master';
    // Thresholds live in rank_utils (mirrors the backend's 800/1200/1600/
    // 2000/2400).
    final eloNeeded = eloNeededForNextRank(rank, user.elo);
    final me = seasonProvider.hasSeason ? seasonProvider.current?.me : null;
    String caption = isMaxRank
        ? l10n.maxRankReached
        : l10n.homeNextRankIn(RankTranslation.translate(l10n, nextRank(rank)), math.max(eloNeeded, 0));
    var label = me != null ? '${l10n.competitiveModeTitle} · #${me.position}' : l10n.competitiveModeTitle;
    VoidCallback? onTap = _onCompetitiveTapped;
    String action = l10n.play;
    String? actionXp = xp?.ranked == null ? null : l10n.homeXpGain(xp!.ranked!);
    if (_activeMatch != null) {
      caption = l10n.homeMatchInProgress('${_activeMatch!['opponentUsername'] ?? ''}');
      onTap = _rejoinMatch;
      action = l10n.homeResume;
      actionXp = null;
    } else if (_inActiveTournament) {
      label = '${l10n.activeTournament} · ${_activeTournamentName ?? l10n.tournament}';
      caption = l10n.homeRankedLockedCaption;
      onTap = null;
      actionXp = null;
    }
    return [
      // Free users: the daily-match hint stays visible (it reads "match
      // used" once the free match is spent) and tapping Compétitif then
      // opens the paywall. During Free Play the upsell hint is replaced by
      // the "it's free tonight" line.
      if (subscription.freePlayActive) ...[
        _buildFreePlayBanner(),
        const SizedBox(height: 10),
      ] else if (!subscription.isPremiumActive && subscription.matchesRemainingToday != null) ...[
        _buildFreeTierHint(subscription),
        const SizedBox(height: 10),
      ],
      CompetitiveCard(
        leading: CompetitiveCard.rankImage(RankUtils.getRankIcon(rank)),
        label: label,
        value: formatXp(user.elo),
        progress: isMaxRank ? 1.0 : rankProgress(rank, user.elo),
        caption: caption,
        actionLabel: action,
        actionXp: actionXp,
        onTap: onTap,
        liveRanked: _liveRanked,
        liveTotal: _liveCount,
      ),
    ];
  }
}
