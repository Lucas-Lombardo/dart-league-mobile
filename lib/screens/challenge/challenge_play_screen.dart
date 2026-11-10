import 'dart:async';
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
import '../../services/dataset_capture_service.dart';
import '../../utils/app_theme.dart';
import '../../utils/dart_sound_service.dart';
import '../../utils/game_system_ui.dart';
import '../../utils/haptic_service.dart';
import '../../utils/orientation_utils.dart';
import '../../utils/score_converter.dart';
import '../../utils/storage_service.dart';
import '../../widgets/dartboard_edit_modal.dart';
import '../../widgets/design_system.dart';
import '../../widgets/local_camera_preview.dart';
import '../training/logic/training_strategy.dart';
import '../training/training_game_view.dart';
import 'challenge_api.dart';
import 'challenge_models.dart';
import 'challenge_proof_uploader.dart';
import 'challenge_result_screen.dart';
import 'logic/challenge_strategy.dart';

/// One attempt of the daily challenge: the AI training pipeline (camera +
/// auto-scoring + TrainingGameView), with three differences:
///  - the AI cannot be turned off (camera IA obligatoire);
///  - a ranked attempt is filmed: the native ring retains the whole session
///    (ChallengeProofUploader), and the camera stream stays on between
///    visits so the video has no hole;
///  - every dart is recorded with its origin (AI-read, corrected by hand) and
///    the time of its visit, and the SERVER computes the score from them.
class ChallengePlayScreen extends StatefulWidget {
  final ChallengeStart attempt;
  const ChallengePlayScreen({super.key, required this.attempt});

  @override
  State<ChallengePlayScreen> createState() => _ChallengePlayScreenState();
}

class _Slot {
  final TrainingDart dart;
  final bool ai;
  final bool fixed;
  const _Slot(this.dart, {this.ai = false, this.fixed = false});
}

class _ChallengePlayScreenState extends State<ChallengePlayScreen> with WidgetsBindingObserver {
  late final ChallengeStrategy _strategy = ChallengeStrategy(widget.attempt.format);
  final List<_Slot> _current = [];
  final List<ChallengeVisitRecord> _records = [];
  final DateTime _startedAt = DateTime.now();

  CameraFrameService? _camera;
  AutoScoringService? _ai;
  bool _aiLoading = true;
  bool _pausedForEdit = false;
  bool _switchingCamera = false;
  String? _initError;
  double _zoom = 1, _minZoom = 1, _maxZoom = 1;

  bool _finished = false;
  bool _submitting = false;
  String? _submitError;

  bool get _ranked => widget.attempt.ranked;
  List<TrainingDart> get _pending => _current.map((s) => s.dart).toList();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WakelockPlus.enable();
    OrientationUtils.allowAll();
    GameSystemUi.enter();
    _ai = AutoScoringService()..telemetrySessionOf = () => ('training', null);
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopCamera();
    DatasetCaptureService.flush();
    WakelockPlus.disable();
    OrientationUtils.portraitOnly();
    GameSystemUi.exit();
    super.dispose();
  }

  void _stopCamera() {
    _ai?.stopCapture();
    _ai?.dispose();
    _ai = null;
    // Disposing the camera also stops the replay ring; the retained session
    // segments stay on disk for the upload.
    _camera?.dispose();
    _camera = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _ai?.stopCapture();
    } else if (state == AppLifecycleState.resumed) {
      _maybeStartCapture();
    }
  }

  Future<void> _init() async {
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
      final camera = CameraFrameService();
      // Ranked: tee the frames into the replay ring, retained for this attempt.
      await camera.initialize(replayRing: _ranked);
      if (!mounted) {
        await camera.dispose();
        return;
      }
      if (!camera.isInitialized) {
        await camera.dispose();
        if (!mounted) return;
        setState(() {
          _aiLoading = false;
          _initError = 'no_camera';
        });
        return;
      }
      _camera = camera;
      if (_ranked) {
        await ChallengeProofUploader.beginRecording(widget.attempt.attemptId);
      } else {
        // Practice: nobody films it, the stream may sleep between visits.
        _ai?.onCaptureActiveChanged = camera.setAiActive;
      }
      try {
        _minZoom = await camera.getMinZoomLevel();
        _maxZoom = await camera.getMaxZoomLevel();
        _zoom = (await StorageService.getCameraZoom()).clamp(_minZoom, _maxZoom);
        await camera.setZoomLevel(_zoom);
      } catch (_) {}
      await _ai!.loadModel();
      if (!mounted) return;
      setState(() => _aiLoading = false);
      _maybeStartCapture();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _aiLoading = false;
        _initError = 'init_failed';
      });
    }
  }

  void _maybeStartCapture() {
    final ai = _ai;
    final camera = _camera;
    if (ai == null || !ai.modelLoaded || camera == null) return;
    if (_pausedForEdit || _finished) return;
    ai.startCapture(
      captureFrame: () => camera.captureFrame(),
      captureRgba: () => camera.captureRgba(),
      captureYuv: () => camera.captureYuvPlanes(),
      cleanupFile: (path) async {
        try {
          await File(path).delete();
        } catch (_) {}
      },
      onDartDetected: _onDartDetected,
      onAutoConfirm: _onAutoConfirm,
    );
  }

  void _onDartDetected(int slot, DartScore score) {
    if (!mounted || _finished) return;
    final (base, mul) = dartScoreToBackend(score);
    HapticService.mediumImpact();
    DartSoundService.playDartHit(base, mul);
    setState(() {
      final s = _Slot(TrainingDart(base, mul), ai: true);
      if (slot < _current.length) {
        _current[slot] = s;
      } else {
        while (_current.length < slot) {
          _current.add(const _Slot(TrainingDart(0, ScoreMultiplier.single)));
        }
        _current.add(s);
      }
    });
  }

  void _onAutoConfirm() {
    if (!mounted || _finished) return;
    HapticService.heavyImpact();
    _confirmVisit();
  }

  Future<void> _editSlot(int index, DartScore? current) async {
    HapticService.lightImpact();
    _ai?.stopCapture();
    _pausedForEdit = true;
    final result = await showDartboardEditModal(context, dartIndex: index, currentScore: current);
    if (!mounted) return;
    if (result != null) {
      final (base, mul) = dartScoreToBackend(result);
      setState(() {
        while (_current.length <= index) {
          _current.add(const _Slot(TrainingDart(0, ScoreMultiplier.single)));
        }
        _current[index] = _Slot(TrainingDart(base, mul), fixed: true);
      });
      _ai?.overrideDart(index, result);
    }
    _pausedForEdit = false;
    _maybeStartCapture();
  }

  void _removeLast() {
    if (_current.isEmpty) return;
    _ai?.removeDart(_current.length - 1);
    setState(() => _current.removeLast());
  }

  void _confirmVisit() {
    if (_finished) return;
    final slots = List<_Slot>.generate(
      3,
      (i) => i < _current.length ? _current[i] : const _Slot(TrainingDart(0, ScoreMultiplier.single)),
    );
    _records.add(ChallengeVisitRecord(
      DateTime.now().millisecondsSinceEpoch,
      [for (final s in slots) ChallengeThrow(challengeDartOf(s.dart), ai: s.ai, fixed: s.fixed)],
    ));
    final outcome = _strategy.submitVisit(slots.map((s) => s.dart).toList());
    _current.clear();
    _ai?.resetTurn();
    _pausedForEdit = false;
    if (outcome.finished) {
      _finish();
    } else {
      setState(() {});
      _maybeStartCapture();
    }
  }

  /// The session is over (or the player stopped a ranked attempt): stop
  /// filming, then send the darts. The server's result opens next.
  Future<void> _finish() async {
    if (_finished) return;
    setState(() => _finished = true);
    _stopCamera();
    await _submit();
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      final result = await ChallengeApi.submit(
        widget.attempt.attemptId,
        visits: _records,
        clientScore: _strategy.result.score,
        durationSec: DateTime.now().difference(_startedAt).inSeconds,
      );
      unawaited(ChallengeStore.instance.refresh());
      if (_ranked && result.proofRequired && result.proofStatus != 'delivered') {
        unawaited(ChallengeProofUploader.upload(widget.attempt.attemptId));
      } else if (_ranked) {
        unawaited(ChallengeProofUploader.discard(widget.attempt.attemptId));
      }
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => ChallengeResultScreen(result: result, xpSince: _startedAt)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _submitError = AppLocalizations.of(context).challengeSubmitFailed;
      });
    }
  }

  Future<void> _onBack() async {
    if (_finished) return;
    final l10n = AppLocalizations.of(context);
    final navigator = Navigator.of(context);
    final played = _records.isNotEmpty;
    if (!played && _strategy.progress(const []) == 0 && !_ranked) {
      navigator.pop();
      return;
    }
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text(_ranked ? l10n.challengeQuitRankedTitle : l10n.trainingQuitTitle),
        content: Text(_ranked ? l10n.challengeQuitRankedBody : l10n.trainingQuitMessage),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.stay)),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.leave),
          ),
        ],
      ),
    );
    if (leave != true || !mounted) return;
    // A ranked attempt with darts counts as it stands; without any, it is
    // simply spent (it was started).
    if (_ranked && played) {
      await _finish();
    } else {
      navigator.pop();
    }
  }

  Future<void> _zoomBy(double delta) async {
    final camera = _camera;
    if (camera == null) return;
    final next = (_zoom + delta).clamp(_minZoom, _maxZoom);
    try {
      await camera.setZoomLevel(next);
      if (mounted) setState(() => _zoom = next);
    } catch (_) {}
  }

  Future<void> _switchCamera() async {
    final camera = _camera;
    if (camera == null || _switchingCamera) return;
    HapticService.lightImpact();
    setState(() => _switchingCamera = true);
    try {
      await camera.switchCamera();
      try {
        _minZoom = await camera.getMinZoomLevel();
        _maxZoom = await camera.getMaxZoomLevel();
        _zoom = _zoom.clamp(_minZoom, _maxZoom);
        await camera.setZoomLevel(_zoom);
      } catch (_) {}
    } finally {
      if (mounted) setState(() => _switchingCamera = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final format = widget.attempt.format;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: Scaffold(
        backgroundColor: AppTheme.gameBackground,
        body: _finished
            ? _buildSubmitting(l10n)
            : _aiLoading
                ? _buildMessage(l10n, l10n.loadingAi, loading: true)
                : _initError != null
                    ? _buildMessage(l10n, switch (_initError) {
                        'permission' => l10n.cameraPermissionRequired,
                        'no_camera' => l10n.noCamerasFound,
                        _ => l10n.trainingAiUnavailable,
                      })
                    : TrainingGameView(
                        scoringService: _ai!,
                        strategy: _strategy,
                        pending: _pending,
                        title: '${format.short.resolve(context)} · ${_ranked ? l10n.challengeRankedBadge : l10n.challengePracticeBadge}',
                        onConfirm: _confirmVisit,
                        localCameraPreview: !_switchingCamera && _camera?.controller != null
                            ? LocalCameraPreview(controller: _camera!.controller!)
                            : null,
                        onBack: _onBack,
                        onSwitchCamera: _camera != null ? _switchCamera : null,
                        onZoomIn: _camera != null ? () => _zoomBy(0.1) : null,
                        onZoomOut: _camera != null ? () => _zoomBy(-0.1) : null,
                        currentZoom: _zoom,
                        minZoom: _minZoom,
                        maxZoom: _maxZoom,
                        onEditSlot: _editSlot,
                        onRemoveLast: _removeLast,
                        // The AI camera is mandatory in the challenge.
                        onToggleAi: null,
                        aiEnabled: true,
                      ),
      ),
    );
  }

  Widget _buildMessage(AppLocalizations l10n, String text, {bool loading = false}) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        child: Column(
          children: [
            DsScreenHeader(title: l10n.challengeTitle, showBack: true, onBack: () => Navigator.of(context).pop()),
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (loading)
                      const SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: AppTheme.primary),
                      )
                    else
                      const Icon(Icons.videocam_off_outlined, size: 32, color: AppTheme.textSecondary),
                    const SizedBox(height: 16),
                    Text(text, style: AppTheme.bodyMedium, textAlign: TextAlign.center),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubmitting(AppLocalizations l10n) {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_submitting)
                const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: AppTheme.primary),
                ),
              const SizedBox(height: 16),
              Text(
                _submitError ?? l10n.challengeSubmitting,
                style: AppTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              if (_submitError != null) ...[
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(onPressed: _submit, child: Text(l10n.challengeRetry)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
