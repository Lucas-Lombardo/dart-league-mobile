import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../models/cricket.dart';
import '../../models/rtc_v2_config.dart';
import '../../providers/game_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/tournament_game_provider.dart'
    show TournamentGameState;
import '../../services/camera_frame_service.dart';
import '../../services/p2p_match_video.dart';
import '../../services/replay_buffer_service.dart';
import '../../services/replay_clips_store.dart';
import '../../services/replay_overlay_timeline.dart';
import '../../services/replay_upload_service.dart';
import '../../services/match_proof_service.dart';
import '../../services/board_crop.dart' show OpponentVideoFraming, VideoPoint;
import '../../services/rtc_frames_service.dart';
import '../../services/socket_service.dart';
import '../../services/turn_report_service.dart';
import '../../utils/haptic_service.dart';
import '../../utils/media_permissions.dart';
import '../../utils/dart_sound_service.dart';
import '../../utils/dart_caller_service.dart';
import '../../utils/app_theme.dart';
import '../../utils/orientation_utils.dart';
import '../../utils/score_converter.dart';
import '../../widgets/cricket_board.dart';
import '../../utils/storage_service.dart';
import '../../services/auto_scoring_service.dart';
import '../../services/dart_scoring_service.dart';
import '../../services/dataset_capture_service.dart';
import '../../l10n/app_localizations.dart';
import '../../models/opponent_dart_zoom.dart';
import '../../widgets/board_safe_video.dart' show VideoZoomController;
import '../../widgets/design_system.dart';
import '../../widgets/game_turn_ui.dart';
import '../../widgets/turn_report_banner.dart';
import '../../widgets/logo_watermark.dart';
import '../../widgets/auto_score_display.dart';
import '../../widgets/local_camera_preview.dart';

/// Shared base state for GameScreen and TournamentGameScreen.
/// readGame() returns dynamic to support both GameProvider and TournamentGameProvider.
abstract class BaseGameScreenState<W extends StatefulWidget> extends State<W>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {

  // ─── Abstract ────────────────────────────────────────────────────────────────
  dynamic readGame();

  /// Mode this screen's AI frames are attributed to in the model telemetry:
  /// 'ranked', 'friendly' or 'tournament'. Paired with the CURRENT leg id, so
  /// every telemetry row can be joined to the server's own record of the same
  /// darts (matches.aiTrustSnapshot).
  String get aiTelemetryContext;
  String get opponentUsername;
  Widget buildAppBarTitle();
  Widget buildEndScreen(dynamic game, AuthProvider auth);
  void onScreenSpecificStateChange(dynamic game);
  Future<void> initScreenSpecific();
  void disposeScreenSpecific();
  String get leaveWarningText;
  String? get matchIdForLeave;
  void showForfeitDialog(dynamic game);

  // ─── Shared state ─────────────────────────────────────────────────────────────
  late AnimationController scoreAnimationController;
  String loadingMessage = 'Connecting...';
  int? editingDartIndex;
  String? storedPlayerId;
  bool gameStarted = false;
  bool gameEnded = false;
  // Tracks the seriesEnded transition (D7): the final BO3 leg must tear the
  // call down when ranked_match_won lands, not on its game_won.
  bool _sawSeriesEnded = false;
  CameraFrameService? cameraFrameService;
  // ─── Replays ──────────────────────────────────────────────────────────────

  /// Format band burned into replay overlays — screens override with their
  /// own context (the tournament screen shows the tournament name); null
  /// falls back to the match type read off the provider.
  String? get replayFormatLabel => null;

  String _replayDefaultFormat(dynamic game) {
    try {
      if (game.isFriendly == true) {
        return game.bestOf > 1 ? 'FRIENDLY · BO${game.bestOf}' : 'FRIENDLY';
      }
      if (game.isRankedSeries == true) return 'RANKED · BO${game.bestOf}';
    } catch (_) {}
    return 'FRIENDLY';
  }

  /// Legs needed to take the series — one pip per leg on the replay cards.
  int _replayLegsTarget(dynamic game) {
    try {
      final bestOf = game.bestOf as int?;
      if (bestOf != null && bestOf > 0) return (bestOf ~/ 2) + 1;
    } catch (_) {}
    return 2;
  }

  /// The « Enregistrer » pill on my camera panel — visible during MY turn
  /// once the visit has something to record. Every clip comes from this one
  /// gesture: the auto-capture of checkouts was dropped 2026-08-04, a replay
  /// is only ever something the player asked for.
  Widget? buildReplayCaptureButton(dynamic game) {
    // Before my first dart the capture bar has nothing to record, so the slot
    // is free — that is where the report bar lives (2026-08-13). One slot, two
    // gestures, never both at once.
    if (game.dartsThrown < 1 && _turnDartTimes.isEmpty) {
      return buildTurnFlagButton(game);
    }
    if (!ReplayBufferService.armed) return null;
    return ReplayCaptureButton(onCapture: () => captureTurnClip(game));
  }

  /// The report bar, or null when there is nothing to flag: no opponent visit
  /// yet (I opened the leg), quota spent, that visit already flagged, or the
  /// feature off for this match (old backend, old opponent — the server's
  /// `turnReports` block is the both-sides verdict).
  Widget? buildTurnFlagButton(dynamic game) {
    if (!TurnReportService.enabled) return null;
    final matchId = matchIdForLeave;
    if (matchId == null) return null;
    List<int> opponentRounds;
    try {
      opponentRounds = List<int>.from(game.opponentRounds as List);
    } catch (_) {
      return null;
    }
    if (opponentRounds.isEmpty) return null;
    final turnIndex = opponentRounds.length;
    if (TurnReportService.flagsInLeg(matchId) >= TurnReportService.maxPerLeg) {
      return null;
    }
    final flagged = TurnReportService.alreadyFlagged(matchId, turnIndex);
    return TurnFlagButton(
      // The key ties the widget's countdown to the visit it targets: without
      // it, the next turn reuses the element and inherits a running timer.
      key: ValueKey('flag-$matchId-$turnIndex'),
      volleyScore: opponentRounds.last,
      alreadyFlagged: flagged,
      onConfirmed: () => postTurnFlag(
        matchId: matchId,
        turnIndex: turnIndex,
        volleyScore: opponentRounds.last,
      ),
    );
  }

  /// Posts the flag over the game socket. The server acks it, deduplicates on
  /// [flagId] and relays the capture request to the opponent's device; the
  /// reason is asked for at the end of the match, never here.
  void postTurnFlag({
    required String matchId,
    required int turnIndex,
    int? volleyScore,
    bool isWinningVolley = false,
  }) {
    TurnReportService.postFlag({
      'flagId': _newFlagId(matchId, turnIndex, isWinningVolley),
      'matchId': matchId,
      'turnIndex': turnIndex,
      'volleyScore': ?volleyScore,
      'isWinningVolley': isWinningVolley,
    });
  }

  /// True once the end-of-match report list has been settled (sent, skipped,
  /// or emptied), so the result screen takes over.
  bool turnReportsSettled = false;

  /// The winning-visit banner for the two end screens, or null when there is
  /// nothing to offer: I won the leg (you don't report your own checkout), the
  /// feature is off for this match, or it is already flagged.
  Widget? buildWinningVisitBanner(dynamic game, {required bool didWin}) {
    if (didWin) return null;
    if (!TurnReportService.enabled) return null;
    final matchId = matchIdForLeave;
    if (matchId == null) return null;
    List<int> opponentRounds;
    try {
      opponentRounds = List<int>.from(game.opponentRounds as List);
    } catch (_) {
      opponentRounds = const [];
    }
    // The checkout is the visit AFTER their last recorded one, and it scored
    // exactly what they had left when it started.
    final score = _opponentScoreAtVisitStart;
    return WinningVisitBanner(
      matchId: matchId,
      volleyScore: score,
      onFlag: () => postTurnFlag(
        matchId: matchId,
        turnIndex: opponentRounds.length + 1,
        volleyScore: score,
        isWinningVolley: true,
      ),
    );
  }

  // ── Between-legs minimum dwell ─────────────────────────────────────────
  //
  // The server can send ranked_next_leg within a second of the checkout, and
  // the between-legs screen is one of only two places the loser can ever flag
  // the winning visit (see [buildWinningVisitBanner]). It was gone before the
  // thumb arrived — "on n'a pas le temps de signaler, l'écran est trop
  // rapide" (2026-08-14). So the screen now owes the player a fixed minimum
  // on screen, counted down in plain sight, before the next leg may take it.
  //
  // Held for BOTH players, not just the loser: legs have no shot clock, so a
  // few seconds cost nothing, while releasing one side early would put the
  // two devices in different legs for the length of the hold.
  static const Duration legEndMinDwell = Duration(seconds: 6);
  DateTime? _legEndShownAt;
  Timer? _legEndTicker;
  Widget? _legEndBanner;
  bool? _legEndWon;

  /// Snapshot of "did I win the leg that just ended", taken the first time the
  /// between-legs screen builds. The next leg's game_started clears
  /// legWinnerId mid-hold, which would otherwise flip the screen to MANCHE
  /// PERDUE under the winner's eyes.
  bool legEndWonLeg(bool current) => _legEndWon ??= current;

  /// The winning-visit banner for the between-legs screen, built ONCE when
  /// that screen first appears and reused for the whole dwell: ranked_next_leg
  /// lands mid-hold and swaps matchId while wiping the round history, so a
  /// rebuilt banner would key its flag to the leg nobody has played yet.
  Widget? legEndWinningVisitBanner(dynamic game, {required bool didWin}) =>
      _legEndBanner ??= buildWinningVisitBanner(game, didWin: didWin);

  /// Whole seconds still owed to the between-legs screen (0 = free to leave).
  int get legEndSecondsLeft {
    final shownAt = _legEndShownAt;
    if (shownAt == null) return 0;
    final left = legEndMinDwell - DateTime.now().difference(shownAt);
    return left.isNegative ? 0 : (left.inMilliseconds / 1000).ceil();
  }

  /// True while the next leg has already started but the dwell isn't over —
  /// the screen's build keeps returning the between-legs view.
  bool get legEndHoldActive => legEndSecondsLeft > 0;

  /// Arms the dwell the first time the between-legs screen is built, and runs
  /// a 1s ticker so the countdown repaints and the hold releases itself.
  void armLegEndDwell() {
    _legEndShownAt ??= DateTime.now();
    if (_legEndTicker != null) return;
    _legEndTicker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        _legEndTicker = null;
        return;
      }
      final stillHolding = legEndHoldActive;
      setState(() {});
      if (!stillHolding) {
        timer.cancel();
        _legEndTicker = null;
      }
    });
  }

  /// Re-arms the dwell for the next leg. Called from the live-match build:
  /// the board is on screen, so the previous leg's hold is spent.
  void clearLegEndDwell() {
    if (_legEndShownAt == null) return;
    _legEndShownAt = null;
    _legEndBanner = null;
    _legEndWon = null;
    _legEndTicker?.cancel();
    _legEndTicker = null;
  }

  /// Opens the app's existing report dialog for ONE flagged visit. Nothing is
  /// sent here — the reason lands on the pending report and travels with the
  /// others when the list is submitted.
  Future<void> editTurnReport(PendingTurnReport report) {
    final l10n = AppLocalizations.of(context);
    // Awaiting the DIALOG, not the submit callback: a cancelled or dismissed
    // dialog never calls onComplete, and the list screen must come back either
    // way to re-read the row.
    return showReportDialog(
      title: l10n.turnReportDialogTitle,
      subtitle: report.volleyScore != null
          ? l10n.turnReportVisitScore(report.volleyScore!)
          : null,
      icon: Icons.flag,
      showSuccessSnackBar: false,
      onSubmit: (reason, comment) async {
        report.reason = reason;
        report.comment = comment;
      },
      onComplete: () {},
    );
  }

  /// Sends the completed reports, drops the rest, and hands over to the
  /// result screen.
  void finishTurnReports({String? matchId, String? seriesId}) {
    final hadAny = TurnReportService.pending.any((r) => r.isComplete);
    TurnReportService.submit(matchId: matchId, seriesId: seriesId);
    if (mounted) {
      setState(() => turnReportsSettled = true);
      if (hadAny) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(AppLocalizations.of(context).turnReportSent),
          backgroundColor: AppTheme.success,
          duration: const Duration(seconds: 2),
        ));
      }
    }
  }

  /// Deterministic from what the flag targets, so a re-tap after a socket blip
  /// carries the SAME id and the server's dedup collapses it into one case —
  /// same contract as [_nextDartId] on the provider, minus the sequence, which
  /// would defeat the point here.
  String _newFlagId(String matchId, int turnIndex, bool isWinningVolley) {
    final match = matchId.replaceAll('-', '');
    final head = match.length >= 12 ? match.substring(0, 12) : match;
    return 'f$head-${isWinningVolley ? 'w' : 't'}$turnIndex';
  }

  /// Cuts the clip of the current visit from the ring buffer (a cheap
  /// passthrough concat) and stores it RAW. The heavy tail — the multi-second
  /// overlay re-encode and the R2 upload — is queued for the END of the match
  /// (see [processPendingReplayClips]): mid-match the camera, the AI and the
  /// RTC encoder are already running, and stacking a render + a network burst
  /// on top was a heat spike at the worst moment. The overlay timeline is
  /// still built HERE, because it freezes the scores as they are at the tap.
  Future<bool> captureTurnClip(dynamic game) async {
    final now = DateTime.now();
    var from = _turnDartTimes.isNotEmpty
        ? _turnDartTimes.first.subtract(const Duration(seconds: 2))
        // No AI timestamps (manual scoring): a fixed window still covers the
        // visit — segment snapping widens it anyway.
        : now.subtract(const Duration(seconds: 20));
    // Never reach back before this visit could have started (see
    // [_replayWindowFloor]).
    final floor = _replayWindowFloor;
    if (floor != null && from.isBefore(floor)) from = floor;
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final captured = await ReplayBufferService.captureRange(
      from,
      now,
      rotationDegrees: CameraFrameService.calibratedUprightRotation,
    );
    if (captured == null) return false;
    // A checkout capture usually happens from the win dialog, while the
    // final dart is still PENDING confirmation: the provider has not applied
    // it yet, so its score reads one dart short (16 burned on a 70-finish,
    // 2026-08-05 report — DB had the correct 0). The verdict being asked for
    // IS the checkout: burn the end state.
    bool pendingWin = false;
    try {
      pendingWin = game.pendingType == 'win';
    } catch (_) {}
    Map<String, dynamic>? timeline;
    try {
      timeline = buildReplayOverlayTimeline(
        myRemainingScore: pendingWin ? 0 : game.myScore as int,
        opponentScore: game.opponentScore as int,
        myName: auth.currentUser?.username ?? 'YOU',
        opponentName: opponentUsername,
        myLegs: game.myLegsWon as int,
        opponentLegs: game.opponentLegsWon as int,
        legsTarget: _replayLegsTarget(game),
        seriesTitle: replayFormatLabel ?? _replayDefaultFormat(game),
        logoPath: await materializeReplayLogo(),
      );
    } catch (e) {
      // No timeline → the clip stays raw, exactly like a failed render.
      debugPrint('[Replay] timeline skipped: $e');
    }
    final clip = ReplayClip(
      path: captured.path,
      createdAt: now,
      matchId: matchIdForLeave,
      opponent: opponentUsername,
      turnTotal: autoScoringService?.turnTotal,
      durationMs: captured.durationMs,
    );
    _pendingReplayRenders.add((clip, timeline));
    // The final checkout's capture races the win-dialog confirm: when the
    // series verdict already drained the queue, this clip would sit in it
    // forever (and its library row would say "preparing" until app death).
    // Hand it straight to the drain instead.
    if (_replayProcessingStarted) _drainReplayQueue();
    ReplayClipsStore.add(clip);
    // Per-screen list: the screen survives the whole BO3/tournament series,
    // so this is exactly "the clips of this match" for the end view. The
    // pill's own ✓ state is the only in-match feedback — sharing lives on
    // the end screen, never mid-game.
    matchReplayClips.add(clip);
    return true;
  }

  /// Notes the metadata of the visit I just finished for [TurnReportService].
  /// No cut, no file I/O anymore (thermal round 5): the ring now RETAINS the
  /// whole match, so the clip is cut on demand only when a `capture_turn`
  /// actually arrives — instead of writing 3-7.5 MB to disk at every visit
  /// end of every match "just in case".
  ///
  /// Runs on the turn-change notify, right after [ReplayBufferService.setMyTurn]
  /// closed the open segment, so the visit's window is fully on disk.
  void cacheVisitForReports(dynamic game) {
    if (!TurnReportService.enabled) return;
    if (!ReplayBufferService.armed) return;
    final matchId = matchIdForLeave;
    if (matchId == null) return;
    // No impact times means no visit was actually thrown (turn skipped, manual
    // scoring with nothing detected) — there is nothing worth keeping.
    if (_turnDartTimes.isEmpty) return;
    final dartTimes = List.of(_turnDartTimes);
    final from = dartTimes.first.subtract(const Duration(seconds: 2));
    final floor = _replayWindowFloor;
    final start = floor != null && from.isBefore(floor) ? floor : from;
    int turnIndex = 0;
    try {
      turnIndex = (game.myRounds as List).length;
    } catch (_) {}
    TurnReportService.noteVisit(
      matchId: matchId,
      turnIndex: turnIndex,
      dartTimes: dartTimes,
      windowStart: start,
      windowEnd: DateTime.now(),
    );
  }

  /// Same note as [cacheVisitForReports], but for the visit that ENDED the
  /// leg and under a key that survives the rest of the series: the loser
  /// flags it from the end-of-leg or end-of-match screen, well after the
  /// rolling note moved on.
  void cacheWinningVisitForReports(dynamic game) {
    final matchId = matchIdForLeave;
    if (matchId == null) return;
    cacheVisitForReports(game);
    TurnReportService.keepAsWinningVisit(matchId);
  }

  // Clips waiting for their end-of-match overlay render + upload, in capture
  // order. A null timeline means "upload raw as-is".
  final List<(ReplayClip, Map<String, dynamic>?)> _pendingReplayRenders = [];
  bool _replayProcessingStarted = false;

  /// Runs the deferred tail of every capture: burn the overlay in, swap the
  /// clip's path to the dressed file, upload. Fired on the series-end
  /// transition (the end screen is up, camera/AI/RTC load is gone) with a
  /// dispose() fallback for abandons; the guard makes every later call a
  /// no-op — except through [captureTurnClip]'s handoff, which drains a
  /// capture that finished AFTER the verdict (checkout-modal capture racing
  /// the confirm).
  void processPendingReplayClips() {
    if (_replayProcessingStarted) return;
    _replayProcessingStarted = true;
    _drainReplayQueue();
  }

  /// Every await in here is BOUNDED. The uploads are the user-visible part
  /// (the library's "preparing" rows resolve when they land) and they must
  /// never sit behind an open-ended native call: a stalled overlay export
  /// held the whole chain for minutes on-device (2026-08-04) and the clips
  /// only surfaced after the screen died freed the hardware.
  void _drainReplayQueue() {
    if (_pendingReplayRenders.isEmpty) return;
    final pending = List.of(_pendingReplayRenders);
    _pendingReplayRenders.clear();
    Future(() async {
      // Free the ring's hardware encoder BEFORE the first render — they
      // otherwise compete for codec instances, and the ring is useless once
      // the verdict is in (no more captures). Idempotent with the stop the
      // camera teardown issues.
      try {
        await ReplayBufferService.stop()
            .timeout(const Duration(seconds: 5));
      } catch (e) {
        debugPrint('[Replay] ring stop timed out: $e');
      }
      for (final (clip, timeline) in pending) {
        final watch = Stopwatch()..start();
        if (timeline != null) {
          // Falls back to the raw clip on failure or timeout (a timed-out
          // export keeps running native-side; if it lands later the local
          // path still upgrades for sharing, but the upload stops waiting).
          try {
            final dressed = await ReplayBufferService.renderOverlay(
              inPath: clip.path,
              timeline: timeline,
            ).timeout(const Duration(seconds: 30));
            if (dressed != null) clip.path = dressed;
          } catch (e) {
            debugPrint('[Replay] overlay render timed out: $e');
          }
        }
        final renderMs = watch.elapsedMilliseconds;
        // Awaited on purpose: concurrent uploads split the uplink and every
        // clip lands together at the end — sequential costs the same total
        // but resolves the FIRST library row as early as possible.
        await ReplayUploadService.uploadClip(clip);
        debugPrint('[Replay] clip processed: render=${renderMs}ms '
            'upload=${watch.elapsedMilliseconds - renderMs}ms');
      }
    });
  }

  // ─── RTC v2 (P2P) ──────────────────────────────────────────────────────────
  // Non-null while this match has video at all: the payload carried an rtcV2
  // block. P2P is the only transport, so there is nothing to fall back to —
  // recovery is the session's own rebuild loop. It deliberately survives leg
  // transitions (BO3 ranked AND tournament): the peers never change between
  // legs, so there is nothing to re-key either.
  /// The whole P2P path in one object (session + native track + recovery
  /// loop) — see [P2pMatchVideo]. Null when the match got no video block.
  P2pMatchVideo? p2pVideo;
  // Opponent-turn dart zoom: driven by OpponentDartFlash, painted by the
  // remote video (BoardSafeVideo). One per screen, idle outside their turn.
  final VideoZoomController videoZoom = VideoZoomController();
  // Ownership token of the static outgoing-crop state (OpponentVideoFraming):
  // this screen's deferred dispose must not wipe a successor match screen's.
  int? _framingGeneration;

  // Guards initializeP2p against concurrent entry (initial init racing the
  // reconnect relaunch).
  bool _p2pInitInFlight = false;

  // Tracks the tournamentState==seriesEnded transition: tournament P2P calls
  // skip the historical per-leg teardown, so the series verdict is what ends
  // the call (mirrors _sawSeriesEnded for ranked BO3).
  bool _sawTournamentSeriesEnded = false;
  // True while the camera is being flipped front/back, so the build shows the
  // placeholder instead of a LocalCameraPreview bound to a disposed controller.
  bool switchingCamera = false;
  bool isAudioMuted = true;
  bool permissionsGranted = false;
  bool cameraZoomInitialized = false;
  double cameraZoom = 1.0;
  double cameraMinZoom = 1.0;
  double cameraMaxZoom = 1.0;
  bool isLoading = true;
  AutoScoringService? autoScoringService;
  bool autoScoringEnabled = false;
  bool autoScoringLoading = false;
  bool aiManuallyDisabled = false;
  bool aiPausedForEdit = false;
  CaptureFrameCallback? _captureFrameCallback;
  CaptureRgbaCallback? _captureRgbaCallback;
  CaptureBgraCallback? _captureBgraCallback;
  CaptureYuvCallback? _captureYuvCallback;
  OnDartDetectedCallback? _onDartDetectedCallback;
  // Impact timestamps of MY current visit (AI-detected) — the replay pill's
  // capture window is [first dart − 2s, tap]. Cleared when my turn starts.
  final List<DateTime> _turnDartTimes = [];
  // Earliest instant the current visit can have started: my turn beginning, or
  // the new leg's start when the checkout kept the turn. The ring keeps
  // encoding across that leg boundary (still my turn), so without this floor
  // the manual-scoring fallback window (now − 20s) reached back into the
  // previous leg exactly like the stale [_turnDartTimes] did.
  DateTime? _replayWindowFloor;

  /// The opponent's remaining score at the start of their current visit — what
  /// a checkout on it is worth. See the turn-change block.
  int? _opponentScoreAtVisitStart;
  /// Clips captured during this screen's match/series, newest last — handed
  /// to MatchEndView, where sharing happens.
  final List<ReplayClip> matchReplayClips = [];
  String? lastKnownCurrentPlayer;
  // Last leg number seen (BO3 ranked series / tournament series). Detects leg
  // transitions that turn-change detection misses: when the SAME player ends
  // one leg (checkout keeps the turn) and starts the next, currentPlayerId
  // never changes, so without this the empty-board gate is not re-armed and
  // the AI re-scores the darts still in the board from the finishing visit.
  int? _lastKnownLeg;
  // Signature of the visit the caller last announced, so a full 3-dart round is
  // called exactly once even though handleSharedStateChange fires on every
  // provider notify. Cleared at the start of each of our turns.
  String? _lastCalledVisitSignature;
  // Same guard for the opponent's visit — their throws stream in live via
  // score_updated, so without a signature the total would be announced on
  // every provider notify after their third dart.
  String? _lastCalledOpponentVisitSignature;
  bool winDialogShowing = false;
  bool bustDialogShowing = false;
  bool forfeitDialogShowing = false;
  // Why: iOS fires inactive → resumed for sub-second blips (screenshot,
  // notification, control center). Re-syncing the call on every blip is pure
  // churn. Track whether we actually backgrounded so we only re-sync after a
  // real paused state.
  bool _wasPausedSinceLastResume = false;

  // ─── Wakelock re-assert ────────────────────────────────────────────────────────
  // Why: WakelockPlus is a single, non-refcounted window flag
  // (FLAG_KEEP_SCREEN_ON on Android). We are pushed via pushAndRemoveUntil()
  // over the matchmaking / training screen, and that screen calls
  // WakelockPlus.disable() in its dispose(). Flutter defers disposing a route
  // *beneath* a still-animating pushed route until the push transition
  // completes, so that disable() lands ~300ms AFTER our initState enable() and
  // WINS — clearing the flag for the whole match, so the screen sleeps (most
  // visibly during the opponent's turn, when nobody touches the screen).
  // Rather than race that single late disable() with animation-status timing
  // (fragile, and the timing varies per entry path: matchmaking, friend,
  // tournament), we re-assert the wakelock on a short periodic timer for the
  // whole match. enable() is idempotent and cheap, so this is a no-op in
  // steady state and deterministically recovers the flag within one tick after
  // any stray disable() — no matter which screen cleared it or when.
  Timer? _wakelockReassertTimer;
  static const Duration _wakelockReassertInterval = Duration(seconds: 3);

  // ─── Auto-scoring loading watchdog ─────────────────────────────────────────
  // autoScoringLoading drives a FULL-SCREEN overlay that replaces the game UI.
  // Every path that sets it true relies on an async completion to clear it
  // (model load, RTC relaunch, a game_state_sync that may never arrive on
  // the rejoin path). If that completion wedges — e.g. the native inference
  // thread is stuck on a hung GPU call, so the next loadModel never returns —
  // the player is locked out of the whole match. This watchdog only drops the
  // overlay: the model load / capture start keep running in the background and
  // the AI still comes up whenever they complete (plus the per-turn self-heal
  // retry in handleSharedStateChange).
  Timer? _autoScoringLoadingWatchdog;
  static const Duration _autoScoringLoadingMaxWait = Duration(seconds: 30);

  // ─── "Match won't start" recovery ──────────────────────────────────────────
  // game_started is a single un-replayed push to the match room. If this
  // device isn't in that room when it fires — most bluntly, if its socket is
  // dead or belongs to another account — nothing ever flips gameStarted and
  // the player stared at "INITIALISATION DU MATCH…" forever, with no hint of
  // what was wrong and no way out but killing the app. Shared by ranked,
  // friendly and tournament: they all render buildInitializingScreen().
  Timer? _startStallTimer;
  bool startStalled = false;
  bool retryingStart = false;
  static const Duration _startStallDelay = Duration(seconds: 10);

  /// Arm (once) the deadline after which the init spinner becomes an
  /// actionable "the match isn't starting" screen. Called from the spinner's
  /// own build, so it covers every entry path without each screen wiring it.
  void _armStartStallTimer() {
    if (_startStallTimer != null || startStalled) return;
    _startStallTimer = Timer(_startStallDelay, () {
      if (!mounted) return;
      // Read the provider rather than trusting the cached flag: on the rejoin
      // path the listener is attached after a multi-second camera/AI init.
      bool started = gameStarted;
      try { started = readGame().gameStarted as bool; } catch (_) {}
      if (!started) setState(() => startStalled = true);
    });
  }

  void _cancelStartStallTimer() {
    _startStallTimer?.cancel();
    _startStallTimer = null;
  }

  /// Manual recovery from the stalled screen: make sure we have a socket that
  /// belongs to THIS user, re-attach the provider's listeners, then ask the
  /// server to re-send the state. Same three steps for every match type.
  Future<void> retryMatchStart() async {
    if (retryingStart) return;
    setState(() => retryingStart = true);
    try {
      await SocketService.ensureAuthenticated();
      if (!mounted) return;
      final game = readGame();
      game.ensureListenersSetup();
      game.reconnectToMatch();
    } catch (e) {
      debugPrint('[BaseGameScreen] retryMatchStart failed: $e');
    }
    if (!mounted) return;
    setState(() {
      retryingStart = false;
      startStalled = false;
    });
    _cancelStartStallTimer();
    _armStartStallTimer();
  }

  /// (Re-)arm the deadline after which a still-true [autoScoringLoading] is
  /// force-cleared. Call whenever autoScoringLoading is set to true.
  void armAutoScoringLoadingWatchdog() {
    _autoScoringLoadingWatchdog?.cancel();
    _autoScoringLoadingWatchdog = Timer(_autoScoringLoadingMaxWait, () {
      if (mounted && autoScoringLoading) {
        debugPrint('[BaseGameScreen] auto-scoring loading watchdog fired — '
            'unblocking game UI (AI init continues in background)');
        setState(() => autoScoringLoading = false);
      }
    });
  }

  // ─── Lifecycle ────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WakelockPlus.enable();
    _wakelockReassertTimer = Timer.periodic(
      _wakelockReassertInterval,
      (_) { if (mounted) WakelockPlus.enable(); },
    );
    OrientationUtils.allowAll();
    // Both roles of the report feature start listening here and stay attached
    // for the whole screen — which spans a whole BO3/tournament series. The
    // REPORTED side matters most: a player who never flags anything still has
    // to answer a capture request, silently.
    TurnReportService.listen();
    _framingGeneration = OpponentVideoFraming.claim();
    autoScoringService = AutoScoringService();
    autoScoringService!.telemetrySessionOf =
        () => (aiTelemetryContext, matchIdForLeave);
    scoreAnimationController = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      try {
        await initScreenSpecific().timeout(
          const Duration(seconds: 30),
          onTimeout: () => debugPrint('[Init] init timed out after 30s'),
        );
      } catch (e) {
        debugPrint('[BaseGameScreen] Init error: $e');
      }
      if (mounted) setState(() => isLoading = false);
    });
  }

  @override
  void dispose() {
    // Abandon/quit before the series verdict: the deferred replay tail must
    // still run (async — it survives this screen; renders need only the clip
    // files, not the ring). No-op when the series-end transition already ran.
    processPendingReplayClips();
    // Static and self-guarded, so unlike the replay tail it is re-fired here
    // on purpose: it also drains a checkout-race capture that landed after
    // the verdict's flush.
    DatasetCaptureService.flush();
    WidgetsBinding.instance.removeObserver(this);
    _wakelockReassertTimer?.cancel();
    _wakelockReassertTimer = null;
    _autoScoringLoadingWatchdog?.cancel();
    _autoScoringLoadingWatchdog = null;
    _legEndTicker?.cancel();
    _legEndTicker = null;
    _cancelStartStallTimer();
    disposeScreenSpecific();
    scoreAnimationController.dispose();
    WakelockPlus.disable();
    OrientationUtils.portraitOnly();
    autoScoringService?.dispose();
    autoScoringService = null;
    RtcFramesService.onSendActiveChanged = null;
    cameraFrameService?.dispose();
    cameraFrameService = null;
    // P2P: fire-and-forget, mirroring the un-awaited leaveChannel below (a
    // State.dispose can't await). The controller sends the telemetry report
    // and releases the native track.
    p2pVideo?.stopDetached();
    p2pVideo = null;
    videoZoom.dispose();
    // Outgoing board crop + zoom bookkeeping is static, like the turn gate
    // it follows: forget this match's board — unless a newer match screen
    // already owns it (deferred-dispose overlap).
    OpponentVideoFraming.reset(ifGeneration: _framingGeneration);
    TurnReportService.stopListening();
    // Drops the visits cached for this match, including the winning one the
    // end screens could still flag. Runs at dispose and not at match end on
    // purpose: those screens are still up until the player leaves them.
    final reportedMatchId = matchIdForLeave;
    if (reportedMatchId != null) TurnReportService.disposeMatch(reportedMatchId);
    // A flag left uncompleted here (back button, app kill) is abandoned rather
    // than carried into the next match's list; the server purges its row and
    // clip within 24h.
    TurnReportService.clearPending();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      cameraFrameService?.pause();
      _wasPausedSinceLastResume = true;
    } else if (state == AppLifecycleState.inactive) {
      // Brief interruption (screenshot, notification banner, control center).
      // Pause the camera but DO NOT mark as backgrounded — a resumed event
      // immediately after an inactive-only blip should not trigger a full
      // socket/call re-sync.
      cameraFrameService?.pause(releaseCamera: false);
    } else if (state == AppLifecycleState.resumed && mounted) {
      final camera = cameraFrameService;
      camera?.resume().then((_) {
        if (mounted && identical(cameraFrameService, camera)) setState(() {});
      });
      // Re-assert on every resume: a backgrounded/recreated activity can come
      // back without FLAG_KEEP_SCREEN_ON. Cheap no-op if already set.
      WakelockPlus.enable();
      if (!_wasPausedSinceLastResume) {
        // Came back from a brief inactive blip — no socket/call work needed.
        return;
      }
      _wasPausedSinceLastResume = false;
      if (!kIsWeb && Platform.isAndroid) p2pVideo?.onAppResumed();
      // App actually backgrounded — re-sync everything. A connect timeout used
      // to surface as an unhandled future error, and reconnectToMatch never
      // ran: recovery then depended entirely on the reconnect listener.
      SocketService.ensureConnected().then((_) {
        if (!mounted) return;
        final game = readGame();
        // Re-register socket listeners FIRST: reconnect_to_match's reply
        // (game_state_sync) is useless if nothing is listening for it.
        game.ensureListenersSetup();
        // Tell the server we're back so opponent sees us as connected
        game.reconnectToMatch();
      }).catchError((Object e) {
        debugPrint('[BaseGameScreen] resume reconnect failed: $e');
      });
    }
  }

  // ─── State-change handler ─────────────────────────────────────────────────────
  void handleSharedStateChange() {
    if (!mounted) return;
    try {
      final game = readGame();
      gameStarted = game.gameStarted;
      if (gameStarted) {
        _cancelStartStallTimer();
        startStalled = false;
        // A LIVE game on a screen whose previous verdict already ran the
        // replay drain (friendly rematch): captures must queue for the next
        // verdict again, not drain mid-match.
        if (_replayProcessingStarted && !game.gameEnded) {
          _replayProcessingStarted = false;
        }
      }
      final wasGameEnded = gameEnded;
      gameEnded = game.gameEnded;
      if (game.gameEnded && !wasGameEnded && game.winnerId != null) {
        final auth = Provider.of<AuthProvider>(context, listen: false);
        if (game.winnerId == auth.currentUser?.id) {
          DartSoundService.playWin();
          // I just checked out: the turn never flips after a winning visit, so
          // the usual end-of-turn cache never runs for the one visit the loser
          // is most likely to want looked at. Cut it now and keep it aside —
          // their end-of-leg screen can still flag it minutes later.
          cacheWinningVisitForReports(game);
        } else {
          DartSoundService.playLose();
        }
      }
      // Why: tear down the call/camera as soon as the match ends instead of
      // waiting for the user to navigate away from the end screen. Otherwise
      // it keeps burning battery and bandwidth while the user reads their ELO
      // result. dispose() in the widget lifecycle remains as a safety net for
      // the back-arrow / app-kill paths.
      //
      // EXCEPT between BO3 legs (D7): the series continues against the same
      // opponent within seconds, and a teardown + full rebuild (session,
      // camera, model reload) on an already-hot phone was exactly the CoreML
      // recompile scenario of the July regression. Keep the session alive — it
      // spans legs, so the next leg needs nothing re-keyed. Tournament
      // providers don't expose these getters (try/catch), so tournaments keep
      // the historical full teardown per leg. A forfeit ends the series no
      // matter what the leg counters say.
      bool seriesGoesOn = false;
      try {
        seriesGoesOn = (game.isRankedSeries as bool) &&
            !(game.seriesEnded as bool) &&
            game.pendingType != 'forfeit';
      } catch (_) {}
      final toreDownNow = game.gameEnded && !wasGameEnded && !seriesGoesOn;
      if (toreDownNow) {
        // P2P sessions survive tournament legs too (same peers next leg —
        // keeping camera, AI and call alive avoids the multi-second rebuild);
        // the series verdict below ends the call instead. A match with no
        // video block has nothing to keep, and tears down as before.
        if (p2pVideo == null || !_tournamentSeriesGoesOn(game)) {
          endMatchCall();
        }
      }
      // The FINAL leg ends while the series still reads as ongoing (game_won
      // arrives moments before ranked_match_won), so the branch above skips
      // it — tear down on the seriesEnded transition instead.
      bool seriesEndedNow = false;
      try { seriesEndedNow = game.seriesEnded as bool; } catch (_) {}
      if (seriesEndedNow && !_sawSeriesEnded && !toreDownNow) {
        endMatchCall();
      }
      _sawSeriesEnded = seriesEndedNow;
      // P2P + tournament: the per-leg teardown was skipped above, so end the
      // call on the tournamentState==seriesEnded transition (the ranked
      // seriesEnded getter doesn't exist on the tournament provider).
      bool tournamentSeriesEndedNow = false;
      try {
        tournamentSeriesEndedNow =
            game.tournamentState == TournamentGameState.seriesEnded;
      } catch (_) {}
      if (p2pVideo != null &&
          tournamentSeriesEndedNow &&
          !_sawTournamentSeriesEnded) {
        endMatchCall();
      }
      _sawTournamentSeriesEnded = tournamentSeriesEndedNow;
      // The match verdict is when the deferred replay renders + uploads run —
      // the end screen is up and the match load is gone. Three shapes, same
      // ones that gate the call teardown: a FRIENDLY has no series at all
      // (seriesEnded stays false — 2026-08-04 on-device: friendly clips sat
      // "preparing" until the screen died), so its verdict is the plain
      // gameEnded transition, minus tournament legs whose series goes on.
      // Guarded internally, safe on every notify.
      final matchOverNow = toreDownNow && !_tournamentSeriesGoesOn(game);
      if (matchOverNow || seriesEndedNow || tournamentSeriesEndedNow) {
        processPendingReplayClips();
        // Same deferral contract for the dataset frames: raw copies queued
        // mid-match, encode + upload only now that the call/AI load is gone.
        DatasetCaptureService.flush();
      }
      // Replay ring turn gate: encode only while I throw (the local camera
      // films MY board — the opponent's turn is dead footage and half the
      // encoder heat). Idempotent, safe on every notify.
      ReplayBufferService.setMyTurn(game.isMyTurn);
      // Match proof: keep the retention registry aware of every id this
      // series answers to (per-leg matchIds, seriesId) so a dispute on any
      // of them finds the footage. Cheap and idempotent.
      MatchProofService.noteId(_gameMatchIdOf(game) ?? matchIdForLeave);
      try {
        MatchProofService.noteId(game.seriesId as String?);
      } catch (_) {}
      // Same turn gate for the outgoing P2P video (thermal audit 2026-08-10):
      // the opponent's screen only renders OUR stream during OUR turn, so
      // full-rate pushing + encoding during theirs heated both phones for a
      // feed nobody displayed. This notify IS the turn-change moment (the
      // turn-finished sound below fires off it); the service closes 1s
      // later (Lucas's spec) and then only trickles at ~1 fps — never
      // silence, the peer's stall watchdog needs frames flowing (see
      // RtcFramesService). Audio stays live; no-op in solo modes.
      RtcFramesService.setSendActive(game.isMyTurn);
      // Same turn moment for the outgoing board crop: my turn re-measures
      // the square until my first dart, their turn keeps it still.
      OpponentVideoFraming.setMyTurn(game.isMyTurn);
      if (game.currentPlayerId != lastKnownCurrentPlayer && lastKnownCurrentPlayer != null) {
        if (game.isMyTurn) {
          DartSoundService.playYourTurn();
          // Fresh visit: the replay pill's capture window restarts here.
          _turnDartTimes.clear();
          _replayWindowFloor = DateTime.now();
        } else {
          DartSoundService.playTurnFinished();
          // Their visit starts now, so their remaining score IS what a
          // checkout would be worth. Snapshotted because a winning visit never
          // lands in opponentRounds (a checkout produces no round_confirmed),
          // and the end-screen banner would otherwise name the wrong number.
          try {
            _opponentScoreAtVisitStart = game.opponentScore as int?;
          } catch (_) {}
          // My visit just ended: cut it out of the ring and keep it locally,
          // in case my opponent flags it. Nothing is sent — see
          // [cacheVisitForReports].
          cacheVisitForReports(game);
        }
      }
      // lastKnownCurrentPlayer == null means this is the FIRST run since the
      // listener was attached — and it is attached after the multi-second
      // call/camera init, so game_started and the join notifies were likely
      // all missed. That first run is a baseline, never a turn change: without
      // the null guard (same one the sound block above uses), a first run
      // triggered by the score echo of the match's first dart reset the AI
      // slots and re-armed the empty-board gate MID-VISIT — the dart stayed
      // scored server-side while the UI asked to remove it. Match-start gate
      // arming doesn't rely on this path: initAutoScoring arms it explicitly.
      final justBecameMyTurn = game.isMyTurn &&
          lastKnownCurrentPlayer != null &&
          game.currentPlayerId != lastKnownCurrentPlayer;
      // New leg in a series (BO3 ranked / tournament): always clear the turn
      // slots and re-arm the empty-board gate, even when the same player
      // starts again (see _lastKnownLeg).
      int? legNow;
      try { legNow = game.currentLeg as int?; } catch (_) {}
      if (legNow != null && _lastKnownLeg != null && legNow != _lastKnownLeg) {
        aiPausedForEdit = false;
        autoScoringService?.resetTurn();
        autoScoringService?.waitForEmptyBoardOnce();
        _lastCalledVisitSignature = null;
        _lastCalledOpponentVisitSignature = null;
        // Same reason for the replay window: the checkout keeps the turn, so
        // the turn-change clear below never runs and the impact times of the
        // finishing visit survived into the new leg — a capture on the first
        // visit of leg 2 then opened 2s before the PREVIOUS leg's checkout
        // (25s clip holding the double + the 140, 2026-08-11 report).
        _turnDartTimes.clear();
        _replayWindowFloor = DateTime.now();
      }
      _lastKnownLeg = legNow;
      // Reset dart slots on turn change (always, even without AI capture) and
      // re-arm the empty-board gate: a player who ended their previous turn
      // without pulling their darts (END TURN pill, bust confirm) leaves them
      // in the board, and the AI used to re-score those three as this turn's
      // throws — then auto-confirm passed the turn before a single real dart
      // was thrown. The gate clears itself as soon as the board is seen empty.
      if (justBecameMyTurn) {
        aiManuallyDisabled = false;
        aiPausedForEdit = false;
        autoScoringService!.resetTurn();
        autoScoringService!.waitForEmptyBoardOnce();
      }
      // Caller: signature reset so the next visit is called even if it
      // repeats the previous visit's exact darts.
      if (justBecameMyTurn) {
        _lastCalledVisitSignature = null;
      }
      // Caller: announce the visit total once the server has accepted a full
      // 3-dart round (pendingConfirmation) that did NOT bust and did NOT win.
      // We can't decide this from the local darts alone: the throws hit 3
      // locally before the server rules, and on a bust/win the backend sends
      // pending_bust / pending_win with no score_updated. So we wait for the
      // verdict — round_ready_confirm is the ONLY outcome that leaves
      // pendingType null. Requiring exactly that (rather than "not a bust")
      // stops two wrong calls: a win announced while the confirm dialog is
      // still up and editable, and — because an edit mid-pending changes the
      // local darts without clearing pendingConfirmation — a busted edit
      // announced as a valid score. Also require every dart to be acked, so
      // we never read out a total the server hasn't got. Guard against ''
      // edit placeholders.
      if (game.isMyTurn) {
        final throws = game.currentRoundThrows as List<String>;
        final visitComplete = throws.length == 3 && throws.every((t) => t.isNotEmpty);
        int unacked = 0;
        try { unacked = (game.unackedDartCount as int?) ?? 0; } catch (_) {}
        if (visitComplete &&
            game.pendingConfirmation &&
            game.pendingType == null &&
            unacked == 0) {
          final sig = throws.join(',');
          if (sig != _lastCalledVisitSignature) {
            _lastCalledVisitSignature = sig;
            // Cricket has no called score — the totals are marks, not points.
            if (cricketStateOf(game) == null) {
              DartCallerService.callScore(game.currentRoundScore as int);
            }
          }
        } else if (throws.isEmpty) {
          _lastCalledVisitSignature = null;
        }
      }
      // Caller: announce the opponent's visit total as soon as the result of
      // their THIRD dart arrives — no need to wait for their round to be
      // committed. Unlike our own visit there is no pending/ack state to
      // consult for the remote side: their throws simply stream in via
      // score_updated and the list is cleared on round_complete, which also
      // re-arms the signature for their next visit. Early-ended opponent
      // turns (1–2 darts) never reach 3 throws and are not announced.
      {
        final oppThrows = game.opponentRoundThrows as List<String>;
        if (oppThrows.length == 3 && oppThrows.every((t) => t.isNotEmpty)) {
          final sig = oppThrows.join(',');
          if (sig != _lastCalledOpponentVisitSignature) {
            _lastCalledOpponentVisitSignature = sig;
            if (cricketStateOf(game) == null) {
              DartCallerService.callScore(
                  oppThrows.fold<int>(0, (sum, n) => sum + notationPoints(n)));
            }
          }
        } else if (oppThrows.isEmpty) {
          _lastCalledOpponentVisitSignature = null;
        }
      }
      // Caller: announce "you require <n>" when we come to the throw on a
      // finish (no-op otherwise). Deliberately AFTER the opponent-visit block:
      // both can fire on the same notify when their third dart and the turn
      // change land together, and the queue plays in enqueue order — a real
      // caller says "one hundred and forty… you require one hundred and one",
      // never the reverse.
      if (justBecameMyTurn && cricketStateOf(game) == null) {
        DartCallerService.callCheckout(game.myScore as int);
      }
      // Start/stop AI capture when supported
      if (autoScoringEnabled && !aiManuallyDisabled && _captureFrameCallback != null && autoScoringService!.modelLoaded) {
        final pendingNeedsStop = game.pendingConfirmation && (game.pendingType == 'bust' || game.pendingType == 'win');
        if (game.isMyTurn && !pendingNeedsStop && !autoScoringService!.isCapturing && !aiPausedForEdit) {
          if (!justBecameMyTurn && !game.pendingConfirmation) {
            // Darts the game layer accounts for: echoed by the server PLUS
            // those still in delivery. Passing only the echo let an in-flight
            // dart's slot be freed and re-emitted.
            int accounted = game.currentRoundThrows.length as int;
            try { accounted += (game.unackedDartCount as int?) ?? 0; } catch (_) {}
            autoScoringService!.syncEmittedCount(accounted);
          }
          autoScoringService!.startCapture(
            captureFrame: _captureFrameCallback!,
            captureRgba: _captureRgbaCallback,
            captureBgra: _captureBgraCallback,
            captureYuv: _captureYuvCallback,
            cleanupFile: (path) async { try { await File(path).delete(); } catch (_) {} },
            onDartDetected: _onDartDetectedCallback,
            onAutoConfirm: () { if (mounted) submitAutoScoredDarts(readGame()); },
          );
        } else if ((!game.isMyTurn || pendingNeedsStop) && autoScoringService!.isCapturing) {
          autoScoringService!.stopCapture();
        }
      }
      // Self-heal: a transient model-load failure at match start used to leave
      // the AI dead for the whole match (only an app restart recovered it). If
      // the model still isn't loaded when it becomes our turn, retry the load
      // in the background and start capture on success — no restart needed.
      // Guarded to one attempt per turn change; skipped while a load is running.
      if (justBecameMyTurn &&
          autoScoringEnabled &&
          !aiManuallyDisabled &&
          !kIsWeb &&
          AutoScoringService.isSupported &&
          _captureFrameCallback != null &&
          !autoScoringService!.modelLoaded &&
          !autoScoringService!.isModelLoading) {
        recoverAutoScoring();
      }
      lastKnownCurrentPlayer = game.currentPlayerId;
      if (game.pendingConfirmation && game.pendingType != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !context.mounted) return;
          if (game.pendingType == 'win' && !winDialogShowing) { showPendingWinDialog(game); }
          else if (game.pendingType == 'bust' && !bustDialogShowing) { DartSoundService.playBust(); showPendingBustDialog(game); }
        });
      }
      if (game.needsRtcReconnect == true) {
        game.clearRtcReconnectFlag();
        reconnectRtcTransport(game);
      }
      if (game.gameEnded && game.pendingType == 'forfeit') {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && context.mounted && !forfeitDialogShowing) showForfeitDialog(game);
        });
      }
      // Why: server emits reconnect_failed when a player rejoins after the
      // match has already ended. Without this, the player gets stuck on the
      // game screen with no way to learn the outcome.
      try {
        if (game.reconnectFailed == true) {
          game.clearReconnectFailedFlag();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && context.mounted) {
              final l10n = AppLocalizations.of(context);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(l10n.matchNoLongerInProgress),
                backgroundColor: AppTheme.error,
                duration: const Duration(seconds: 3),
              ));
              try { game.reset(); } catch (_) {}
              Navigator.of(context).popUntil((r) => r.isFirst);
            }
          });
        }
      } catch (e) {
        debugPrint('[BaseGameScreen] reconnectFailed handling error: $e');
      }
      onScreenSpecificStateChange(game);
    } catch (e, stack) {
      // This handler drives turn changes, capture start/stop and the pending
      // dialogs. Swallowing silently meant a single throw skipped everything
      // after it with zero diagnostics.
      debugPrint('[BaseGameScreen] handleSharedStateChange error: $e');
      debugPrint('$stack');
    }
  }

  void updateLoadingMessage(String msg) {
    if (mounted) setState(() => loadingMessage = msg);
  }

  // ─── Auto-scoring ─────────────────────────────────────────────────────────────
  Future<void> loadAutoScoringPref() async {
    if (kIsWeb || !AutoScoringService.isSupported) { autoScoringEnabled = false; return; }
    if (mounted) setState(() => autoScoringEnabled = true);
  }

  ScoreMultiplier dartScoreToMultiplier(DartScore dartScore) {
    switch (dartScore.ring) {
      case 'triple': return ScoreMultiplier.triple;
      case 'double':
      case 'double_bull': return ScoreMultiplier.double;
      default: return ScoreMultiplier.single;
    }
  }

  void toggleAiScoring() {
    if (!mounted) return;
    setState(() {
      aiManuallyDisabled = !aiManuallyDisabled;
      if (aiManuallyDisabled) {
        autoScoringService?.stopCapture();
      } else if (autoScoringEnabled && autoScoringService != null && autoScoringService!.modelLoaded && _captureFrameCallback != null) {
        final game = readGame();
        if (game.isMyTurn) autoScoringService!.startCapture(
          captureFrame: _captureFrameCallback!,
          captureRgba: _captureRgbaCallback,
          captureBgra: _captureBgraCallback,
          captureYuv: _captureYuvCallback,
          // Without this the file-capture fallback path leaks cam_frame_*.jpg
          // for the rest of the match after the AI is toggled back on.
          cleanupFile: (path) async { try { await File(path).delete(); } catch (_) {} },
          onDartDetected: _onDartDetectedCallback,
          onAutoConfirm: () { if (mounted) submitAutoScoredDarts(readGame()); },
        );
      }
    });
  }

  /// [armEmptyBoardGate] must be false when re-initializing MID-TURN (an RTC
  /// relaunch): the board still holds this turn's darts, so the gate would
  /// never clear until takeout and every remaining dart of the turn would go
  /// unscored. At match start / turn start the board is expected empty.
  Future<void> initAutoScoring({bool armEmptyBoardGate = true}) async {
    if (cameraFrameService == null || kIsWeb || !AutoScoringService.isSupported) return;
    if (!mounted) return;
    setState(() {
      autoScoringEnabled = true;
      autoScoringLoading = true;
    });
    armAutoScoringLoadingWatchdog();
    final camService = cameraFrameService!;
    _captureFrameCallback = () => camService.captureFrame();
    _captureRgbaCallback = () => camService.captureRgba();
    _captureBgraCallback = () => camService.captureBgra();
    _captureYuvCallback = () => camService.captureYuvPlanes();
    _onDartDetectedCallback = (_, dartScore) {
      if (!mounted) return;
      final g = readGame();
      if (!g.isMyTurn || g.pendingConfirmation) return;
      // Impact time of this dart — the replay clip window opens 2s before
      // the first one of the visit.
      _turnDartTimes.add(DateTime.now());
      final (base, mul) = dartScoreToBackend(dartScore);
      HapticService.mediumImpact();
      DartSoundService.playDartHit(base, mul);
      // Tag as AI-proposed so the backend can score the trust factor (accepted
      // vs corrected). Manual entry/edits flow through the default 'manual'.
      // The tip's position travels with it: radius/angle are already in the
      // scorer's normalized board frame, so nothing is converted here. Together
      // with a later correction by the player, they are a ground-truth training
      // sample — the reason any of this is worth sending.
      // Where the dart sits on the video the opponent receives — their
      // screen zooms on it (OpponentDartFlash). Null when the sender could
      // not place it; the dart scores the same either way.
      final vx = dartScore.videoX, vy = dartScore.videoY;
      g.throwDart(
        baseScore: base,
        multiplier: mul,
        source: 'ai',
        radius: dartScore.radius,
        angle: dartScore.angle,
        confidence: dartScore.confidence,
        zoom: vx != null && vy != null ? VideoPoint(vx, vy) : null,
      );
    };
    await autoScoringService!.loadModel();
    if (mounted) {
      setState(() => autoScoringLoading = false);
      if (autoScoringService!.modelLoaded) {
        // Arm the one-shot "empty board" gate so practice darts thrown while
        // the player was in the queue don't get counted in the new match.
        // The gate clears itself once the camera sees an empty dartboard.
        if (armEmptyBoardGate) autoScoringService!.waitForEmptyBoardOnce();
        final game = readGame();
        if (game.isMyTurn) {
          autoScoringService!.startCapture(
            captureFrame: _captureFrameCallback!,
            captureRgba: _captureRgbaCallback,
            captureBgra: _captureBgraCallback,
            captureYuv: _captureYuvCallback,
            cleanupFile: (path) async { try { await File(path).delete(); } catch (_) {} },
            onDartDetected: _onDartDetectedCallback,
            onAutoConfirm: () { if (mounted) submitAutoScoredDarts(readGame()); },
          );
        }
      }
    }
  }

  /// Retry a failed auto-scoring model load mid-match (self-heal). A transient
  /// native load failure at match start used to leave the AI dead until the app
  /// was restarted; this recovers it on a later turn instead. Silent — no
  /// loading overlay — so the player keeps manual scoring while it retries, then
  /// AI detections start flowing once the model loads.
  Future<void> recoverAutoScoring() async {
    final svc = autoScoringService;
    if (svc == null || _captureFrameCallback == null) return;
    await svc.loadModel();
    if (!mounted) return;
    // Rebuild so the AI toggle reflects the now-loaded model.
    setState(() {});
    if (!svc.modelLoaded) return;
    final game = readGame();
    if (!game.isMyTurn || svc.isCapturing || aiManuallyDisabled) return;
    // Practice darts left in the board from the queue warm-up shouldn't count.
    // Only when the visit hasn't started: arming mid-turn would stall the AI
    // until the player pulls this turn's darts (i.e. for the rest of the turn).
    final roundEmpty = (game.currentRoundThrows as List).isEmpty &&
        ((game.unackedDartCount as int?) ?? 0) == 0;
    if (roundEmpty) svc.waitForEmptyBoardOnce();
    svc.startCapture(
      captureFrame: _captureFrameCallback!,
      captureRgba: _captureRgbaCallback,
      captureBgra: _captureBgraCallback,
      captureYuv: _captureYuvCallback,
      cleanupFile: (path) async { try { await File(path).delete(); } catch (_) {} },
      onDartDetected: _onDartDetectedCallback,
      onAutoConfirm: () { if (mounted) submitAutoScoredDarts(readGame()); },
    );
  }

  /// Commit the current turn.
  ///
  /// The turn ends on exactly one rule, whether the AI or the player triggers
  /// it: at least one dart was detected, and the board has been seen empty
  /// (the AI's 3-consecutive-frame takeout check). A visit of fewer than 3
  /// darts is legitimate — a dart that bounces out or drops off the board
  /// scores nothing but still counts as thrown, and `end_round_early` pads the
  /// visit with S0 accordingly. Never second-guess the count here: the dart
  /// that must not be lost is protected by the delivery layer instead
  /// (confirmRound waits for every in-flight dart to be acked, and the server
  /// refuses a confirm whose dartCount disagrees with its own).
  void submitAutoScoredDarts(dynamic game) {
    aiPausedForEdit = false;
    autoScoringService?.stopCapture();
    // The AI only closes a turn once it has seen the board empty, so a visit
    // that lands here with fewer than three darts is one where a dart was
    // thrown and did not stay in the board. Saying so keeps the server from
    // booking its S0 filler as a dart thrown at a double.
    game.confirmRound(endReason: 'bounce_out');
  }

  /// Restart AI capture after the dart-edit modal closes (including cancel).
  /// Mid-turn, so the empty-board gate is never re-armed here.
  void resumeCaptureAfterEdit() {
    if (!mounted) return;
    final svc = autoScoringService;
    if (svc == null ||
        !autoScoringEnabled ||
        aiManuallyDisabled ||
        aiPausedForEdit ||
        !svc.modelLoaded ||
        svc.isCapturing ||
        _captureFrameCallback == null) {
      return;
    }
    final game = readGame();
    final pendingNeedsStop = game.pendingConfirmation &&
        (game.pendingType == 'bust' || game.pendingType == 'win');
    if (!game.isMyTurn || pendingNeedsStop || game.gameEnded) return;
    svc.startCapture(
      captureFrame: _captureFrameCallback!,
      captureRgba: _captureRgbaCallback,
      captureBgra: _captureBgraCallback,
      captureYuv: _captureYuvCallback,
      cleanupFile: (path) async { try { await File(path).delete(); } catch (_) {} },
      onDartDetected: _onDartDetectedCallback,
      onAutoConfirm: () { if (mounted) submitAutoScoredDarts(readGame()); },
    );
  }

  // ─── RTC v2 (P2P) ─────────────────────────────────────────────────────────────

  /// Starts match video, and arms the rejoin catch-up. The only entry point
  /// the screens need. P2P is the sole transport: when the payload carries no
  /// rtcV2 verdict yet, we start nothing here and let the sync-driven
  /// [reconnectRtcTransport] launch the call as soon as one lands.
  Future<void> startMatchVideo({
    required dynamic game,
    required String? matchId,
    required String opponentId,
  }) async {
    final rtcV2 = _rtcV2ConfigOf(game);
    // No matchId means no signaling scope — starting a call nobody can reach
    // is worse than starting none (the tournament screen's historical
    // currentGameMatchId guard).
    if (rtcV2 != null && matchId != null && RtcFramesService.isSupported) {
      updateLoadingMessage('Starting camera...');
      await initializeP2p(
        matchId: matchId,
        opponentId: opponentId,
        config: rtcV2,
      );
    }
    game.addListener(handleSharedStateChange);
    updateLoadingMessage('Loading AI model...');
    await loadAutoScoringPref();
    // Rejoin: credentials arrive later via game_state_sync, so show the
    // spinner rather than the manual dartboard until the model loads. On the
    // P2P path the camera/AI are already up, hence the p2pVideo guard.
    if (autoScoringEnabled &&
        p2pVideo == null &&
        !kIsWeb &&
        AutoScoringService.isSupported) {
      setState(() => autoScoringLoading = true);
      // If game_state_sync never arrives (or the reconnect wedges), the
      // watchdog drops the blocking overlay instead of spinning forever.
      armAutoScoringLoadingWatchdog();
      // A sync may have fired before the listener was attached: process the
      // pending reconnect now instead of waiting for the next notification.
      if (game.needsRtcReconnect == true) {
        game.clearRtcReconnectFlag();
        reconnectRtcTransport(game);
      }
    }
  }

  /// Shared RTC recovery for a consumed reconnect flag — called from the
  /// provider listener AND from the screens' pre-listener catch-up. Either
  /// re-drives the live session or launches one; never gives up on P2P,
  /// because there is nothing else to give up TO.
  void reconnectRtcTransport(dynamic game) {
    if (p2pVideo != null) {
      // P2P: nothing to re-key — the session spans legs and socket
      // reconnects. BUT the sync that brought us here proves the socket
      // works again: if the media link is down, re-drive the negotiation —
      // any restart offer emitted while the socket was dead was lost
      // forever (no replay), and waiting wedged the airplane-mode test.
      if (!p2pVideo!.isLinkUp) {
        // The socket is proof the network is usable again: renegotiate NOW —
        // any offer emitted into the dead socket was lost forever (signals
        // have no replay).
        p2pVideo!.onSocketReconnected();
      }
      return;
    }
    final rtcV2 = _rtcV2ConfigOf(game);
    final relaunchMatchId = _gameMatchIdOf(game) ?? matchIdForLeave;
    final relaunchOpponentId = _opponentIdOf(game);
    if (rtcV2 != null &&
        relaunchMatchId != null &&
        relaunchOpponentId != null &&
        RtcFramesService.isSupported) {
      // The sync rehydrated an rtcV2 verdict but no session is live
      // (init raced the credentials, or this is a rejoin): relaunch
      // P2P — otherwise the surviving opponent's offers land on a screen
      // with no rtc_signal handler and both sides sit on dead video.
      // Fire-and-forget like the initial init.
      initializeP2p(
        matchId: relaunchMatchId,
        opponentId: relaunchOpponentId,
        config: rtcV2,
      );
      return;
    }
    // Nothing to start yet — most often a sync that landed before the server
    // had both players' sockets and so carried no rtcV2 block. Deliberately a
    // no-op: there is no second transport to try, and the one that used to be
    // here captured the match on a transport the opponent was not using AND
    // blocked every later P2P relaunch (2026-08-13). The next sync brings the
    // verdict, and the in-flight init guard makes a duplicate call harmless.
    debugPrint('[BaseGameScreen] reconnectRtcTransport: no rtcV2 verdict yet '
        '(match=$relaunchMatchId, opponent=$relaunchOpponentId) — waiting');
  }

  /// Defensive reads over the two provider shapes (GameProvider /
  /// TournamentGameProvider), which don't share an interface.
  RtcV2Config? _rtcV2ConfigOf(dynamic game) {
    try {
      return game.rtcV2Config as RtcV2Config?;
    } catch (_) {
      return null;
    }
  }

  String? _gameMatchIdOf(dynamic game) {
    try {
      final id = game.matchId as String?;
      if (id != null) return id;
    } catch (_) {}
    try {
      return game.currentGameMatchId as String?;
    } catch (_) {}
    return null;
  }

  String? _opponentIdOf(dynamic game) {
    try {
      return game.opponentUserId as String?;
    } catch (_) {
      return null;
    }
  }

  /// Establish the P2P (RTC v2) call and wire the camera/AI pipeline to it:
  /// the camera service pushes into the WebRTC track (p2pMode) and feeds the
  /// same TFLite capture callbacks.
  ///
  /// No fallback, because there is no other transport: connection failures are
  /// the recovery loop's job (it rebuilds until the network lets it through),
  /// and a camera failure degrades to a receive-only call (tagged in
  /// telemetry) rather than ending it.
  Future<void> initializeP2p({
    required String matchId,
    required String opponentId,
    required RtcV2Config config,
  }) async {
    // Re-entry guard: the reconnect relaunch is fire-and-forget from a
    // provider listener that can notify repeatedly, and two concurrent
    // sessions would fight over the single rtc_signal handler slot.
    if (p2pVideo != null || _p2pInitInFlight) return;
    _p2pInitInFlight = true;
    // Camera for the app-owned capture, mic for the WebRTC audio track.
    if (!kIsWeb) {
      permissionsGranted = await MediaPermissions.requestCameraAndMic();
      if (!permissionsGranted) {
        _p2pInitInFlight = false;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(AppLocalizations.of(context)
                  .cameraAndMicPermissionRequired),
              backgroundColor: AppTheme.error));
        }
        return;
      }
    } else {
      permissionsGranted = true;
    }
    final video = P2pMatchVideo(
      matchId: matchId,
      opponentId: opponentId,
      configProvider: () => _rtcV2ConfigOf(readGame()) ?? config,
      onChanged: () {
        if (mounted) setState(() {});
      },
    );
    p2pVideo = video;
    // A mid-match relaunch builds a FRESH P2pMatchVideo whose mic starts
    // muted, while the screen's toggle still shows whatever the player chose
    // — an unmuted player went silently mute at every relaunch (device test
    // 2026-08-31). Re-assert the UI state; the video object re-applies it on
    // every session (re)connect.
    if (!isAudioMuted) video.setMicEnabled(true);
    try {
      await video.start();
      if (!mounted) return;
      if (!kIsWeb) {
        cameraFrameService = CameraFrameService();
        await cameraFrameService!.initialize(p2pMode: true, replayRing: true);
        // Capture throttle rides the same turn gate as the P2P push cadence
        // (my turn = 15 fps, opponent's turn +1s = ~2 fps at the native
        // source). Wired here — not in the service — because the gate flag is
        // static while the camera service is per-screen.
        RtcFramesService.onSendActiveChanged =
            (active) => cameraFrameService?.setCaptureGated(!active);
        cameraFrameService?.setCaptureGated(!RtcFramesService.sendActive);
        // Match proof: retain the whole match's my-turn segments (same
        // encoder — zero extra heat) so a result dispute can pull the full
        // footage. Keyed by the leg-1 matchId; later legs/seriesId register
        // on every state notify.
        if (ReplayBufferService.armed) {
          MatchProofService.startMatch(key: matchId);
          TurnReportService.activeRetentionKey = matchId;
        }
        await initCameraZoom();
        if (!mounted) {
          // The screen died during the camera init: this instance was
          // created AFTER State.dispose ran, so nobody else will release
          // it — the device would stay locked ("camera already in use")
          // for the next match.
          try {
            await cameraFrameService?.dispose();
          } catch (_) {}
          cameraFrameService = null;
          return;
        }
        // Fire-and-forget so the game screen shows immediately;
        // autoScoringLoading drives the UI loading state.
        initAutoScoring();
      }
    } catch (e) {
      // Camera/AI init failed — the call itself keeps going (receive-only
      // at worst, the recovery loop owns the transport) and the player
      // still has the manual dartboard.
      debugPrint('[BaseGameScreen] initializeP2p error: $e');
      if (mounted) setState(() => autoScoringLoading = false);
    } finally {
      _p2pInitInFlight = false;
    }
  }

  /// True while a TOURNAMENT series still has legs to play. The tournament
  /// provider exposes tournamentState instead of the ranked provider's
  /// isRankedSeries/seriesEnded getters; every non-tournament provider throws
  /// here and yields false.
  bool _tournamentSeriesGoesOn(dynamic game) {
    try {
      return game.tournamentState != TournamentGameState.seriesEnded &&
          game.pendingType != 'forfeit';
    } catch (_) {
      return false;
    }
  }

  /// Ends the live call (P2P session) plus the shared camera pipeline.
  ///
  /// Camera FIRST — same order as dispose(). It is the local, fast half
  /// (image stream, replay ring, AI tee) and it must stop feeding the
  /// transports before they are torn down. Gating it behind p2pVideo.stop()
  /// left the whole camera pipeline running on the end screen whenever that
  /// stop dragged (telemetry emit, native track dispose) — 2026-08-04
  /// report: the deferred replay renders/uploads then crawled until the
  /// screen was left.
  Future<void> endMatchCall() async {
    try {
      autoScoringService?.stopCapture();
      RtcFramesService.onSendActiveChanged = null;
      await cameraFrameService?.dispose();
      cameraFrameService = null;
      if (p2pVideo != null) {
        await p2pVideo!.stop();
        p2pVideo = null;
      }
    } catch (e) {
      debugPrint('[BaseGameScreen] endMatchCall error: $e');
    }
  }

  Future<void> initCameraZoom({int attempt = 0}) async {
    if (cameraFrameService == null || !mounted || cameraZoomInitialized) return;
    try {
      final minZoom = await cameraFrameService!.getMinZoomLevel();
      final maxZoom = await cameraFrameService!.getMaxZoomLevel();
      if (mounted && maxZoom > 1.0) {
        final savedZoom = await StorageService.getCameraZoom();
        final clampedZoom = savedZoom.clamp(minZoom, maxZoom.clamp(1.0, 10.0));
        await cameraFrameService!.setZoomLevel(clampedZoom);
        cameraZoomInitialized = true;
        setState(() { cameraMinZoom = minZoom; cameraMaxZoom = maxZoom.clamp(1.0, 10.0); cameraZoom = clampedZoom; });
      }
    } catch (_) {
      if (attempt < 5 && mounted) Future.delayed(Duration(milliseconds: 500 * (attempt + 1)), () => initCameraZoom(attempt: attempt + 1));
    }
  }

  Future<void> toggleAudio() async {
    // The audio track is pre-added disabled, so the toggle is a plain
    // enabled flip.
    if (p2pVideo == null) return;
    setState(() => isAudioMuted = !isAudioMuted);
    await p2pVideo!.setMicEnabled(!isAudioMuted);
  }

  Future<void> switchCamera() async {
    final svc = cameraFrameService;
    if (svc == null || switchingCamera) return;
    HapticService.lightImpact();
    setState(() => switchingCamera = true);
    try {
      await svc.switchCamera();
      // Zoom range differs per lens (front cameras often can't zoom at all),
      // so re-read the bounds and re-apply the saved zoom for the new lens.
      cameraZoomInitialized = false;
      await initCameraZoom();
    } finally {
      if (mounted) setState(() => switchingCamera = false);
    }
  }
  Future<void> zoomIn() async {
    if (cameraFrameService == null) return;
    final next = (cameraZoom + 0.1).clamp(cameraMinZoom, cameraMaxZoom);
    try { await cameraFrameService!.setZoomLevel(next); if (mounted) setState(() => cameraZoom = next); } catch (_) {}
  }
  Future<void> zoomOut() async {
    if (cameraFrameService == null) return;
    final next = (cameraZoom - 0.1).clamp(cameraMinZoom, cameraMaxZoom);
    try { await cameraFrameService!.setZoomLevel(next); if (mounted) setState(() => cameraZoom = next); } catch (_) {}
  }


  // ─── Leave / pop ──────────────────────────────────────────────────────────────

  /// A ranked BO3 series is still live even when the current LEG has ended:
  /// between legs the provider reads gameEnded=true (leg result screen) then
  /// gameStarted=false (next leg not started). Leaving in that window
  /// forfeits the whole series, so the leave/pop guards below must treat it
  /// as a live match. Providers without series state (tournament, friendly)
  /// fall back to false.
  bool get seriesStillLive {
    try {
      final game = readGame();
      return game.isRankedSeries == true && game.seriesEnded != true;
    } catch (_) {
      return false;
    }
  }

  void leaveMatch() {
    try {
      final matchId = matchIdForLeave;
      if (matchId == null || storedPlayerId == null) {
        return;
      }
      if ((!gameStarted || gameEnded) && !seriesStillLive) {
        return;
      }
      // The game providers are shared across matches, and Flutter defers a
      // popped route's dispose() by ~300ms — long enough for the NEXT match
      // (rematch, next tournament leg) to have started. gameStarted/gameEnded
      // then describe the new match while matchId is the old one, so this
      // emitted a leave_match for a match we already left, during live entry
      // into its successor. Only forfeit the match the provider is still on.
      try {
        final currentMatchId = readGame().matchId as String?;
        if (currentMatchId != null && currentMatchId != matchId) {
          debugPrint('[BaseGameScreen] skipping leave_match for stale match $matchId '
              '(provider now on $currentMatchId)');
          return;
        }
      } catch (_) {
        // Provider gone — fall through and emit; a leave for an ended match
        // is ignored server-side.
      }
      SocketService.emit('leave_match', {'matchId': matchId, 'playerId': storedPlayerId});
    } catch (e) {
      debugPrint('[BaseGameScreen] leaveMatch failed: $e');
    }
  }

  Future<bool> onWillPop() async {
    final game = readGame();
    // Between BO3 legs (leg ended / next not started) leaving still forfeits
    // the series — keep the warning dialog up in that window.
    if ((!game.gameStarted || game.gameEnded) && !seriesStillLive) return true;
    final l10n = AppLocalizations.of(context);
    final result = await showGameDialog<bool>(
      context,
      accent: AppTheme.error,
      icon: Icons.logout_rounded,
      title: l10n.leaveMatch,
      content: Text(leaveWarningText, style: AppTheme.bodyMedium),
      actionsBuilder: (ctx) => [
        OutlinedButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(l10n.stayInMatch),
        ),
        ElevatedButton(
          onPressed: () { leaveMatch(); Navigator.pop(ctx, true); },
          style: gameFilledButtonStyle(AppTheme.error),
          child: Text(l10n.leaveAndForfeit),
        ),
      ],
    );
    return result ?? false;
  }

  // ─── Shared dialogs ───────────────────────────────────────────────────────────
  void showPendingWinDialog(dynamic game) {
    // Null when the pending win was recovered from a sync whose round was
    // empty. Never substitute a placeholder here: "You hit Unknown to finish!"
    // reads as a bug. Drop the sentence and keep the question instead.
    final notation = (game.pendingData?['finalDart'])?['notation'] as String?;
    final l10n = AppLocalizations.of(context);
    winDialogShowing = true;
    // The in-game capture bar, docked to the dialog's bottom edge: the
    // checkout dart opens this modal INSTANTLY, so the bar on the camera
    // panel sits unreachable under the barrier — exactly on the visit most
    // worth keeping. Armed ring is the ONLY gate — the in-game bar's
    // dart-count gate hid it here when the winning visit was auto-validated
    // with the AI silent (manual D8, 2026-08-04): visit committed, dart
    // count back to 0, no AI timestamps — yet the footage IS in the ring
    // (captureTurnClip falls back to a 20s window). Saving does not close
    // the dialog (the bar shows its own ✓); capture MUST stay possible
    // before « Modifier les fléchettes », whose undoAllDarts() wipes the
    // visit timestamps.
    Widget? checkoutBar;
    if (ReplayBufferService.armed) {
      checkoutBar = ReplayCaptureButton(onCapture: () => captureTurnClip(game));
    } else {
      debugPrint('[Replay] checkout bar hidden: ring not armed');
    }
    final isCricket = cricketStateOf(game) != null;
    showGameDialog(
      context,
      accent: AppTheme.success,
      icon: Icons.emoji_events_outlined,
      title: isCricket ? l10n.cricketAllClosedTitle : l10n.checkout,
      bottomBar: checkoutBar,
      prominentActions: true,
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (isCricket) ...[
          Text(l10n.cricketAllClosedBody, style: gameDialogBodyStyle),
          const SizedBox(height: 6),
        ] else if (notation != null && notation.isNotEmpty) ...[
          Text(l10n.youHitToFinish(notation), style: gameDialogBodyStyle),
          const SizedBox(height: 6),
        ],
        Text(l10n.isThisCorrect, style: gameDialogHintStyle),
      ]),
      actionsBuilder: (ctx) => [
        OutlinedButton(
          onPressed: () { winDialogShowing = false; Navigator.pop(ctx); setState(() { aiPausedForEdit = true; }); autoScoringService?.stopCapture(); game.undoAllDarts(); _turnDartTimes.clear(); for (int i = 0; i < 3; i++) { autoScoringService?.clearDart(i); } },
          style: gameNeutralOutlineButtonStyle(),
          child: Text(l10n.editDarts),
        ),
        ElevatedButton(
          onPressed: () { winDialogShowing = false; Navigator.pop(ctx); setState(() { aiPausedForEdit = true; }); autoScoringService?.stopCapture(); game.confirmWin(); },
          style: gameFilledButtonStyle(AppTheme.success),
          child: Text(dsSentence(l10n.confirmWin)),
        ),
      ],
    ).then((_) { if (mounted) winDialogShowing = false; });
  }

  void showPendingBustDialog(dynamic game) {
    bustDialogShowing = true;
    final l10n = AppLocalizations.of(context);
    final reasonText = switch (game.pendingReason ?? '') {
      'score_below_zero' => l10n.bustReasonBelowZero,
      'must_finish_double' => l10n.bustReasonMustDouble,
      'score_one_remaining' => l10n.bustReasonOneRemaining,
      _ => l10n.bustReasonInvalid,
    };
    final figures = pendingBustFigures(
      currentScore: game.myScore,
      currentRoundScore: game.currentRoundScore,
      pendingData: game.pendingData,
    );
    showGameDialog(
      context,
      accent: AppTheme.error,
      icon: Icons.error_outline_rounded,
      title: l10n.bust,
      prominentActions: true,
      content: GameBustDialogContent(
        reason: reasonText,
        remaining: figures?.remaining,
        visitTotal: figures?.visitTotal,
      ),
      actionsBuilder: (ctx) => [
        OutlinedButton(
          onPressed: () { bustDialogShowing = false; Navigator.pop(ctx); setState(() { aiPausedForEdit = true; }); autoScoringService?.stopCapture(); game.undoAllDarts(); _turnDartTimes.clear(); for (int i = 0; i < 3; i++) { autoScoringService?.clearDart(i); } },
          style: gameNeutralOutlineButtonStyle(),
          child: Text(l10n.editDarts),
        ),
        ElevatedButton(
          onPressed: () { bustDialogShowing = false; Navigator.pop(ctx); setState(() { aiPausedForEdit = true; }); autoScoringService?.stopCapture(); game.confirmBust(); },
          style: gameFilledButtonStyle(AppTheme.primary),
          child: Text(l10n.confirmBustButton),
        ),
      ],
    ).then((_) { if (mounted) bustDialogShowing = false; });
  }

  /// Reason + optional comment dialog feeding the dispute endpoint. Defaults
  /// to the "report player" wording; tournaments restyle it as "refuse result"
  /// via the optional labels without changing the underlying call.
  /// Returns when the dialog closes, whichever way — submitted, cancelled or
  /// dismissed. Callers that only care about the submit path can ignore it.
  Future<void> showReportDialog({
    required Future<void> Function(String reason, String? comment) onSubmit,
    required VoidCallback onComplete,
    String? title,
    String? subtitle,
    String? submitLabel,
    List<String>? reasons,
    IconData icon = Icons.flag_outlined,
    // A per-visit report is only being FILLED IN here — it is sent later, from
    // the list screen — so the "submitted" confirmation would be a lie.
    bool showSuccessSnackBar = true,
  }) {
    final l10n = AppLocalizations.of(context);
    return showDialog(
      context: context,
      builder: (ctx) => _ReportDialog(
        icon: icon,
        title: title ?? l10n.reportPlayer,
        subtitle: subtitle ?? l10n.selectReasonReporting,
        reasons: reasons ??
            [
              l10n.reportReasonCheating,
              l10n.reportReasonUnsportsmanlike,
              l10n.reportReasonIncorrectScore,
              l10n.reportReasonConnectionIssues,
              l10n.reportReasonOther,
            ],
        commentLabel: l10n.reportCommentLabel,
        commentHint: l10n.reportCommentHint,
        cancelLabel: l10n.cancel,
        submitLabel: dsSentence(submitLabel ?? l10n.submitReport),
        // Runs once the dialog has popped itself, so the messenger and the
        // `mounted` checks below are the SCREEN's, exactly as before.
        onSubmit: (reason, comment) async {
          final messenger = ScaffoldMessenger.of(context);
          try {
            await onSubmit(reason, comment);
            if (mounted && showSuccessSnackBar) messenger.showSnackBar(SnackBar(content: Text(l10n.disputeSubmitted), backgroundColor: AppTheme.success, duration: const Duration(seconds: 2)));
          } catch (e) {
            if (mounted) messenger.showSnackBar(SnackBar(content: Text(l10n.errorWithMessage.replaceAll('{message}', e.toString())), backgroundColor: AppTheme.error, duration: const Duration(seconds: 3)));
          }
          onComplete();
        },
      ),
    );
  }

  // ─── Shared widget builders ────────────────────────────────────────────────────
  String formatSeconds(int s) { final m = s ~/ 60; final r = s % 60; return '$m:${r.toString().padLeft(2, '0')}'; }

  /// Back action shared by both turn layouts: confirm-leave dialog, then pop.
  Future<void> handleBackPressed() async {
    final shouldLeave = await onWillPop();
    if (shouldLeave && mounted) Navigator.of(context).pop();
  }

  /// Back button styled like the in-camera controls (glass circle).
  Widget buildGameBackButton() => GameControlButton(
        icon: Icons.arrow_back_ios_new_rounded,
        onTap: handleBackPressed,
      );

  /// Banner overlay shown when OUR OWN socket is down mid-match. Without it
  /// the player keeps "throwing" into a dead connection and only learns about
  /// the problem when the forfeit arrives.
  Widget? buildSelfDisconnectBanner(dynamic game, double safeTop) {
    bool selfDisconnected = false;
    int graceSeconds = 0;
    try {
      selfDisconnected = game.selfDisconnected == true;
      graceSeconds = (game.selfDisconnectGraceSeconds as int?) ?? 0;
    } catch (_) {
      return null;
    }
    if (!selfDisconnected) return null;
    final l10n = AppLocalizations.of(context);
    return Positioned(
      top: safeTop + 52,
      left: 12,
      right: 12,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.surface.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.error.withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 16, height: 16,
              child: CircularProgressIndicator(color: AppTheme.error, strokeWidth: 2),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${l10n.connectionLostReconnecting}\n${l10n.timeLeftToReconnect.replaceAll('{time}', formatSeconds(graceSeconds))}',
                style: const TextStyle(color: AppTheme.error, fontSize: 13, fontWeight: FontWeight.w600, height: 1.3),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildLoadingScreen() {
    return PopScope(
      canPop: false,
      // `mounted`, not `context.mounted`: `context` here is the State getter,
      // which throws once the screen has unmounted.
      onPopInvokedWithResult: (didPop, _) async { if (didPop) return; final nav = Navigator.of(context); if (await onWillPop() && mounted) nav.pop(); },
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: SafeArea(child: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Image.asset('assets/logo/logo.png', width: 90, height: 90),
          const SizedBox(height: 32),
          const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 2)),
          const SizedBox(height: 24),
          Text(dsSentence(AppLocalizations.of(context).preparingMatch), style: AppTheme.titleLarge),
          const SizedBox(height: 6),
          Text(loadingMessage, style: AppTheme.caption.copyWith(fontSize: 13)),
        ]))),
      ),
    );
  }

  /// [bottomOverlay] is the opponent-visit ticker docked to the bottom of the
  /// feed; [leading] a back button and [roundChipText] a "TOUR n" pill, both
  /// top-left — used by the cricket layout, whose screen has no header
  /// (2026-08-18 no-scroll redesign).
  Widget buildOpponentTurnVideoLayout(
    dynamic game, {
    Widget? bottomOverlay,
    Widget? leading,
    String? roundChipText,
  }) {
    final opponentThrows = game.opponentRoundThrows as List<String>;
    final cricket = cricketStateOf(game);
    // "Waiting..." placeholder until the peer's video arrives.
    final Widget waitingPlaceholder = Container(
      color: AppTheme.gamePanelEmpty,
      child: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.videocam_off_outlined, size: 40, color: AppTheme.textSecondary), const SizedBox(height: 10),
        Text(dsSentence(AppLocalizations.of(context).waitingUpper), style: AppTheme.caption),
      ])),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      child: Stack(
        fit: StackFit.expand,
          children: [
            // ── Camera feed ──
            // P2P (RTC v2): the session's RTCVideoView while media actually
            // flows; the placeholder before the first frame AND during a
            // detected outage — a dead renderer painted black and read as
            // "no camera at all" in the 2026-08-03 airplane test.
            if (p2pVideo != null)
              (p2pVideo!.isRemoteReady && p2pVideo!.isLinkUp
                  ? (p2pVideo!.remoteView(
                        zoom: videoZoom,
                        topInset: kOpponentFeedBadgeRowHeight,
                      ) ??
                      waitingPlaceholder)
                  : waitingPlaceholder)
            else
              waitingPlaceholder,
            // ── Dart label + one-second zoom on the dart that just landed ──
            OpponentDartFlash(
              throws: opponentThrows,
              zoom: opponentDartZoomOf(game),
              controller: videoZoom,
              // Cricket docks its visit ticker at the feed's bottom edge
              // (36 px, 12 px up): the score band sits above it.
              bottomInset: bottomOverlay != null ? 54 : 0,
              subtitleOf: cricket != null
                  ? (n) => AppLocalizations.of(context)
                      .cricketMarks(cricketNotationMarks(n))
                  : null,
            ),
            // ── Rose identity border: the turn cue (blue on my own turn) ──
            IgnorePointer(child: Container(decoration: BoxDecoration(border: Border.all(color: AppTheme.opponentPink, width: 1.5), borderRadius: BorderRadius.circular(AppTheme.radiusCard)))),
            // ── Brand bug (top center), like a TV channel logo ──
            const Positioned(
              top: 12,
              left: 0,
              right: 0,
              child: Center(child: LogoWatermark()),
            ),
            // ── Back button (cricket: the screen has no header to host it) ──
            if (leading != null) Positioned(top: 10, left: 10, child: leading),
            // No live badge on the opponent feed (removed 2026-09-06 on
            // request: the pink border already says it's live). Spectator
            // screens keep theirs.
            // ── "TOUR n" pill (cricket: replaces the header's round chip) ──
            if (roundChipText != null)
              Positioned(
                top: 58,
                left: 10,
                child: GameChip(
                  text: roundChipText,
                  color: AppTheme.textSecondary,
                ),
              ),
            // ── Mic / camera controls (mic open = the live, tinted one) ──
            Positioned(
              top: 10,
              right: 10,
              child: Row(children: [
                GameControlButton(
                  icon: isAudioMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                  color: AppTheme.opponentPink,
                  active: !isAudioMuted,
                  onTap: toggleAudio,
                ),
                const SizedBox(width: 8),
                GameControlButton(
                  icon: Icons.cameraswitch_rounded,
                  onTap: switchCamera,
                ),
              ]),
            ),
            // ── Opponent-visit ticker docked to the feed's bottom edge ──
            if (bottomOverlay != null)
              Positioned(
                left: 10,
                right: 10,
                bottom: 12,
                child: IgnorePointer(child: bottomOverlay),
              ),
          ],
        ),
      );
  }

  /// The opponent's latest dart with its zoom point, or null when the
  /// provider doesn't carry one (or none arrived for this visit).
  OpponentDartZoom? opponentDartZoomOf(dynamic game) {
    try {
      return game.opponentDartZoom as OpponentDartZoom?;
    } catch (_) {
      return null;
    }
  }

  /// Round number of the side currently throwing (1-based), or null when the
  /// provider doesn't track per-round history (tournament legs).
  int? roundNumberOf(dynamic game, {required bool forOpponent}) {
    try {
      final rounds = (forOpponent ? game.opponentRounds : game.myRounds) as List;
      return rounds.length + 1;
    } catch (_) {
      return null;
    }
  }

  double? opponentAvgOrNull(dynamic game) {
    try {
      final avg = game.opponentAveragePerRound as double;
      return avg > 0 ? avg : null;
    } catch (_) {
      return null;
    }
  }

  double? myAvgOrNull(dynamic game) {
    try {
      final avg = game.myAveragePerRound as double;
      return avg > 0 ? avg : null;
    } catch (_) {
      return null;
    }
  }

  /// Quiet "opponent disconnected" strip (unchanged behavior, shared here so
  /// both game screens stop duplicating it): surface, hairline, secondary
  /// text — it informs, the rose warning banner below already alerts.
  Widget? buildOpponentDisconnectBanner(dynamic game) {
    if (game.opponentDisconnected != true) return null;
    final l10n = AppLocalizations.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.wifi_off_rounded, color: AppTheme.textSecondary, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${l10n.opponentDisconnected} — ${l10n.timeLeftToReconnect.replaceAll('{time}', formatSeconds(game.disconnectGraceSeconds))}',
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  /// Full opponent-turn screen (maquette layout), shared by the ranked and
  /// tournament game screens. The camera panel uses gameCameraHeight() so it
  /// is exactly the same size as on the player's own turn.
  Widget buildOpponentTurnScreenShared(
    dynamic game,
    AuthProvider auth,
    double safeTop, {
    String? seriesTitle,
    int myLegs = 0,
    int opponentLegs = 0,
  }) {
    final l10n = AppLocalizations.of(context);
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    final safeBottom = MediaQuery.of(context).padding.bottom;
    final disconnectBanner = buildOpponentDisconnectBanner(game);
    final cricket = cricketStateOf(game);

    final throws = game.opponentRoundThrows as List<String>;
    final roundNumber = roundNumberOf(game, forOpponent: true);

    if (cricket != null) {
      // Cricket: no header — the camera sits exactly where it is on my own
      // turn (the feed no longer jumps when the turn flips), the score table
      // goes below, the opponent's visit lives on the feed as the enlarged
      // ticker, back button and round chip move onto the feed.
      final ticker = VisitTicker(
        labelTop: l10n.visitUpper,
        labelBottom: opponentUsername.toUpperCase(),
        throws: throws,
        totalValue: cricketVisitTotal(throws),
        totalLabel: l10n.cricketMarksShort(cricketVisitMarks(throws)),
      );
      final cameraView = buildOpponentTurnVideoLayout(
        game,
        bottomOverlay: ticker,
        leading: buildGameBackButton(),
        roundChipText:
            roundNumber != null ? l10n.roundChip(roundNumber) : null,
      );
      final boardPanel = CricketScoreTable(
        state: cricket,
        myName: auth.currentUser?.username ?? 'You',
        opponentName: opponentUsername,
        seriesTitle: seriesTitle,
        myLegs: myLegs,
        opponentLegs: opponentLegs,
        myTurn: false,
      );

      if (isLandscape) {
        return Container(
          color: AppTheme.gameBackground,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: safeTop),
              if (disconnectBanner != null) disconnectBanner,
              Expanded(
                child: Row(children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
                      child: cameraView,
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(6, 8, 12, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          boardPanel,
                          const Spacer(),
                          const SizedBox(height: 8),
                          const OpponentWarningBanner(),
                        ],
                      ),
                    ),
                  ),
                ]),
              ),
              SizedBox(height: safeBottom),
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
                child: Stack(
                  children: [
                    Positioned.fill(child: cameraView),
                    // Overlaid on the feed instead of taking layout height:
                    // the fixed column below the camera has no scroll
                    // fallback and no slack for an in-flow banner.
                    if (disconnectBanner != null)
                      Positioned(
                        top: 56,
                        left: 10,
                        right: 10,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: ColoredBox(
                            color: AppTheme.gameBackground.withValues(
                              alpha: 0.88,
                            ),
                            child: disconnectBanner,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: boardPanel,
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(12, 8, 12, safeBottom + 10),
              child: const OpponentWarningBanner(),
            ),
          ],
        ),
      );
    }

    // X01: the shared no-badges header on top, and the opponent's visit back
    // as the big chip row below the camera (2026-08-19 decision — the slim
    // ticker stays cricket-only); back button and round chip on the feed.
    final header = TurnScoreHeader(
      myName: auth.currentUser?.username ?? 'You',
      opponentName: opponentUsername,
      myScore: game.myScore,
      opponentScore: game.opponentScore,
      myAverage: myAvgOrNull(game),
      opponentAverage: opponentAvgOrNull(game),
      seriesTitle: seriesTitle,
      myLegs: myLegs,
      opponentLegs: opponentLegs,
      showBadges: false,
      myTurn: false,
    );
    final cameraView = buildOpponentTurnVideoLayout(
      game,
      leading: buildGameBackButton(),
      roundChipText:
          roundNumber != null ? l10n.roundChip(roundNumber) : null,
    );
    final visitSection = buildOpponentVisitSection(throws);

    if (isLandscape) {
      return Container(
        color: AppTheme.gameBackground,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: safeTop),
            if (disconnectBanner != null) disconnectBanner,
            Expanded(
              child: Row(children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
                    child: cameraView,
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(6, 8, 12, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        header,
                        const SizedBox(height: 12),
                        visitSection,
                        const Spacer(),
                        const SizedBox(height: 8),
                        const OpponentWarningBanner(),
                      ],
                    ),
                  ),
                ),
              ]),
            ),
            SizedBox(height: safeBottom),
          ],
        ),
      );
    }

    return Container(
      color: AppTheme.gameBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: safeTop + 6),
          header,
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SizedBox(
              height: gameCameraHeight(context),
              child: Stack(
                children: [
                  Positioned.fill(child: cameraView),
                  // Overlaid on the feed instead of taking layout height:
                  // with the big chip row back below the camera, the column
                  // has no slack left for an in-flow banner (same treatment
                  // as the cricket layout).
                  if (disconnectBanner != null)
                    Positioned(
                      top: 56,
                      left: 10,
                      right: 10,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: ColoredBox(
                          color: AppTheme.gameBackground.withValues(
                            alpha: 0.88,
                          ),
                          child: disconnectBanner,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: visitSection,
          ),
          const Spacer(),
          Padding(
            padding: EdgeInsets.fromLTRB(12, 8, 12, safeBottom + 10),
            child: const OpponentWarningBanner(),
          ),
        ],
      ),
    );
  }

  /// "VOLÉE DE (name) … TOTAL n" label row + the three big visit chips for
  /// the opponent's current X01 visit (restored 2026-08-19 — cricket keeps
  /// its enlarged on-feed ticker instead).
  Widget buildOpponentVisitSection(List<String> throws) {
    final l10n = AppLocalizations.of(context);
    final total = throws.fold<int>(0, (sum, n) => sum + notationPoints(n));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        VisitLabelRow(
          label: l10n.visitOf(opponentUsername),
          total: total,
          color: AppTheme.opponentPinkBright,
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 74,
          child: Row(
            children: List.generate(3, (i) {
              final notation = i < throws.length ? throws[i] : null;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(left: i == 0 ? 0 : 10),
                  child: DartVisitChip(
                    notation: notation,
                    accent: AppTheme.surfaceLight,
                    highlighted: notation != null && i == throws.length - 1,
                  ),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }

  /// "BO3 · Manche 2" center label for the series displays, or null for a
  /// single-leg match (the displays fall back to their BO1 layout).
  String? seriesTitleOf(dynamic game) {
    try {
      final bestOf = game.bestOf as int;
      if (bestOf <= 1) return null;
      return 'BO$bestOf · ${AppLocalizations.of(context).legNumber(game.currentLeg as int)}';
    } catch (_) {
      return null;
    }
  }

  /// The authoritative cricket board of a cricket friendly, or null for every
  /// X01 match (and for providers that don't track cricket at all — the
  /// duck-typed read mirrors seriesTitleOf).
  CricketState? cricketStateOf(dynamic game) {
    try {
      return game.cricketState as CricketState?;
    } catch (_) {
      return null;
    }
  }

  /// Raw marks a notation is worth on the cricket numbers — the display
  /// approximation used for chip subtitles and visit totals (the authoritative
  /// marks/points live server-side; the board block is what's exact).
  int cricketNotationMarks(String notation) {
    if (notation.length < 2) return 0;
    final base = int.tryParse(notation.substring(1)) ?? -1;
    if (!kCricketTargets.contains(base)) return 0;
    if (notation[0] == 'T') return base == 25 ? 0 : 3;
    if (notation[0] == 'D') return 2;
    return 1;
  }

  /// Total marks of a visit's notations — one fold shared by the my-turn
  /// total and the opponent ticker so the two can't drift apart.
  int cricketVisitMarks(List<String> throws) =>
      throws.fold<int>(0, (sum, n) => sum + cricketNotationMarks(n));

  String cricketVisitTotal(List<String> throws) =>
      '+${cricketVisitMarks(throws)}';

  /// "INITIALISATION DU MATCH..." spinner, shown until game_started /
  /// game_state_sync flips the provider's gameStarted. After
  /// [_startStallDelay] with no start it turns into a diagnosis + retry/leave
  /// screen instead of spinning forever.
  Widget buildInitializingScreen() {
    final l10n = AppLocalizations.of(context);
    _armStartStallTimer();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await onWillPop() && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0, iconTheme: const IconThemeData(color: Colors.white)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: startStalled
                ? _buildStartStalledBody(l10n)
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 2)),
                      const SizedBox(height: 16),
                      Text(dsSentence(l10n.initializingMatch), style: AppTheme.caption.copyWith(fontSize: 13, fontWeight: FontWeight.w600)),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildStartStalledBody(AppLocalizations l10n) {
    // Distinguish "no network" from "connected but the start never came" —
    // they need different things from the player.
    final offline = !SocketService.isConnected;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          offline ? Icons.wifi_off_rounded : Icons.hourglass_disabled_rounded,
          size: 48,
          color: AppTheme.error,
        ),
        const SizedBox(height: 16),
        Text(
          l10n.matchNotStartingTitle,
          textAlign: TextAlign.center,
          style: AppTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          offline ? l10n.matchNotStartingOffline : l10n.matchNotStartingBody,
          textAlign: TextAlign.center,
          style: AppTheme.bodyMedium,
        ),
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton.icon(
            onPressed: retryingStart ? null : retryMatchStart,
            icon: retryingStart
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded, size: 20),
            label: Text(l10n.retry),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton(
            // Through onWillPop: the match may still be live server-side, so
            // leaving must go through the same forfeit warning as the board.
            onPressed: () async {
              if (await onWillPop() && mounted) Navigator.of(context).pop();
            },
            style: OutlinedButton.styleFrom(foregroundColor: AppTheme.textSecondary),
            child: Text(l10n.leave),
          ),
        ),
      ],
    );
  }

  /// The live in-match body — my turn (AutoScoreGameView), opponent turn and
  /// the self-disconnect banner. ONE implementation for ranked, friendly and
  /// tournament matches: game-mode differences must come from the provider's
  /// data (bestOf, legs, rounds), never from a forked copy of this layout.
  Widget buildLiveMatchBody(dynamic game, AuthProvider auth) {
    final safeTop = MediaQuery.of(context).padding.top;
    final seriesTitle = seriesTitleOf(game);
    final cricket = cricketStateOf(game);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await onWillPop() && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: Stack(
          children: [
            autoScoringLoading && (game.isMyTurn || game.pendingConfirmation)
              ? Container(
                  color: AppTheme.background,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 2)),
                        const SizedBox(height: 16),
                        Text(AppLocalizations.of(context).loadingAutoScoring, style: AppTheme.caption.copyWith(fontSize: 13, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                )
              : (game.isMyTurn || game.pendingConfirmation)
                ? AutoScoreGameView(
                    scoringService: autoScoringService!,
                    onConfirm: () => submitAutoScoredDarts(game),
                    onEndRoundEarly: () => submitAutoScoredDarts(game),
                    pendingConfirmation: game.pendingConfirmation,
                    captureButton: buildReplayCaptureButton(game),
                    localCameraPreview: !switchingCamera && cameraFrameService?.controller != null && cameraFrameService!.controller!.value.isInitialized
                        ? LocalCameraPreview(controller: cameraFrameService!.controller!)
                        : null,
                    isAudioMuted: isAudioMuted,
                    onToggleAudio: toggleAudio,
                    onSwitchCamera: switchCamera,
                    onZoomIn: zoomIn,
                    onZoomOut: zoomOut,
                    currentZoom: cameraZoom,
                    minZoom: cameraMinZoom,
                    maxZoom: cameraMaxZoom,
                    onEditDart: (index, dartScore) {
                      final (base, mul) = dartScoreToBackend(dartScore);
                      game.editDartThrow(index, base, mul);
                    },
                    onRemoveDart: (index) { autoScoringService?.removeDart(index); game.undoLastDart(); if (_turnDartTimes.isNotEmpty) _turnDartTimes.removeLast(); },
                    onEditModalClosed: resumeCaptureAfterEdit,
                    onToggleAi: autoScoringService!.modelLoaded ? toggleAiScoring : null,
                    aiEnabled: !aiManuallyDisabled,
                    roundNumber: roundNumberOf(game, forOpponent: false),
                    onBack: handleBackPressed,
                    // Cricket: the score table fills the space below the
                    // compact chips; X01: the shared no-badges score header
                    // sits above the camera, same component as the opponent
                    // turn (2026-08-19 layout).
                    confirmBesideChips: cricket != null,
                    scorePanel: cricket != null
                        ? CricketScoreTable(
                            state: cricket,
                            myName: auth.currentUser?.username ?? 'You',
                            opponentName: opponentUsername,
                            seriesTitle: seriesTitle,
                            myLegs: game.myLegsWon,
                            opponentLegs: game.opponentLegsWon,
                            myTurn: true,
                            rowHeight: 22,
                          )
                        : null,
                    header: cricket == null
                        ? TurnScoreHeader(
                            myName: auth.currentUser?.username ?? 'You',
                            opponentName: opponentUsername,
                            myScore: game.myScore,
                            opponentScore: game.opponentScore,
                            myAverage: myAvgOrNull(game),
                            opponentAverage: opponentAvgOrNull(game),
                            seriesTitle: seriesTitle,
                            myLegs: game.myLegsWon,
                            opponentLegs: game.opponentLegsWon,
                            showBadges: false,
                            myTurn: true,
                          )
                        : null,
                    visitTotalText: cricket != null
                        ? cricketVisitTotal(
                            (game.currentRoundThrows as List).cast<String>())
                        : null,
                    chipSubtitle: cricket != null
                        ? (i, notation) => AppLocalizations.of(context)
                            .cricketMarks(cricketNotationMarks(notation))
                        : null,
                  )
                // Opponent's turn
                : buildOpponentTurnScreenShared(
                    game,
                    auth,
                    safeTop,
                    seriesTitle: seriesTitle,
                    myLegs: game.myLegsWon,
                    opponentLegs: game.opponentLegsWon,
                  ),

            // Own-connection banner (shows when OUR socket is down)
            if (buildSelfDisconnectBanner(game, safeTop) case final banner?)
              banner,
          ],
        ),
      ),
    );
  }

}

/// The reason + comment dialog behind [BaseGameScreenState.showReportDialog].
///
/// A real widget, and not the [StatefulBuilder] it used to be, for ONE reason:
/// the comment field's [TextEditingController] must live and die with the
/// route. It was disposed from `showDialog(...).then(...)`, and that future
/// completes the instant `Navigator.pop` is called — NOT when the route is
/// gone (see `Route.didPop`: "routes should not wait for their exit animation").
/// The field was therefore still on screen, and still the platform's text-input
/// client, when its controller died: the IME's closing update then landed on a
/// disposed notifier. That exception was thrown in the middle of the element
/// deactivation walk and left the tree half torn down — `_dependents.isEmpty`,
/// then "dirty widget in the wrong build scope", then the engine (device test
/// 2026-08-13, validating a turn report killed the app).
class _ReportDialog extends StatefulWidget {
  const _ReportDialog({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.reasons,
    required this.commentLabel,
    required this.commentHint,
    required this.cancelLabel,
    required this.submitLabel,
    required this.onSubmit,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<String> reasons;
  final String commentLabel;
  final String commentHint;
  final String cancelLabel;
  final String submitLabel;

  /// Called with the chosen reason and the trimmed comment (null when empty),
  /// right after this dialog popped itself.
  final void Function(String reason, String? comment) onSubmit;

  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  final TextEditingController _comment = TextEditingController();
  String? _reason;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  void _submit() {
    HapticService.mediumImpact();
    final reason = _reason;
    if (reason == null) return;
    final comment = _comment.text.trim();
    Navigator.of(context).pop();
    widget.onSubmit(reason, comment.isEmpty ? null : comment);
  }

  @override
  Widget build(BuildContext context) => gameDialogFrame(
        accent: AppTheme.textSecondary,
        icon: widget.icon,
        title: widget.title,
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(widget.subtitle, style: AppTheme.caption),
          const SizedBox(height: 14),
          // One row per reason; the chosen one takes the primary tint, the
          // only coloured border on the dialog (a state, not a decoration).
          for (final r in widget.reasons) ...[
            DsCard(
              radius: AppTheme.radiusControl,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              color: _reason == r ? AppTheme.primary.withValues(alpha: 0.08) : AppTheme.background,
              side: BorderSide(color: _reason == r ? AppTheme.primary : AppTheme.border),
              onTap: () => setState(() => _reason = r),
              child: Row(children: [
                Icon(
                  _reason == r ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                  size: 20,
                  color: _reason == r ? AppTheme.primaryLight : AppTheme.textTertiary,
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(r, style: AppTheme.rowTitle.copyWith(fontSize: 14))),
              ]),
            ),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 6),
          Text(widget.commentLabel, style: AppTheme.caption),
          const SizedBox(height: 8),
          TextField(
            controller: _comment,
            minLines: 3,
            maxLines: 5,
            maxLength: 500,
            textInputAction: TextInputAction.newline,
            style: AppTheme.bodyMedium.copyWith(color: AppTheme.textPrimary),
            decoration: InputDecoration(
              hintText: widget.commentHint,
              counterStyle: AppTheme.caption.copyWith(fontSize: 11),
              fillColor: AppTheme.background,
              contentPadding: const EdgeInsets.all(12),
            ),
          ),
        ])),
        actions: [
          OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: Text(widget.cancelLabel)),
          ElevatedButton(
            onPressed: _reason == null ? null : _submit,
            child: Text(widget.submitLabel),
          ),
        ],
      );
}
 