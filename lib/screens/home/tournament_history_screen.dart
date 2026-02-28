import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/tournament_provider.dart';
import '../../models/tournament.dart';
import '../../utils/app_theme.dart';
import '../../utils/haptic_service.dart';
import 'tournament_detail_screen.dart';

class TournamentHistoryScreen extends StatefulWidget {
  const TournamentHistoryScreen({super.key});

  @override
  State<TournamentHistoryScreen> createState() => _TournamentHistoryScreenState();
}

class _TournamentHistoryScreenState extends State<TournamentHistoryScreen> {
  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final provider = context.read<TournamentProvider>();
    await provider.loadTournamentHistory();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        elevation: 0,
        title: const Text(
          'Tournament History',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.textPrimary),
          onPressed: () {
            HapticService.lightImpact();
            Navigator.pop(context);
          },
        ),
      ),
      body: Consumer<TournamentProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          final history = provider.tournamentHistory;

          if (history.isEmpty) {
            return RefreshIndicator(
              onRefresh: _loadHistory,
              child: ListView(
                children: [
                  SizedBox(height: MediaQuery.of(context).size.height * 0.3),
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.history,
                          size: 64,
                          color: AppTheme.textSecondary.withValues(alpha: 0.5),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'No Tournament History',
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Complete tournaments to see your history here',
                          style: TextStyle(
                            color: AppTheme.textSecondary.withValues(alpha: 0.7),
                            fontSize: 14,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _loadHistory,
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: history.length,
              itemBuilder: (context, index) {
                return _TournamentHistoryCard(tournament: history[index]);
              },
            ),
          );
        },
      ),
    );
  }
}

class _TournamentHistoryCard extends StatelessWidget {
  final TournamentHistory tournament;

  const _TournamentHistoryCard({required this.tournament});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticService.lightImpact();
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => TournamentDetailScreen(tournamentId: tournament.id),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              tournament.isWinner
                  ? AppTheme.accent.withValues(alpha: 0.15)
                  : AppTheme.surface,
              AppTheme.surfaceLight.withValues(alpha: 0.5),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: tournament.isWinner
                ? AppTheme.accent.withValues(alpha: 0.6)
                : AppTheme.surfaceLight.withValues(alpha: 0.3),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          tournament.isWinner
                              ? AppTheme.accent.withValues(alpha: 0.3)
                              : AppTheme.primary.withValues(alpha: 0.3),
                          tournament.isWinner
                              ? AppTheme.accent.withValues(alpha: 0.1)
                              : AppTheme.primary.withValues(alpha: 0.1),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      tournament.isWinner ? Icons.emoji_events : Icons.emoji_events_outlined,
                      color: tournament.isWinner ? AppTheme.accent : AppTheme.primary,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tournament.name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.calendar_today,
                              size: 12,
                              color: AppTheme.textSecondary.withValues(alpha: 0.8),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _formatDate(tournament.scheduledDate),
                              style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.textSecondary.withValues(alpha: 0.8),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          _getPlacementColor(tournament.placement).withValues(alpha: 0.2),
                          _getPlacementColor(tournament.placement).withValues(alpha: 0.1),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _getPlacementColor(tournament.placement).withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      tournament.placementDisplay,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: _getPlacementColor(tournament.placement),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  _InfoChip(
                    icon: Icons.people,
                    label: '${tournament.totalParticipants} players',
                  ),
                  const SizedBox(width: 10),
                  if (tournament.isWinner) ...[
                    _InfoChip(
                      icon: Icons.star,
                      label: '+${tournament.winnerEloReward} ELO',
                      color: AppTheme.accent,
                    ),
                    const SizedBox(width: 10),
                  ],
                  if (tournament.hasPrize && tournament.isWinner) ...[
                    _InfoChip(
                      icon: tournament.hasCashPrize ? Icons.attach_money : Icons.emoji_events,
                      label: tournament.formattedPrize,
                      color: tournament.hasCashPrize ? AppTheme.success : AppTheme.accent,
                    ),
                  ],
                  const Spacer(),
                  Icon(
                    Icons.arrow_forward_ios,
                    size: 14,
                    color: AppTheme.textSecondary.withValues(alpha: 0.5),
                  ),
                ],
              ),
              if (tournament.winnerUsername != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceLight.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.emoji_events,
                        size: 14,
                        color: AppTheme.accent,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Winner: ${tournament.winnerUsername}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Color _getPlacementColor(int? placement) {
    if (placement == null) return AppTheme.textSecondary;
    if (placement == 1) return AppTheme.accent;
    if (placement == 2) return const Color(0xFFC0C0C0);
    if (placement == 3) return const Color(0xFFCD7F32);
    return AppTheme.textSecondary;
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;

  const _InfoChip({
    required this.icon,
    required this.label,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final chipColor = color ?? AppTheme.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: chipColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: chipColor),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: chipColor,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }
}
