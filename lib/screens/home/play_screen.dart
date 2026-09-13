import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/subscription_provider.dart';
import '../../providers/match_invite_provider.dart';
import '../../providers/placement_provider.dart';
import '../../providers/tournament_provider.dart';
import '../../providers/season_provider.dart';
import '../../widgets/recent_matches_widget.dart';
import '../../widgets/design_system.dart';
import '../../widgets/live_matches_pill.dart';
import '../../services/presence_service.dart';
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
import '../../utils/season_format.dart';
import '../../widgets/season_picker_sheet.dart';
import 'seasons_screen.dart';
import '../matchmaking/camera_setup_screen.dart';
import '../matchmaking/friend_select_screen.dart';
import '../local_match/local_match_entry_screen.dart';
import '../../models/user.dart';
import '../../widgets/player_card.dart';
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


class _PlayScreenState extends State<PlayScreen> with WidgetsBindingObserver {
  List<Match> _recentMatches = [];
  bool _loadingMatches = false;
  Map<String, dynamic>? _activeMatch;
  TournamentMatch? _pendingTournamentMatch;
  TournamentMatch? _activeTournamentLeg;
  TournamentProvider? _tournamentProvider;
  bool _inActiveTournament = false;
  String? _activeTournamentName;
  ActivitySnapshot? _activity;
  int _liveCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadRecentMatches();
    _checkActiveMatch();
    _checkPendingTournamentMatch();
    _checkActiveTournamentStatus();
    _loadActivity();
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
    _loadActivity();
    _loadLiveCount();
  }

  /// Feeds the activity pulse card; the card stays hidden until (and unless)
  /// a snapshot arrives, so failures cost nothing. 24 h window: a full day of
  /// matches reads better under Compétitif than half a day.
  Future<void> _loadActivity() async {
    final snapshot = await PresenceService.fetchActivity(hours: 24);
    if (mounted && snapshot != null) {
      setState(() => _activity = snapshot);
    }
  }

  /// Feeds the live-matches pill; 0 (no capability, error, nothing live)
  /// keeps the classic activity pill in place. Gated on the handshake's
  /// supportsSpectate so a pre-spectate backend is never polled (guaranteed
  /// 404 otherwise).
  Future<void> _loadLiveCount() async {
    try {
      await SocketService.ensureAuthenticated();
    } catch (_) {}
    if (!SocketService.supportsSpectate) {
      if (mounted && _liveCount != 0) setState(() => _liveCount = 0);
      return;
    }
    final live = await SpectateService.fetchLive();
    if (mounted) {
      setState(() => _liveCount = live?.liveCount ?? 0);
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

  /// The one filled block of the screen. Every state that takes the play slot
  /// renders through this so they all keep the same geometry.
  Widget _primarySlot({
    required IconData icon,
    required String title,
    String? subtitle,
    VoidCallback? onTap,
    bool muted = false,
  }) {
    return DsPrimaryRow(
      icon: icon,
      title: dsSentence(title),
      subtitle: subtitle,
      onTap: onTap,
      muted: muted,
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

  /// Play slot when a friend invite is pending; tapping it asks the player to
  /// accept or decline.
  Widget _buildFriendInviteButton(IncomingInvite invite, AppLocalizations l10n) {
    final hint = l10n.invitedYouToMatch
        .replaceAll('{username}', invite.inviterUsername);
    return _primarySlot(
      icon: Icons.sports_esports_outlined,
      title: l10n.joinMatch,
      subtitle: '$hint · ${invite.isCricket ? l10n.cricketLabel : '501'} · BO${invite.bestOf}',
      onTap: () => _onFriendInviteTapped(invite),
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

  /// The player card: badge, name, rank · position, ELO, progress to the next
  /// rank and the season selector. With a past season selected it freezes to
  /// that season's line for this player: final badge, final ELO, standing,
  /// "Classement final ›".
  Widget _buildPlayerCard({
    required AppLocalizations l10n,
    required SeasonProvider seasonProvider,
    required User user,
    required bool isPremium,
  }) {
    final hasSeason = seasonProvider.hasSeason;
    final selected = seasonProvider.selectedSeason;

    if (hasSeason && selected != null && !seasonProvider.isActiveSelected) {
      final standing = seasonProvider.selectedStanding;
      final loading = seasonProvider.loadingSelected;
      final total = selected.playersCount ?? 0;
      final Widget subline = loading
          ? const SizedBox(
              height: 12,
              width: 12,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary),
            )
          : Text(
              standing != null
                  ? '${l10n.seasonEndedLabel} · ${l10n.seasonFinalRank} '
                      '${RankTranslation.translate(l10n, standing.rank)} · '
                      '#${standing.position} ${l10n.seasonOf(total)}'
                  : '${l10n.seasonEndedLabel} · ${l10n.seasonNotRanked}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.caption.copyWith(fontSize: 13),
            );
      return PlayerCard(
        rank: standing?.rank ?? user.rank,
        username: user.username,
        isPremium: isPremium,
        subline: subline,
        value: standing?.elo == null ? '—' : '${standing!.elo}',
        valueLabel: l10n.seasonEloFinal,
        progress: 1.0,
        footerLeft: _link(
          l10n.seasonFinalStandings,
          () => seasonProvider.requestStandings(selected.number),
        ),
        footerRight: _seasonSelector(l10n, seasonProvider, showCountdown: false),
      );
    }

    final me = seasonProvider.current?.me;
    final rank = user.rank;
    final isMaxRank = rank.toLowerCase() == 'master';
    // Thresholds live in rank_utils (mirrors the backend's 800/1200/1600/
    // 2000/2400).
    final eloNeeded = eloNeededForNextRank(rank, user.elo);
    final nextLabel = RankTranslation.translate(l10n, nextRank(rank));
    final position = hasSeason && me != null ? ' · #${me.position}' : '';
    return PlayerCard(
      rank: rank,
      username: user.username,
      isPremium: isPremium,
      subline: Text(
        '${RankTranslation.translate(l10n, rank)}$position',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTheme.caption.copyWith(fontSize: 13),
      ),
      value: '${user.elo}',
      valueLabel: l10n.eloLabel,
      progress: isMaxRank ? 1.0 : rankProgress(rank, user.elo),
      footerLeft: isMaxRank
          ? Text(
              l10n.maxRankReached,
              style: AppTheme.caption.copyWith(color: const Color(0xFFCBD5E1)),
            )
          : Text.rich(
              TextSpan(
                style: AppTheme.caption.copyWith(color: const Color(0xFFCBD5E1)),
                children: [
                  TextSpan(text: '$nextLabel ${l10n.nextRankConnector} '),
                  TextSpan(
                    text: '+${math.max(eloNeeded, 0)} pts',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
      footerRight: hasSeason
          ? _seasonSelector(l10n, seasonProvider, showCountdown: true)
          : null,
    );
  }

  /// Unranked: the same card with the placement progress as its number.
  Widget _buildPlacementCard({
    required AppLocalizations l10n,
    required User user,
    required bool isPremium,
    required int matchesPlayed,
  }) {
    // Mirrors the backend's TOTAL_PLACEMENT_MATCHES (and the 4 hardcoded in
    // PlacementHubScreen).
    const total = 4;
    final played = matchesPlayed.clamp(0, total);
    return PlayerCard(
      rank: 'unranked',
      username: user.username,
      isPremium: isPremium,
      subline: Text(l10n.unranked, style: AppTheme.caption.copyWith(fontSize: 13)),
      value: '$played / $total',
      valueLabel: l10n.placementUpper,
      progress: played / total,
      footerLeft: Text(
        l10n.completePlacementToUnlock,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTheme.caption.copyWith(color: const Color(0xFFCBD5E1)),
      ),
    );
  }

  Widget _link(String label, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () {
        HapticService.lightImpact();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.primaryLight,
              ),
            ),
            const Icon(Icons.chevron_right_rounded, size: 14, color: AppTheme.primaryLight),
          ],
        ),
      ),
    );
  }

  /// "Saison 1 · 84 j ▾" — opens the season picker.
  Widget _seasonSelector(
    AppLocalizations l10n,
    SeasonProvider seasonProvider, {
    required bool showCountdown,
  }) {
    final selected = seasonProvider.selectedSeason;
    if (selected == null) return const SizedBox.shrink();
    var label = l10n.seasonN(selected.number);
    if (showCountdown && seasonProvider.activeSeason?.endAt != null) {
      label = '$label · ${formatSeasonCountdown(l10n, seasonProvider.timeLeft)}';
    }
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: _openSeasonPicker,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.primaryLight,
              ),
            ),
            const Icon(Icons.expand_more_rounded, size: 16, color: AppTheme.primaryLight),
          ],
        ),
      ),
    );
  }

  Future<void> _openSeasonPicker() async {
    HapticService.lightImpact();
    final provider = context.read<SeasonProvider>();
    final result = await SeasonPickerSheet.show(context);
    if (!mounted || result == null) return;
    if (result == SeasonPickerSheet.allSeasonsResult) {
      final picked = await Navigator.of(context).push<int>(
        MaterialPageRoute(
          builder: (_) => SeasonsScreen(initialNumber: provider.selectedNumber),
        ),
      );
      if (!mounted || picked == null) return;
      // "Standings ›" on a poster: hand over to the Rankings tab.
      provider.requestStandings(picked);
      return;
    }
    await provider.select(result);
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

    return RefreshIndicator(
      color: AppTheme.primary,
      onRefresh: () async {
        await Future.wait([
          _loadRecentMatches(),
          _checkActiveMatch(),
          _checkPendingTournamentMatch(),
          _checkActiveTournamentStatus(),
          _loadActivity(),
          _loadLiveCount(),
        ]);
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (isUnranked)
              _buildPlacementCard(
                l10n: l10n,
                user: user,
                isPremium: isPremium,
                matchesPlayed:
                    context.watch<PlacementProvider>().status?.matchesPlayed ?? 0,
              )
            else
              _buildPlayerCard(
                l10n: l10n,
                seasonProvider: seasonProvider,
                user: user,
                isPremium: isPremium,
              ),
            const SizedBox(height: 14),
            ..._buildPrimarySlot(l10n, subscription, matchInvite, isUnranked),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: DsTile(
                    icon: Icons.people_outline_rounded,
                    label: l10n.friendModeTitle,
                    // Premium (or the Free Play window) is required to invite a
                    // friend — show the gate on the tile instead of letting the
                    // user discover it once they've picked someone.
                    locked: !subscription.canPlayFriendMatch,
                    onTap: _openFriendMatch,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DsTile(
                    icon: Icons.smartphone_outlined,
                    label: l10n.localModeTitle,
                    onTap: _openLocalMatch,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DsTile(
                    icon: Icons.fitness_center_rounded,
                    label: l10n.trainingPlayCardTitle,
                    onTap: _openTraining,
                  ),
                ),
              ],
            ),
            if (_liveCount > 0) ...[
              const SizedBox(height: 14),
              LiveMatchesPill(count: _liveCount),
            ],
            const SizedBox(height: 28),
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

  /// CTA priority, unchanged: live tournament leg → pending tournament join →
  /// friend invite → placement → active match rejoin → tournament lock →
  /// Compétitif (with the free-tier hint above it).
  List<Widget> _buildPrimarySlot(
    AppLocalizations l10n,
    SubscriptionProvider subscription,
    MatchInviteProvider matchInvite,
    bool isUnranked,
  ) {
    final liveLeg = _activeTournamentLeg;
    if (liveLeg?.lastGameId != null) {
      // A tournament leg is LIVE for this player (app was killed mid-match) —
      // resuming outranks everything: the disconnect grace timer is running
      // server-side.
      return [
        _primarySlot(
          icon: Icons.replay_rounded,
          title: l10n.resumeTournamentMatch,
          subtitle: '${liveLeg!.tournamentName ?? l10n.tournament} · '
              '${localizedRoundLabel(l10n, liveLeg)}',
          onTap: _resumeTournamentLeg,
        ),
      ];
    }
    final pending = _pendingTournamentMatch;
    if (pending != null) {
      // A tournament commitment outranks friend invites and placement.
      return [
        _primarySlot(
          icon: Icons.emoji_events_outlined,
          title: l10n.joinMatch,
          subtitle: '${pending.tournamentName ?? l10n.tournament} · '
              '${localizedRoundLabel(l10n, pending)}',
          onTap: () => _joinTournamentMatch(pending),
        ),
      ];
    }
    if (matchInvite.incoming != null) {
      // The inviter is actively waiting and the invite is short-lived. (The
      // backend refuses to invite a busy player, so this can't collide with
      // an active-match rejoin.)
      return [_buildFriendInviteButton(matchInvite.incoming!, l10n)];
    }
    if (isUnranked) {
      return [
        _primarySlot(
          icon: Icons.flag_outlined,
          title: l10n.placementMatches,
          subtitle: l10n.completePlacementToUnlock,
          onTap: _openPlacement,
        ),
      ];
    }
    if (_activeMatch != null) {
      return [
        _primarySlot(
          icon: Icons.play_arrow_rounded,
          title: l10n.play,
          subtitle: '${l10n.rejoinVs} ${_activeMatch!['opponentUsername']}',
          onTap: _rejoinMatch,
        ),
      ];
    }
    if (_inActiveTournament) {
      return [
        _primarySlot(
          icon: Icons.lock_outline_rounded,
          title: l10n.rankedLocked,
          subtitle: '${l10n.activeTournament} · ${_activeTournamentName ?? l10n.tournament}',
          muted: true,
        ),
      ];
    }
    final activity = _activity;
    final subtitle = activity == null
        ? l10n.homeCompetitiveSubtitle
        : '${l10n.homeCompetitiveSubtitle} · ${activity.matches} '
            '${l10n.activityMatchesLabel(activity.windowHours).toLowerCase()}';
    return [
      // The play row is always shown for free users; the daily-match hint
      // stays visible (it reads "match used" once the free match is spent)
      // and tapping Compétitif then opens the paywall. During Free Play the
      // upsell hint is replaced by the "it's free tonight" line.
      if (subscription.freePlayActive) ...[
        _buildFreePlayBanner(),
        const SizedBox(height: 10),
      ] else if (!subscription.isPremiumActive &&
          subscription.matchesRemainingToday != null) ...[
        _buildFreeTierHint(subscription),
        const SizedBox(height: 10),
      ],
      _primarySlot(
        icon: Icons.military_tech_outlined,
        title: l10n.competitiveModeTitle,
        subtitle: subtitle,
        onTap: _onCompetitiveTapped,
      ),
    ];
  }
}
