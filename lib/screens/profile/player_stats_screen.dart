import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../models/head_to_head.dart';
import '../../models/user.dart';
import '../../providers/auth_provider.dart';
import '../../providers/friends_provider.dart';
import '../../services/stats_service.dart';
import '../../services/user_service.dart';
import '../../utils/app_navigator.dart';
import '../../utils/app_theme.dart';
import '../../utils/friendly_match_launcher.dart';
import '../../utils/notification_service.dart';
import '../../utils/rank_translation.dart';
import '../../utils/rank_utils.dart';
import '../../widgets/design_system.dart';
import '../../widgets/player_card.dart';
import '../chat/chat_thread_screen.dart';
import '../home/stats/stats_widgets.dart';
import 'head_to_head_screen.dart';

/// Another player's profile (also opens on your own row of a leaderboard):
/// their player card, the challenge row for a friend, the head-to-head
/// shortcut, their career figures, and the friend action at the bottom.
class PlayerStatsScreen extends StatefulWidget {
  final String userId;
  final String username;

  const PlayerStatsScreen({
    super.key,
    required this.userId,
    required this.username,
  });

  @override
  State<PlayerStatsScreen> createState() => _PlayerStatsScreenState();
}

/// What the top card needs and the stats endpoint does not send.
typedef _Identity = ({String rank, int elo, bool isPremium});

class _PlayerStatsScreenState extends State<PlayerStatsScreen> {
  bool _isLoading = true;
  UserStats? _stats;
  String? _errorMessage;

  /// Best effort, never blocks the screen: the opponent's rank / ELO /
  /// premium for the card when they are not a friend, and the record for the
  /// head-to-head row. Absent on your own profile (the endpoint refuses it).
  HeadToHead? _headToHead;
  bool _friendBusy = false;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    if (!_isSelf(context)) _loadHeadToHead();
    try {
      final stats = await UserService.getUserStats(widget.userId);
      if (!mounted) return;
      setState(() {
        _stats = stats;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  Future<void> _loadHeadToHead() async {
    try {
      final data = await StatsService.getHeadToHead(widget.userId);
      if (mounted) setState(() => _headToHead = data);
    } catch (_) {
      // The card falls back to the name alone; the row still opens the screen.
    }
  }

  /// This screen also opens on your OWN row in the leaderboard.
  bool _isSelf(BuildContext context) =>
      context.read<AuthProvider>().currentUser?.id == widget.userId;

  User? _friendUser(FriendsProvider friends) =>
      friends.friends.where((f) => f.id == widget.userId).firstOrNull;

  _Identity? _identity(BuildContext context, FriendsProvider friends) {
    if (_isSelf(context)) {
      final me = context.read<AuthProvider>().currentUser;
      if (me == null) return null;
      return (rank: me.rank, elo: me.elo, isPremium: me.isPremiumActive);
    }
    final friend = _friendUser(friends);
    if (friend != null) {
      return (rank: friend.rank, elo: friend.elo, isPremium: friend.isPremiumActive);
    }
    final opponent = _headToHead?.opponent;
    if (opponent != null) {
      return (rank: opponent.rank, elo: opponent.elo, isPremium: opponent.isPremium);
    }
    return null;
  }

  Future<void> _addFriend() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _friendBusy = true);
    try {
      await context.read<FriendsProvider>().sendFriendRequest(widget.userId);
      if (mounted) {
        NotificationService.showSuccess(
          context,
          l10n.friendRequestSent.replaceAll('{username}', widget.username),
        );
      }
    } catch (e) {
      if (mounted) {
        NotificationService.showError(context, e.toString().replaceAll('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _friendBusy = false);
    }
  }

  Future<void> _removeFriend() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.removeFriendTitle),
        content: Text(l10n.removeFriendMessage.replaceAll('{username}', widget.username)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(foregroundColor: AppTheme.textSecondary),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.error),
            child: Text(l10n.removeButton),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _friendBusy = true);
    try {
      await context.read<FriendsProvider>().removeFriend(widget.userId);
      if (mounted) {
        NotificationService.showSuccess(
          context,
          l10n.friendRemoved.replaceAll('{username}', widget.username),
        );
      }
    } catch (e) {
      if (mounted) {
        NotificationService.showError(context, e.toString().replaceAll('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _friendBusy = false);
    }
  }

  void _openHeadToHead() {
    AppNavigator.toScreen(
      context,
      HeadToHeadScreen(opponentId: widget.userId, opponentUsername: widget.username),
    );
  }

  void _openChat() {
    AppNavigator.toScreen(
      context,
      ChatThreadScreen(counterpartId: widget.userId, username: widget.username),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isSelf = _isSelf(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.username),
        actions: [
          if (!isSelf)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: DsIconButton(
                  icon: Icons.chat_bubble_outline_rounded,
                  tooltip: l10n.chatMessageAction,
                  onTap: _openChat,
                ),
              ),
            ),
        ],
      ),
      body: _buildBody(l10n, isSelf),
    );
  }

  Widget _buildBody(AppLocalizations l10n, bool isSelf) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
    }
    if (_errorMessage != null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
        child: DsCard(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
          child: Column(
            children: [
              const Icon(Icons.error_outline_rounded, size: 32, color: AppTheme.textTertiary),
              const SizedBox(height: 12),
              Text(_errorMessage!, textAlign: TextAlign.center, style: AppTheme.rowTitle),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _loadStats, child: Text(l10n.retry)),
            ],
          ),
        ),
      );
    }
    final stats = _stats;
    if (stats == null) {
      return Center(child: Text(l10n.noStatisticsAvailable, style: AppTheme.bodyMedium));
    }

    final friends = context.watch<FriendsProvider>();
    final friend = isSelf ? null : _friendUser(friends);
    final status = isSelf ? 'self' : friends.getFriendshipStatus(widget.userId);

    return RefreshIndicator(
      onRefresh: _loadStats,
      color: AppTheme.primary,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildTopCard(l10n, _identity(context, friends), stats),
            if (friend != null) ...[
              const SizedBox(height: 14),
              _buildChallengeRow(l10n, friend, friends.isOnline(friend.id)),
            ],
            if (!isSelf) ...[
              const SizedBox(height: 14),
              _buildHeadToHeadRow(l10n),
            ],
            const SizedBox(height: 28),
            DsSectionHeader(title: l10n.performanceOverview),
            const SizedBox(height: 12),
            _buildRecordCard(l10n, stats),
            const SizedBox(height: 14),
            _buildFiguresCard(l10n, stats),
            if (!isSelf) ...[
              const SizedBox(height: 28),
              _buildFriendButton(l10n, status),
            ],
          ],
        ),
      ),
    );
  }

  /// The player card when their rank and ELO are known; otherwise the same
  /// card without a badge or number — a wrong badge is worse than none.
  Widget _buildTopCard(AppLocalizations l10n, _Identity? identity, UserStats stats) {
    if (identity != null) {
      final isMaxRank = identity.rank.toLowerCase() == 'master';
      return PlayerCard(
        rank: identity.rank,
        username: widget.username,
        isPremium: identity.isPremium,
        subline: Text(
          RankTranslation.translate(l10n, identity.rank),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTheme.caption.copyWith(fontSize: 13),
        ),
        value: '${identity.elo}',
        valueLabel: l10n.eloLabel,
        progress: isMaxRank ? 1.0 : rankProgress(identity.rank, identity.elo),
      );
    }
    final initial = widget.username.isNotEmpty ? widget.username[0].toUpperCase() : '?';
    return DsCard(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: AppTheme.surfaceLight),
            child: Text(
              initial,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.username,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.titleLarge.copyWith(height: 1.1),
                ),
                const SizedBox(height: 5),
                Text(
                  '${l10n.totalMatches} · ${stats.totalMatches}',
                  style: AppTheme.caption.copyWith(fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The one filled block of the screen: challenge a friend to a friendly
  /// match. Muted (no arrow) while they are offline, still tappable — the
  /// invite waits for them.
  Widget _buildChallengeRow(AppLocalizations l10n, User friend, bool isOnline) {
    return DsPrimaryRow(
      icon: Icons.gps_fixed_rounded,
      title: l10n.headToHeadChallenge(friend.username),
      subtitle: isOnline ? l10n.online : l10n.friendsOffline,
      muted: !isOnline,
      onTap: () => FriendlyMatchLauncher.invite(context, friend),
    );
  }

  Widget _buildHeadToHeadRow(AppLocalizations l10n) {
    final data = _headToHead;
    String? subtitle;
    if (data != null && data.hasHistory) {
      subtitle = '${data.record.wins} – ${data.record.losses} · '
          '${data.record.encounters} ${l10n.headToHeadEncounters.toLowerCase()}';
    }
    return DsListRow(
      leading: const Icon(Icons.compare_arrows_rounded, size: 22, color: Color(0xFFCBD5E1)),
      title: l10n.headToHeadTitle,
      subtitle: subtitle,
      onTap: _openHeadToHead,
    );
  }

  /// Win rate as the hero, the tally under it.
  Widget _buildRecordCard(AppLocalizations l10n, UserStats stats) {
    if (stats.totalMatches == 0) return StatsBlockEmpty(l10n.noStatisticsAvailable);
    return StatsCard(
      children: [
        StatsHero(
          value: stats.winRate.toStringAsFixed(1),
          unit: '%',
          caption: l10n.winRate,
        ),
        const SizedBox(height: 16),
        StatsRow(label: l10n.wins, value: '${stats.wins}', valueColor: AppTheme.success),
        const SizedBox(height: 10),
        StatsRow(label: l10n.losses, value: '${stats.losses}', valueColor: AppTheme.error),
        const SizedBox(height: 10),
        StatsRow(label: l10n.totalMatches, value: '${stats.totalMatches}'),
        const SizedBox(height: 10),
        StatsRow(
          label: dsSentence(l10n.streak),
          value: '${stats.currentStreak}',
          valueColor: stats.currentStreak > 0 ? AppTheme.success : null,
        ),
      ],
    );
  }

  /// The dart figures. A player whose only matches were against bots has no
  /// measured darts — an empty block, never "0.0" read as a real average.
  Widget _buildFiguresCard(AppLocalizations l10n, UserStats stats) {
    if (stats.legsCounted == 0) return StatsBlockEmpty(l10n.noStatisticsAvailable);
    return StatsCard(
      children: [
        StatsHero(
          value: stats.averageScore.toStringAsFixed(1),
          caption: l10n.avgScore,
        ),
        const SizedBox(height: 16),
        StatsRow(label: l10n.count180s, value: '${stats.count180s}'),
        if (stats.biggestCheckout > 0) ...[
          const SizedBox(height: 10),
          StatsRow(label: l10n.bestCheckout, value: '${stats.biggestCheckout}'),
        ],
        if (stats.finishingDoublePercentage > 0) ...[
          const SizedBox(height: 10),
          StatsRow(
            label: l10n.finishingDoubles,
            value: '${stats.finishingDoublePercentage.toStringAsFixed(1)} %',
          ),
        ],
      ],
    );
  }

  Widget _buildFriendButton(AppLocalizations l10n, String status) {
    switch (status) {
      case 'friends':
        return OutlinedButton.icon(
          onPressed: _friendBusy ? null : _removeFriend,
          icon: const Icon(Icons.person_remove_outlined, size: 18),
          label: Text(l10n.removeFriendTitle),
        );
      case 'pending_sent':
      case 'pending_received':
        return OutlinedButton.icon(
          onPressed: null,
          icon: const Icon(Icons.hourglass_empty_rounded, size: 18),
          label: Text(l10n.pendingStatus),
        );
      default:
        return OutlinedButton.icon(
          onPressed: _friendBusy ? null : _addFriend,
          icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
          label: Text(l10n.addFriendButton),
        );
    }
  }
}
