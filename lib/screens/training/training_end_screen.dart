import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../../models/training.dart';
import '../../utils/app_navigator.dart';
import '../../utils/app_theme.dart';
import '../../utils/haptic_service.dart';
import '../../widgets/design_system.dart';
import 'training_select_screen.dart';

/// End screen shown after a training run. Submits the result to the backend
/// and displays the outcome.
class TrainingEndScreen extends StatelessWidget {
  final TrainingType type;
  final int score;
  final int dartsThrown;
  final bool completed;
  final String scoreLabel;
  final String? subtitle;
  final bool isSubmitting;
  final String? submitError;
  final VoidCallback onPlayAgain;
  final VoidCallback? onRetrySubmit;

  /// False for quiz trainings (no dart is thrown) — hides the darts row.
  final bool showDartsThrown;

  /// When the drill has a ceiling (e.g. 60 darts), shown as "/ 60" next to
  /// the hero number.
  final int? maxScore;

  const TrainingEndScreen({
    super.key,
    required this.type,
    required this.score,
    required this.dartsThrown,
    required this.completed,
    required this.scoreLabel,
    required this.onPlayAgain,
    this.subtitle,
    this.isSubmitting = false,
    this.submitError,
    this.onRetrySubmit,
    this.showDartsThrown = true,
    this.maxScore,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final title = trainingDisplayName(l10n, type);
    return PopScope(
      canPop: !isSubmitting,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 72, 24, 16),
                  child: Column(
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppTheme.success.withValues(alpha: 0.12),
                          border: Border.all(
                            color: AppTheme.success.withValues(alpha: 0.6),
                            width: 2,
                          ),
                        ),
                        child: const Icon(
                          Icons.check_rounded,
                          color: AppTheme.success,
                          size: 32,
                        ),
                      ),
                      const SizedBox(height: 22),
                      Text(
                        dsSentence(l10n.trainingComplete),
                        style: AppTheme.displayMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        title,
                        style: AppTheme.bodyLarge,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 28),
                      SizedBox(
                        width: double.infinity,
                        child: DsCard(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            children: [
                              Text(
                                scoreLabel.toUpperCase(),
                                style: AppTheme.labelSmall,
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                              _heroNumber(),
                              if (showDartsThrown) ...[
                                const SizedBox(height: 8),
                                Text(
                                  '${l10n.trainingDartsThrown}: $dartsThrown',
                                  style: AppTheme.caption.copyWith(
                                    fontSize: 13,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                              if (subtitle != null) ...[
                                const SizedBox(height: 6),
                                Text(
                                  subtitle!,
                                  style: AppTheme.caption.copyWith(
                                    fontSize: 13,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                              if (!completed) ...[
                                const SizedBox(height: 10),
                                Text(
                                  l10n.trainingIncomplete,
                                  style: AppTheme.caption.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                              const SizedBox(height: 12),
                              _saveStatus(l10n),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        onPressed: isSubmitting
                            ? null
                            : () {
                                HapticService.mediumImpact();
                                onPlayAgain();
                              },
                        icon: const Icon(Icons.replay_rounded, size: 20),
                        label: Text(l10n.trainingPlayAgain),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: OutlinedButton(
                        onPressed: isSubmitting
                            ? null
                            : () {
                                HapticService.lightImpact();
                                AppNavigator.toHomeClearing(context);
                              },
                        child: Text(l10n.backToHome),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 56 / 800 tabular score, with the optional "/ max" on its baseline.
  Widget _heroNumber() {
    const hero = TextStyle(
      color: AppTheme.textPrimary,
      fontSize: 56,
      fontWeight: FontWeight.w800,
      letterSpacing: -1.5,
      height: 1,
      fontFeatures: [FontFeature.tabularFigures()],
    );
    if (maxScore == null) return Text('$score', style: hero);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text('$score', style: hero),
        const SizedBox(width: 8),
        Text(
          '/ $maxScore',
          style: const TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  /// Saving → error (+ retry) → saved, all on one quiet line.
  Widget _saveStatus(AppLocalizations l10n) {
    if (isSubmitting) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(width: 8),
          Text(l10n.saving, style: AppTheme.caption),
        ],
      );
    }
    if (submitError != null) {
      return Column(
        children: [
          Text(
            submitError!,
            style: AppTheme.caption.copyWith(color: AppTheme.error),
            textAlign: TextAlign.center,
          ),
          if (onRetrySubmit != null)
            TextButton(onPressed: onRetrySubmit, child: Text(l10n.retry)),
        ],
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.check_rounded, size: 14, color: AppTheme.success),
        const SizedBox(width: 6),
        Text(
          l10n.trainingResultSaved,
          style: const TextStyle(
            color: AppTheme.success,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
