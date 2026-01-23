import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/friends_provider.dart';
import '../../models/user.dart';
import '../../services/friends_service.dart';
import '../../widgets/rank_badge.dart';
import '../../utils/app_theme.dart';
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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<FriendsProvider>().loadAll();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _performSearch(String query) async {
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
            content: Text('Search failed: ${e.toString().replaceAll('Exception: ', '')}'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  Future<void> _sendFriendRequest(String friendId, String username) async {
    try {
      HapticService.mediumImpact();
      await context.read<FriendsProvider>().sendFriendRequest(friendId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Friend request sent to $username!'),
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
    try {
      HapticService.mediumImpact();
      await context.read<FriendsProvider>().acceptFriendRequest(friendshipId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('You are now friends with $username!'),
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
    try {
      HapticService.mediumImpact();
      await context.read<FriendsProvider>().rejectFriendRequest(friendshipId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Declined friend request from $username'),
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
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Remove Friend', style: TextStyle(color: Colors.white)),
        content: Text(
          'Are you sure you want to remove $username from your friends?',
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.error),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        HapticService.mediumImpact();
        await context.read<FriendsProvider>().removeFriend(friendId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Removed $username from friends'),
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
        Container(
          color: AppTheme.surface,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text('Friends', style: AppTheme.titleLarge),
                    ),
                    ElevatedButton.icon(
                      onPressed: () {
                        HapticService.lightImpact();
                        setState(() => _showSearch = true);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                      icon: const Icon(Icons.person_add, size: 20),
                      label: const Text('Add'),
                    ),
                  ],
                ),
              ),
              TabBar(
                controller: _tabController,
                labelColor: AppTheme.primary,
                unselectedLabelColor: AppTheme.textSecondary,
                indicatorColor: AppTheme.primary,
                tabs: [
                  Tab(text: 'Friends (${friendsProvider.friends.length})'),
                  Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('Requests'),
                        if (friendsProvider.pendingRequestsCount > 0) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.error,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${friendsProvider.pendingRequestsCount}',
                              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
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
                    hintText: 'Search by username...',
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
              'Search for users by username',
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
              'No users found',
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
            title: Text(
              user.username,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              'ELO: ${user.elo} • ${user.wins}W - ${user.losses}L',
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
            trailing: _buildSearchResultAction(user.id, user.username, status),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => PlayerStatsScreen(
                    userId: user.id,
                    username: user.username,
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildSearchResultAction(String userId, String username, String status) {
    switch (status) {
      case 'friends':
        return const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, color: AppTheme.success, size: 20),
            SizedBox(width: 4),
            Text('Friends', style: TextStyle(color: AppTheme.success, fontSize: 12)),
          ],
        );
      case 'pending_sent':
        return const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.schedule, color: AppTheme.textSecondary, size: 20),
            SizedBox(width: 4),
            Text('Pending', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
          ],
        );
      case 'pending_received':
        return TextButton(
          onPressed: () async {
            final friendsProvider = context.read<FriendsProvider>();
            final request = friendsProvider.pendingRequests.firstWhere((r) => r.user.id == userId);
            await _acceptRequest(request.id, username);
          },
          child: const Text('Accept', style: TextStyle(fontSize: 12)),
        );
      default:
        return IconButton(
          icon: const Icon(Icons.person_add, color: AppTheme.primary),
          onPressed: () => _sendFriendRequest(userId, username),
        );
    }
  }

  Widget _buildRequestsList(FriendsProvider provider) {
    final pendingRequests = provider.pendingRequests;
    final sentRequests = provider.sentRequests;

    if (pendingRequests.isEmpty && sentRequests.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 64, color: AppTheme.textSecondary.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            const Text(
              'No friend requests',
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
          const Text(
            'Incoming Requests',
            style: TextStyle(color: AppTheme.primary, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          ...pendingRequests.map((request) => _buildRequestCard(request, true)),
          const SizedBox(height: 24),
        ],
        if (sentRequests.isNotEmpty) ...[
          const Text(
            'Sent Requests',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          ...sentRequests.map((request) => _buildRequestCard(request, false)),
        ],
      ],
    );
  }

  Widget _buildRequestCard(FriendRequest request, bool isIncoming) {
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
        title: Text(
          request.user.username,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
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
            : const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.schedule, color: AppTheme.textSecondary, size: 20),
                  SizedBox(width: 4),
                  Text('Pending', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                ],
              ),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => PlayerStatsScreen(
                userId: request.user.id,
                username: request.user.username,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFriendsList(List<User> friends, FriendsProvider provider) {
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
              child: const Text('Retry'),
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
              'No friends yet',
              style: AppTheme.titleLarge.copyWith(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 8),
            Text(
              'Add friends to see them here!',
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
              label: const Text('Add Friends'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => provider.loadFriends(),
      color: AppTheme.primary,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: friends.length,
        separatorBuilder: (context, index) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final friend = friends[index];
          return Container(
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.surfaceLight.withValues(alpha: 0.5)),
            ),
            child: ListTile(
              leading: RankBadge(
                rank: friend.rank,
                size: 40,
                showLabel: false,
              ),
              title: Text(
                friend.username,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                'ELO: ${friend.elo} • ${friend.wins}W - ${friend.losses}L',
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.person_remove, color: AppTheme.error),
                onPressed: () => _removeFriend(friend.id, friend.username),
              ),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => PlayerStatsScreen(
                      userId: friend.id,
                      username: friend.username,
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
