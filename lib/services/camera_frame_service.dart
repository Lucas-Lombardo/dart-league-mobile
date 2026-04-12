import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image/image.dart' as img;

import 'agora_service.dart';

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

  CameraController? get controller => _controller;
  bool get isInitialized => _controller?.value.isInitialized ?? false;

  /// Initialize the camera and start pushing frames to Agora.
  Future<void> initialize({
    required RtcEngine agoraEngine,
    required int videoTrackId,
  }) async {
    _agoraEngine = agoraEngine;
    _videoTrackId = videoTrackId;

    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      debugPrint('[CameraFrameService] No cameras available');
      return;
    }

    final backCamera = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );
    _sensorOrientation = backCamera.sensorOrientation;

    _controller = CameraController(
      backCamera,
      ResolutionPreset.high, // 720p
      enableAudio: false, // Agora handles audio — avoid iOS AVAudioSession conflict
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.yuv420
          : ImageFormatGroup.bgra8888,
    );

    await _controller!.initialize();

    // Disable flash
    try {
      await _controller!.setFlashMode(FlashMode.off);
    } catch (_) {}

    // Start the image stream — each frame goes to Agora + cached for AI
    _startImageStream();
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
        // iOS: BGRA8888 — rotate the pixel data ourselves because the
        // Flutter Agora SDK's ExternalVideoFrame.rotation field does not
        // reliably apply rotation. Raw sensor frames are landscape; we
        // rotate to portrait before pushing so rotation=0 works everywhere.
        final rotation = _sensorOrientation ?? 0;
        final bgra = image.planes[0].bytes;
        final srcW = image.width;
        final srcH = image.height;
        final srcStride = image.planes[0].bytesPerRow;

        if (rotation == 90) {
          // Rotate 90° CW: output is srcH × srcW
          final outW = srcH;
          final outH = srcW;
          final out = Uint8List(outW * outH * 4);
          for (int sy = 0; sy < srcH; sy++) {
            final srcRow = sy * srcStride;
            for (int sx = 0; sx < srcW; sx++) {
              final dx = srcH - 1 - sy;
              final dy = sx;
              final si = srcRow + sx * 4;
              final di = (dy * outW + dx) * 4;
              out[di]     = bgra[si];
              out[di + 1] = bgra[si + 1];
              out[di + 2] = bgra[si + 2];
              out[di + 3] = bgra[si + 3];
            }
          }
          buffer = out;
          stride = outW;
          height = outH;
        } else if (rotation == 270) {
          final outW = srcH;
          final outH = srcW;
          final out = Uint8List(outW * outH * 4);
          for (int sy = 0; sy < srcH; sy++) {
            final srcRow = sy * srcStride;
            for (int sx = 0; sx < srcW; sx++) {
              final dx = sy;
              final dy = srcW - 1 - sx;
              final si = srcRow + sx * 4;
              final di = (dy * outW + dx) * 4;
              out[di]     = bgra[si];
              out[di + 1] = bgra[si + 1];
              out[di + 2] = bgra[si + 2];
              out[di + 3] = bgra[si + 3];
            }
          }
          buffer = out;
          stride = outW;
          height = outH;
        } else {
          buffer = Uint8List.fromList(bgra);
          stride = image.planes[0].bytesPerRow ~/ 4;
          height = image.height;
        }
        format = VideoPixelFormat.videoPixelBgra;
      }

      final frame = ExternalVideoFrame(
        type: VideoBufferType.videoBufferRawData,
        format: format,
        buffer: buffer,
        stride: stride,
        height: height,
        rotation: 0,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

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
        sensorOrientation: Platform.isAndroid ? (_sensorOrientation ?? 0) : 0,
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

        // DartsMind: apply rotation from imageInfo.getRotationDegrees() to
        // ensure the image is portrait before sending to AI.
        // On most Android phones, sensorOrientation is 90 (sensor is landscape).
        final rotation = _sensorOrientation ?? 0;

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
      return (
        yPlane: Uint8List.fromList(frame.planes[0].bytes),
        uPlane: Uint8List.fromList(frame.planes[1].bytes),
        vPlane: Uint8List.fromList(frame.planes[2].bytes),
        width: frame.width,
        height: frame.height,
        yRowStride: frame.planes[0].bytesPerRow,
        uvRowStride: frame.planes[1].bytesPerRow,
        uvPixelStride: frame.planes[1].bytesPerPixel ?? 1,
        rotation: _sensorOrientation ?? 0,
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
