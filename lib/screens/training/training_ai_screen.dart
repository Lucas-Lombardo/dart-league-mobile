import 'dart:io';
import 'dart:math' show min;

import 'package:camera/camera.dart';
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
import '../../utils/score_converter.dart';
import '../../utils/storage_service.dart';
import '../../widgets/dartboard_edit_modal.dart';
import 'logic/training_strategy.dart';
import 'training_end_screen.dart';
import 'training_select_screen.dart';

/// Solo AI-driven training screen. Self-contained: sets up the local camera
/// and AI pipeline, then delegates per-training scoring to [strategy]. The
/// layout mirrors dartsmind's single-player training view — no opponent
/// scoreboard, a dart-slot row + a training-specific info panel.
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

  // Camera + AI.
  CameraFrameService? _cameraService;
  AutoScoringService? _ai;
  bool _aiLoading = true;
  bool _aiManuallyDisabled = false;
  bool _aiPausedForEdit = false;
  String? _initError;
  double _cameraZoom = 1.0;
  double _cameraMinZoom = 1.0;
  double _cameraMaxZoom = 1.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WakelockPlus.enable();
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
        try { await File(path).delete(); } catch (_) {}
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
      setState(() {});
      _maybeStartCapture();
    }
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
        backgroundColor: AppTheme.background,
        body: SafeArea(
          top: true,
          bottom: true,
          child: _aiLoading
              ? _buildLoadingView(l10n)
              : _initError != null
                  ? _buildErrorView(l10n)
                  : _buildPlayingView(l10n),
        ),
      ),
    );
  }

  Widget _buildLoadingView(AppLocalizations l10n) {
    return Column(
      children: [
        _buildTopBar(l10n),
        Expanded(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircularProgressIndicator(color: AppTheme.primary),
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
    );
  }

  Widget _buildErrorView(AppLocalizations l10n) {
    final msg = switch (_initError) {
      'permission' => l10n.cameraPermissionRequired,
      'no_camera' => l10n.noCamerasFound,
      'unsupported' => l10n.trainingAiUnavailable,
      _ => l10n.trainingAiUnavailable,
    };
    return Column(
      children: [
        _buildTopBar(l10n),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.videocam_off,
                      color: AppTheme.error, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    msg,
                    style: AppTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l10n.backToHome),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPlayingView(AppLocalizations l10n) {
    return Column(
      children: [
        _buildTopBar(l10n),
        Expanded(
          flex: 5,
          child: _CameraPanel(
            camera: _cameraService?.controller,
            zoom: _cameraZoom,
            minZoom: _cameraMinZoom,
            maxZoom: _cameraMaxZoom,
            onZoomIn: _zoomIn,
            onZoomOut: _zoomOut,
            aiEnabled: !_aiManuallyDisabled,
            onToggleAi: _ai?.modelLoaded == true ? _toggleAi : null,
          ),
        ),
        _DartSlotsRow(
          ai: _ai!,
          currentVisit: _currentVisit,
          onEditSlot: _editDartSlot,
          onRemoveLast: _removeLastDart,
        ),
        Expanded(
          flex: 4,
          child: _InfoPanel(
            strategy: _strategy,
            l10n: l10n,
            pending: _currentVisit,
          ),
        ),
        _buildActionButton(l10n),
      ],
    );
  }

  Widget _buildTopBar(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: () async {
              if (await _confirmLeave() && mounted) {
                Navigator.of(context).pop();
              }
            },
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppTheme.surfaceLight.withValues(alpha: 0.4),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, size: 20, color: Colors.white),
            ),
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

  Widget _buildActionButton(AppLocalizations l10n) {
    final hasDarts = _currentVisit.isNotEmpty;
    final label = hasDarts
        ? l10n.trainingConfirmVisit
        : l10n.trainingEndRoundEarly;
    final color = hasDarts ? AppTheme.primary : AppTheme.surfaceLight;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton.icon(
          onPressed: () {
            HapticService.heavyImpact();
            _submitVisit();
          },
          icon: Icon(hasDarts ? Icons.check_circle_outline : Icons.skip_next),
          label: Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Camera panel ──────────────────────────────────────────────────────────────

class _CameraPanel extends StatelessWidget {
  final CameraController? camera;
  final double zoom;
  final double minZoom;
  final double maxZoom;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final bool aiEnabled;
  final VoidCallback? onToggleAi;

  const _CameraPanel({
    required this.camera,
    required this.zoom,
    required this.minZoom,
    required this.maxZoom,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.aiEnabled,
    required this.onToggleAi,
  });

  @override
  Widget build(BuildContext context) {
    final ready = camera != null && camera!.value.isInitialized;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            Positioned.fill(
              child: Container(
                color: Colors.black,
                child: ready
                    ? FittedBox(
                        fit: BoxFit.cover,
                        child: SizedBox(
                          width: camera!.value.previewSize!.height,
                          height: camera!.value.previewSize!.width,
                          child: CameraPreview(camera!),
                        ),
                      )
                    : const Center(
                        child: Icon(Icons.videocam_off,
                            color: Colors.white24, size: 48),
                      ),
              ),
            ),
            if (ready)
              Positioned(
                bottom: 8,
                left: 8,
                child: Row(children: [
                  _RoundIconButton(
                    icon: Icons.remove,
                    enabled: zoom > minZoom,
                    onTap: onZoomOut,
                  ),
                  const SizedBox(width: 4),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${zoom.toStringAsFixed(1)}x',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  _RoundIconButton(
                    icon: Icons.add,
                    enabled: zoom < maxZoom,
                    onTap: onZoomIn,
                  ),
                ]),
              ),
            if (ready && onToggleAi != null)
              Positioned(
                bottom: 8,
                right: 8,
                child: _RoundIconButton(
                  icon: aiEnabled ? Icons.smart_toy : Icons.smart_toy_outlined,
                  enabled: true,
                  active: aiEnabled,
                  onTap: onToggleAi!,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final bool active;
  final VoidCallback onTap;
  const _RoundIconButton({
    required this.icon,
    required this.onTap,
    this.enabled = true,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Opacity(
        opacity: enabled ? 1.0 : 0.4,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            shape: BoxShape.circle,
            border: Border.all(
              color: active
                  ? AppTheme.primary
                  : Colors.white.withValues(alpha: 0.4),
            ),
          ),
          child: Icon(
            icon,
            color: active ? AppTheme.primary : Colors.white,
            size: 18,
          ),
        ),
      ),
    );
  }
}

// ── Dart slots row (3 dart indicators) ───────────────────────────────────────

class _DartSlotsRow extends StatelessWidget {
  final AutoScoringService ai;
  final List<TrainingDart> currentVisit;
  final Future<void> Function(int index, DartScore? current) onEditSlot;
  final VoidCallback onRemoveLast;

  const _DartSlotsRow({
    required this.ai,
    required this.currentVisit,
    required this.onEditSlot,
    required this.onRemoveLast,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ai,
      builder: (context, _) {
        final slots = ai.dartSlots;
        final lastFilled = currentVisit.length - 1;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: List.generate(3, (i) {
              final score = i < slots.length ? slots[i] : null;
              final isLast = i == lastFilled;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: _DartSlot(
                    index: i,
                    score: score,
                    isCapturing: ai.isCapturing,
                    onTap: () => onEditSlot(i, score),
                    onRemove: isLast ? onRemoveLast : null,
                  ),
                ),
              );
            }),
          ),
        );
      },
    );
  }
}

class _DartSlot extends StatelessWidget {
  final int index;
  final DartScore? score;
  final bool isCapturing;
  final VoidCallback onTap;
  final VoidCallback? onRemove;

  const _DartSlot({
    required this.index,
    required this.score,
    required this.isCapturing,
    required this.onTap,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final has = score != null;
    return GestureDetector(
      onTap: onTap,
      child: LayoutBuilder(
        builder: (ctx, c) {
          final size = min(c.maxWidth * 0.9, 72.0).clamp(48.0, 72.0);
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: size,
                height: size,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: size,
                      height: size,
                      decoration: BoxDecoration(
                        color: has
                            ? AppTheme.primary.withValues(alpha: 0.15)
                            : AppTheme.surface,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: has
                              ? AppTheme.primary
                              : AppTheme.surfaceLight,
                          width: 2,
                        ),
                      ),
                      child: has
                          ? Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  _shortLabel(score!),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    height: 1,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${score!.score}',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                    height: 1,
                                  ),
                                ),
                              ],
                            )
                          : isCapturing
                              ? const Center(
                                  child: SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                                )
                              : const Center(
                                  child: Icon(Icons.add,
                                      color: AppTheme.textSecondary,
                                      size: 24),
                                ),
                    ),
                    if (onRemove != null)
                      Positioned(
                        top: -6,
                        right: -6,
                        child: GestureDetector(
                          onTap: onRemove,
                          child: Container(
                            width: 22,
                            height: 22,
                            decoration: const BoxDecoration(
                              color: AppTheme.error,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.close,
                                color: Colors.white, size: 14),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                AppLocalizations.of(context).dartNumber(index + 1),
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 11,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _shortLabel(DartScore s) {
    switch (s.ring) {
      case 'double_bull':
        return 'DB';
      case 'single_bull':
        return 'B';
      case 'triple':
        return 'T${s.segment}';
      case 'double':
        return 'D${s.segment}';
      case 'inner_single':
      case 'outer_single':
        return 'S${s.segment}';
      default:
        return 'M';
    }
  }
}

// ── Info panel ────────────────────────────────────────────────────────────────

class _InfoPanel extends StatelessWidget {
  final TrainingStrategy strategy;
  final AppLocalizations l10n;
  final List<TrainingDart> pending;
  const _InfoPanel({
    required this.strategy,
    required this.l10n,
    required this.pending,
  });

  @override
  Widget build(BuildContext context) {
    final focalLabel = strategy.primaryLabel(l10n);
    final focalValue = strategy.primaryValue(l10n, pending);
    final secondaryLabel = strategy.secondaryLabel(l10n);
    final secondaryValue = strategy.secondaryValue(l10n, pending);
    final progress = strategy.progress(pending).clamp(0.0, 1.0);
    final caption = strategy.progressCaption(l10n, pending);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: AppTheme.surfaceLight.withValues(alpha: 0.5),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: LayoutBuilder(
          builder: (ctx, c) {
            return Column(
              children: [
                if (caption != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      caption,
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                if (caption != null) const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 4,
                    color: AppTheme.primary,
                    backgroundColor: AppTheme.surfaceLight,
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(
                              focalLabel.toUpperCase(),
                              style: const TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.8,
                              ),
                            ),
                            const SizedBox(height: 4),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                focalValue,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 72,
                                  fontWeight: FontWeight.w900,
                                  height: 1,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (secondaryLabel != null && secondaryValue != null) ...[
                        Container(
                          width: 1,
                          margin:
                              const EdgeInsets.symmetric(horizontal: 12),
                          color: AppTheme.surfaceLight
                              .withValues(alpha: 0.6),
                        ),
                        Expanded(
                          flex: 2,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment:
                                CrossAxisAlignment.center,
                            children: [
                              Text(
                                secondaryLabel.toUpperCase(),
                                style: const TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.8,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 4),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  secondaryValue,
                                  style: const TextStyle(
                                    color: AppTheme.accent,
                                    fontSize: 40,
                                    fontWeight: FontWeight.bold,
                                    height: 1,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
