import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import '../../models/rtc_v2_config.dart';
import '../../providers/game_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/tournament_game_provider.dart'
    show TournamentGameState;
import '../../services/agora_service.dart';
import '../../services/camera_frame_service.dart';
import '../../services/p2p_match_video.dart';
import '../../services/replay_buffer_service.dart';
import '../../services/replay_clips_store.dart';
import '../../services/replay_overlay_timeline.dart';
import '../../services/replay_upload_service.dart';
import '../../services/rtc_frames_service.dart';
import '../../services/socket_service.dart';
import '../../utils/haptic_service.dart';
import '../../utils/dart_sound_service.dart';
import '../../utils/dart_caller_service.dart';
import '../../utils/app_theme.dart';
import '../../utils/orientation_utils.dart';
import '../../utils/score_converter.dart';
import '../../utils/storage_service.dart';
import '../../services/auto_scoring_service.dart';
import '../../services/dart_scoring_service.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/game_turn_ui.dart';
import '../../widgets/logo_watermark.dart';
import '../../widgets/auto_score_display.dart';
import '../../widgets/local_camera_preview.dart';

/// Shared base state for GameScreen and TournamentGameScreen.
/// readGame() returns dynamic to support both GameProvider and TournamentGameProvider.
abstract class BaseGameScreenState<W extends StatefulWidget> extends State<W>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {

  // ─── Abstract ────────────────────────────────────────────────────────────────
  dynamic readGame();
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
  // Agora call down when ranked_match_won lands, not on its game_won.
  bool _sawSeriesEnded = false;
  RtcEngine? agoraEngine;
  CameraFrameService? cameraFrameService;
  int? customVideoTrackId;
  // ─── Replays ──────────────────────────────────────────────────────────────

  /// Format band burned into replay overlays — screens override with their
  /// own context (the tournament screen shows the tournament name); null
  /// falls back to the match type read off the provider.
  String? get replayFormatLabel => null;

  String _replayDefaultFormat(dynamic game) {
    try {
      if (game.isFriendly == true) return 'FRIENDLY';
    } catch (_) {}
    try {
      if (game.isRankedSeries == true) return 'RANKED · BO${game.bestOf}';
    } catch (_) {}
    return 'RANKED';
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
    if (!ReplayBufferService.armed) return null;
    if (game.dartsThrown < 1 && _turnDartTimes.isEmpty) return null;
    return ReplayCaptureButton(onCapture: () => captureTurnClip(game));
  }

  /// Cuts the clip of the current visit from the ring buffer, burns the
  /// broadcast overlay in (scoreboard, banner, end card) and
  /// stores it. Local-only: sharing never waits on any upload, and a failed
  /// render falls back to the raw clip.
  Future<bool> captureTurnClip(dynamic game) async {
    final now = DateTime.now();
    final from = _turnDartTimes.isNotEmpty
        ? _turnDartTimes.first.subtract(const Duration(seconds: 2))
        // No AI timestamps (manual scoring): a fixed window still covers the
        // visit — segment snapping widens it anyway.
        : now.subtract(const Duration(seconds: 20));
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final captured = await ReplayBufferService.captureRange(from, now);
    if (captured == null) return false;
    var path = captured.path;
    try {
      final timeline = buildReplayOverlayTimeline(
        clipStartWallMs: captured.startWallMs,
        dartTimes: List.of(_turnDartTimes),
        dartNotations: List<String>.from(game.currentRoundThrows as List),
        myRemainingScore: game.myScore as int,
        opponentScore: game.opponentScore as int,
        myName: auth.currentUser?.username ?? 'YOU',
        opponentName: opponentUsername,
        myLegs: game.myLegsWon as int,
        opponentLegs: game.opponentLegsWon as int,
        legsTarget: _replayLegsTarget(game),
        seriesTitle: replayFormatLabel ?? _replayDefaultFormat(game),
        // Video dressing only — the gold band reads the visit itself, not any
        // clip category.
        checkout: (game.myScore as int) == 0,
        logoPath: await materializeReplayLogo(),
      );
      final dressed = await ReplayBufferService.renderOverlay(
        inPath: path,
        timeline: timeline,
      );
      if (dressed != null) path = dressed;
    } catch (e) {
      debugPrint('[Replay] overlay skipped: $e');
    }
    final clip = ReplayClip(
      path: path,
      createdAt: now,
      matchId: matchIdForLeave,
      turnTotal: autoScoringService?.turnTotal,
    );
    ReplayClipsStore.add(clip);
    // Per-screen list: the screen survives the whole BO3/tournament series,
    // so this is exactly "the clips of this match" for the end view. The
    // pill's own ✓ state is the only in-match feedback — sharing lives on
    // the end screen, never mid-game.
    matchReplayClips.add(clip);
    // Cloud library, fire-and-forget: the local clip is already usable and
    // shareable whether or not the upload lands.
    ReplayUploadService.uploadClip(clip);
    return true;
  }

  // ─── RTC v2 (P2P) ──────────────────────────────────────────────────────────
  // Non-null while this match runs on the P2P WebRTC path (payload carried an
  // rtcV2 block — both clients are new, so P2P is the transport for the whole
  // series, with NO Agora fallback: recovery is the session's own rebuild
  // loop). Mutually exclusive with agoraEngine, which only serves matches
  // against an old client. It deliberately survives leg transitions (BO3
  // ranked AND tournament): the peers never change between legs, so unlike
  // Agora there is nothing to re-key.
  /// The whole P2P path in one object (session + native track + recovery
  /// loop) — see [P2pMatchVideo]. Null on the Agora path.
  P2pMatchVideo? p2pVideo;

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
  // notification, control center). Reconnecting Agora on every blip resets
  // the mic to muted (since joinChannel defaults to publishMicrophoneTrack:
  // false). Track whether we actually backgrounded so we only re-sync after a
  // real paused state.
  bool _wasPausedSinceLastResume = false;
  // Why: debounce remote-video recovery. onRemoteVideoStateChanged can fire
  // repeatedly during a single freeze; we only want one mute/unmute toggle in
  // flight at a time.
  bool _remoteVideoRecoveryInFlight = false;
  // Watchdog: if we haven't seen onUserJoined for the opponent within this
  // window, force a mute/unmute cycle on the opponent's deterministic UID to
  // wake up the remote subscription. Without this, the player can sit on a
  // black "Waiting..." tile forever if the event was missed.
  Timer? _remoteJoinedWatchdog;
  static const Duration _remoteJoinedWatchdogDelay = Duration(seconds: 8);

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
  // (model load, Agora reconnect, a game_state_sync that may never arrive on
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
    autoScoringService = AutoScoringService();
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
    WidgetsBinding.instance.removeObserver(this);
    _wakelockReassertTimer?.cancel();
    _wakelockReassertTimer = null;
    _autoScoringLoadingWatchdog?.cancel();
    _autoScoringLoadingWatchdog = null;
    _remoteJoinedWatchdog?.cancel();
    _remoteJoinedWatchdog = null;
    _cancelStartStallTimer();
    disposeScreenSpecific();
    scoreAnimationController.dispose();
    WakelockPlus.disable();
    OrientationUtils.portraitOnly();
    autoScoringService?.dispose();
    autoScoringService = null;
    cameraFrameService?.dispose();
    cameraFrameService = null;
    // P2P: fire-and-forget, mirroring the un-awaited leaveChannel below (a
    // State.dispose can't await). The controller sends the telemetry report
    // and releases the native track.
    p2pVideo?.stopDetached();
    p2pVideo = null;
    if (agoraEngine != null) { AgoraService.leaveChannel(agoraEngine!); AgoraService.dispose(); }
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
      // Agora reconnect, which would reset the mic to muted.
      cameraFrameService?.pause();
    } else if (state == AppLifecycleState.resumed && mounted) {
      cameraFrameService?.resume();
      // Re-assert on every resume: a backgrounded/recreated activity can come
      // back without FLAG_KEEP_SCREEN_ON. Cheap no-op if already set.
      WakelockPlus.enable();
      if (!_wasPausedSinceLastResume) {
        // Came back from a brief inactive blip — no socket/Agora work needed.
        return;
      }
      _wasPausedSinceLastResume = false;
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
      }
      final wasGameEnded = gameEnded;
      gameEnded = game.gameEnded;
      if (game.gameEnded && !wasGameEnded && game.winnerId != null) {
        final auth = Provider.of<AuthProvider>(context, listen: false);
        if (game.winnerId == auth.currentUser?.id) {
          DartSoundService.playWin();
        } else {
          DartSoundService.playLose();
        }
      }
      // Why: tear down Agora/camera as soon as the match ends instead of waiting
      // for the user to navigate away from the end screen. Otherwise the call
      // keeps burning Agora minutes, battery and bandwidth while the user reads
      // their ELO result. dispose() in the widget lifecycle remains as a safety
      // net for the back-arrow / app-kill paths.
      //
      // EXCEPT between BO3 legs (D7): the series continues against the same
      // opponent within seconds, and the old teardown + full rebuild (engine,
      // camera, model reload) on an already-hot phone was exactly the CoreML
      // recompile scenario of the July regression. Keep the session alive;
      // reconnectAgora re-keys the new leg's channel on the live engine.
      // Tournament providers don't expose these getters (try/catch), so
      // tournaments keep the historical full teardown per leg. A forfeit ends
      // the series no matter what the leg counters say.
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
        // the series verdict below ends the call instead. The Agora path
        // keeps its historical per-leg teardown.
        if (p2pVideo == null || !_tournamentSeriesGoesOn(game)) {
          _endAgoraCall();
        }
      }
      // The FINAL leg ends while the series still reads as ongoing (game_won
      // arrives moments before ranked_match_won), so the branch above skips
      // it — tear down on the seriesEnded transition instead.
      bool seriesEndedNow = false;
      try { seriesEndedNow = game.seriesEnded as bool; } catch (_) {}
      if (seriesEndedNow && !_sawSeriesEnded && !toreDownNow) {
        _endAgoraCall();
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
        _endAgoraCall();
      }
      _sawTournamentSeriesEnded = tournamentSeriesEndedNow;
      // Replay ring turn gate: encode only while I throw (the local camera
      // films MY board — the opponent's turn is dead footage and half the
      // encoder heat). Idempotent, safe on every notify.
      ReplayBufferService.setMyTurn(game.isMyTurn);
      if (game.currentPlayerId != lastKnownCurrentPlayer && lastKnownCurrentPlayer != null) {
        if (game.isMyTurn) {
          DartSoundService.playYourTurn();
          // Fresh visit: the replay pill's capture window restarts here.
          _turnDartTimes.clear();
        } else {
          DartSoundService.playTurnFinished();
        }
      }
      // lastKnownCurrentPlayer == null means this is the FIRST run since the
      // listener was attached — and it is attached after the multi-second
      // Agora/camera init, so game_started and the join notifies were likely
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
            DartCallerService.callScore(game.currentRoundScore as int);
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
            DartCallerService.callScore(
                oppThrows.fold<int>(0, (sum, n) => sum + notationPoints(n)));
          }
        } else if (oppThrows.isEmpty) {
          _lastCalledOpponentVisitSignature = null;
        }
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
      if (game.needsAgoraReconnect == true) {
        // Leg transitions (D7) reuse the live session; every other reconnect
        // keeps the full rebuild — there the fresh engine IS the recovery.
        bool legTransition = false;
        try { legTransition = game.agoraLegTransition as bool; } catch (_) {}
        game.clearAgoraReconnectFlag();
        reconnectRtcTransport(game, legTransition: legTransition);
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

  /// [armEmptyBoardGate] must be false when re-initializing MID-TURN (Agora
  /// reconnect): the board still holds this turn's darts, so the gate would
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
      g.throwDart(baseScore: base, multiplier: mul, source: 'ai');
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
    game.confirmRound();
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

  /// Starts match video on the right transport, and arms the rejoin
  /// catch-up. The only entry point the screens need: P2P when the payload
  /// carried an rtcV2 verdict (both clients support it), the untouched
  /// legacy Agora path only for matches against an old client.
  ///
  /// [hasAgoraCredentials] is the screen's own check — the ranked screen
  /// reads its widget params, the tournament screen its provider.
  Future<void> startMatchVideo({
    required dynamic game,
    required String? matchId,
    required String opponentId,
    required Future<void> Function() startAgora,
    required bool hasAgoraCredentials,
  }) async {
    final rtcV2 = _rtcV2ConfigOf(game);
    // No matchId means no signaling scope: use Agora rather than start a
    // call nobody can reach (the tournament screen's historical
    // currentGameMatchId guard).
    if (rtcV2 != null && matchId != null && RtcFramesService.isSupported) {
      updateLoadingMessage('Starting camera...');
      await initializeP2p(
        matchId: matchId,
        opponentId: opponentId,
        config: rtcV2,
      );
    } else if (hasAgoraCredentials) {
      updateLoadingMessage('Starting camera...');
      await startAgora();
    }
    game.addListener(handleSharedStateChange);
    updateLoadingMessage('Loading AI model...');
    await loadAutoScoringPref();
    // Rejoin: credentials arrive later via game_state_sync, so show the
    // spinner rather than the manual dartboard until the model loads. On the
    // P2P path the camera/AI are already up, hence the p2pVideo guard.
    if (autoScoringEnabled &&
        agoraEngine == null &&
        p2pVideo == null &&
        !kIsWeb &&
        AutoScoringService.isSupported) {
      setState(() => autoScoringLoading = true);
      // If game_state_sync never arrives (or the reconnect wedges), the
      // watchdog drops the blocking overlay instead of spinning forever.
      armAutoScoringLoadingWatchdog();
      // A sync may have fired before the listener was attached: process the
      // pending reconnect now instead of waiting for the next notification.
      if (game.needsAgoraReconnect == true) {
        game.clearAgoraReconnectFlag();
        reconnectRtcTransport(game, legTransition: false);
      }
    }
  }

  /// Shared RTC recovery for a consumed `needsAgoraReconnect` flag — called
  /// from the provider listener AND from the screens' pre-listener catch-up.
  /// Decides between: nothing (live P2P), a P2P (re)launch, or the legacy
  /// Agora rebuild.
  void reconnectRtcTransport(dynamic game, {required bool legTransition}) {
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
        agoraEngine == null &&
        RtcFramesService.isSupported) {
      // The sync rehydrated an rtcV2 verdict but no session is live
      // (init raced the credentials, or this is a rejoin): relaunch
      // P2P — otherwise the surviving opponent's offers land on a screen
      // with no rtc_signal handler and both sides sit on dead video.
      // `agoraEngine == null` matters: when Agora is already up (old-client
      // match, credentials-first), P2P must NOT be stacked on top of the
      // live call. Fire-and-forget like the initial init.
      initializeP2p(
        matchId: relaunchMatchId,
        opponentId: relaunchOpponentId,
        config: rtcV2,
      );
    } else {
      reconnectAgora(game, reuseSession: legTransition);
    }
  }

  /// Defensive reads over the two provider shapes (GameProvider /
  /// TournamentGameProvider) — same pattern as the agoraLegTransition read.
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

  /// Establish the P2P (RTC v2) call and wire the SAME camera/AI pipeline as
  /// the Agora path — minus the Agora engine: the camera service pushes into
  /// the WebRTC track (p2pMode) and feeds the same TFLite capture callbacks.
  ///
  /// No fallback: connection failures are the recovery loop's job (it
  /// rebuilds until the network lets it through), and a camera failure
  /// degrades to a receive-only call (tagged in telemetry) — Agora shares
  /// the same camera pipeline, so switching would not have helped.
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
    // Same permission gate as initializeAgora: camera for the app-owned
    // capture, mic for the WebRTC audio track.
    if (!kIsWeb) {
      permissionsGranted = await AgoraService.requestPermissions();
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
    try {
      await video.start();
      if (!mounted) return;
      if (!kIsWeb) {
        cameraFrameService = CameraFrameService();
        await cameraFrameService!.initialize(p2pMode: true, replayRing: true);
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
        // Fire-and-forget so the game screen shows immediately, same as the
        // Agora path; autoScoringLoading drives the UI loading state.
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

  // ─── Agora ────────────────────────────────────────────────────────────────────
  Future<void> initializeAgora({required String appId, required String token, required String channelName, int? uid}) async {
    if (!kIsWeb) {
      permissionsGranted = await AgoraService.requestPermissions();
      if (!permissionsGranted) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).cameraAndMicPermissionRequired), backgroundColor: AppTheme.error));
        return;
      }
    } else {
      permissionsGranted = true;
    }
    final agoraUid = uid ?? 0;
    try {
      if (kIsWeb) {
        // Web: use default Agora camera capture (custom video track not supported)
        agoraEngine = await AgoraService.initializeEngineWeb(appId);
        _registerAgoraHandlers();
        await AgoraService.joinChannel(
          engine: agoraEngine!,
          token: token,
          channelName: channelName,
          uid: agoraUid,
          customVideoTrackId: null, // use default camera on web
        );
      } else {
        // Native: use custom video track with external video source
        // 1. Init Agora engine (with external video source enabled)
        agoraEngine = await AgoraService.initializeEngine(appId);

        // 2. Create custom video track
        customVideoTrackId = await AgoraService.createCustomVideoTrack();

        // 3. Start Flutter camera and begin pushing frames to Agora
        cameraFrameService = CameraFrameService();
        await cameraFrameService!.initialize(
          agoraEngine: agoraEngine!,
          videoTrackId: customVideoTrackId!,
          replayRing: true,
        );

        // 4. Register Agora event handlers
        _registerAgoraHandlers();

        // 5. Join channel with custom video track
        await AgoraService.joinChannel(
          engine: agoraEngine!,
          token: token,
          channelName: channelName,
          uid: agoraUid,
          customVideoTrackId: customVideoTrackId,
        );

        // 6. Init camera zoom from saved preferences
        await initCameraZoom();

        // 7. Init auto scoring — fire-and-forget so the game screen shows immediately.
        // autoScoringLoading flag drives the UI loading state.
        initAutoScoring();
      }
      _armRemoteVideoWatchdog();
    } catch (e) {
      debugPrint('[BaseGameScreen] initializeAgora error: $e');
      if (mounted) setState(() => autoScoringLoading = false);
    }
  }

  Future<void> reconnectAgora(dynamic game, {bool reuseSession = false}) async {
    final appId = game.agoraAppId;
    final channelName = game.agoraChannelName;
    // Strict path (uid=hash(userId) + matching token) when available,
    // legacy path (uid=0 + legacy token) otherwise. The strict path is what
    // makes eager remote-view rendering work, but we never assume the
    // backend has been upgraded — we look at what's actually in the provider.
    final String? legacyToken = game.agoraToken as String?;
    final String? strictToken = game.agoraTokenStrict as String?;
    final int? providerUid = game.agoraUid as int?;
    final bool useStrict = strictToken != null && strictToken.isNotEmpty && providerUid != null && providerUid != 0;
    final String token = useStrict ? strictToken : (legacyToken ?? '');
    final int agoraUid = useStrict ? providerUid : 0;
    if (appId == null || appId.isEmpty || token.isEmpty || channelName == null || channelName.isEmpty) {
      if (mounted) setState(() => autoScoringLoading = false);
      return;
    }
    // Why: show the loading state up-front so the UI doesn't briefly render
    // an empty game while the camera and engine are being torn down. Without
    // this preempt, the "Chargement de l'auto-scoreur" indicator only kicks
    // in inside initAutoScoring() — too late, after the screen has already
    // flashed empty.
    if (mounted && autoScoringEnabled && AutoScoringService.isSupported && !kIsWeb) {
      setState(() => autoScoringLoading = true);
      armAutoScoringLoadingWatchdog();
    }
    // Why: with deterministic UIDs we keep the opponent UID across reconnect
    // — but until the engine is rebuilt we want the AgoraVideoView to
    // un-bind from the old engine reference. We re-set remoteUid below after
    // joinChannel succeeds.
    try {
      if (game.setRemoteUser is Function) {
        game.setRemoteUser(null);
      }
    } catch (_) {}
    final int? opponentUidForRecovery = game.opponentAgoraUid as int?;
    // Preserve the user's mic preference across the reconnect so a resumed-
    // from-background or a screenshot-induced reconnect doesn't silently
    // re-mute the mic.
    final wasUnmuted = !isAudioMuted;

    // Restore mic state: if user had unmuted before the reconnect, re-publish
    // the mic track. joinChannel always defaults to publishMicrophoneTrack:
    // false, so without this the mic UI flips to muted on every reconnect.
    Future<void> restoreMicState() async {
      if (wasUnmuted && agoraEngine != null) {
        try {
          await agoraEngine!.updateChannelMediaOptions(
            const ChannelMediaOptions(publishMicrophoneTrack: true),
          );
          await agoraEngine!.muteLocalAudioStream(false);
          isAudioMuted = false;
        } catch (e) {
          debugPrint('[BaseGameScreen] restore mic error: $e');
          isAudioMuted = true;
        }
      } else {
        isAudioMuted = true;
      }
    }

    // Re-assert publishing flags after a join — see the full path below for
    // why this needs the retry (silently no-ops when racing Agora's state
    // machine → "audio works but video is a black tile").
    Future<void> reassertVideoPublish() async {
      for (var attempt = 0; attempt < 3; attempt++) {
        try {
          await agoraEngine!.updateChannelMediaOptions(ChannelMediaOptions(
            publishCustomVideoTrack: true,
            customVideoTrackId: customVideoTrackId,
            publishCameraTrack: false,
          ));
          break;
        } catch (e) {
          debugPrint('[BaseGameScreen] updateChannelMediaOptions(video) attempt ${attempt + 1} error: $e');
          if (attempt == 2) {
            debugPrint('[BaseGameScreen] updateChannelMediaOptions(video) gave up after 3 attempts');
          } else {
            await Future.delayed(Duration(milliseconds: 500 * (1 << attempt)));
          }
        }
      }
    }

    // D7 fast path — BO3 leg transition: engine, camera, custom track and
    // loaded model are all healthy, only the CHANNEL changes (the server
    // issues one per leg). Leave + join on the live engine instead of the
    // multi-second teardown/rebuild whose model reload was the July
    // hot-phone CoreML-recompile scenario. Any failure falls through to the
    // full rebuild below, which recovers from arbitrary state.
    if (reuseSession && !kIsWeb && agoraEngine != null &&
        cameraFrameService != null && customVideoTrackId != null &&
        autoScoringService != null) {
      try {
        await AgoraService.leaveChannel(agoraEngine!);
        await AgoraService.joinChannel(
          engine: agoraEngine!,
          token: token,
          channelName: channelName,
          uid: agoraUid,
          customVideoTrackId: customVideoTrackId,
        );
        await reassertVideoPublish();
        autoScoringService!.stopCapture();
        // New leg always starts with a clean round server-side; resetTurn +
        // gate arming mirror the leg-change handling in the game listener.
        final roundEmpty = ((readGame().currentRoundThrows as List).isEmpty) &&
            ((readGame().unackedDartCount as int?) ?? 0) == 0;
        if (roundEmpty) autoScoringService!.resetTurn();
        initAutoScoring(armEmptyBoardGate: roundEmpty);
        if (opponentUidForRecovery != null && opponentUidForRecovery != 0) {
          try { game.setRemoteUser(opponentUidForRecovery); } catch (_) {}
        }
        _armRemoteVideoWatchdog();
        await restoreMicState();
        return;
      } catch (e) {
        debugPrint('[BaseGameScreen] leg-transition fast path failed, falling back to full rebuild: $e');
      }
    }

    try {
      // Tear down camera and Agora
      await cameraFrameService?.dispose();
      cameraFrameService = null;
      customVideoTrackId = null;
      if (agoraEngine != null) { agoraEngine = null; await AgoraService.dispose(); }
      if (!kIsWeb && !permissionsGranted) { permissionsGranted = await AgoraService.requestPermissions(); if (!permissionsGranted) { if (mounted) setState(() => autoScoringLoading = false); return; } }

      if (kIsWeb) {
        // Web: use default Agora camera capture
        agoraEngine = await AgoraService.initializeEngineWeb(appId);
        _registerAgoraHandlers();
        await AgoraService.joinChannel(
          engine: agoraEngine!,
          token: token,
          channelName: channelName,
          uid: agoraUid,
          customVideoTrackId: null,
        );
      } else {
        // Native: reinitialize with custom video track
        agoraEngine = await AgoraService.initializeEngine(appId);
        customVideoTrackId = await AgoraService.createCustomVideoTrack();
        cameraFrameService = CameraFrameService();
        await cameraFrameService!.initialize(
          agoraEngine: agoraEngine!,
          videoTrackId: customVideoTrackId!,
          replayRing: true,
        );
        _registerAgoraHandlers();
        await AgoraService.joinChannel(
          engine: agoraEngine!,
          token: token,
          channelName: channelName,
          uid: agoraUid,
          customVideoTrackId: customVideoTrackId,
        );
        // Why: explicitly re-assert publishing flags after joinChannel.
        // Without this, opponents intermittently fail to receive the rejoiner's
        // video — joinChannel's options are sometimes not enough on rejoin.
        // Retry with exponential backoff: the first call sometimes races with
        // Agora's internal state machine and silently no-ops, which is the
        // "audio works but video is a black tile" symptom.
        await reassertVideoPublish();
        cameraZoomInitialized = false;
        await initCameraZoom();
        autoScoringService!.stopCapture();
        // Mid-turn (darts already thrown this visit): keep the AI's slot and
        // emitted-dart bookkeeping. resetTurn() here wiped _emittedSlots, so
        // the darts physically still in the board were detected as fresh and
        // emitted a SECOND time. Only a clean board justifies a full reset,
        // and only then is the empty-board gate safe to arm.
        final roundEmpty = ((readGame().currentRoundThrows as List).isEmpty) &&
            ((readGame().unackedDartCount as int?) ?? 0) == 0;
        if (roundEmpty) autoScoringService!.resetTurn();
        initAutoScoring(armEmptyBoardGate: roundEmpty);
      }
      // Re-seed remoteUid with the deterministic opponent UID so the remote
      // AgoraVideoView re-binds to the new engine immediately, without
      // waiting for the (potentially delayed) onUserJoined event.
      if (opponentUidForRecovery != null && opponentUidForRecovery != 0) {
        try { game.setRemoteUser(opponentUidForRecovery); } catch (_) {}
      }
      _armRemoteVideoWatchdog();
      await restoreMicState();
    } catch (_) {
      if (mounted) setState(() => autoScoringLoading = false);
    }
  }

  /// Ends the live call, whichever transport carries it (P2P session or
  /// Agora engine), plus the shared camera pipeline.
  Future<void> _endAgoraCall() async {
    try {
      autoScoringService?.stopCapture();
      if (p2pVideo != null) {
        await p2pVideo!.stop();
        p2pVideo = null;
      }
      await cameraFrameService?.dispose();
      cameraFrameService = null;
      customVideoTrackId = null;
      if (agoraEngine != null) {
        await AgoraService.leaveChannel(agoraEngine!);
        await AgoraService.dispose();
        agoraEngine = null;
      }
    } catch (e) {
      debugPrint('[BaseGameScreen] _endAgoraCall error: $e');
    }
  }

  void _registerAgoraHandlers() {
    agoraEngine!.registerEventHandler(RtcEngineEventHandler(
      onJoinChannelSuccess: (_, _) { if (!mounted) return; readGame().setLocalUserJoined(true); },
      onUserJoined: (_, uid, _) {
        if (!mounted) return;
        readGame().setRemoteUser(uid);
        _remoteJoinedWatchdog?.cancel();
        _remoteJoinedWatchdog = null;
      },
      onUserOffline: (_, uid, _) {
        if (!mounted) return;
        // On the legacy path we don't know the opponent UID ahead of time,
        // so any offline = clear. On the strict path we keep the view bound
        // to the deterministic opponent UID so reconnects re-render
        // immediately without going through a black-tile intermediate state.
        final g = readGame();
        final bool hasStrict = (g.hasStrictAgoraCredentials as bool?) ?? false;
        if (!hasStrict) {
          g.setRemoteUser(null);
          return;
        }
        final opponentUid = (g.opponentAgoraUid as int?) ?? 0;
        if (opponentUid == 0 || uid != opponentUid) {
          g.setRemoteUser(null);
        }
      },
      // Why: when the opponent's stream freezes/fails, force a re-subscribe by
      // toggling muteRemoteVideoStream. Without this, the local viewer sees a
      // frozen frame indefinitely — there is no other code path that detects
      // a remote freeze, since onUserOffline only fires on a real disconnect.
      onRemoteVideoStateChanged: (_, uid, state, reason, _) {
        if (!mounted) return;
        if (state != RemoteVideoState.remoteVideoStateFrozen &&
            state != RemoteVideoState.remoteVideoStateFailed) return;
        debugPrint('[Agora] remote video $uid → $state (reason=$reason); recovering');
        _recoverRemoteVideo(uid);
      },
      // Why: detect when the SDK has given up reconnecting on its own and
      // proactively ask the server for a fresh token + re-join. Without this
      // we only reconnect on AppLifecycleState.resumed, so a connection drop
      // that happens while the app is foreground stays broken.
      onConnectionStateChanged: (_, state, reason) {
        debugPrint('[Agora] connection state → $state (reason=$reason)');
        if (!mounted) return;
        if (state == ConnectionStateType.connectionStateFailed) {
          try { readGame().reconnectToMatch(); } catch (_) {}
        }
      },
    ));
  }

  Future<void> _recoverRemoteVideo(int uid) async {
    if (_remoteVideoRecoveryInFlight) return;
    _remoteVideoRecoveryInFlight = true;
    try {
      await agoraEngine?.muteRemoteVideoStream(uid: uid, mute: true);
      await Future.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;
      await agoraEngine?.muteRemoteVideoStream(uid: uid, mute: false);
    } catch (e) {
      debugPrint('[Agora] _recoverRemoteVideo error: $e');
    } finally {
      _remoteVideoRecoveryInFlight = false;
    }
  }

  /// Watchdog that fires if onUserJoined has not arrived for the opponent
  /// within [_remoteJoinedWatchdogDelay]. Only meaningful when both sides
  /// are on the strict-UID path; on the legacy path the opponent's UID is
  /// auto-assigned by Agora, so we can't pre-target a recovery.
  void _armRemoteVideoWatchdog() {
    _remoteJoinedWatchdog?.cancel();
    final game = readGame();
    final bool hasStrict = (game.hasStrictAgoraCredentials as bool?) ?? false;
    if (!hasStrict) return;
    _remoteJoinedWatchdog = Timer(_remoteJoinedWatchdogDelay, () async {
      if (!mounted) return;
      final g = readGame();
      final int opponentUid = (g.opponentAgoraUid as int?) ?? 0;
      if (opponentUid == 0 || agoraEngine == null) return;
      debugPrint('[Agora] watchdog: forcing remote re-subscribe for uid=$opponentUid');
      await _recoverRemoteVideo(opponentUid);
    });
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
    // P2P: the audio track is pre-added disabled, so the toggle is a plain
    // enabled flip — same isAudioMuted state handling as Agora.
    if (p2pVideo != null) {
      setState(() => isAudioMuted = !isAudioMuted);
      await p2pVideo!.setMicEnabled(!isAudioMuted);
      return;
    }
    if (agoraEngine == null) return;
    setState(() => isAudioMuted = !isAudioMuted);
    await agoraEngine!.updateChannelMediaOptions(ChannelMediaOptions(publishMicrophoneTrack: !isAudioMuted));
    await agoraEngine!.muteLocalAudioStream(isAudioMuted);
  }
  Future<void> switchCamera() async {
    // Web uses Agora's own capture — let the SDK flip it.
    if (kIsWeb) {
      try {
        await agoraEngine?.switchCamera();
      } catch (e) {
        debugPrint('[BaseGameScreen] web switchCamera error: $e');
      }
      return;
    }
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
      accent: AppTheme.opponentPink,
      icon: Icons.warning_amber_rounded,
      title: l10n.leaveMatch,
      content: Text(leaveWarningText, style: AppTheme.bodyLarge.copyWith(fontSize: 15), textAlign: TextAlign.center),
      actionsBuilder: (ctx) => [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(l10n.stayInMatch, style: const TextStyle(color: AppTheme.textSecondary)),
        ),
        ElevatedButton(
          onPressed: () { leaveMatch(); Navigator.pop(ctx, true); },
          style: gameFilledButtonStyle(AppTheme.opponentPink),
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
    showGameDialog(
      context,
      accent: AppTheme.success,
      icon: Icons.emoji_events,
      title: l10n.checkout,
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        if (notation != null && notation.isNotEmpty) ...[
          Text(l10n.youHitToFinish(notation), style: AppTheme.bodyLarge.copyWith(fontSize: 16), textAlign: TextAlign.center),
          const SizedBox(height: 8),
        ],
        Text(l10n.isThisCorrect, style: const TextStyle(color: AppTheme.textSecondary)),
      ]),
      actionsBuilder: (ctx) => [
        OutlinedButton(
          onPressed: () { winDialogShowing = false; Navigator.pop(ctx); setState(() { aiPausedForEdit = true; }); autoScoringService?.stopCapture(); game.undoAllDarts(); _turnDartTimes.clear(); for (int i = 0; i < 3; i++) { autoScoringService?.clearDart(i); } },
          style: gameOutlineButtonStyle(AppTheme.playerBlue),
          child: Text(l10n.editDarts),
        ),
        ElevatedButton(
          onPressed: () { winDialogShowing = false; Navigator.pop(ctx); setState(() { aiPausedForEdit = true; }); autoScoringService?.stopCapture(); game.confirmWin(); },
          style: gameFilledButtonStyle(AppTheme.success),
          child: Text(l10n.confirmWin),
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
    showGameDialog(
      context,
      accent: AppTheme.opponentPink,
      icon: Icons.warning_amber_rounded,
      title: l10n.bust,
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(reasonText, style: AppTheme.bodyLarge.copyWith(fontSize: 16), textAlign: TextAlign.center),
        const SizedBox(height: 8), Text(l10n.confirmPassOrEdit, style: const TextStyle(color: AppTheme.textSecondary), textAlign: TextAlign.center),
      ]),
      actionsBuilder: (ctx) => [
        OutlinedButton(
          onPressed: () { bustDialogShowing = false; Navigator.pop(ctx); setState(() { aiPausedForEdit = true; }); autoScoringService?.stopCapture(); game.undoAllDarts(); _turnDartTimes.clear(); for (int i = 0; i < 3; i++) { autoScoringService?.clearDart(i); } },
          style: gameOutlineButtonStyle(AppTheme.playerBlue),
          child: Text(l10n.editDarts),
        ),
        ElevatedButton(
          onPressed: () { bustDialogShowing = false; Navigator.pop(ctx); setState(() { aiPausedForEdit = true; }); autoScoringService?.stopCapture(); game.confirmBust(); },
          style: gameFilledButtonStyle(AppTheme.opponentPink),
          child: Text(l10n.confirmBustButton),
        ),
      ],
    ).then((_) { if (mounted) bustDialogShowing = false; });
  }

  /// Reason + optional comment dialog feeding the dispute endpoint. Defaults
  /// to the "report player" wording; tournaments restyle it as "refuse result"
  /// via the optional labels without changing the underlying call.
  void showReportDialog({
    required Future<void> Function(String reason, String? comment) onSubmit,
    required VoidCallback onComplete,
    String? title,
    String? subtitle,
    String? submitLabel,
    List<String>? reasons,
    IconData icon = Icons.flag,
  }) {
    String? selectedReason;
    final commentController = TextEditingController();
    final l10n = AppLocalizations.of(context);
    final reasonList = reasons ??
        [
          l10n.reportReasonCheating,
          l10n.reportReasonUnsportsmanlike,
          l10n.reportReasonIncorrectScore,
          l10n.reportReasonConnectionIssues,
          l10n.reportReasonOther,
        ];
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setDlg) => gameDialogFrame(
      accent: AppTheme.opponentPink,
      icon: icon,
      title: title ?? l10n.reportPlayer,
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(subtitle ?? l10n.selectReasonReporting, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
        const SizedBox(height: 16),
        ...reasonList.map((r) => InkWell(
          onTap: () => setDlg(() => selectedReason = r),
          child: Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Row(children: [
            Icon(selectedReason == r ? Icons.radio_button_checked : Icons.radio_button_unchecked, color: selectedReason == r ? AppTheme.opponentPink : AppTheme.textSecondary),
            const SizedBox(width: 12), Text(r, style: const TextStyle(color: Colors.white)),
          ])),
        )),
        const SizedBox(height: 16),
        Text(l10n.reportCommentLabel, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
        const SizedBox(height: 8),
        TextField(
          controller: commentController,
          minLines: 3,
          maxLines: 5,
          maxLength: 500,
          textInputAction: TextInputAction.newline,
          cursorColor: AppTheme.opponentPink,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            hintText: l10n.reportCommentHint,
            hintStyle: TextStyle(color: AppTheme.textSecondary.withValues(alpha: 0.6), fontSize: 14),
            counterStyle: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
            filled: true,
            fillColor: AppTheme.surface,
            contentPadding: const EdgeInsets.all(12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppTheme.surfaceLight.withValues(alpha: 0.5))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.opponentPink, width: 2)),
          ),
        ),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(l10n.cancel.toUpperCase(), style: const TextStyle(color: AppTheme.textSecondary))),
        ElevatedButton(
          onPressed: selectedReason == null ? null : () async {
            HapticService.mediumImpact();
            final comment = commentController.text.trim();
            Navigator.of(ctx).pop();
            final messenger = ScaffoldMessenger.of(context);
            try {
              await onSubmit(selectedReason!, comment.isEmpty ? null : comment);
              if (mounted) messenger.showSnackBar(SnackBar(content: Text(l10n.disputeSubmitted), backgroundColor: AppTheme.success, duration: const Duration(seconds: 2)));
            } catch (e) {
              if (mounted) messenger.showSnackBar(SnackBar(content: Text(l10n.errorWithMessage.replaceAll('{message}', e.toString())), backgroundColor: AppTheme.error, duration: const Duration(seconds: 3)));
            }
            onComplete();
          },
          style: gameFilledButtonStyle(AppTheme.opponentPink),
          child: Text(submitLabel ?? l10n.submitReport),
        ),
      ],
    ))).then((_) => commentController.dispose());
  }

  // ─── Shared widget builders ────────────────────────────────────────────────────
  String formatSeconds(int s) { final m = s ~/ 60; final r = s % 60; return '$m:${r.toString().padLeft(2, '0')}'; }

  /// Back action shared by both turn layouts: confirm-leave dialog, then pop.
  Future<void> handleBackPressed() async {
    final shouldLeave = await onWillPop();
    if (shouldLeave && mounted) Navigator.of(context).pop();
  }

  /// Back button styled like the in-camera controls (rounded square).
  Widget buildGameBackButton() => GameControlButton(
        icon: Icons.arrow_back_ios_new,
        color: AppTheme.textSecondary,
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.error.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 16, height: 16,
              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${l10n.connectionLostReconnecting}\n${l10n.timeLeftToReconnect.replaceAll('{time}', formatSeconds(graceSeconds))}',
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
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
          const CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 2),
          const SizedBox(height: 24),
          Text(AppLocalizations.of(context).preparingMatch, style: AppTheme.titleLarge.copyWith(color: AppTheme.textSecondary, letterSpacing: 3, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(loadingMessage, style: AppTheme.bodyLarge.copyWith(color: AppTheme.textSecondary)),
        ]))),
      ),
    );
  }

  Widget buildOpponentTurnVideoLayout(dynamic game, {String channelId = ''}) {
    final opponentThrows = game.opponentRoundThrows as List<String>;
    // Same "Waiting..." placeholder for the P2P and Agora branches.
    final Widget waitingPlaceholder = Container(
      color: AppTheme.gamePanelEmpty,
      child: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.videocam_off, size: 48, color: AppTheme.textSecondary), const SizedBox(height: 8),
        Text(AppLocalizations.of(context).waitingUpper, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontWeight: FontWeight.bold)),
      ])),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
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
                  ? (p2pVideo!.remoteView() ?? waitingPlaceholder)
                  : waitingPlaceholder)
            else if (agoraEngine != null && game.remoteUid != null)
              kIsWeb
                ? FittedBox(
                    fit: BoxFit.cover,
                    child: RotatedBox(
                      quarterTurns: 1,
                      child: SizedBox(
                        width: 720,
                        height: 960,
                        child: AgoraVideoView(
                          controller: VideoViewController.remote(
                            rtcEngine: agoraEngine!,
                            canvas: VideoCanvas(
                              uid: game.remoteUid!,
                              renderMode: RenderModeType.renderModeHidden,
                            ),
                            connection: RtcConnection(channelId: channelId),
                          ),
                        ),
                      ),
                    ),
                  )
                : AgoraVideoView(
                    controller: VideoViewController.remote(
                      rtcEngine: agoraEngine!,
                      canvas: VideoCanvas(
                        uid: game.remoteUid!,
                        renderMode: RenderModeType.renderModeHidden,
                      ),
                      connection: RtcConnection(channelId: channelId),
                    ),
                  )
            else
              waitingPlaceholder,
            // ── Dart-hit flash (big "T20 / +60 pts" glow) ──
            DartHitFlash(throws: opponentThrows),
            // ── Pink border ──
            Container(decoration: BoxDecoration(border: Border.all(color: AppTheme.opponentPink, width: 2), borderRadius: BorderRadius.circular(22))),
            // ── Brand bug (top center), like a TV channel logo ──
            const Positioned(
              top: 12,
              left: 0,
              right: 0,
              child: Center(child: LogoWatermark()),
            ),
            // ── Live badge ──
            const Positioned(top: 12, left: 12, child: LiveBadge()),
            // ── Mic / camera controls ──
            Positioned(
              top: 10,
              right: 10,
              child: Row(children: [
                GameControlButton(
                  icon: isAudioMuted ? Icons.mic_off : Icons.mic,
                  color: isAudioMuted ? AppTheme.opponentPink : AppTheme.playerBlue,
                  onTap: toggleAudio,
                ),
                const SizedBox(width: 8),
                GameControlButton(
                  icon: Icons.cameraswitch,
                  color: AppTheme.playerBlue,
                  onTap: switchCamera,
                ),
              ]),
            ),
          ],
        ),
      );
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

  /// "VOLÉE DE (name) … TOTAL n" label row + the three visit chips for the
  /// opponent's current visit.
  Widget buildOpponentVisitSection(dynamic game) {
    final l10n = AppLocalizations.of(context);
    final throws = game.opponentRoundThrows as List<String>;
    final total = throws.fold<int>(0, (sum, n) => sum + notationPoints(n));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(children: [
          Expanded(
            child: Text(
              l10n.visitOf(opponentUsername.toUpperCase()),
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
          VisitTotal(total: total, color: AppTheme.opponentPinkBright),
        ]),
        const SizedBox(height: 8),
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

  /// Yellow "opponent disconnected" strip (unchanged behavior, shared here so
  /// both game screens stop duplicating it).
  Widget? buildOpponentDisconnectBanner(dynamic game) {
    if (game.opponentDisconnected != true) return null;
    final l10n = AppLocalizations.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: AppTheme.accent.withValues(alpha: 0.15),
      child: Row(
        children: [
          const Icon(Icons.wifi_off, color: AppTheme.accent, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${l10n.opponentDisconnected} — ${l10n.timeLeftToReconnect.replaceAll('{time}', formatSeconds(game.disconnectGraceSeconds))}',
              style: const TextStyle(color: AppTheme.accent, fontSize: 13, fontWeight: FontWeight.w600),
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
    String? channelId,
    String? seriesTitle,
    int myLegs = 0,
    int opponentLegs = 0,
  }) {
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    final safeBottom = MediaQuery.of(context).padding.bottom;
    final disconnectBanner = buildOpponentDisconnectBanner(game);

    final header = TurnScoreHeader(
      myName: auth.currentUser?.username ?? 'You',
      opponentName: opponentUsername,
      myScore: game.myScore,
      opponentScore: game.opponentScore,
      roundNumber: roundNumberOf(game, forOpponent: true),
      myAverage: myAvgOrNull(game),
      opponentAverage: opponentAvgOrNull(game),
      leading: buildGameBackButton(),
      seriesTitle: seriesTitle,
      myLegs: myLegs,
      opponentLegs: opponentLegs,
    );

    final cameraView = buildOpponentTurnVideoLayout(
      game,
      channelId: channelId ?? game.agoraChannelName ?? '',
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
                    child: Column(children: [
                      header,
                      const SizedBox(height: 8),
                      Expanded(
                        child: SingleChildScrollView(
                          child: buildOpponentVisitSection(game),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const OpponentWarningBanner(),
                    ]),
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
          SizedBox(height: safeTop),
          if (disconnectBanner != null) disconnectBanner,
          const SizedBox(height: 6),
          header,
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SizedBox(
              height: gameCameraHeight(context),
              child: cameraView,
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: buildOpponentVisitSection(game),
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

  /// Agora channel fallback when the provider doesn't hold one (ranked passes
  /// the channel it was opened with).
  String? get fallbackAgoraChannelId => null;

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
                      const CircularProgressIndicator(color: AppTheme.primary),
                      const SizedBox(height: 16),
                      Text(l10n.initializingMatch, style: const TextStyle(color: AppTheme.textSecondary, letterSpacing: 2, fontWeight: FontWeight.bold)),
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
          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        Text(
          offline ? l10n.matchNotStartingOffline : l10n.matchNotStartingBody,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
        ),
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton.icon(
            onPressed: retryingStart ? null : retryMatchStart,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            icon: retryingStart
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            label: Text(l10n.retry, style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: OutlinedButton(
            // Through onWillPop: the match may still be live server-side, so
            // leaving must go through the same forfeit warning as the board.
            onPressed: () async {
              if (await onWillPop() && mounted) Navigator.of(context).pop();
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.textSecondary,
              side: BorderSide(color: AppTheme.surfaceLight.withValues(alpha: 0.6), width: 2),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: Text(l10n.leave, style: const TextStyle(fontWeight: FontWeight.bold)),
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
                        const CircularProgressIndicator(color: AppTheme.primary),
                        const SizedBox(height: 16),
                        Text(AppLocalizations.of(context).loadingAutoScoring, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
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
                    myScore: game.myScore,
                    opponentScore: game.opponentScore,
                    opponentName: opponentUsername,
                    myName: auth.currentUser?.username ?? 'You',
                    iAmPlayer2: game.iAmPlayer2,
                    dartsThrown: game.dartsThrown,
                    captureButton: buildReplayCaptureButton(game),
                    agoraEngine: agoraEngine,
                    localCameraPreview: !switchingCamera && cameraFrameService?.controller != null && cameraFrameService!.controller!.value.isInitialized
                        ? LocalCameraPreview(controller: cameraFrameService!.controller!)
                        : null,
                    remoteUid: game.remoteUid,
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
                    myAverage: myAvgOrNull(game),
                    opponentAverage: opponentAvgOrNull(game),
                    roundNumber: roundNumberOf(game, forOpponent: false),
                    onBack: handleBackPressed,
                    seriesTitle: seriesTitle,
                    myLegs: game.myLegsWon,
                    opponentLegs: game.opponentLegsWon,
                  )
                // Opponent's turn
                : buildOpponentTurnScreenShared(
                    game,
                    auth,
                    safeTop,
                    channelId: game.agoraChannelName ?? fallbackAgoraChannelId ?? '',
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
 