import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/placement_provider.dart';
import '../../utils/app_navigator.dart';
import '../../utils/app_theme.dart';
import '../../utils/rank_translation.dart';
import '../../utils/rank_utils.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/design_system.dart';
import 'placement_camera_setup_screen.dart';
import 'placement_result_screen.dart';

/// The placement run: an unranked player card carrying the "2 / 4" progress,
/// the four bot slots as list rows (result square, "à jouer" or a lock), the
/// single primary button that starts (or resumes) the next match, and the
/// rules of the run as a quiet caption card.
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
      final provider = context.read<PlacementProvider>();
      provider.loadStatus();
      provider.loadActiveMatch();
    });
  }

  static String _rankForWins(int wins) {
    switch (wins) {
      case 0: return 'bronze';
      case 1: return 'silver';
      case 2: return 'silver';
      case 3: return 'gold';
      case 4: return 'platinum';
      default: return 'bronze';
    }
  }

  // Mirrors the backend's RANK_ASSIGNMENT (PlacementService) — preview only,
  // the server is authoritative.
  static int _eloForWins(int wins) {
    switch (wins) {
      case 0: return 500;
      case 1: return 800;
      case 2: return 1000;
      case 3: return 1300;
      case 4: return 1700;
      default: return 500;
    }
  }

  /// The four opponents of the run, in order: rank key (for the localized
  /// name) and the three-dart average the bot throws.
  static const List<({String rank, int avg})> _botConfigs = [
    (rank: 'bronze', avg: 20),
    (rank: 'silver', avg: 30),
    (rank: 'gold', avg: 40),
    (rank: 'platinum', avg: 55),
  ];

  Future<void> _startNextMatch() async {
    final provider = context.read<PlacementProvider>();
    final success = await provider.startMatch();
    if (success && mounted) {
      await _runMatchAndHandleResult(provider);
    }
  }

  Future<void> _resumeActiveMatch() async {
    final provider = context.read<PlacementProvider>();
    final active = provider.activeMatch;
    if (active == null) return;
    provider.resumeFromActiveMatch(active);
    await _runMatchAndHandleResult(provider);
  }

  Future<void> _runMatchAndHandleResult(PlacementProvider provider) async {
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (context) => const PlacementCameraSetupScreen(),
      ),
    );
    if (!mounted) return;
    await provider.loadStatus();
    await provider.loadActiveMatch();
    final isComplete = provider.status?.isComplete == true;
    if (isComplete && mounted) {
      final assignedRank = (result?['assignedRank'] as String?) ?? _rankForWins(provider.status?.wins ?? 0);
      final assignedElo = result?['assignedElo'] as int? ?? _eloForWins(provider.status?.wins ?? 0);
      AppNavigator.replaceWith(
        context,
        PlacementResultScreen(
          assignedRank: assignedRank,
          assignedElo: assignedElo,
          wins: provider.status?.wins ?? 0,
          totalMatches: 4,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: Text(l10n.placementMatches)),
      body: Consumer<PlacementProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading && provider.status == null) {
            return const Center(
              child: CircularProgressIndicator(color: AppTheme.primary),
            );
          }

          if (provider.error != null && provider.status == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: DsCard(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline_rounded,
                          color: AppTheme.error, size: 28),
                      const SizedBox(height: 12),
                      Text(
                        provider.error!,
                        textAlign: TextAlign.center,
                        style: AppTheme.caption,
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () => provider.loadStatus(),
                          child: Text(dsSentence(l10n.retry)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          final status = provider.status;
          if (status == null) {
            return const Center(
              child: CircularProgressIndicator(color: AppTheme.primary),
            );
          }

          return Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildProgressCard(status, l10n),
                      const SizedBox(height: 28),
                      DsSectionHeader(title: l10n.placementMatches),
                      const SizedBox(height: 10),
                      ...List.generate(4, (index) {
                        final matchNumber = index + 1;
                        final config = _botConfigs[index];
                        final result = status.results.length > index
                            ? status.results[index]
                            : null;
                        final isNext =
                            matchNumber == (status.nextMatchNumber ?? 5);
                        final isLocked =
                            matchNumber > (status.nextMatchNumber ?? 5);

                        return Padding(
                          padding: EdgeInsets.only(top: index == 0 ? 0 : 10),
                          child: _buildBotRow(
                            config: config,
                            matchNumber: matchNumber,
                            result: result,
                            isNext: isNext,
                            isLocked: isLocked,
                            l10n: l10n,
                          ),
                        );
                      }),
                      const SizedBox(height: 14),
                      // How the run works — a quiet caption block, never a
                      // second filled panel.
                      DsCard(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          l10n.placementDescription,
                          style: AppTheme.caption.copyWith(height: 1.5),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
              // The one filled block of the screen: start or resume.
              if (!status.isComplete && status.nextMatchNumber != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: SizedBox(
                    height: 56,
                    child: ElevatedButton(
                      onPressed: provider.isLoading
                          ? null
                          : (provider.activeMatch != null
                              ? _resumeActiveMatch
                              : _startNextMatch),
                      child: provider.isLoading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2.5),
                            )
                          : Text(
                              provider.activeMatch != null
                                  ? l10n.placementHubResumeMatch(
                                      provider.activeMatch!.botName)
                                  : l10n.placementHubPlayMatch(
                                      status.nextMatchNumber!),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  /// The player card of the run: the unranked badge, "Non classé", the
  /// "2 / 4" hero number and the 3 px progress hairline.
  Widget _buildProgressCard(PlacementStatus status, AppLocalizations l10n) {
    return DsCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              RankUtils.getRankBadge('unranked', size: 72),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.unranked,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.titleLarge.copyWith(height: 1.1),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      status.wins > 0
                          ? '${status.wins} ${status.wins == 1 ? l10n.winSingular : l10n.winsPlural}'
                          : l10n.completePlacementToUnlock,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.caption.copyWith(
                        color: status.wins > 0
                            ? AppTheme.success
                            : AppTheme.textSecondary,
                        fontWeight:
                            status.wins > 0 ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${status.matchesPlayed} / 4',
                      style: AppTheme.displayLarge),
                  const SizedBox(height: 3),
                  Text(
                    l10n.matchesCompleted.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.3,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          DsProgressBar(value: status.matchesPlayed / 4),
        ],
      ),
    );
  }

  /// One slot of the run, 56 px: the match number, the bot and its average,
  /// then the verdict — result square, "à jouer", or a lock.
  Widget _buildBotRow({
    required ({String rank, int avg}) config,
    required int matchNumber,
    PlacementResult? result,
    required bool isNext,
    required bool isLocked,
    required AppLocalizations l10n,
  }) {
    final botName =
        l10n.placementHubBotName(RankTranslation.translate(l10n, config.rank));
    final muted = isLocked ? AppTheme.textTertiary : AppTheme.textPrimary;

    return SizedBox(
      height: 56,
      child: DsCard(
        radius: AppTheme.radiusRow,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        side: BorderSide(
          color: isNext
              ? AppTheme.primaryLight.withValues(alpha: 0.45)
              : AppTheme.border,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              child: Text(
                '$matchNumber',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textTertiary,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    botName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.rowTitle.copyWith(color: muted),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    l10n.placementHubBotAverage(config.avg),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.caption,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            if (result != null)
              DsResultSquare(
                won: result.won,
                letter: result.won ? l10n.formWinLetter : l10n.formLossLetter,
                size: 28,
              )
            else if (isNext)
              Text(
                l10n.placementHubToPlay,
                style: AppTheme.caption.copyWith(
                  color: AppTheme.primaryLight,
                  fontWeight: FontWeight.w700,
                ),
              )
            else
              const Icon(Icons.lock_outline_rounded,
                  size: 18, color: AppTheme.textTertiary),
          ],
        ),
      ),
    );
  }
}
