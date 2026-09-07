import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../l10n/app_localizations.dart';
import '../../services/board_framing.dart';
import '../../services/camera_frame_service.dart';
import '../../services/dart_detection_service_stub.dart'
    if (dart.library.io) '../../services/dart_detection_service.dart';
import '../../services/native_inference.dart';
import '../../widgets/board_placement_guide.dart';
import '../../widgets/board_safe_video.dart';
import '../../widgets/design_system.dart';
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
  bool boardDetected = false;
  // Framing state driving the setup overlay pill.
  GuideState guideState = GuideState.searching;
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

  /// Label for the play/ready button. Kept SHORT on purpose: the placement
  /// guide's pill narrates what to do — mirroring the hint here turned the
  /// CTA into a broken two-line banner.
  String getPlayButtonLabel(AppLocalizations l10n) {
    if (!permissionsGranted || !cameraReady) {
      return dsSentence(l10n.cameraRequiredButton);
    }
    if (cameraSetupConfig.enableAiDetection && !kIsWeb && !aiModelLoaded) {
      return l10n.loadingAi;
    }
    return l10n.play;
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
          // Cap the sensor like the in-game pipeline (thermal audit
          // 2026-08-10): these screens ran at the ~30 fps sensor default
          // while analysing 2–5 frames/s — pure pre-match heat soak, so the
          // phone reached the OS throttling threshold before the first dart.
          fps: CameraFrameService.cameraFps,
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
        guideState = GuideState.searching;
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
  Future<void> _startAiFrameStream() async {
    final controller = cameraController;
    if (_aiFrameStreamActive ||
        controller == null ||
        !controller.value.isInitialized ||
        controller.value.isStreamingImages) {
      return;
    }
    // Claim the slot before awaiting so a second loop iteration can't fire a
    // concurrent start on the same controller.
    _aiFrameStreamActive = true;
    try {
      await controller.startImageStream((image) => _latestAiFrame = image);
    } catch (e) {
      // Release the slot so the next loop iteration retries. startImageStream
      // reports failure asynchronously, so the previously un-awaited call left
      // the flag set on a stream that never started: no frame ever reached the
      // AI loop, the guide stayed on "searching" and the player could not
      // leave setup. Seen on a Pixel 8 (NPE in Camera.startCapture) 2026-08-14.
      _aiFrameStreamActive = false;
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
        await _startAiFrameStream();
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

  /// Clockwise rotation applied to the raw frame before inference. Android
  /// delivers image-stream frames in FIXED sensor coordinates, so on a
  /// portrait phone (sensorOrientation 90) the board reaches the model lying
  /// on its side — measured on a Pixel 8 (2026-08-14): 1–2 calibration points
  /// on the raw frame against 4 on every single rotated frame of the same
  /// scene. That starved the framing gate and pinned the screen on "board not
  /// fully visible" with a perfectly centered board, so Android players could
  /// never leave setup. Same rotation the in-game pipeline uses, from the
  /// same helper. iOS keeps 0: its plugin already delivers frames rotated to
  /// the device orientation, and rotating again would tip the board over.
  int get _setupAnalysisRotation {
    if (!Platform.isAndroid) return 0;
    final controller = cameraController;
    if (controller == null) return 0;
    return CameraFrameService.uprightRotationFor(
      sensorOrientation: controller.description.sensorOrientation,
      deviceOrientation: controller.value.deviceOrientation,
      isFrontFacing:
          controller.description.lensDirection == CameraLensDirection.front,
    );
  }

  /// Analyze a raw camera frame through the same native path the in-game
  /// scorer uses — no JPEG/file round-trip. Android sends the YUV planes
  /// (rotated board-upright, see [_setupAnalysisRotation]); iOS sends the
  /// BGRA bytes and native does the channel swap on its background queue.
  Future<ScoringResult> _analyzeSetupFrame(CameraImage frame, int rotation) {
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
        rotation: rotation,
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
    if (_aiAnalyzing) return;
    if (_nativeInference == null || !aiModelLoaded) return;
    final frame = _latestAiFrame;
    if (frame == null) return;
    _aiAnalyzing = true;
    try {
      final rotation = _setupAnalysisRotation;
      final result = await _analyzeSetupFrame(frame, rotation);
      if (!mounted) return;
      final calibs = result.calibrationPoints;
      // Cache-served calibration must never validate framing (it once let a
      // 2.5× half-board pass the gate) — treat it like an unusable frame.
      final framing = result.calibrationFromCache
          ? null
          : BoardFraming.compute(calibs,
              imageWidth: result.imageWidth, imageHeight: result.imageHeight);
      // Prime the replay ring's orientation hint before the match screen even
      // opens. The tilt is measured in the ANALYZED frame, so the rotation we
      // applied to get there has to travel with it (see
      // CameraFrameService.reportBoardTilt).
      if (framing?.tiltDegrees != null && Platform.isAndroid) {
        CameraFrameService.reportBoardTilt(
          analysisRotation: rotation,
          tiltDegrees: framing!.tiltDegrees!,
        );
      }

      // ── Framing states — size only, like before the placement guide ──
      // The position checks (fully-visible circle, centering, direction
      // chevrons) once nagged the user to "move" forever, because the frame
      // reaching the model was sensor-oriented — now fixed at the source in
      // [_setupAnalysisRotation]. Guidance stays zoom-only regardless: it is
      // the one instruction a mounted phone can actually act on.
      // Same spread zone as the in-game hints (kZoomSpreadMin/Max).
      final GuideState state;
      if (framing == null) {
        state = calibs.isEmpty ? GuideState.searching : GuideState.cut;
      } else if (framing.spread > kZoomSpreadMax) {
        state = GuideState.tooClose;
      } else if (framing.spread < kZoomSpreadMin) {
        state = GuideState.tooFar;
      } else {
        state = GuideState.locked;
      }

      // One line per state CHANGE (not per frame): enough to tell a framing
      // complaint apart from a detection failure without flooding the log.
      if (state != guideState) {
        debugPrint('[CameraSetup] guide ${guideState.name} -> ${state.name} '
            'rotation=$rotation calibs=${calibs.length} '
            'spread=${framing?.spread.toStringAsFixed(2) ?? '-'} '
            'cache=${result.calibrationFromCache}');
      }

      final locked = state == GuideState.locked;
      if (locked && !boardDetected) HapticService.heavyImpact();
      setState(() {
        guideState = state;
        boardDetected = locked;
      });
    } catch (e) {
      debugPrint('[CameraSetup] AI capture error: $e');
    } finally {
      _aiAnalyzing = false;
    }
  }

  /// Text of the guide's status pill — one clear instruction per state.
  String _guideStatusText(AppLocalizations l10n) {
    return switch (guideState) {
      GuideState.searching => l10n.dartboardNotDetected,
      GuideState.cut => l10n.boardNotFullyVisible,
      GuideState.tooFar => l10n.zoomInBoardTooFar,
      GuideState.tooClose => l10n.zoomOutBoardTooClose,
      GuideState.locked => l10n.boardLocked,
    };
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
  Widget buildCameraPreview() {
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
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppTheme.primary, width: 1.5),
      ),
      child: GestureDetector(
        onScaleStart: cameraSetupConfig.enableGestureZoom ? onScaleStart : null,
        onScaleUpdate:
            cameraSetupConfig.enableGestureZoom ? onScaleUpdate : null,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppTheme.radiusCard - 1.5),
          child: Stack(
            children: [
              // Not cover: this screen's whole job is "is the board fully in
              // frame?", and a preview cropped without limit answers it about
              // a frame the model never sees — the player lines the board up
              // inside a picture whose edges were thrown away. BoardSafeVideo
              // only ever crops outside the board's square, so what they judge
              // is what is analyzed.
              SizedBox.expand(
                child: BoardSafeVideo(
                  sourceWidth: previewW,
                  sourceHeight: previewH,
                  child: CameraPreview(cameraController!),
                ),
              ),
              Positioned(
                right: 12,
                top: 0,
                bottom: 0,
                child: buildZoomControls(),
              ),
              // The "cercle fantôme" placement guide — replaces the old side
              // gauge + auto-frame button (validated design 2026-08-09).
              if (aiModelLoaded && cameraSetupConfig.enableAiDetection)
                Positioned.fill(
                  child: IgnorePointer(
                    child: BoardPlacementGuide(
                      state: guideState,
                      statusText: _guideStatusText(l10n),
                    ),
                  ),
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
    return _glassButton(
      icon: Icons.cameraswitch_outlined,
      onTap: toggleCameraLens,
      active: isFront,
    );
  }

  /// 40 px "glass" control laid over the live preview: translucent white
  /// disc and hairline, light icon. [active] tints it primary (the front
  /// lens being selected).
  Widget _glassButton({
    required IconData icon,
    required VoidCallback onTap,
    bool active = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: active
              ? AppTheme.primary.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.08),
          shape: BoxShape.circle,
          border: Border.all(
            color: active
                ? AppTheme.primaryLight
                : Colors.white.withValues(alpha: 0.10),
          ),
        ),
        child: Icon(
          icon,
          color: active ? AppTheme.primaryLight : const Color(0xFFE2E8F0),
          size: 20,
        ),
      ),
    );
  }

  Widget buildLoadingView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              color: AppTheme.primary,
              strokeWidth: 2.5,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            AppLocalizations.of(context).initializingCamera,
            style: AppTheme.caption.copyWith(fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget buildErrorView() {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: DsCard(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.videocam_off_outlined,
                color: AppTheme.error,
                size: 40,
              ),
              const SizedBox(height: 14),
              Text(
                dsSentence(l10n.cameraRequired),
                style: AppTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                errorMessage ?? l10n.unknownError,
                style: AppTheme.caption.copyWith(height: 1.4),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: initializeCamera,
                  child: Text(dsSentence(l10n.tryAgain)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget buildZoomControls() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        buildZoomButton(Icons.add_rounded, zoomIn),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            '${currentZoom.toStringAsFixed(1)}×',
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              fontFeatures: [FontFeature.tabularFigures()],
              // Legibility over a bright live frame — not decoration.
              shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
            ),
          ),
        ),
        buildZoomButton(Icons.remove_rounded, zoomOut),
      ],
    );
  }

  Widget buildZoomButton(IconData icon, VoidCallback onPressed) {
    return _glassButton(icon: icon, onTap: onPressed);
  }

  /// Centered 13 / 500 caption with a 16 px leading icon (the "camera
  /// required for AI scoring" line under the preview).
  Widget buildInfoRow(IconData icon, String text) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: AppTheme.textSecondary, size: 16),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: AppTheme.caption.copyWith(fontSize: 13),
          ),
        ),
      ],
    );
  }

  /// Flat, left-aligned 22 / 800 title (the theme's AppBar) in sentence case
  /// — legacy ALL-CAPS titles pass through [dsSentence].
  PreferredSizeWidget buildCameraAppBar(String title) {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
        onPressed: () {
          HapticService.lightImpact();
          Navigator.of(context).pop();
        },
      ),
      title: Text(dsSentence(title)),
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
