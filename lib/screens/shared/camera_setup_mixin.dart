import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../l10n/app_localizations.dart';
import '../../services/detection_isolate_stub.dart'
    if (dart.library.io) '../../services/detection_isolate.dart';
import '../../utils/app_theme.dart';
import '../../utils/haptic_service.dart';
import '../../utils/silent_capture.dart';
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
  bool isLoading = true;
  bool permissionsGranted = false;
  bool cameraReady = false;
  String? errorMessage;
  double currentZoom = 1.0;
  double minZoom = 1.0;
  double maxZoom = 1.0;
  double _baseZoom = 1.0;

  // AI dartboard detection
  DetectionIsolate? _detectionIsolate;
  bool aiModelLoaded = false;
  String? aiHint;
  bool boardDetected = false;
  bool _aiCapturing = false;
  bool _aiAnalyzing = false;

  /// Override to customize camera setup behavior.
  CameraSetupConfig get cameraSetupConfig => const CameraSetupConfig();

  /// Whether the play/ready button should be enabled.
  bool get canPlay {
    if (!permissionsGranted || !cameraReady) return false;
    if (aiModelLoaded && !boardDetected) return false;
    return true;
  }

  /// Label for the play/ready button based on current state.
  String getPlayButtonLabel(AppLocalizations l10n) {
    if (!permissionsGranted || !cameraReady) return l10n.cameraRequiredButton;
    if (aiModelLoaded && !boardDetected) {
      return aiHint != null ? aiHint!.toUpperCase() : l10n.scanningButton;
    }
    return l10n.play.toUpperCase();
  }

  /// Call from initState to start camera and optional AI detection.
  void initCamera() {
    if (cameraSetupConfig.enableAiDetection && !kIsWeb) {
      _initAiDetection();
    }
  }

  /// Call from dispose to clean up resources.
  void disposeCamera() {
    _aiCapturing = false;
    _detectionIsolate?.dispose();
    _detectionIsolate = null;
    cameraController?.dispose();
  }

  /// Handle app lifecycle changes for AI capture.
  void handleAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _aiCapturing = false;
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

      final backCamera = cameras!.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras!.first,
      );

      cameraController = CameraController(
        backCamera,
        ResolutionPreset.high,
        enableAudio: false,
      );

      await cameraController!.initialize();

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

  // --- AI Detection ---

  Future<void> _initAiDetection() async {
    try {
      _detectionIsolate = DetectionIsolate();
      await _detectionIsolate!.start();
      if (mounted) {
        setState(() => aiModelLoaded = true);
        _startAiCapture();
      }
    } catch (e) {
      debugPrint('[CameraSetup] AI detection init failed: $e');
    }
  }

  void _startAiCapture() {
    if (_aiCapturing || !aiModelLoaded) return;
    _aiCapturing = true;
    _runAiCaptureLoop();
  }

  Future<void> _runAiCaptureLoop() async {
    while (_aiCapturing && mounted && aiModelLoaded) {
      if (cameraReady && cameraController != null) {
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

  Future<void> _runAiCapture() async {
    final l10n = AppLocalizations.of(context);
    if (_aiAnalyzing) return;
    if (_detectionIsolate == null || !aiModelLoaded) return;
    if (cameraController == null ||
        !cameraController!.value.isInitialized) {
      return;
    }
    _aiAnalyzing = true;
    try {
      final imagePath = await silentCapture(cameraController!);
      if (imagePath == null || !mounted) {
        if (imagePath != null) {
          try {
            await File(imagePath).delete();
          } catch (e) {
            debugPrint('[CameraSetup] File cleanup failed: $e');
          }
        }
        return;
      }
      final result = await _detectionIsolate!.analyze(imagePath);
      try {
        await File(imagePath).delete();
      } catch (e) {
        debugPrint('[CameraSetup] File cleanup failed: $e');
      }
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
        if (spread < 0.50) {
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
                    width: cameraController!.value.previewSize!.height,
                    height: cameraController!.value.previewSize!.width,
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
            ],
          ),
        ),
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
    await StorageService.saveCameraZoom(currentZoom);
    await cameraController?.dispose();
    cameraController = null;
  }
}
