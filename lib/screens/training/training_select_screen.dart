import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/training.dart';
import '../../utils/app_theme.dart';
import '../../utils/haptic_service.dart';
import 'logic/atc_mode.dart';
import 'logic/atc_strategy.dart';
import 'logic/bobs_27_strategy.dart';
import 'logic/checkout_50_strategy.dart';
import 'logic/checkout_finish_strategy.dart';
import 'logic/high_score_strategy.dart';
import 'logic/training_strategy.dart';
import 'training_ai_screen.dart';

class TrainingSelectScreen extends StatelessWidget {
  const TrainingSelectScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.trainingSelectTitle)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _TrainingTile(
            title: l10n.trainingAroundTheClock,
            description: l10n.trainingAroundTheClockDescription,
            icon: Icons.schedule,
            color: AppTheme.primary,
            onTap: () => _openAtc(context),
          ),
          const SizedBox(height: 12),
          _TrainingTile(
            title: l10n.trainingBobs27,
            description: l10n.trainingBobs27Description,
            icon: Icons.gps_fixed,
            color: AppTheme.accent,
            onTap: () => _startWithStrategy(context, Bobs27Strategy()),
          ),
          const SizedBox(height: 12),
          _TrainingTile(
            title: l10n.trainingHighScore,
            description: l10n.trainingHighScoreDescription,
            icon: Icons.local_fire_department,
            color: AppTheme.error,
            onTap: () => _startWithStrategy(context, HighScoreStrategy()),
          ),
          const SizedBox(height: 12),
          _TrainingTile(
            title: l10n.trainingCheckout50,
            description: l10n.trainingCheckout50Description,
            icon: Icons.center_focus_strong,
            color: AppTheme.success,
            onTap: () => _startWithStrategy(context, Checkout50Strategy()),
          ),
          const SizedBox(height: 12),
          _TrainingTile(
            title: l10n.trainingCheckout81_121,
            description: l10n.trainingCheckout81_121Description,
            icon: Icons.flag_outlined,
            color: const Color(0xFF7C3AED),
            onTap: () => _openCheckoutPicker(context),
          ),
        ],
      ),
    );
  }

  Future<void> _openAtc(BuildContext context) async {
    HapticService.mediumImpact();
    final l10n = AppLocalizations.of(context);
    final mode = await showModalBottomSheet<AtcMode>(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ModeSheet(
        title: l10n.trainingAtcPickModeTitle,
        options: [
          _SheetOption(
            label: l10n.trainingAtcSingle,
            hint: l10n.trainingAtcSingleHint,
            value: AtcMode.single,
            color: AppTheme.primary,
          ),
          _SheetOption(
            label: l10n.trainingAtcDouble,
            hint: l10n.trainingAtcDoubleHint,
            value: AtcMode.double,
            color: AppTheme.success,
          ),
          _SheetOption(
            label: l10n.trainingAtcTriple,
            hint: l10n.trainingAtcTripleHint,
            value: AtcMode.triple,
            color: AppTheme.error,
          ),
        ],
      ),
    );
    if (mode == null || !context.mounted) return;
    _startWithStrategy(context, AtcStrategy(mode: mode));
  }

  Future<void> _openCheckoutPicker(BuildContext context) async {
    HapticService.mediumImpact();
    final l10n = AppLocalizations.of(context);
    final start = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ModeSheet(
        title: l10n.trainingCheckoutPickScore,
        options: [
          _SheetOption(
            label: '81',
            hint: l10n.trainingCheckout81Hint,
            value: 81,
            color: AppTheme.primary,
          ),
          _SheetOption(
            label: '121',
            hint: l10n.trainingCheckout121Hint,
            value: 121,
            color: AppTheme.accent,
          ),
        ],
      ),
    );
    if (start == null || !context.mounted) return;
    _startWithStrategy(
      context,
      CheckoutFinishStrategy(startScore: start),
    );
  }

  void _startWithStrategy(BuildContext context, TrainingStrategy strategy) {
    HapticService.mediumImpact();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TrainingAiScreen(strategy: strategy),
      ),
    );
  }
}

/// Resolves a display name for any training type.
String trainingDisplayName(AppLocalizations l10n, TrainingType type) {
  switch (type) {
    case TrainingType.aroundTheClock:
      return l10n.trainingAroundTheClock;
    case TrainingType.aroundTheClockDouble:
      return l10n.trainingAroundTheClockDouble;
    case TrainingType.aroundTheClockTriple:
      return l10n.trainingAroundTheClockTriple;
    case TrainingType.bobs27:
      return l10n.trainingBobs27;
    case TrainingType.highScore:
      return l10n.trainingHighScore;
    case TrainingType.checkout50:
      return l10n.trainingCheckout50;
    case TrainingType.checkout81:
      return l10n.trainingCheckoutFromN(81);
    case TrainingType.checkout121:
      return l10n.trainingCheckoutFromN(121);
  }
}

class _TrainingTile extends StatelessWidget {
  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _TrainingTile({
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppTheme.titleLarge),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: AppTheme.bodyLarge.copyWith(fontSize: 13),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppTheme.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

class _SheetOption<T> {
  final String label;
  final String hint;
  final T value;
  final Color color;
  const _SheetOption({
    required this.label,
    required this.hint,
    required this.value,
    required this.color,
  });
}

class _ModeSheet<T> extends StatelessWidget {
  final String title;
  final List<_SheetOption<T>> options;

  const _ModeSheet({required this.title, required this.options});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: AppTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ...options.map((o) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _SheetButton(option: o),
                )),
          ],
        ),
      ),
    );
  }
}

class _SheetButton<T> extends StatelessWidget {
  final _SheetOption<T> option;
  const _SheetButton({required this.option});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticService.mediumImpact();
          Navigator.of(context).pop(option.value);
        },
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: option.color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: option.color, width: 1.5),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      option.label,
                      style: TextStyle(
                        color: option.color,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      option.hint,
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.play_arrow_rounded, color: option.color),
            ],
          ),
        ),
      ),
    );
  }
}
