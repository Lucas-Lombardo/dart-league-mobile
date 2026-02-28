import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/user_service.dart';
import '../../l10n/app_localizations.dart';
import '../profile/match_history_screen.dart';
import '../../utils/app_theme.dart';

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
        final stats = await UserService.getUserStats(userId);

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
    final l10n = AppLocalizations.of(context);
    
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          color: AppTheme.primary,
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
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
      );
    }

    if (_stats == null) {
      return const Center(
        child: Text('No statistics available'),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadStats,
      color: AppTheme.primary,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.performanceOverview,
              style: AppTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 1.1,
              children: [
                _buildStatCard(
                  l10n.winRate,
                  '${_stats!.winRate.toStringAsFixed(1)}%',
                  Icons.trending_up,
                  AppTheme.success,
                ),
                _buildStatCard(
                  l10n.totalMatches,
                  _stats!.totalMatches.toString(),
                  Icons.sports_esports,
                  AppTheme.primary,
                ),
                _buildStatCard(
                  l10n.avgScore,
                  _stats!.averageScore.toStringAsFixed(1),
                  Icons.calculate,
                  AppTheme.accent,
                ),
                _buildStatCard(
                  l10n.count180s,
                  _stats!.count180s.toString(),
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
                          l10n.wins.toUpperCase(),
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
                          l10n.losses.toUpperCase(),
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
                          l10n.streak,
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
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const MatchHistoryScreen(),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.surfaceLight,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 20),
              ),
              icon: const Icon(Icons.history_rounded),
              label: Text(l10n.viewFullMatchHistory),
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
