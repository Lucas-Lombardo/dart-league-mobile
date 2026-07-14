import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../l10n/app_localizations.dart';
import '../../services/dart_detection_service_stub.dart'
    if (dart.library.io) '../../services/dart_detection_service.dart';
import '../../services/native_inference.dart';
import '../../utils/app_theme.dart';
import '../../utils/haptic_service.dart';
import '../../utils/orientation_utils.dart';
import '../../utils/storage_service.dart';

/// Configuration for camera setup behavior.
class CameraSetupConfig {
  /// Whether to request microphone permission alongside camera.
  final bool requireMicrophone;

  /// Whether to enable AI dartboard detection.
  final bool enableAiDetection;

  /// Whether to restore saved zoom level from storage.
  final bool restoreSavedZoom;

  /// Whether to support pinch-to-zoom gestures.
  final bool enableGestureZoom;

  const CameraSetupConfig({
    this.requireMicrophone = true,
    this.enableAiDetection = true,
    this.restoreSavedZoom = false,
    this.enableGestureZoom = false,
  });
}

/// Mixin that provides shared camera setup logic for camera setup screens.
///
/// Subclasses must:
/// - Call [initCamera] in `initState()` (or via `addPostFrameCallback`)
/// - Call [disposeCamera] in `dispose()`
/// - Override [cameraSetupConfig] to customize behavior
/// - Override [onCameraReady] if needed
mixin CameraSetupMixin<T extends StatefulWidget> on State<T> {
  CameraController? cameraController;
  List<CameraDescription>? cameras;
  // Which lens the preview is currently using. Seeded from the persisted
  // preference in [initializeCamera] and flipped by [toggleCameraLens].
  CameraLensDirection cameraLensDirection = CameraLensDirection.back;
  bool isLoading = true;
  bool permissionsGranted = false;
  bool cameraReady = false;
  String? errorMessage;
  double currentZoom = 1.0;
  double minZoom = 1.0;
  double maxZoom = 1.0;
  double _baseZoom = 1.0;

  // AI dartboard detection
  NativeInference? _nativeInference;
  bool aiModelLoaded = false;
  String? aiHint;
  bool boardDetected = false;
  bool _aiCapturing = false;
  bool _aiAnalyzing = false;
  // Latest frame from the persistent image stream, analyzed by the AI loop.
  CameraImage? _latestAiFrame;
  bool _aiFrameStreamActive = false;

  /// Override to customize camera setup behavior.
  CameraSetupConfig get cameraSetupConfig => const CameraSetupConfig();

  /// Whether the play/ready button should be enabled.
  bool get canPlay {
    if (!permissionsGranted || !cameraReady) return false;
    if (cameraSetupConfig.enableAiDetection && !kIsWeb) {
      // AI scoring is a core feature — never let a match start without a
      // loaded model AND a detected board. Before this, a failed model load
      // silently skipped the AI gate and the player could queue into a match
      // whose AI then had to cold-load (or was already broken).
      if (!aiModelLoaded || !boardDetected) return false;
    }
    return true;
  }

  /// Label for the play/ready button based on current state.
  String getPlayButtonLabel(AppLocalizations l10n) {
    if (!permissionsGranted || !cameraReady) return l10n.cameraRequiredButton;
    if (cameraSetupConfig.enableAiDetection && !kIsWeb && !aiModelLoaded) {
      return l10n.loadingAi.toUpperCase();
    }
    if (aiModelLoaded && !boardDetected) {
      return aiHint != null ? aiHint!.toUpperCase() : l10n.scanningButton;
    }
    return l10n.play.toUpperCase();
  }

  /// Call from initState to start camera and optional AI detection.
  void initCamera() {
    OrientationUtils.allowAll();
    if (cameraSetupConfig.enableAiDetection && !kIsWeb) {
      _initAiDetection();
    }
  }

  /// Call from dispose to clean up resources.
  void disposeCamera() {
    _aiCapturing = false;
    _stopAiFrameStream();
    _nativeInference?.dispose();
    _nativeInference = null;
    final controller = cameraController;
    cameraController = null;
    if (controller != null) {
      // Dispose only after any in-flight AI analysis finishes: disposing a
      // controller that is still being torn away from (stream detach racing
      // an analysis) can wedge the camera plugin. Fire-and-forget since
      // dispose() can't await; the next screen's camera open retries "in use".
      _disposeControllerWhenAiIdle(controller);
    }
    OrientationUtils.portraitOnly();
  }

  /// Wait (bounded) for an in-flight AI analysis to finish before releasing
  /// the camera.
  Future<void> _waitForAiIdle() async {
    final sw = Stopwatch()..start();
    while (_aiAnalyzing && sw.elapsed < const Duration(seconds: 5)) {
      await Future.delayed(const Duration(milliseconds: 50));
    }
  }

  Future<void> _disposeControllerWhenAiIdle(CameraController controller) async {
    await _waitForAiIdle();
    try {
      await controller.dispose().timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('[CameraSetup] deferred controller dispose failed: $e');
    }
  }

  /// Handle app lifecycle changes for AI capture.
  void handleAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _aiCapturing = false;
      _stopAiFrameStream();
    } else if (state == AppLifecycleState.resumed) {
      if (aiModelLoaded && cameraReady) {
        _startAiCapture();
      }
    }
  }

  /// Initialize camera with permissions and configuration.
  Future<void> initializeCamera() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    if (kIsWeb) {
      setState(() {
        isLoading = false;
        permissionsGranted = true;
        cameraReady = true;
      });
      return;
    }

    final l10n = AppLocalizations.of(context);
    final config = cameraSetupConfig;

    try {
      if (config.requireMicrophone) {
        final statuses = await [
          Permission.camera,
          Permission.microphone,
        ].request();

        final cameraGranted =
            statuses[Permission.camera]?.isGranted ?? false;
        final micGranted =
            statuses[Permission.microphone]?.isGranted ?? false;

        if (!cameraGranted || !micGranted) {
          setState(() {
            isLoading = false;
            permissionsGranted = false;
            if (!cameraGranted && !micGranted) {
              errorMessage = l10n.cameraAndMicPermissionRequired;
            } else if (!cameraGranted) {
              errorMessage = l10n.cameraPermissionRequired;
            } else {
              errorMessage = l10n.micPermissionRequired;
            }
          });
          return;
        }
      } else {
        final status = await Permission.camera.request();
        if (!status.isGranted) {
          setState(() {
            isLoading = false;
            permissionsGranted = false;
            errorMessage = l10n.cameraPermissionRequired;
          });
          return;
        }
      }

      permissionsGranted = true;

      cameras = await availableCameras();
      if (cameras == null || cameras!.isEmpty) {
        setState(() {
          isLoading = false;
          errorMessage = l10n.noCamerasFound;
        });
        return;
      }

      // Seed the lens from the persisted front/back preference. Falls back to
      // the back camera (then any camera) when the chosen lens isn't present.
      final useFront = await StorageService.getUseFrontCamera();
      final desired = useFront
          ? CameraLensDirection.front
          : CameraLensDirection.back;
      final selectedCamera = cameras!.firstWhere(
        (camera) => camera.lensDirection == desired,
        orElse: () => cameras!.firstWhere(
          (camera) => camera.lensDirection == CameraLensDirection.back,
          orElse: () => cameras!.first,
        ),
      );
      cameraLensDirection = selectedCamera.lensDirection;

      // Initialize with retries + a per-attempt timeout. The camera can still
      // be held by the screen we navigated from (its dispose() releases the
      // device asynchronously, up to ~1s later — same window handled by
      // CameraFrameService._openCamera), and on some devices initialize() can
      // hang outright instead of failing. Without this, a transient
      // "camera in use" left the user stuck on the spinner with no way out.
      const maxAttempts = 5;
      for (var attempt = 0; attempt < maxAttempts; attempt++) {
        if (!mounted) return;
        cameraController = CameraController(
          selectedCamera,
          ResolutionPreset.high,
          enableAudio: false,
          // Same stream format as the in-game pipeline (CameraFrameService):
          // the AI loop reads raw frames off the image stream.
          imageFormatGroup: Platform.isAndroid
              ? ImageFormatGroup.yuv420
              : ImageFormatGroup.bgra8888,
        );
        try {
          await cameraController!
              .initialize()
              .timeout(const Duration(seconds: 10));
          break;
        } catch (e) {
          final failed = cameraController;
          cameraController = null;
          try {
            await failed?.dispose().timeout(const Duration(seconds: 2));
          } catch (_) {}
          if (attempt == maxAttempts - 1) rethrow;
          debugPrint('[CameraSetup] init failed '
              '(attempt ${attempt + 1}/$maxAttempts), retrying in 400ms: $e');
          await Future.delayed(const Duration(milliseconds: 400));
        }
      }
      if (!mounted) {
        final orphan = cameraController;
        cameraController = null;
        try {
          await orphan?.dispose();
        } catch (_) {}
        return;
      }

      try {
        await cameraController!.setFlashMode(FlashMode.off);
      } catch (e) {
        debugPrint('[Camera] Flash mode not supported: $e');
      }

      try {
        minZoom = await cameraController!.getMinZoomLevel();
        maxZoom = await cameraController!.getMaxZoomLevel();
        if (config.restoreSavedZoom) {
          final savedZoom = await StorageService.getCameraZoom();
          currentZoom = savedZoom.clamp(minZoom, maxZoom);
          await cameraController!.setZoomLevel(currentZoom);
        } else {
          currentZoom = minZoom;
        }
      } catch (e) {
        debugPrint('[CameraSetup] Zoom config failed: $e');
        minZoom = 1.0;
        maxZoom = 1.0;
        currentZoom = 1.0;
      }

      if (mounted) {
        setState(() {
          cameraReady = true;
          isLoading = false;
        });
        if (aiModelLoaded) _startAiCapture();
      }
    } catch (e) {
      setState(() {
        isLoading = false;
        cameraReady = false;
        errorMessage = '${l10n.failedToInitializeCamera}: $e';
      });
    }
  }

  /// Whether the device exposes both a front and a back camera, i.e. flipping
  /// between them is meaningful. Drives the visibility of the flip button.
  bool get canFlipCamera {
    final c = cameras;
    if (c == null) return false;
    final hasFront =
        c.any((x) => x.lensDirection == CameraLensDirection.front);
    final hasBack =
        c.any((x) => x.lensDirection == CameraLensDirection.back);
    return hasFront && hasBack;
  }

  /// Flip between the front and back camera. Persists the choice (so the game
  /// screen and the next launch honour it) and rebuilds the preview on the
  /// other lens.
  Future<void> toggleCameraLens() async {
    if (isLoading || !cameraReady) return;
    final goingFront = cameraLensDirection != CameraLensDirection.front;
    HapticService.lightImpact();
    await StorageService.saveUseFrontCamera(goingFront);
    // Pause the AI loop, detach the frame stream and wait out any in-flight
    // analysis before releasing the lens — disposing a controller that is
    // still being used can wedge the camera plugin. initializeCamera()
    // restarts the capture loop (and stream) once the new lens is up.
    _aiCapturing = false;
    _stopAiFrameStream();
    // Release the current lens before opening the other one — the camera
    // device can't be held twice. initializeCamera() re-reads the saved
    // preference to pick the new lens.
    final old = cameraController;
    cameraController = null;
    if (mounted) {
      setState(() {
        cameraReady = false;
        boardDetected = false;
        aiHint = null;
      });
    }
    await _waitForAiIdle();
    try {
      await old?.dispose().timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('[CameraSetup] dispose during lens flip failed: $e');
    }
    if (!mounted) return;
    await initializeCamera();
  }

  // --- AI Detection ---

  Future<void> _initAiDetection() async {
    // The play gate requires a loaded model (AI is a core feature), so a
    // failed load can't just give up — keep retrying with backoff while the
    // screen is up. Each native call is time-bounded (NativeInference
    // timeouts), so one wedged attempt can't hang this loop.
    var attempt = 0;
    while (mounted && !aiModelLoaded) {
      try {
        _nativeInference?.dispose();
        _nativeInference = NativeInference();
        await _nativeInference!.loadModel();
        if (!mounted) return;
        if (_nativeInference!.isLoaded) {
          setState(() => aiModelLoaded = true);
          _startAiCapture();
          return;
        }
      } catch (e) {
        debugPrint(
            '[CameraSetup] AI detection init failed (attempt ${attempt + 1}): $e');
      }
      attempt++;
      await Future.delayed(
          Duration(milliseconds: (600 * attempt).clamp(600, 5000)));
    }
  }

  void _startAiCapture() {
    if (_aiCapturing || !aiModelLoaded) return;
    _aiCapturing = true;
    _runAiCaptureLoop();
  }

  /// Keep the latest camera frame cached for the AI loop. The persistent
  /// image stream replaces the old silentCapture start/stop churn (2×/s),
  /// which both burned CPU for nothing (YUV→RGB pixel loop in Dart + JPEG
  /// encode + file write + native JPEG decode per capture) and could wedge
  /// the camera plugin when a dispose raced an in-flight stream toggle.
  void _startAiFrameStream() {
    final controller = cameraController;
    if (_aiFrameStreamActive ||
        controller == null ||
        !controller.value.isInitialized ||
        controller.value.isStreamingImages) {
      return;
    }
    try {
      controller.startImageStream((image) => _latestAiFrame = image);
      _aiFrameStreamActive = true;
    } catch (e) {
      debugPrint('[CameraSetup] startImageStream failed: $e');
    }
  }

  void _stopAiFrameStream() {
    final controller = cameraController;
    _latestAiFrame = null;
    if (!_aiFrameStreamActive) return;
    _aiFrameStreamActive = false;
    try {
      if (controller != null &&
          controller.value.isInitialized &&
          controller.value.isStreamingImages) {
        controller.stopImageStream();
      }
    } catch (e) {
      debugPrint('[CameraSetup] stopImageStream failed: $e');
    }
  }

  Future<void> _runAiCaptureLoop() async {
    while (_aiCapturing && mounted && aiModelLoaded) {
      if (cameraReady && cameraController != null) {
        // (Re-)attach the frame stream — idempotent, and needed both when the
        // camera becomes ready after the model loaded and after a lens flip.
        _startAiFrameStream();
        await _runAiCapture();
      }
      if (!_aiCapturing || !mounted) break;
      await Future.delayed(
        Platform.isAndroid
            ? const Duration(milliseconds: 500)
            : const Duration(milliseconds: 200),
      );
    }
  }

  /// Analyze a raw camera frame through the same native path the in-game
  /// scorer uses — no JPEG/file round-trip. Android sends the YUV planes
  /// (rotation 0, matching the old unrotated JPEG path); iOS sends the BGRA
  /// bytes and native does the channel swap on its background queue.
  Future<ScoringResult> _analyzeSetupFrame(CameraImage frame) {
    if (Platform.isAndroid) {
      return _nativeInference!.analyzeYuv(
        yPlane: frame.planes[0].bytes,
        uPlane: frame.planes[1].bytes,
        vPlane: frame.planes[2].bytes,
        width: frame.width,
        height: frame.height,
        yRowStride: frame.planes[0].bytesPerRow,
        uvRowStride: frame.planes[1].bytesPerRow,
        uvPixelStride: frame.planes[1].bytesPerPixel ?? 1,
        rotation: 0,
      );
    }
    final plane = frame.planes[0];
    final w = frame.width;
    final h = frame.height;
    final stride = plane.bytesPerRow;
    var bgra = plane.bytes;
    if (stride != w * 4) {
      // Strip row padding — native expects tightly packed rows.
      final tight = Uint8List(w * h * 4);
      final rowBytes = w * 4;
      for (int y = 0; y < h; y++) {
        tight.setRange(y * rowBytes, y * rowBytes + rowBytes, bgra, y * stride);
      }
      bgra = tight;
    }
    return _nativeInference!.analyzeRgba(bgra, w, h, isBgra: true);
  }

  Future<void> _runAiCapture() async {
    final l10n = AppLocalizations.of(context);
    if (_aiAnalyzing) return;
    if (_nativeInference == null || !aiModelLoaded) return;
    final frame = _latestAiFrame;
    if (frame == null) return;
    _aiAnalyzing = true;
    try {
      final result = await _analyzeSetupFrame(frame);
      if (!mounted) return;
      final calibs = result.calibrationPoints;
      String? hint;
      bool detected = false;
      if (calibs.length < 4) {
        hint = calibs.isEmpty
            ? l10n.dartboardNotDetected
            : l10n.boardNotFullyVisible;
        detected = false;
      } else {
        double minX = 1, maxX = 0, minY = 1, maxY = 0;
        for (final c in calibs) {
          if (c.x < minX) minX = c.x;
          if (c.x > maxX) maxX = c.x;
          if (c.y < minY) minY = c.y;
          if (c.y > maxY) maxY = c.y;
        }
        final spread =
            (maxX - minX) > (maxY - minY) ? (maxX - minX) : (maxY - minY);
        // Match the in-game scorer's tolerance (auto_scoring_service._updateZoomHint).
        // Setup used to demand >= 0.50 spread, which forced users to zoom in
        // past what the AI actually needs to score reliably (0.35).
        if (spread < 0.35) {
          hint = l10n.zoomInBoardTooFar;
          detected = false;
        } else if (spread > 0.85) {
          hint = l10n.zoomOutBoardTooClose;
          detected = false;
        } else {
          hint = null;
          detected = true;
        }
      }
      setState(() {
        aiHint = hint;
        boardDetected = detected;
      });
    } catch (e) {
      debugPrint('[CameraSetup] AI capture error: $e');
    } finally {
      _aiAnalyzing = false;
    }
  }

  // --- Zoom Controls ---

  void onScaleStart(ScaleStartDetails details) {
    _baseZoom = currentZoom;
  }

  Future<void> onScaleUpdate(ScaleUpdateDetails details) async {
    if (details.scale == 1.0) return;
    final newZoom = (_baseZoom * details.scale).clamp(minZoom, maxZoom);
    await cameraController?.setZoomLevel(newZoom);
    setState(() => currentZoom = newZoom);
  }

  Future<void> zoomIn() async {
    final newZoom = (currentZoom + 0.1).clamp(minZoom, maxZoom);
    await cameraController?.setZoomLevel(newZoom);
    setState(() => currentZoom = newZoom);
  }

  Future<void> zoomOut() async {
    final newZoom = (currentZoom - 0.1).clamp(minZoom, maxZoom);
    await cameraController?.setZoomLevel(newZoom);
    setState(() => currentZoom = newZoom);
  }

  // --- Shared UI Builders ---

  /// Builds the camera preview with a border, full-width fitted preview,
  /// zoom controls, and a customizable overlay.
  /// [overlayChildren] are placed inside the status overlay container
  /// after the "Camera ready" row.
  Widget buildCameraPreview({List<Widget> overlayChildren = const []}) {
    final l10n = AppLocalizations.of(context);
    if (cameraController == null || !cameraController!.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    // CameraController reports previewSize in the sensor's natural (landscape)
    // orientation. In portrait we have to swap width/height so the FittedBox
    // covers correctly; in landscape we use the natural values.
    final previewW = isLandscape
        ? cameraController!.value.previewSize!.width
        : cameraController!.value.previewSize!.height;
    final previewH = isLandscape
        ? cameraController!.value.previewSize!.height
        : cameraController!.value.previewSize!.width;

    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.primary, width: 2),
      ),
      child: GestureDetector(
        onScaleStart: cameraSetupConfig.enableGestureZoom ? onScaleStart : null,
        onScaleUpdate:
            cameraSetupConfig.enableGestureZoom ? onScaleUpdate : null,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            children: [
              SizedBox.expand(
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: previewW,
                    height: previewH,
                    child: CameraPreview(cameraController!),
                  ),
                ),
              ),
              Positioned(
                top: 16,
                left: 16,
                right: 16,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: AppTheme.primary.withValues(alpha: 0.5)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: const BoxDecoration(
                              color: AppTheme.success,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            l10n.cameraReady,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      ...overlayChildren,
                      if (aiModelLoaded) ...[
                        const SizedBox(height: 10),
                        buildAiStatusOverlay(l10n),
                      ],
                    ],
                  ),
                ),
              ),
              Positioned(
                right: 12,
                top: 0,
                bottom: 0,
                child: buildZoomControls(),
              ),
              if (canFlipCamera)
                Positioned(
                  left: 12,
                  bottom: 12,
                  child: buildCameraFlipButton(),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Circular button that flips between the front and back camera. Only shown
  /// (via [canFlipCamera]) when the device actually has both lenses.
  Widget buildCameraFlipButton() {
    final isFront = cameraLensDirection == CameraLensDirection.front;
    return GestureDetector(
      onTap: toggleCameraLens,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: isFront
              ? AppTheme.primary.withValues(alpha: 0.85)
              : Colors.black.withValues(alpha: 0.6),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
        ),
        child: const Icon(Icons.cameraswitch, color: Colors.white, size: 22),
      ),
    );
  }

  Widget buildLoadingView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(
            color: AppTheme.primary,
            strokeWidth: 3,
          ),
          const SizedBox(height: 24),
          Text(
            AppLocalizations.of(context).initializingCamera,
            style:
                AppTheme.bodyLarge.copyWith(color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget buildErrorView() {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppTheme.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.error, width: 2),
              ),
              child: const Icon(
                Icons.videocam_off,
                color: AppTheme.error,
                size: 80,
              ),
            ),
            const SizedBox(height: 32),
            Text(
              l10n.cameraRequired,
              style: AppTheme.displayMedium.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              errorMessage ?? l10n.unknownError,
              style: AppTheme.bodyLarge
                  .copyWith(color: AppTheme.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: initializeCamera,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  l10n.tryAgain,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildZoomControls() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        buildZoomButton(Icons.add, zoomIn),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            '${currentZoom.toStringAsFixed(1)}x',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              shadows: [Shadow(color: Colors.black, blurRadius: 4)],
            ),
          ),
        ),
        buildZoomButton(Icons.remove, zoomOut),
      ],
    );
  }

  Widget buildZoomButton(IconData icon, VoidCallback onPressed) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }

  Widget buildAiStatusOverlay(AppLocalizations l10n) {
    if (!aiModelLoaded) return const SizedBox.shrink();
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: (aiHint == null && boardDetected)
            ? AppTheme.success.withValues(alpha: 0.2)
            : (aiHint != null)
                ? AppTheme.error.withValues(alpha: 0.2)
                : AppTheme.accent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: (aiHint == null && boardDetected)
              ? AppTheme.success
              : (aiHint != null)
                  ? AppTheme.error
                  : AppTheme.accent,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            (aiHint == null && boardDetected)
                ? Icons.check_circle
                : (aiHint != null)
                    ? Icons.warning_rounded
                    : Icons.smart_toy_outlined,
            color: (aiHint == null && boardDetected)
                ? AppTheme.success
                : (aiHint != null)
                    ? AppTheme.error
                    : AppTheme.accent,
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              (aiHint == null && boardDetected)
                  ? l10n.dartboardDetectedGoodPosition
                  : aiHint ?? l10n.scanningForDartboard,
              style: TextStyle(
                color: (aiHint == null && boardDetected)
                    ? AppTheme.success
                    : (aiHint != null)
                        ? AppTheme.error
                        : AppTheme.accent,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildInfoRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, color: AppTheme.textSecondary, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: AppTheme.bodyLarge
                .copyWith(color: AppTheme.textSecondary, fontSize: 14),
          ),
        ),
      ],
    );
  }

  PreferredSizeWidget buildCameraAppBar(String title) {
    return AppBar(
      backgroundColor: AppTheme.surface,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.white),
        onPressed: () {
          HapticService.lightImpact();
          Navigator.of(context).pop();
        },
      ),
      title: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
          letterSpacing: 1,
        ),
      ),
      centerTitle: true,
    );
  }

  /// Save zoom and dispose camera before navigating away.
  Future<void> prepareForNavigation() async {
    // Stop the AI loop and detach the frame stream BEFORE touching the
    // controller: disposing while the stream is being toggled can wedge the
    // camera plugin — the dispose below then never returns and the user is
    // stuck on the setup screen with a dead preview (spinner).
    _aiCapturing = false;
    _stopAiFrameStream();
    await StorageService.saveCameraZoom(currentZoom);
    await _waitForAiIdle();
    final controller = cameraController;
    cameraController = null;
    if (controller != null) {
      try {
        await controller.dispose().timeout(const Duration(seconds: 5));
      } catch (e) {
        // Proceed with navigation anyway — the next screen's camera open
        // retries while the device finishes releasing.
        debugPrint('[CameraSetup] dispose before navigation failed: $e');
      }
    }
  }
}
