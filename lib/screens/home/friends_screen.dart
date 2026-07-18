import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/friends_provider.dart';
import '../../models/user.dart';
import '../../services/friends_service.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/rank_badge.dart';
import '../../widgets/premium_badge.dart';
import '../../utils/app_navigator.dart';
import '../../utils/app_theme.dart';
import '../../utils/friendly_match_launcher.dart';
import '../../utils/haptic_service.dart';
import '../profile/player_stats_screen.dart';

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
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text(l10n.removeFriendTitle, style: const TextStyle(color: Colors.white)),
        content: Text(
          l10n.removeFriendMessage.replaceAll('{username}', username),
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
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

  @override
  Widget build(BuildContext context) {
    final friendsProvider = context.watch<FriendsProvider>();
    final l10n = AppLocalizations.of(context);

    if (_showSearch) {
      return Column(
        children: [
          _buildSearchSection(),
          Expanded(child: _buildSearchResults()),
        ],
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              Text(
                l10n.friends,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: AppTheme.surfaceLight.withValues(alpha: 0.7),
                  ),
                ),
                child: Text(
                  '${friendsProvider.friends.length}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: () {
                  HapticService.lightImpact();
                  setState(() => _showSearch = true);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: const Icon(Icons.person_add, size: 16),
                label: Text(l10n.add, style: const TextStyle(fontSize: 12.5)),
              ),
            ],
          ),
        ),
        TabBar(
          controller: _tabController,
          labelColor: AppTheme.primary,
          unselectedLabelColor: AppTheme.textSecondary,
          indicatorColor: AppTheme.primary,
          dividerColor: Colors.transparent,
          labelStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
          tabs: [
            Tab(
              height: 40,
              text: '${l10n.friendsCount} (${friendsProvider.friends.length})',
            ),
            Tab(
              height: 40,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(l10n.requests),
                  if (friendsProvider.pendingRequestsCount > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppTheme.error,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${friendsProvider.pendingRequestsCount}',
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildFriendsList(friendsProvider.friends, friendsProvider),
              _buildRequestsList(friendsProvider),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSearchSection() {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () {
                  HapticService.lightImpact();
                  setState(() {
                    _showSearch = false;
                    _searchController.clear();
                    _searchResults = [];
                  });
                },
                icon: const Icon(Icons.arrow_back),
              ),
              Expanded(
                child: TextField(
                  controller: _searchController,
                  autofocus: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: l10n.searchByUsernameHint,
                    hintStyle: TextStyle(color: AppTheme.textSecondary),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppTheme.surfaceLight),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppTheme.surfaceLight),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppTheme.primary, width: 2),
                    ),
                    prefixIcon: const Icon(Icons.search, color: AppTheme.textSecondary),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, color: AppTheme.textSecondary),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _searchResults = [];
                              });
                            },
                          )
                        : null,
                  ),
                  onChanged: (value) {
                    _performSearch(value);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
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
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search, size: 64, color: AppTheme.textSecondary.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text(
              l10n.searchForUsersByUsername,
              style: AppTheme.titleLarge.copyWith(color: AppTheme.textSecondary),
            ),
          ],
        ),
      );
    }

    if (_searchResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_off, size: 64, color: AppTheme.textSecondary.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text(
              l10n.noUsersFound,
              style: AppTheme.titleLarge.copyWith(color: AppTheme.textSecondary),
            ),
          ],
        ),
      );
    }

    final friendsProvider = context.watch<FriendsProvider>();

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _searchResults.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final user = _searchResults[index];
        final status = friendsProvider.getFriendshipStatus(user.id);
        
        return Container(
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.surfaceLight.withValues(alpha: 0.5)),
          ),
          child: ListTile(
            leading: RankBadge(
              rank: user.rank,
              size: 40,
              showLabel: false,
            ),
            title: Row(
              children: [
                Flexible(
                  child: Text(
                    user.username,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                PremiumBadge(isPremium: user.isPremiumActive, size: 14),
              ],
            ),
            subtitle: Text(
              'ELO: ${user.elo} • ${user.wins}W - ${user.losses}L',
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
            trailing: _buildSearchResultAction(user.id, user.username, status),
            onTap: () {
              AppNavigator.toScreen(
                context,
                PlayerStatsScreen(userId: user.id, username: user.username),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildSearchResultAction(String userId, String username, String status) {
    final l10n = AppLocalizations.of(context);
    switch (status) {
      case 'friends':
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, color: AppTheme.success, size: 20),
            SizedBox(width: 4),
            Text(l10n.friendsStatus, style: TextStyle(color: AppTheme.success, fontSize: 12)),
          ],
        );
      case 'pending_sent':
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.schedule, color: AppTheme.textSecondary, size: 20),
            SizedBox(width: 4),
            Text(l10n.pendingStatus, style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
          ],
        );
      case 'pending_received':
        return TextButton(
          onPressed: () async {
            final friendsProvider = context.read<FriendsProvider>();
            final request = friendsProvider.pendingRequests.firstWhere((r) => r.user.id == userId);
            await _acceptRequest(request.id, username);
          },
          child: Text(l10n.acceptButton, style: const TextStyle(fontSize: 12)),
        );
      default:
        return IconButton(
          icon: const Icon(Icons.person_add, color: AppTheme.primary),
          onPressed: () => _sendFriendRequest(userId, username),
        );
    }
  }

  Widget _buildRequestsList(FriendsProvider provider) {
    final l10n = AppLocalizations.of(context);
    final pendingRequests = provider.pendingRequests;
    final sentRequests = provider.sentRequests;

    if (pendingRequests.isEmpty && sentRequests.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 64, color: AppTheme.textSecondary.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text(
              l10n.noFriendRequests,
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 16),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (pendingRequests.isNotEmpty) ...[
          Text(
            l10n.incomingRequests,
            style: TextStyle(color: AppTheme.primary, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          ...pendingRequests.map((request) => _buildRequestCard(request, true)),
          const SizedBox(height: 24),
        ],
        if (sentRequests.isNotEmpty) ...[
          Text(
            l10n.sentRequests,
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          ...sentRequests.map((request) => _buildRequestCard(request, false)),
        ],
      ],
    );
  }

  Widget _buildRequestCard(FriendRequest request, bool isIncoming) {
    final l10n = AppLocalizations.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isIncoming ? AppTheme.primary.withValues(alpha: 0.3) : AppTheme.surfaceLight.withValues(alpha: 0.5),
        ),
      ),
      child: ListTile(
        leading: RankBadge(
          rank: request.user.rank,
          size: 40,
          showLabel: false,
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                request.user.username,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            PremiumBadge(isPremium: request.user.isPremiumActive, size: 14),
          ],
        ),
        subtitle: Text(
          'ELO: ${request.user.elo} • ${request.user.wins}W - ${request.user.losses}L',
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
        ),
        trailing: isIncoming
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.check, color: AppTheme.success),
                    onPressed: () => _acceptRequest(request.id, request.user.username),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: AppTheme.error),
                    onPressed: () => _rejectRequest(request.id, request.user.username),
                  ),
                ],
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.schedule, color: AppTheme.textSecondary, size: 20),
                  SizedBox(width: 4),
                  Text(l10n.pendingStatus, style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                ],
              ),
        onTap: () {
          AppNavigator.toScreen(
            context,
            PlayerStatsScreen(userId: request.user.id, username: request.user.username),
          );
        },
      ),
    );
  }

  Widget _buildFriendsList(List<User> friends, FriendsProvider provider) {
    final l10n = AppLocalizations.of(context);
    if (provider.isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primary),
      );
    }

    if (provider.error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: AppTheme.error, size: 64),
            const SizedBox(height: 16),
            Text(
              provider.error!.replaceAll('Exception: ', ''),
              style: const TextStyle(color: AppTheme.error),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => provider.loadFriends(),
              child: Text(l10n.retry),
            ),
          ],
        ),
      );
    }

    if (friends.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 64, color: AppTheme.textSecondary.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text(
              l10n.noFriendsYet,
              style: AppTheme.titleLarge.copyWith(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.addFriendsHint,
              style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _showSearch = true;
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              ),
              icon: const Icon(Icons.person_add),
              label: Text(l10n.addFriendsButton),
            ),
          ],
        ),
      );
    }

    // Online friends first — they're the ones you can actually challenge now.
    final sorted = [
      ...friends.where((f) => provider.isOnline(f.id)),
      ...friends.where((f) => !provider.isOnline(f.id)),
    ];

    return RefreshIndicator(
      onRefresh: () => provider.loadFriends(),
      color: AppTheme.primary,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: sorted.length,
        separatorBuilder: (context, index) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final friend = sorted[index];
          final isOnline = provider.isOnline(friend.id);
          return _FriendRow(
            friend: friend,
            isOnline: isOnline,
            onChallenge: () => FriendlyMatchLauncher.invite(context, friend),
            onRemove: () => _removeFriend(friend.id, friend.username),
            onTap: () {
              AppNavigator.toScreen(
                context,
                PlayerStatsScreen(userId: friend.id, username: friend.username),
              );
            },
          );
        },
      ),
    );
  }
}

/// Dense friend row: presence dot on the rank badge, one "Challenge" CTA
/// (solid when the friend is online), removal moved behind a swipe so the
/// destructive action is never one accidental tap away.
class _FriendRow extends StatelessWidget {
  final User friend;
  final bool isOnline;
  final VoidCallback onChallenge;
  final Future<void> Function() onRemove;
  final VoidCallback onTap;

  const _FriendRow({
    required this.friend,
    required this.isOnline,
    required this.onChallenge,
    required this.onRemove,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return ClipRRect(
      borderRadius: BorderRadius.circular(13),
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
              const Icon(Icons.person_remove, color: Colors.white, size: 20),
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
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                color: isOnline
                    ? AppTheme.success.withValues(alpha: 0.35)
                    : AppTheme.surfaceLight.withValues(alpha: 0.55),
              ),
            ),
            child: Row(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    RankBadge(rank: friend.rank, size: 36, showLabel: false),
                    Positioned(
                      right: -1,
                      bottom: -1,
                      child: Semantics(
                        label: isOnline ? l10n.online : null,
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: isOnline
                                ? AppTheme.success
                                : AppTheme.surfaceLight,
                            shape: BoxShape.circle,
                            border: Border.all(color: AppTheme.surface, width: 2),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              friend.username,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          PremiumBadge(isPremium: friend.isPremiumActive, size: 12),
                        ],
                      ),
                      const SizedBox(height: 1),
                      Text.rich(
                        TextSpan(
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 11,
                          ),
                          children: [
                            if (isOnline)
                              TextSpan(
                                text: '● ${l10n.online} · ',
                                style: const TextStyle(
                                  color: AppTheme.success,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            TextSpan(
                              text:
                                  '${friend.elo} · ${friend.wins}${l10n.formWinLetter}-${friend.losses}${l10n.formLossLetter}',
                            ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Material(
                  color: isOnline ? AppTheme.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () {
                      HapticService.lightImpact();
                      onChallenge();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        border: isOnline
                            ? null
                            : Border.all(
                                color: AppTheme.primary.withValues(alpha: 0.45),
                              ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.track_changes,
                            size: 14,
                            color: isOnline ? Colors.white : AppTheme.primary,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            l10n.challengeFriend,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: isOnline ? Colors.white : AppTheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
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
