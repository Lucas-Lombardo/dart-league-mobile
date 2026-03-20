import 'package:flutter/material.dart';
import '../providers/game_provider.dart' show ScoreMultiplier;
import '../utils/app_theme.dart';
import '../utils/haptic_service.dart';
import '../utils/dart_sound_service.dart';

/// Number pad for dart score input, replacing the interactive dartboard.
/// Much easier to use on small phones.
class NumberPadInput extends StatefulWidget {
  final Function(int score, ScoreMultiplier multiplier) onDartThrow;
  final ScoreMultiplier initialMultiplier;

  const NumberPadInput({
    super.key,
    required this.onDartThrow,
    this.initialMultiplier = ScoreMultiplier.single,
  });

  @override
  State<NumberPadInput> createState() => _NumberPadInputState();
}

class _NumberPadInputState extends State<NumberPadInput> {
  late ScoreMultiplier _selectedMultiplier = widget.initialMultiplier;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Column(
          children: [
            // Multiplier selector
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
              child: Row(
                children: [
                  _MultiplierButton(
                    label: 'SINGLE',
                    shortLabel: 'S',
                    isSelected: _selectedMultiplier == ScoreMultiplier.single,
                    color: AppTheme.textSecondary,
                    onTap: () => setState(() => _selectedMultiplier = ScoreMultiplier.single),
                  ),
                  const SizedBox(width: 6),
                  _MultiplierButton(
                    label: 'DOUBLE',
                    shortLabel: 'D',
                    isSelected: _selectedMultiplier == ScoreMultiplier.double,
                    color: AppTheme.success,
                    onTap: () => setState(() => _selectedMultiplier = ScoreMultiplier.double),
                  ),
                  const SizedBox(width: 6),
                  _MultiplierButton(
                    label: 'TRIPLE',
                    shortLabel: 'T',
                    isSelected: _selectedMultiplier == ScoreMultiplier.triple,
                    color: AppTheme.error,
                    onTap: () => setState(() => _selectedMultiplier = ScoreMultiplier.triple),
                  ),
                ],
              ),
            ),
            // Number grid
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
                child: _buildNumberGrid(),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildNumberGrid() {
    // Layout: 4 rows of 5 numbers + bottom row with BULL and MISS
    const rows = [
      [1, 2, 3, 4, 5],
      [6, 7, 8, 9, 10],
      [11, 12, 13, 14, 15],
      [16, 17, 18, 19, 20],
    ];

    return Column(
      children: [
        ...rows.map((row) => Expanded(
          child: Row(
            children: row.map((number) => Expanded(
              child: _NumberButton(
                number: number,
                multiplier: _selectedMultiplier,
                onTap: () => _submitScore(number),
              ),
            )).toList(),
          ),
        )),
        // Bottom row: BULL + MISS
        Expanded(
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: _SpecialButton(
                  label: _selectedMultiplier == ScoreMultiplier.double ? 'BULL (50)' : 'BULL (25)',
                  color: _selectedMultiplier == ScoreMultiplier.double ? AppTheme.success : AppTheme.accent,
                  onTap: () => _submitBull(),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                flex: 2,
                child: _SpecialButton(
                  label: 'MISS',
                  color: AppTheme.surfaceLight,
                  onTap: () => _submitMiss(),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _submitScore(int number) {
    // Triple 25 is not valid
    if (number == 25 && _selectedMultiplier == ScoreMultiplier.triple) return;
    HapticService.mediumImpact();
    DartSoundService.playDartHit(number, _selectedMultiplier);
    widget.onDartThrow(number, _selectedMultiplier);
  }

  void _submitBull() {
    // Bull is always single (25) or double (50), ignore triple
    final multiplier = _selectedMultiplier == ScoreMultiplier.triple
        ? ScoreMultiplier.single
        : _selectedMultiplier;
    HapticService.mediumImpact();
    DartSoundService.playDartHit(25, multiplier);
    widget.onDartThrow(25, multiplier);
  }

  void _submitMiss() {
    HapticService.mediumImpact();
    DartSoundService.playDartHit(0, ScoreMultiplier.single);
    widget.onDartThrow(0, ScoreMultiplier.single);
  }
}

class _MultiplierButton extends StatelessWidget {
  final String label;
  final String shortLabel;
  final bool isSelected;
  final Color color;
  final VoidCallback onTap;

  const _MultiplierButton({
    required this.label,
    required this.shortLabel,
    required this.isSelected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: isSelected ? color.withValues(alpha: 0.2) : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected ? color : AppTheme.surfaceLight,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  color: isSelected ? color : AppTheme.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
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
  final VoidCallback onTap;

  const _NumberButton({
    required this.number,
    required this.multiplier,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final displayScore = switch (multiplier) {
      ScoreMultiplier.single => number,
      ScoreMultiplier.double => number * 2,
      ScoreMultiplier.triple => number * 3,
    };
    final prefix = switch (multiplier) {
      ScoreMultiplier.single => '',
      ScoreMultiplier.double => 'D',
      ScoreMultiplier.triple => 'T',
    };

    return Padding(
      padding: const EdgeInsets.all(2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(8),
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
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (multiplier != ScoreMultiplier.single)
                    Text(
                      '=$displayScore',
                      style: TextStyle(
                        color: multiplier == ScoreMultiplier.double
                            ? AppTheme.success.withValues(alpha: 0.7)
                            : AppTheme.error.withValues(alpha: 0.7),
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
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

class _SpecialButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _SpecialButton({
    required this.label,
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
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withValues(alpha: 0.5)),
            ),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  color: color == AppTheme.surfaceLight ? AppTheme.textSecondary : color,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
