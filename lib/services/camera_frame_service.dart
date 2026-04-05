import 'dart:async';
import 'dart:io';

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
  void _pushFrameToAgora(CameraImage image) {
    if (_agoraEngine == null || _videoTrackId == null) return;

    try {
      final Uint8List buffer;
      final VideoPixelFormat format;
      final int stride;
      final int height;

      if (Platform.isAndroid) {
        // Android: YUV420 — concatenate Y, U, V planes
        buffer = _concatenateYuvPlanes(image);
        format = VideoPixelFormat.videoPixelI420;
        stride = image.planes[0].bytesPerRow;
        height = image.height;
      } else {
        // iOS: BGRA8888 — single plane
        buffer = Uint8List.fromList(image.planes[0].bytes);
        format = VideoPixelFormat.videoPixelBgra;
        stride = image.planes[0].bytesPerRow ~/ 4; // BGRA = 4 bytes per pixel
        height = image.height;
      }

      final frame = ExternalVideoFrame(
        type: VideoBufferType.videoBufferRawData,
        format: format,
        buffer: buffer,
        stride: stride,
        height: height,
        rotation: _sensorOrientation ?? 0,
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

  /// Concatenate YUV420 planes into a single buffer for Agora.
  Uint8List _concatenateYuvPlanes(CameraImage image) {
    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];

    final ySize = yPlane.bytes.length;
    final uSize = uPlane.bytes.length;
    final vSize = vPlane.bytes.length;

    final buffer = Uint8List(ySize + uSize + vSize);
    buffer.setRange(0, ySize, yPlane.bytes);
    buffer.setRange(ySize, ySize + uSize, uPlane.bytes);
    buffer.setRange(ySize + uSize, ySize + uSize + vSize, vPlane.bytes);

    return buffer;
  }

  /// Capture the latest frame as a JPEG file for AI scoring.
  /// Returns the file path, or null if no frame is available.
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
        final rgba = Uint8List(w * h * 4);
        final yRowStride = yPlane.bytesPerRow;
        final uvRowStride = uPlane.bytesPerRow;
        final uvPixelStride = uPlane.bytesPerPixel ?? 1;

        for (int y = 0; y < h; y++) {
          for (int x = 0; x < w; x++) {
            final yVal = yPlane.bytes[y * yRowStride + x];
            final uvIdx = (y ~/ 2) * uvRowStride + (x ~/ 2) * uvPixelStride;
            final uVal = uPlane.bytes[uvIdx];
            final vVal = vPlane.bytes[uvIdx];
            final di = (y * w + x) * 4;
            rgba[di] = (yVal + 1.370705 * (vVal - 128)).clamp(0, 255).toInt();
            rgba[di + 1] = (yVal - 0.337633 * (uVal - 128) - 0.698001 * (vVal - 128)).clamp(0, 255).toInt();
            rgba[di + 2] = (yVal + 1.732446 * (uVal - 128)).clamp(0, 255).toInt();
            rgba[di + 3] = 255;
          }
        }
        return (rgba, w, h);
      }
    } catch (e) {
      debugPrint('[CameraFrameService] captureRgba error: $e');
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

  _CaptureData({
    required this.planes,
    required this.width,
    required this.height,
    required this.formatIndex,
  });
}

/// Convert a camera frame to JPEG. Runs in a separate isolate.
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
