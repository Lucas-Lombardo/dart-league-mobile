import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../services/auto_scoring_service.dart';
import '../../services/dart_scoring_service.dart';
import '../../utils/app_theme.dart';
import '../../utils/haptic_service.dart';
import '../../widgets/auto_score_display.dart' show shortDartLabel;
import '../../widgets/game_turn_ui.dart';
import 'logic/training_strategy.dart';

/// In-drill layout for solo trainings — the training-mode twin of
/// [AutoScoreGameView]. Same building blocks as a ranked match (camera panel,
/// visit chips, auto-validation row, CONFIRM pill) so a drill and a match look
/// like the same app; the only difference is the score bar, which shows the
/// drill's target/score/progress instead of two players.
///
/// Nothing here ever scrolls: the player throws from the oche and reads the
/// screen from ~2m away, so every block has to be on screen at once. The
/// camera is the only elastic block — it gives up exactly the height the
/// scoring stack needs, and on short phones the dense tier shrinks the chips
/// and the focal number instead of pushing the drill bar out of view.
/// See training_game_view_layout_test.dart for the sizes this is held to.
class TrainingGameView extends StatelessWidget {
  final AutoScoringService scoringService;
  final TrainingStrategy strategy;

  /// Darts detected this visit but not yet committed. Feeds the strategy's
  /// live previews (next target, running score…).
  final List<TrainingDart> pending;

  /// Display name of the drill, shown above the score bar.
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
        final safeTop = MediaQuery.of(context).padding.top;
        final safeBottom = MediaQuery.of(context).padding.bottom;
        final isLandscape =
            MediaQuery.of(context).orientation == Orientation.landscape;
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
                icon: Icons.cameraswitch,
                color: AppTheme.playerBlue,
                onTap: onSwitchCamera,
              ),
            if (onToggleAi != null)
              GameControlButton(
                icon: aiEnabled ? Icons.smart_toy : Icons.smart_toy_outlined,
                color: aiEnabled ? AppTheme.playerBlue : AppTheme.textSecondary,
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

        final visitLabel = Row(
          children: [
            Expanded(
              child: Text(
                l10n.yourVisit,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                ),
              ),
            ),
            VisitTotal(
              total: scoringService.turnTotal,
              color: AppTheme.playerBlueBright,
            ),
          ],
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

        Widget scoreBar(bool dense) => TrainingScoreBar(
          title: title,
          strategy: strategy,
          pending: pending,
          dense: dense,
        );

        // A visit with darts confirms the throw (filled, primary action); an
        // empty visit skips the round (outlined, secondary) — same
        // filled/outlined grammar as the match CONFIRM button.
        final hasDarts = pending.isNotEmpty;
        // Unlike the match's one-word "CONFIRM", these labels need two lines on
        // a narrow phone (three on a 320dp one) — hence the tighter padding,
        // the tighter tracking and the centered wrap. Wrapping beats the
        // ellipsis the intrinsically-sized button used to produce.
        final confirmChild = Text(
          hasDarts
              ? l10n.trainingConfirmVisit.toUpperCase()
              : l10n.trainingEndRoundEarly.toUpperCase(),
          maxLines: 3,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
        );
        const confirmPadding = WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        );
        const confirmTextStyle = WidgetStatePropertyAll(
          TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
          ),
        );
        final confirmButton = hasDarts
            ? ElevatedButton(
                onPressed: () {
                  HapticService.heavyImpact();
                  onConfirm();
                },
                style: gameFilledButtonStyle(AppTheme.playerBlue).copyWith(
                  padding: confirmPadding,
                  textStyle: confirmTextStyle,
                ),
                child: confirmChild,
              )
            : OutlinedButton(
                onPressed: () {
                  HapticService.heavyImpact();
                  onConfirm();
                },
                style: gameOutlineButtonStyle(AppTheme.playerBlue).copyWith(
                  padding: confirmPadding,
                  textStyle: confirmTextStyle,
                ),
                child: confirmChild,
              );

        final showAutoValidation = aiEnabled && scoringService.isCapturing;
        final autoValidationChip = Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppTheme.gamePanelEmpty,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppTheme.playerBlueDim.withValues(alpha: 0.5),
            ),
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
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.autoValidation,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.playerBlue,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                    Text(
                      l10n.autoValidationHint,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 10,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );

        // Fixed 55/45 split when both are shown — an intrinsically sized button
        // ate so much width that the hint was clipped mid-word. Alone, the
        // button spans the row: it's the only action left.
        // The height is fixed rather than intrinsic: the auto-validation chip
        // comes and goes during a visit, and since the camera now absorbs the
        // slack, a growing row would resize the video feed mid-throw.
        final bottomRow = SizedBox(
          height: 56,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: showAutoValidation
                ? [
                    Expanded(flex: 11, child: autoValidationChip),
                    const SizedBox(width: 10),
                    Expanded(flex: 9, child: confirmButton),
                  ]
                : [Expanded(child: confirmButton)],
          ),
        );

        if (isLandscape) {
          // Half a phone's width per column and barely 350dp of height: the
          // scoring side always runs dense here.
          return Container(
            color: AppTheme.gameBackground,
            child: Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      12,
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
                      12,
                      safeBottom + 8,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Spacer(),
                        visitLabel,
                        const SizedBox(height: 8),
                        chipsRow(true),
                        const SizedBox(height: 10),
                        scoreBar(true),
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
            padding: EdgeInsets.fromLTRB(12, safeTop + 4, 12, safeBottom + 10),
            child: LayoutBuilder(
              builder: (context, constraints) {
                // The scoring stack needs ~340dp at full size; below this the
                // camera would be starved, so trade size for fit instead.
                final dense = constraints.maxHeight < 620;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Elastic: the camera keeps whatever the stack leaves.
                    Expanded(child: cameraPanel),
                    const SizedBox(height: 12),
                    visitLabel,
                    const SizedBox(height: 8),
                    chipsRow(dense),
                    const SizedBox(height: 10),
                    scoreBar(dense),
                    const SizedBox(height: 8),
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

/// Training counterpart of [UserScoreBar]: same panel, same typographic scale,
/// but it reads the drill's focal value (next target, remaining…) and its
/// secondary metric instead of two players' remaining scores.
class TrainingScoreBar extends StatelessWidget {
  final String title;
  final TrainingStrategy strategy;
  final List<TrainingDart> pending;

  /// Shrinks the focal number and the paddings when the screen is too short to
  /// fit the bar at full size (landscape, small phones). Everything stays
  /// visible — the bar never scrolls.
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
      fontSize: dense ? 36 : 46,
      fontWeight: FontWeight.w800,
      height: 1.05,
      letterSpacing: -1,
      color: AppTheme.playerBlueBright,
    );

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: dense ? 9 : 12),
      decoration: BoxDecoration(
        color: AppTheme.gamePanelEmpty,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              if (caption != null) ...[
                const SizedBox(width: 8),
                // Flexible: the JDC caption ("PART 1 — SHANGHAI 10-15") is
                // long enough to push past the panel on a narrow phone.
                Flexible(
                  child: Text(
                    caption.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppTheme.textSecondary.withValues(alpha: 0.9),
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ],
            ],
          ),
          SizedBox(height: dense ? 4 : 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      strategy.primaryLabel(l10n).toUpperCase(),
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 2),
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
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        secondaryValue,
                        style: TextStyle(
                          color: AppTheme.accent,
                          fontSize: dense ? 23 : 28,
                          fontWeight: FontWeight.w800,
                          height: 1.1,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
          SizedBox(height: dense ? 8 : 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 4,
              color: AppTheme.playerBlue,
              backgroundColor: AppTheme.gamePanel,
            ),
          ),
        ],
      ),
    );
  }
}
