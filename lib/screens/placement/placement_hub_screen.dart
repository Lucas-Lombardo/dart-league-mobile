import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/placement_provider.dart';
import '../../utils/app_theme.dart';
import '../../l10n/app_localizations.dart';
import 'placement_game_screen.dart';
import 'placement_result_screen.dart';

class PlacementHubScreen extends StatefulWidget {
  const PlacementHubScreen({super.key});

  @override
  State<PlacementHubScreen> createState() => _PlacementHubScreenState();
}

class _PlacementHubScreenState extends State<PlacementHubScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PlacementProvider>().loadStatus();
    });
  }

  static const List<Map<String, dynamic>> _botConfigs = [
    {'name': 'Bot Bronze', 'avg': 20, 'color': Color(0xFFCD7F32), 'icon': Icons.shield_outlined},
    {'name': 'Bot Silver', 'avg': 30, 'color': Color(0xFFC0C0C0), 'icon': Icons.shield},
    {'name': 'Bot Gold', 'avg': 40, 'color': Color(0xFFFFD700), 'icon': Icons.shield},
    {'name': 'Bot Platinum', 'avg': 55, 'color': Color(0xFF00CED1), 'icon': Icons.shield},
  ];

  Future<void> _startNextMatch() async {
    final provider = context.read<PlacementProvider>();
    final success = await provider.startMatch();
    if (success && mounted) {
      final result = await Navigator.of(context).push<Map<String, dynamic>>(
        MaterialPageRoute(
          builder: (context) => const PlacementGameScreen(),
        ),
      );
      // Reload status after returning from game
      if (mounted) {
        await provider.loadStatus();
        // If placement just completed, show result screen
        if (result != null && result['placementComplete'] == true && mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) {
                final placementStatus = result['placementStatus'] as Map<String, dynamic>?;
                return PlacementResultScreen(
                  assignedRank: result['assignedRank'] as String? ?? 'bronze',
                  assignedElo: result['assignedElo'] as int? ?? 500,
                  wins: placementStatus?['wins'] as int? ?? 0,
                  totalMatches: 4,
                );
              },
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(l10n.placementMatches),
        backgroundColor: Colors.transparent,
      ),
      body: Consumer<PlacementProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading && provider.status == null) {
            return const Center(
              child: CircularProgressIndicator(color: AppTheme.primary),
            );
          }

          if (provider.error != null && provider.status == null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, color: AppTheme.error, size: 48),
                  const SizedBox(height: 16),
                  Text(provider.error!, style: const TextStyle(color: AppTheme.textSecondary)),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => provider.loadStatus(),
                    child: Text(l10n.retry),
                  ),
                ],
              ),
            );
          }

          final status = provider.status;
          if (status == null) {
            return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: AppTheme.surfaceGradient,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppTheme.surfaceLight.withValues(alpha: 0.5)),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.emoji_events, size: 48, color: AppTheme.accent),
                      const SizedBox(height: 12),
                      Text(l10n.placementMatches, style: AppTheme.displayMedium),
                      const SizedBox(height: 8),
                      Text(
                        l10n.placementDescription,
                        textAlign: TextAlign.center,
                        style: AppTheme.bodyLarge,
                      ),
                      const SizedBox(height: 16),
                      // Progress indicator
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '${status.matchesPlayed}/4',
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.primary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            l10n.matchesCompleted,
                            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
                          ),
                        ],
                      ),
                      if (status.wins > 0) ...[
                        const SizedBox(height: 4),
                        Text(
                          '${status.wins} ${status.wins == 1 ? l10n.winSingular : l10n.winsPlural}',
                          style: const TextStyle(
                            color: AppTheme.success,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Bot cards
                ...List.generate(4, (index) {
                  final matchNumber = index + 1;
                  final config = _botConfigs[index];
                  final result = status.results.length > index ? status.results[index] : null;
                  final isNext = matchNumber == (status.nextMatchNumber ?? 5);
                  final isLocked = matchNumber > (status.nextMatchNumber ?? 5);
                  final isCompleted = result != null;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _buildBotCard(
                      config: config,
                      matchNumber: matchNumber,
                      result: result,
                      isNext: isNext,
                      isLocked: isLocked,
                      isCompleted: isCompleted,
                      l10n: l10n,
                    ),
                  );
                }),

                const SizedBox(height: 20),

                // Start button
                if (!status.isComplete && status.nextMatchNumber != null)
                  SizedBox(
                    height: 56,
                    child: ElevatedButton(
                      onPressed: provider.isLoading ? null : _startNextMatch,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: provider.isLoading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : Text(
                              '${l10n.startMatch} vs ${status.nextBotName}',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildBotCard({
    required Map<String, dynamic> config,
    required int matchNumber,
    PlacementResult? result,
    required bool isNext,
    required bool isLocked,
    required bool isCompleted,
    required AppLocalizations l10n,
  }) {
    final color = config['color'] as Color;
    final botName = config['name'] as String;
    final avg = config['avg'] as int;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isLocked ? AppTheme.surface.withValues(alpha: 0.5) : AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isNext
              ? AppTheme.primary
              : isCompleted
                  ? (result!.won ? AppTheme.success : AppTheme.error)
                  : AppTheme.surfaceLight.withValues(alpha: 0.3),
          width: isNext ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          // Bot avatar
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: isLocked ? Colors.grey.withValues(alpha: 0.2) : color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isLocked ? Icons.lock : (config['icon'] as IconData),
              color: isLocked ? Colors.grey : color,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  botName,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isLocked ? AppTheme.textSecondary : AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Avg: $avg ${l10n.avgPerRound}',
                  style: TextStyle(
                    fontSize: 13,
                    color: isLocked ? AppTheme.textSecondary.withValues(alpha: 0.5) : AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          // Status
          if (isCompleted)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: result!.won
                    ? AppTheme.success.withValues(alpha: 0.15)
                    : AppTheme.error.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                result.won ? l10n.win.toUpperCase() : l10n.loss.toUpperCase(),
                style: TextStyle(
                  color: result.won ? AppTheme.success : AppTheme.error,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            )
          else if (isNext)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                l10n.next,
                style: const TextStyle(
                  color: AppTheme.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            )
          else if (isLocked)
            const Icon(Icons.lock_outline, color: Colors.grey, size: 20),
        ],
      ),
    );
  }
}
