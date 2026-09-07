import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/chat_provider.dart';
import '../../providers/friends_provider.dart';
import '../../models/chat_message.dart';
import '../../models/user.dart';
import '../../services/friends_service.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/design_system.dart';
import '../../widgets/premium_badge.dart';
import '../../utils/app_navigator.dart';
import '../../utils/app_theme.dart';
import '../../utils/friendly_match_launcher.dart';
import '../../utils/haptic_service.dart';
import '../../utils/rank_utils.dart';
import '../chat/chat_thread_screen.dart';
import '../profile/player_stats_screen.dart';

/// Every row of this tab (team, friend, request, search result) is a 64 px
/// flat card with the same inner padding.
const double _kRowHeight = 64;
const EdgeInsets _kRowPadding = EdgeInsets.fromLTRB(14, 0, 12, 0);
const EdgeInsets _kListPadding = EdgeInsets.fromLTRB(16, 14, 16, 24);
const Color _kIconMuted = Color(0xFFCBD5E1);

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  List<User> _searchResults = [];
  bool _isSearching = false;
  bool _showSearch = false;
  late TabController _tabController;
  Timer? _onlineTimer;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<FriendsProvider>().loadAll();
    });
    // Keep the online indicators fresh while the friends screen is open.
    _onlineTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) context.read<FriendsProvider>().refreshOnlineFriends();
    });
  }

  @override
  void dispose() {
    _onlineTimer?.cancel();
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _performSearch(String query) async {
    final l10n = AppLocalizations.of(context);
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
    });

    try {
      final results = await FriendsService.searchUsers(query);
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    } catch (e) {
      setState(() {
        _isSearching = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.searchFailed.replaceAll('{message}', e.toString().replaceAll('Exception: ', ''))),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  Future<void> _sendFriendRequest(String friendId, String username) async {
    final l10n = AppLocalizations.of(context);
    try {
      HapticService.mediumImpact();
      await context.read<FriendsProvider>().sendFriendRequest(friendId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.friendRequestSent.replaceAll('{username}', username)),
            backgroundColor: AppTheme.success,
          ),
        );
        _searchController.clear();
        setState(() {
          _searchResults = [];
          _showSearch = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  Future<void> _acceptRequest(String friendshipId, String username) async {
    final l10n = AppLocalizations.of(context);
    try {
      HapticService.mediumImpact();
      await context.read<FriendsProvider>().acceptFriendRequest(friendshipId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.friendRequestAccepted.replaceAll('{username}', username)),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  Future<void> _rejectRequest(String friendshipId, String username) async {
    final l10n = AppLocalizations.of(context);
    try {
      HapticService.mediumImpact();
      await context.read<FriendsProvider>().rejectFriendRequest(friendshipId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.friendRequestDeclined.replaceAll('{username}', username)),
            backgroundColor: AppTheme.textSecondary,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  Future<void> _removeFriend(String friendId, String username) async {
    final l10n = AppLocalizations.of(context);
    // The dialog theme (surface, r20, Manrope) does the styling; only the
    // destructive action is colored.
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.removeFriendTitle),
        content: Text(l10n.removeFriendMessage.replaceAll('{username}', username)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.error),
            child: Text(l10n.removeButton),
          ),
        ],
      ),
    );

    if (confirm == true) {
      if (!mounted) return;
      try {
        HapticService.mediumImpact();
        await context.read<FriendsProvider>().removeFriend(friendId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.friendRemoved.replaceAll('{username}', username)),
              backgroundColor: AppTheme.success,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(e.toString().replaceAll('Exception: ', '')),
              backgroundColor: AppTheme.error,
            ),
          );
        }
      }
    }
  }

  void _openSearch() {
    setState(() => _showSearch = true);
  }

  void _closeSearch() {
    _searchController.clear();
    setState(() {
      _showSearch = false;
      _searchResults = [];
    });
  }

  void _openStats(User user) {
    AppNavigator.toScreen(
      context,
      PlayerStatsScreen(userId: user.id, username: user.username),
    );
  }

  void _openThread(String counterpartId, String username) {
    AppNavigator.toScreen(
      context,
      ChatThreadScreen(counterpartId: counterpartId, username: username),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_showSearch) return _buildSearchView();

    final friendsProvider = context.watch<FriendsProvider>();
    final l10n = AppLocalizations.of(context);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: DsScreenHeader(
            title: l10n.friends,
            actions: [
              DsIconButton(
                icon: Icons.search_rounded,
                tooltip: MaterialLocalizations.of(context).searchFieldLabel,
                onTap: _openSearch,
              ),
              DsIconButton(
                icon: Icons.person_add_alt_1_outlined,
                tooltip: l10n.addFriendsButton,
                onTap: _openSearch,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: AnimatedBuilder(
            // Follows the swipe of the TabBarView, not only the settled index.
            animation: _tabController.animation!,
            builder: (context, _) => _SegmentedControl(
              index: _tabController.animation!.value.round(),
              labels: [
                '${l10n.friendsCount} (${friendsProvider.friends.length})',
                '${l10n.requests} (${friendsProvider.pendingRequestsCount})',
              ],
              onSelect: (i) => _tabController.animateTo(i),
            ),
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildFriendsList(friendsProvider),
              _buildRequestsList(friendsProvider),
            ],
          ),
        ),
      ],
    );
  }

  // ─── Friends tab ────────────────────────────────────────────────────────

  Widget _buildFriendsList(FriendsProvider provider) {
    final l10n = AppLocalizations.of(context);
    if (provider.isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primary),
      );
    }

    if (provider.error != null) {
      return _ErrorState(
        message: provider.error!.replaceAll('Exception: ', ''),
        onRetry: () => provider.loadFriends(),
      );
    }

    final chat = context.watch<ChatProvider>();
    final friends = provider.friends;
    // Online friends first — they're the ones you can actually challenge now.
    final online = friends.where((f) => provider.isOnline(f.id)).toList();
    final offline = friends.where((f) => !provider.isOnline(f.id)).toList();

    // Row 0 is the pinned "Équipe Dart Rivals" — everyone can write to the
    // team, without it being a friendship (and without being challengeable).
    final children = <Widget>[
      _TeamRow(
        unreadCount: chat.unreadSupport,
        onTap: () => _openThread(kSupportConversationId, l10n.teamDartRivals),
      ),
    ];

    if (friends.isEmpty) {
      children.add(const SizedBox(height: 14));
      children.add(_EmptyState(
        icon: Icons.people_outline_rounded,
        title: l10n.noFriendsYet,
        subtitle: l10n.addFriendsHint,
        action: ElevatedButton(
          onPressed: _openSearch,
          child: Text(l10n.addFriendsButton),
        ),
      ));
    } else {
      void addGroup(String label, List<User> group) {
        if (group.isEmpty) return;
        children.add(const SizedBox(height: 20));
        children.add(_GroupLabel('${label.toUpperCase()} · ${group.length}'));
        for (final friend in group) {
          final isOnline = provider.isOnline(friend.id);
          children.add(const SizedBox(height: 10));
          children.add(_FriendRow(
            friend: friend,
            isOnline: isOnline,
            unreadCount: chat.unreadFrom(friend.id),
            onChallenge: () => FriendlyMatchLauncher.invite(context, friend),
            onMessage: () => _openThread(friend.id, friend.username),
            onRemove: () => _removeFriend(friend.id, friend.username),
            onTap: () => _openStats(friend),
          ));
        }
      }

      addGroup(l10n.online, online);
      addGroup(l10n.friendsOffline, offline);
    }

    return RefreshIndicator(
      onRefresh: () => provider.loadFriends(),
      color: AppTheme.primary,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: _kListPadding,
        children: children,
      ),
    );
  }

  // ─── Requests tab ───────────────────────────────────────────────────────

  Widget _buildRequestsList(FriendsProvider provider) {
    final l10n = AppLocalizations.of(context);
    final pendingRequests = provider.pendingRequests;
    final sentRequests = provider.sentRequests;

    if (pendingRequests.isEmpty && sentRequests.isEmpty) {
      return ListView(
        padding: _kListPadding,
        children: [
          _EmptyState(
            icon: Icons.people_outline_rounded,
            title: l10n.noFriendRequests,
          ),
        ],
      );
    }

    return ListView(
      padding: _kListPadding,
      children: [
        if (pendingRequests.isNotEmpty) ...[
          _GroupLabel(l10n.incomingRequests.toUpperCase()),
          for (final request in pendingRequests) ...[
            const SizedBox(height: 10),
            _PlayerRow(
              user: request.user,
              onTap: () => _openStats(request.user),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _RoundIconButton(
                    icon: Icons.check_rounded,
                    iconSize: 18,
                    color: AppTheme.success,
                    fillColor: AppTheme.success.withValues(alpha: 0.14),
                    semanticsLabel: l10n.acceptButton,
                    onTap: () => _acceptRequest(request.id, request.user.username),
                  ),
                  const SizedBox(width: 8),
                  _RoundIconButton(
                    icon: Icons.close_rounded,
                    iconSize: 18,
                    color: AppTheme.error,
                    fillColor: AppTheme.error.withValues(alpha: 0.14),
                    semanticsLabel: l10n.declineInvite,
                    onTap: () => _rejectRequest(request.id, request.user.username),
                  ),
                ],
              ),
            ),
          ],
        ],
        if (sentRequests.isNotEmpty) ...[
          if (pendingRequests.isNotEmpty) const SizedBox(height: 20),
          _GroupLabel(l10n.sentRequests.toUpperCase()),
          for (final request in sentRequests) ...[
            const SizedBox(height: 10),
            _PlayerRow(
              user: request.user,
              onTap: () => _openStats(request.user),
              trailing: DsPill(label: l10n.pendingStatus, color: AppTheme.textSecondary),
            ),
          ],
        ],
      ],
    );
  }

  // ─── Search view ────────────────────────────────────────────────────────

  Widget _buildSearchView() {
    final l10n = AppLocalizations.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: DsScreenHeader(
            title: l10n.addFriendsButton,
            showBack: true,
            onBack: _closeSearch,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: TextField(
            controller: _searchController,
            autofocus: true,
            // The input theme paints the field (surface, r14, primary focus).
            decoration: InputDecoration(
              hintText: l10n.searchByUsernameHint,
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {
                          _searchResults = [];
                        });
                      },
                    )
                  : null,
            ),
            onChanged: _performSearch,
          ),
        ),
        Expanded(child: _buildSearchResults()),
      ],
    );
  }

  Widget _buildSearchResults() {
    final l10n = AppLocalizations.of(context);
    if (_isSearching) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primary),
      );
    }

    if (_searchController.text.isEmpty) {
      return ListView(
        padding: _kListPadding,
        children: [
          _EmptyState(icon: Icons.search_rounded, title: l10n.searchForUsersByUsername),
        ],
      );
    }

    if (_searchResults.isEmpty) {
      return ListView(
        padding: _kListPadding,
        children: [
          _EmptyState(icon: Icons.person_off_outlined, title: l10n.noUsersFound),
        ],
      );
    }

    final friendsProvider = context.watch<FriendsProvider>();

    return ListView.separated(
      padding: _kListPadding,
      itemCount: _searchResults.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final user = _searchResults[index];
        final status = friendsProvider.getFriendshipStatus(user.id);
        return _PlayerRow(
          user: user,
          onTap: () => _openStats(user),
          trailing: _buildSearchResultAction(user, status),
        );
      },
    );
  }

  Widget _buildSearchResultAction(User user, String status) {
    final l10n = AppLocalizations.of(context);
    switch (status) {
      case 'friends':
        return DsPill(label: l10n.friendsStatus, color: AppTheme.success);
      case 'pending_sent':
        return DsPill(label: l10n.pendingStatus, color: AppTheme.textSecondary);
      case 'pending_received':
        return _SmallPill(
          label: l10n.acceptButton,
          filled: true,
          onTap: () async {
            final friendsProvider = context.read<FriendsProvider>();
            final request = friendsProvider.pendingRequests.firstWhere((r) => r.user.id == user.id);
            await _acceptRequest(request.id, user.username);
          },
        );
      default:
        return _RoundIconButton(
          icon: Icons.person_add_alt_1_outlined,
          iconSize: 18,
          color: AppTheme.primaryLight,
          fillColor: AppTheme.primary.withValues(alpha: 0.14),
          semanticsLabel: l10n.addFriendsButton,
          onTap: () => _sendFriendRequest(user.id, user.username),
        );
    }
  }
}

// ─── Private building blocks ──────────────────────────────────────────────

/// "Amis (5) | Demandes (2)": a surface container with the active segment on
/// a surfaceLight pad. Drives (and is driven by) the TabController.
class _SegmentedControl extends StatelessWidget {
  final int index;
  final List<String> labels;
  final ValueChanged<int> onSelect;

  const _SegmentedControl({
    required this.index,
    required this.labels,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(left: i == 0 ? 0 : 3),
                child: _segment(i),
              ),
            ),
        ],
      ),
    );
  }

  Widget _segment(int i) {
    final active = i == index;
    return Material(
      color: active ? AppTheme.surfaceLight : Colors.transparent,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: () {
          HapticService.lightImpact();
          onSelect(i);
        },
        child: Center(
          child: Text(
            labels[i],
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: active ? FontWeight.w700 : FontWeight.w600,
              color: active ? AppTheme.textPrimary : AppTheme.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// "EN LIGNE · 1 ───────" group label with a hairline.
class _GroupLabel extends StatelessWidget {
  final String text;
  const _GroupLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(text, style: AppTheme.labelSmall),
        const SizedBox(width: 12),
        Expanded(child: Container(height: 1, color: AppTheme.border)),
      ],
    );
  }
}

/// 36 px rank badge; when [isOnline] is given, a 12 px presence dot sits on
/// its bottom-right corner (success online, surfaceLight offline).
class _RankAvatar extends StatelessWidget {
  final String rank;
  final bool? isOnline;

  const _RankAvatar({required this.rank, this.isOnline});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SizedBox(
      width: 36,
      height: 36,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          RankUtils.getRankBadge(rank, size: 36),
          if (isOnline != null)
            Positioned(
              right: -2,
              bottom: -2,
              child: Semantics(
                label: isOnline! ? l10n.online : l10n.friendsOffline,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: isOnline! ? AppTheme.success : AppTheme.surfaceLight,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppTheme.surface, width: 2),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The 64 px player row shared by friends, requests and search results:
/// rank badge, name + premium crown, "1240 ELO · 12V · 8D" caption (prefixed
/// by "En ligne" when [isOnline]), and a caller-provided trailing.
class _PlayerRow extends StatelessWidget {
  final User user;
  final bool? isOnline;
  final Widget trailing;
  final VoidCallback onTap;

  const _PlayerRow({
    required this.user,
    this.isOnline,
    required this.trailing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final stats =
        '${user.elo} ${l10n.eloLabel} · ${user.wins}${l10n.formWinLetter} · ${user.losses}${l10n.formLossLetter}';

    return SizedBox(
      height: _kRowHeight,
      child: DsCard(
        radius: AppTheme.radiusRow,
        padding: _kRowPadding,
        onTap: onTap,
        child: Row(
          children: [
            _RankAvatar(rank: user.rank, isOnline: isOnline),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          user.username,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.sectionTitle,
                        ),
                      ),
                      PremiumBadge(
                        isPremium: user.isPremiumActive,
                        size: 12,
                        color: AppTheme.accent,
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text.rich(
                    TextSpan(
                      style: AppTheme.caption,
                      children: [
                        if (isOnline == true) ...[
                          TextSpan(
                            text: l10n.online,
                            style: const TextStyle(
                              color: AppTheme.success,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const TextSpan(text: ' · '),
                        ],
                        TextSpan(text: stats),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            trailing,
          ],
        ),
      ),
    );
  }
}

/// Friend row: presence dot on the rank badge, round message button with the
/// unread badge, "Défier" pill (filled when the friend is online). Removal
/// stays behind a swipe so the destructive action is never one accidental
/// tap away.
class _FriendRow extends StatelessWidget {
  final User friend;
  final bool isOnline;
  final int unreadCount;
  final VoidCallback onChallenge;
  final VoidCallback onMessage;
  final Future<void> Function() onRemove;
  final VoidCallback onTap;

  const _FriendRow({
    required this.friend,
    required this.isOnline,
    required this.unreadCount,
    required this.onChallenge,
    required this.onMessage,
    required this.onRemove,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.radiusRow),
      child: Dismissible(
        key: ValueKey('friend-${friend.id}'),
        direction: DismissDirection.endToStart,
        // _removeFriend owns the confirmation dialog and the actual removal;
        // returning false keeps the row (the provider rebuilds the list when
        // a removal really happens).
        confirmDismiss: (_) async {
          await onRemove();
          return false;
        },
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 18),
          color: AppTheme.error,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.person_remove_outlined, color: Colors.white, size: 20),
              const SizedBox(height: 2),
              Text(
                l10n.removeButton,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        child: _PlayerRow(
          user: friend,
          isOnline: isOnline,
          onTap: onTap,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _RoundIconButton(
                icon: Icons.chat_bubble_outline_rounded,
                color: _kIconMuted,
                borderColor: AppTheme.surfaceLight,
                badge: unreadCount > 0 ? DsBadge(count: unreadCount) : null,
                semanticsLabel: l10n.chatMessageAction,
                onTap: onMessage,
              ),
              const SizedBox(width: 8),
              _SmallPill(
                label: l10n.challengeFriend,
                filled: isOnline,
                onTap: onChallenge,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 36 px round icon button: outline ([borderColor]) or tinted ([fillColor]),
/// optional badge on the top-right corner.
class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final double iconSize;
  final Color color;
  final Color? fillColor;
  final Color? borderColor;
  final VoidCallback onTap;
  final Widget? badge;
  final String? semanticsLabel;

  const _RoundIconButton({
    required this.icon,
    this.iconSize = 17,
    required this.color,
    this.fillColor,
    this.borderColor,
    required this.onTap,
    this.badge,
    this.semanticsLabel,
  });

  @override
  Widget build(BuildContext context) {
    final Widget button = Material(
      color: fillColor ?? Colors.transparent,
      shape: CircleBorder(
        side: borderColor == null ? BorderSide.none : BorderSide(color: borderColor!),
      ),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () {
          HapticService.lightImpact();
          onTap();
        },
        child: SizedBox(
          width: 36,
          height: 36,
          child: Center(
            child: Icon(icon, size: iconSize, color: color, semanticLabel: semanticsLabel),
          ),
        ),
      ),
    );
    if (badge == null) return button;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        button,
        Positioned(top: -4, right: -4, child: badge!),
      ],
    );
  }
}

/// 32 px action pill ("Défier", "Accepter"): primary gradient + white when
/// [filled], hairline outline + textPrimary otherwise.
class _SmallPill extends StatelessWidget {
  final String label;
  final bool filled;
  final VoidCallback onTap;

  const _SmallPill({
    required this.label,
    required this.filled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () {
          HapticService.lightImpact();
          onTap();
        },
        // Ink (not Container) so the ripple paints above the gradient.
        child: Ink(
          decoration: BoxDecoration(
            gradient: filled ? AppTheme.primaryGradient : null,
            borderRadius: BorderRadius.circular(999),
            border: filled ? null : Border.all(color: AppTheme.surfaceLight),
          ),
          child: Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: filled ? Colors.white : AppTheme.textPrimary,
                height: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Pinned "Équipe Dart Rivals" row at the top of the friends list. Not a
/// friendship: message-only (no challenge), available to every player.
class _TeamRow extends StatelessWidget {
  final int unreadCount;
  final VoidCallback onTap;

  const _TeamRow({required this.unreadCount, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SizedBox(
      height: _kRowHeight,
      child: DsCard(
        radius: AppTheme.radiusRow,
        padding: _kRowPadding,
        color: AppTheme.primary.withValues(alpha: 0.08),
        side: BorderSide(color: AppTheme.primaryLight.withValues(alpha: 0.3)),
        onTap: onTap,
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: AppTheme.primaryGradient,
              ),
              alignment: Alignment.center,
              child: Image.asset(
                'assets/logo/logo-without-letters.png',
                width: 22,
                height: 22,
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.teamDartRivals,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.sectionTitle,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    l10n.teamConversationSubtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.caption,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            _RoundIconButton(
              icon: Icons.chat_bubble_outline_rounded,
              color: AppTheme.primaryLight,
              borderColor: AppTheme.primaryLight.withValues(alpha: 0.45),
              badge: unreadCount > 0 ? DsBadge(count: unreadCount) : null,
              semanticsLabel: l10n.chatMessageAction,
              onTap: onTap,
            ),
          ],
        ),
      ),
    );
  }
}

/// Quiet empty state on a card: 32 px tertiary icon, a title, an optional
/// hint and an optional action.
class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  const _EmptyState({
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return DsCard(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 32, color: AppTheme.textTertiary),
          const SizedBox(height: 12),
          Text(title, textAlign: TextAlign.center, style: AppTheme.rowTitle),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle!, textAlign: TextAlign.center, style: AppTheme.caption),
          ],
          if (action != null) ...[
            const SizedBox(height: 16),
            SizedBox(width: double.infinity, child: action),
          ],
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 32, color: AppTheme.error),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: AppTheme.bodyMedium),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: Text(l10n.retry)),
          ],
        ),
      ),
    );
  }
}
