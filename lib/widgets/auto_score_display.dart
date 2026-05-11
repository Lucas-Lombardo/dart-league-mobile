import 'dart:math' show min;
import 'package:flutter/material.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import '../services/auto_scoring_service.dart';
import '../services/dart_scoring_service.dart';
import '../utils/app_theme.dart';
import '../utils/haptic_service.dart';
import '../utils/score_converter.dart';
import '../l10n/app_localizations.dart';
import 'dartboard_edit_modal.dart';
import 'tv_scoreboard.dart';

/// Full-screen auto-scoring layout for when it's the player's turn.
/// Camera feed on top (~55%), dart indicators + score panel below, confirm button.
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
  final VoidCallback? onToggleAi;
  final bool aiEnabled;
  final bool iAmPlayer2;
  final double? myAverage;
  final double? opponentAverage;

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
    this.onToggleAi,
    this.aiEnabled = true,
    this.iAmPlayer2 = false,
    this.myAverage,
    this.opponentAverage,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: scoringService,
      builder: (context, _) {
        final slots = scoringService.dartSlots;
        final turnTotal = scoringService.turnTotal;
        final hint = scoringService.zoomHint;
        final noDartsDetected = slots.every((s) => s == null);
        final lastFilledIndex = slots.lastIndexWhere((s) => s != null);

        final safeTop = MediaQuery.of(context).padding.top;

        return Column(
          children: [
            // ── Camera feed + all overlay controls ──
            // The native camera preview is a platform view that renders ABOVE
            // sibling Flutter widgets earlier in the tree, so every control
            // has to live inside this Stack (after the camera Container) to
            // be visible. We overlay them at the top with semi-transparent
            // backgrounds; they sit over the wall area above the dartboard
            // rather than the board itself.
            Expanded(
              flex: 50,
              child: Stack(
                children: [
                  Container(
                    width: double.infinity,
                    height: double.infinity,
                    color: Colors.black,
                    child: localCameraPreview != null
                        ? localCameraPreview!
                        : agoraEngine != null
                            ? AgoraVideoView(
                                controller: VideoViewController(
                                  rtcEngine: agoraEngine!,
                                  canvas: const VideoCanvas(uid: 0),
                                ),
                              )
                            : const Center(
                                child: Icon(
                                  Icons.videocam_off,
                                  color: Colors.white24,
                                  size: 48,
                                ),
                              ),
                  ),

                  // Zoom hint overlay
                  if (hint != null)
                    Positioned(
                      top: safeTop + 4,
                      left: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.7),
                              Colors.transparent,
                            ],
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.camera_alt, color: AppTheme.accent, size: 16),
                            const SizedBox(width: 8),
                            Text(
                              hint,
                              style: const TextStyle(
                                color: AppTheme.accent,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // ── Primary action pill (top-right, aligned with back) ──
                  // Single contextual button. Label & icon shift with state:
                  //  • no darts        → END ROUND EARLY (skip icon)
                  //  • darts detected  → END TURN (check icon)
                  //  • pending confirm → CONFIRM & END TURN (filled primary)
                  Positioned(
                    top: safeTop + 8,
                    right: 12,
                    child: GestureDetector(
                      onTap: () {
                        HapticService.heavyImpact();
                        onConfirm();
                      },
                      child: Container(
                        height: 36,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: pendingConfirmation
                              ? AppTheme.primary
                              : Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(18),
                          border: pendingConfirmation
                              ? null
                              : Border.all(
                                  color: Colors.white.withValues(alpha: 0.2),
                                ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              noDartsDetected
                                  ? Icons.skip_next
                                  : Icons.check_circle_outline,
                              size: 16,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              noDartsDetected
                                  ? AppLocalizations.of(context).endRoundEarlyUpper
                                  : pendingConfirmation
                                      ? AppLocalizations.of(context).confirmAndEndTurn
                                      : AppLocalizations.of(context).endTurnUpper,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // ── Camera controls (zoom / mic / cam switch) ──
                  // Anchored to the bottom-right of the camera area so they
                  // sit over the wall below the dartboard, well clear of the
                  // top-right action pill. Each subgroup decides its own
                  // visibility from its callbacks/state.
                  Positioned(
                    bottom: 12,
                    right: 12,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (onZoomIn != null && onZoomOut != null) ...[
                          _ZoomButton(
                            icon: Icons.remove,
                            onTap: currentZoom > minZoom ? onZoomOut : null,
                          ),
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${currentZoom.toStringAsFixed(1)}x',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          _ZoomButton(
                            icon: Icons.add,
                            onTap: currentZoom < maxZoom ? onZoomIn : null,
                          ),
                          const SizedBox(width: 8),
                        ],
                        if (agoraEngine != null) ...[
                          _CameraControlButton(
                            icon: isAudioMuted ? Icons.mic_off : Icons.mic,
                            isActive: !isAudioMuted,
                            onTap: onToggleAudio,
                          ),
                          const SizedBox(width: 8),
                          _CameraControlButton(
                            icon: Icons.cameraswitch,
                            isActive: true,
                            onTap: onSwitchCamera,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── Scoring panel ──
            Expanded(
              flex: 50,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final safeBottom = MediaQuery.of(context).padding.bottom;
                  final screenH = MediaQuery.of(context).size.height;
                  final isSmallScreen = screenH < 700;
                  final availableH = constraints.maxHeight;
                  // No bottom button anymore — the End-Turn / End-Round-Early
                  // action lives in the top-right pill regardless of state,
                  // freeing the bottom region for the score readout.
                  final buttonH = safeBottom;
                  final contentH = availableH - buttonH;
                  // Even smaller indicator allotment so the scoreboard grows
                  // substantially — readable from ~2m.
                  final indicatorH = (contentH * 0.24).clamp(50.0, 72.0);
                  final hintStr = (myScore >= 2 && myScore <= 170) ? checkoutHint(myScore) : null;
                  final hintParts = hintStr?.split(' ') ?? [];

                  return Container(
                    color: AppTheme.background,
                    child: Column(
                      children: [
                        // 3 dart indicators
                        SizedBox(
                          height: indicatorH,
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(12, isSmallScreen ? 2 : 4, 12, 0),
                            child: Row(
                              children: List.generate(3, (i) {
                                // Place suggestions only under empty dart slots,
                                // starting from the first empty slot.
                                final suggestionIdx = i - (lastFilledIndex + 1);
                                final suggestion = (slots[i] == null &&
                                        suggestionIdx >= 0 &&
                                        suggestionIdx < hintParts.length)
                                    ? hintParts[suggestionIdx]
                                    : '';
                                return Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 4),
                                    child: _DartIndicator(
                                      index: i,
                                      score: slots[i],
                                      isCapturing: scoringService.isCapturing,
                                      onTap: () => _editDart(context, i, slots[i]),
                                      onRemove: (onRemoveDart != null && i == lastFilledIndex)
                                          ? () => onRemoveDart!(i)
                                          : null,
                                      suggestion: suggestion,
                                    ),
                                  ),
                                );
                              }),
                            ),
                          ),
                        ),

                        // Turn total
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.surface,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: turnTotal > 0
                                  ? AppTheme.primary.withValues(alpha: 0.5)
                                  : AppTheme.surfaceLight.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${AppLocalizations.of(context).turnLabel} ',
                                style: TextStyle(
                                  color: AppTheme.textSecondary.withValues(alpha: 0.6),
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                '$turnTotal',
                                style: TextStyle(
                                  color: turnTotal > 0 ? AppTheme.primary : Colors.white30,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // TV Scoreboard — fills remaining space
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(12, 2, 12, 2),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.center,
                              child: SizedBox(
                                width: constraints.maxWidth - 24,
                                child: TvScoreboard(
                                  myScore: myScore,
                                  opponentScore: opponentScore,
                                  myName: myName,
                                  opponentName: opponentName,
                                  isMyTurn: true,
                                  iAmPlayer2: iAmPlayer2,
                                  myAverage: myAverage,
                                  opponentAverage: opponentAverage,
                                ),
                              ),
                            ),
                          ),
                        ),

                        // Only reserve the system safe-area at the bottom —
                        // the action button now lives in the top-right pill.
                        SizedBox(height: safeBottom),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _editDart(BuildContext context, int index, DartScore? current) async {
    HapticService.lightImpact();
    // Pause AI capture while the edit modal is open so detections
    // don't overwrite the manual correction.
    scoringService.stopCapture();
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
    // Capture restarts automatically via handleSharedStateChange
    // when the game state updates after editDartThrow.
  }
}

// ── Dart indicator (small circle icon with score) ──

class _DartIndicator extends StatelessWidget {
  final int index;
  final DartScore? score;
  final bool isCapturing;
  final VoidCallback onTap;
  final VoidCallback? onRemove;
  final String suggestion;

  const _DartIndicator({
    required this.index,
    required this.score,
    required this.isCapturing,
    required this.onTap,
    this.onRemove,
    this.suggestion = '',
  });

  @override
  Widget build(BuildContext context) {
    final hasScore = score != null;

    return GestureDetector(
      onTap: onTap,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Always reserve the same space so all 3 circles are identical size
          const reservedForText = 36.0;
          final widthBased = constraints.maxWidth * 0.82;
          final heightBased = constraints.maxHeight - reservedForText;
          final size = min(widthBased, heightBased).clamp(44.0, 84.0);
          final labelSize = (size * 0.32).clamp(14.0, 26.0);
          final subSize = (size * 0.20).clamp(10.0, 15.0);
          final iconSize = (size * 0.36).clamp(18.0, 28.0);
          final badgeSize = (size * 0.30).clamp(18.0, 26.0);

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: size,
                height: size,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: size,
                      height: size,
                      decoration: BoxDecoration(
                        color: hasScore
                            ? AppTheme.primary.withValues(alpha: 0.15)
                            : AppTheme.surface,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: hasScore ? AppTheme.primary : AppTheme.surfaceLight,
                          width: 2,
                        ),
                      ),
                      child: hasScore
                          ? Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  _shortLabel(score!),
                                  style: TextStyle(
                                    color: _scoreLabelColor(score!),
                                    fontSize: labelSize,
                                    fontWeight: FontWeight.bold,
                                    height: 1,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${score!.score}',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: subSize,
                                    fontWeight: FontWeight.w500,
                                    height: 1,
                                  ),
                                ),
                              ],
                            )
                          : isCapturing
                              ? SizedBox(
                                  width: iconSize,
                                  height: iconSize,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppTheme.textSecondary.withValues(alpha: 0.3),
                                  ),
                                )
                              : Icon(
                                  Icons.add,
                                  color: AppTheme.textSecondary,
                                  size: iconSize,
                                ),
                    ),
                    if (onRemove != null)
                      Positioned(
                        top: -4,
                        right: -4,
                        child: GestureDetector(
                          onTap: () {
                            HapticService.heavyImpact();
                            onRemove!();
                          },
                          child: Container(
                            width: badgeSize,
                            height: badgeSize,
                            decoration: const BoxDecoration(
                              color: AppTheme.error,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.close, size: badgeSize * 0.55, color: Colors.white),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 2),
              Text(
                hasScore ? AppLocalizations.of(context).editLabel : AppLocalizations.of(context).dartNumber(index + 1),
                style: TextStyle(
                  color: hasScore
                      ? AppTheme.primary.withValues(alpha: 0.7)
                      : AppTheme.textSecondary.withValues(alpha: 0.5),
                  fontSize: (size * 0.16).clamp(9.0, 12.0),
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 1),
              // Always same height so all circles stay the same size
              SizedBox(
                height: (size * 0.20).clamp(10.0, 16.0) + 2,
                child: suggestion.isNotEmpty
                    ? Text(
                        suggestion,
                        style: TextStyle(
                          color: AppTheme.success,
                          fontSize: (size * 0.22).clamp(12.0, 18.0),
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      )
                    : null,
              ),
            ],
          );
        },
      ),
    );
  }

  static String _shortLabel(DartScore score) {
    if (score.ring == 'double_bull') return 'D25';
    if (score.ring == 'single_bull') return 'S25';
    if (score.ring == 'triple') return 'T${score.segment}';
    if (score.ring == 'double') return 'D${score.segment}';
    if (score.ring == 'miss') return 'MISS';
    return 'S${score.segment}';
  }

  static Color _scoreLabelColor(DartScore score) {
    if (score.ring == 'triple') return AppTheme.error;
    if (score.ring == 'double' || score.ring == 'double_bull') return AppTheme.success;
    if (score.ring == 'single_bull') return AppTheme.accent;
    if (score.ring == 'miss') return AppTheme.error;
    return AppTheme.textSecondary;
  }
}

// ── Small camera control button ──

class _CameraControlButton extends StatelessWidget {
  final IconData icon;
  final bool isActive;
  final VoidCallback? onTap;

  const _CameraControlButton({
    required this.icon,
    required this.isActive,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const offColor = AppTheme.error;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.5),
          shape: BoxShape.circle,
          border: Border.all(
            color: isActive
                ? Colors.white.withValues(alpha: 0.3)
                : offColor.withValues(alpha: 0.5),
          ),
        ),
        child: Icon(
          icon,
          color: isActive ? Colors.white : offColor,
          size: 18,
        ),
      ),
    );
  }
}

// ── Zoom button (+/-) ──

class _ZoomButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _ZoomButton({
    required this.icon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isEnabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.5),
          shape: BoxShape.circle,
          border: Border.all(
            color: isEnabled
                ? Colors.white.withValues(alpha: 0.3)
                : Colors.white.withValues(alpha: 0.1),
          ),
        ),
        child: Icon(
          icon,
          color: isEnabled ? Colors.white : Colors.white30,
          size: 18,
        ),
      ),
    );
  }
}

