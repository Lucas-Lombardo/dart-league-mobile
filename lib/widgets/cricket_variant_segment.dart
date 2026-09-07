import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/cricket.dart';
import '../utils/app_theme.dart';
import '../utils/haptic_service.dart';

/// Score / no-score cricket variant picker: the system's segmented control
/// (surface track, hairline, the active option on surfaceLight in 13 / 700)
/// with the selected variant's one-line rule under it. Shared by the bot and
/// local match setup screens; only the score-mode rule differs between them
/// (who the "opponent" is), so the caller supplies [scoreHint].
class CricketVariantSegment extends StatelessWidget {
  final CricketScoreMode value;
  final ValueChanged<CricketScoreMode> onChanged;

  /// Rule line shown when [value] is [CricketScoreMode.score].
  final String scoreHint;

  const CricketVariantSegment({
    super.key,
    required this.value,
    required this.onChanged,
    required this.scoreHint,
  });

  Widget _option(CricketScoreMode mode, String label) {
    final selected = value == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          if (selected) return;
          HapticService.lightImpact();
          onChanged(mode);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppTheme.surfaceLight : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? AppTheme.textPrimary : AppTheme.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.border),
          ),
          child: Row(
            children: [
              _option(CricketScoreMode.score, l10n.cricketScoreLabel),
              const SizedBox(width: 4),
              _option(CricketScoreMode.noScore, l10n.cricketNoScoreLabel),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          value == CricketScoreMode.score ? scoreHint : l10n.cricketNoScoreHint,
          textAlign: TextAlign.center,
          style: AppTheme.caption,
        ),
      ],
    );
  }
}
