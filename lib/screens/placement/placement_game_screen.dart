import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../providers/placement_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/game_provider.dart';
import '../../services/auto_scoring_service.dart';
import '../../services/dart_scoring_service.dart';
import '../../utils/dart_sound_service.dart';
import '../../utils/haptic_service.dart';
import '../../utils/app_theme.dart';
import '../../utils/score_converter.dart';
import '../../utils/storage_service.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/auto_score_display.dart';
import '../../widgets/interactive_dartboard.dart';
import '../../widgets/tv_scoreboard.dart';

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
  List<_DartThrow> _currentRoundThrows = [];
  int _scoreBeforeRound = 501;
  bool _isBust = false;
  bool _isWin = false;
  bool _winDialogShowing = false;

  // Auto-scoring (local camera)
  CameraController? _cameraController;
  AutoScoringService? _autoScoringService;
  bool _autoScoringEnabled = false;
  bool _autoScoringLoading = false;
  bool _aiManuallyDisabled = false;
  bool _aiPausedForEdit = false;
  double _cameraZoom = 1.0;
  double _cameraMinZoom = 1.0;
  double _cameraMaxZoom = 1.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WakelockPlus.enable();
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
    _cameraController?.dispose();
    _cameraController = null;
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _stopAiCapture();
    } else if (state == AppLifecycleState.resumed) {
      if (_autoScoringEnabled && !_aiManuallyDisabled && !_gameEnded && !_botTurnInProgress) {
        _startAiCapture();
      }
    }
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

    final enabled = await StorageService.getAutoScoring();
    if (!mounted) return;
    setState(() => _autoScoringEnabled = enabled);
    if (!enabled) return;

    setState(() => _autoScoringLoading = true);

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty || !mounted) { setState(() => _autoScoringLoading = false); return; }
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      _cameraController = CameraController(back, ResolutionPreset.high, enableAudio: false);
      await _cameraController!.initialize();
      if (!mounted) { _cameraController?.dispose(); _cameraController = null; setState(() => _autoScoringLoading = false); return; }

      try {
        final minZoom = await _cameraController!.getMinZoomLevel();
        final maxZoom = await _cameraController!.getMaxZoomLevel();
        final savedZoom = await StorageService.getCameraZoom();
        final clampedZoom = savedZoom.clamp(minZoom, maxZoom);
        await _cameraController!.setZoomLevel(clampedZoom);
        if (mounted) setState(() { _cameraMinZoom = minZoom; _cameraMaxZoom = maxZoom; _cameraZoom = clampedZoom; });
      } catch (e) {
        debugPrint('[PlacementGame] Zoom config failed: $e');
      }

      _autoScoringService = AutoScoringService();
      await _autoScoringService!.loadModel();
      if (!mounted) { setState(() => _autoScoringLoading = false); return; }
      setState(() => _autoScoringLoading = false);
      if (_autoScoringService!.modelLoaded) _startAiCapture();
    } catch (e) {
      if (mounted) setState(() => _autoScoringLoading = false);
    }
  }

  Future<String?> _captureFrame() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return null;
    try {
      final xFile = await _cameraController!.takePicture();
      return xFile.path;
    } catch (_) {
      return null;
    }
  }

  Future<void> _cleanupFile(String path) async {
    try { await File(path).delete(); } catch (_) {}
  }

  void _onDartDetected(int slotIndex, DartScore dartScore) {
    if (!mounted || _botTurnInProgress || _gameEnded) return;
    final (base, mul) = dartScoreToBackend(dartScore);
    HapticService.mediumImpact();
    DartSoundService.playDartHit(base, mul);
    _throwDart(base, mul);
    if (_isWin) {
      _stopAiCapture();
      WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _showWinDialog(); });
    } else if (_isBust) {
      _stopAiCapture();
      WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _showBustDialog(); });
    }
  }

  void _startAiCapture() {
    if (_autoScoringService == null || _aiManuallyDisabled || _aiPausedForEdit) return;
    _autoScoringService!.startCapture(
      captureFrame: _captureFrame,
      cleanupFile: _cleanupFile,
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
    if (_cameraController == null) return;
    final next = (_cameraZoom + 0.1).clamp(_cameraMinZoom, _cameraMaxZoom);
    try { await _cameraController!.setZoomLevel(next); if (mounted) setState(() => _cameraZoom = next); } catch (_) {}
  }

  Future<void> _zoomOut() async {
    if (_cameraController == null) return;
    final next = (_cameraZoom - 0.1).clamp(_cameraMinZoom, _cameraMaxZoom);
    try { await _cameraController!.setZoomLevel(next); if (mounted) setState(() => _cameraZoom = next); } catch (_) {}
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

    if (_isBust) {
      roundScore = 0;
      setState(() {
        _myScore = _scoreBeforeRound;
        _dartsThrown = 0;
        _currentRoundThrows = [];
        _isBust = false;
        _scoreBeforeRound = _myScore;
      });
    } else {
      roundScore = _scoreBeforeRound - _myScore;
      setState(() {
        _dartsThrown = 0;
        _currentRoundThrows = [];
        _scoreBeforeRound = _myScore;
      });
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
    );

    if (success && mounted) {
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
    }
  }

  bool _bustDialogShowing = false;

  void _showBustDialog() {
    if (_bustDialogShowing || !mounted) return;
    _bustDialogShowing = true;
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
          Text('BUST!', style: AppTheme.titleLarge.copyWith(color: AppTheme.error, fontWeight: FontWeight.bold)),
        ]),
        content: const Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Score busted!', style: TextStyle(color: AppTheme.textPrimary, fontSize: 16), textAlign: TextAlign.center),
          SizedBox(height: 8),
          Text('Confirm to pass turn or edit if incorrect', style: TextStyle(color: AppTheme.textSecondary), textAlign: TextAlign.center),
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
            child: const Text('Edit Darts'),
          ),
          ElevatedButton(
            onPressed: () {
              _bustDialogShowing = false;
              Navigator.pop(ctx);
              _confirmRound();
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            child: const Text('Confirm Bust'),
          ),
        ],
      ),
    ).then((_) => _bustDialogShowing = false);
  }

  void _showWinDialog() {
    if (_winDialogShowing || !mounted) return;
    final notation = _currentRoundThrows.isNotEmpty ? _currentRoundThrows.last.notation : '—';
    _winDialogShowing = true;
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
          Text('CHECKOUT!', style: AppTheme.titleLarge.copyWith(color: AppTheme.success, fontWeight: FontWeight.bold)),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('You hit $notation to finish!', style: AppTheme.bodyLarge.copyWith(fontSize: 16), textAlign: TextAlign.center),
          const SizedBox(height: 8),
          const Text('Is this correct?', style: TextStyle(color: AppTheme.textSecondary)),
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
            child: const Text('Edit Darts'),
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
            child: const Text('Confirm Win'),
          ),
        ],
      ),
    ).then((_) => _winDialogShowing = false);
  }

  void _handleGameEnd(String? winnerId) async {
    setState(() {
      _gameEnded = true;
      _winnerId = winnerId;
    });

    if (winnerId == null) {
      DartSoundService.playLose();
    }

    final placement = context.read<PlacementProvider>();
    final result = await placement.completeMatch(winnerId, player1Score: _myScore);

    if (mounted && result != null) {
      await context.read<AuthProvider>().checkAuthStatus();
      if (mounted) {
        Navigator.of(context).pop(result);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final placement = context.watch<PlacementProvider>();
    final auth = context.watch<AuthProvider>();

    if (_gameEnded) {
      final didWin = _winnerId == auth.currentUser?.id;
      return _buildGameEndScreen(didWin);
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
    final botName = 'Bot #${placement.currentBotDifficulty ?? 1}';

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
            _autoScoringEnabled && _autoScoringLoading
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: AppTheme.primary),
                      const SizedBox(height: 16),
                      Text(AppLocalizations.of(context).loadingAutoScoring, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
                    ],
                  ),
                )
              : _autoScoringEnabled && !_aiManuallyDisabled && !_aiPausedForEdit && _autoScoringService != null && _autoScoringService!.modelLoaded && _cameraController != null && _cameraController!.value.isInitialized && !_botTurnInProgress
                ? AutoScoreGameView(
                    scoringService: _autoScoringService!,
                    onConfirm: () { HapticService.heavyImpact(); _confirmRound(); },
                    onEndRoundEarly: () { HapticService.heavyImpact(); _confirmRound(); },
                    pendingConfirmation: _isBust || _isWin,
                    myScore: _myScore,
                    opponentScore: placement.player2Score,
                    opponentName: botName,
                    myName: auth.currentUser?.username ?? 'You',
                    dartsThrown: _dartsThrown,
                    localCameraPreview: SizedBox.expand(
                      child: FittedBox(
                        fit: BoxFit.cover,
                        child: SizedBox(
                          width: _cameraController!.value.previewSize!.height,
                          height: _cameraController!.value.previewSize!.width,
                          child: CameraPreview(_cameraController!),
                        ),
                      ),
                    ),
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
                      }
                    },
                    onToggleAi: _toggleAi,
                    aiEnabled: !_aiManuallyDisabled,
                  )
                : Container(
                    color: AppTheme.background,
                    child: Stack(
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(height: safeTop),
                            // TV Scoreboard
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                              child: TvScoreboard(
                                myScore: _myScore,
                                opponentScore: placement.player2Score,
                                myName: auth.currentUser?.username ?? 'You',
                                opponentName: botName,
                                isMyTurn: !_botTurnInProgress,
                              ),
                            ),
                            // Dart throws indicator (during my turn)
                            if (!_botTurnInProgress)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                                child: Row(
                                  children: [
                                    ...List.generate(3, (index) {
                                      final hasThrow = index < _currentRoundThrows.length;
                                      final isNext = index == _currentRoundThrows.length;
                                      final isEditing = _editingDartIndex == index;
                                      return GestureDetector(
                                        onTap: hasThrow ? () {
                                          HapticService.lightImpact();
                                          setState(() {
                                            _editingDartIndex = isEditing ? null : index;
                                          });
                                        } : null,
                                        child: Container(
                                          width: 52, height: 40, margin: const EdgeInsets.only(right: 8),
                                          decoration: BoxDecoration(
                                            color: isEditing ? AppTheme.error.withValues(alpha: 0.3) : hasThrow ? AppTheme.primary.withValues(alpha: 0.2) : AppTheme.surface,
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(
                                              color: isEditing ? AppTheme.error : hasThrow ? AppTheme.primary : isNext ? Colors.white24 : Colors.transparent,
                                              width: isEditing ? 3 : (hasThrow || isNext ? 2 : 1),
                                            ),
                                          ),
                                          child: Center(
                                            child: hasThrow
                                              ? Text(_currentRoundThrows[index].notation, style: TextStyle(color: isEditing ? AppTheme.error : AppTheme.primary, fontSize: 14, fontWeight: FontWeight.bold))
                                              : Icon(Icons.adjust, color: isNext ? Colors.white54 : Colors.white10, size: 16),
                                          ),
                                        ),
                                      );
                                    }),
                                    const Spacer(),
                                    if (_editingDartIndex != null)
                                      GestureDetector(
                                        onTap: () => setState(() => _editingDartIndex = null),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                          decoration: BoxDecoration(color: AppTheme.error.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                                            const Icon(Icons.edit, color: AppTheme.error, size: 14),
                                            const SizedBox(width: 4),
                                            Text('Dart ${(_editingDartIndex ?? 0) + 1}', style: const TextStyle(color: AppTheme.error, fontSize: 12, fontWeight: FontWeight.bold)),
                                            const SizedBox(width: 6),
                                            const Icon(Icons.close, color: AppTheme.error, size: 14),
                                          ]),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            // Bot turn display
                            if (_botTurnInProgress)
                              Expanded(
                                flex: 55,
                                child: _buildBotTurnDisplay(placement),
                              ),
                            // Controls Area
                            Expanded(
                              flex: _botTurnInProgress ? 38 : 6,
                              child: Container(
                                decoration: const BoxDecoration(
                                  color: AppTheme.surface,
                                  borderRadius: BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24)),
                                  boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, -4))],
                                ),
                                child: _botTurnInProgress
                                  ? _buildWaitingForBot()
                                  : _buildDartboard(),
                              ),
                            ),
                          ],
                        ),
                        // AI toggle button (floating, during my turn)
                        if (!_botTurnInProgress && _autoScoringEnabled && _autoScoringService != null && _autoScoringService!.modelLoaded)
                          Positioned(
                            bottom: 80 + MediaQuery.of(context).viewPadding.bottom,
                            right: 12,
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: _toggleAi,
                                borderRadius: BorderRadius.circular(28),
                                child: Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: _aiManuallyDisabled ? AppTheme.surface : AppTheme.success.withValues(alpha: 0.15),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: _aiManuallyDisabled ? AppTheme.textSecondary : AppTheme.success, width: 2),
                                  ),
                                  child: Icon(
                                    _aiManuallyDisabled ? Icons.smart_toy_outlined : Icons.smart_toy,
                                    color: _aiManuallyDisabled ? AppTheme.textSecondary : AppTheme.success,
                                    size: 22,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

            // Floating back button
            Positioned(
              top: safeTop + 8,
              left: 12,
              child: GestureDetector(
                onTap: () async {
                  final shouldLeave = await _showLeaveDialog();
                  if (shouldLeave && context.mounted) {
                    Navigator.of(context).pop();
                  }
                },
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.arrow_back_ios_new, size: 16, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBotTurnDisplay(PlacementProvider placement) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      color: AppTheme.surface,
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.smart_toy, color: AppTheme.accent, size: 32),
              const SizedBox(width: 12),
              Text(
                'Bot #${placement.currentBotDifficulty ?? 1} is throwing...',
                style: const TextStyle(color: AppTheme.accent, fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              placement.lastBotThrows.length,
              (index) {
                final t = placement.lastBotThrows[index];
                return Container(
                  width: 60,
                  height: 50,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.primary, width: 2),
                  ),
                  child: Center(
                    child: Text(t.notation, style: const TextStyle(color: AppTheme.primary, fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          if (placement.botIsBust)
            Text(AppLocalizations.of(context).bust, style: const TextStyle(color: AppTheme.error, fontSize: 16, fontWeight: FontWeight.bold))
          else if (placement.botIsCheckout)
            Text(AppLocalizations.of(context).checkout, style: const TextStyle(color: AppTheme.success, fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildWaitingForBot() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: AppTheme.accent),
          const SizedBox(height: 16),
          Text(AppLocalizations.of(context).botIsThrowing, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildDartboard() {
    return Column(
      children: [
        const Spacer(flex: 1),
        Expanded(
          flex: 3,
          child: Container(
            color: AppTheme.surface,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: InteractiveDartboard(
              onDartThrow: (baseScore, multiplier) {
                HapticService.mediumImpact();
                _throwDart(baseScore, multiplier);
              },
            ),
          ),
        ),
        // Bottom confirm button
        Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          color: AppTheme.surface,
          child: SafeArea(
            top: false,
            child: SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _dartsThrown > 0
                    ? () {
                        HapticService.heavyImpact();
                        if (_isWin) { _showWinDialog(); } else if (_isBust) { _showBustDialog(); } else { _confirmRound(); }
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isBust
                      ? AppTheme.error
                      : _isWin
                          ? AppTheme.success
                          : AppTheme.primary,
                  disabledBackgroundColor: AppTheme.primary.withValues(alpha: 0.3),
                  foregroundColor: Colors.white,
                  disabledForegroundColor: Colors.white54,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(_isBust ? Icons.replay : _dartsThrown == 3 ? Icons.check_circle : _dartsThrown == 0 ? Icons.sports_esports_outlined : Icons.send, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      _isBust
                          ? AppLocalizations.of(context).bustConfirm
                          : _isWin
                              ? AppLocalizations.of(context).confirmWin
                              : _dartsThrown >= 3
                                  ? 'CONFIRM ROUND'
                                  : 'END ROUND EARLY',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGameEndScreen(bool didWin) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.surfaceGradient),
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: didWin
                        ? AppTheme.success.withValues(alpha: 0.1)
                        : AppTheme.error.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: didWin ? AppTheme.success : AppTheme.error,
                      width: 4,
                    ),
                  ),
                  child: Icon(
                    didWin ? Icons.emoji_events : Icons.sentiment_dissatisfied,
                    color: didWin ? AppTheme.success : AppTheme.error,
                    size: 80,
                  ),
                ),
                const SizedBox(height: 32),
                Text(
                  didWin ? '${AppLocalizations.of(context).victory.toUpperCase()}!' : AppLocalizations.of(context).defeat.toUpperCase(),
                  style: AppTheme.displayLarge.copyWith(
                    color: didWin ? AppTheme.success : AppTheme.error,
                    fontSize: 48,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  didWin
                      ? '${AppLocalizations.of(context).youWon.replaceAll('!', '')} — bot'
                      : '${AppLocalizations.of(context).youLost} — bot',
                  style: AppTheme.bodyLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 48),
                const CircularProgressIndicator(color: AppTheme.primary),
                const SizedBox(height: 16),
                Text(
                  AppLocalizations.of(context).savingResult,
                  style: const TextStyle(color: AppTheme.textSecondary),
                ),
              ],
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
