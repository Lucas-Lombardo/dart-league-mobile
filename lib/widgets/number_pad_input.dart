import 'package:flutter/material.dart';
import '../providers/game_provider.dart' show ScoreMultiplier;
import '../utils/app_theme.dart';
import '../utils/haptic_service.dart';
import '../utils/dart_sound_service.dart';
import '../l10n/app_localizations.dart';
import 'design_system.dart';

/// Number pad for dart score input, replacing the interactive dartboard.
/// Much easier to use on small phones.
///
/// System D: a segmented S / D / T control, then quiet 56 px surface keys
/// (20 / 700 digits, r14) — no coloured keys. The two action keys are the
/// miss (quiet, secondary icon) and the bull (the one primary key).
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

  void _select(ScoreMultiplier m) {
    if (m == _selectedMultiplier) return;
    HapticService.lightImpact();
    setState(() => _selectedMultiplier = m);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        return Column(
          children: [
            // Multiplier selector
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
              child: _Segmented(
                options: [
                  (ScoreMultiplier.single, dsSentence(l10n.singleUpper)),
                  (ScoreMultiplier.double, dsSentence(l10n.doubleUpper)),
                  (ScoreMultiplier.triple, dsSentence(l10n.tripleUpper)),
                ],
                value: _selectedMultiplier,
                onChanged: _select,
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
    final l10n = AppLocalizations.of(context);

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
        // Bottom row: BULL (the one primary key) + MISS (quiet)
        Expanded(
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: _ActionKey(
                  label: dsSentence(
                    _selectedMultiplier == ScoreMultiplier.double
                        ? l10n.bull50
                        : l10n.bull25,
                  ),
                  primary: true,
                  onTap: _submitBull,
                ),
              ),
              Expanded(
                flex: 2,
                child: _ActionKey(
                  label: dsSentence(l10n.missButton),
                  icon: Icons.close_rounded,
                  onTap: _submitMiss,
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

/// Surface track with a hairline; the active option sits on surfaceLight.
class _Segmented extends StatelessWidget {
  final List<(ScoreMultiplier, String)> options;
  final ScoreMultiplier value;
  final ValueChanged<ScoreMultiplier> onChanged;

  const _Segmented({
    required this.options,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          for (final (mode, label) in options)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(mode),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: value == mode ? AppTheme.surfaceLight : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      color: value == mode ? AppTheme.textPrimary : AppTheme.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
        ],
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
      padding: const EdgeInsets.all(3),
      child: DsCard(
        radius: AppTheme.radiusControl,
        padding: EdgeInsets.zero,
        onTap: onTap,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$prefix$number',
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  height: 1,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              if (multiplier != ScoreMultiplier.single) ...[
                const SizedBox(height: 3),
                Text(
                  '= $displayScore',
                  style: AppTheme.caption.copyWith(
                    fontSize: 10,
                    height: 1,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Bull (primary filled) or miss (quiet surface key with a secondary icon).
class _ActionKey extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool primary;
  final VoidCallback onTap;

  const _ActionKey({
    required this.label,
    this.icon,
    this.primary = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = primary ? Colors.white : AppTheme.textSecondary;
    final text = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: fg,
        fontSize: 15,
        fontWeight: FontWeight.w700,
        height: 1,
      ),
    );
    return Padding(
      padding: const EdgeInsets.all(3),
      child: DsCard(
        radius: AppTheme.radiusControl,
        padding: EdgeInsets.zero,
        color: primary ? AppTheme.primary : AppTheme.surface,
        side: primary ? BorderSide.none : null,
        onTap: onTap,
        child: Center(
          child: icon == null
              ? text
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 18, color: fg),
                    const SizedBox(width: 6),
                    Flexible(child: text),
                  ],
                ),
        ),
      ),
    );
  }
}
