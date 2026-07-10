import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../l10n/app_localizations.dart';
import '../../models/local_match_config.dart';
import '../../providers/game_provider.dart' show ScoreMultiplier;
import '../../services/auto_scoring_service.dart';
import '../../services/camera_frame_service.dart';
import '../../services/dart_scoring_service.dart';
import '../../utils/app_theme.dart';
import '../../utils/dart_sound_service.dart';
import '../../utils/haptic_service.dart';
import '../../utils/orientation_utils.dart';
import '../../utils/score_converter.dart';
import '../../utils/storage_service.dart';
import '../../widgets/auto_score_display.dart';
import '../../widgets/local_camera_preview.dart';

/// Local (hot-seat) 1v1 match: two players share one device, alternating turns
/// in front of the camera. Fully client-side — no sockets, no API, no stats,
/// nothing persisted. The X01 scoring logic mirrors the bot-training screen but
/// the "opponent's turn" is simply a hand-the-phone-over step.
class LocalMatchScreen extends StatefulWidget {
  final LocalMatchConfig config;

  const LocalMatchScreen({super.key, required this.config});

  @override
  State<LocalMatchScreen> createState() => _LocalMatchScreenState();
}

class _LocalMatchScreenState extends State<LocalMatchScreen>
    with WidgetsBindingObserver {
  // ── Match state ──────────────────────────────────────────────────────────
  late final List<int> _scores; // [player0, player1]
  final List<int> _legsWon = [0, 0];
  int _activePlayer = 0; // who is throwing now
  int _legStarter = 0; // who threw first in the current leg (alternates)
  int _legNumber = 1;
  bool _gameEnded = false;
  int? _matchWinner;

  // Transient "it's X's turn" banner shown briefly when the turn auto-switches.
  // The phone stays mounted — turns pass hands-free, no interstitial.
  String? _turnBannerName;
  Timer? _turnBannerTimer;

  // ── Current visit (active player) ──
  int _dartsThrown = 0;
  List<_LocalDart> _currentRoundThrows = [];
  late int _scoreBeforeRound;
  bool _isBust = false;
  bool _isWin = false;
  bool _winDialogShowing = false;
  bool _bustDialogShowing = false;
  int? _editingDartIndex;

  // Per-player visit scores, for live & end-of-match 3-dart averages.
  final List<List<int>> _roundScores = [[], []];

  // ── Auto-scoring (local camera) ──
  CameraFrameService? _cameraService;
  AutoScoringService? _autoScoringService;
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
    _scores = [widget.config.startingScore, widget.config.startingScore];
    _scoreBeforeRound = widget.config.startingScore;
    _autoScoringService = AutoScoringService();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _initCameraAndAI();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _turnBannerTimer?.cancel();
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
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _stopAiCapture();
      _cameraService?.pause();
    } else if (state == AppLifecycleState.resumed) {
      _cameraService?.resume();
      if (!_aiManuallyDisabled && !_gameEnded) {
        _startAiCapture();
      }
    }
  }

  LocalMatchConfig get _config => widget.config;
  int get _opponent => 1 - _activePlayer;

  double? _averageOf(int player) {
    final rs = _roundScores[player];
    if (rs.isEmpty) return null;
    return rs.fold<int>(0, (a, b) => a + b) / rs.length;
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

  // ── X01 rule helpers (honour the double-out toggle) ──────────────────────

  bool _isBustResult(int newScore, ScoreMultiplier multiplier) {
    if (newScore < 0) return true;
    if (_config.doubleOut) {
      return newScore == 1 ||
          (newScore == 0 && multiplier != ScoreMultiplier.double);
    }
    return false;
  }

  bool _isWinResult(int newScore, ScoreMultiplier multiplier) {
    if (newScore != 0) return false;
    return _config.doubleOut ? multiplier == ScoreMultiplier.double : true;
  }

  // ── Auto-scoring ──────────────────────────────────────────────────────────

  Future<void> _initCameraAndAI() async {
    if (kIsWeb || !AutoScoringService.isSupported) return;
    if (!mounted) return;
    setState(() => _autoScoringLoading = true);

    try {
      final cameraService = CameraFrameService();
      await cameraService.initialize(agoraEngine: null, videoTrackId: null);
      if (!mounted) {
        await cameraService.dispose();
        return;
      }
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
        if (mounted) {
          setState(() {
            _cameraMinZoom = minZoom;
            _cameraMaxZoom = maxZoom;
            _cameraZoom = clampedZoom;
          });
        }
      } catch (e) {
        debugPrint('[LocalMatch] Zoom config failed: $e');
      }

      await _autoScoringService!.loadModel();
      if (!mounted) return;
      setState(() => _autoScoringLoading = false);
      if (_autoScoringService!.modelLoaded) {
        _startAiCapture();
        _showTurnBanner(_config.nameOf(_activePlayer));
      }
    } catch (e) {
      if (mounted) setState(() => _autoScoringLoading = false);
    }
  }

  void _onDartDetected(int slotIndex, DartScore dartScore) {
    if (!mounted || _gameEnded) return;
    final (base, mul) = dartScoreToBackend(dartScore);
    HapticService.mediumImpact();
    DartSoundService.playDartHit(base, mul);

    if (slotIndex < _currentRoundThrows.length) {
      setState(() => _currentRoundThrows[slotIndex] = _LocalDart(base, mul));
      _recalculateScore();
    } else {
      _throwDart(base, mul);
    }

    if (_isWin) {
      _stopAiCapture();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showWinDialog();
      });
    } else if (_isBust) {
      _stopAiCapture();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showBustDialog();
      });
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
      cleanupFile: (path) async {
        try {
          await File(path).delete();
        } catch (_) {}
      },
      onDartDetected: _onDartDetected,
      onAutoConfirm: () {
        if (mounted) {
          HapticService.heavyImpact();
          _confirmRound();
        }
      },
    );
  }

  void _stopAiCapture() => _autoScoringService?.stopCapture();

  void _toggleAi() {
    if (!mounted) return;
    setState(() {
      _aiManuallyDisabled = !_aiManuallyDisabled;
      if (_aiManuallyDisabled) {
        _stopAiCapture();
      } else if (_autoScoringService?.modelLoaded ?? false) {
        _startAiCapture();
      }
    });
  }

  Future<void> _zoomIn() async {
    if (_cameraService == null) return;
    final next = (_cameraZoom + 0.1).clamp(_cameraMinZoom, _cameraMaxZoom);
    try {
      await _cameraService!.setZoomLevel(next);
      if (mounted) setState(() => _cameraZoom = next);
    } catch (_) {}
  }

  Future<void> _zoomOut() async {
    if (_cameraService == null) return;
    final next = (_cameraZoom - 0.1).clamp(_cameraMinZoom, _cameraMaxZoom);
    try {
      await _cameraService!.setZoomLevel(next);
      if (mounted) setState(() => _cameraZoom = next);
    } catch (_) {}
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
        if (mounted) {
          setState(() {
            _cameraMinZoom = minZoom;
            _cameraMaxZoom = maxZoom;
            _cameraZoom = clamped;
          });
        }
      } catch (_) {}
    } finally {
      if (mounted) setState(() => _switchingCamera = false);
    }
  }

  // ── Scoring ────────────────────────────────────────────────────────────────

  void _throwDart(int baseScore, ScoreMultiplier multiplier) {
    if (_dartsThrown >= 3 || _gameEnded || _isBust || _isWin) {
      return;
    }

    if (_editingDartIndex != null &&
        _editingDartIndex! < _currentRoundThrows.length) {
      setState(() {
        _currentRoundThrows[_editingDartIndex!] =
            _LocalDart(baseScore, multiplier);
        _editingDartIndex = null;
      });
      _recalculateScore();
      return;
    }

    DartSoundService.playDartHit(baseScore, multiplier);
    final score = _dartScore(baseScore, multiplier);
    final newScore = _scores[_activePlayer] - score;

    if (_isBustResult(newScore, multiplier)) {
      setState(() {
        _isBust = true;
        _currentRoundThrows.add(_LocalDart(baseScore, multiplier));
        _dartsThrown++;
      });
      DartSoundService.playBust();
      return;
    }

    setState(() {
      _scores[_activePlayer] = newScore;
      _currentRoundThrows.add(_LocalDart(baseScore, multiplier));
      _dartsThrown++;
    });

    if (_isWinResult(newScore, multiplier)) {
      setState(() => _isWin = true);
    }
  }

  void _recalculateScore() {
    int score = _scoreBeforeRound;
    bool bust = false;
    bool win = false;

    for (final dart in _currentRoundThrows) {
      final newScore = score - _dartScore(dart.baseScore, dart.multiplier);
      if (_isBustResult(newScore, dart.multiplier)) {
        bust = true;
        break;
      }
      score = newScore;
      if (_isWinResult(newScore, dart.multiplier)) {
        win = true;
        break;
      }
    }

    setState(() {
      _scores[_activePlayer] = bust ? _scoreBeforeRound : score;
      _dartsThrown = _currentRoundThrows.length;
      _isBust = bust;
      _isWin = win;
    });
  }

  /// Finalise the active player's visit and pass to the opponent automatically.
  /// No interstitial — the phone stays mounted; the AI scores the next player.
  void _confirmRound() {
    if (_gameEnded) return;
    _stopAiCapture();

    if (_isBust) {
      _scores[_activePlayer] = _scoreBeforeRound;
      _roundScores[_activePlayer].add(0);
    } else {
      _roundScores[_activePlayer].add(_scoreBeforeRound - _scores[_activePlayer]);
    }

    DartSoundService.playTurnFinished();
    _switchToPlayer(_opponent);
  }

  /// Switch the active thrower and resume auto-scoring for them — hands-free.
  void _switchToPlayer(int next) {
    setState(() {
      _activePlayer = next;
      _scoreBeforeRound = _scores[next];
      _currentRoundThrows = [];
      _dartsThrown = 0;
      _isBust = false;
      _isWin = false;
      _editingDartIndex = null;
      _aiManuallyDisabled = false;
      _aiPausedForEdit = false;
    });
    _autoScoringService?.resetTurn();
    _startAiCapture();
    DartSoundService.playYourTurn();
    _showTurnBanner(_config.nameOf(next));
  }

  void _showTurnBanner(String name) {
    _turnBannerTimer?.cancel();
    setState(() => _turnBannerName = name);
    _turnBannerTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _turnBannerName = null);
    });
  }

  void _handleLegWon(int winner) {
    // Fold the final (unconfirmed) visit into the average before resetting.
    if (_currentRoundThrows.isNotEmpty && !_isBust) {
      final rs = _scoreBeforeRound - _scores[winner];
      if (rs >= 0) _roundScores[winner].add(rs);
    }
    _stopAiCapture();
    DartSoundService.playWin();
    setState(() => _legsWon[winner]++);

    if (_legsWon[winner] >= _config.legsToWin) {
      setState(() {
        _gameEnded = true;
        _matchWinner = winner;
      });
    } else {
      _startNextLeg();
    }
  }

  void _startNextLeg() {
    // The player who didn't start the previous leg throws first.
    _legStarter = 1 - _legStarter;
    _legNumber++;
    _scores[0] = _config.startingScore;
    _scores[1] = _config.startingScore;
    _switchToPlayer(_legStarter);
  }

  void _rematch() {
    setState(() {
      _gameEnded = false;
      _matchWinner = null;
      _legsWon[0] = 0;
      _legsWon[1] = 0;
      _legNumber = 1;
      _legStarter = 0;
      _activePlayer = 0;
      _scores[0] = _config.startingScore;
      _scores[1] = _config.startingScore;
      _scoreBeforeRound = _config.startingScore;
      _roundScores[0].clear();
      _roundScores[1].clear();
      _currentRoundThrows = [];
      _dartsThrown = 0;
      _isBust = false;
      _isWin = false;
      _aiManuallyDisabled = false;
      _aiPausedForEdit = false;
      _editingDartIndex = null;
    });
    _autoScoringService?.resetTurn();
    _startAiCapture();
    _showTurnBanner(_config.nameOf(_activePlayer));
  }

  // ── Dialogs ────────────────────────────────────────────────────────────────

  void _showBustDialog() {
    if (_bustDialogShowing || !mounted) return;
    _bustDialogShowing = true;
    final l10n = AppLocalizations.of(context);
    showDialog<void>(
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
          Text(l10n.bust,
              style: AppTheme.titleLarge
                  .copyWith(color: AppTheme.error, fontWeight: FontWeight.bold)),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(l10n.scoreBusted,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 16),
              textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(l10n.confirmPassOrEdit,
              style: const TextStyle(color: AppTheme.textSecondary),
              textAlign: TextAlign.center),
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
                _scores[_activePlayer] = _scoreBeforeRound;
              });
              _autoScoringService?.stopCapture();
              for (int i = 0; i < 3; i++) {
                _autoScoringService?.clearDart(i);
              }
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
    final notation =
        _currentRoundThrows.isNotEmpty ? _currentRoundThrows.last.notation : '—';
    _winDialogShowing = true;
    final l10n = AppLocalizations.of(context);
    showDialog<void>(
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
          Text(l10n.checkout,
              style: AppTheme.titleLarge.copyWith(
                  color: AppTheme.success, fontWeight: FontWeight.bold)),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(l10n.youHitToFinish(notation),
              style: AppTheme.bodyLarge.copyWith(fontSize: 16),
              textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(l10n.isThisCorrect,
              style: const TextStyle(color: AppTheme.textSecondary)),
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
                _scores[_activePlayer] = _scoreBeforeRound;
              });
              _autoScoringService?.stopCapture();
              for (int i = 0; i < 3; i++) {
                _autoScoringService?.clearDart(i);
              }
            },
            child: Text(l10n.editDarts),
          ),
          ElevatedButton(
            onPressed: () {
              _winDialogShowing = false;
              Navigator.pop(ctx);
              _handleLegWon(_activePlayer);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.success),
            child: Text(l10n.confirmWin),
          ),
        ],
      ),
    ).then((_) => _winDialogShowing = false);
  }

  Future<bool> _showLeaveDialog() async {
    final l10n = AppLocalizations.of(context);
    final shouldLeave = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppTheme.error, width: 2),
        ),
        title: Row(children: [
          const Icon(Icons.warning, color: AppTheme.error, size: 32),
          const SizedBox(width: 12),
          Text(l10n.leaveMatch,
              style: AppTheme.titleLarge
                  .copyWith(color: AppTheme.error, fontWeight: FontWeight.bold)),
        ]),
        content: Text(l10n.leaveMatchWarning,
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.stay),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            child: Text(l10n.leave),
          ),
        ],
      ),
    );
    return shouldLeave ?? false;
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_gameEnded) return _buildEndScreen();

    final safeTop = MediaQuery.of(context).padding.top;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldPop = await _showLeaveDialog();
        if (shouldPop && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: Stack(
          children: [
            if (_autoScoringLoading) _buildLoading() else _buildTurnView(),

            // Top-center status: a transient "it's X's turn" banner right after
            // an auto-switch, otherwise a compact leg-score indicator.
            _buildTopStatus(safeTop),
          ],
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return Container(
      color: AppTheme.background,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: AppTheme.primary),
            const SizedBox(height: 16),
            Text(AppLocalizations.of(context).loadingAutoScoring,
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 14)),
          ],
        ),
      ),
    );
  }

  Widget _buildTurnView() {
    return AutoScoreGameView(
      scoringService: _autoScoringService!,
      onConfirm: () {
        HapticService.heavyImpact();
        if (_isWin) {
          _showWinDialog();
        } else if (_isBust) {
          _showBustDialog();
        } else {
          _confirmRound();
        }
      },
      onEndRoundEarly: () {
        HapticService.heavyImpact();
        _confirmRound();
      },
      pendingConfirmation: _isBust || _isWin,
      myScore: _scores[_activePlayer],
      opponentScore: _scores[_opponent],
      myName: _config.nameOf(_activePlayer),
      opponentName: _config.nameOf(_opponent),
      dartsThrown: _dartsThrown,
      startingScore: _config.startingScore,
      iAmPlayer2: _activePlayer == 1,
      myAverage: _averageOf(_activePlayer),
      opponentAverage: _averageOf(_opponent),
      localCameraPreview: !_switchingCamera &&
              _cameraService?.controller != null &&
              _cameraService!.isInitialized
          ? LocalCameraPreview(controller: _cameraService!.controller!)
          : null,
      onBack: () async {
        final shouldLeave = await _showLeaveDialog();
        if (shouldLeave && mounted) Navigator.of(context).pop();
      },
      onSwitchCamera: _switchCamera,
      onZoomIn: _zoomIn,
      onZoomOut: _zoomOut,
      currentZoom: _cameraZoom,
      minZoom: _cameraMinZoom,
      maxZoom: _cameraMaxZoom,
      onEditDart: (index, dartScore) {
        final (base, mul) = dartScoreToBackend(dartScore);
        if (index < _currentRoundThrows.length) {
          _currentRoundThrows[index] = _LocalDart(base, mul);
        } else {
          while (_currentRoundThrows.length < index) {
            _currentRoundThrows.add(_LocalDart(0, ScoreMultiplier.single));
          }
          _currentRoundThrows.add(_LocalDart(base, mul));
        }
        _recalculateScore();
        if (_isWin) {
          _stopAiCapture();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _showWinDialog();
          });
        } else if (_isBust) {
          _stopAiCapture();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _showBustDialog();
          });
        } else {
          _startAiCapture();
        }
      },
      onToggleAi: (_autoScoringService?.modelLoaded ?? false) ? _toggleAi : null,
      aiEnabled: !_aiManuallyDisabled,
    );
  }

  /// Top-center overlay: turn-change banner if one is active, else a compact
  /// leg-score indicator (only for multi-leg matches). Sits below the back
  /// button / end-turn pill so it never overlaps them.
  Widget _buildTopStatus(double safeTop) {
    if (_turnBannerName != null) return _buildTurnBanner(safeTop);
    if (_config.bestOf == 1 || _autoScoringLoading) {
      return const SizedBox.shrink();
    }
    return _buildLegIndicator(safeTop);
  }

  Widget _buildTurnBanner(double safeTop) {
    final l10n = AppLocalizations.of(context);
    return Positioned(
      top: safeTop + 52,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            builder: (context, t, child) => Opacity(
              opacity: t,
              child: Transform.scale(scale: 0.92 + 0.08 * t, child: child),
            ),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                gradient: AppTheme.primaryGradient,
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primary.withValues(alpha: 0.5),
                    blurRadius: 18,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.sports_esports,
                      color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  Text(
                    l10n.turnOf(_turnBannerName!).toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
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

  Widget _buildLegIndicator(double safeTop) {
    final l10n = AppLocalizations.of(context);
    return Positioned(
      top: safeTop + 52,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
            ),
            child: Text(
              '${l10n.legNumber(_legNumber)}  ·  ${_legsWon[0]}–${_legsWon[1]}',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEndScreen() {
    final l10n = AppLocalizations.of(context);
    final winner = _matchWinner ?? 0;
    final winnerName = _config.nameOf(winner);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.surfaceGradient),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: AppTheme.success.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                      border: Border.all(color: AppTheme.success, width: 4),
                    ),
                    child: const Icon(Icons.emoji_events,
                        color: AppTheme.success, size: 80),
                  ),
                  const SizedBox(height: 32),
                  Text(
                    '${l10n.victory.toUpperCase()}!',
                    style: AppTheme.displayLarge
                        .copyWith(color: AppTheme.success, fontSize: 44),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.localMatchWinner(winnerName),
                    style: AppTheme.bodyLarge.copyWith(color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${_config.nameOf(0)}  ${_legsWon[0]} — ${_legsWon[1]}  ${_config.nameOf(1)}',
                    style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _rematch,
                      icon: const Icon(Icons.replay),
                      label: Text(l10n.rematchButton),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.textSecondary,
                        side: BorderSide(
                            color: AppTheme.surfaceLight.withValues(alpha: 0.8)),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text(l10n.backToHome),
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

class _LocalDart {
  final int baseScore;
  final ScoreMultiplier multiplier;

  _LocalDart(this.baseScore, this.multiplier);

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
