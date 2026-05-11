import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../../models/training.dart';
import '../../utils/app_navigator.dart';
import '../../utils/app_theme.dart';
import '../../utils/haptic_service.dart';
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
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppTheme.success.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    border: Border.all(color: AppTheme.success, width: 3),
                  ),
                  child: const Icon(
                    Icons.check_circle_outline,
                    color: AppTheme.success,
                    size: 56,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  l10n.trainingComplete.toUpperCase(),
                  style: AppTheme.displayLarge.copyWith(
                    color: AppTheme.success,
                    fontSize: 28,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(title, style: AppTheme.titleLarge),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppTheme.surfaceLight.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        scoreLabel.toUpperCase(),
                        style: AppTheme.labelLarge.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '$score',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 56,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${l10n.trainingDartsThrown}: $dartsThrown',
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          subtitle!,
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 14,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                      if (!completed) ...[
                        const SizedBox(height: 12),
                        Text(
                          l10n.trainingIncomplete,
                          style: const TextStyle(
                            color: AppTheme.accent,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (isSubmitting)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppTheme.primary,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        AppLocalizations.of(context).saving,
                        style: const TextStyle(color: AppTheme.textSecondary),
                      ),
                    ],
                  )
                else if (submitError != null)
                  Column(
                    children: [
                      Text(
                        submitError!,
                        style: const TextStyle(color: AppTheme.error),
                        textAlign: TextAlign.center,
                      ),
                      if (onRetrySubmit != null)
                        TextButton(
                          onPressed: onRetrySubmit,
                          child: Text(l10n.retry),
                        ),
                    ],
                  )
                else
                  Text(
                    l10n.trainingResultSaved,
                    style: const TextStyle(color: AppTheme.textSecondary),
                  ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: isSubmitting
                        ? null
                        : () {
                            HapticService.mediumImpact();
                            onPlayAgain();
                          },
                    style: AppTheme.primaryButtonStyle,
                    icon: const Icon(Icons.replay),
                    label: Text(l10n.trainingPlayAgain),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: isSubmitting
                        ? null
                        : () {
                            HapticService.lightImpact();
                            AppNavigator.toHomeClearing(context);
                          },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.textPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      side: BorderSide(
                        color: AppTheme.surfaceLight.withValues(alpha: 0.8),
                      ),
                    ),
                    icon: const Icon(Icons.home_outlined),
                    label: Text(l10n.backToHome),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
