import 'package:flutter/material.dart';
import '../providers/game_provider.dart' show ScoreMultiplier;
import '../services/dart_scoring_service.dart';
import '../utils/app_theme.dart';
import '../utils/haptic_service.dart';
import '../utils/dart_sound_service.dart';

/// Shows a modal bottom sheet with a flat grid for correcting a dart score.
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
    builder: (context) => _DartEditSheet(
      dartIndex: dartIndex,
      currentScore: currentScore,
    ),
  );
}

class _DartEditSheet extends StatelessWidget {
  final int dartIndex;
  final DartScore? currentScore;

  const _DartEditSheet({
    required this.dartIndex,
    this.currentScore,
  });

  void _submit(BuildContext context, int baseScore, ScoreMultiplier multiplier) {
    HapticService.mediumImpact();
    DartSoundService.playDartHit(baseScore, multiplier);
    final ring = _multiplierToRing(baseScore, multiplier);
    final score = _computeScore(baseScore, multiplier);
    Navigator.pop(context, DartScore(
      score: score,
      segment: baseScore == 25 ? 0 : baseScore,
      ring: ring,
      radius: 0,
      angle: 0,
    ));
  }

  void _submitMiss(BuildContext context) {
    HapticService.mediumImpact();
    DartSoundService.playDartHit(0, ScoreMultiplier.single);
    Navigator.pop(context, DartScore(
      score: 0, segment: 0, ring: 'miss', radius: 2.0, angle: 0,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
              child: Row(
                children: [
                  const Icon(Icons.edit, color: AppTheme.primary, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Edit Dart ${dartIndex + 1}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (currentScore != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      '(${currentScore!.formatted})',
                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                    ),
                  ],
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: AppTheme.textSecondary, size: 20),
                  ),
                ],
              ),
            ),

            const Divider(color: AppTheme.surfaceLight, height: 1),

            // Flat grid
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
              child: _buildFlatGrid(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFlatGrid(BuildContext context) {
    const topRow = [20, 19, 18, 17, 16, 15, 14, 13, 12, 11];
    const bottomRow = [10, 9, 8, 7, 6, 5, 4, 3, 2, 1];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Special row: MISS, S-BULL, D-BULL
        _buildSpecialRow(context),
        const SizedBox(height: 4),

        // Singles
        _buildNumberRow(context, topRow, ScoreMultiplier.single),
        _buildNumberRow(context, bottomRow, ScoreMultiplier.single),
        const SizedBox(height: 4),

        // Doubles
        _buildNumberRow(context, topRow, ScoreMultiplier.double),
        _buildNumberRow(context, bottomRow, ScoreMultiplier.double),
        const SizedBox(height: 4),

        // Triples
        _buildNumberRow(context, topRow, ScoreMultiplier.triple),
        _buildNumberRow(context, bottomRow, ScoreMultiplier.triple),
      ],
    );
  }

  Widget _buildSpecialRow(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: _GridCell(
            label: 'MISS',
            color: AppTheme.error,
            onTap: () => _submitMiss(context),
          ),
        ),
        Expanded(
          flex: 2,
          child: _GridCell(
            label: 'S-BULL',
            subtitle: '25',
            color: AppTheme.accent,
            onTap: () => _submit(context, 25, ScoreMultiplier.single),
          ),
        ),
        Expanded(
          flex: 2,
          child: _GridCell(
            label: 'D-BULL',
            subtitle: '50',
            color: AppTheme.success,
            onTap: () => _submit(context, 25, ScoreMultiplier.double),
          ),
        ),
      ],
    );
  }

  Widget _buildNumberRow(BuildContext context, List<int> numbers, ScoreMultiplier multiplier) {
    final prefix = switch (multiplier) {
      ScoreMultiplier.single => '',
      ScoreMultiplier.double => '',
      ScoreMultiplier.triple => '',
    };
    final dotCount = switch (multiplier) {
      ScoreMultiplier.single => 0,
      ScoreMultiplier.double => 2,
      ScoreMultiplier.triple => 3,
    };
    final color = switch (multiplier) {
      ScoreMultiplier.single => Colors.white,
      ScoreMultiplier.double => AppTheme.success,
      ScoreMultiplier.triple => AppTheme.error,
    };
    final bgAlpha = switch (multiplier) {
      ScoreMultiplier.single => 0.0,
      ScoreMultiplier.double => 0.08,
      ScoreMultiplier.triple => 0.08,
    };

    return Row(
      children: numbers.map((n) => Expanded(
        child: _NumberCell(
          number: n,
          prefix: prefix,
          dotCount: dotCount,
          textColor: color,
          bgAlpha: bgAlpha,
          onTap: () => _submit(context, n, multiplier),
        ),
      )).toList(),
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

class _GridCell extends StatelessWidget {
  final String label;
  final String? subtitle;
  final Color color;
  final VoidCallback onTap;

  const _GridCell({
    required this.label,
    this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withValues(alpha: 0.3)),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: color,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: TextStyle(
                        color: color.withValues(alpha: 0.7),
                        fontSize: 10,
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
}

class _NumberCell extends StatelessWidget {
  final int number;
  final String prefix;
  final int dotCount;
  final Color textColor;
  final double bgAlpha;
  final VoidCallback onTap;

  const _NumberCell({
    required this.number,
    required this.prefix,
    required this.dotCount,
    required this.textColor,
    required this.bgAlpha,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(1),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: bgAlpha > 0
                  ? textColor.withValues(alpha: bgAlpha)
                  : AppTheme.surface,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: AppTheme.surfaceLight.withValues(alpha: 0.5),
              ),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$prefix$number',
                    style: TextStyle(
                      color: textColor,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (dotCount > 0)
                    Text(
                      '·' * dotCount,
                      style: TextStyle(
                        color: textColor.withValues(alpha: 0.7),
                        fontSize: 10,
                        height: 0.8,
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
}
