import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/cricket.dart';
import '../utils/app_theme.dart';

/// Score / no-score cricket variant picker: a two-way pill segment with the
/// selected variant's one-line rule under it. Shared by the bot and local
/// match setup screens; only the score-mode rule differs between them (who
/// the "opponent" is), so the caller supplies [scoreHint].
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
        onTap: () => onChanged(mode),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? AppTheme.success.withValues(alpha: 0.22)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? Colors.white : AppTheme.textSecondary,
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
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppTheme.success.withValues(alpha: 0.35),
            ),
          ),
          child: Row(
            children: [
              _option(CricketScoreMode.score, l10n.cricketScoreLabel),
              const SizedBox(width: 6),
              _option(CricketScoreMode.noScore, l10n.cricketNoScoreLabel),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value == CricketScoreMode.score ? scoreHint : l10n.cricketNoScoreHint,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
        ),
      ],
    );
  }
}
