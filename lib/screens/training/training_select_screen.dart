import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/training.dart';
import '../../utils/app_theme.dart';
import '../../utils/haptic_service.dart';
import '../../widgets/design_system.dart';
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
/// charted in on the progress screen and the stats tab. The hub itself is
/// neutral (system D): no family colors on tiles or rows.
const Color kImportantDoublesColor = Color(0xFF199E70);

/// Accent of the Checkouts family — the purple the Checkout 81/121 drill was
/// already charted in.
const Color kCheckoutsColor = Color(0xFF7C3AED);

/// The training families the hub groups the drills into, below the
/// always-visible bot primary row.
enum TrainingCategory { doubles, checkouts, scoring, games, calcul }

/// Light icon on a quiet 38 px disc — the leading of every tile and row here.
const Color _kIconColor = Color(0xFFE2E8F0);

class TrainingSelectScreen extends StatelessWidget {
  const TrainingSelectScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.trainingSelectTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        children: [
          // THE filled block of the screen: the bot match. Its rules live
          // behind the (i) of the configurator it opens.
          DsPrimaryRow(
            icon: Icons.smart_toy_outlined,
            title: l10n.botSetupTitle,
            subtitle: l10n.trainingBotRowSubtitle,
            onTap: () => _pushBotSetup(context),
          ),
          const SizedBox(height: 28),
          DsSectionHeader(title: l10n.trainingCategoriesLabel),
          const SizedBox(height: 12),
          _grid([
            _CategoryTile(
              title: l10n.trainingCategoryDoubles,
              caption: l10n.trainingCategoryGameCount(3),
              icon: Icons.my_location_outlined,
              onTap: () => _openCategory(context, TrainingCategory.doubles),
            ),
            _CategoryTile(
              title: l10n.trainingCategoryCheckouts,
              caption: l10n.trainingCategoryGameCount(2),
              icon: Icons.flag_outlined,
              onTap: () => _openCategory(context, TrainingCategory.checkouts),
            ),
            _CategoryTile(
              title: l10n.trainingCategoryScoring,
              caption: l10n.trainingCategoryGameCount(2),
              icon: Icons.local_fire_department_outlined,
              onTap: () => _openCategory(context, TrainingCategory.scoring),
            ),
            _CategoryTile(
              title: l10n.trainingCategoryGames,
              caption: l10n.trainingCategoryGameCount(1),
              icon: Icons.emoji_events_outlined,
              onTap: () => _openCategory(context, TrainingCategory.games),
            ),
            _CategoryTile(
              title: l10n.trainingCategoryCalcul,
              caption:
                  '${l10n.trainingCategoryGameCount(2)} · ${l10n.trainingNoCameraShort}',
              icon: Icons.calculate_outlined,
              onTap: () => _openCategory(context, TrainingCategory.calcul),
            ),
          ]),
        ],
      ),
    );
  }

  /// Two columns, 10 px gaps; an odd last tile keeps its half width.
  Widget _grid(List<Widget> tiles) {
    final rows = <Widget>[];
    for (var i = 0; i < tiles.length; i += 2) {
      if (i > 0) rows.add(const SizedBox(height: 10));
      rows.add(
        Row(
          children: [
            Expanded(child: tiles[i]),
            const SizedBox(width: 10),
            Expanded(
              child: i + 1 < tiles.length ? tiles[i + 1] : const SizedBox(),
            ),
          ],
        ),
      );
    }
    return Column(children: rows);
  }
}

/// One training family: the games behind the hub tile the player tapped, as
/// rows (description + rules) — the flat list the hub used to be.
class TrainingCategoryScreen extends StatelessWidget {
  final TrainingCategory category;

  const TrainingCategoryScreen({super.key, required this.category});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tiles = _tiles(context, l10n);
    return Scaffold(
      appBar: AppBar(title: Text(_title(l10n))),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        itemCount: tiles.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, i) => tiles[i],
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
            icon: Icons.my_location_outlined,
            onTap: () => openImportantDoublesPicker(context),
            onInfo: () => showTrainingRulesSheet(
              context,
              title: l10n.trainingImportantDoubles,
              body: l10n.trainingRulesImportantDoubles,
              icon: Icons.my_location_outlined,
            ),
          ),
          _TrainingTile(
            title: l10n.trainingBobs27,
            description: l10n.trainingBobs27Description,
            icon: Icons.adjust_outlined,
            onTap: () => _startWithStrategy(context, Bobs27Strategy()),
            onInfo: () => showTrainingRulesSheet(
              context,
              title: l10n.trainingBobs27,
              body: l10n.trainingRulesBobs27,
              icon: Icons.adjust_outlined,
            ),
          ),
          _TrainingTile(
            title: l10n.trainingAroundTheClockDouble,
            description: l10n.trainingAroundTheClockDoublesDescription,
            icon: Icons.schedule_outlined,
            onTap: () =>
                _startWithStrategy(context, AtcStrategy(mode: AtcMode.double)),
            onInfo: () => showTrainingRulesSheet(
              context,
              title: l10n.trainingAroundTheClockDouble,
              body: l10n.trainingRulesAroundTheClock,
              icon: Icons.schedule_outlined,
            ),
          ),
        ];
      case TrainingCategory.checkouts:
        return [
          _TrainingTile(
            title: l10n.trainingCheckout50,
            description: l10n.trainingCheckout50Description,
            icon: Icons.center_focus_strong_outlined,
            onTap: () => _startWithStrategy(context, Checkout50Strategy()),
            onInfo: () => showTrainingRulesSheet(
              context,
              title: l10n.trainingCheckout50,
              body: l10n.trainingRulesCheckout50,
              icon: Icons.center_focus_strong_outlined,
            ),
          ),
          _TrainingTile(
            title: l10n.trainingCheckout81_121,
            description: l10n.trainingCheckout81_121Description,
            icon: Icons.flag_outlined,
            onTap: () => _openCheckoutPicker(context),
            onInfo: () => showTrainingRulesSheet(
              context,
              title: l10n.trainingCheckout81_121,
              body: l10n.trainingRulesCheckout81_121,
              icon: Icons.flag_outlined,
            ),
          ),
        ];
      case TrainingCategory.scoring:
        return [
          _TrainingTile(
            title: l10n.trainingHighScore,
            description: l10n.trainingHighScoreDescription,
            icon: Icons.local_fire_department_outlined,
            onTap: () => _startWithStrategy(context, HighScoreStrategy()),
            onInfo: () => showTrainingRulesSheet(
              context,
              title: l10n.trainingHighScore,
              body: l10n.trainingRulesHighScore,
              icon: Icons.local_fire_department_outlined,
            ),
          ),
          _TrainingTile(
            title: l10n.trainingAroundTheClock,
            description: l10n.trainingAroundTheClockScoringDescription,
            icon: Icons.schedule_outlined,
            onTap: () => _openAtcSingleTriple(context),
            onInfo: () => showTrainingRulesSheet(
              context,
              title: l10n.trainingAroundTheClock,
              body: l10n.trainingRulesAroundTheClock,
              icon: Icons.schedule_outlined,
            ),
          ),
        ];
      case TrainingCategory.games:
        return [
          _TrainingTile(
            title: l10n.trainingJdcChallenge,
            description: l10n.trainingJdcChallengeDescription,
            icon: Icons.emoji_events_outlined,
            onTap: () => _startWithStrategy(context, JdcChallengeStrategy()),
            onInfo: () => showTrainingRulesSheet(
              context,
              title: l10n.trainingJdcChallenge,
              body: l10n.trainingRulesJdcChallenge,
              icon: Icons.emoji_events_outlined,
            ),
          ),
        ];
      case TrainingCategory.calcul:
        return [
          _TrainingTile(
            title: l10n.trainingQuickCount,
            description: l10n.trainingQuickCountDescription,
            icon: Icons.calculate_outlined,
            onTap: () => _startQuizScreen(context, const QuickCountScreen()),
            onInfo: () => showTrainingRulesSheet(
              context,
              title: l10n.trainingQuickCount,
              body: l10n.trainingRulesQuickCount,
              icon: Icons.calculate_outlined,
            ),
          ),
          _TrainingTile(
            title: l10n.trainingCheckoutVision,
            description: l10n.trainingCheckoutVisionDescription,
            icon: Icons.track_changes_outlined,
            onTap: () =>
                _startQuizScreen(context, const CheckoutVisionScreen()),
            onInfo: () => showTrainingRulesSheet(
              context,
              title: l10n.trainingCheckoutVision,
              body: l10n.trainingRulesCheckoutVision,
              icon: Icons.track_changes_outlined,
            ),
          ),
        ];
    }
  }
}

// The tiles and rows below are DsCards, which already give the tap haptic —
// these private launchers therefore don't add one of their own.

void _openCategory(BuildContext context, TrainingCategory category) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => TrainingCategoryScreen(category: category),
    ),
  );
}

Future<void> _pushBotSetup(BuildContext context) {
  return Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => const BotTrainingSetupScreen()),
  );
}

/// Mode sheet for the Scoring-family Around the Clock card. The Doubles mode
/// has its own card in the Doubles family, so only Single and Triple remain.
Future<void> _openAtcSingleTriple(BuildContext context) async {
  final l10n = AppLocalizations.of(context);
  final mode = await showModalBottomSheet<AtcMode>(
    context: context,
    builder: (_) => _ModeSheet(
      title: l10n.trainingAtcPickModeTitle,
      options: [
        _SheetOption(
          label: l10n.trainingAtcSingle,
          hint: l10n.trainingAtcSingleHint,
          value: AtcMode.single,
        ),
        _SheetOption(
          label: l10n.trainingAtcTriple,
          hint: l10n.trainingAtcTripleHint,
          value: AtcMode.triple,
        ),
      ],
    ),
  );
  if (mode == null || !context.mounted) return;
  _startWithStrategy(context, AtcStrategy(mode: mode));
}

Future<void> _openCheckoutPicker(BuildContext context) async {
  final l10n = AppLocalizations.of(context);
  final start = await showModalBottomSheet<int>(
    context: context,
    builder: (_) => _ModeSheet(
      title: l10n.trainingCheckoutPickScore,
      options: [
        _SheetOption(
          label: '81',
          hint: l10n.trainingCheckout81Hint,
          value: 81,
        ),
        _SheetOption(
          label: '121',
          hint: l10n.trainingCheckout121Hint,
          value: 121,
        ),
      ],
    ),
  );
  if (start == null || !context.mounted) return;
  _startWithStrategy(context, CheckoutFinishStrategy(startScore: start));
}

void _startWithStrategy(BuildContext context, TrainingStrategy strategy) {
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => TrainingAiScreen(strategy: strategy)),
  );
}

/// Launches a camera-free quiz drill (Calcul family) — same gesture as
/// [_startWithStrategy] without the AI screen.
void _startQuizScreen(BuildContext context, Widget screen) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
}

/// Opens the bot match configurator (mode, format, rank on one screen) — it
/// routes through the placement camera setup → game screens on "play".
/// Kept as the single entry point so the hub row and the stats tab both
/// land on the same flow.
Future<void> openBotTrainingPicker(BuildContext context) async {
  HapticService.mediumImpact();
  await _pushBotSetup(context);
}

/// Opens the double picker and, if the player validates a selection, starts an
/// Important Doubles run on those targets (one 60-dart block each).
Future<void> openImportantDoublesPicker(BuildContext context) async {
  HapticService.mediumImpact();
  final targets = await showModalBottomSheet<List<int>>(
    context: context,
    isScrollControlled: true,
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
                style: AppTheme.caption.copyWith(fontSize: 13),
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
                style: AppTheme.caption.copyWith(fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _selected.isEmpty
                      ? null
                      : () =>
                          Navigator.of(context).pop(List<int>.from(_selected)),
                  icon: const Icon(Icons.play_arrow_rounded, size: 20),
                  label: Text(l10n.trainingStartButton),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 76 × 66 selectable chip; the selected variant is primary at 8 % with a
/// primary hairline, the label in primaryLight.
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
    return SizedBox(
      width: 76,
      height: 66,
      child: DsCard(
        radius: AppTheme.radiusRow,
        padding: EdgeInsets.zero,
        color: selected ? AppTheme.primary.withValues(alpha: 0.08) : null,
        side: selected ? const BorderSide(color: AppTheme.primary) : null,
        onTap: onTap,
        child: Stack(
          children: [
            Center(
              child: Text(
                'D$target',
                style: TextStyle(
                  color:
                      selected ? AppTheme.primaryLight : AppTheme.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (selected && showOrder)
              Positioned(
                top: 6,
                right: 8,
                child: Text(
                  '$order',
                  style: const TextStyle(
                    color: AppTheme.primaryLight,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Opens a modal bottom sheet that explains the rules of a training.
/// Reused by the drill rows and the bot configurator's (i).
Future<void> showTrainingRulesSheet(
  BuildContext context, {
  required String title,
  required String body,
  required IconData icon,
}) {
  HapticService.lightImpact();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _RulesSheet(title: title, body: body, icon: icon),
  );
}

class _RulesSheet extends StatelessWidget {
  final String title;
  final String body;
  final IconData icon;

  const _RulesSheet({
    required this.title,
    required this.body,
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
                  _IconDisc(icon),
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
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.close),
                ),
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

/// 38 px quiet disc with a light 20 px icon.
class _IconDisc extends StatelessWidget {
  final IconData icon;
  const _IconDisc(this.icon);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: 0.06),
      ),
      child: Icon(icon, size: 20, color: _kIconColor),
    );
  }
}

/// 72 px drill row: disc, 15 / 700 title, two-line caption, (i) for the
/// rules. Tapping the row launches the drill.
class _TrainingTile extends StatelessWidget {
  final String title;
  final String description;
  final IconData icon;
  final VoidCallback onTap;
  final VoidCallback? onInfo;

  const _TrainingTile({
    required this.title,
    required this.description,
    required this.icon,
    required this.onTap,
    this.onInfo,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SizedBox(
      height: 72,
      child: DsCard(
        radius: AppTheme.radiusRow,
        padding: const EdgeInsets.fromLTRB(14, 0, 10, 0),
        onTap: onTap,
        child: Row(
          children: [
            _IconDisc(icon),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.sectionTitle,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.caption.copyWith(height: 1.25),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (onInfo != null)
              DsIconButton(
                icon: Icons.info_outline_rounded,
                size: 36,
                tooltip: l10n.trainingRules,
                onTap: onInfo,
              )
            else
              const Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: AppTheme.textTertiary,
              ),
          ],
        ),
      ),
    );
  }
}

/// 100 px hub tile for a training family: disc top-left, name and "N jeux"
/// caption at the bottom. The shape is the signal — the full-width row
/// launches a game, tiles open a category.
class _CategoryTile extends StatelessWidget {
  final String title;
  final String caption;
  final IconData icon;
  final VoidCallback onTap;

  const _CategoryTile({
    required this.title,
    required this.caption,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 100,
      child: DsCard(
        radius: AppTheme.radiusRow,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _IconDisc(icon),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.sectionTitle.copyWith(height: 1.2),
                ),
                const SizedBox(height: 2),
                Text(
                  caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.caption.copyWith(height: 1.2),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetOption<T> {
  final String label;
  final String hint;
  final T value;
  const _SheetOption({
    required this.label,
    required this.hint,
    required this.value,
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
                            padding: const EdgeInsets.only(bottom: 10),
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

/// Option row of a mode sheet: label, hint, play icon. Tapping picks it.
class _SheetButton<T> extends StatelessWidget {
  final _SheetOption<T> option;
  const _SheetButton({required this.option});

  @override
  Widget build(BuildContext context) {
    return DsCard(
      radius: AppTheme.radiusRow,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      onTap: () => Navigator.of(context).pop(option.value),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(option.label, style: AppTheme.sectionTitle),
                const SizedBox(height: 2),
                Text(option.hint, style: AppTheme.caption),
              ],
            ),
          ),
          const SizedBox(width: 10),
          const Icon(
            Icons.play_arrow_rounded,
            color: AppTheme.primaryLight,
            size: 22,
          ),
        ],
      ),
    );
  }
}
