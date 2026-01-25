import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/user_service.dart';
import '../../services/friends_service.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/rank_badge.dart';
import '../../utils/app_theme.dart';
import '../profile/player_stats_screen.dart';

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  bool _isLoading = true;
  List<LeaderboardEntry> _entries = [];
  String? _errorMessage;
  bool _showFriendsOnly = false;

  @override
  void initState() {
    super.initState();
    _loadLeaderboard();
  }

  Future<void> _loadLeaderboard() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      if (_showFriendsOnly) {
        final friends = await FriendsService.getFriendsLeaderboard();
        final entries = friends.asMap().entries.map((entry) {
          final index = entry.key;
          final user = entry.value;
          return LeaderboardEntry(
            user: user,
            rank: index + 1,
            wins: user.wins,
            losses: user.losses,
          );
        }).toList();
        setState(() {
          _entries = entries;
          _isLoading = false;
        });
      } else {
        final entries = await UserService.getLeaderboard();
        setState(() {
          _entries = entries;
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = context.watch<AuthProvider>().currentUser?.id;
    final l10n = AppLocalizations.of(context);

    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          color: AppTheme.primary,
        ),
      );
    }

    if (_errorMessage != null) {
      return RefreshIndicator(
        onRefresh: _loadLeaderboard,
        color: AppTheme.primary,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: AppTheme.error, size: 64),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                style: const TextStyle(color: AppTheme.error),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadLeaderboard,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_entries.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _showFriendsOnly ? Icons.people_outline : Icons.leaderboard_outlined,
              size: 64,
              color: AppTheme.textSecondary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              _showFriendsOnly ? 'No friends yet' : 'No leaderboard data available',
              style: AppTheme.titleLarge.copyWith(color: AppTheme.textSecondary),
            ),
            if (_showFriendsOnly) ...[
              const SizedBox(height: 8),
              const Text(
                'Add friends to see their rankings!',
                style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
              ),
            ],
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadLeaderboard,
      color: AppTheme.primary,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.surfaceLight.withValues(alpha: 0.5)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
            child: Row(
              children: [
                Icon(
                  _showFriendsOnly ? Icons.people : Icons.public,
                  color: AppTheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _showFriendsOnly ? l10n.friends : l10n.globalLeaderboard,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceLight.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      _buildToggleButton(l10n.global, !_showFriendsOnly, () {
                        setState(() {
                          _showFriendsOnly = false;
                        });
                        _loadLeaderboard();
                      }),
                      _buildToggleButton(l10n.friends, _showFriendsOnly, () {
                        setState(() {
                          _showFriendsOnly = true;
                        });
                        _loadLeaderboard();
                      }),
                    ],
                  ),
                ),
              ],
            ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                Expanded(child: _buildHeaderCell(l10n.rank.toUpperCase(), TextAlign.center)),
                Expanded(flex: 3, child: _buildHeaderCell(l10n.player.toUpperCase(), TextAlign.left)),
                Expanded(child: _buildHeaderCell(l10n.elo, TextAlign.right)),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: _entries.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final entry = _entries[index];
                final isCurrentUser = entry.user.id == currentUserId;
                final isTopThree = index < 3;

                return InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => PlayerStatsScreen(
                          userId: entry.user.id,
                          username: entry.user.username,
                        ),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isCurrentUser
                          ? AppTheme.primary.withValues(alpha: 0.15)
                          : AppTheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isCurrentUser
                            ? AppTheme.primary
                            : Colors.transparent,
                        width: 1,
                      ),
                      boxShadow: [
                        if (isTopThree)
                          BoxShadow(
                            color: _getRankColor(index).withValues(alpha: 0.2),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                      ],
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      leading: SizedBox(
                        width: 40,
                        child: Center(
                          child: isTopThree
                            ? Icon(
                                Icons.emoji_events,
                                color: _getRankColor(index),
                                size: 32,
                              )
                            : Text(
                                '${entry.rank}',
                                style: TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                        ),
                      ),
                      title: Row(
                        children: [
                          RankBadge(
                            rank: entry.user.rank,
                            size: 40,
                            showLabel: false,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              entry.user.username,
                              style: TextStyle(
                                color: isCurrentUser ? AppTheme.primary : Colors.white,
                                fontWeight: isCurrentUser ? FontWeight.bold : FontWeight.w500,
                                fontSize: 16,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      subtitle: Text(
                        '${entry.wins}W - ${entry.losses}L',
                        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                      ),
                      trailing: Text(
                        '${entry.user.elo}',
                        style: TextStyle(
                          color: isTopThree ? _getRankColor(index) : AppTheme.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderCell(String text, TextAlign align) {
    return Text(
      text.toUpperCase(),
      textAlign: align,
      style: AppTheme.labelLarge.copyWith(color: AppTheme.textSecondary),
    );
  }

  Color _getRankColor(int index) {
    switch (index) {
      case 0:
        return const Color(0xFFFFD700);
      case 1:
        return const Color(0xFFC0C0C0);
      case 2:
        return const Color(0xFFCD7F32);
      default:
        return AppTheme.textSecondary;
    }
  }

  Widget _buildToggleButton(String label, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : AppTheme.textSecondary,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}
