import 'package:flutter/material.dart';
import '../../services/user_service.dart';
import '../../widgets/rank_badge.dart';
import '../profile/match_history_screen.dart';
import '../../utils/app_theme.dart';

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

class _PlayerStatsScreenState extends State<PlayerStatsScreen> {
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
      var stats = await UserService.getUserStats(widget.userId);
      
      // If backend returns zeros, calculate from match history
      if (stats.totalMatches == 0) {
        try {
          final matches = await UserService.getUserMatches(widget.userId);
          if (matches.isNotEmpty) {
            stats = UserService.calculateStatsFromMatches(matches, widget.userId);
          }
        } catch (_) {
          // If match history fails, use backend stats (even if zeros)
        }
      }
      
      setState(() {
        _stats = stats;
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
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(widget.username),
        backgroundColor: AppTheme.surface,
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primary),
            )
          : _errorMessage != null
              ? Center(
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
                        onPressed: _loadStats,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _stats == null
                  ? const Center(child: Text('No statistics available'))
                  : RefreshIndicator(
                      onRefresh: _loadStats,
                      color: AppTheme.primary,
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Performance Overview',
                              style: AppTheme.titleLarge,
                            ),
                            const SizedBox(height: 16),
                            GridView.count(
                              crossAxisCount: 2,
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              mainAxisSpacing: 16,
                              crossAxisSpacing: 16,
                              childAspectRatio: 1.35,
                              children: [
                                _buildStatCard(
                                  'Win Rate',
                                  '${_stats!.winRate.toStringAsFixed(1)}%',
                                  Icons.trending_up,
                                  AppTheme.success,
                                ),
                                _buildStatCard(
                                  'Total Matches',
                                  _stats!.totalMatches.toString(),
                                  Icons.sports_esports,
                                  AppTheme.primary,
                                ),
                                _buildStatCard(
                                  'Avg Score',
                                  _stats!.averageScore.toStringAsFixed(1),
                                  Icons.calculate,
                                  AppTheme.accent,
                                ),
                                _buildStatCard(
                                  'Highest Score',
                                  _stats!.highestScore.toString(),
                                  Icons.emoji_events,
                                  const Color(0xFFFFD700),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: AppTheme.surface,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: AppTheme.surfaceLight.withValues(alpha: 0.5)),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: [
                                        Text(
                                          'WINS',
                                          style: AppTheme.labelLarge.copyWith(color: AppTheme.textSecondary),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          _stats!.wins.toString(),
                                          style: const TextStyle(
                                            fontSize: 32,
                                            fontWeight: FontWeight.bold,
                                            color: AppTheme.success,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    width: 1,
                                    height: 40,
                                    color: AppTheme.surfaceLight,
                                  ),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: [
                                        Text(
                                          'LOSSES',
                                          style: AppTheme.labelLarge.copyWith(color: AppTheme.textSecondary),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          _stats!.losses.toString(),
                                          style: const TextStyle(
                                            fontSize: 32,
                                            fontWeight: FontWeight.bold,
                                            color: AppTheme.error,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    width: 1,
                                    height: 40,
                                    color: AppTheme.surfaceLight,
                                  ),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: [
                                        Text(
                                          'STREAK',
                                          style: AppTheme.labelLarge.copyWith(color: AppTheme.textSecondary),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          _stats!.currentStreak.toString(),
                                          style: TextStyle(
                                            fontSize: 32,
                                            fontWeight: FontWeight.bold,
                                            color: _stats!.currentStreak > 0 ? const Color(0xFFFF6B35) : AppTheme.textSecondary,
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
                    ),
    );
  }

  Widget _buildStatCard(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.surfaceLight.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: AppTheme.labelLarge.copyWith(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
