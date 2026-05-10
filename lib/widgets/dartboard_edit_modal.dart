import 'package:flutter/material.dart';
import '../providers/game_provider.dart' show ScoreMultiplier;
import '../services/dart_scoring_service.dart';
import '../utils/app_theme.dart';
import '../utils/haptic_service.dart';
import '../utils/dart_sound_service.dart';

/// Shows a modal bottom sheet for correcting a dart score.
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

class _DartEditSheet extends StatefulWidget {
  final int dartIndex;
  final DartScore? currentScore;

  const _DartEditSheet({
    required this.dartIndex,
    this.currentScore,
  });

  @override
  State<_DartEditSheet> createState() => _DartEditSheetState();
}

class _DartEditSheetState extends State<_DartEditSheet> {
  ScoreMultiplier _multiplier = ScoreMultiplier.single;

  void _submit(int baseScore, ScoreMultiplier multiplier) {
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

  void _submitMiss() {
    HapticService.mediumImpact();
    DartSoundService.playDartHit(0, ScoreMultiplier.single);
    Navigator.pop(context, DartScore(
      score: 0, segment: 0, ring: 'miss', radius: 2.0, angle: 0,
    ));
  }

  void _setMultiplier(ScoreMultiplier m) {
    HapticService.lightImpact();
    setState(() => _multiplier = m);
  }

  Color get _multiplierColor => switch (_multiplier) {
        ScoreMultiplier.single => Colors.white,
        ScoreMultiplier.double => AppTheme.success,
        ScoreMultiplier.triple => AppTheme.error,
      };

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
              width: 48,
              height: 5,
              decoration: BoxDecoration(
                color: AppTheme.textSecondary.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(3),
              ),
            ),

            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
              child: Row(
                children: [
                  const Icon(Icons.edit, color: AppTheme.primary, size: 24),
                  const SizedBox(width: 10),
                  Text(
                    'Edit Dart ${widget.dartIndex + 1}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (widget.currentScore != null) ...[
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceLight,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        widget.currentScore!.formatted,
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: AppTheme.textSecondary, size: 26),
                  ),
                ],
              ),
            ),

            const Divider(color: AppTheme.surfaceLight, height: 1),

            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Column(
                children: [
                  _buildSpecialRow(),
                  const SizedBox(height: 12),
                  _buildMultiplierSelector(),
                  const SizedBox(height: 12),
                  _buildNumberGrid(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSpecialRow() {
    return Row(
      children: [
        Expanded(
          child: _BigButton(
            label: 'MISS',
            color: AppTheme.error,
            onTap: _submitMiss,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _BigButton(
            label: 'S-BULL',
            subtitle: '25',
            color: AppTheme.accent,
            onTap: () => _submit(25, ScoreMultiplier.single),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _BigButton(
            label: 'D-BULL',
            subtitle: '50',
            color: AppTheme.success,
            onTap: () => _submit(25, ScoreMultiplier.double),
          ),
        ),
      ],
    );
  }

  Widget _buildMultiplierSelector() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          _multiplierTab(ScoreMultiplier.single, 'SINGLE', '×1', Colors.white),
          _multiplierTab(ScoreMultiplier.double, 'DOUBLE', '×2', AppTheme.success),
          _multiplierTab(ScoreMultiplier.triple, 'TRIPLE', '×3', AppTheme.error),
        ],
      ),
    );
  }

  Widget _multiplierTab(ScoreMultiplier value, String label, String mult, Color color) {
    final selected = _multiplier == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => _setMultiplier(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.18) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? color.withValues(alpha: 0.6) : Colors.transparent,
              width: 2,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: selected ? color : AppTheme.textSecondary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                mult,
                style: TextStyle(
                  color: selected
                      ? color.withValues(alpha: 0.8)
                      : AppTheme.textSecondary.withValues(alpha: 0.7),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNumberGrid() {
    const numbers = [
      [20, 19, 18, 17, 16],
      [15, 14, 13, 12, 11],
      [10, 9, 8, 7, 6],
      [5, 4, 3, 2, 1],
    ];
    final color = _multiplierColor;
    return Column(
      children: numbers
          .map((row) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: row
                      .map((n) => Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: _NumberButton(
                                number: n,
                                multiplier: _multiplier,
                                color: color,
                                onTap: () => _submit(n, _multiplier),
                              ),
                            ),
                          ))
                      .toList(),
                ),
              ))
          .toList(),
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

class _BigButton extends StatelessWidget {
  final String label;
  final String? subtitle;
  final Color color;
  final VoidCallback onTap;

  const _BigButton({
    required this.label,
    this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.5), width: 2),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      color: color.withValues(alpha: 0.8),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NumberButton extends StatelessWidget {
  final int number;
  final ScoreMultiplier multiplier;
  final Color color;
  final VoidCallback onTap;

  const _NumberButton({
    required this.number,
    required this.multiplier,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isSingle = multiplier == ScoreMultiplier.single;
    final score = switch (multiplier) {
      ScoreMultiplier.single => number,
      ScoreMultiplier.double => number * 2,
      ScoreMultiplier.triple => number * 3,
    };
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 64,
          decoration: BoxDecoration(
            color: isSingle
                ? AppTheme.surfaceLight.withValues(alpha: 0.4)
                : color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSingle
                  ? AppTheme.surfaceLight
                  : color.withValues(alpha: 0.5),
              width: 1.5,
            ),
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$number',
                  style: TextStyle(
                    color: color,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    height: 1,
                  ),
                ),
                if (!isSingle) ...[
                  const SizedBox(height: 2),
                  Text(
                    '=$score',
                    style: TextStyle(
                      color: color.withValues(alpha: 0.7),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      height: 1,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
