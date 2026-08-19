import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/auth_provider.dart';
import '../../services/user_service.dart';
import '../../utils/app_navigator.dart';
import '../../utils/app_theme.dart';
import '../../utils/haptic_service.dart';
import 'head_to_head_screen.dart';

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
      final stats = await UserService.getUserStats(widget.userId);

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
                        child: Text(AppLocalizations.of(context).retry),
                      ),
                    ],
                  ),
                )
              : _stats == null
                  ? Center(child: Text(AppLocalizations.of(context).noStatisticsAvailable))
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
                              AppLocalizations.of(context).performanceOverview,
                              style: AppTheme.titleLarge,
                            ),
                            const SizedBox(height: 16),
                            // Their career, then what they have done to YOU —
                            // the second question every player asks on this
                            // screen, and the one it could never answer. Absent
                            // on your own profile: there is no head-to-head
                            // against yourself, and the endpoint refuses it.
                            if (!_isSelf(context)) ...[
                              _buildHeadToHeadButton(context),
                              const SizedBox(height: 16),
                            ],
                            GridView.count(
                              crossAxisCount: 2,
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              mainAxisSpacing: 16,
                              crossAxisSpacing: 16,
                              childAspectRatio: 1.1,
                              children: [
                                _buildStatCard(
                                  AppLocalizations.of(context).winRate,
                                  '${_stats!.winRate.toStringAsFixed(1)}%',
                                  Icons.trending_up,
                                  AppTheme.success,
                                ),
                                _buildStatCard(
                                  AppLocalizations.of(context).totalMatches,
                                  _stats!.totalMatches.toString(),
                                  Icons.sports_esports,
                                  AppTheme.primary,
                                ),
                                // A player whose only matches were against
                                // bots has no measured darts here — showing
                                // "0.0" would read as a real average.
                                _buildStatCard(
                                  AppLocalizations.of(context).avgScore,
                                  _stats!.legsCounted == 0
                                      ? '—'
                                      : _stats!.averageScore.toStringAsFixed(1),
                                  Icons.calculate,
                                  AppTheme.accent,
                                ),
                                _buildStatCard(
                                  AppLocalizations.of(context).count180s,
                                  _stats!.legsCounted == 0
                                      ? '—'
                                      : _stats!.count180s.toString(),
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
                                          AppLocalizations.of(context).wins.toUpperCase(),
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
                                          AppLocalizations.of(context).losses.toUpperCase(),
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
                                          AppLocalizations.of(context).streak,
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

  /// This screen also opens on your OWN row in the leaderboard.
  bool _isSelf(BuildContext context) =>
      context.read<AuthProvider>().currentUser?.id == widget.userId;

  Widget _buildHeadToHeadButton(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          HapticService.lightImpact();
          AppNavigator.toScreen(
            context,
            HeadToHeadScreen(
              opponentId: widget.userId,
              opponentUsername: widget.username,
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.primary.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              const Icon(Icons.compare_arrows_rounded, color: AppTheme.primary, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  l10n.headToHeadTitle,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right, color: AppTheme.textSecondary),
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
