import 'dart:async';
import 'package:flutter/material.dart';
import '../models/opponent_dart_zoom.dart';
import '../services/dart_detection_types.dart';
import '../utils/app_theme.dart';
import '../utils/haptic_service.dart';
import '../l10n/app_localizations.dart';
import 'board_safe_video.dart';
import 'design_system.dart';
import 'logo_watermark.dart';

/// Shared building blocks of the in-match UI (system D, 2026-09): the flat
/// slate surfaces, hairline borders and Manrope scale of the rest of the app,
/// plus the one thing only the match screens have — a blue (me) vs rose
/// (opponent) identity. Both turn layouts — AutoScoreGameView (your turn) and
/// the opponent-turn screen — compose these widgets so the two states stay
/// visually consistent.

/// Icon tint of a quiet camera control.
const Color _controlIcon = Color(0xFFE2E8F0);

/// Hairline drawn over video (controls, pills, docked bars).
const Color _glassBorder = Color(0x1AFFFFFF);

/// Height of the camera panel in portrait, IDENTICAL on your turn and the
/// opponent's turn so the video feed never resizes when the turn flips.
/// Derived from the screen height minus the vertical chrome each layout needs
/// below/above the camera, clamped so it neither collapses on small phones
/// nor starves the scoring panels on tall ones.
/// Height of the badge row docked on the opponent feed (back button, logo
/// bug, mic/camera controls: top 10 + 40 px + a hair). The
/// received board square is fitted BELOW it, so the top of the board is never
/// under a badge — the same whole board in portrait and in landscape.
const double kOpponentFeedBadgeRowHeight = 52;

double gameCameraHeight(BuildContext context) {
  final mq = MediaQuery.of(context);
  final h = mq.size.height;
  final reserved = 340.0 + mq.padding.top + mq.padding.bottom;
  return (h - reserved).clamp(h * 0.32, h * 0.54);
}

/// Points value of a backend dart notation ('S20' → 20, 'T20' → 60, 'D25' →
/// 50, 'MISS' → 0). Mirrors GameProvider.currentRoundScore parsing.
int notationPoints(String notation) {
  if (notation.length < 2) return 0;
  final base = int.tryParse(notation.substring(1)) ?? 0;
  switch (notation[0]) {
    case 'S':
      return base;
    case 'D':
      return base * 2;
    case 'T':
      return base * 3;
    default:
      return 0;
  }
}

int visitPoints(Iterable<String> throws) =>
    throws.fold(0, (total, dart) => total + notationPoints(dart));

/// Live pending_bust replaces the final score_updated: earlier darts have
/// reduced the score, but the busting dart exists only in the pending payload.
/// Syncs and edits have different snapshots and cannot use this reconstruction.
({int remaining, int visitTotal})? pendingBustFigures({
  required int currentScore,
  required int currentRoundScore,
  required Map<String, dynamic>? pendingData,
}) {
  final notation = pendingData?['notation'] as String?;
  if (pendingData?['restoredFromSync'] == true ||
      notation == null || notation.isEmpty) {
    return null;
  }
  return (
    remaining: currentScore + currentRoundScore,
    visitTotal: currentRoundScore + notationPoints(notation),
  );
}

class GameBustDialogContent extends StatelessWidget {
  final String reason;
  final int? remaining;
  final int? visitTotal;

  const GameBustDialogContent({
    super.key,
    required this.reason,
    this.remaining,
    this.visitTotal,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(reason, style: gameDialogBodyStyle),
        if (remaining != null && visitTotal != null) ...[
          const SizedBox(height: 6),
          Text(l10n.bustFigures(remaining!, visitTotal!),
              style: gameDialogHintStyle),
        ],
        const SizedBox(height: 6),
        Text(l10n.confirmPassOrEdit, style: gameDialogHintStyle),
      ],
    );
  }
}

/// Small group-label pill over video ("VOUS", "TOUR 26"): 11 / 700 spaced
/// label on a translucent background with a glass hairline.
class GameChip extends StatelessWidget {
  final String text;
  final Color color;

  const GameChip({super.key, required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppTheme.gameBackground.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _glassBorder),
      ),
      child: Text(
        text,
        style: AppTheme.labelSmall.copyWith(color: color, height: 1),
      ),
    );
  }
}

/// "EN DIRECT" pill shown on a live camera feed (spectator screens): the
/// rose live dot on a quiet tinted pill.
class LiveBadge extends StatelessWidget {
  const LiveBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppTheme.gameBackground.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _glassBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: AppTheme.secondary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            AppLocalizations.of(context).liveBadge,
            style: AppTheme.labelSmall.copyWith(
              color: AppTheme.textPrimary,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

/// Opaque 40 px camera control, readable even over a brightly lit board.
/// The icon and border identify the active state without changing its size.
class GameControlButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final bool active;

  const GameControlButton({
    super.key,
    required this.icon,
    this.color = _controlIcon,
    this.onTap,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppTheme.gameBackground,
          shape: BoxShape.circle,
          border: Border.all(
            color: active
                ? AppTheme.primaryLight
                : AppTheme.textTertiary,
          ),
        ),
        child: Icon(
          icon,
          color: active ? AppTheme.primaryLight : color,
          size: 22,
        ),
      ),
    );
  }
}

/// "− 1,9× +" zoom pill anchored to the bottom of the local camera feed:
/// 34 px, translucent background, glass hairline, 13 / 700 value.
class ZoomPill extends StatelessWidget {
  final double zoom;
  final double minZoom;
  final double maxZoom;
  final VoidCallback? onZoomIn;
  final VoidCallback? onZoomOut;

  const ZoomPill({
    super.key,
    required this.zoom,
    required this.minZoom,
    required this.maxZoom,
    this.onZoomIn,
    this.onZoomOut,
  });

  @override
  Widget build(BuildContext context) {
    Widget btn(IconData icon, VoidCallback? onTap, Color color) =>
        GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Icon(
              icon,
              size: 14,
              color: onTap != null ? color : AppTheme.textTertiary,
            ),
          ),
        );
    return Container(
      height: 34,
      decoration: BoxDecoration(
        color: AppTheme.gameBackground.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _glassBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          btn(
            Icons.remove_rounded,
            zoom > minZoom ? onZoomOut : null,
            AppTheme.textSecondary,
          ),
          Text(
            '${zoom.toStringAsFixed(1)}×',
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              height: 1,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          btn(
            Icons.add_rounded,
            zoom < maxZoom ? onZoomIn : null,
            AppTheme.textPrimary,
          ),
        ],
      ),
    );
  }
}

/// The camera panel every AI-scored mode renders on top of its layout: the
/// video feed, the colored border, the brand bug, a back button, the top-right
/// controls, the camera guidance pills and the zoom pill.
///
/// Shared by [AutoScoreGameView] (ranked / friendly / bot training) and
/// TrainingGameView (solo drills) so the feed looks identical everywhere.
///
/// [videoView] stays a plain widget — the caller builds the remote renderer or
/// the local preview — so this file never has to depend on the RTC engine.
class GameCameraPanel extends StatelessWidget {
  final Widget? videoView;
  final Color borderColor;
  final VoidCallback? onBack;

  /// Top-right controls (mic, camera flip, AI toggle…). Spacing is inserted
  /// between them here so callers just list the buttons they want.
  final List<Widget> controls;

  /// Amber "take your darts off the board" pill — only shown once the AI has
  /// actually seen leftover darts.
  final bool showRemoveDartsHint;

  /// The AI's zoom/detection hint, shown under the remove-darts pill.
  /// Semantic value from the scorer — localized here at render time.
  final ZoomHint? hint;

  final double zoom;
  final double minZoom;
  final double maxZoom;
  final VoidCallback? onZoomIn;
  final VoidCallback? onZoomOut;

  /// Full-width bar docked to the panel's bottom edge (the replay capture
  /// button). When present, the zoom pill slides up above it.
  final Widget? bottomBar;

  const GameCameraPanel({
    super.key,
    this.videoView,
    this.borderColor = AppTheme.playerBlue,
    this.onBack,
    this.controls = const [],
    this.showRemoveDartsHint = false,
    this.hint,
    this.zoom = 1.0,
    this.minZoom = 1.0,
    this.maxZoom = 1.0,
    this.onZoomIn,
    this.onZoomOut,
    this.bottomBar,
  });

  Widget _hintTextPill(AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.gameBackground.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.photo_camera_outlined,
            color: AppTheme.textSecondary,
            size: 15,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              switch (hint!) {
                ZoomHint.dartboardNotDetected => l10n.dartboardNotDetected,
                ZoomHint.boardNotFullyVisible => l10n.boardNotFullyVisible,
                ZoomHint.zoomIn => l10n.zoomInBoardTooFar,
                ZoomHint.zoomOut => l10n.zoomOutBoardTooClose,
              },
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // The native camera preview is a platform view that renders ABOVE sibling
    // Flutter widgets earlier in the tree, so every control has to live inside
    // this Stack (after the video Container) to be visible.
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            color: videoView == null ? AppTheme.gamePanelEmpty : Colors.black,
            child:
                videoView ??
                const Center(
                  child: Icon(
                    Icons.videocam_off_outlined,
                    color: AppTheme.textSecondary,
                    size: 40,
                  ),
                ),
          ),

          // ── Identity border: blue on my turn, rose on the opponent's. This
          // 1.5 px line IS the turn cue; nothing else on the panel changes.
          IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: borderColor, width: 1.5),
                borderRadius: BorderRadius.circular(AppTheme.radiusCard),
              ),
            ),
          ),

          // ── Bad-framing alert: pulsing amber ring over the whole panel,
          // readable in peripheral vision while aiming (the pill below
          // carries the words, this carries the urgency).
          if (hint == ZoomHint.zoomIn || hint == ZoomHint.zoomOut)
            const Positioned.fill(
              child: IgnorePointer(child: PulsingFrameBorder()),
            ),

          // ── Brand bug (top center), like a TV channel logo ──
          const Positioned(
            top: 12,
            left: 0,
            right: 0,
            child: Center(child: LogoWatermark()),
          ),

          // ── Back button (top-left, styled like the other controls) ──
          if (onBack != null)
            Positioned(
              top: 10,
              left: 10,
              child: GameControlButton(
                icon: Icons.arrow_back_ios_new_rounded,
                onTap: onBack,
              ),
            ),

          // ── Mic / camera / AI controls (top-right) ──
          if (controls.isNotEmpty)
            Positioned(
              top: 10,
              right: 10,
              child: Row(
                children: [
                  for (var i = 0; i < controls.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    controls[i],
                  ],
                ],
              ),
            ),

          // ── Camera guidance pills, dead center of the panel:
          // "remove your darts" while the empty-board gate is armed, and the
          // AI's zoom/detection hint. They used to sit above the zoom pill,
          // where the two overlapped and neither could be read (2026-08-14);
          // the middle is also the one spot that can't collide with the
          // controls pinned to the panel's edges. IgnorePointer so a pill
          // over the video never eats a pinch-zoom.
          if (showRemoveDartsHint || hint != null)
            Positioned.fill(
              child: IgnorePointer(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Gold on purpose: this is the one warning the
                        // player must act on before throwing.
                        if (showRemoveDartsHint)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.accent,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.warning_amber_rounded,
                                  color: AppTheme.background,
                                  size: 16,
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    l10n.removeDartsFromBoardHint,
                                    style: const TextStyle(
                                      color: AppTheme.background,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (showRemoveDartsHint && hint != null)
                          const SizedBox(height: 8),
                        if (hint != null) _hintTextPill(l10n),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // ── Bottom stack: zoom pill over the docked capture bar. One
          // column so the pill slides up when the bar appears below it. Text
          // scale is clamped so accessibility sizes can't silently push the
          // stack past the panel's top edge (the Positioned column has
          // unbounded height and ClipRRect would cut it without any overflow
          // warning).
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.2,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (onZoomIn != null && onZoomOut != null)
                    Padding(
                      padding: EdgeInsets.only(
                        bottom: bottomBar != null ? 8 : 12,
                      ),
                      child: Center(
                        child: ZoomPill(
                          zoom: zoom,
                          minZoom: minZoom,
                          maxZoom: maxZoom,
                          onZoomIn: onZoomIn,
                          onZoomOut: onZoomOut,
                        ),
                      ),
                    ),
                  ?bottomBar,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The replay capture bar, docked full-width to the bottom edge of MY
/// camera panel while my turn has something to record (piste D of the
/// 2026-08-03 design round: the floating pill was invisible over video).
/// Manages its own tap lifecycle: idle → saving (spinner) → saved (check,
/// 2.5s) → idle.
class ReplayCaptureButton extends StatefulWidget {
  /// Cuts the clip; returns true when a clip file was produced.
  final Future<bool> Function() onCapture;

  const ReplayCaptureButton({super.key, required this.onCapture});

  @override
  State<ReplayCaptureButton> createState() => _ReplayCaptureButtonState();
}

enum _CaptureState { idle, saving, saved }

class _ReplayCaptureButtonState extends State<ReplayCaptureButton> {
  _CaptureState _state = _CaptureState.idle;

  Future<void> _tap() async {
    if (_state != _CaptureState.idle) return;
    HapticService.lightImpact();
    setState(() => _state = _CaptureState.saving);
    final ok = await widget.onCapture();
    if (!mounted) return;
    setState(() => _state = ok ? _CaptureState.saved : _CaptureState.idle);
    if (ok) {
      Future.delayed(const Duration(milliseconds: 2500), () {
        if (mounted) setState(() => _state = _CaptureState.idle);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final saved = _state == _CaptureState.saved;
    final foreground = saved ? AppTheme.success : AppTheme.primaryLight;
    return GestureDetector(
      onTap: _tap,
      child: DockedBar(
        color: foreground,
        leading: _state == _CaptureState.saving
            ? SizedBox(
                width: 15,
                height: 15,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: foreground,
                ),
              )
            : Icon(
                saved
                    ? Icons.check_circle_outline_rounded
                    : Icons.movie_outlined,
                size: 16,
                color: foreground,
              ),
        label: dsSentence(saved ? l10n.replaySaved : l10n.replayCapture),
      ),
    );
  }
}

/// The 46 px bar docked to the bottom edge of the camera panel (replay
/// capture, visit report): translucent background, top hairline, a 16 px
/// icon and a 13 / 700 label centred in [color]. No fill, no gradient — the
/// colour of the text alone says which of the two bars this is.
class DockedBar extends StatelessWidget {
  final Widget leading;
  final String label;
  final Color color;

  const DockedBar({
    super.key,
    required this.leading,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppTheme.gameBackground.withValues(alpha: 0.86),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          leading,
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                height: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The report bar, in the SAME slot as [ReplayCaptureButton] — the bottom edge
/// of my camera panel. That slot is empty until my first dart of the visit
/// (the capture button has nothing to record yet), which is exactly the window
/// where flagging my opponent's previous visit makes sense: their visit is
/// complete, its score is on screen, and I haven't started throwing.
///
/// Red rather than the capture bar's blue: same shape, same place, opposite
/// colour — the two gestures can't be confused even without reading.
///
/// One tap arms it, then a 4-second window to undo. Nothing is asked of the
/// opponent's device until that window closes, so a mis-tap costs nothing. The
/// window is deliberately NOT a confirmation dialog: a modal mid-visit loses
/// the camera and the AI, and a feature nobody can afford to open is a feature
/// nobody uses.
class TurnFlagButton extends StatefulWidget {
  /// Fires when the undo window closes — this is what actually posts the flag.
  final VoidCallback onConfirmed;

  /// Score of the visit being flagged, shown in the label so the target is
  /// unambiguous. Null renders the label without it (bust, unknown).
  final int? volleyScore;

  /// Already flagged this visit: inert until my first dart swaps the bar.
  final bool alreadyFlagged;

  const TurnFlagButton({
    super.key,
    required this.onConfirmed,
    this.volleyScore,
    this.alreadyFlagged = false,
  });

  @override
  State<TurnFlagButton> createState() => _TurnFlagButtonState();
}

class _TurnFlagButtonState extends State<TurnFlagButton> {
  /// Lucas's spec (2026-08-13). Long enough to catch a mis-tap, short enough
  /// that the flag is gone before the visit is.
  static const Duration _undoWindow = Duration(seconds: 4);

  Timer? _countdown;
  int _remaining = 0;
  bool _sent = false;

  @override
  void dispose() {
    _countdown?.cancel();
    super.dispose();
  }

  void _tap() {
    if (_sent || widget.alreadyFlagged) return;
    HapticService.mediumImpact();
    if (_countdown != null) {
      // Second tap inside the window: cancel. Nothing was ever asked of the
      // opponent's device, so there is nothing to take back.
      _countdown!.cancel();
      _countdown = null;
      setState(() => _remaining = 0);
      return;
    }
    setState(() => _remaining = _undoWindow.inSeconds);
    _countdown = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _remaining--);
      if (_remaining <= 0) {
        timer.cancel();
        _countdown = null;
        _confirm();
      }
    });
  }

  /// Also called from outside the countdown: throwing a dart commits the flag
  /// rather than leaving a decision hanging while the player aims.
  void _confirm() {
    if (_sent) return;
    setState(() => _sent = true);
    widget.onConfirmed();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final counting = _countdown != null;
    final done = _sent || widget.alreadyFlagged;

    final String label;
    if (done) {
      label = l10n.flagVisitSent;
    } else if (counting) {
      label = l10n.flagVisitUndo(_remaining);
    } else if (widget.volleyScore != null) {
      label = l10n.flagVisitWithScore(widget.volleyScore!);
    } else {
      label = l10n.flagVisit;
    }

    // Rose = armed / counting (the undo window dims it a notch), green +
    // check once the flag is posted.
    final color = done
        ? AppTheme.success
        : counting
        ? AppTheme.opponentPinkBright
        : AppTheme.opponentPink;

    return GestureDetector(
      onTap: _tap,
      child: DockedBar(
        color: color,
        leading: Icon(
          done ? Icons.check_circle_outline_rounded : Icons.flag_outlined,
          size: 16,
          color: color,
        ),
        label: dsSentence(label),
      ),
    );
  }
}

/// Both averages stay visible on the existing center line. The fixed left /
/// right order and player colours match the scores above, even before one
/// player has completed a visit. No animation or interaction on the tripod.
class TurnAverages extends StatelessWidget {
  final double? myAverage;
  final double? opponentAverage;

  const TurnAverages({super.key, this.myAverage, this.opponentAverage});

  @override
  Widget build(BuildContext context) {
    if (myAverage == null && opponentAverage == null) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    final mine = myAverage?.toStringAsFixed(1) ?? '—';
    final opponent = opponentAverage?.toStringAsFixed(1) ?? '—';
    return Semantics(
      label: '${l10n.yourAvgLabel} $mine, ${l10n.opponentAvgLabel} $opponent',
      excludeSemantics: true,
      child: SizedBox(
        height: 16,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text.rich(
            TextSpan(
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                height: 1,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
              children: [
                TextSpan(
                  text: '${dsSentence(l10n.avgLabel)} ',
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                TextSpan(
                  text: mine,
                  style: const TextStyle(color: AppTheme.playerBlueBright),
                ),
                const TextSpan(
                  text: '  |  ',
                  style: TextStyle(
                    color: AppTheme.textTertiary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                TextSpan(
                  text: opponent,
                  style: const TextStyle(color: AppTheme.opponentPinkBright),
                ),
              ],
            ),
            maxLines: 1,
          ),
        ),
      ),
    );
  }
}

/// The score header above the camera, shared by both turns: my identity
/// (blue, left) vs the opponent (rose, right), names in the identity colour,
/// scores in plain white, and the series context in the middle (group label,
/// two-coloured legs, simultaneous averages). A 6 px identity dot next to the
/// name says whose turn it is.
class TurnScoreHeader extends StatelessWidget {
  final String myName;
  final String opponentName;
  final int myScore;
  final int opponentScore;
  final int? roundNumber;
  final double? myAverage;
  final double? opponentAverage;
  final Widget? leading;
  // BO3 series context ("BO3 · Manche 2"). When set, the center column shows
  // it over the colored legs score, and the round chip moves next to the
  // "VOUS" chip on the left. Null for single-leg matches (center = round chip).
  final String? seriesTitle;
  final int myLegs;
  final int opponentLegs;

  /// False hides the badge row entirely (back / VOUS / TOUR / JOUE) — the
  /// online opponent screen moved those onto the camera feed, keeping only
  /// names + scores here (2026-08-18 redesign).
  final bool showBadges;

  /// Whose turn it is: true puts the identity dot next to my name, false next
  /// to the opponent's, null (callers that don't track it) draws no dot.
  final bool? myTurn;

  const TurnScoreHeader({
    super.key,
    required this.myName,
    required this.opponentName,
    required this.myScore,
    required this.opponentScore,
    this.roundNumber,
    this.myAverage,
    this.opponentAverage,
    this.leading,
    this.seriesTitle,
    this.myLegs = 0,
    this.opponentLegs = 0,
    this.showBadges = true,
    this.myTurn,
  });

  static const _scoreStyle = TextStyle(
    fontSize: 42,
    fontWeight: FontWeight.w800,
    height: 1,
    letterSpacing: -1.2,
    color: AppTheme.textPrimary,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  Widget _dot(Color color) => Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );

  Widget _nameRow({required bool mine}) {
    final name = mine ? myName : opponentName;
    final color = mine ? AppTheme.playerBlueBright : AppTheme.opponentPinkBright;
    final dotColor = mine ? AppTheme.playerBlue : AppTheme.opponentPink;
    final showDot = myTurn == mine;
    final text = Flexible(
      child: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 13,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    );
    return SizedBox(
      height: 13,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: mine ? MainAxisAlignment.start : MainAxisAlignment.end,
        children: [
          if (mine && showDot) ...[_dot(dotColor), const SizedBox(width: 6)],
          text,
          if (!mine && showDot) ...[const SizedBox(width: 6), _dot(dotColor)],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Every column stacks: badge row (fixed height so the back button can't
    // push the left column down) → name → score. Fixed heights keep the two
    // names and the two scores on exactly the same lines.
    const badgeRowHeight = 40.0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // scaleDown: in landscape each side column is a quarter of the
                // screen, and back button + VOUS + TOUR n overflowed it by
                // ~23px (2026-08-14). Shrinking beats clipping the round chip.
                if (showBadges) ...[
                  SizedBox(
                    height: badgeRowHeight,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Row(
                        children: [
                          if (leading != null) ...[
                            leading!,
                            const SizedBox(width: 8),
                          ],
                          GameChip(text: l10n.you, color: AppTheme.playerBlue),
                          if (seriesTitle != null && roundNumber != null) ...[
                            const SizedBox(width: 8),
                            GameChip(
                              text: l10n.roundChip(roundNumber!),
                              color: AppTheme.textSecondary,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                _nameRow(mine: true),
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text('$myScore', style: _scoreStyle),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 8,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                children: [
                  if (showBadges)
                    SizedBox(
                      height: badgeRowHeight,
                      child: Center(
                        child: seriesTitle == null && roundNumber != null
                            ? GameChip(
                                text: l10n.roundChip(roundNumber!),
                                color: AppTheme.textSecondary,
                              )
                            : const SizedBox.shrink(),
                      ),
                    ),
                  // Series mode: group label on the names line, two-coloured
                  // legs on the scores line (mirrors the two side columns).
                  if (seriesTitle != null) ...[
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        seriesTitle!.toUpperCase(),
                        maxLines: 1,
                        style: AppTheme.labelSmall.copyWith(height: 1),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SeriesLegsScore(
                      myLegs: myLegs,
                      opponentLegs: opponentLegs,
                      fontSize: 24,
                    ),
                  ],
                  if (myAverage != null || opponentAverage != null) ...[
                    // The averages grow from 11 to 16 px; reclaim those 5 px
                    // from the gap so the header and camera keep their height.
                    SizedBox(height: seriesTitle != null ? 3 : 6),
                    TurnAverages(
                      myAverage: myAverage,
                      opponentAverage: opponentAverage,
                    ),
                  ],
                ],
              ),
            ),
          ),
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (showBadges) ...[
                  SizedBox(
                    height: badgeRowHeight,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          _dot(AppTheme.opponentPink),
                          const SizedBox(width: 6),
                          Text(
                            l10n.playingBadge,
                            style: AppTheme.labelSmall.copyWith(
                              color: AppTheme.opponentPinkBright,
                              height: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                _nameRow(mine: false),
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text('$opponentScore', style: _scoreStyle),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Two-coloured legs score ("1 – 0"): my legs in bright blue, the opponent's
/// in bright rose, a smaller tertiary dash between. Shared by the turn
/// header, the cricket table and the end-of-leg / end-of-match screens.
class SeriesLegsScore extends StatelessWidget {
  final int myLegs;
  final int opponentLegs;
  final double fontSize;

  const SeriesLegsScore({
    super.key,
    required this.myLegs,
    required this.opponentLegs,
    this.fontSize = 24,
  });

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: fontSize,
      fontWeight: FontWeight.w800,
      height: 1,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text('$myLegs', style: style.copyWith(color: AppTheme.playerBlueBright)),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: fontSize * 0.25),
          child: Text(
            '–',
            style: style.copyWith(
              color: AppTheme.textTertiary,
              fontSize: fontSize * 0.75,
            ),
          ),
        ),
        Text(
          '$opponentLegs',
          style: style.copyWith(color: AppTheme.opponentPinkBright),
        ),
      ],
    );
  }
}

/// One dart of the current visit. Filled chips show the notation + points
/// (and an optional EDIT footer on the player's own chips); empty chips are
/// dashed with "à venir".
class DartVisitChip extends StatelessWidget {
  final String? notation;
  final Color accent;
  final bool highlighted;
  final bool showEditLabel;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;
  final bool capturing;

  /// Line under the notation. Null keeps the X01 default ("60 pts");
  /// cricket passes its own ("1 marque", "+60 pts").
  final String? subtitle;

  /// Reduced type for the ~64pt cricket chip row that shares its line with
  /// the CONFIRM button (2026-08-19 "tableau" layout) — also drops the EDIT
  /// footer, which doesn't fit; the chip stays tappable.
  final bool compact;

  const DartVisitChip({
    super.key,
    this.notation,
    required this.accent,
    this.highlighted = false,
    this.showEditLabel = false,
    this.onTap,
    this.onRemove,
    this.capturing = false,
    this.subtitle,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final filled = notation != null && notation!.isNotEmpty;

    final radius = compact ? 12.0 : 14.0;
    Widget chip;
    if (filled) {
      chip = Container(
        decoration: BoxDecoration(
          color: AppTheme.gamePanel,
          borderRadius: BorderRadius.circular(radius),
          // The identity colour IS the border: blue on my chips, rose on the
          // opponent's last dart, surfaceLight on their earlier ones.
          border: Border.all(
            color: highlighted ? AppTheme.opponentPink : accent,
            width: 1.4,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              notation!,
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: compact ? 18 : 24,
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
            SizedBox(height: compact ? 2 : 3),
            Text(
              subtitle ?? l10n.ptsLabel(notationPoints(notation!)),
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: compact ? 9.5 : 11,
                fontWeight: FontWeight.w600,
                height: 1,
              ),
            ),
            if (showEditLabel && !compact) ...[
              const SizedBox(height: 5),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.only(top: 5),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: accent.withValues(alpha: 0.3)),
                  ),
                ),
                child: Text(
                  dsSentence(l10n.editShort),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: accent,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    height: 1,
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    } else {
      chip = CustomPaint(
        painter: _DashedRRectPainter(
          color: AppTheme.surfaceLight.withValues(alpha: 0.9),
          radius: radius,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: AppTheme.gameBackground,
            borderRadius: BorderRadius.circular(radius),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              capturing
                  ? SizedBox(
                      width: compact ? 14 : 18,
                      height: compact ? 14 : 18,
                      child: const CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.surfaceLight,
                      ),
                    )
                  : Container(
                      width: compact ? 18 : 22,
                      height: 3,
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceLight,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
              SizedBox(height: compact ? 5 : 8),
              Text(
                l10n.upcomingDart,
                style: TextStyle(
                  color: AppTheme.textTertiary,
                  fontSize: compact ? 9.5 : 11,
                  fontWeight: FontWeight.w600,
                  height: 1,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        fit: StackFit.expand,
        children: [
          chip,
          if (onRemove != null && filled)
            Positioned(
              top: -8,
              right: -8,
              child: GestureDetector(
                onTap: onRemove,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: AppTheme.opponentPink,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppTheme.background, width: 2),
                  ),
                  child: const Icon(
                    Icons.close_rounded,
                    size: 12,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DashedRRectPainter extends CustomPainter {
  final Color color;
  final double radius;

  _DashedRRectPainter({required this.color, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect.deflate(0.75));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    const dash = 6.0, gap = 5.0;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(metric.extractPath(distance, distance + dash), paint);
        distance += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRRectPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}

/// "TOTAL 80" readout paired with the visit chips.
class VisitTotal extends StatelessWidget {
  final int total;
  final Color color;

  /// Overrides the numeric display. Null keeps X01's "$total"; cricket
  /// passes "+3 marques" / "+60 pts".
  final String? text;

  const VisitTotal({super.key, required this.total, required this.color, this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(AppLocalizations.of(context).totalLabel, style: AppTheme.labelSmall),
        const SizedBox(width: 8),
        Text(
          text ?? '$total',
          style: TextStyle(
            color: color,
            fontSize: 28,
            fontWeight: FontWeight.w800,
            height: 1,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

/// The "VOTRE VOLÉE · TOUR 7 …… TOTAL 60" row above the visit chips: a group
/// label on the left, [VisitTotal] on the right.
class VisitLabelRow extends StatelessWidget {
  final String label;
  final int total;
  final Color color;
  final String? totalText;

  const VisitLabelRow({
    super.key,
    required this.label,
    required this.total,
    required this.color,
    this.totalText,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.labelSmall,
            ),
          ),
        ),
        VisitTotal(total: total, color: color, text: totalText),
      ],
    );
  }
}

/// The opponent's dart, announced on their live feed (2026-09-06 redesign):
/// a full-width band docked at the bottom of the feed ("T19  +57 pts …
/// FLÉCHETTE 2 / 3" on a dark veil — option A of the second device round:
/// the small corner pill was unreadable over a zoomed board) and, when the
/// thrower sent where the dart sits in the frame, a zoom on it — scale 1 →
/// 2.2 about the impact (350 ms), hold (1 400 ms — long enough to actually
/// see the dart), back (500 ms). No marker on the dart: the zoom itself
/// shows it. Replaces the 84 px centred flash that used to cover the board
/// for almost three seconds.
///
/// [bottomInset] lifts the band above whatever the screen docks at the
/// feed's bottom edge (the cricket visit ticker).
///
/// The zoom itself is painted by the video ([BoardSafeVideo]) through
/// [controller]; this widget only drives it. A dart that lands while a zoom
/// is in flight restarts the sequence FROM the current scale and focus (no
/// jump back to 1). A typed score zooms on its bed centre with the wider ring
/// and a MANUAL tag. Without a point (older app on the other side, tip out
/// of frame) the label alone appears.
class OpponentDartFlash extends StatefulWidget {
  final List<String> throws;
  final OpponentDartZoom? zoom;
  final VideoZoomController controller;

  /// Subtitle under the notation. Null keeps the X01 "+60 pts"; cricket
  /// passes marks ("3 marques").
  final String Function(String notation)? subtitleOf;
  final double bottomInset;

  const OpponentDartFlash({
    super.key,
    required this.throws,
    required this.zoom,
    required this.controller,
    this.subtitleOf,
    this.bottomInset = 0,
  });

  @override
  State<OpponentDartFlash> createState() => _OpponentDartFlashState();
}

class _OpponentDartFlashState extends State<OpponentDartFlash>
    with SingleTickerProviderStateMixin {
  static const _totalMs = 2250;
  static const _total = Duration(milliseconds: _totalMs);
  static const _zoomInEnd = 350 / _totalMs;
  static const _zoomOutStart = 1750 / _totalMs;
  static const _labelInEnd = 200 / _totalMs;
  static const _maxScale = 2.2;

  late final AnimationController _anim;
  String? _notation;
  int _dartIndex = 0;
  bool _manual = false;
  double? _targetX;
  double? _targetY;
  double _startScale = 1;
  double _startX = 0.5;
  double _startY = 0.5;
  // A dart without a point while a zoom is in flight: ease the video back to
  // 1 instead of leaving it stuck at 2.2× until the sequence ends.
  bool _releaseOnly = false;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: _total)
      ..addListener(_drive)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          widget.controller.value = VideoZoomState.none;
        }
      });
  }

  @override
  void didUpdateWidget(OpponentDartFlash oldWidget) {
    super.didUpdateWidget(oldWidget);
    final z = widget.zoom;
    final newZoom = z != null && z.seq != oldWidget.zoom?.seq;
    final newDart = widget.throws.length > oldWidget.throws.length &&
        widget.throws.isNotEmpty;
    if (!newZoom && !newDart) return;
    // Restart from wherever the video is right now, never from a jump.
    final current = widget.controller.value;
    _startScale = current.scale;
    if (newZoom) {
      _notation = z.notation;
      _dartIndex = z.dartIndex;
      _manual = z.manual;
      _targetX = z.x;
      _targetY = z.y;
      _releaseOnly = false;
    } else {
      _notation = widget.throws.last;
      _dartIndex = widget.throws.length;
      _manual = false;
      _targetX = null;
      _targetY = null;
      _releaseOnly = current.scale > 1.0005;
    }
    if (current.scale > 1.0005) {
      _startX = current.focusX;
      _startY = current.focusY;
    } else {
      _startX = _targetX ?? 0.5;
      _startY = _targetY ?? 0.5;
    }
    _anim.forward(from: 0);
  }

  void _drive() {
    final t = _anim.value;
    if (_releaseOnly) {
      final k = Curves.easeInOut.transform((t / _zoomInEnd).clamp(0.0, 1.0));
      widget.controller.value = VideoZoomState(
        scale: _startScale + (1 - _startScale) * k,
        focusX: _startX,
        focusY: _startY,
        manual: false,
      );
      return;
    }
    final tx = _targetX, ty = _targetY;
    if (tx == null || ty == null) return; // label only, video untouched
    final double scale;
    if (t < _zoomInEnd) {
      final k = Curves.easeOutCubic.transform(t / _zoomInEnd);
      scale = _startScale + (_maxScale - _startScale) * k;
    } else if (t < _zoomOutStart) {
      scale = _maxScale;
    } else {
      final k = Curves.easeInOut.transform((t - _zoomOutStart) / (1 - _zoomOutStart));
      scale = _maxScale + (1 - _maxScale) * k;
    }
    final f = Curves.easeOutCubic.transform((t / _zoomInEnd).clamp(0.0, 1.0));
    widget.controller.value = VideoZoomState(
      scale: scale,
      focusX: _startX + (tx - _startX) * f,
      focusY: _startY + (ty - _startY) * f,
      manual: _manual,
    );
  }

  @override
  void dispose() {
    _anim.dispose();
    // The layout is going away (my turn now): leave the video plain for the
    // next time the opponent's feed shows.
    widget.controller.value = VideoZoomState.none;
    super.dispose();
  }

  double _labelOpacity(double t) {
    if (t < _labelInEnd) return Curves.easeOut.transform(t / _labelInEnd);
    if (t < _zoomOutStart) return 1;
    return 1 - Curves.easeIn.transform((t - _zoomOutStart) / (1 - _zoomOutStart));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final notation = _notation;
    return IgnorePointer(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: EdgeInsets.only(bottom: widget.bottomInset),
          child: AnimatedBuilder(
            animation: _anim,
            builder: (context, child) {
              final visible = _anim.isAnimating ? _labelOpacity(_anim.value) : 0.0;
              return Opacity(
                opacity: visible,
                child: Transform.translate(
                  offset: Offset(0, 10 * (1 - visible)),
                  child: child,
                ),
              );
            },
            child: notation == null
                ? const SizedBox.shrink()
                : Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(16, 26, 16, 14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          AppTheme.gameBackground.withValues(alpha: 0),
                          AppTheme.gameBackground.withValues(alpha: 0.92),
                          AppTheme.gameBackground.withValues(alpha: 0.96),
                        ],
                        stops: const [0, 0.38, 1],
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          notation,
                          style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 40,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.8,
                            height: 1,
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Points + MANUAL tag shrink together before anything
                        // overflows on a narrow panel (iPhone SE).
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.bottomLeft,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Text(
                                    widget.subtitleOf?.call(notation) ??
                                        l10n.plusPts(notationPoints(notation)),
                                    style: const TextStyle(
                                      color: AppTheme.opponentPinkBright,
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800,
                                      height: 1,
                                    ),
                                  ),
                                ),
                                if (_manual) ...[
                                  const SizedBox(width: 10),
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 2),
                                    child: DsPill(
                                      label: l10n.manualDartTag,
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Takes what is left and fades rather than overflows
                        // on a narrow panel (iPhone SE, wide test font).
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Text(
                              l10n.dartOf(_dartIndex),
                              textAlign: TextAlign.right,
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.fade,
                              style: AppTheme.labelSmall.copyWith(height: 1),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// "Ne lancez pas vos fléchettes" bottom banner for the opponent's turn: a
/// rose-tinted card whose border alone "breathes" (dim to half rose and
/// back on a ~2.2 s cycle); icon, texts and background stay constant.
class OpponentWarningBanner extends StatefulWidget {
  const OpponentWarningBanner({super.key});

  @override
  State<OpponentWarningBanner> createState() => _OpponentWarningBannerState();
}

class _OpponentWarningBannerState extends State<OpponentWarningBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _pulse = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        final t = _pulse.value;
        return Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 60),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: AppTheme.secondary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppTheme.radiusRow),
            border: Border.all(
              color: AppTheme.opponentPink.withValues(alpha: 0.2 + 0.4 * t),
            ),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.info_outline_rounded,
                color: AppTheme.opponentPinkBright,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dsSentence(l10n.doNotThrowTitle),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.opponentPinkBright,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      l10n.opponentTurnWait,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.caption.copyWith(fontSize: 11, height: 1.1),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Translucent score band docked to the bottom of a camera feed:
/// "VATI99 288 · BO3 · MANCHE 1 0–0 · 355 DODO180". The match screens moved
/// their scores off the feed (2026-08-19 layout); only the spectator screen
/// still docks this on its stream.
class CameraScoreBand extends StatelessWidget {
  final String myName;
  final String opponentName;
  final int myScore;
  final int opponentScore;
  final String? seriesTitle;
  final int myLegs;
  final int opponentLegs;

  const CameraScoreBand({
    super.key,
    required this.myName,
    required this.opponentName,
    required this.myScore,
    required this.opponentScore,
    this.seriesTitle,
    this.myLegs = 0,
    this.opponentLegs = 0,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    Widget side({required bool mine}) {
      final name = mine ? myName : opponentName;
      final score = mine ? myScore : opponentScore;
      return Column(
        crossAxisAlignment: mine
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: mine
                  ? AppTheme.playerBlueBright
                  : AppTheme.opponentPinkBright,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              height: 1,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '$score',
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 32,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.8,
                height: 1,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.gameBackground.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        border: Border.all(color: _glassBorder),
      ),
      child: Row(
        children: [
          Expanded(child: Align(alignment: Alignment.centerLeft, child: side(mine: true))),
          seriesTitle != null
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      seriesTitle!.toUpperCase(),
                      style: AppTheme.labelSmall.copyWith(fontSize: 9, height: 1),
                    ),
                    const SizedBox(height: 4),
                    SeriesLegsScore(
                      myLegs: myLegs,
                      opponentLegs: opponentLegs,
                      fontSize: 12,
                    ),
                  ],
                )
              : Text(
                  l10n.vsLabel,
                  style: AppTheme.labelSmall.copyWith(
                    color: AppTheme.textTertiary,
                    height: 1,
                  ),
                ),
          Expanded(child: Align(alignment: Alignment.centerRight, child: side(mine: false))),
        ],
      ),
    );
  }
}

/// Opponent-visit ticker overlaid on the live feed (cricket): stacked
/// "VOLÉE / DODO180" label, one big slot per dart and the running total —
/// sized so each dart's notation is readable from throwing distance
/// (2026-08-19 enlargement; X01 went back to the big chip row below the
/// camera instead).
class VisitTicker extends StatelessWidget {
  /// Top caption ("VOLÉE").
  final String labelTop;

  /// The thrower's name, under the caption.
  final String labelBottom;

  final List<String> throws;

  /// "+1" / "+65" — the running visit total.
  final String totalValue;

  /// Tiny caption under the total: "MARQUE(S)" / "POINTS".
  final String totalLabel;

  const VisitTicker({
    super.key,
    required this.labelTop,
    required this.labelBottom,
    required this.throws,
    required this.totalValue,
    required this.totalLabel,
  });

  @override
  Widget build(BuildContext context) {
    Widget slot(int i) {
      final notation = i < throws.length ? throws[i] : null;
      final isLast = notation != null && i == throws.length - 1;
      return Container(
        width: 44,
        height: 36,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(
          color: AppTheme.gamePanel.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isLast ? AppTheme.opponentPink : AppTheme.surfaceLight,
            width: 1.4,
          ),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            notation ?? '—',
            style: TextStyle(
              color: notation == null
                  ? AppTheme.textTertiary
                  : AppTheme.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: AppTheme.gameBackground.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        border: Border.all(color: _glassBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  labelTop,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.labelSmall.copyWith(fontSize: 9, height: 1),
                ),
                const SizedBox(height: 4),
                Text(
                  labelBottom,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.opponentPinkBright,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          for (var i = 0; i < 3; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            slot(i),
          ],
          const SizedBox(width: 10),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                totalValue,
                style: const TextStyle(
                  color: AppTheme.opponentPinkBright,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  height: 1,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                totalLabel,
                style: AppTheme.labelSmall.copyWith(fontSize: 8, height: 1),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Label style of the in-match buttons. A ButtonStyle's textStyle replaces
/// the ambient DefaultTextStyle instead of merging with it, so the family
/// has to be spelled out here exactly as the theme's button styles do.
const TextStyle gameButtonTextStyle = TextStyle(
  fontFamily: AppTheme.fontFamily,
  fontSize: 15,
  fontWeight: FontWeight.w700,
);

/// Button styles of the in-match actions (the CONFIRM button, dialog
/// actions): the theme's 15 / 700 sentence-case buttons at the 16 px row
/// radius, tinted with [accent] (blue for me, success for a checkout…).
ButtonStyle gameOutlineButtonStyle(Color accent) => OutlinedButton.styleFrom(
  foregroundColor: accent,
  side: BorderSide(color: accent, width: 1.5),
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(AppTheme.radiusRow),
  ),
  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
  textStyle: gameButtonTextStyle,
);

ButtonStyle gameFilledButtonStyle(Color accent) => ElevatedButton.styleFrom(
  backgroundColor: accent,
  foregroundColor: Colors.white,
  disabledBackgroundColor: AppTheme.surfaceLight,
  disabledForegroundColor: AppTheme.textSecondary,
  elevation: 0,
  shadowColor: Colors.transparent,
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(AppTheme.radiusRow),
  ),
  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
  textStyle: gameButtonTextStyle,
);

/// The neutral half of a [prominentActions] dialog pair ("Modifier les
/// fléchettes"): same shape as [gameFilledButtonStyle] so the two stacked
/// buttons match, but no colour of its own — the accent is the card's edge.
ButtonStyle gameNeutralOutlineButtonStyle() => OutlinedButton.styleFrom(
  foregroundColor: AppTheme.textPrimary,
  side: const BorderSide(color: AppTheme.surfaceLight),
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(AppTheme.radiusRow),
  ),
  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
  textStyle: gameButtonTextStyle,
);

/// Body and secondary line of a [prominentActions] dialog: 15 / 600 primary
/// over 13 / 500 secondary (the compact dialogs keep bodyMedium + caption).
const TextStyle gameDialogBodyStyle = TextStyle(
  fontFamily: AppTheme.fontFamily,
  fontSize: 15,
  fontWeight: FontWeight.w600,
  height: 1.35,
  color: AppTheme.textPrimary,
);

const TextStyle gameDialogHintStyle = TextStyle(
  fontFamily: AppTheme.fontFamily,
  fontSize: 13,
  fontWeight: FontWeight.w500,
  height: 1.4,
  color: AppTheme.textSecondary,
);

/// The dialog shell shared by every in-match popup (win, bust, leave,
/// forfeit, report): the theme's flat surface dialog, a 17 / 700 sentence-
/// case title with a 22 px icon in [accent]. [actionsBuilder] receives the
/// dialog's own context so actions can Navigator.pop the dialog route.
Future<T?> showGameDialog<T>(
  BuildContext context, {
  required Color accent,
  required IconData icon,
  required String title,
  Widget? content,
  required List<Widget> Function(BuildContext ctx) actionsBuilder,
  bool barrierDismissible = false,
  Widget? bottomBar,
  bool prominentActions = false,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (ctx) => gameDialogFrame(
      accent: accent,
      icon: icon,
      title: title,
      content: content,
      actions: actionsBuilder(ctx),
      bottomBar: bottomBar,
      prominentActions: prominentActions,
    ),
  );
}

/// The dialog widget itself, exposed for callers that need a StatefulBuilder
/// or custom showDialog options around it.
///
/// [bottomBar] docks a full-width widget to the dialog's bottom edge, under
/// the actions and flush with the rounded border — the replay capture bar of
/// the checkout dialog (2026-08-04, piste 2: the in-game bar "follows" the
/// player into the modal that covers it). Null keeps the exact AlertDialog
/// every other dialog ships.
///
/// [prominentActions] is the layout of the two dialogs a player answers with
/// the phone on its tripod, at arm's length (checkout, bust — 2026-09-08,
/// « alternative 2 »): a wider card (28 px inset instead of 40), the accent
/// as a 3 px edge rather than a coloured button, and two FULL-WIDTH 64 px
/// actions separated by 28 px of empty space — the AlertDialog's OverflowBar
/// stacked those two long labels flush against each other, right-aligned,
/// which is exactly what a rough tap gets wrong. The leave / forfeit /
/// report dialogs keep the compact frame.
Widget gameDialogFrame({
  required Color accent,
  required IconData icon,
  required String title,
  Widget? content,
  required List<Widget> actions,
  Widget? bottomBar,
  bool prominentActions = false,
  Widget? titleTrailing,
}) {
  final titleRow = Row(
    children: [
      Icon(icon, color: accent, size: prominentActions ? 24 : 22),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          dsSentence(title),
          style: prominentActions
              ? AppTheme.titleLarge.copyWith(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                )
              : AppTheme.titleLarge,
        ),
      ),
      if (titleTrailing != null) ...[const SizedBox(width: 10), titleTrailing],
    ],
  );
  final shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(AppTheme.radiusCard),
    side: const BorderSide(color: AppTheme.border),
  );
  if (prominentActions) {
    return Dialog(
      backgroundColor: AppTheme.surface,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(height: 3, color: accent),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
              child: titleRow,
            ),
            // Flexible + scroll: the card is short at the default text size,
            // but an accessibility scale can push the message past the screen
            // — better a scrolling message than clipped actions.
            if (content != null)
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: content,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < actions.length; i++) ...[
                    if (i > 0) const SizedBox(height: 28),
                    // minHeight, not a fixed box: a large text scale grows the
                    // button instead of clipping its label.
                    ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 64),
                      child: SizedBox(width: double.infinity, child: actions[i]),
                    ),
                  ],
                ],
              ),
            ),
            ?bottomBar,
          ],
        ),
      ),
    );
  }
  if (bottomBar == null) {
    return AlertDialog(
      backgroundColor: AppTheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: shape,
      title: titleRow,
      content: content,
      actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      actions: actions,
    );
  }
  // A full-bleed footer cannot live in an AlertDialog (title, content and
  // actions are all inset), so this branch rebuilds the same frame as a plain
  // Dialog whose Column ends with the bar, clipped by the shared rounded
  // border. Paddings mirror the AlertDialog ones above; the width cap keeps
  // the bar's unbounded Row from stretching the dialog in landscape.
  return Dialog(
    backgroundColor: AppTheme.surface,
    surfaceTintColor: Colors.transparent,
    shape: shape,
    clipBehavior: Clip.antiAlias,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 340),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
            child: titleRow,
          ),
          if (content != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: content,
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: SizedBox(
              width: double.infinity,
              child: OverflowBar(
                alignment: MainAxisAlignment.end,
                spacing: 8,
                overflowAlignment: OverflowBarAlignment.end,
                overflowSpacing: 8,
                children: actions,
              ),
            ),
          ),
          bottomBar,
        ],
      ),
    ),
  );
}

/// Pulsing primary ring shown over the camera panel while the board framing
/// is out of the reliable zone (or the auto-framing servo is correcting it).
class PulsingFrameBorder extends StatefulWidget {
  const PulsingFrameBorder({super.key});

  @override
  State<PulsingFrameBorder> createState() => _PulsingFrameBorderState();
}

class _PulsingFrameBorderState extends State<PulsingFrameBorder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final t = 0.2 + 0.4 * _ctrl.value;
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusCard),
            border: Border.all(
              color: AppTheme.primary.withValues(alpha: t),
              width: 3,
            ),
          ),
        );
      },
    );
  }
}
