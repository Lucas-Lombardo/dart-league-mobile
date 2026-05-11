import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import '../../providers/game_provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/agora_service.dart';
import '../../services/camera_frame_service.dart';
import '../../services/socket_service.dart';
import '../../utils/haptic_service.dart';
import '../../utils/dart_sound_service.dart';
import '../../utils/app_theme.dart';
import '../../utils/score_converter.dart';
import '../../utils/storage_service.dart';
import '../../services/auto_scoring_service.dart';
import '../../services/dart_scoring_service.dart';
import '../../l10n/app_localizations.dart';

/// Shared base state for GameScreen and TournamentGameScreen.
/// readGame() returns dynamic to support both GameProvider and TournamentGameProvider.
abstract class BaseGameScreenState<W extends StatefulWidget> extends State<W>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {

  // ─── Abstract ────────────────────────────────────────────────────────────────
  dynamic readGame();
  String get opponentUsername;
  Widget buildAppBarTitle();
  Widget? buildExtraHeader(dynamic game, AuthProvider auth);
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
  RtcEngine? agoraEngine;
  CameraFrameService? cameraFrameService;
  int? customVideoTrackId;
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
  String? lastKnownCurrentPlayer;
  bool winDialogShowing = false;
  bool bustDialogShowing = false;
  bool forfeitDialogShowing = false;
  // Why: iOS fires inactive → resumed for sub-second blips (screenshot,
  // notification, control center). Reconnecting Agora on every blip resets
  // the mic to muted (since joinChannel defaults to publishMicrophoneTrack:
  // false). Track whether we actually backgrounded so we only re-sync after a
  // real paused state.
  bool _wasPausedSinceLastResume = false;

  // ─── Lifecycle ────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WakelockPlus.enable();
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
    disposeScreenSpecific();
    scoreAnimationController.dispose();
    WakelockPlus.disable();
    autoScoringService?.dispose();
    autoScoringService = null;
    cameraFrameService?.dispose();
    cameraFrameService = null;
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
      if (!_wasPausedSinceLastResume) {
        // Came back from a brief inactive blip — no socket/Agora work needed.
        return;
      }
      _wasPausedSinceLastResume = false;
      // App actually backgrounded — re-sync everything.
      SocketService.ensureConnected().then((_) {
        if (!mounted) return;
        final game = readGame();
        // Tell the server we're back so opponent sees us as connected
        game.reconnectToMatch();
        // Re-register socket listeners in case they were lost
        game.ensureListenersSetup();
      });
    }
  }

  // ─── State-change handler ─────────────────────────────────────────────────────
  void handleSharedStateChange() {
    if (!mounted) return;
    try {
      final game = readGame();
      gameStarted = game.gameStarted;
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
      if (game.currentPlayerId != lastKnownCurrentPlayer && lastKnownCurrentPlayer != null) {
        if (game.isMyTurn) {
          DartSoundService.playYourTurn();
        } else {
          DartSoundService.playTurnFinished();
        }
      }
      final justBecameMyTurn = game.isMyTurn && game.currentPlayerId != lastKnownCurrentPlayer;
      // Reset dart slots on turn change (always, even without AI capture)
      if (justBecameMyTurn) { aiManuallyDisabled = false; aiPausedForEdit = false; autoScoringService!.resetTurn(); }
      // Start/stop AI capture when supported
      if (autoScoringEnabled && !aiManuallyDisabled && _captureFrameCallback != null && autoScoringService!.modelLoaded) {
        final pendingNeedsStop = game.pendingConfirmation && (game.pendingType == 'bust' || game.pendingType == 'win');
        if (game.isMyTurn && !pendingNeedsStop && !autoScoringService!.isCapturing && !aiPausedForEdit) {
          if (!justBecameMyTurn && !game.pendingConfirmation) { autoScoringService!.syncEmittedCount(game.currentRoundThrows.length); }
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
      lastKnownCurrentPlayer = game.currentPlayerId;
      if (game.pendingConfirmation && game.pendingType != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !context.mounted) return;
          if (game.pendingType == 'win' && !winDialogShowing) { showPendingWinDialog(game); }
          else if (game.pendingType == 'bust' && !bustDialogShowing) { DartSoundService.playBust(); showPendingBustDialog(game); }
        });
      }
      if (game.needsAgoraReconnect) { game.clearAgoraReconnectFlag(); reconnectAgora(game); }
      if (game.gameEnded && game.pendingType == 'forfeit') {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && context.mounted && !forfeitDialogShowing) showForfeitDialog(game);
        });
      }
      onScreenSpecificStateChange(game);
    } catch (_) {}
  }

  void updateLoadingMessage(String msg) {
    if (mounted) setState(() => loadingMessage = msg);
  }

  // ─── Auto-scoring ─────────────────────────────────────────────────────────────
  Future<void> loadAutoScoringPref() async {
    if (kIsWeb || !AutoScoringService.isSupported) { autoScoringEnabled = false; return; }
    final enabled = await StorageService.getAutoScoring();
    if (mounted) setState(() => autoScoringEnabled = enabled);
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
          onDartDetected: _onDartDetectedCallback,
          onAutoConfirm: () { if (mounted) submitAutoScoredDarts(readGame()); },
        );
      }
    });
  }

  Future<void> initAutoScoring() async {
    if (cameraFrameService == null || kIsWeb || !AutoScoringService.isSupported) return;
    final enabled = await StorageService.getAutoScoring();
    if (!mounted) return;
    setState(() => autoScoringEnabled = enabled);
    if (!autoScoringEnabled) return;
    setState(() => autoScoringLoading = true);
    final camService = cameraFrameService!;
    _captureFrameCallback = () => camService.captureFrame();
    _captureRgbaCallback = () => camService.captureRgba();
    _captureBgraCallback = () => camService.captureBgra();
    _captureYuvCallback = () => camService.captureYuvPlanes();
    _onDartDetectedCallback = (_, dartScore) {
      if (!mounted) return;
      final g = readGame();
      if (!g.isMyTurn || g.pendingConfirmation) return;
      final (base, mul) = dartScoreToBackend(dartScore);
      HapticService.mediumImpact();
      DartSoundService.playDartHit(base, mul);
      g.throwDart(baseScore: base, multiplier: mul);
    };
    await autoScoringService!.loadModel();
    if (mounted) {
      setState(() => autoScoringLoading = false);
      if (autoScoringService!.modelLoaded) {
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

  void submitAutoScoredDarts(dynamic game) { aiPausedForEdit = false; autoScoringService?.stopCapture(); game.confirmRound(); }

  // ─── Agora ────────────────────────────────────────────────────────────────────
  Future<void> initializeAgora({required String appId, required String token, required String channelName}) async {
    if (!kIsWeb) {
      permissionsGranted = await AgoraService.requestPermissions();
      if (!permissionsGranted) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).cameraAndMicPermissionRequired), backgroundColor: AppTheme.error));
        return;
      }
    } else {
      permissionsGranted = true;
    }
    try {
      if (kIsWeb) {
        // Web: use default Agora camera capture (custom video track not supported)
        agoraEngine = await AgoraService.initializeEngineWeb(appId);
        _registerAgoraHandlers();
        await AgoraService.joinChannel(
          engine: agoraEngine!,
          token: token,
          channelName: channelName,
          uid: 0,
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
        );

        // 4. Register Agora event handlers
        _registerAgoraHandlers();

        // 5. Join channel with custom video track
        await AgoraService.joinChannel(
          engine: agoraEngine!,
          token: token,
          channelName: channelName,
          uid: 0,
          customVideoTrackId: customVideoTrackId,
        );

        // 6. Init camera zoom from saved preferences
        await initCameraZoom();

        // 7. Init auto scoring — fire-and-forget so the game screen shows immediately.
        // autoScoringLoading flag drives the UI loading state.
        initAutoScoring();
      }
    } catch (e) {
      debugPrint('[BaseGameScreen] initializeAgora error: $e');
      if (mounted) setState(() => autoScoringLoading = false);
    }
  }

  Future<void> reconnectAgora(dynamic game) async {
    final appId = game.agoraAppId; final token = game.agoraToken; final channelName = game.agoraChannelName;
    if (appId == null || appId.isEmpty || token == null || token.isEmpty || channelName == null || channelName.isEmpty) {
      if (mounted) setState(() => autoScoringLoading = false);
      return;
    }
    // Preserve the user's mic preference across the reconnect so a resumed-
    // from-background or a screenshot-induced reconnect doesn't silently
    // re-mute the mic.
    final wasUnmuted = !isAudioMuted;
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
          uid: 0,
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
        );
        _registerAgoraHandlers();
        await AgoraService.joinChannel(
          engine: agoraEngine!,
          token: token,
          channelName: channelName,
          uid: 0,
          customVideoTrackId: customVideoTrackId,
        );
        // Why: explicitly re-assert publishing flags after joinChannel.
        // Without this, opponents intermittently fail to receive the rejoiner's
        // video — joinChannel's options are sometimes not enough on rejoin.
        try {
          await agoraEngine!.updateChannelMediaOptions(ChannelMediaOptions(
            publishCustomVideoTrack: true,
            customVideoTrackId: customVideoTrackId,
            publishCameraTrack: false,
          ));
        } catch (e) {
          debugPrint('[BaseGameScreen] updateChannelMediaOptions(video) error: $e');
        }
        cameraZoomInitialized = false;
        await initCameraZoom();
        autoScoringService!.stopCapture();
        autoScoringService!.resetTurn();
        initAutoScoring();
      }
      // Restore mic state: if user had unmuted before the reconnect, re-publish
      // the mic track. joinChannel always defaults to publishMicrophoneTrack:
      // false, so without this the mic UI flips to muted on every reconnect.
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
    } catch (_) {
      if (mounted) setState(() => autoScoringLoading = false);
    }
  }

  void _registerAgoraHandlers() {
    agoraEngine!.registerEventHandler(RtcEngineEventHandler(
      onJoinChannelSuccess: (_, _) { if (!mounted) return; readGame().setLocalUserJoined(true); },
      onUserJoined: (_, uid, _) { if (!mounted) return; readGame().setRemoteUser(uid); },
      onUserOffline: (_, uid, _) { if (!mounted) return; readGame().setRemoteUser(null); },
    ));
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
    if (agoraEngine == null) return;
    setState(() => isAudioMuted = !isAudioMuted);
    await agoraEngine!.updateChannelMediaOptions(ChannelMediaOptions(publishMicrophoneTrack: !isAudioMuted));
    await agoraEngine!.muteLocalAudioStream(isAudioMuted);
  }
  Future<void> switchCamera() async {
    // Not applicable with custom video track — always uses back camera
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
  void leaveMatch() {
    try {
      final matchId = matchIdForLeave;
      if (matchId != null && storedPlayerId != null && gameStarted && !gameEnded) {
        SocketService.emit('leave_match', {'matchId': matchId, 'playerId': storedPlayerId});
      }
    } catch (_) {}
  }

  Future<bool> onWillPop() async {
    final game = readGame();
    if (!game.gameStarted || game.gameEnded) return true;
    final l10n = AppLocalizations.of(context);
    final result = await showDialog<bool>(
      context: context, barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: AppTheme.error, width: 2)),
        title: Row(children: [const Icon(Icons.warning, color: AppTheme.error, size: 32), const SizedBox(width: 12), Text(l10n.leaveMatch, style: AppTheme.titleLarge.copyWith(color: AppTheme.error, fontWeight: FontWeight.bold))]),
        content: Text(leaveWarningText, style: AppTheme.bodyLarge.copyWith(fontSize: 16), textAlign: TextAlign.center),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.stayInMatch)),
          ElevatedButton(onPressed: () { leaveMatch(); Navigator.pop(ctx, true); }, style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error), child: Text(l10n.leaveAndForfeit)),
        ],
      ),
    );
    return result ?? false;
  }

  // ─── Shared dialogs ───────────────────────────────────────────────────────────
  void showPendingWinDialog(dynamic game) {
    final notation = (game.pendingData?['finalDart'])?['notation'] ?? 'Unknown';
    final l10n = AppLocalizations.of(context);
    winDialogShowing = true;
    showDialog(context: context, barrierDismissible: false, builder: (ctx) => AlertDialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: AppTheme.success, width: 2)),
      title: Row(children: [const Icon(Icons.emoji_events, color: AppTheme.success, size: 32), const SizedBox(width: 12), Text(l10n.checkout, style: AppTheme.titleLarge.copyWith(color: AppTheme.success, fontWeight: FontWeight.bold))]),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(l10n.youHitToFinish(notation), style: AppTheme.bodyLarge.copyWith(fontSize: 16), textAlign: TextAlign.center),
        const SizedBox(height: 8), Text(l10n.isThisCorrect, style: const TextStyle(color: AppTheme.textSecondary)),
      ]),
      actions: [
        OutlinedButton(onPressed: () { winDialogShowing = false; Navigator.pop(ctx); setState(() { aiPausedForEdit = true; }); autoScoringService?.stopCapture(); game.undoAllDarts(); for (int i = 0; i < 3; i++) { autoScoringService?.clearDart(i); } }, child: Text(l10n.editDarts)),
        ElevatedButton(onPressed: () { winDialogShowing = false; Navigator.pop(ctx); setState(() { aiPausedForEdit = true; }); autoScoringService?.stopCapture(); game.confirmWin(); }, style: ElevatedButton.styleFrom(backgroundColor: AppTheme.success), child: Text(l10n.confirmWin)),
      ],
    )).then((_) { if (mounted) winDialogShowing = false; });
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
    showDialog(context: context, barrierDismissible: false, builder: (ctx) => AlertDialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: AppTheme.error, width: 2)),
      title: Row(children: [const Icon(Icons.warning, color: AppTheme.error, size: 32), const SizedBox(width: 12), Text(l10n.bust, style: AppTheme.titleLarge.copyWith(color: AppTheme.error, fontWeight: FontWeight.bold))]),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(reasonText, style: AppTheme.bodyLarge.copyWith(fontSize: 16), textAlign: TextAlign.center),
        const SizedBox(height: 8), Text(l10n.confirmPassOrEdit, style: const TextStyle(color: AppTheme.textSecondary), textAlign: TextAlign.center),
      ]),
      actions: [
        OutlinedButton(onPressed: () { bustDialogShowing = false; Navigator.pop(ctx); setState(() { aiPausedForEdit = true; }); autoScoringService?.stopCapture(); game.undoAllDarts(); for (int i = 0; i < 3; i++) { autoScoringService?.clearDart(i); } }, child: Text(l10n.editDarts)),
        ElevatedButton(onPressed: () { bustDialogShowing = false; Navigator.pop(ctx); setState(() { aiPausedForEdit = true; }); autoScoringService?.stopCapture(); game.confirmBust(); }, style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error), child: Text(l10n.confirmBustButton)),
      ],
    )).then((_) { if (mounted) bustDialogShowing = false; });
  }

  void showReportDialog({required Future<void> Function(String) onSubmit, required VoidCallback onComplete}) {
    String? selectedReason;
    final l10n = AppLocalizations.of(context);
    final reasons = [
      l10n.reportReasonCheating,
      l10n.reportReasonUnsportsmanlike,
      l10n.reportReasonIncorrectScore,
      l10n.reportReasonConnectionIssues,
      l10n.reportReasonOther,
    ];
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setDlg) => AlertDialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: AppTheme.error, width: 2)),
      title: Row(children: [const Icon(Icons.flag, color: AppTheme.error), const SizedBox(width: 12), Text(l10n.reportPlayer, style: AppTheme.titleLarge.copyWith(color: AppTheme.error, fontWeight: FontWeight.bold))]),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(l10n.selectReasonReporting, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
        const SizedBox(height: 16),
        ...reasons.map((r) => InkWell(
          onTap: () => setDlg(() => selectedReason = r),
          child: Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Row(children: [
            Icon(selectedReason == r ? Icons.radio_button_checked : Icons.radio_button_unchecked, color: selectedReason == r ? AppTheme.error : AppTheme.textSecondary),
            const SizedBox(width: 12), Text(r, style: const TextStyle(color: Colors.white)),
          ])),
        )),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(l10n.cancel.toUpperCase(), style: const TextStyle(color: AppTheme.textSecondary))),
        ElevatedButton(
          onPressed: selectedReason == null ? null : () async {
            HapticService.mediumImpact(); Navigator.of(ctx).pop();
            final messenger = ScaffoldMessenger.of(context);
            try {
              await onSubmit(selectedReason!);
              if (mounted) messenger.showSnackBar(SnackBar(content: Text(l10n.disputeSubmitted), backgroundColor: AppTheme.success, duration: const Duration(seconds: 2)));
            } catch (e) {
              if (mounted) messenger.showSnackBar(SnackBar(content: Text(l10n.errorWithMessage.replaceAll('{message}', e.toString())), backgroundColor: AppTheme.error, duration: const Duration(seconds: 3)));
            }
            onComplete();
          },
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          child: Text(l10n.submitReport, style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    )));
  }

  // ─── Shared widget builders ────────────────────────────────────────────────────
  String formatSeconds(int s) { final m = s ~/ 60; final r = s % 60; return '$m:${r.toString().padLeft(2, '0')}'; }

  Widget buildLoadingScreen() {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async { if (didPop) return; final nav = Navigator.of(context); if (await onWillPop() && context.mounted) nav.pop(); },
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        fit: StackFit.expand,
          children: [
            // ── Camera feed ──
            if (agoraEngine != null && game.remoteUid != null)
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
              Container(
                color: AppTheme.surface,
                child: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.videocam_off, size: 48, color: AppTheme.textSecondary), const SizedBox(height: 8),
                  Text(AppLocalizations.of(context).waitingUpper, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontWeight: FontWeight.bold)),
                ])),
              ),
            // ── Red border ──
            Container(decoration: BoxDecoration(border: Border.all(color: AppTheme.error, width: 3), borderRadius: BorderRadius.circular(16))),
            // ── Controls + dart scores — bottom overlay ──
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black.withValues(alpha: 0.75), Colors.transparent],
                  ),
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  buildControlButton(icon: isAudioMuted ? Icons.mic_off : Icons.mic, color: isAudioMuted ? AppTheme.error : AppTheme.primary, onTap: toggleAudio),
                  const SizedBox(width: 10),
                  buildControlButton(icon: Icons.cameraswitch, color: AppTheme.primary, onTap: switchCamera),
                  const SizedBox(width: 20),
                  ...List.generate(3, (i) {
                    final hasThrow = i < opponentThrows.length;
                    return Container(
                      width: 52,
                      margin: const EdgeInsets.only(left: 6),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: hasThrow ? AppTheme.primary.withValues(alpha: 0.7) : Colors.white24),
                      ),
                      child: Text(
                        hasThrow ? opponentThrows[i] : '—',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: hasThrow ? Colors.white : Colors.white38, fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                    );
                  }),
                ]),
              ),
            ),
          ],
        ),
      );
  }

  Widget buildControlButton({required IconData icon, required Color color, required VoidCallback onTap}) {
    return Material(color: Colors.transparent, child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(8), child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(8), border: Border.all(color: color, width: 2)),
      child: Icon(icon, color: color, size: 24),
    )));
  }

  Widget buildOpponentWaitingPanel(dynamic game) {
    final myHint = (game.myScore >= 2 && game.myScore <= 170) ? checkoutHint(game.myScore) : null;
    final l10n = AppLocalizations.of(context);
    return Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const SizedBox(width: 36, height: 36, child: CircularProgressIndicator(color: AppTheme.error, strokeWidth: 2.5)),
      const SizedBox(height: 12),
      Text(l10n.opponentTurnUpper, style: TextStyle(color: AppTheme.error.withValues(alpha: 0.8), fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 2)),
      const SizedBox(height: 4), Text(l10n.pleaseWait, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
      if (myHint != null) ...[
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(color: AppTheme.success.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10), border: Border.all(color: AppTheme.success.withValues(alpha: 0.4))),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.gps_fixed, color: AppTheme.success, size: 18), const SizedBox(width: 8),
            Text(l10n.finishHint(myHint), style: const TextStyle(color: AppTheme.success, fontSize: 13, fontWeight: FontWeight.bold)),
          ]),
        ),
      ],
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        margin: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(color: AppTheme.error.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10), border: Border.all(color: AppTheme.error.withValues(alpha: 0.5))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.warning_rounded, color: AppTheme.error, size: 18), const SizedBox(width: 8),
          Flexible(child: Text(l10n.doNotPlayDuringOpponentTurn, style: const TextStyle(color: AppTheme.error, fontSize: 12, fontWeight: FontWeight.w600))),
        ]),
      ),
    ]));
  }

}
 