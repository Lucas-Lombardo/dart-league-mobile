import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/user_service.dart';
import '../profile/match_history_screen.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  bool _isLoading = true;
  UserStats? _stats;
  String? _errorMessage;

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

    try {
      final authProvider = context.read<AuthProvider>();
      final userId = authProvider.currentUser?.id;
      
      if (userId != null) {
        var stats = await UserService.getUserStats(userId);
        
        // If backend returns zeros, calculate from match history
        if (stats.totalMatches == 0) {
          try {
            final matches = await UserService.getUserMatches(userId);
            if (matches.isNotEmpty) {
              stats = UserService.calculateStatsFromMatches(matches, userId);
            }
          } catch (e) {
            // If match history fails, use backend stats (even if zeros)
            debugPrint('Failed to load matches for stats calculation: $e');
          }
        }
        
        setState(() {
          _stats = stats;
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
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          color: Color(0xFF00E5FF),
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Color(0xFFFF5252), size: 64),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              style: const TextStyle(color: Color(0xFFFF5252)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadStats,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00E5FF),
                foregroundColor: Colors.black,
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_stats == null) {
      return const Center(
        child: Text('No statistics available'),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadStats,
      color: const Color(0xFF00E5FF),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const MatchHistoryScreen(),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00E5FF),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.history),
                label: const Text(
                  'View Match History',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            _buildStatCard(
              'Total Matches',
              _stats!.totalMatches.toString(),
              Icons.sports_esports,
              const Color(0xFF00E5FF),
            ),
            const SizedBox(height: 12),
            _buildStatCard(
              'Win Rate',
              '${_stats!.winRate.toStringAsFixed(1)}%',
              Icons.trending_up,
              const Color(0xFF4CAF50),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    'Wins',
                    _stats!.wins.toString(),
                    Icons.check_circle,
                    const Color(0xFF4CAF50),
                    compact: true,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatCard(
                    'Losses',
                    _stats!.losses.toString(),
                    Icons.cancel,
                    const Color(0xFFFF5252),
                    compact: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildStatCard(
              'Average Score',
              _stats!.averageScore.toStringAsFixed(1),
              Icons.calculate,
              const Color(0xFFFFB74D),
            ),
            const SizedBox(height: 12),
            _buildStatCard(
              'Highest Score',
              _stats!.highestScore.toString(),
              Icons.emoji_events,
              const Color(0xFFFFD700),
            ),
            const SizedBox(height: 12),
            _buildStatCard(
              'Current Streak',
              _stats!.currentStreak.toString(),
              Icons.local_fire_department,
              _stats!.currentStreak > 0 ? const Color(0xFFFF6B35) : Colors.grey,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(
    String label,
    String value,
    IconData icon,
    Color color, {
    bool compact = false,
  }) {
    return Container(
      padding: EdgeInsets.all(compact ? 16 : 20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 2),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: compact ? 24 : 32),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: compact ? 12 : 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    color: color,
                    fontSize: compact ? 24 : 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
