import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/game_provider.dart' show ScoreMultiplier;
import '../../services/auto_scoring_service.dart';
import '../../services/camera_frame_service.dart';
import '../../services/dart_scoring_service.dart';
import '../../services/training_service.dart';
import '../../utils/app_theme.dart';
import '../../utils/dart_sound_service.dart';
import '../../utils/haptic_service.dart';
import '../../utils/orientation_utils.dart';
import '../../utils/score_converter.dart';
import '../../utils/storage_service.dart';
import '../../widgets/dartboard_edit_modal.dart';
import '../../widgets/game_turn_ui.dart';
import '../../widgets/local_camera_preview.dart';
import '../../widgets/queue_searching_banner.dart';
import 'logic/training_strategy.dart';
import 'training_end_screen.dart';
import 'training_game_view.dart';
import 'training_select_screen.dart';

/// Solo AI-driven training screen. Self-contained: sets up the local camera
/// and AI pipeline, then delegates per-training scoring to [strategy] and all
/// rendering to [TrainingGameView] — which is built from the same pieces as a
/// ranked match, so drills and matches look like the same app.
class TrainingAiScreen extends StatefulWidget {
  final TrainingStrategy strategy;
  const TrainingAiScreen({super.key, required this.strategy});

  @override
  State<TrainingAiScreen> createState() => _TrainingAiScreenState();
}

class _TrainingAiScreenState extends State<TrainingAiScreen>
    with WidgetsBindingObserver {
  TrainingStrategy get _strategy => widget.strategy;

  // Visit state — one entry per dart the AI (or user) has logged this visit.
  final List<TrainingDart> _currentVisit = [];
  bool _finished = false;
  bool _submitting = false;
  String? _submitError;
  TrainingResult? _finalResult;
  // Non-null for ~1.2s after a busted visit so the UI can flash "BUST!" before
  // the next visit starts. Cleared by [_clearBustFlash]; ignored when the
  // session is already finished (the end screen handles that).
  String? _bustFlash;

  // Camera + AI.
  CameraFrameService? _cameraService;
  AutoScoringService? _ai;
  bool _aiLoading = true;
  bool _aiManuallyDisabled = false;
  bool _aiPausedForEdit = false;
  bool _switchingCamera = false;
  String? _initError;
  double _cameraZoom = 1.0;
  double _cameraMinZoom = 1.0;
  double _cameraMaxZoom = 1.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WakelockPlus.enable();
    OrientationUtils.allowAll();
    _ai = AutoScoringService();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initCameraAndAi());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ai?.stopCapture();
    _ai?.dispose();
    _ai = null;
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
      _ai?.stopCapture();
    } else if (state == AppLifecycleState.resumed) {
      _maybeStartCapture();
    }
  }

  Future<void> _initCameraAndAi() async {
    if (kIsWeb || !AutoScoringService.isSupported) {
      setState(() {
        _aiLoading = false;
        _initError = 'unsupported';
      });
      return;
    }

    try {
      final status = await Permission.camera.request();
      if (!status.isGranted) {
        if (!mounted) return;
        setState(() {
          _aiLoading = false;
          _initError = 'permission';
        });
        return;
      }

      final cameraService = CameraFrameService();
      // Solo mode: no Agora — the service runs the camera + image stream and
      // caches the latest frame for AI scoring without pushing video anywhere.
      await cameraService.initialize(agoraEngine: null, videoTrackId: null);
      if (!mounted) {
        await cameraService.dispose();
        return;
      }
      if (!cameraService.isInitialized) {
        await cameraService.dispose();
        if (!mounted) return;
        setState(() {
          _aiLoading = false;
          _initError = 'no_camera';
        });
        return;
      }
      _cameraService = cameraService;
      // Solo mode: stop the 30fps image stream whenever the AI loop is off
      // (score edit, AI toggled off, training finished) — no Agora viewer
      // needs the frames.
      _ai?.onCaptureActiveChanged = cameraService.setAiActive;

      try {
        final minZoom = await cameraService.getMinZoomLevel();
        final maxZoom = await cameraService.getMaxZoomLevel();
        final savedZoom = await StorageService.getCameraZoom();
        final clampedZoom = savedZoom.clamp(minZoom, maxZoom);
        await cameraService.setZoomLevel(clampedZoom);
        if (!mounted) return;
        setState(() {
          _cameraMinZoom = minZoom;
          _cameraMaxZoom = maxZoom;
          _cameraZoom = clampedZoom;
        });
      } catch (_) {}

      await _ai!.loadModel();
      if (!mounted) return;
      setState(() => _aiLoading = false);
      _maybeStartCapture();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _aiLoading = false;
        _initError = 'init_failed';
      });
    }
  }

  void _maybeStartCapture() {
    if (_ai == null || !_ai!.modelLoaded) return;
    if (_cameraService == null) return;
    if (_aiManuallyDisabled || _aiPausedForEdit || _finished) return;
    final camService = _cameraService!;
    _ai!.startCapture(
      captureFrame: () => camService.captureFrame(),
      captureRgba: () => camService.captureRgba(),
      captureYuv: () => camService.captureYuvPlanes(),
      cleanupFile: (path) async {
        try {
          await File(path).delete();
        } catch (_) {}
      },
      onDartDetected: _onDartDetected,
      onAutoConfirm: _onAutoConfirm,
    );
  }

  void _onDartDetected(int slotIndex, DartScore score) {
    if (!mounted || _finished) return;
    final (base, mul) = dartScoreToBackend(score);
    HapticService.mediumImpact();
    DartSoundService.playDartHit(base, mul);
    setState(() {
      if (slotIndex < _currentVisit.length) {
        _currentVisit[slotIndex] = TrainingDart(base, mul);
      } else {
        while (_currentVisit.length < slotIndex) {
          _currentVisit.add(const TrainingDart(0, ScoreMultiplier.single));
        }
        _currentVisit.add(TrainingDart(base, mul));
      }
    });
  }

  void _onAutoConfirm() {
    if (!mounted || _finished) return;
    HapticService.heavyImpact();
    _submitVisit();
  }

  Future<void> _editDartSlot(int index, DartScore? current) async {
    HapticService.lightImpact();
    _ai?.stopCapture();
    _aiPausedForEdit = true;
    final result = await showDartboardEditModal(
      context,
      dartIndex: index,
      currentScore: current,
    );
    if (!mounted) return;
    if (result != null) {
      final (base, mul) = dartScoreToBackend(result);
      setState(() {
        while (_currentVisit.length <= index) {
          _currentVisit.add(const TrainingDart(0, ScoreMultiplier.single));
        }
        _currentVisit[index] = TrainingDart(base, mul);
      });
      _ai?.overrideDart(index, result);
    }
    _aiPausedForEdit = false;
    _maybeStartCapture();
  }

  void _removeLastDart() {
    if (_currentVisit.isEmpty) return;
    final lastIndex = _currentVisit.length - 1;
    _ai?.removeDart(lastIndex);
    setState(() => _currentVisit.removeLast());
  }

  void _toggleAi() {
    setState(() {
      _aiManuallyDisabled = !_aiManuallyDisabled;
      if (_aiManuallyDisabled) {
        _ai?.stopCapture();
      } else {
        _maybeStartCapture();
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

  void _submitVisit() {
    if (_finished) return;
    final darts = List<TrainingDart>.generate(
      3,
      (i) => i < _currentVisit.length
          ? _currentVisit[i]
          : const TrainingDart(0, ScoreMultiplier.single),
    );
    final outcome = _strategy.submitVisit(darts);
    _currentVisit.clear();
    _ai?.resetTurn();
    _aiPausedForEdit = false;
    if (outcome.finished) {
      final l10n = AppLocalizations.of(context);
      setState(() {
        _finished = true;
        _finalResult = _strategy.buildResult(l10n);
      });
      _ai?.stopCapture();
      _submitResult();
    } else {
      // Mid-session bust — flash the indicator briefly so the player knows
      // their score reverted before the next visit starts.
      if (outcome.bustReason != null) {
        HapticService.heavyImpact();
        setState(() => _bustFlash = outcome.bustReason);
        Future.delayed(const Duration(milliseconds: 1200), _clearBustFlash);
      } else {
        setState(() {});
      }
      _maybeStartCapture();
    }
  }

  void _clearBustFlash() {
    if (!mounted) return;
    setState(() => _bustFlash = null);
  }

  Future<void> _submitResult() async {
    final result = _finalResult;
    if (result == null) return;
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      await TrainingService.submit(
        type: _strategy.trainingType,
        score: result.score,
        dartsThrown: result.dartsThrown,
        completed: result.completed,
        details: result.details,
      );
      if (!mounted) return;
      setState(() => _submitting = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _submitError = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  Future<bool> _confirmLeave() async {
    if (_finished ||
        (_currentVisit.isEmpty && _strategy.progress(const []) == 0)) {
      return true;
    }
    final l10n = AppLocalizations.of(context);
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text(l10n.trainingQuitTitle),
        content: Text(l10n.trainingQuitMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.stay),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.leave),
          ),
        ],
      ),
    );
    return res ?? false;
  }

  void _resetAndReplay() {
    _strategy.reset();
    _currentVisit.clear();
    _ai?.resetTurn();
    setState(() {
      _finished = false;
      _finalResult = null;
      _submitError = null;
    });
    _maybeStartCapture();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (_finished && _finalResult != null) {
      final r = _finalResult!;
      return TrainingEndScreen(
        type: _strategy.trainingType,
        score: r.score,
        dartsThrown: r.dartsThrown,
        completed: r.completed,
        scoreLabel: r.scoreLabel,
        subtitle: r.subtitle,
        isSubmitting: _submitting,
        submitError: _submitError,
        onRetrySubmit: _submitResult,
        onPlayAgain: _resetAndReplay,
      );
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmLeave() && mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: AppTheme.gameBackground,
        // No SafeArea here: TrainingGameView insets itself like the match
        // layouts do, so the camera can sit right under the status bar.
        body: Stack(
          children: [
            _aiLoading
                ? _buildLoadingView(l10n)
                : _initError != null
                ? _buildErrorView(l10n)
                : _buildPlayingView(l10n),
            // "Still searching" pill when the drill was started while queued.
            // Sits a row below the in-camera top controls so it never overlaps
            // them — same placement as the bot-training screen.
            Positioned(
              top: MediaQuery.of(context).padding.top + 52,
              left: 0,
              right: 0,
              child: const Center(child: QueueSearchingBanner()),
            ),
            if (_bustFlash != null) _buildBustOverlay(l10n, _bustFlash!),
          ],
        ),
      ),
    );
  }

  Widget _buildBustOverlay(AppLocalizations l10n, String reason) {
    final reasonText = switch (reason) {
      'below_zero' => l10n.trainingBustBelowZero,
      'not_double_finish' => l10n.trainingBustNotDouble,
      'left_one' => l10n.trainingBustLeftOne,
      _ => l10n.trainingBustedOut,
    };
    return IgnorePointer(
      child: Container(
        color: Colors.black.withValues(alpha: 0.6),
        alignment: Alignment.center,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 32),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 22),
          decoration: BoxDecoration(
            color: AppTheme.error,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: AppTheme.error.withValues(alpha: 0.5),
                blurRadius: 30,
                spreadRadius: 4,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.warning_rounded, color: Colors.white, size: 48),
              const SizedBox(height: 8),
              Text(
                l10n.trainingBusted.toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 36,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 4,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                reasonText,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingView(AppLocalizations l10n) {
    return SafeArea(
      child: Column(
        children: [
          _buildTopBar(l10n),
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(color: AppTheme.playerBlue),
                  const SizedBox(height: 16),
                  Text(
                    l10n.loadingAi,
                    style: const TextStyle(color: AppTheme.textSecondary),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView(AppLocalizations l10n) {
    final msg = switch (_initError) {
      'permission' => l10n.cameraPermissionRequired,
      'no_camera' => l10n.noCamerasFound,
      'unsupported' => l10n.trainingAiUnavailable,
      _ => l10n.trainingAiUnavailable,
    };
    return SafeArea(
      child: Column(
        children: [
          _buildTopBar(l10n),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.videocam_off,
                      color: AppTheme.error,
                      size: 48,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      msg,
                      style: AppTheme.bodyLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      style: gameFilledButtonStyle(AppTheme.playerBlue),
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(l10n.backToHome),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayingView(AppLocalizations l10n) {
    final cam = _cameraService;
    final ready = !_switchingCamera && cam != null && cam.isInitialized;
    return TrainingGameView(
      scoringService: _ai!,
      strategy: _strategy,
      pending: _currentVisit,
      title: trainingDisplayName(l10n, _strategy.trainingType),
      onConfirm: _submitVisit,
      localCameraPreview: ready && cam.controller != null
          ? LocalCameraPreview(controller: cam.controller!)
          : null,
      onBack: () async {
        if (await _confirmLeave() && mounted) {
          Navigator.of(context).pop();
        }
      },
      onSwitchCamera: cam != null ? _switchCamera : null,
      onZoomIn: cam != null ? _zoomIn : null,
      onZoomOut: cam != null ? _zoomOut : null,
      currentZoom: _cameraZoom,
      minZoom: _cameraMinZoom,
      maxZoom: _cameraMaxZoom,
      onEditSlot: _editDartSlot,
      onRemoveLast: _removeLastDart,
      onToggleAi: _ai?.modelLoaded == true ? _toggleAi : null,
      aiEnabled: !_aiManuallyDisabled,
    );
  }

  /// Minimal header for the pre-game states (AI loading, camera error) — once
  /// the drill starts, TrainingGameView carries its own in-camera back button.
  Widget _buildTopBar(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          GameControlButton(
            icon: Icons.arrow_back_ios_new,
            color: AppTheme.textSecondary,
            onTap: () async {
              if (await _confirmLeave() && mounted) {
                Navigator.of(context).pop();
              }
            },
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              trainingDisplayName(l10n, _strategy.trainingType),
              style: AppTheme.titleLarge,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
