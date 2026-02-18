import 'package:flutter/material.dart';
import '../providers/game_provider.dart' show ScoreMultiplier;
import '../services/dart_scoring_service.dart';
import '../utils/app_theme.dart';
import '../utils/haptic_service.dart';
import 'interactive_dartboard.dart';

/// Shows a modal bottom sheet containing the interactive dartboard
/// for manually correcting a dart score.
///
/// Returns the selected [DartScore] or null if dismissed.
Future<DartScore?> showDartboardEditModal(
  BuildContext context, {
  required int dartIndex,
  DartScore? currentScore,
}) {
  return showModalBottomSheet<DartScore>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _DartboardEditSheet(
      dartIndex: dartIndex,
      currentScore: currentScore,
    ),
  );
}

class _DartboardEditSheet extends StatelessWidget {
  final int dartIndex;
  final DartScore? currentScore;

  const _DartboardEditSheet({
    required this.dartIndex,
    this.currentScore,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: Column(
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppTheme.textSecondary.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.edit,
                    color: AppTheme.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Edit Dart ${dartIndex + 1}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (currentScore != null)
                        Text(
                          'Current: ${currentScore!.formatted}',
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                    ],
                  ),
                ),
                // Miss button
                _MissButton(
                  onTap: () {
                    HapticService.mediumImpact();
                    final miss = DartScore(
                      score: 0,
                      segment: 0,
                      ring: 'miss',
                      radius: 2.0,
                      angle: 0,
                    );
                    Navigator.pop(context, miss);
                  },
                ),
                const SizedBox(width: 8),
                // Close button
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),

          const Divider(color: AppTheme.surfaceLight, height: 1),

          // Interactive Dartboard
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: InteractiveDartboard(
                onDartThrow: (baseScore, multiplier) {
                  // Convert dartboard tap to DartScore and return
                  final ring = _multiplierToRing(baseScore, multiplier);
                  final score = _computeScore(baseScore, multiplier);
                  final dartScore = DartScore(
                    score: score,
                    segment: baseScore == 25 ? 0 : baseScore,
                    ring: ring,
                    radius: 0,
                    angle: 0,
                  );
                  Navigator.pop(context, dartScore);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _multiplierToRing(int baseScore, ScoreMultiplier multiplier) {
    if (baseScore == 25) {
      return multiplier == ScoreMultiplier.double ? 'double_bull' : 'single_bull';
    }
    if (baseScore == 0) return 'miss';
    switch (multiplier) {
      case ScoreMultiplier.triple:
        return 'triple';
      case ScoreMultiplier.double:
        return 'double';
      case ScoreMultiplier.single:
        return 'inner_single';
    }
  }

  static int _computeScore(int baseScore, ScoreMultiplier multiplier) {
    if (baseScore == 25) {
      return multiplier == ScoreMultiplier.double ? 50 : 25;
    }
    switch (multiplier) {
      case ScoreMultiplier.triple:
        return baseScore * 3;
      case ScoreMultiplier.double:
        return baseScore * 2;
      case ScoreMultiplier.single:
        return baseScore;
    }
  }
}

class _MissButton extends StatelessWidget {
  final VoidCallback onTap;

  const _MissButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: AppTheme.error.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: AppTheme.error.withValues(alpha: 0.3),
            ),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.close, color: AppTheme.error, size: 16),
              SizedBox(width: 4),
              Text(
                'MISS',
                style: TextStyle(
                  color: AppTheme.error,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
