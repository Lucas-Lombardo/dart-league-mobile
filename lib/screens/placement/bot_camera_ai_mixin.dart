import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../services/auto_scoring_service.dart';
import '../../services/camera_frame_service.dart';
import '../../services/dart_scoring_service.dart';
import '../../utils/haptic_service.dart';
import '../../utils/storage_service.dart';

/// Local-camera auto-scoring plumbing shared by the single-phone screens (X01
/// placement/bot-training, bot cricket, local hot-seat cricket): camera + AI
/// init, capture start/stop, the manual AI toggle, zoom and lens switching.
/// Single-phone means no RTC viewer: the camera runs a continuous image
/// stream and caches the latest frame for the AI loop, which is stopped
/// whenever nothing consumes it.
///
/// Screens keep their own lifecycle observer and dispose order, implement the
/// two detection hooks, and may hook diagnostics into
/// [onCameraAiReady]/[onCameraAiInitFailed] (the X01 screen's placement debug
/// capture does).
mixin BotCameraAiMixin<T extends StatefulWidget> on State<T> {
  CameraFrameService? cameraService;
  AutoScoringService? autoScoringService;

  /// True once [initCameraAndAI] decided this device supports auto-scoring —
  /// the lifecycle-resume guard, so a resume before init never starts capture.
  bool autoScoringEnabled = false;
  bool autoScoringLoading = false;
  bool aiManuallyDisabled = false;
  bool aiPausedForEdit = false;
  bool switchingCamera = false;
  double cameraZoom = 1.0;
  double cameraMinZoom = 1.0;
  double cameraMaxZoom = 1.0;

  /// A dart landed, or an already-tracked slot's prediction was refined.
  void onAiDartDetected(int slotIndex, DartScore dartScore);

  /// The AI auto-validated a full visit (mounted-checked, haptic done).
  void onAiAutoConfirm();

  /// Successful init (camera up, model load attempted).
  void onCameraAiReady() {}

  /// Init failed at [stage]: 'camera_init_failed' or 'ai_init_threw'.
  void onCameraAiInitFailed(String stage) {}

  Future<void> initCameraAndAI() async {
    if (kIsWeb) return;
    if (!AutoScoringService.isSupported) return;
    if (!mounted) return;
    setState(() {
      autoScoringEnabled = true;
      autoScoringLoading = true;
    });

    try {
      final camera = CameraFrameService();
      await camera.initialize();
      if (!mounted) {
        await camera.dispose();
        return;
      }
      if (!camera.isInitialized) {
        await camera.dispose();
        onCameraAiInitFailed('camera_init_failed');
        if (mounted) setState(() => autoScoringLoading = false);
        return;
      }
      cameraService = camera;
      // Stop the 30fps image stream whenever the AI loop is off — nothing
      // else consumes the frames in solo mode.
      autoScoringService?.onCaptureActiveChanged = camera.setAiActive;

      try {
        final minZoom = await camera.getMinZoomLevel();
        final maxZoom = await camera.getMaxZoomLevel();
        final savedZoom = await StorageService.getCameraZoom();
        final clampedZoom = savedZoom.clamp(minZoom, maxZoom);
        await camera.setZoomLevel(clampedZoom);
        if (mounted) {
          setState(() {
            cameraMinZoom = minZoom;
            cameraMaxZoom = maxZoom;
            cameraZoom = clampedZoom;
          });
        }
      } catch (e) {
        debugPrint('[BotCameraAi] Zoom config failed: $e');
      }

      await autoScoringService!.loadModel();
      if (!mounted) return;
      setState(() => autoScoringLoading = false);
      if (autoScoringService!.modelLoaded) startAiCapture();
      onCameraAiReady();
    } catch (_) {
      onCameraAiInitFailed('ai_init_threw');
      if (mounted) setState(() => autoScoringLoading = false);
    }
  }

  void startAiCapture() {
    if (autoScoringService == null || cameraService == null) return;
    if (aiManuallyDisabled || aiPausedForEdit) return;
    final camera = cameraService!;
    autoScoringService!.startCapture(
      captureFrame: () => camera.captureFrame(),
      captureRgba: () => camera.captureRgba(),
      captureBgra: () => camera.captureBgra(),
      captureYuv: () => camera.captureYuvPlanes(),
      cleanupFile: (path) async {
        try {
          await File(path).delete();
        } catch (_) {}
      },
      onDartDetected: onAiDartDetected,
      onAutoConfirm: () {
        if (mounted) {
          HapticService.heavyImpact();
          onAiAutoConfirm();
        }
      },
    );
  }

  void stopAiCapture() {
    autoScoringService?.stopCapture();
  }

  void toggleAi() {
    if (!mounted) return;
    setState(() {
      aiManuallyDisabled = !aiManuallyDisabled;
      if (aiManuallyDisabled) {
        stopAiCapture();
      } else if (autoScoringService?.modelLoaded == true) {
        startAiCapture();
      }
    });
  }

  Future<void> zoomIn() async {
    if (cameraService == null) return;
    final next = (cameraZoom + 0.1).clamp(cameraMinZoom, cameraMaxZoom);
    try {
      await cameraService!.setZoomLevel(next);
      if (mounted) setState(() => cameraZoom = next);
    } catch (_) {}
  }

  Future<void> zoomOut() async {
    if (cameraService == null) return;
    final next = (cameraZoom - 0.1).clamp(cameraMinZoom, cameraMaxZoom);
    try {
      await cameraService!.setZoomLevel(next);
      if (mounted) setState(() => cameraZoom = next);
    } catch (_) {}
  }

  Future<void> switchCamera() async {
    final svc = cameraService;
    if (svc == null || switchingCamera) return;
    HapticService.lightImpact();
    setState(() => switchingCamera = true);
    try {
      await svc.switchCamera();
      // Refresh the zoom bounds for the new lens (front cameras often can't zoom).
      try {
        final minZoom = await svc.getMinZoomLevel();
        final maxZoom = await svc.getMaxZoomLevel();
        final clamped = cameraZoom.clamp(minZoom, maxZoom);
        await svc.setZoomLevel(clamped);
        if (mounted) {
          setState(() {
            cameraMinZoom = minZoom;
            cameraMaxZoom = maxZoom;
            cameraZoom = clamped;
          });
        }
      } catch (_) {}
    } finally {
      if (mounted) setState(() => switchingCamera = false);
    }
  }

  /// Tears down capture, model and camera. Call from dispose() after any
  /// screen-specific teardown that still reads the services.
  void disposeCameraAndAI() {
    stopAiCapture();
    autoScoringService?.dispose();
    autoScoringService = null;
    cameraService?.dispose();
    cameraService = null;
  }
}
