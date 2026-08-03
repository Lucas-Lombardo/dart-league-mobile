import 'package:flutter/material.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import '../services/auto_scoring_service.dart';
import '../services/dart_scoring_service.dart';
import '../utils/app_theme.dart';
import '../utils/haptic_service.dart';
import '../l10n/app_localizations.dart';
import 'dartboard_edit_modal.dart';
import 'game_turn_ui.dart';

/// Full-screen auto-scoring layout for when it's the player's turn (maquette
/// layout): blue-bordered camera on top — sized by gameCameraHeight() so it
/// matches the opponent-turn camera exactly — then the visit chips, the
/// score bar and the AUTO VALIDATION + CONFIRM row.
class AutoScoreGameView extends StatelessWidget {
  final AutoScoringService scoringService;
  final VoidCallback onConfirm;
  final VoidCallback? onEndRoundEarly;
  final bool pendingConfirmation;
  final int myScore;
  final int opponentScore;
  final String opponentName;
  final String myName;
  final int dartsThrown;
  final RtcEngine? agoraEngine;
  final int? remoteUid;
  final String? agoraChannelName;
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
  final bool iAmPlayer2;
  final double? myAverage;
  final double? opponentAverage;
  final int startingScore;
  final int? roundNumber;
  final VoidCallback? onBack;
  /// The replay "record this turn" pill (built by the screen, which owns the
  /// capture flow) — rendered bottom-right of the camera panel.
  final Widget? captureButton;

  // BO3 series context for the score bar center ("BO3 · Manche 2" over the
  // colored legs score). Null for single-leg matches.
  final String? seriesTitle;
  final int myLegs;
  final int opponentLegs;

  const AutoScoreGameView({
    super.key,
    required this.scoringService,
    required this.onConfirm,
    this.onEndRoundEarly,
    required this.myScore,
    required this.opponentScore,
    required this.opponentName,
    required this.myName,
    this.pendingConfirmation = false,
    this.dartsThrown = 0,
    this.agoraEngine,
    this.remoteUid,
    this.agoraChannelName,
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
    this.iAmPlayer2 = false,
    this.myAverage,
    this.opponentAverage,
    this.startingScore = 501,
    this.roundNumber,
    this.captureButton,
    this.seriesTitle,
    this.myLegs = 0,
    this.opponentLegs = 0,
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
        final lastFilledIndex = slots.lastIndexWhere((s) => s != null);

        final safeTop = MediaQuery.of(context).padding.top;
        final safeBottom = MediaQuery.of(context).padding.bottom;
        final isLandscape =
            MediaQuery.of(context).orientation == Orientation.landscape;

        // ── Camera feed + overlay controls ──
        final cameraPanel = GameCameraPanel(
          videoView:
              localCameraPreview ??
              (agoraEngine != null
                  ? AgoraVideoView(
                      controller: VideoViewController(
                        rtcEngine: agoraEngine!,
                        canvas: const VideoCanvas(uid: 0),
                      ),
                    )
                  : null),
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
          cornerAction: captureButton,
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
            VisitTotal(total: turnTotal, color: AppTheme.playerBlueBright),
          ],
        );

        // ── The three visit chips ──
        final chipsRow = SizedBox(
          height: 92,
          child: Row(
            children: List.generate(3, (i) {
              final score = slots[i];
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(left: i == 0 ? 0 : 10),
                  child: DartVisitChip(
                    notation: score != null ? shortDartLabel(score) : null,
                    accent: AppTheme.playerBlue,
                    showEditLabel: score != null,
                    capturing: scoringService.isCapturing,
                    onTap: () => _editDart(context, i, score),
                    onRemove:
                        (onRemoveDart != null &&
                            score != null &&
                            i == lastFilledIndex)
                        ? () {
                            HapticService.heavyImpact();
                            onRemoveDart!(i);
                          }
                        : null,
                  ),
                ),
              );
            }),
          ),
        );

        final scoreBar = UserScoreBar(
          myName: myName,
          opponentName: opponentName,
          myScore: myScore,
          opponentScore: opponentScore,
          seriesTitle: seriesTitle,
          myLegs: myLegs,
          opponentLegs: opponentLegs,
        );

        // ── Bottom row: AUTO VALIDATION chip + CONFIRM button ──
        final showAutoValidation =
            aiEnabled && (scoringService.isCapturing || pendingConfirmation);
        final confirmButton = pendingConfirmation
            ? ElevatedButton(
                onPressed: () {
                  HapticService.heavyImpact();
                  onConfirm();
                },
                style: gameFilledButtonStyle(AppTheme.playerBlue),
                child: Text(l10n.confirmUpper),
              )
            : OutlinedButton(
                onPressed: () {
                  HapticService.heavyImpact();
                  onConfirm();
                },
                style: gameOutlineButtonStyle(AppTheme.playerBlue),
                child: Text(l10n.confirmUpper),
              );
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
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                visitLabel,
                                const SizedBox(height: 8),
                                chipsRow,
                                const SizedBox(height: 10),
                                scoreBar,
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(12, safeTop + 4, 12, 0),
                child: SizedBox(
                  height: gameCameraHeight(context),
                  child: cameraPanel,
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      visitLabel,
                      const SizedBox(height: 8),
                      chipsRow,
                      const SizedBox(height: 10),
                      scoreBar,
                    ],
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(12, 8, 12, safeBottom + 10),
                child: bottomRow,
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
