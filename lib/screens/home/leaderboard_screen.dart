import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/user_service.dart';
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
      final entries = await UserService.getLeaderboard();
      setState(() {
        _entries = entries;
        _isLoading = false;
      });
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
      return const Center(
        child: Text('No leaderboard data available'),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadLeaderboard,
      color: AppTheme.primary,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(child: _buildHeaderCell('Rank', TextAlign.center)),
                Expanded(flex: 3, child: _buildHeaderCell('Player', TextAlign.left)),
                Expanded(child: _buildHeaderCell('ELO', TextAlign.right)),
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
}
