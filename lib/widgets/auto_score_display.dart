import 'package:flutter/material.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import '../services/auto_scoring_service.dart';
import '../services/dart_scoring_service.dart';
import '../utils/app_theme.dart';
import '../utils/haptic_service.dart';
import 'dartboard_edit_modal.dart';

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
  final bool isAudioMuted;
  final VoidCallback? onToggleAudio;
  final VoidCallback? onSwitchCamera;
  final VoidCallback? onZoomIn;
  final VoidCallback? onZoomOut;
  final double currentZoom;
  final double minZoom;
  final double maxZoom;
  final void Function(int index, DartScore score)? onEditDart;
  final VoidCallback? onToggleAi;
  final bool aiEnabled;

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
    this.isAudioMuted = true,
    this.onToggleAudio,
    this.onSwitchCamera,
    this.onZoomIn,
    this.onZoomOut,
    this.currentZoom = 1.0,
    this.minZoom = 1.0,
    this.maxZoom = 1.0,
    this.onEditDart,
    this.onToggleAi,
    this.aiEnabled = true,
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

        return Column(
          children: [
            // ── Camera feed ──
            Expanded(
              flex: 62,
              child: Stack(
                children: [
                  // Camera preview (local Agora video)
                  Container(
                    width: double.infinity,
                    color: Colors.black,
                    child: agoraEngine != null
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

                  // Zoom hint overlay (top)
                  if (hint != null)
                    Positioned(
                      top: 0,
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

                  // Zoom controls overlay (bottom-left)
                  if (agoraEngine != null && onZoomIn != null && onZoomOut != null)
                    Positioned(
                      bottom: 12,
                      left: 12,
                      child: Row(
                        children: [
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
                        ],
                      ),
                    ),

                  // Camera controls overlay (bottom-right)
                  if (agoraEngine != null)
                    Positioned(
                      bottom: 12,
                      right: 12,
                      child: Row(
                        children: [
                          if (onToggleAi != null) ...[
                            _CameraControlButton(
                              icon: aiEnabled ? Icons.smart_toy : Icons.smart_toy_outlined,
                              isActive: aiEnabled,
                              onTap: onToggleAi,
                              inactiveColor: AppTheme.textSecondary,
                            ),
                            const SizedBox(width: 8),
                          ],
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
                      ),
                    ),
                ],
              ),
            ),

            // ── Scoring panel ──
            Expanded(
              flex: 38,
              child: Container(
                color: AppTheme.background,
                child: Column(
                  children: [
                    // 3 dart indicators
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 10, 24, 0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(3, (i) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: _DartIndicator(
                              index: i,
                              score: slots[i],
                              isCapturing: scoringService.isCapturing,
                              onTap: () => _editDart(context, i, slots[i]),
                            ),
                          );
                        }),
                      ),
                    ),

                    const SizedBox(height: 6),

                    // Dashed separator
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: CustomPaint(
                        size: const Size(double.infinity, 1),
                        painter: _DashedLinePainter(),
                      ),
                    ),

                    // Score section — my score only, centered
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Big score
                          Text(
                            '$myScore',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 52,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'monospace',
                              height: 1,
                            ),
                          ),
                          const SizedBox(height: 6),
                          // Turn total box
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppTheme.surface,
                              borderRadius: BorderRadius.circular(10),
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
                                  'TURN: ',
                                  style: TextStyle(
                                    color: AppTheme.textSecondary.withValues(alpha: 0.6),
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  '$turnTotal',
                                  style: TextStyle(
                                    color: turnTotal > 0 ? AppTheme.primary : Colors.white30,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Confirm / End Round Early button
                    Container(
                      padding: const EdgeInsets.all(12),
                      color: AppTheme.surface,
                      child: noDartsDetected && onEndRoundEarly != null
                          ? SizedBox(
                              width: double.infinity,
                              height: 52,
                              child: ElevatedButton(
                                onPressed: () {
                                  HapticService.heavyImpact();
                                  onEndRoundEarly!();
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.surfaceLight,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.skip_next, size: 20),
                                    SizedBox(width: 8),
                                    Text(
                                      'END ROUND EARLY',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 1,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : SizedBox(
                              width: double.infinity,
                              height: 52,
                              child: ElevatedButton(
                                onPressed: () {
                                  HapticService.heavyImpact();
                                  onConfirm();
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: pendingConfirmation
                                      ? AppTheme.primary
                                      : AppTheme.primary.withValues(alpha: 0.5),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      pendingConfirmation ? 'CONFIRM & END TURN' : 'END TURN',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 1,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    const Icon(Icons.check_circle_outline, size: 20),
                                  ],
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _editDart(BuildContext context, int index, DartScore? current) async {
    HapticService.lightImpact();
    final result = await showDartboardEditModal(
      context,
      dartIndex: index,
      currentScore: current,
    );
    if (result != null) {
      scoringService.overrideDart(index, result);
      onEditDart?.call(index, result);
    }
  }
}

// ── Dart indicator (small circle icon with score) ──

class _DartIndicator extends StatelessWidget {
  final int index;
  final DartScore? score;
  final bool isCapturing;
  final VoidCallback onTap;

  const _DartIndicator({
    required this.index,
    required this.score,
    required this.isCapturing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasScore = score != null;

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Dart icon
          Container(
            width: 56,
            height: 56,
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
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          height: 1,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${score!.score}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          height: 1,
                        ),
                      ),
                    ],
                  )
                : isCapturing
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppTheme.textSecondary.withValues(alpha: 0.3),
                        ),
                      )
                    : const Icon(
                        Icons.add,
                        color: AppTheme.textSecondary,
                        size: 20,
                      ),
          ),
          const SizedBox(height: 4),
          // Label
          Text(
            hasScore ? 'EDIT' : 'Dart ${index + 1}',
            style: TextStyle(
              color: hasScore
                  ? AppTheme.primary.withValues(alpha: 0.7)
                  : AppTheme.textSecondary.withValues(alpha: 0.5),
              fontSize: 9,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ],
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
  final Color? inactiveColor;

  const _CameraControlButton({
    required this.icon,
    required this.isActive,
    this.onTap,
    this.inactiveColor,
  });

  @override
  Widget build(BuildContext context) {
    final offColor = inactiveColor ?? AppTheme.error;
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

// ── Dashed line painter ──

class _DashedLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppTheme.surfaceLight.withValues(alpha: 0.4)
      ..strokeWidth = 1;

    const dashWidth = 6.0;
    const dashSpace = 4.0;
    double x = 0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0), Offset(x + dashWidth, 0), paint);
      x += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
