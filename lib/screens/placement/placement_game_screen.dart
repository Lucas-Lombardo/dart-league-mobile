import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../models/bot_rank.dart';
import '../../models/training.dart';
import '../../providers/placement_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/game_provider.dart';
import '../../services/auto_scoring_service.dart';
import '../../services/camera_frame_service.dart';
import '../../services/dart_scoring_service.dart';
import '../../services/training_service.dart';
import '../../utils/dart_caller_service.dart';
import '../../utils/dart_sound_service.dart';
import '../../utils/haptic_service.dart';
import '../../utils/app_theme.dart';
import '../../utils/orientation_utils.dart';
import '../../utils/score_converter.dart';
import '../../utils/storage_service.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/auto_score_display.dart';
import '../../widgets/game_turn_ui.dart';
import '../../widgets/local_camera_preview.dart';
import '../../widgets/queue_searching_banner.dart';

class PlacementGameScreen extends StatefulWidget {
  const PlacementGameScreen({super.key});

  @override
  State<PlacementGameScreen> createState() => _PlacementGameScreenState();
}

class _PlacementGameScreenState extends State<PlacementGameScreen>
    with WidgetsBindingObserver {
  bool _botTurnInProgress = false;
  bool _gameEnded = false;
  String? _winnerId;
  int? _editingDartIndex;

  // Local scoring state (no sockets)
  int _myScore = 501;
  int _dartsThrown = 0;
  int _totalDartsThrown = 0;
  List<_DartThrow> _currentRoundThrows = [];
  int _scoreBeforeRound = 501;
  bool _isBust = false;
  bool _isWin = false;
  bool _winDialogShowing = false;

  // Per-visit (3-dart) round scores for live & end-of-match averages.
  final List<int> _myRoundScores = [];
  final List<int> _botRoundScores = [];
  int _lastBotScore = 501;

  // Post-match stat screen state (bot-training only).
  bool _statsLoading = false;
  double? _overallBotAverage;
  bool _endIsBotTraining = false;

  // Auto-scoring (local camera)
  CameraFrameService? _cameraService;
  AutoScoringService? _autoScoringService;
  bool _autoScoringEnabled = false;
  bool _autoScoringLoading = false;
  bool _aiManuallyDisabled = false;
  bool _aiPausedForEdit = false;
  bool _switchingCamera = false;
  double _cameraZoom = 1.0;
  double _cameraMinZoom = 1.0;
  double _cameraMaxZoom = 1.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WakelockPlus.enable();
    OrientationUtils.allowAll();
    final provider = context.read<PlacementProvider>();
    _myScore = provider.player1Score;
    _scoreBeforeRound = _myScore;
    _lastBotScore = provider.player2Score;
    _autoScoringService = AutoScoringService();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _initCameraAndAI();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopAiCapture();
    _autoScoringService?.dispose();
    _autoScoringService = null;
    _cameraService?.dispose();
    _cameraService = null;
    WakelockPlus.disable();
    OrientationUtils.portraitOnly();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _stopAiCapture();
      _cameraService?.pause();
    } else if (state == AppLifecycleState.resumed) {
      _cameraService?.resume();
      if (_autoScoringEnabled && !_aiManuallyDisabled && !_gameEnded && !_botTurnInProgress) {
        _startAiCapture();
      }
    }
  }

  double? get _myAverage {
    if (_myRoundScores.isEmpty) return null;
    final total = _myRoundScores.fold<int>(0, (a, b) => a + b);
    return total / _myRoundScores.length;
  }

  double? get _botAverage {
    if (_botRoundScores.isEmpty) return null;
    final total = _botRoundScores.fold<int>(0, (a, b) => a + b);
    return total / _botRoundScores.length;
  }

  int _dartScore(int baseScore, ScoreMultiplier multiplier) {
    switch (multiplier) {
      case ScoreMultiplier.single:
        return baseScore;
      case ScoreMultiplier.double:
        return baseScore * 2;
      case ScoreMultiplier.triple:
        return baseScore * 3;
    }
  }

  // ─── Auto-scoring ──────────────────────────────────────────────────────────

  Future<void> _initCameraAndAI() async {
    if (kIsWeb) return;
    if (!AutoScoringService.isSupported) return;

    if (!mounted) return;
    setState(() {
      _autoScoringEnabled = true;
      _autoScoringLoading = true;
    });

    try {
      final cameraService = CameraFrameService();
      // Solo mode: no Agora. The service runs a continuous image stream and
      // caches the latest frame for AI scoring — no per-cycle start/stop.
      await cameraService.initialize(agoraEngine: null, videoTrackId: null);
      if (!mounted) { await cameraService.dispose(); setState(() => _autoScoringLoading = false); return; }
      if (!cameraService.isInitialized) {
        await cameraService.dispose();
        if (mounted) setState(() => _autoScoringLoading = false);
        return;
      }
      _cameraService = cameraService;

      try {
        final minZoom = await cameraService.getMinZoomLevel();
        final maxZoom = await cameraService.getMaxZoomLevel();
        final savedZoom = await StorageService.getCameraZoom();
        final clampedZoom = savedZoom.clamp(minZoom, maxZoom);
        await cameraService.setZoomLevel(clampedZoom);
        if (mounted) setState(() { _cameraMinZoom = minZoom; _cameraMaxZoom = maxZoom; _cameraZoom = clampedZoom; });
      } catch (e) {
        debugPrint('[PlacementGame] Zoom config failed: $e');
      }

      await _autoScoringService!.loadModel();
      if (!mounted) { setState(() => _autoScoringLoading = false); return; }
      setState(() => _autoScoringLoading = false);
      if (_autoScoringService!.modelLoaded) _startAiCapture();
    } catch (e) {
      if (mounted) setState(() => _autoScoringLoading = false);
    }
  }

  void _onDartDetected(int slotIndex, DartScore dartScore) {
    if (!mounted || _botTurnInProgress || _gameEnded) return;
    final (base, mul) = dartScoreToBackend(dartScore);
    HapticService.mediumImpact();
    DartSoundService.playDartHit(base, mul);

    // Score update for an already-tracked dart (model refined its prediction)
    if (slotIndex < _currentRoundThrows.length) {
      setState(() {
        _currentRoundThrows[slotIndex] = _DartThrow(base, mul);
      });
      _recalculateScore();
    } else {
      _throwDart(base, mul);
    }

    if (_isWin) {
      _stopAiCapture();
      WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _showWinDialog(); });
    } else if (_isBust) {
      _stopAiCapture();
      WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _showBustDialog(); });
    }
  }

  void _startAiCapture() {
    if (_autoScoringService == null || _cameraService == null) return;
    if (_aiManuallyDisabled || _aiPausedForEdit) return;
    final camService = _cameraService!;
    _autoScoringService!.startCapture(
      captureFrame: () => camService.captureFrame(),
      captureRgba: () => camService.captureRgba(),
      captureBgra: () => camService.captureBgra(),
      captureYuv: () => camService.captureYuvPlanes(),
      cleanupFile: (path) async { try { await File(path).delete(); } catch (_) {} },
      onDartDetected: _onDartDetected,
      onAutoConfirm: () { if (mounted) { HapticService.heavyImpact(); _confirmRound(); } },
    );
  }

  void _stopAiCapture() {
    _autoScoringService?.stopCapture();
  }

  void _toggleAi() {
    if (!mounted) return;
    setState(() {
      _aiManuallyDisabled = !_aiManuallyDisabled;
      if (_aiManuallyDisabled) {
        _stopAiCapture();
      } else if (_autoScoringService != null && _autoScoringService!.modelLoaded) {
        _startAiCapture();
      }
    });
  }

  Future<void> _zoomIn() async {
    if (_cameraService == null) return;
    final next = (_cameraZoom + 0.1).clamp(_cameraMinZoom, _cameraMaxZoom);
    try { await _cameraService!.setZoomLevel(next); if (mounted) setState(() => _cameraZoom = next); } catch (_) {}
  }

  Future<void> _zoomOut() async {
    if (_cameraService == null) return;
    final next = (_cameraZoom - 0.1).clamp(_cameraMinZoom, _cameraMaxZoom);
    try { await _cameraService!.setZoomLevel(next); if (mounted) setState(() => _cameraZoom = next); } catch (_) {}
  }

  Future<void> _switchCamera() async {
    final svc = _cameraService;
    if (svc == null || _switchingCamera) return;
    HapticService.lightImpact();
    setState(() => _switchingCamera = true);
    try {
      await svc.switchCamera();
      // Refresh the zoom bounds for the new lens (front cameras often can't zoom).
      try {
        final minZoom = await svc.getMinZoomLevel();
        final maxZoom = await svc.getMaxZoomLevel();
        final clamped = _cameraZoom.clamp(minZoom, maxZoom);
        await svc.setZoomLevel(clamped);
        if (mounted) setState(() { _cameraMinZoom = minZoom; _cameraMaxZoom = maxZoom; _cameraZoom = clamped; });
      } catch (_) {}
    } finally {
      if (mounted) setState(() => _switchingCamera = false);
    }
  }

  // ───────────────────────────────────────────────────────────────────────────

  void _throwDart(int baseScore, ScoreMultiplier multiplier) {
    if (_dartsThrown >= 3 || _botTurnInProgress || _gameEnded || _isBust || _isWin) return;

    // If editing an existing dart, replace it
    if (_editingDartIndex != null && _editingDartIndex! < _currentRoundThrows.length) {
      setState(() {
        _currentRoundThrows[_editingDartIndex!] = _DartThrow(baseScore, multiplier);
        _editingDartIndex = null;
      });
      _recalculateScore();
      return;
    }

    // Play dart hit sound
    DartSoundService.playDartHit(baseScore, multiplier);

    final score = _dartScore(baseScore, multiplier);
    final newScore = _myScore - score;

    // Bust: score goes below 0, equals 1, or hits 0 without a double
    if (newScore < 0 || newScore == 1 || (newScore == 0 && multiplier != ScoreMultiplier.double)) {
      setState(() {
        _isBust = true;
        _currentRoundThrows.add(_DartThrow(baseScore, multiplier));
        _dartsThrown++;
      });
      DartSoundService.playBust();
      return;
    }

    setState(() {
      _myScore = newScore;
      _currentRoundThrows.add(_DartThrow(baseScore, multiplier));
      _dartsThrown++;
    });

    // Check win (checkout on double)
    if (newScore == 0 && multiplier == ScoreMultiplier.double) {
      setState(() => _isWin = true);
      return;
    }

    // Caller: announce the visit total right after the third dart lands.
    // Turns that end early (1–2 darts) are announced from _confirmRound instead.
    if (_dartsThrown == 3) {
      DartCallerService.callScore(_scoreBeforeRound - _myScore);
    }
  }

  void _recalculateScore() {
    int score = _scoreBeforeRound;
    bool bust = false;
    bool win = false;

    for (final dart in _currentRoundThrows) {
      final s = _dartScore(dart.baseScore, dart.multiplier);
      final newScore = score - s;
      if (newScore < 0 || newScore == 1 || (newScore == 0 && dart.multiplier != ScoreMultiplier.double)) {
        bust = true;
        break;
      }
      score = newScore;
      if (score == 0 && dart.multiplier == ScoreMultiplier.double) {
        win = true;
        break;
      }
    }

    setState(() {
      _myScore = bust ? _scoreBeforeRound : score;
      _dartsThrown = _currentRoundThrows.length;
      _isBust = bust;
      _isWin = win;
    });
  }

  void _confirmRound() {
    _stopAiCapture();

    final int roundScore;
    final List<String> roundThrows = _currentRoundThrows.map((t) => t.notation).toList();
    final int dartsThisRound = _currentRoundThrows.length;

    if (_isBust) {
      roundScore = 0;
      setState(() {
        _myScore = _scoreBeforeRound;
        _dartsThrown = 0;
        _totalDartsThrown += dartsThisRound;
        _currentRoundThrows = [];
        _isBust = false;
        _scoreBeforeRound = _myScore;
        _myRoundScores.add(0);
      });
    } else {
      roundScore = _scoreBeforeRound - _myScore;
      setState(() {
        _dartsThrown = 0;
        _totalDartsThrown += dartsThisRound;
        _currentRoundThrows = [];
        _scoreBeforeRound = _myScore;
        _myRoundScores.add(roundScore);
      });
      // Caller: a full 3-dart visit is already announced by _throwDart when the
      // third dart lands. Here we only cover turns ended early (1–2 darts) via
      // "finish turn" or removing darts.
      if (dartsThisRound >= 1 && dartsThisRound < 3) {
        DartCallerService.callScore(roundScore);
      }
    }

    DartSoundService.playTurnFinished();
    _executeBotTurn(playerRoundScore: roundScore, playerRoundThrows: roundThrows);
  }

  Future<void> _executeBotTurn({int? playerRoundScore, List<String>? playerRoundThrows}) async {
    if (_botTurnInProgress || _gameEnded) return;

    setState(() => _botTurnInProgress = true);

    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;

    final placement = context.read<PlacementProvider>();
    final success = await placement.triggerBotTurn(
      playerRoundScore: playerRoundScore,
      playerRoundThrows: playerRoundThrows,
      playerScoreAfterRound: _myScore,
    );

    if (success && mounted) {
      // Bot just played a visit: record its 3-dart score (0 on bust).
      final botRoundScore =
          placement.botIsBust ? 0 : (_lastBotScore - placement.player2Score);
      if (botRoundScore >= 0) {
        setState(() {
          _botRoundScores.add(botRoundScore);
          _lastBotScore = placement.player2Score;
        });
      } else {
        _lastBotScore = placement.player2Score;
      }

      await Future.delayed(const Duration(milliseconds: 1200));

      if (placement.botIsCheckout && placement.player2Score == 0) {
        _handleGameEnd(null);
        return;
      }
    }

    if (mounted) {
      setState(() { _botTurnInProgress = false; _aiManuallyDisabled = false; _aiPausedForEdit = false; });
      _autoScoringService?.resetTurn();
      _startAiCapture();
      DartSoundService.playYourTurn();
      // Caller: announce "you require N" when the player comes to the throw on a
      // finish (no-op otherwise), mirroring the online game screen.
      DartCallerService.callCheckout(_myScore);
    }
  }

  bool _bustDialogShowing = false;

  void _showBustDialog() {
    if (_bustDialogShowing || !mounted) return;
    _bustDialogShowing = true;
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppTheme.error, width: 2),
        ),
        title: Row(children: [
          const Icon(Icons.warning, color: AppTheme.error, size: 32),
          const SizedBox(width: 12),
          Text(l10n.bust, style: AppTheme.titleLarge.copyWith(color: AppTheme.error, fontWeight: FontWeight.bold)),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(l10n.scoreBusted, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 16), textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(l10n.confirmPassOrEdit, style: const TextStyle(color: AppTheme.textSecondary), textAlign: TextAlign.center),
        ]),
        actions: [
          OutlinedButton(
            onPressed: () {
              _bustDialogShowing = false;
              Navigator.pop(ctx);
              setState(() {
                _aiPausedForEdit = true;
                _isBust = false;
                _currentRoundThrows.clear();
                _dartsThrown = 0;
                _myScore = _scoreBeforeRound;
              });
              _autoScoringService?.stopCapture();
              for (int i = 0; i < 3; i++) { _autoScoringService?.clearDart(i); }
            },
            child: Text(l10n.editDarts),
          ),
          ElevatedButton(
            onPressed: () {
              _bustDialogShowing = false;
              Navigator.pop(ctx);
              _confirmRound();
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            child: Text(l10n.confirmBustButton),
          ),
        ],
      ),
    ).then((_) => _bustDialogShowing = false);
  }

  void _showWinDialog() {
    if (_winDialogShowing || !mounted) return;
    final notation = _currentRoundThrows.isNotEmpty ? _currentRoundThrows.last.notation : '—';
    _winDialogShowing = true;
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppTheme.success, width: 2),
        ),
        title: Row(children: [
          const Icon(Icons.emoji_events, color: AppTheme.success, size: 32),
          const SizedBox(width: 12),
          Text(l10n.checkout, style: AppTheme.titleLarge.copyWith(color: AppTheme.success, fontWeight: FontWeight.bold)),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(l10n.youHitToFinish(notation), style: AppTheme.bodyLarge.copyWith(fontSize: 16), textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(l10n.isThisCorrect, style: const TextStyle(color: AppTheme.textSecondary)),
        ]),
        actions: [
          OutlinedButton(
            onPressed: () {
              _winDialogShowing = false;
              Navigator.pop(ctx);
              setState(() {
                _aiPausedForEdit = true;
                _isWin = false;
                _currentRoundThrows.clear();
                _dartsThrown = 0;
                _myScore = _scoreBeforeRound;
              });
              _autoScoringService?.stopCapture();
              for (int i = 0; i < 3; i++) { _autoScoringService?.clearDart(i); }
            },
            child: Text(l10n.editDarts),
          ),
          ElevatedButton(
            onPressed: () {
              _winDialogShowing = false;
              Navigator.pop(ctx);
              final auth = context.read<AuthProvider>();
              DartSoundService.playWin();
              _handleGameEnd(auth.currentUser?.id);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.success),
            child: Text(l10n.confirmWin),
          ),
        ],
      ),
    ).then((_) => _winDialogShowing = false);
  }

  void _handleGameEnd(String? winnerId) async {
    // When the player wins mid-visit, _confirmRound is bypassed — fold the
    // final (unconfirmed) round into our local rounds list so the match
    // average reflects every dart actually thrown.
    if (_currentRoundThrows.isNotEmpty) {
      final roundScore = _scoreBeforeRound - _myScore;
      if (!_isBust && roundScore >= 0) {
        _myRoundScores.add(roundScore);
      } else {
        _myRoundScores.add(0);
      }
    }

    final placement = context.read<PlacementProvider>();
    final auth = context.read<AuthProvider>();
    final wasPlacement = placement.mode == PlacementMode.placement;
    final isBotTraining = placement.mode == PlacementMode.botTraining;

    setState(() {
      _gameEnded = true;
      _winnerId = winnerId;
      _endIsBotTraining = isBotTraining;
      _statsLoading = isBotTraining;
    });

    if (winnerId == null) {
      DartSoundService.playLose();
    }
    // Include any darts in the current (unconfirmed) round — when the player
    // wins mid-visit, _confirmRound is bypassed and those darts haven't been
    // rolled into _totalDartsThrown yet.
    final totalDarts = _totalDartsThrown + _currentRoundThrows.length;
    final matchAverage = _myAverage;
    final result = await placement.completeMatch(
      winnerId,
      player1Score: _myScore,
      currentUserId: auth.currentUser?.id,
      dartsThrown: totalDarts,
      matchPlayerAverage: matchAverage,
    );

    if (!mounted || result == null) return;

    if (wasPlacement) {
      await context.read<AuthProvider>().checkAuthStatus();
      if (mounted) Navigator.of(context).pop(result);
      return;
    }

    if (isBotTraining) {
      // Stay on the end screen and load the historical bot-training average
      // so the player can see both this match's stat and their overall trend.
      try {
        final sessions = await TrainingService.listSessions(
          type: TrainingType.botTraining,
          limit: 50,
        );
        final averages = <double>[];
        for (final s in sessions) {
          final d = s.details;
          if (d == null) continue;
          final a = d['playerAverage'];
          if (a is num && a > 0) averages.add(a.toDouble());
        }
        if (matchAverage != null && matchAverage > 0) {
          averages.add(matchAverage);
        }
        final overall = averages.isEmpty
            ? null
            : averages.reduce((a, b) => a + b) / averages.length;
        if (mounted) {
          setState(() {
            _overallBotAverage = overall;
            _statsLoading = false;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _statsLoading = false);
      }
      return;
    }

    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final placement = context.watch<PlacementProvider>();
    final auth = context.watch<AuthProvider>();

    if (_gameEnded) {
      final didWin = _winnerId == auth.currentUser?.id;
      return _buildGameEndScreen(didWin, isBotTraining: _endIsBotTraining);
    }

    if (placement.currentMatchId == null) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        body: const Center(
          child: CircularProgressIndicator(color: AppTheme.primary),
        ),
      );
    }

    final safeTop = MediaQuery.of(context).padding.top;
    final botName = _botName(context, placement);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldPop = await _showLeaveDialog();
        if (shouldPop && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: Stack(
          children: [
            // Main content
            _autoScoringLoading && !_botTurnInProgress
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
              : !_botTurnInProgress
                ? AutoScoreGameView(
                    scoringService: _autoScoringService!,
                    onConfirm: () {
                      HapticService.heavyImpact();
                      if (_isWin) { _showWinDialog(); } else if (_isBust) { _showBustDialog(); } else { _confirmRound(); }
                    },
                    onEndRoundEarly: () { HapticService.heavyImpact(); _confirmRound(); },
                    pendingConfirmation: _isBust || _isWin,
                    myScore: _myScore,
                    opponentScore: placement.player2Score,
                    opponentName: botName,
                    myName: auth.currentUser?.username ?? 'You',
                    dartsThrown: _dartsThrown,
                    startingScore: placement.startingScore,
                    myAverage: _myAverage,
                    opponentAverage: _botAverage,
                    localCameraPreview: !_switchingCamera && _cameraService?.controller != null && _cameraService!.isInitialized
                        ? LocalCameraPreview(controller: _cameraService!.controller!)
                        : null,
                    onSwitchCamera: _switchCamera,
                    onZoomIn: _zoomIn,
                    onZoomOut: _zoomOut,
                    currentZoom: _cameraZoom,
                    minZoom: _cameraMinZoom,
                    maxZoom: _cameraMaxZoom,
                    onEditDart: (index, dartScore) {
                      final (base, mul) = dartScoreToBackend(dartScore);
                      if (index < _currentRoundThrows.length) {
                        _currentRoundThrows[index] = _DartThrow(base, mul);
                      } else {
                        while (_currentRoundThrows.length < index) {
                          _currentRoundThrows.add(_DartThrow(0, ScoreMultiplier.single));
                        }
                        _currentRoundThrows.add(_DartThrow(base, mul));
                      }
                      _recalculateScore();
                      if (_isWin) {
                        _stopAiCapture();
                        WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _showWinDialog(); });
                      } else if (_isBust) {
                        _stopAiCapture();
                        WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _showBustDialog(); });
                      } else {
                        // Why: the dart edit modal stops capture so detections
                        // don't overwrite the manual correction. In ranked,
                        // capture restarts via the GameProvider listener; bot
                        // training has no such listener, so restart explicitly
                        // — otherwise removal detection can't auto-end the turn.
                        _startAiCapture();
                      }
                    },
                    onToggleAi: _autoScoringService!.modelLoaded ? _toggleAi : null,
                    aiEnabled: !_aiManuallyDisabled,
                    onBack: () async {
                      final shouldLeave = await _showLeaveDialog();
                      if (shouldLeave && context.mounted) Navigator.of(context).pop();
                    },
                  )
                // Bot's turn
                : _buildBotTurnScreen(placement, auth, botName, safeTop),

            // "Still searching" pill when this bot training was launched while
            // queued — the player is pulled into the match automatically when
            // an opponent is found (see MatchmakingNavigationGate). Sits a row
            // below the in-camera top controls so it never overlaps them, and
            // uses a high-contrast gold style to stay readable over the
            // camera feed.
            Positioned(
              top: safeTop + 52,
              left: 0,
              right: 0,
              child: const Center(child: QueueSearchingBanner()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBotTurnScreen(
    PlacementProvider placement,
    AuthProvider auth,
    String botName,
    double safeTop,
  ) {
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    final safeBottom = MediaQuery.of(context).padding.bottom;

    final header = TurnScoreHeader(
      myName: auth.currentUser?.username ?? 'You',
      opponentName: botName,
      myScore: _myScore,
      opponentScore: placement.player2Score,
      roundNumber: _botRoundScores.length + 1,
      myAverage: _myAverage,
      opponentAverage: _botAverage,
      leading: GameControlButton(
        icon: Icons.arrow_back_ios_new,
        color: AppTheme.textSecondary,
        onTap: () async {
          final shouldLeave = await _showLeaveDialog();
          if (shouldLeave && mounted) Navigator.of(context).pop();
        },
      ),
    );

    final botPanel = _buildBotPanel(placement);
    final visitSection = _buildBotVisitSection(placement, botName);

    if (isLandscape) {
      return Container(
        color: AppTheme.gameBackground,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: safeTop),
            Expanded(
              child: Row(children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
                    child: botPanel,
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(6, 8, 12, 8),
                    child: Column(children: [
                      header,
                      const SizedBox(height: 8),
                      Expanded(child: SingleChildScrollView(child: visitSection)),
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
          const SizedBox(height: 6),
          header,
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SizedBox(
              height: gameCameraHeight(context),
              child: botPanel,
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: visitSection,
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

  /// Center panel for the bot's turn — same pink frame and size as the
  /// opponent camera, showing the bot throw animation instead of a live feed:
  /// robot + spinner while the bot "aims", then the visit total as a big
  /// glow with a BUST/CHECKOUT verdict when the throws land.
  Widget _buildBotPanel(PlacementProvider placement) {
    final l10n = AppLocalizations.of(context);
    final throws = placement.lastBotThrows;
    final hasThrown = throws.isNotEmpty;
    final visitTotal =
        throws.fold<int>(0, (sum, t) => sum + notationPoints(t.notation));
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(color: AppTheme.gamePanelEmpty),
          Center(
            child: hasThrown
                ? Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(
                      l10n.plusPts(placement.botIsBust ? 0 : visitTotal),
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 64,
                        fontWeight: FontWeight.w900,
                        height: 1,
                        shadows: [
                          Shadow(
                            color: AppTheme.opponentPink.withValues(alpha: 0.9),
                            blurRadius: 36,
                          ),
                          Shadow(
                            color: AppTheme.opponentPink.withValues(alpha: 0.6),
                            blurRadius: 70,
                          ),
                        ],
                      ),
                    ),
                    if (placement.botIsBust || placement.botIsCheckout) ...[
                      const SizedBox(height: 12),
                      Text(
                        placement.botIsBust ? l10n.bust.toUpperCase() : l10n.checkout.toUpperCase(),
                        style: TextStyle(
                          color: placement.botIsBust
                              ? AppTheme.opponentPinkBright
                              : AppTheme.success,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2.5,
                        ),
                      ),
                    ],
                  ])
                : Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(
                      Icons.smart_toy,
                      size: 56,
                      color: AppTheme.opponentPinkBright.withValues(alpha: 0.9),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _botIsThrowingLabel(context, placement),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppTheme.opponentPinkBright,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        color: AppTheme.opponentPink,
                        strokeWidth: 2,
                      ),
                    ),
                  ]),
          ),
          // Pink frame, mirroring the opponent camera border.
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: AppTheme.opponentPink, width: 2),
              borderRadius: BorderRadius.circular(22),
            ),
          ),
          // "BOT" pill where the live badge sits during online matches.
          Positioned(
            top: 12,
            left: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppTheme.opponentPink,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.smart_toy, size: 12, color: Colors.white),
                SizedBox(width: 6),
                Text(
                  'BOT',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  /// "VOLÉE DE (bot) … TOTAL n" + the three visit chips, mirroring the
  /// opponent-turn visit section.
  Widget _buildBotVisitSection(PlacementProvider placement, String botName) {
    final l10n = AppLocalizations.of(context);
    final throws = placement.lastBotThrows;
    final total =
        throws.fold<int>(0, (sum, t) => sum + notationPoints(t.notation));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(children: [
          Expanded(
            child: Text(
              l10n.visitOf(botName.toUpperCase()),
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
              final notation = i < throws.length ? throws[i].notation : null;
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

  Widget _buildGameEndScreen(bool didWin, {bool isBotTraining = false}) {
    final l10n = AppLocalizations.of(context);
    final color = didWin ? AppTheme.success : AppTheme.error;
    final match = _myAverage;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.surfaceGradient),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                      border: Border.all(color: color, width: 4),
                    ),
                    child: Icon(
                      didWin ? Icons.emoji_events : Icons.sentiment_dissatisfied,
                      color: color,
                      size: 80,
                    ),
                  ),
                  const SizedBox(height: 32),
                  Text(
                    didWin
                        ? '${l10n.victory.toUpperCase()}!'
                        : l10n.defeat.toUpperCase(),
                    style: AppTheme.displayLarge.copyWith(
                      color: color,
                      fontSize: 48,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    didWin
                        ? '${l10n.youWon.replaceAll('!', '')} — bot'
                        : '${l10n.youLost} — bot',
                    style: AppTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  if (!isBotTraining) ...[
                    const CircularProgressIndicator(color: AppTheme.primary),
                    const SizedBox(height: 16),
                    Text(
                      l10n.savingResult,
                      style: const TextStyle(color: AppTheme.textSecondary),
                    ),
                  ] else ...[
                    _StatRow(
                      label: l10n.matchAverageLabel,
                      value: match != null && match > 0
                          ? l10n.matchAverageValue(match.toStringAsFixed(1))
                          : '—',
                      color: AppTheme.primary,
                      icon: Icons.timeline,
                    ),
                    const SizedBox(height: 12),
                    _StatRow(
                      label: l10n.overallBotAverageLabel,
                      value: _statsLoading
                          ? '…'
                          : (_overallBotAverage != null &&
                                  _overallBotAverage! > 0
                              ? l10n.overallBotAverageValue(
                                  _overallBotAverage!.toStringAsFixed(1))
                              : '—'),
                      color: AppTheme.accent,
                      icon: Icons.equalizer,
                    ),
                    const SizedBox(height: 32),
                    ElevatedButton(
                      onPressed: _statsLoading
                          ? null
                          : () => Navigator.of(context).pop({
                                'botTraining': true,
                                'won': didWin,
                              }),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 32, vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(
                        l10n.continueButton,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<bool> _showLeaveDialog() async {
    final shouldLeave = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppTheme.error, width: 2),
        ),
        title: Row(
          children: [
            const Icon(Icons.warning, color: AppTheme.error, size: 32),
            const SizedBox(width: 12),
            Text(
              AppLocalizations.of(context).leaveMatch,
              style: AppTheme.titleLarge.copyWith(
                color: AppTheme.error,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Text(
          AppLocalizations.of(context).leaveMatchWarning,
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(AppLocalizations.of(context).stay),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogContext, true);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            child: Text(AppLocalizations.of(context).leave),
          ),
        ],
      ),
    );
    return shouldLeave ?? false;
  }
}

String _botName(BuildContext context, PlacementProvider placement) {
  final l10n = AppLocalizations.of(context);
  if (placement.mode == PlacementMode.botTraining && placement.botRank != null) {
    return l10n.botRankBotName(_rankLabel(l10n, placement.botRank!));
  }
  return l10n.botName(placement.currentBotDifficulty ?? 1);
}

String _botIsThrowingLabel(BuildContext context, PlacementProvider placement) {
  final l10n = AppLocalizations.of(context);
  if (placement.mode == PlacementMode.botTraining && placement.botRank != null) {
    return l10n.botRankIsThrowing(_rankLabel(l10n, placement.botRank!));
  }
  return l10n.botNameIsThrowing(placement.currentBotDifficulty ?? 1);
}

String _rankLabel(AppLocalizations l10n, BotRank rank) {
  switch (rank) {
    case BotRank.bronze:
      return l10n.rankBronze;
    case BotRank.silver:
      return l10n.rankSilver;
    case BotRank.gold:
      return l10n.rankGold;
    case BotRank.platinum:
      return l10n.rankPlatinum;
    case BotRank.diamond:
      return l10n.rankDiamond;
    case BotRank.pro:
      return l10n.rankPro;
    case BotRank.master:
      return l10n.rankMaster;
  }
}

class _DartThrow {
  final int baseScore;
  final ScoreMultiplier multiplier;

  _DartThrow(this.baseScore, this.multiplier);

  String get notation {
    switch (multiplier) {
      case ScoreMultiplier.single:
        return 'S$baseScore';
      case ScoreMultiplier.double:
        return 'D$baseScore';
      case ScoreMultiplier.triple:
        return 'T$baseScore';
    }
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  const _StatRow({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 320,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 1.5),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
