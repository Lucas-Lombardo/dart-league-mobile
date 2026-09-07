import 'package:flutter/material.dart';
import '../../utils/app_navigator.dart';
import '../../utils/app_theme.dart';
import '../../utils/rank_translation.dart';
import '../../utils/rank_utils.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/design_system.dart';

/// End of the placement run: the result disc, "Placement terminé", the won /
/// played line, then one card with the assigned badge, "Tu commences en Or"
/// and the starting ELO — and the single primary button into ranked play.
class PlacementResultScreen extends StatefulWidget {
  final String assignedRank;
  final int assignedElo;
  final int wins;
  final int totalMatches;

  const PlacementResultScreen({
    super.key,
    required this.assignedRank,
    required this.assignedElo,
    required this.wins,
    required this.totalMatches,
  });

  @override
  State<PlacementResultScreen> createState() => _PlacementResultScreenState();
}

class _PlacementResultScreenState extends State<PlacementResultScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _scaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.6, curve: Curves.elasticOut),
      ),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.4, 1.0, curve: Curves.easeIn),
      ),
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final rankLabel = RankTranslation.translate(l10n, widget.assignedRank);

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 40, 16, 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight - 64),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    children: [
                      ScaleTransition(
                        scale: _scaleAnimation,
                        child: Container(
                          width: 88,
                          height: 88,
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppTheme.primary.withValues(alpha: 0.6),
                              width: 2,
                            ),
                          ),
                          child: const Icon(
                            Icons.check_rounded,
                            color: AppTheme.primaryLight,
                            size: 38,
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      FadeTransition(
                        opacity: _fadeAnimation,
                        child: Column(
                          children: [
                            Text(
                              dsSentence(l10n.placementComplete),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: AppTheme.textPrimary,
                                fontSize: 32,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.7,
                                height: 1.05,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${l10n.youWonOutOf} ${widget.wins} / ${widget.totalMatches}',
                              textAlign: TextAlign.center,
                              style: AppTheme.caption.copyWith(fontSize: 14),
                            ),
                            const SizedBox(height: 18),
                            SizedBox(
                              width: double.infinity,
                              child: _buildRankCard(l10n, rankLabel),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: Column(
                      children: [
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton(
                            onPressed: () => AppNavigator.toHomeClearing(context),
                            child: Text(dsSentence(l10n.startPlayingRanked)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The verdict card: the 96 px badge, "Tu commences en Or" and the starting
  /// ELO as the hero number.
  Widget _buildRankCard(AppLocalizations l10n, String rankLabel) {
    return DsCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          RankUtils.getRankBadge(widget.assignedRank, size: 96),
          const SizedBox(height: 14),
          Text(
            l10n.placementResultStartsIn(rankLabel),
            textAlign: TextAlign.center,
            style: AppTheme.rowTitle,
          ),
          const SizedBox(height: 18),
          Text('${widget.assignedElo}', style: AppTheme.displayLarge),
          const SizedBox(height: 5),
          Text(
            l10n.startingElo.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}
