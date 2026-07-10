import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show DeviceOrientation;
import 'package:path_provider/path_provider.dart';
import 'package:image/image.dart' as img;

import 'agora_service.dart';
import '../utils/storage_service.dart';

/// Owns the Flutter camera during gameplay and distributes frames to both
/// Agora (for video calling) and AI scoring (for dart detection).
///
/// This mirrors DartsMind's approach: the app controls the camera via CameraX
/// (here Flutter's camera package) and pushes custom frames to Agora instead
/// of letting Agora control the camera directly.
class CameraFrameService {
  CameraController? _controller;
  int? _videoTrackId;
  RtcEngine? _agoraEngine;
  bool _isStreaming = false;
  bool _disposed = false;

  // Throttle: only push every other frame to keep at ~15fps
  int _frameCount = 0;
  static const int _frameSkip = 1; // push every 2nd frame (30fps camera -> 15fps push)

  // Cache the latest frame for AI scoring capture
  CameraImage? _latestFrame;
  int? _sensorOrientation;
  bool _firstPushLogged = false;
  DeviceOrientation? _lastLoggedOrientation;

  // Which physical lens is currently open. Follows the persisted preference on
  // start and flips via [switchCamera].
  CameraLensDirection _lensDirection = CameraLensDirection.back;
  bool _switching = false;

  CameraController? get controller => _controller;
  bool get isInitialized => _controller?.value.isInitialized ?? false;
  CameraLensDirection get lensDirection => _lensDirection;

  // --- ANDROID-ONLY device-orientation-aware frame rotation -----------------
  // Android delivers image-stream frames in FIXED sensor coordinates that do
  // NOT follow the device's physical rotation, so in landscape the board ends
  // up sideways (90°/270°) and the detector loses calibration points. We
  // compensate for the current physical orientation so the board is always fed
  // to the model upright (0°) or flipped (180°) — both of which it handles —
  // but never sideways.
  //
  // iOS uses NONE of this. Its camera plugin already delivers frames rotated to
  // the active device orientation, so the board is upright at 0° in every
  // orientation. The iOS capture paths pass a hard-coded 0 and are kept
  // byte-for-byte identical to the pre-landscape behaviour — applying any
  // rotation there would tip the already-upright board sideways (a 20 read as
  // a 6).

  /// Physical device rotation away from portraitUp, in degrees (Android only).
  int _deviceRotationDegrees() {
    switch (_controller?.value.deviceOrientation) {
      case DeviceOrientation.landscapeRight:
        return 90;
      case DeviceOrientation.portraitDown:
        return 180;
      case DeviceOrientation.landscapeLeft:
        return 270;
      case DeviceOrientation.portraitUp:
      default:
        return 0;
    }
  }

  /// ANDROID-ONLY clockwise rotation (degrees) for the raw sensor frame so the
  /// board is upright — for the model AND as the Agora push rotation metadata
  /// (both share the same "rotate CW to upright" semantic). Portrait returns
  /// the sensor mount angle (the previously-shipped value); landscape
  /// compensates for the device's physical rotation so the board lands
  /// upright/flipped, never sideways.
  /// Must never be called on the iOS paths — those pass a literal 0.
  int _effectiveRotation() {
    final baseline = _sensorOrientation ?? 0;
    final o = _controller?.value.deviceOrientation;
    int rot = baseline;
    if (o == DeviceOrientation.landscapeLeft ||
        o == DeviceOrientation.landscapeRight) {
      // In landscape the board was coming out 180° upside-down (20 scored as
      // 3), so we add 180 to land it upright. CRITICAL: only an upright (0°)
      // frame scores correctly — 180° inverts the whole board — so this must
      // resolve to upright. Both landscape orientations need the same +180
      // here because they produce the same (inverted) frame.
      rot = (baseline - _deviceRotationDegrees() + 180 + 360) % 360;
    }
    if (o != _lastLoggedOrientation) {
      _lastLoggedOrientation = o;
      debugPrint('[CameraFrameService] deviceOrientation=$o '
          'sensor=$_sensorOrientation effectiveRotation=$rot');
    }
    return rot;
  }

  /// Initialize the camera. When [agoraEngine] is non-null, also pushes frames
  /// to the given custom video track. Pass nulls for solo modes (training,
  /// placement) where the local camera preview is shown directly via the
  /// exposed [controller] and only AI scoring needs the frame stream.
  Future<void> initialize({
    RtcEngine? agoraEngine,
    int? videoTrackId,
  }) async {
    _agoraEngine = agoraEngine;
    _videoTrackId = videoTrackId;

    // Honour the persisted front/back choice (set from the camera-setup screen
    // or a previous in-game switch). Defaults to the back camera.
    final useFront = await StorageService.getUseFrontCamera();
    final requested =
        useFront ? CameraLensDirection.front : CameraLensDirection.back;

    if (!await _openCamera(requested)) return;
    if (_disposed) return;

    // Start the image stream — each frame goes to Agora + cached for AI
    _startImageStream();
  }

  /// Open (or re-open) the physical camera for the given [requested] lens.
  /// Falls back to the back camera, then any camera, when that lens is
  /// unavailable, and records the lens actually opened in [_lensDirection] /
  /// [_sensorOrientation]. Returns false if no camera could be initialised.
  Future<bool> _openCamera(CameraLensDirection requested) async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      debugPrint('[CameraFrameService] No cameras available');
      return false;
    }

    final selected = cameras.firstWhere(
      (c) => c.lensDirection == requested,
      orElse: () => cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      ),
    );
    _lensDirection = selected.lensDirection;
    _sensorOrientation = selected.sensorOrientation;
    debugPrint(
        '[CameraFrameService] platform=${Platform.isIOS ? "iOS" : "Android"} '
        'camera=${selected.name} lens=$_lensDirection '
        'sensorOrientation=$_sensorOrientation');

    CameraController buildController() => CameraController(
          selected,
          ResolutionPreset.high, // 720p
          enableAudio: false, // Agora handles audio — avoid iOS AVAudioSession conflict
          imageFormatGroup: Platform.isAndroid
              ? ImageFormatGroup.yuv420
              : ImageFormatGroup.bgra8888,
        );

    // Initialize with retries. When a match is found mid-training, the training
    // screen still owns the camera and only releases it from its dispose() —
    // which Flutter defers until *our* (the match screen's) push transition
    // completes (~300ms), after which CameraController.dispose() frees the
    // device asynchronously. So the camera can keep throwing "already in use"
    // for up to ~1s after navigation. A single quick retry (the old behaviour)
    // gave up long before then, leaving the match with dead video + AI until
    // the app was restarted. Retry across the whole release window instead.
    // The match screen shows its loading state until this returns, so the only
    // visible effect is a slightly longer "Starting camera…".
    const maxAttempts = 8;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      if (_disposed) return false;
      _controller = buildController();
      try {
        await _controller!.initialize();
        break;
      } catch (e) {
        await _controller?.dispose();
        _controller = null;
        if (attempt == maxAttempts - 1) {
          debugPrint('[CameraFrameService] init failed after $maxAttempts attempts: $e');
          return false;
        }
        debugPrint(
            '[CameraFrameService] init failed (attempt ${attempt + 1}/$maxAttempts), '
            'retrying in 400ms: $e');
        await Future.delayed(const Duration(milliseconds: 400));
      }
    }
    // dispose() may have raced in during the (now longer) retry window. It sets
    // _disposed first and owns tearing down the controller it saw, so bail here
    // rather than dereference _controller! (which it may already have nulled) or
    // start a stream on a controller that is being disposed.
    if (_disposed) return false;
    final preview = _controller!.value.previewSize;
    debugPrint(
        '[CameraFrameService] previewSize=${preview?.width}x${preview?.height}');

    // Disable flash
    try {
      await _controller!.setFlashMode(FlashMode.off);
    } catch (_) {}

    return true;
  }

  /// Flip between the back and front camera during gameplay. Tears down the
  /// current controller, opens the other lens, resumes streaming to Agora + AI,
  /// and persists the choice so it carries to the next screen and next launch.
  /// No-op while a switch is already in flight or after [dispose].
  Future<void> switchCamera() async {
    if (_disposed || _switching) return;
    _switching = true;
    try {
      final target = _lensDirection == CameraLensDirection.front
          ? CameraLensDirection.back
          : CameraLensDirection.front;

      // Tear down the current controller. Null it out FIRST so any widget
      // rebuild that races with us reads a null controller (and renders its
      // placeholder) instead of touching a disposed one.
      _stopImageStream();
      final old = _controller;
      _controller = null;
      _latestFrame = null;
      _firstPushLogged = false;
      await old?.dispose();
      if (_disposed) return;

      if (!await _openCamera(target)) return;
      if (_disposed) return;
      _startImageStream();

      // Persist the lens actually opened (the target may have fallen back to
      // back when the device has no camera for that direction).
      await StorageService.saveUseFrontCamera(
          _lensDirection == CameraLensDirection.front);
    } finally {
      _switching = false;
    }
  }

  void _startImageStream() {
    if (_controller == null || !_controller!.value.isInitialized || _isStreaming) return;

    _isStreaming = true;
    _controller!.startImageStream((CameraImage image) {
      if (_disposed) return;

      // Cache latest frame for AI capture
      _latestFrame = image;

      // Throttle frame push to ~15fps
      _frameCount++;
      if (_frameCount % (_frameSkip + 1) != 0) return;

      _pushFrameToAgora(image);
    });
  }

  void _stopImageStream() {
    if (!_isStreaming || _controller == null) return;
    _isStreaming = false;
    try {
      _controller!.stopImageStream();
    } catch (_) {}
  }

  /// Push a camera frame to Agora as an external video frame.
  /// Mirrors DartsMind: uses imageProxy.getImageInfo().getRotationDegrees()
  /// and proper YUV format detection (I420 vs NV21).
  /// No-op when running in solo mode without Agora.
  void _pushFrameToAgora(CameraImage image) {
    if (_agoraEngine == null || _videoTrackId == null) return;

    try {
      final Uint8List buffer;
      final VideoPixelFormat format;
      final int stride;
      final int height;

      if (Platform.isAndroid) {
        // DartsMind's YUVHelper checks pixelStride to determine format:
        // pixelStride == 1 → planar I420
        // pixelStride == 2 → interleaved NV21/NV12
        final uvPixelStride = image.planes[1].bytesPerPixel ?? 1;

        if (uvPixelStride == 1) {
          buffer = _buildI420Buffer(image);
          format = VideoPixelFormat.videoPixelI420;
        } else {
          buffer = _buildNv21Buffer(image);
          format = VideoPixelFormat.videoPixelNv21;
        }
        stride = image.width;
        height = image.height;
      } else {
        // iOS: BGRA8888 — push raw pixels and pass rotation=0. The encoder
        // is set to adaptive orientation mode so it won't add its own
        // rotation pass on top of ours (fixedPortrait mode was stacking
        // rotations and producing wrong orientation on Android receivers).
        buffer = Uint8List.fromList(image.planes[0].bytes);
        format = VideoPixelFormat.videoPixelBgra;
        stride = image.planes[0].bytesPerRow ~/ 4;
        height = image.height;
      }

      // Android frames stay in fixed sensor coordinates, so the rotation
      // metadata must follow the device's physical orientation — a frozen
      // _sensorOrientation is only right in portrait and made receivers
      // render this device's landscape stream 90° sideways. In portrait
      // _effectiveRotation() returns that same baseline, so portrait pushes
      // are unchanged. iOS buffers already arrive upright in every
      // orientation, so iOS keeps pushing 0.
      final int frameRotation = Platform.isAndroid ? _effectiveRotation() : 0;

      final frame = ExternalVideoFrame(
        type: VideoBufferType.videoBufferRawData,
        format: format,
        buffer: buffer,
        stride: stride,
        height: height,
        rotation: frameRotation,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      if (!_firstPushLogged) {
        _firstPushLogged = true;
        debugPrint(
            '[CameraFrameService] first push: src=${image.width}x${image.height} '
            'pushed=${stride}x$height rotation=$frameRotation format=$format');
      }

      AgoraService.pushVideoFrame(
        frame: frame,
        videoTrackId: _videoTrackId!,
      );
    } catch (e) {
      debugPrint('[CameraFrameService] pushFrame error: $e');
    }
  }

  /// Build a proper I420 buffer (planar Y + U + V) with padding removed.
  /// Used when pixelStride == 1 (true planar YUV420).
  Uint8List _buildI420Buffer(CameraImage image) {
    final w = image.width;
    final h = image.height;
    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];

    final ySize = w * h;
    final uvSize = (w ~/ 2) * (h ~/ 2);
    final buffer = Uint8List(ySize + uvSize * 2);

    // Copy Y plane, removing row padding
    final yRowStride = yPlane.bytesPerRow;
    if (yRowStride == w) {
      buffer.setRange(0, ySize, yPlane.bytes);
    } else {
      for (int row = 0; row < h; row++) {
        buffer.setRange(row * w, row * w + w, yPlane.bytes, row * yRowStride);
      }
    }

    // Copy U plane, removing row padding
    final uvRowStride = uPlane.bytesPerRow;
    final uvW = w ~/ 2;
    final uvH = h ~/ 2;
    if (uvRowStride == uvW) {
      buffer.setRange(ySize, ySize + uvSize, uPlane.bytes);
    } else {
      for (int row = 0; row < uvH; row++) {
        buffer.setRange(ySize + row * uvW, ySize + row * uvW + uvW, uPlane.bytes, row * uvRowStride);
      }
    }

    // Copy V plane, removing row padding
    if (uvRowStride == uvW) {
      buffer.setRange(ySize + uvSize, ySize + uvSize * 2, vPlane.bytes);
    } else {
      for (int row = 0; row < uvH; row++) {
        buffer.setRange(ySize + uvSize + row * uvW, ySize + uvSize + row * uvW + uvW, vPlane.bytes, row * uvRowStride);
      }
    }

    return buffer;
  }

  /// Build NV21 buffer (Y plane + interleaved VU) from interleaved UV planes.
  /// Used when pixelStride == 2 (NV21/NV12 from Android camera).
  /// DartsMind's YUVHelper handles this case explicitly.
  Uint8List _buildNv21Buffer(CameraImage image) {
    final w = image.width;
    final h = image.height;
    final yPlane = image.planes[0];
    final vPlane = image.planes[2]; // V plane — in NV21, VU pairs are interleaved

    final ySize = w * h;
    // NV21: Y plane followed by interleaved V,U pairs
    final vuSize = (w ~/ 2) * (h ~/ 2) * 2;
    final buffer = Uint8List(ySize + vuSize);

    // Copy Y plane
    final yRowStride = yPlane.bytesPerRow;
    if (yRowStride == w) {
      buffer.setRange(0, ySize, yPlane.bytes);
    } else {
      for (int row = 0; row < h; row++) {
        buffer.setRange(row * w, row * w + w, yPlane.bytes, row * yRowStride);
      }
    }

    // Copy interleaved VU data from the V plane (which contains V,U,V,U,... with pixelStride=2)
    // On Android with NV21, planes[2] (V) starts 1 byte before planes[1] (U) and they share the same buffer
    final vuRowStride = vPlane.bytesPerRow;
    final uvH = h ~/ 2;
    if (vuRowStride == w) {
      final copyLen = min(vuSize, vPlane.bytes.length);
      buffer.setRange(ySize, ySize + copyLen, vPlane.bytes);
    } else {
      for (int row = 0; row < uvH; row++) {
        final rowBytes = min(w, vPlane.bytes.length - row * vuRowStride);
        if (rowBytes <= 0) break;
        buffer.setRange(ySize + row * w, ySize + row * w + rowBytes, vPlane.bytes, row * vuRowStride);
      }
    }

    return buffer;
  }

  /// Capture the latest frame as a JPEG file for AI scoring.
  /// Returns the file path, or null if no frame is available.
  /// DartsMind applies rotation via Matrix.postRotate(rotationDegrees) before AI.
  Future<String?> captureFrame() async {
    final frame = _latestFrame;
    if (frame == null) return null;

    try {
      // Convert CameraImage to JPEG in an isolate to avoid blocking UI
      final jpegBytes = await compute(_convertCameraImageToJpeg, _CaptureData(
        planes: frame.planes.map((p) => _PlaneData(
          bytes: Uint8List.fromList(p.bytes),
          bytesPerRow: p.bytesPerRow,
          bytesPerPixel: p.bytesPerPixel,
          width: p.width,
          height: p.height,
        )).toList(),
        width: frame.width,
        height: frame.height,
        formatIndex: frame.format.group.index,
        // Android compensates for device orientation; iOS frames already arrive
        // upright, so it passes 0 — exactly as before the landscape change.
        sensorOrientation: Platform.isAndroid ? _effectiveRotation() : 0,
      ));

      if (jpegBytes == null) return null;

      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/cam_frame_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await File(path).writeAsBytes(jpegBytes);
      return path;
    } catch (e) {
      debugPrint('[CameraFrameService] captureFrame error: $e');
      return null;
    }
  }

  /// iOS-only: capture the latest frame as raw BGRA bytes (camera native format).
  /// Returns (bgraBytes, width, height) or null if unavailable / non-iOS.
  ///
  /// Skips the per-pixel BGRA→RGBA conversion that `captureRgba` does on the
  /// main isolate. The native plugin does the channel swap on its background
  /// queue (vDSP), so all the heavy work stays off the UI thread.
  (Uint8List, int, int)? captureBgra() {
    if (!Platform.isIOS) return null;
    final frame = _latestFrame;
    if (frame == null) return null;

    try {
      final bgra = frame.planes[0].bytes;
      final w = frame.width;
      final h = frame.height;
      final stride = frame.planes[0].bytesPerRow;

      // Zero-copy: row stride matches packed width.
      if (stride == w * 4) return (bgra, w, h);

      // Strip per-row padding only — single setRange per row, no per-pixel work.
      final tight = Uint8List(w * h * 4);
      final rowBytes = w * 4;
      for (int y = 0; y < h; y++) {
        tight.setRange(y * rowBytes, y * rowBytes + rowBytes, bgra, y * stride);
      }
      return (tight, w, h);
    } catch (e) {
      debugPrint('[CameraFrameService] captureBgra error: $e');
      return null;
    }
  }

  /// Capture the latest frame as raw RGBA pixels directly — no file I/O.
  /// Returns (rgbaBytes, width, height) or null if no frame is available.
  /// This is the fast path matching DartsMind: camera buffer → model directly.
  ///
  /// DartsMind rotates the bitmap using imageProxy.getImageInfo().getRotationDegrees()
  /// before sending to AI. We do the same here: on Android, the sensor is typically
  /// landscape (90° rotated), so we rotate to ensure the image is always portrait.
  (Uint8List, int, int)? captureRgba() {
    final frame = _latestFrame;
    if (frame == null) return null;

    try {
      if (Platform.isIOS) {
        // iOS: BGRA8888 — convert to RGBA in place
        final bgra = frame.planes[0].bytes;
        final w = frame.width;
        final h = frame.height;
        final stride = frame.planes[0].bytesPerRow;
        final rgba = Uint8List(w * h * 4);
        for (int y = 0; y < h; y++) {
          final srcRow = y * stride;
          final dstRow = y * w * 4;
          for (int x = 0; x < w; x++) {
            final si = srcRow + x * 4;
            final di = dstRow + x * 4;
            rgba[di] = bgra[si + 2];     // R <- B channel
            rgba[di + 1] = bgra[si + 1]; // G
            rgba[di + 2] = bgra[si];     // B <- R channel
            rgba[di + 3] = bgra[si + 3]; // A
          }
        }
        // iOS frames already arrive upright in every device orientation, so no
        // rotation is applied here — identical to the pre-landscape behaviour.
        return (rgba, w, h);
      } else {
        // Android: YUV420 — convert to RGBA
        final yPlane = frame.planes[0];
        final uPlane = frame.planes[1];
        final vPlane = frame.planes[2];
        final w = frame.width;
        final h = frame.height;
        final yRowStride = yPlane.bytesPerRow;
        final uvRowStride = uPlane.bytesPerRow;
        final uvPixelStride = uPlane.bytesPerPixel ?? 1;

        // Rotate so the board is upright for the model in any device
        // orientation (portrait OR landscape) — see _effectiveRotation.
        final rotation = _effectiveRotation();

        if (rotation == 90) {
          // Rotate 90° CW: (x, y) → (h-1-y, x), output is h×w
          final outW = h;
          final outH = w;
          final rgba = Uint8List(outW * outH * 4);
          for (int sy = 0; sy < h; sy++) {
            for (int sx = 0; sx < w; sx++) {
              final yVal = yPlane.bytes[sy * yRowStride + sx];
              final uvIdx = (sy ~/ 2) * uvRowStride + (sx ~/ 2) * uvPixelStride;
              final uVal = uPlane.bytes[uvIdx];
              final vVal = vPlane.bytes[uvIdx];
              // Destination after 90° CW rotation
              final dx = h - 1 - sy;
              final dy = sx;
              final di = (dy * outW + dx) * 4;
              rgba[di] = (yVal + 1.370705 * (vVal - 128)).clamp(0, 255).toInt();
              rgba[di + 1] = (yVal - 0.337633 * (uVal - 128) - 0.698001 * (vVal - 128)).clamp(0, 255).toInt();
              rgba[di + 2] = (yVal + 1.732446 * (uVal - 128)).clamp(0, 255).toInt();
              rgba[di + 3] = 255;
            }
          }
          return (rgba, outW, outH);
        } else if (rotation == 270) {
          // Rotate 270° CW (= 90° CCW): (x, y) → (y, w-1-x), output is h×w
          final outW = h;
          final outH = w;
          final rgba = Uint8List(outW * outH * 4);
          for (int sy = 0; sy < h; sy++) {
            for (int sx = 0; sx < w; sx++) {
              final yVal = yPlane.bytes[sy * yRowStride + sx];
              final uvIdx = (sy ~/ 2) * uvRowStride + (sx ~/ 2) * uvPixelStride;
              final uVal = uPlane.bytes[uvIdx];
              final vVal = vPlane.bytes[uvIdx];
              final dx = sy;
              final dy = w - 1 - sx;
              final di = (dy * outW + dx) * 4;
              rgba[di] = (yVal + 1.370705 * (vVal - 128)).clamp(0, 255).toInt();
              rgba[di + 1] = (yVal - 0.337633 * (uVal - 128) - 0.698001 * (vVal - 128)).clamp(0, 255).toInt();
              rgba[di + 2] = (yVal + 1.732446 * (uVal - 128)).clamp(0, 255).toInt();
              rgba[di + 3] = 255;
            }
          }
          return (rgba, outW, outH);
        } else {
          // 0 or 180 — no dimension swap needed
          final rgba = Uint8List(w * h * 4);
          for (int sy = 0; sy < h; sy++) {
            for (int sx = 0; sx < w; sx++) {
              final yVal = yPlane.bytes[sy * yRowStride + sx];
              final uvIdx = (sy ~/ 2) * uvRowStride + (sx ~/ 2) * uvPixelStride;
              final uVal = uPlane.bytes[uvIdx];
              final vVal = vPlane.bytes[uvIdx];
              final int dx, dy;
              if (rotation == 180) {
                dx = w - 1 - sx;
                dy = h - 1 - sy;
              } else {
                dx = sx;
                dy = sy;
              }
              final di = (dy * w + dx) * 4;
              rgba[di] = (yVal + 1.370705 * (vVal - 128)).clamp(0, 255).toInt();
              rgba[di + 1] = (yVal - 0.337633 * (uVal - 128) - 0.698001 * (vVal - 128)).clamp(0, 255).toInt();
              rgba[di + 2] = (yVal + 1.732446 * (uVal - 128)).clamp(0, 255).toInt();
              rgba[di + 3] = 255;
            }
          }
          return (rgba, w, h);
        }
      }
    } catch (e) {
      debugPrint('[CameraFrameService] captureRgba error: $e');
      return null;
    }
  }

  /// Capture the latest frame as raw YUV planes for native-side processing.
  /// Android only — returns (yPlane, uPlane, vPlane, width, height,
  /// yRowStride, uvRowStride, uvPixelStride, rotation) or null.
  /// This matches DartsMind's flow: raw camera data → native conversion.
  ({
    Uint8List yPlane,
    Uint8List uPlane,
    Uint8List vPlane,
    int width,
    int height,
    int yRowStride,
    int uvRowStride,
    int uvPixelStride,
    int rotation,
  })? captureYuvPlanes() {
    final frame = _latestFrame;
    if (frame == null || !Platform.isAndroid) return null;

    try {
      // Pass plane bytes directly — MethodChannel serialization copies them once
      // into a Kotlin ByteArray. The extra Uint8List.fromList() call used to
      // copy them a second time (~1.4MB/frame at 720p) for no benefit.
      return (
        yPlane: frame.planes[0].bytes,
        uPlane: frame.planes[1].bytes,
        vPlane: frame.planes[2].bytes,
        width: frame.width,
        height: frame.height,
        yRowStride: frame.planes[0].bytesPerRow,
        uvRowStride: frame.planes[1].bytesPerRow,
        uvPixelStride: frame.planes[1].bytesPerPixel ?? 1,
        rotation: _effectiveRotation(),
      );
    } catch (e) {
      debugPrint('[CameraFrameService] captureYuvPlanes error: $e');
      return null;
    }
  }

  // --- Zoom controls ---

  Future<double> getMinZoomLevel() async {
    if (_controller == null || !_controller!.value.isInitialized) return 1.0;
    return await _controller!.getMinZoomLevel();
  }

  Future<double> getMaxZoomLevel() async {
    if (_controller == null || !_controller!.value.isInitialized) return 1.0;
    return await _controller!.getMaxZoomLevel();
  }

  Future<void> setZoomLevel(double zoom) async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    await _controller!.setZoomLevel(zoom);
  }

  /// Pause the camera (e.g. when app goes to background).
  void pause() {
    _stopImageStream();
  }

  /// Resume the camera (e.g. when app comes back to foreground).
  void resume() {
    if (_controller != null && _controller!.value.isInitialized && !_isStreaming && !_disposed) {
      _startImageStream();
    }
  }

  /// Release all resources.
  Future<void> dispose() async {
    _disposed = true;
    _stopImageStream();
    _latestFrame = null;

    if (_videoTrackId != null) {
      await AgoraService.destroyCustomVideoTrack(_videoTrackId!);
      _videoTrackId = null;
    }

    await _controller?.dispose();
    _controller = null;
    _agoraEngine = null;
  }
}

// --- Isolate-safe data classes for JPEG conversion ---

class _PlaneData {
  final Uint8List bytes;
  final int bytesPerRow;
  final int? bytesPerPixel;
  final int? width;
  final int? height;

  _PlaneData({
    required this.bytes,
    required this.bytesPerRow,
    required this.bytesPerPixel,
    required this.width,
    required this.height,
  });
}

class _CaptureData {
  final List<_PlaneData> planes;
  final int width;
  final int height;
  final int formatIndex;
  final int sensorOrientation;

  _CaptureData({
    required this.planes,
    required this.width,
    required this.height,
    required this.formatIndex,
    this.sensorOrientation = 0,
  });
}

/// Convert a camera frame to JPEG. Runs in a separate isolate.
/// DartsMind applies Matrix.postRotate(rotationDegrees) before AI processing.
Uint8List? _convertCameraImageToJpeg(_CaptureData data) {
  try {
    img.Image image;

    // ImageFormatGroup indices: 0=unknown, 1=yuv420, 2=bgra8888, 3=jpeg, 4=nv21
    if (data.formatIndex == 2) {
      // BGRA8888 (iOS)
      image = img.Image.fromBytes(
        width: data.width,
        height: data.height,
        bytes: data.planes[0].bytes.buffer,
        order: img.ChannelOrder.bgra,
      );
    } else if (data.formatIndex == 1 || data.formatIndex == 4) {
      // YUV420 (Android) or NV21
      image = _convertYuv420ToImage(data.planes, data.width, data.height);
    } else if (data.formatIndex == 3 && data.planes.isNotEmpty) {
      // JPEG — already encoded
      return data.planes[0].bytes;
    } else {
      return null;
    }

    // Apply rotation to ensure portrait orientation (like DartsMind's Matrix.postRotate)
    if (data.sensorOrientation == 90) {
      image = img.copyRotate(image, angle: 90);
    } else if (data.sensorOrientation == 180) {
      image = img.copyRotate(image, angle: 180);
    } else if (data.sensorOrientation == 270) {
      image = img.copyRotate(image, angle: 270);
    }

    return Uint8List.fromList(img.encodeJpg(image, quality: 85));
  } catch (e) {
    return null;
  }
}

img.Image _convertYuv420ToImage(List<_PlaneData> planes, int width, int height) {
  final yPlane = planes[0];
  final uPlane = planes[1];
  final vPlane = planes[2];

  final image = img.Image(width: width, height: height);

  final yRowStride = yPlane.bytesPerRow;
  final uvRowStride = uPlane.bytesPerRow;
  final uvPixelStride = uPlane.bytesPerPixel ?? 1;

  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final yIndex = y * yRowStride + x;
      final uvIndex = (y ~/ 2) * uvRowStride + (x ~/ 2) * uvPixelStride;

      final yVal = yPlane.bytes[yIndex];
      final uVal = uPlane.bytes[uvIndex];
      final vVal = vPlane.bytes[uvIndex];

      final r = (yVal + 1.370705 * (vVal - 128)).clamp(0, 255).toInt();
      final g = (yVal - 0.337633 * (uVal - 128) - 0.698001 * (vVal - 128))
          .clamp(0, 255)
          .toInt();
      final b = (yVal + 1.732446 * (uVal - 128)).clamp(0, 255).toInt();

      image.setPixelRgba(x, y, r, g, b, 255);
    }
  }

  return image;
}
