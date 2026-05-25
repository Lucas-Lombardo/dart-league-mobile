import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/bot_rank.dart';
import '../../models/training.dart';
import '../../providers/placement_provider.dart';
import '../../utils/app_theme.dart';
import '../../utils/haptic_service.dart';
import '../placement/placement_camera_setup_screen.dart';
import 'logic/atc_mode.dart';
import 'logic/atc_strategy.dart';
import 'logic/bobs_27_strategy.dart';
import 'logic/checkout_50_strategy.dart';
import 'logic/checkout_finish_strategy.dart';
import 'logic/high_score_strategy.dart';
import 'logic/jdc_challenge_strategy.dart';
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
            title: l10n.trainingBotTraining,
            description: l10n.trainingBotTrainingDescription,
            icon: Icons.smart_toy,
            color: AppTheme.accent,
            onTap: () => openBotTrainingPicker(context),
            onInfo: () => showTrainingRulesSheet(
              context,
              title: l10n.trainingBotTraining,
              body: l10n.trainingRulesBotTraining,
              color: AppTheme.accent,
              icon: Icons.smart_toy,
            ),
          ),
          const SizedBox(height: 12),
          _TrainingTile(
            title: l10n.trainingAroundTheClock,
            description: l10n.trainingAroundTheClockDescription,
            icon: Icons.schedule,
            color: AppTheme.primary,
            onTap: () => _openAtc(context),
            onInfo: () => showTrainingRulesSheet(
              context,
              title: l10n.trainingAroundTheClock,
              body: l10n.trainingRulesAroundTheClock,
              color: AppTheme.primary,
              icon: Icons.schedule,
            ),
          ),
          const SizedBox(height: 12),
          _TrainingTile(
            title: l10n.trainingBobs27,
            description: l10n.trainingBobs27Description,
            icon: Icons.gps_fixed,
            color: AppTheme.accent,
            onTap: () => _startWithStrategy(context, Bobs27Strategy()),
            onInfo: () => showTrainingRulesSheet(
              context,
              title: l10n.trainingBobs27,
              body: l10n.trainingRulesBobs27,
              color: AppTheme.accent,
              icon: Icons.gps_fixed,
            ),
          ),
          const SizedBox(height: 12),
          _TrainingTile(
            title: l10n.trainingHighScore,
            description: l10n.trainingHighScoreDescription,
            icon: Icons.local_fire_department,
            color: AppTheme.error,
            onTap: () => _startWithStrategy(context, HighScoreStrategy()),
            onInfo: () => showTrainingRulesSheet(
              context,
              title: l10n.trainingHighScore,
              body: l10n.trainingRulesHighScore,
              color: AppTheme.error,
              icon: Icons.local_fire_department,
            ),
          ),
          const SizedBox(height: 12),
          _TrainingTile(
            title: l10n.trainingCheckout50,
            description: l10n.trainingCheckout50Description,
            icon: Icons.center_focus_strong,
            color: AppTheme.success,
            onTap: () => _startWithStrategy(context, Checkout50Strategy()),
            onInfo: () => showTrainingRulesSheet(
              context,
              title: l10n.trainingCheckout50,
              body: l10n.trainingRulesCheckout50,
              color: AppTheme.success,
              icon: Icons.center_focus_strong,
            ),
          ),
          const SizedBox(height: 12),
          _TrainingTile(
            title: l10n.trainingCheckout81_121,
            description: l10n.trainingCheckout81_121Description,
            icon: Icons.flag_outlined,
            color: const Color(0xFF7C3AED),
            onTap: () => _openCheckoutPicker(context),
            onInfo: () => showTrainingRulesSheet(
              context,
              title: l10n.trainingCheckout81_121,
              body: l10n.trainingRulesCheckout81_121,
              color: const Color(0xFF7C3AED),
              icon: Icons.flag_outlined,
            ),
          ),
          const SizedBox(height: 12),
          _TrainingTile(
            title: l10n.trainingJdcChallenge,
            description: l10n.trainingJdcChallengeDescription,
            icon: Icons.emoji_events,
            color: const Color(0xFFEAB308),
            onTap: () => _startWithStrategy(context, JdcChallengeStrategy()),
            onInfo: () => showTrainingRulesSheet(
              context,
              title: l10n.trainingJdcChallenge,
              body: l10n.trainingRulesJdcChallenge,
              color: const Color(0xFFEAB308),
              icon: Icons.emoji_events,
            ),
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

/// Opens the rank picker bottomsheet and, if a rank is chosen, configures the
/// PlacementProvider for bot-training mode before routing through the existing
/// placement camera setup → placement game screens.
Future<void> openBotTrainingPicker(BuildContext context) async {
  HapticService.mediumImpact();
  final l10n = AppLocalizations.of(context);
  final rank = await showModalBottomSheet<BotRank>(
    context: context,
    backgroundColor: AppTheme.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _ModeSheet<BotRank>(
      title: l10n.trainingBotPickRank,
      options: [
        _SheetOption(
          label: l10n.rankBronze,
          hint: l10n.trainingBotAvg(BotRank.bronze.targetAverage),
          value: BotRank.bronze,
          color: const Color(0xFFCD7F32),
        ),
        _SheetOption(
          label: l10n.rankSilver,
          hint: l10n.trainingBotAvg(BotRank.silver.targetAverage),
          value: BotRank.silver,
          color: const Color(0xFFC0C0C0),
        ),
        _SheetOption(
          label: l10n.rankGold,
          hint: l10n.trainingBotAvg(BotRank.gold.targetAverage),
          value: BotRank.gold,
          color: const Color(0xFFFFD700),
        ),
        _SheetOption(
          label: l10n.rankPlatinum,
          hint: l10n.trainingBotAvg(BotRank.platinum.targetAverage),
          value: BotRank.platinum,
          color: const Color(0xFF9CB6C6),
        ),
        _SheetOption(
          label: l10n.rankDiamond,
          hint: l10n.trainingBotAvg(BotRank.diamond.targetAverage),
          value: BotRank.diamond,
          color: const Color(0xFF63D6F2),
        ),
        _SheetOption(
          label: l10n.rankPro,
          hint: l10n.trainingBotAvg(BotRank.pro.targetAverage),
          value: BotRank.pro,
          color: const Color(0xFF7C3AED),
        ),
        _SheetOption(
          label: l10n.rankMaster,
          hint: l10n.trainingBotAvg(BotRank.master.targetAverage),
          value: BotRank.master,
          color: AppTheme.error,
        ),
      ],
    ),
  );
  if (rank == null || !context.mounted) return;
  HapticService.mediumImpact();

  // Second sheet: pick the game length (501 / 301 / 201).
  final startingScore = await showModalBottomSheet<int>(
    context: context,
    backgroundColor: AppTheme.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _ModeSheet<int>(
      title: l10n.trainingBotPickGameType,
      options: [
        _SheetOption(
          label: '501',
          hint: l10n.trainingBotGameTypeHint501,
          value: 501,
          color: AppTheme.primary,
        ),
        _SheetOption(
          label: '301',
          hint: l10n.trainingBotGameTypeHint301,
          value: 301,
          color: AppTheme.accent,
        ),
        _SheetOption(
          label: '201',
          hint: l10n.trainingBotGameTypeHint201,
          value: 201,
          color: AppTheme.success,
        ),
      ],
    ),
  );
  if (startingScore == null || !context.mounted) return;
  HapticService.mediumImpact();
  context
      .read<PlacementProvider>()
      .startBotTrainingMatch(rank, startingScore: startingScore);
  if (!context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => const PlacementCameraSetupScreen(),
    ),
  );
}

/// Opens a modal bottom sheet that explains the rules of a training.
/// Reused by the picker tiles and (potentially) by the in-game UI.
Future<void> showTrainingRulesSheet(
  BuildContext context, {
  required String title,
  required String body,
  required Color color,
  required IconData icon,
}) {
  HapticService.lightImpact();
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppTheme.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _RulesSheet(
      title: title,
      body: body,
      color: color,
      icon: icon,
    ),
  );
}

class _RulesSheet extends StatelessWidget {
  final String title;
  final String body;
  final Color color;
  final IconData icon;

  const _RulesSheet({
    required this.title,
    required this.body,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: color, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: AppTheme.titleLarge,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Flexible(
                child: SingleChildScrollView(
                  child: Text(
                    body,
                    style: AppTheme.bodyLarge.copyWith(height: 1.45),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: color,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.close),
              ),
            ],
          ),
        ),
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
    case TrainingType.botTraining:
      return l10n.trainingBotTraining;
    case TrainingType.jdcChallenge:
      return l10n.trainingJdcChallenge;
  }
}

class _TrainingTile extends StatelessWidget {
  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final VoidCallback? onInfo;

  const _TrainingTile({
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    required this.onTap,
    this.onInfo,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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
              if (onInfo != null)
                IconButton(
                  tooltip: l10n.trainingRules,
                  icon: const Icon(Icons.info_outline),
                  color: AppTheme.textSecondary,
                  onPressed: onInfo,
                )
              else
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
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: AppTheme.titleLarge, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: options
                        .map((o) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _SheetButton(option: o),
                            ))
                        .toList(),
                  ),
                ),
              ),
            ],
          ),
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
