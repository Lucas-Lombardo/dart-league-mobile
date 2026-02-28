import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import '../../providers/game_provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/agora_service.dart';
import '../../services/socket_service.dart';
import '../../utils/haptic_service.dart';
import '../../utils/dart_sound_service.dart';
import '../../utils/app_theme.dart';
import '../../utils/score_converter.dart';
import '../../utils/storage_service.dart';
import '../../services/auto_scoring_service.dart';
import '../../services/dart_scoring_service.dart';
import '../../widgets/auto_score_display.dart';
import '../../widgets/interactive_dartboard.dart';

/// Shared base state for GameScreen and TournamentGameScreen.
/// readGame() returns dynamic to support both GameProvider and TournamentGameProvider.
abstract class BaseGameScreenState<W extends StatefulWidget> extends State<W>
    with SingleTickerProviderStateMixin {

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
  int? editingDartIndex;
  String? storedPlayerId;
  bool gameStarted = false;
  bool gameEnded = false;
  RtcEngine? agoraEngine;
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
  CaptureFrameCallback? _captureFrameCallback;
  OnDartDetectedCallback? _onDartDetectedCallback;
  String? lastKnownCurrentPlayer;
  bool winDialogShowing = false;
  bool bustDialogShowing = false;
  bool forfeitDialogShowing = false;

  // ─── Lifecycle ────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    scoreAnimationController = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Wait 5 seconds so the screen transition completes before heavy init
      await Future.delayed(const Duration(seconds: 5));
      if (!mounted) return;
      try {
        await initScreenSpecific().timeout(
          const Duration(seconds: 10),
          onTimeout: () => print('[Init] Model loading timed out after 10s'),
        );
      } catch (_) {}
      if (mounted) setState(() => isLoading = false);
    });
  }

  @override
  void dispose() {
    disposeScreenSpecific();
    scoreAnimationController.dispose();
    WakelockPlus.disable();
    autoScoringService?.dispose();
    autoScoringService = null;
    if (agoraEngine != null) { AgoraService.leaveChannel(agoraEngine!); AgoraService.dispose(); }
    super.dispose();
  }

  // ─── State-change handler ─────────────────────────────────────────────────────
  void handleSharedStateChange() {
    if (!mounted) return;
    try {
      final game = readGame();
      gameStarted = game.gameStarted;
      gameEnded = game.gameEnded;
      if (autoScoringService != null && autoScoringEnabled && !aiManuallyDisabled && _captureFrameCallback != null) {
        final justBecameMyTurn = game.isMyTurn && game.currentPlayerId != lastKnownCurrentPlayer;
        if (game.isMyTurn && !game.pendingConfirmation && !autoScoringService!.isCapturing) {
          if (justBecameMyTurn) { autoScoringService!.resetTurn(); }
          else { autoScoringService!.syncEmittedCount(game.currentRoundThrows.length); }
          autoScoringService!.startCapture(
            captureFrame: _captureFrameCallback!,
            onDartDetected: _onDartDetectedCallback,
          );
        } else if (!game.isMyTurn && autoScoringService!.isCapturing) {
          autoScoringService!.stopCapture();
        }
      }
      lastKnownCurrentPlayer = game.currentPlayerId;
      if (game.pendingConfirmation && game.pendingType != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !context.mounted) return;
          if (game.pendingType == 'win' && !winDialogShowing) { showPendingWinDialog(game); }
          else if (game.pendingType == 'bust' && !bustDialogShowing) { showPendingBustDialog(game); }
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
          onDartDetected: _onDartDetectedCallback,
        );
      }
    });
  }

  Future<void> initAutoScoring() async {
    if (agoraEngine == null || kIsWeb || !AutoScoringService.isSupported) return;
    final enabled = await StorageService.getAutoScoring();
    if (!mounted) return;
    setState(() => autoScoringEnabled = enabled);
    if (!autoScoringEnabled) return;
    setState(() => autoScoringLoading = true);
    final engine = agoraEngine!;
    _captureFrameCallback = () => AgoraService.takeLocalSnapshot(engine);
    _onDartDetectedCallback = (_, dartScore) {
      if (!mounted) return;
      final g = readGame();
      if (!g.isMyTurn) return;
      final (base, mul) = dartScoreToBackend(dartScore);
      HapticService.mediumImpact();
      DartSoundService.playDartHit(base, mul);
      g.throwDart(baseScore: base, multiplier: mul);
    };
    autoScoringService = AutoScoringService();
    await autoScoringService!.loadModel();
    if (mounted) {
      setState(() => autoScoringLoading = false);
      if (autoScoringService!.modelLoaded) {
        final game = readGame();
        if (game.isMyTurn) {
          autoScoringService!.startCapture(
            captureFrame: _captureFrameCallback!,
            onDartDetected: _onDartDetectedCallback,
          );
        }
      }
    }
  }

  void submitAutoScoredDarts(dynamic game) { autoScoringService?.stopCapture(); game.confirmRound(); }

  // ─── Agora ────────────────────────────────────────────────────────────────────
  Future<void> initializeAgora({required String appId, required String token, required String channelName}) async {
    permissionsGranted = await AgoraService.requestPermissions();
    if (!permissionsGranted) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Camera and microphone permissions are required'), backgroundColor: AppTheme.error));
      return;
    }
    try {
      agoraEngine = await AgoraService.initializeEngine(appId);
      await AgoraService.setBackCamera(agoraEngine!);
      _registerAgoraHandlers();
      await AgoraService.joinChannel(engine: agoraEngine!, token: token, channelName: channelName, uid: 0);
      await initAutoScoring();
    } catch (_) {}
  }

  Future<void> reconnectAgora(dynamic game) async {
    final appId = game.agoraAppId; final token = game.agoraToken; final channelName = game.agoraChannelName;
    if (appId == null || appId.isEmpty || token == null || token.isEmpty || channelName == null || channelName.isEmpty) return;
    try {
      if (agoraEngine != null) { agoraEngine = null; await AgoraService.dispose(); }
      if (!permissionsGranted) { permissionsGranted = await AgoraService.requestPermissions(); if (!permissionsGranted) return; }
      agoraEngine = await AgoraService.initializeEngine(appId);
      await AgoraService.setBackCamera(agoraEngine!);
      _registerAgoraHandlers();
      await AgoraService.joinChannel(engine: agoraEngine!, token: token, channelName: channelName, uid: 0);
      isAudioMuted = true;
      if (autoScoringService != null) { autoScoringService!.stopCapture(); autoScoringService!.dispose(); autoScoringService = null; }
      await initAutoScoring();
    } catch (_) {}
  }

  void _registerAgoraHandlers() {
    agoraEngine!.registerEventHandler(RtcEngineEventHandler(
      onJoinChannelSuccess: (_, _) { if (!mounted) return; readGame().setLocalUserJoined(true); },
      onUserJoined: (_, uid, _) { if (!mounted) return; readGame().setRemoteUser(uid); },
      onUserOffline: (_, uid, _) { if (!mounted) return; readGame().setRemoteUser(null); },
      onLocalVideoStateChanged: (_, state, _) {
        if (state == LocalVideoStreamState.localVideoStreamStateCapturing || state == LocalVideoStreamState.localVideoStreamStateEncoding) initCameraZoom();
      },
    ));
  }

  Future<void> initCameraZoom({int attempt = 0}) async {
    if (agoraEngine == null || !mounted || cameraZoomInitialized) return;
    try {
      final maxZoom = await agoraEngine!.getCameraMaxZoomFactor();
      if (mounted && maxZoom > 1.0) {
        cameraZoomInitialized = true;
        final savedZoom = await StorageService.getCameraZoom();
        final clampedZoom = savedZoom.clamp(1.0, maxZoom.clamp(1.0, 10.0));
        try { await agoraEngine!.setCameraZoomFactor(clampedZoom); } catch (_) {}
        setState(() { cameraMinZoom = 1.0; cameraMaxZoom = maxZoom.clamp(1.0, 10.0); cameraZoom = clampedZoom; });
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
  Future<void> switchCamera() async { if (agoraEngine != null) await AgoraService.switchCamera(agoraEngine!); }
  Future<void> zoomIn() async {
    if (agoraEngine == null) return;
    final next = (cameraZoom + 0.1).clamp(cameraMinZoom, cameraMaxZoom);
    try { await agoraEngine!.setCameraZoomFactor(next); if (mounted) setState(() => cameraZoom = next); } catch (_) {}
  }
  Future<void> zoomOut() async {
    if (agoraEngine == null) return;
    final next = (cameraZoom - 0.1).clamp(cameraMinZoom, cameraMaxZoom);
    try { await agoraEngine!.setCameraZoomFactor(next); if (mounted) setState(() => cameraZoom = next); } catch (_) {}
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
    final result = await showDialog<bool>(
      context: context, barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: AppTheme.error, width: 2)),
        title: Row(children: [const Icon(Icons.warning, color: AppTheme.error, size: 32), const SizedBox(width: 12), Text('Leave Match?', style: AppTheme.titleLarge.copyWith(color: AppTheme.error, fontWeight: FontWeight.bold))]),
        content: Text(leaveWarningText, style: AppTheme.bodyLarge.copyWith(fontSize: 16), textAlign: TextAlign.center),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Stay in Match')),
          ElevatedButton(onPressed: () { leaveMatch(); Navigator.pop(ctx, true); }, style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error), child: const Text('Leave & Forfeit')),
        ],
      ),
    );
    return result ?? false;
  }

  // ─── Shared dialogs ───────────────────────────────────────────────────────────
  void showPendingWinDialog(dynamic game) {
    final notation = (game.pendingData?['finalDart'])?['notation'] ?? 'Unknown';
    winDialogShowing = true;
    showDialog(context: context, barrierDismissible: false, builder: (ctx) => AlertDialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: AppTheme.success, width: 2)),
      title: Row(children: [const Icon(Icons.emoji_events, color: AppTheme.success, size: 32), const SizedBox(width: 12), Text('CHECKOUT!', style: AppTheme.titleLarge.copyWith(color: AppTheme.success, fontWeight: FontWeight.bold))]),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('You hit $notation to finish!', style: AppTheme.bodyLarge.copyWith(fontSize: 16), textAlign: TextAlign.center),
        const SizedBox(height: 8), const Text('Is this correct?', style: TextStyle(color: AppTheme.textSecondary)),
      ]),
      actions: [
        TextButton(onPressed: () { winDialogShowing = false; Navigator.pop(ctx); game.undoLastDart(); }, child: const Text('Edit Darts')),
        ElevatedButton(onPressed: () { winDialogShowing = false; Navigator.pop(ctx); game.confirmWin(); }, style: ElevatedButton.styleFrom(backgroundColor: AppTheme.success), child: const Text('Confirm Win')),
      ],
    )).then((_) => winDialogShowing = false);
  }

  void showPendingBustDialog(dynamic game) {
    bustDialogShowing = true;
    final reasonText = switch (game.pendingReason ?? '') {
      'score_below_zero' => 'Score went below zero',
      'must_finish_double' => 'Must finish on a double',
      'score_one_remaining' => 'Cannot finish from 1',
      _ => 'Invalid throw',
    };
    showDialog(context: context, barrierDismissible: false, builder: (ctx) => AlertDialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: AppTheme.error, width: 2)),
      title: Row(children: [const Icon(Icons.warning, color: AppTheme.error, size: 32), const SizedBox(width: 12), Text('BUST!', style: AppTheme.titleLarge.copyWith(color: AppTheme.error, fontWeight: FontWeight.bold))]),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(reasonText, style: AppTheme.bodyLarge.copyWith(fontSize: 16), textAlign: TextAlign.center),
        const SizedBox(height: 8), const Text('Confirm to pass turn or edit if incorrect', style: TextStyle(color: AppTheme.textSecondary), textAlign: TextAlign.center),
      ]),
      actions: [
        TextButton(onPressed: () { bustDialogShowing = false; Navigator.pop(ctx); game.undoLastDart(); }, child: const Text('Edit Darts')),
        ElevatedButton(onPressed: () { bustDialogShowing = false; Navigator.pop(ctx); game.confirmBust(); }, style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error), child: const Text('Confirm Bust')),
      ],
    )).then((_) => bustDialogShowing = false);
  }

  void showReportDialog({required Future<void> Function(String) onSubmit, required VoidCallback onComplete}) {
    String? selectedReason;
    const reasons = ['Cheating', 'Unsportsmanlike conduct', 'Incorrect score', 'Connection issues', 'Other'];
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setDlg) => AlertDialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: AppTheme.error, width: 2)),
      title: Row(children: [const Icon(Icons.flag, color: AppTheme.error), const SizedBox(width: 12), Text('Report Player', style: AppTheme.titleLarge.copyWith(color: AppTheme.error, fontWeight: FontWeight.bold))]),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Select a reason for reporting:', style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
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
        TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('CANCEL', style: TextStyle(color: AppTheme.textSecondary))),
        ElevatedButton(
          onPressed: selectedReason == null ? null : () async {
            HapticService.mediumImpact(); Navigator.of(ctx).pop();
            final messenger = ScaffoldMessenger.of(context);
            try {
              await onSubmit(selectedReason!);
              if (mounted) messenger.showSnackBar(const SnackBar(content: Text('Dispute submitted'), backgroundColor: AppTheme.success, duration: Duration(seconds: 2)));
            } catch (e) {
              if (mounted) messenger.showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.error, duration: const Duration(seconds: 3)));
            }
            onComplete();
          },
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          child: const Text('SUBMIT REPORT', style: TextStyle(fontWeight: FontWeight.bold)),
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
          Text('PREPARING MATCH', style: AppTheme.titleLarge.copyWith(color: AppTheme.textSecondary, letterSpacing: 3, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('Setting up camera & AI scoring...', style: AppTheme.bodyLarge.copyWith(color: AppTheme.textSecondary)),
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
              AgoraVideoView(
                controller: VideoViewController.remote(
                  rtcEngine: agoraEngine!,
                  canvas: VideoCanvas(uid: game.remoteUid!),
                  connection: RtcConnection(channelId: channelId),
                ),
              )
            else
              Container(
                color: AppTheme.surface,
                child: const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.videocam_off, size: 48, color: AppTheme.textSecondary), SizedBox(height: 8),
                  Text('WAITING...', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontWeight: FontWeight.bold)),
                ])),
              ),
            // ── Red border ──
            Container(decoration: BoxDecoration(border: Border.all(color: AppTheme.error, width: 3), borderRadius: BorderRadius.circular(16))),
            // ── Opponent score — top left ──
            Positioned(top: 12, left: 12, child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(10), border: Border.all(color: AppTheme.error, width: 2)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(opponentUsername.toUpperCase(), style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontWeight: FontWeight.bold)),
                Text('${game.opponentScore}', style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold)),
              ]),
            )),
            // ── Your score — top right ──
            Positioned(top: 12, right: 12, child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.success.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.success, width: 2),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                const Text('YOUR SCORE', style: TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                const SizedBox(height: 2),
                Text('${game.myScore}', style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
              ]),
            )),
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

  Widget buildMediaControls({List<String>? opponentThrows}) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      buildControlButton(icon: isAudioMuted ? Icons.mic_off : Icons.mic, color: isAudioMuted ? AppTheme.error : AppTheme.primary, onTap: toggleAudio),
      const SizedBox(width: 16),
      buildControlButton(icon: Icons.cameraswitch, color: AppTheme.primary, onTap: switchCamera),
      if (autoScoringEnabled && autoScoringService != null && autoScoringService!.modelLoaded) ...[
        const SizedBox(width: 16),
        buildControlButton(
          icon: aiManuallyDisabled ? Icons.smart_toy_outlined : Icons.smart_toy,
          color: aiManuallyDisabled ? AppTheme.textSecondary : AppTheme.success,
          onTap: toggleAiScoring,
        ),
      ],
      if (opponentThrows != null) ...[
        const SizedBox(width: 20),
        ...List.generate(3, (i) {
          final hasThrow = i < opponentThrows.length;
          return Container(
            width: 50,
            margin: const EdgeInsets.only(left: 6),
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: hasThrow ? AppTheme.surface : AppTheme.background,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: hasThrow ? AppTheme.primary.withValues(alpha: 0.4) : AppTheme.surfaceLight.withValues(alpha: 0.2)),
            ),
            child: Text(
              hasThrow ? opponentThrows[i] : '—',
              textAlign: TextAlign.center,
              style: TextStyle(color: hasThrow ? Colors.white : Colors.white24, fontSize: 14, fontWeight: FontWeight.bold),
            ),
          );
        }),
      ],
    ]),
  );

  Widget buildControlButton({required IconData icon, required Color color, required VoidCallback onTap}) {
    return Material(color: Colors.transparent, child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(8), child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(8), border: Border.all(color: color, width: 2)),
      child: Icon(icon, color: color, size: 24),
    )));
  }

  Widget buildMyTurnOverlay(dynamic game) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.surfaceLight.withValues(alpha: 0.95), borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.surfaceLight, width: 2),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            const Text('YOUR SCORE: ', style: TextStyle(color: AppTheme.textSecondary, fontSize: 10, fontWeight: FontWeight.bold)),
            Text('${game.myScore}', style: TextStyle(color: game.myScore <= 170 ? AppTheme.success : AppTheme.primary, fontSize: 22, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            ...List.generate(3, (i) {
              final throws = game.currentRoundThrows;
              final hasThrow = i < throws.length;
              final isNext = i == throws.length;
              final isEditing = editingDartIndex == i;
              return GestureDetector(
                onTap: hasThrow ? () { HapticService.lightImpact(); setState(() => editingDartIndex = isEditing ? null : i); } : null,
                child: Container(
                  width: 36, height: 36, margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    color: isEditing ? AppTheme.error.withValues(alpha: 0.3) : hasThrow ? AppTheme.primary.withValues(alpha: 0.2) : AppTheme.background,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: isEditing ? AppTheme.error : hasThrow ? AppTheme.primary : isNext ? Colors.white24 : Colors.transparent, width: isEditing ? 3 : (hasThrow || isNext ? 2 : 1)),
                  ),
                  child: Center(child: hasThrow
                    ? Text(throws[i], style: TextStyle(color: isEditing ? AppTheme.error : AppTheme.primary, fontSize: 12, fontWeight: FontWeight.bold))
                    : Icon(Icons.adjust, color: isNext ? Colors.white54 : Colors.white10, size: 14)),
                ),
              );
            }),
            Material(color: Colors.transparent, child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () {
                HapticService.mediumImpact();
                final g = readGame();
                if (editingDartIndex != null && editingDartIndex! < g.currentRoundThrows.length) {
                  g.editDartThrow(editingDartIndex!, 0, ScoreMultiplier.single);
                  setState(() => editingDartIndex = null);
                } else { g.throwDart(baseScore: 0, multiplier: ScoreMultiplier.single); }
              },
              child: Container(
                width: 44, height: 36,
                decoration: BoxDecoration(color: AppTheme.background, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppTheme.surfaceLight, width: 2)),
                child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.close, color: Colors.white70, size: 14),
                  Text('MISS', style: TextStyle(color: Colors.white70, fontSize: 7, fontWeight: FontWeight.bold)),
                ]),
              ),
            )),
          ]),
        ]),
      )),
      const SizedBox(width: 10),
      Container(
        width: 90, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.surfaceLight.withValues(alpha: 0.95), borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.surfaceLight, width: 2),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(opponentUsername.toUpperCase(), style: const TextStyle(color: AppTheme.textSecondary, fontSize: 9, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis, maxLines: 1),
          const SizedBox(height: 2),
          Text('${game.opponentScore}', style: const TextStyle(color: AppTheme.primary, fontSize: 22, fontWeight: FontWeight.bold)),
        ]),
      ),
    ]);
  }

  Widget buildOpponentWaitingPanel(dynamic game) {
    return SingleChildScrollView(child: Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const SizedBox(width: 36, height: 36, child: CircularProgressIndicator(color: AppTheme.error, strokeWidth: 2.5)),
      const SizedBox(height: 12),
      Text("OPPONENT'S TURN", style: TextStyle(color: AppTheme.error.withValues(alpha: 0.8), fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 2)),
      const SizedBox(height: 4), const Text("Please wait...", style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        margin: const EdgeInsets.symmetric(horizontal: 40),
        decoration: BoxDecoration(color: AppTheme.error.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10), border: Border.all(color: AppTheme.error.withValues(alpha: 0.5))),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.warning_rounded, color: AppTheme.error, size: 18), SizedBox(width: 8),
          Flexible(child: Text("Do not play during opponent's turn", style: TextStyle(color: AppTheme.error, fontSize: 12, fontWeight: FontWeight.w600))),
        ]),
      ),
    ])));
  }

  Widget buildScoreInputPanel(dynamic game) {
    if (!game.isMyTurn) return buildOpponentWaitingPanel(game);
    return Column(children: [
      Expanded(child: Column(children: [
        const Spacer(flex: 1),
        Expanded(flex: 3, child: Container(
          color: AppTheme.surface,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: InteractiveDartboard(onDartThrow: (score, multiplier) {
            if (editingDartIndex != null && editingDartIndex! < game.currentRoundThrows.length) {
              game.editDartThrow(editingDartIndex!, score, multiplier);
              setState(() => editingDartIndex = null);
            } else { game.throwDart(baseScore: score, multiplier: multiplier); }
          }),
        )),
        if (game.isMyTurn)
          Container(
            padding: const EdgeInsets.all(16),
            color: AppTheme.surface,
            child: SizedBox(
              width: double.infinity, height: 64,
              child: ElevatedButton(
                onPressed: () { HapticService.heavyImpact(); submitAutoScoredDarts(game); },
                style: ElevatedButton.styleFrom(
                  backgroundColor: game.dartsThrown > 0 ? AppTheme.primary : AppTheme.surface,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  side: BorderSide(color: game.dartsThrown > 0 ? AppTheme.primary : AppTheme.surfaceLight, width: 2),
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(game.dartsThrown == 3 ? Icons.check_circle : Icons.send, size: 20),
                  const SizedBox(width: 8),
                  Text(game.dartsThrown == 3 ? 'CONFIRM ROUND' : 'END ROUND EARLY (${game.dartsThrown}/3)', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1)),
                ]),
              ),
            ),
          ),
      ])),
    ]);
  }

  Widget buildGameBody(dynamic game, AuthProvider auth) {
    return Container(color: AppTheme.background, child: Stack(children: [
      Column(children: [
        if (buildExtraHeader(game, auth) != null) buildExtraHeader(game, auth)!,
        if (game.opponentDisconnected)
          Container(
            width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: AppTheme.accent.withValues(alpha: 0.15),
            child: Row(children: [
              const Icon(Icons.wifi_off, color: AppTheme.accent, size: 18), const SizedBox(width: 8),
              Expanded(child: Text('Opponent disconnected — ${formatSeconds(game.disconnectGraceSeconds)} left', style: const TextStyle(color: AppTheme.accent, fontSize: 13, fontWeight: FontWeight.w600))),
            ]),
          ),
        if (!game.isMyTurn)
          Container(height: 240, padding: const EdgeInsets.all(12), child: buildOpponentTurnVideoLayout(game, channelId: game.agoraChannelName ?? '')),
        if (agoraEngine != null && !game.isMyTurn) buildMediaControls(),
        Expanded(flex: 6, child: Container(
          decoration: const BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24)),
            boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, -4))],
          ),
          child: autoScoringEnabled && autoScoringLoading
            ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(color: AppTheme.primary), SizedBox(height: 16), Text('Loading auto-scoring...', style: TextStyle(color: AppTheme.textSecondary, fontSize: 14))]))
            : autoScoringEnabled && !aiManuallyDisabled && autoScoringService != null && autoScoringService!.modelLoaded && (game.isMyTurn || game.pendingConfirmation)
              ? AutoScoreGameView(
                  scoringService: autoScoringService!,
                  onConfirm: () => submitAutoScoredDarts(game),
                  onEndRoundEarly: () => submitAutoScoredDarts(game),
                  pendingConfirmation: game.pendingConfirmation,
                  myScore: game.myScore, opponentScore: game.opponentScore,
                  opponentName: opponentUsername, myName: auth.currentUser?.username ?? 'You',
                  dartsThrown: game.dartsThrown, agoraEngine: agoraEngine, remoteUid: game.remoteUid,
                  isAudioMuted: isAudioMuted, onToggleAudio: toggleAudio, onSwitchCamera: switchCamera,
                  onZoomIn: zoomIn, onZoomOut: zoomOut, currentZoom: cameraZoom, minZoom: cameraMinZoom, maxZoom: cameraMaxZoom,
                  onEditDart: (index, dartScore) => readGame().editDartThrow(index, dartScore.segment == 0 && dartScore.ring != 'miss' ? 25 : dartScore.segment, dartScoreToMultiplier(dartScore)),
                  onToggleAi: toggleAiScoring, aiEnabled: !aiManuallyDisabled,
                )
              : buildScoreInputPanel(game),
        )),
      ]),
      if (game.isMyTurn)
        Positioned(top: 8, left: 12, right: 12, child: buildMyTurnOverlay(game)),
      if (game.isMyTurn && autoScoringEnabled && autoScoringService != null && autoScoringService!.modelLoaded)
        Positioned(
          bottom: 80,
          right: 12,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: toggleAiScoring,
              borderRadius: BorderRadius.circular(28),
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: aiManuallyDisabled ? AppTheme.surface : AppTheme.success.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: aiManuallyDisabled ? AppTheme.textSecondary : AppTheme.success,
                    width: 2,
                  ),
                ),
                child: Icon(
                  aiManuallyDisabled ? Icons.smart_toy_outlined : Icons.smart_toy,
                  color: aiManuallyDisabled ? AppTheme.textSecondary : AppTheme.success,
                  size: 22,
                ),
              ),
            ),
          ),
        ),
      if (editingDartIndex != null && game.isMyTurn)
        Positioned(top: 0, left: 0, right: 0, child: Material(
          elevation: 100, color: AppTheme.error,
          child: SafeArea(bottom: false, child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Row(children: [const Icon(Icons.edit, color: Colors.white, size: 20), const SizedBox(width: 8), Text('Editing Dart ${(editingDartIndex ?? 0) + 1}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))]),
              TextButton(
                onPressed: () => setState(() => editingDartIndex = null),
                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), backgroundColor: Colors.white.withValues(alpha: 0.2)),
                child: const Text('CANCEL', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
              ),
            ]),
          )),
        )),
    ]));
  }
}
 