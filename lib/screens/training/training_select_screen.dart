import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/training.dart';
import '../../utils/app_theme.dart';
import '../../utils/haptic_service.dart';
import 'bot_training_setup_screen.dart';
import 'logic/atc_mode.dart';
import 'logic/atc_strategy.dart';
import 'logic/bobs_27_strategy.dart';
import 'logic/checkout_50_strategy.dart';
import 'logic/checkout_finish_strategy.dart';
import 'logic/high_score_strategy.dart';
import 'logic/important_doubles_strategy.dart';
import 'logic/jdc_challenge_strategy.dart';
import 'logic/training_strategy.dart';
import 'checkout_vision_screen.dart';
import 'quick_count_screen.dart';
import 'training_ai_screen.dart';

/// Accent of the Important Doubles drill — the green the key doubles are
/// charted in, so the drill, its tile and its progress screen all read as one
/// thing.
const Color kImportantDoublesColor = Color(0xFF199E70);

/// Accent of the Checkouts family — the purple the Checkout 81/121 drill was
/// already charted in.
const Color kCheckoutsColor = Color(0xFF7C3AED);

/// The training families the hub groups the drills into, below the
/// always-visible bot hero card.
enum TrainingCategory { doubles, checkouts, scoring, games, calcul }

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
          const SizedBox(height: 20),
          Row(
            children: [
              Text(
                l10n.trainingCategoriesLabel.toUpperCase(),
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.6,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  height: 1,
                  color: AppTheme.surfaceLight.withValues(alpha: 0.65),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _CategoryTile(
                    title: l10n.trainingCategoryDoubles,
                    gameCount: 3,
                    icon: Icons.my_location,
                    color: kImportantDoublesColor,
                    gameIcons: const [
                      Icons.my_location,
                      Icons.gps_fixed,
                      Icons.schedule,
                    ],
                    onTap: () =>
                        _openCategory(context, TrainingCategory.doubles),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _CategoryTile(
                    title: l10n.trainingCategoryCheckouts,
                    gameCount: 2,
                    icon: Icons.flag_outlined,
                    color: kCheckoutsColor,
                    gameIcons: const [
                      Icons.center_focus_strong,
                      Icons.flag_outlined,
                    ],
                    onTap: () =>
                        _openCategory(context, TrainingCategory.checkouts),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _CategoryTile(
                    title: l10n.trainingCategoryScoring,
                    gameCount: 2,
                    icon: Icons.local_fire_department,
                    color: AppTheme.error,
                    gameIcons: const [
                      Icons.local_fire_department,
                      Icons.schedule,
                    ],
                    onTap: () =>
                        _openCategory(context, TrainingCategory.scoring),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _CategoryTile(
                    title: l10n.trainingCategoryGames,
                    gameCount: 1,
                    icon: Icons.emoji_events,
                    color: AppTheme.secondary,
                    gameIcons: const [Icons.emoji_events],
                    onTap: () => _openCategory(context, TrainingCategory.games),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _CategoryTile(
                    title: l10n.trainingCategoryCalcul,
                    gameCount: 2,
                    icon: Icons.psychology,
                    color: AppTheme.primary,
                    gameIcons: const [Icons.calculate, Icons.track_changes],
                    onTap: () =>
                        _openCategory(context, TrainingCategory.calcul),
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(child: SizedBox()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One training family: the games behind the hub tile the player tapped, as
/// the full cards (description + rules) the flat list used to show.
class TrainingCategoryScreen extends StatelessWidget {
  final TrainingCategory category;

  const TrainingCategoryScreen({super.key, required this.category});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(_title(l10n))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: _tiles(context, l10n),
      ),
    );
  }

  String _title(AppLocalizations l10n) {
    switch (category) {
      case TrainingCategory.doubles:
        return l10n.trainingCategoryDoubles;
      case TrainingCategory.checkouts:
        return l10n.trainingCategoryCheckouts;
      case TrainingCategory.scoring:
        return l10n.trainingCategoryScoring;
      case TrainingCategory.games:
        return l10n.trainingCategoryGames;
      case TrainingCategory.calcul:
        return l10n.trainingCategoryCalcul;
    }
  }

  List<Widget> _tiles(BuildContext context, AppLocalizations l10n) {
    switch (category) {
      case TrainingCategory.doubles:
        return [
          _TrainingTile(
            title: l10n.trainingImportantDoubles,
            description: l10n.trainingImportantDoublesDescription,
            icon: Icons.my_location,
            color: kImportantDoublesColor,
            onTap: () => openImportantDoublesPicker(context),
            onInfo: () => showTrainingRulesSheet(
              context,
              title: l10n.trainingImportantDoubles,
              body: l10n.trainingRulesImportantDoubles,
              color: kImportantDoublesColor,
              icon: Icons.my_location,
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
            title: l10n.trainingAroundTheClockDouble,
            description: l10n.trainingAroundTheClockDoublesDescription,
            icon: Icons.schedule,
            color: AppTheme.primary,
            onTap: () =>
                _startWithStrategy(context, AtcStrategy(mode: AtcMode.double)),
            onInfo: () => showTrainingRulesSheet(
              context,
              title: l10n.trainingAroundTheClockDouble,
              body: l10n.trainingRulesAroundTheClock,
              color: AppTheme.primary,
              icon: Icons.schedule,
            ),
          ),
        ];
      case TrainingCategory.checkouts:
        return [
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
            color: kCheckoutsColor,
            onTap: () => _openCheckoutPicker(context),
            onInfo: () => showTrainingRulesSheet(
              context,
              title: l10n.trainingCheckout81_121,
              body: l10n.trainingRulesCheckout81_121,
              color: kCheckoutsColor,
              icon: Icons.flag_outlined,
            ),
          ),
        ];
      case TrainingCategory.scoring:
        return [
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
            title: l10n.trainingAroundTheClock,
            description: l10n.trainingAroundTheClockScoringDescription,
            icon: Icons.schedule,
            color: AppTheme.primary,
            onTap: () => _openAtcSingleTriple(context),
            onInfo: () => showTrainingRulesSheet(
              context,
              title: l10n.trainingAroundTheClock,
              body: l10n.trainingRulesAroundTheClock,
              color: AppTheme.primary,
              icon: Icons.schedule,
            ),
          ),
        ];
      case TrainingCategory.games:
        return [
          _TrainingTile(
            title: l10n.trainingJdcChallenge,
            description: l10n.trainingJdcChallengeDescription,
            icon: Icons.emoji_events,
            color: AppTheme.accent,
            onTap: () => _startWithStrategy(context, JdcChallengeStrategy()),
            onInfo: () => showTrainingRulesSheet(
              context,
              title: l10n.trainingJdcChallenge,
              body: l10n.trainingRulesJdcChallenge,
              color: AppTheme.accent,
              icon: Icons.emoji_events,
            ),
          ),
        ];
      case TrainingCategory.calcul:
        return [
          _TrainingTile(
            title: l10n.trainingQuickCount,
            description: l10n.trainingQuickCountDescription,
            icon: Icons.calculate,
            color: AppTheme.primary,
            onTap: () => _startQuizScreen(context, const QuickCountScreen()),
            onInfo: () => showTrainingRulesSheet(
              context,
              title: l10n.trainingQuickCount,
              body: l10n.trainingRulesQuickCount,
              color: AppTheme.primary,
              icon: Icons.calculate,
            ),
          ),
          const SizedBox(height: 12),
          _TrainingTile(
            title: l10n.trainingCheckoutVision,
            description: l10n.trainingCheckoutVisionDescription,
            icon: Icons.track_changes,
            color: AppTheme.primary,
            onTap: () =>
                _startQuizScreen(context, const CheckoutVisionScreen()),
            onInfo: () => showTrainingRulesSheet(
              context,
              title: l10n.trainingCheckoutVision,
              body: l10n.trainingRulesCheckoutVision,
              color: AppTheme.primary,
              icon: Icons.track_changes,
            ),
          ),
        ];
    }
  }
}

void _openCategory(BuildContext context, TrainingCategory category) {
  HapticService.mediumImpact();
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => TrainingCategoryScreen(category: category),
    ),
  );
}

/// Mode sheet for the Scoring-family Around the Clock card. The Doubles mode
/// has its own card in the Doubles family, so only Single and Triple remain.
Future<void> _openAtcSingleTriple(BuildContext context) async {
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
  _startWithStrategy(context, CheckoutFinishStrategy(startScore: start));
}

void _startWithStrategy(BuildContext context, TrainingStrategy strategy) {
  HapticService.mediumImpact();
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => TrainingAiScreen(strategy: strategy)),
  );
}

/// Launches a camera-free quiz drill (Calcul family) — same gesture as
/// [_startWithStrategy] without the AI screen.
void _startQuizScreen(BuildContext context, Widget screen) {
  HapticService.mediumImpact();
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
}

/// Opens the bot match configurator (mode, format, rank on one screen) — it
/// routes through the placement camera setup → game screens on "play".
/// Kept as the single entry point so the hero card and the stats tab both
/// land on the same flow.
Future<void> openBotTrainingPicker(BuildContext context) async {
  HapticService.mediumImpact();
  await Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => const BotTrainingSetupScreen()),
  );
}

/// Opens the double picker and, if the player validates a selection, starts an
/// Important Doubles run on those targets (one 60-dart block each).
Future<void> openImportantDoublesPicker(BuildContext context) async {
  HapticService.mediumImpact();
  final targets = await showModalBottomSheet<List<int>>(
    context: context,
    backgroundColor: AppTheme.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const _ImportantDoublesSheet(),
  );
  if (targets == null || targets.isEmpty || !context.mounted) return;
  HapticService.mediumImpact();
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => TrainingAiScreen(
        strategy: ImportantDoublesStrategy(targets: targets),
      ),
    ),
  );
}

/// Grid of the eight key doubles. The player picks one or two; picking a third
/// drops the oldest so the selection never has to be cleared by hand.
class _ImportantDoublesSheet extends StatefulWidget {
  const _ImportantDoublesSheet();

  @override
  State<_ImportantDoublesSheet> createState() => _ImportantDoublesSheetState();
}

class _ImportantDoublesSheetState extends State<_ImportantDoublesSheet> {
  final List<int> _selected = [];

  void _toggle(int target) {
    HapticService.lightImpact();
    setState(() {
      if (_selected.remove(target)) return;
      if (_selected.length == 2) _selected.removeAt(0);
      _selected.add(target);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final dartCount =
        _selected.length * ImportantDoublesStrategy.dartsPerDouble;
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
              Text(
                l10n.trainingImportantDoublesPickTitle,
                style: AppTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                l10n.trainingImportantDoublesPickHint,
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 13,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Flexible(
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    alignment: WrapAlignment.center,
                    children: ImportantDoublesStrategy.keyDoubles.map((t) {
                      final order = _selected.indexOf(t);
                      return _DoubleChip(
                        target: t,
                        order: order < 0 ? null : order + 1,
                        showOrder: _selected.length > 1,
                        onTap: () => _toggle(t),
                      );
                    }).toList(),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                _selected.isEmpty
                    ? l10n.trainingImportantDoublesPickEmpty
                    : l10n.trainingImportantDoublesPickSummary(dartCount),
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                onPressed: _selected.isEmpty
                    ? null
                    : () =>
                          Navigator.of(context).pop(List<int>.from(_selected)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kImportantDoublesColor,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AppTheme.surfaceLight,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(l10n.trainingStartButton),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DoubleChip extends StatelessWidget {
  final int target;

  /// 1-based position in the selection, null when unselected.
  final int? order;

  /// Only worth showing the order once two doubles are queued.
  final bool showOrder;
  final VoidCallback onTap;

  const _DoubleChip({
    required this.target,
    required this.order,
    required this.showOrder,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final selected = order != null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 76,
          height: 66,
          decoration: BoxDecoration(
            color: selected
                ? kImportantDoublesColor.withValues(alpha: 0.18)
                : AppTheme.surfaceLight.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? kImportantDoublesColor
                  : AppTheme.surfaceLight.withValues(alpha: 0.8),
              width: selected ? 1.8 : 1,
            ),
          ),
          child: Stack(
            children: [
              Center(
                child: Text(
                  'D$target',
                  style: TextStyle(
                    color: selected ? kImportantDoublesColor : Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (selected && showOrder)
                Positioned(
                  top: 5,
                  right: 6,
                  child: Text(
                    '$order',
                    style: const TextStyle(
                      color: kImportantDoublesColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
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
    builder: (ctx) =>
        _RulesSheet(title: title, body: body, color: color, icon: icon),
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
                  Expanded(child: Text(title, style: AppTheme.titleLarge)),
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
    case TrainingType.importantDoubles:
      return l10n.trainingImportantDoubles;
    case TrainingType.quickCount:
      return l10n.trainingQuickCount;
    case TrainingType.checkoutVision:
      return l10n.trainingCheckoutVision;
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

/// Square hub tile for a training family. The shape is the signal: full-width
/// cards launch a game, tiles open a category — with the games it contains
/// echoed as a mini icon row at the bottom.
class _CategoryTile extends StatelessWidget {
  final String title;
  final int gameCount;
  final IconData icon;
  final Color color;
  final List<IconData> gameIcons;
  final VoidCallback onTap;

  const _CategoryTile({
    required this.title,
    required this.gameCount,
    required this.icon,
    required this.color,
    required this.gameIcons,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color.withValues(alpha: 0.45)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(height: 10),
              Text(
                title,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                l10n.trainingCategoryGameCount(gameCount).toUpperCase(),
                style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 14),
              const Spacer(),
              Row(
                children: [
                  for (final gameIcon in gameIcons)
                    Padding(
                      padding: const EdgeInsets.only(right: 5),
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: AppTheme.textSecondary.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppTheme.surfaceLight.withValues(
                              alpha: 0.65,
                            ),
                          ),
                        ),
                        child: Icon(
                          gameIcon,
                          color: AppTheme.textSecondary,
                          size: 14,
                        ),
                      ),
                    ),
                ],
              ),
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
              Text(
                title,
                style: AppTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: options
                        .map(
                          (o) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _SheetButton(option: o),
                          ),
                        )
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
