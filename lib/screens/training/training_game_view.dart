import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../services/auto_scoring_service.dart';
import '../../services/dart_scoring_service.dart';
import '../../utils/app_theme.dart';
import '../../utils/game_system_ui.dart';
import '../../utils/haptic_service.dart';
import '../../widgets/auto_score_display.dart' show shortDartLabel;
import '../../widgets/design_system.dart';
import '../../widgets/game_turn_ui.dart';
import 'logic/training_strategy.dart';

/// In-drill layout for solo trainings — the training-mode twin of
/// [AutoScoreGameView], in the in-match vocabulary of the visual system: a
/// score header above the camera (drill title, focal value, 3 px progress
/// hairline), the blue-bordered camera panel with its glass controls, the
/// visit label row, the three dart chips and the bottom row (auto-validation
/// strip + the one primary button). The only thing that differs from a match
/// is the header, which reads the drill's target/score/progress instead of
/// two players.
///
/// Nothing here ever scrolls: the player throws from the oche and reads the
/// screen from ~2m away, so every block has to be on screen at once. The
/// camera is the only elastic block — it gives up exactly the height the
/// scoring stack needs, and on short phones the dense tier shrinks the chips
/// and the focal number instead of pushing anything out of view.
/// See training_game_view_layout_test.dart for the sizes this is held to.
class TrainingGameView extends StatelessWidget {
  final AutoScoringService scoringService;
  final TrainingStrategy strategy;

  /// Darts detected this visit but not yet committed. Feeds the strategy's
  /// live previews (next target, running score…).
  final List<TrainingDart> pending;

  /// Display name of the drill, shown in the score header.
  final String title;

  final VoidCallback onConfirm;
  final Widget? localCameraPreview;
  final VoidCallback? onBack;
  final VoidCallback? onSwitchCamera;
  final VoidCallback? onZoomIn;
  final VoidCallback? onZoomOut;
  final double currentZoom;
  final double minZoom;
  final double maxZoom;
  final void Function(int index, DartScore? current) onEditSlot;
  final VoidCallback onRemoveLast;
  final VoidCallback? onToggleAi;
  final bool aiEnabled;

  const TrainingGameView({
    super.key,
    required this.scoringService,
    required this.strategy,
    required this.pending,
    required this.title,
    required this.onConfirm,
    required this.onEditSlot,
    required this.onRemoveLast,
    this.localCameraPreview,
    this.onBack,
    this.onSwitchCamera,
    this.onZoomIn,
    this.onZoomOut,
    this.currentZoom = 1.0,
    this.minZoom = 1.0,
    this.maxZoom = 1.0,
    this.onToggleAi,
    this.aiEnabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: scoringService,
      builder: (context, _) {
        final l10n = AppLocalizations.of(context);
        final slots = scoringService.dartSlots;
        final mq = MediaQuery.of(context);
        final safeTop = mq.padding.top;
        final safeBottom = mq.padding.bottom;
        final isLandscape = mq.orientation == Orientation.landscape;
        // The screen owns the committed visit, so the removable dart is the
        // last one IT knows about — not the last non-null AI slot.
        final lastFilledIndex = pending.length - 1;

        final cameraPanel = GameCameraPanel(
          videoView: localCameraPreview,
          borderColor: AppTheme.playerBlue,
          onBack: onBack,
          controls: [
            if (onSwitchCamera != null)
              GameControlButton(
                icon: Icons.cameraswitch_outlined,
                onTap: onSwitchCamera,
              ),
            if (onToggleAi != null)
              GameControlButton(
                icon: aiEnabled
                    ? Icons.smart_toy_rounded
                    : Icons.smart_toy_outlined,
                active: aiEnabled,
                onTap: onToggleAi,
              ),
          ],
          showRemoveDartsHint: scoringService.showRemoveDartsHint,
          hint: scoringService.zoomHint,
          zoom: currentZoom,
          minZoom: minZoom,
          maxZoom: maxZoom,
          onZoomIn: onZoomIn,
          onZoomOut: onZoomOut,
        );

        final visitLabel = VisitLabelRow(
          label: l10n.yourVisit,
          total: scoringService.turnTotal,
          color: AppTheme.playerBlueBright,
        );

        Widget chipsRow(bool dense) => SizedBox(
          height: dense ? 72 : 92,
          child: Row(
            children: List.generate(3, (i) {
              final score = i < slots.length ? slots[i] : null;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(left: i == 0 ? 0 : 10),
                  child: DartVisitChip(
                    notation: score != null ? shortDartLabel(score) : null,
                    accent: AppTheme.playerBlue,
                    showEditLabel: score != null,
                    capturing: scoringService.isCapturing,
                    onTap: () => onEditSlot(i, score),
                    onRemove: (score != null && i == lastFilledIndex)
                        ? () {
                            HapticService.heavyImpact();
                            onRemoveLast();
                          }
                        : null,
                  ),
                ),
              );
            }),
          ),
        );

        Widget header(bool dense) => TrainingScoreBar(
          title: title,
          strategy: strategy,
          pending: pending,
          dense: dense,
        );

        // A visit with darts confirms the throw (filled primary — the one
        // filled block of the screen); an empty visit skips the round
        // (outlined, secondary). Both come from the theme.
        final hasDarts = pending.isNotEmpty;
        void handleConfirm() {
          HapticService.heavyImpact();
          onConfirm();
        }
        // Unlike the match's one-word "Confirmer", these labels need two
        // lines on a narrow phone (three on a 320dp one): the theme's
        // 14 px vertical padding leaves no room for that, so it is tightened
        // here and the label wraps, centred, instead of being clipped.
        final confirmLabel = Text(
          hasDarts ? l10n.trainingConfirmVisit : l10n.trainingEndRoundEarly,
          maxLines: 3,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
        );
        const confirmStyle = ButtonStyle(
          padding: WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          ),
        );
        final confirmButton = hasDarts
            ? ElevatedButton(
                onPressed: handleConfirm,
                style: confirmStyle,
                child: confirmLabel,
              )
            : OutlinedButton(
                onPressed: handleConfirm,
                style: confirmStyle,
                child: confirmLabel,
              );

        final showAutoValidation = aiEnabled && scoringService.isCapturing;
        final autoValidationChip = Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.radiusRow),
            border: Border.all(color: AppTheme.border),
          ),
          child: Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  color: AppTheme.playerBlue,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.autoValidation,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.labelSmall.copyWith(
                        color: AppTheme.playerBlue,
                        letterSpacing: 0.7,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      l10n.autoValidationHint,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.caption.copyWith(
                        fontSize: 11,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );

        // The strip takes the width, the button keeps the mockup's 140 px —
        // an intrinsically sized button ate so much width that the hint was
        // clipped mid-word. Alone, the button spans the row: it's the only
        // action left. The height is fixed rather than intrinsic: the strip
        // comes and goes during a visit, and since the camera absorbs the
        // slack, a growing row would resize the video feed mid-throw. 64 is
        // what the strip needs at its tallest (label + two lines of hint in
        // French) — anything less clips it (layout test).
        final bottomRow = SizedBox(
          height: 64,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: showAutoValidation
                ? [
                    Expanded(child: autoValidationChip),
                    const SizedBox(width: 10),
                    SizedBox(width: 140, child: confirmButton),
                  ]
                : [Expanded(child: confirmButton)],
          ),
        );

        if (isLandscape) {
          // Half a phone's width per column and barely 350dp of height: the
          // scoring side always runs dense here.
          final gutters = gameSideGutters(context);
          return Container(
            color: AppTheme.gameBackground,
            child: Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      gutters.left,
                      safeTop + 8,
                      6,
                      safeBottom + 8,
                    ),
                    child: cameraPanel,
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      6,
                      safeTop + 8,
                      gutters.right,
                      safeBottom + 8,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        header(true),
                        const Spacer(),
                        visitLabel,
                        const SizedBox(height: 10),
                        chipsRow(true),
                        const Spacer(),
                        bottomRow,
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        return Container(
          color: AppTheme.gameBackground,
          child: Padding(
            padding: EdgeInsets.fromLTRB(12, safeTop + 8, 12, safeBottom + 10),
            child: LayoutBuilder(
              builder: (context, constraints) {
                // The scoring stack needs ~330dp at full size; below this the
                // camera would be starved, so trade size for fit instead.
                final dense = constraints.maxHeight < 620;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    header(dense),
                    const SizedBox(height: 12),
                    // Elastic: the camera keeps whatever the stack leaves.
                    Expanded(child: cameraPanel),
                    const SizedBox(height: 14),
                    visitLabel,
                    const SizedBox(height: 10),
                    chipsRow(dense),
                    const SizedBox(height: 12),
                    bottomRow,
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}

/// Training counterpart of [TurnScoreHeader]: the drill title with its
/// progress caption, the focal value (next target, remaining…) at the match's
/// 42 / 800 tabular size, the optional secondary metric in my identity colour
/// on the right, and a 3 px progress hairline. Bare on the background, like
/// the match header — no panel.
class TrainingScoreBar extends StatelessWidget {
  final String title;
  final TrainingStrategy strategy;
  final List<TrainingDart> pending;

  /// Shrinks the focal number and the gaps when the screen is too short to
  /// fit the header at full size (landscape, small phones). Everything stays
  /// visible — the header never scrolls.
  final bool dense;

  const TrainingScoreBar({
    super.key,
    required this.title,
    required this.strategy,
    required this.pending,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final primaryValue = strategy.primaryValue(l10n, pending);
    final secondaryLabel = strategy.secondaryLabel(l10n);
    final secondaryValue = strategy.secondaryValue(l10n, pending);
    final caption = strategy.progressCaption(l10n, pending);
    final progress = strategy.progress(pending).clamp(0.0, 1.0);

    // Same size as the match remaining-score: it's the one thing the player
    // reads from the oche (~2m away).
    final focalStyle = TextStyle(
      fontSize: dense ? 34 : 42,
      fontWeight: FontWeight.w800,
      height: 1,
      letterSpacing: -1.2,
      color: AppTheme.textPrimary,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final secondaryStyle = TextStyle(
      fontSize: dense ? 20 : 24,
      fontWeight: FontWeight.w800,
      height: 1,
      color: AppTheme.playerBlueBright,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.sectionTitle,
                ),
              ),
              if (caption != null) ...[
                const SizedBox(width: 12),
                // Flexible: the JDC caption ("Partie 1 — Shanghai 10–15") is
                // long enough to push past the row on a narrow phone.
                Flexible(
                  child: Text(
                    caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.caption,
                  ),
                ),
              ],
            ],
          ),
          SizedBox(height: dense ? 8 : 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      strategy.primaryLabel(l10n).toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.labelSmall,
                    ),
                    const SizedBox(height: 6),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(primaryValue, style: focalStyle),
                    ),
                  ],
                ),
              ),
              if (secondaryLabel != null && secondaryValue != null) ...[
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      secondaryLabel.toUpperCase(),
                      style: AppTheme.labelSmall,
                    ),
                    const SizedBox(height: 6),
                    Text(secondaryValue, style: secondaryStyle),
                  ],
                ),
              ],
            ],
          ),
          SizedBox(height: dense ? 8 : 10),
          DsProgressBar(value: progress),
        ],
      ),
    );
  }
}
