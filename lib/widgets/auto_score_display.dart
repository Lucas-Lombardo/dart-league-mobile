import 'package:flutter/material.dart';
import '../services/auto_scoring_service.dart';
import '../services/dart_scoring_service.dart';
import '../utils/app_theme.dart';
import '../utils/haptic_service.dart';
import '../l10n/app_localizations.dart';
import 'dartboard_edit_modal.dart';
import 'game_turn_ui.dart';

/// Full-screen auto-scoring layout for when it's the player's turn (maquette
/// layout): blue-bordered camera — sized by gameCameraHeight() so it matches
/// the opponent-turn camera exactly — plus the visit chips. X01 puts the
/// shared score [header] above the camera and AUTO VALIDATION + CONFIRM at
/// the bottom; cricket ([confirmBesideChips]) docks CONFIRM onto the chip
/// row and fills the space below with the score table (2026-08-19 layout).
class AutoScoreGameView extends StatelessWidget {
  final AutoScoringService scoringService;
  final VoidCallback onConfirm;
  final VoidCallback? onEndRoundEarly;
  final bool pendingConfirmation;
  final Widget? localCameraPreview;
  final bool isAudioMuted;
  final VoidCallback? onToggleAudio;
  final VoidCallback? onSwitchCamera;
  final VoidCallback? onZoomIn;
  final VoidCallback? onZoomOut;
  final double currentZoom;
  final double minZoom;
  final double maxZoom;

  final void Function(int index, DartScore score)? onEditDart;
  final void Function(int index)? onRemoveDart;

  /// Called once the dart-edit modal closes, whatever the outcome. Capture is
  /// stopped while the modal is open; a CANCELLED edit produces no provider
  /// notify, so without this the AI stayed dead for the rest of the turn.
  final VoidCallback? onEditModalClosed;
  final VoidCallback? onToggleAi;
  final bool aiEnabled;
  final int? roundNumber;
  final VoidCallback? onBack;
  /// The replay "record this turn" pill (built by the screen, which owns the
  /// capture flow) — rendered bottom-right of the camera panel.
  final Widget? captureButton;

  /// Score display below the visit chips (cricket: the [CricketScoreTable]).
  /// X01 passes null — its score lives in [header] above the camera.
  final Widget? scorePanel;

  /// Score header above the camera (X01: the shared no-badges
  /// [TurnScoreHeader], the same component as the opponent turn — 2026-08-19
  /// unified-header decision). Cricket passes null: its scores live in the
  /// table below.
  final Widget? header;

  /// Cricket "tableau" layout (2026-08-19): compact chips share their row
  /// with a vertical CONFIRM button and the AUTO VALIDATION strip disappears,
  /// freeing the height the score table needs. False keeps the X01 layout
  /// (full-size chips, CONFIRM in the bottom row).
  final bool confirmBesideChips;

  /// Overrides the visit TOTAL display ("+3 marques"). Null = X01 points sum.
  final String? visitTotalText;

  /// Per-dart chip subtitle ("1 marque", "+60 pts"). Null = X01 "60 pts".
  final String? Function(int index, String notation)? chipSubtitle;

  const AutoScoreGameView({
    super.key,
    required this.scoringService,
    required this.onConfirm,
    this.onEndRoundEarly,
    this.pendingConfirmation = false,
    this.localCameraPreview,
    this.isAudioMuted = true,
    this.onToggleAudio,
    this.onSwitchCamera,
    this.onZoomIn,
    this.onZoomOut,
    this.currentZoom = 1.0,
    this.minZoom = 1.0,
    this.maxZoom = 1.0,
    this.onEditDart,
    this.onRemoveDart,
    this.onEditModalClosed,
    this.onToggleAi,
    this.aiEnabled = true,
    this.roundNumber,
    this.captureButton,
    this.scorePanel,
    this.header,
    this.confirmBesideChips = false,
    this.visitTotalText,
    this.chipSubtitle,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: scoringService,
      builder: (context, _) {
        final l10n = AppLocalizations.of(context);
        final slots = scoringService.dartSlots;
        final turnTotal = scoringService.turnTotal;
        final hint = scoringService.zoomHint;
        // Only true when the AI has actually seen leftover darts on the
        // board — an already-clean board never shows the "remove darts" pill.
        final showRemoveDartsHint = scoringService.showRemoveDartsHint;
        // Cible vide avec UNE seule fléchette comptée : le passage
        // automatique est bloqué, on invite le joueur à CONFIRMER lui-même.
        final manualConfirmNeeded = scoringService.manualConfirmNeeded;
        final lastFilledIndex = slots.lastIndexWhere((s) => s != null);

        final safeTop = MediaQuery.of(context).padding.top;
        final safeBottom = MediaQuery.of(context).padding.bottom;
        final isLandscape =
            MediaQuery.of(context).orientation == Orientation.landscape;

        // ── Camera feed + overlay controls ──
        final cameraPanel = GameCameraPanel(
          videoView: localCameraPreview,
          borderColor: AppTheme.playerBlue,
          onBack: onBack,
          controls: [
            if (onToggleAudio != null)
              GameControlButton(
                icon: isAudioMuted ? Icons.mic_off : Icons.mic,
                color: isAudioMuted
                    ? AppTheme.opponentPink
                    : AppTheme.playerBlue,
                onTap: onToggleAudio,
              ),
            if (onSwitchCamera != null)
              GameControlButton(
                icon: Icons.cameraswitch,
                color: AppTheme.playerBlue,
                onTap: onSwitchCamera,
              ),
          ],
          showRemoveDartsHint: showRemoveDartsHint,
          hint: hint,
          zoom: currentZoom,
          minZoom: minZoom,
          maxZoom: maxZoom,
          onZoomIn: onZoomIn,
          onZoomOut: onZoomOut,
          bottomBar: captureButton,
        );

        // ── Visit label row: "VOTRE VOLÉE — TOUR n"  +  TOTAL ──
        final visitLabel = Row(
          children: [
            Expanded(
              child: Text(
                roundNumber != null
                    ? '${l10n.yourVisit} — ${l10n.roundChip(roundNumber!)}'
                    : l10n.yourVisit,
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
              total: turnTotal,
              color: AppTheme.playerBlueBright,
              text: visitTotalText,
            ),
          ],
        );

        // ── CONFIRM button: full-size in the X01 bottom row, narrow
        // vertical pill sharing the cricket chip row ──
        const compactConfirmPadding = WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 8),
        );
        const compactConfirmText = WidgetStatePropertyAll(
          TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
          ),
        );
        final confirmHighlighted = pendingConfirmation || manualConfirmNeeded;
        // Option C (2026-09-01) : quand la confirmation manuelle est requise,
        // le bouton CONFIRMER devient l'alerte — doré, texte sombre. L'or est
        // réservé à cet état pour qu'il tranche avec le bleu du jeu.
        final goldConfirmStyle = ElevatedButton.styleFrom(
          backgroundColor: AppTheme.accent,
          foregroundColor: AppTheme.gameBackground,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.5,
          ),
        );
        final baseConfirmStyle = manualConfirmNeeded
            ? goldConfirmStyle
            : confirmHighlighted
            ? gameFilledButtonStyle(AppTheme.playerBlue)
            : gameOutlineButtonStyle(AppTheme.playerBlue);
        final confirmStyle = confirmBesideChips
            ? baseConfirmStyle.copyWith(
                padding: compactConfirmPadding,
                textStyle: compactConfirmText,
              )
            : baseConfirmStyle;
        void handleConfirm() {
          HapticService.heavyImpact();
          onConfirm();
        }
        final confirmButton = confirmHighlighted
            ? ElevatedButton(
                onPressed: handleConfirm,
                style: confirmStyle,
                child: Text(l10n.confirmUpper),
              )
            : OutlinedButton(
                onPressed: handleConfirm,
                style: confirmStyle,
                child: Text(l10n.confirmUpper),
              );

        // ── Option C « confirme toi-même » : cible vide + 1 seule fléchette
        // comptée. Une ligne d'explication dorée + le bouton CONFIRMER MA
        // VOLÉE doré pleine largeur, qui remplace toute la rangée du bas
        // (X01). Cricket garde son bouton docké (passé en doré) et affiche la
        // ligne d'explication au-dessus des chips.
        final manualConfirmExplainerText = Text(
          l10n.manualConfirmExplainer,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppTheme.accent,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
            height: 1.25,
          ),
        );
        final manualConfirmColumn = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            manualConfirmExplainerText,
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: handleConfirm,
              style: goldConfirmStyle,
              icon: const Icon(Icons.touch_app, size: 17),
              label: Text(l10n.manualConfirmButton),
            ),
          ],
        );

        // ── The three visit chips (cricket: compact, with the CONFIRM
        // button docked to the row's right — 2026-08-19 "tableau" layout) ──
        Widget chipAt(int i) {
          final score = slots[i];
          return DartVisitChip(
            notation: score != null ? shortDartLabel(score) : null,
            accent: AppTheme.playerBlue,
            compact: confirmBesideChips,
            subtitle: score != null
                ? chipSubtitle?.call(i, shortDartLabel(score))
                : null,
            showEditLabel: score != null,
            capturing: scoringService.isCapturing,
            onTap: () => _editDart(context, i, score),
            onRemove:
                (onRemoveDart != null && score != null && i == lastFilledIndex)
                ? () {
                    HapticService.heavyImpact();
                    onRemoveDart!(i);
                  }
                : null,
          );
        }
        final chipsRow = SizedBox(
          height: confirmBesideChips ? 62 : 92,
          child: Row(
            children: [
              for (var i = 0; i < 3; i++) ...[
                if (i > 0) SizedBox(width: confirmBesideChips ? 8 : 10),
                Expanded(child: chipAt(i)),
              ],
              if (confirmBesideChips) ...[
                const SizedBox(width: 8),
                SizedBox(width: 94, child: confirmButton),
              ],
            ],
          ),
        );

        // ── X01 bottom row: AUTO VALIDATION chip + CONFIRM button ──
        final showAutoValidation =
            aiEnabled && (scoringService.isCapturing || pendingConfirmation);
        final bottomRow = IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: showAutoValidation
                    ? Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.gamePanelEmpty,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: AppTheme.playerBlueDim.withValues(
                              alpha: 0.5,
                            ),
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
                      )
                    : const SizedBox.shrink(),
              ),
              const SizedBox(width: 10),
              confirmButton,
            ],
          ),
        );

        if (isLandscape) {
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
                        if (header != null) ...[
                          header!,
                          const SizedBox(height: 12),
                        ],
                        if (manualConfirmNeeded && confirmBesideChips) ...[
                          manualConfirmExplainerText,
                          const SizedBox(height: 8),
                        ],
                        visitLabel,
                        const SizedBox(height: 8),
                        chipsRow,
                        if (confirmBesideChips) ...[
                          // Cricket: the table hugs the bottom of the column,
                          // mirroring the portrait stack; CONFIRM already
                          // lives on the chip row.
                          const Spacer(),
                          ?scorePanel,
                        ] else ...[
                          const Spacer(),
                          const SizedBox(height: 8),
                          if (manualConfirmNeeded)
                            manualConfirmColumn
                          else
                            bottomRow,
                        ],
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (header != null) ...[
                SizedBox(height: safeTop + 6),
                header!,
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: SizedBox(
                    height: gameCameraHeight(context),
                    child: cameraPanel,
                  ),
                ),
              ] else
                Padding(
                  padding: EdgeInsets.fromLTRB(12, safeTop + 4, 12, 0),
                  child: SizedBox(
                    height: gameCameraHeight(context),
                    child: cameraPanel,
                  ),
                ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    12,
                    confirmBesideChips ? 6 : 12,
                    12,
                    0,
                  ),
                  // Cricket portrait fills its budget to the last points
                  // (chips row + full table, no scroll fallback): clamp the
                  // text scale like the camera stack does, so accessibility
                  // sizes can't push the table past the home indicator.
                  child: MediaQuery.withClampedTextScaling(
                    maxScaleFactor: confirmBesideChips ? 1.1 : 2.0,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (manualConfirmNeeded && confirmBesideChips) ...[
                          manualConfirmExplainerText,
                          const SizedBox(height: 6),
                        ],
                        visitLabel,
                        const SizedBox(height: 8),
                        chipsRow,
                        if (scorePanel != null) ...[
                          const SizedBox(height: 6),
                          scorePanel!,
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              if (confirmBesideChips)
                SizedBox(height: safeBottom + 6)
              else
                Padding(
                  padding: EdgeInsets.fromLTRB(12, 8, 12, safeBottom + 10),
                  child: manualConfirmNeeded ? manualConfirmColumn : bottomRow,
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _editDart(
    BuildContext context,
    int index,
    DartScore? current,
  ) async {
    HapticService.lightImpact();
    // Pause AI capture while the edit modal is open so detections
    // don't overwrite the manual correction.
    scoringService.stopCapture();
    try {
      final result = await showDartboardEditModal(
        context,
        dartIndex: index,
        currentScore: current,
      );
      if (result != null) {
        // Order matters: onEditDart clears all slots on the server then
        // re-emits the edited dart.  overrideDart must come AFTER so the
        // local display isn't wiped by the clear.
        onEditDart?.call(index, result);
        scoringService.overrideDart(index, result);
      }
    } finally {
      // Always resume: a swipe-away/cancel notifies nothing, and relying on
      // the post-edit provider notify left capture stopped for the whole turn.
      onEditModalClosed?.call();
    }
  }
}

/// Compact notation for a detected dart ('T20', 'D25', 'MISS'…), shared by
/// the visit chips and the edit modal callers.
String shortDartLabel(DartScore score) {
  if (score.ring == 'double_bull') return 'D25';
  if (score.ring == 'single_bull') return 'S25';
  if (score.ring == 'triple') return 'T${score.segment}';
  if (score.ring == 'double') return 'D${score.segment}';
  if (score.ring == 'miss') return 'MISS';
  return 'S${score.segment}';
}
