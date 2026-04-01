import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

/// Captures a frame from the camera silently (no shutter sound) by using
/// the image stream API instead of takePicture().
///
/// Returns the file path of the captured JPEG, or null on failure.
Future<String?> silentCapture(CameraController controller) async {
  if (!controller.value.isInitialized) return null;

  // If already streaming, skip — avoid conflicts.
  if (controller.value.isStreamingImages) return null;

  final completer = Completer<CameraImage?>();

  try {
    await controller.startImageStream((CameraImage image) {
      if (!completer.isCompleted) {
        completer.complete(image);
      }
    });

    final cameraImage = await completer.future.timeout(
      const Duration(seconds: 2),
      onTimeout: () => null,
    );

    // Stop the stream as soon as we have a frame.
    await controller.stopImageStream();

    if (cameraImage == null) return null;

    // Convert to JPEG in an isolate to avoid blocking the UI thread.
    final jpegBytes = await compute(_convertToJpeg, cameraImage.planes.map((p) => _PlaneData(
      bytes: Uint8List.fromList(p.bytes),
      bytesPerRow: p.bytesPerRow,
      bytesPerPixel: p.bytesPerPixel,
      width: p.width,
      height: p.height,
    )).toList()..insert(0, _PlaneData(
      bytes: Uint8List(0),
      bytesPerRow: cameraImage.width,
      bytesPerPixel: cameraImage.height,
      width: cameraImage.format.group.index,
      height: 0,
    )));

    if (jpegBytes == null) return null;

    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/silent_capture_${DateTime.now().millisecondsSinceEpoch}.jpg';
    await File(path).writeAsBytes(jpegBytes);
    return path;
  } catch (e) {
    debugPrint('[SilentCapture] Error: $e');
    // Ensure stream is stopped on error.
    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
    } catch (_) {}
    return null;
  }
}

/// Serializable plane data for isolate transfer.
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

/// Convert camera image planes to JPEG bytes. Runs in a separate isolate.
Uint8List? _convertToJpeg(List<_PlaneData> planes) {
  try {
    // First element carries metadata: bytesPerRow=width, bytesPerPixel=height, width=format index
    final meta = planes[0];
    final imageWidth = meta.bytesPerRow;
    final imageHeight = meta.bytesPerPixel!;
    final formatIndex = meta.width!;
    final dataPlanes = planes.sublist(1);

    img.Image image;

    // ImageFormatGroup indices: 0=unknown, 1=yuv420, 2=bgra8888, 3=jpeg, 4=nv21
    if (formatIndex == 2) {
      // BGRA8888 (iOS)
      image = img.Image.fromBytes(
        width: imageWidth,
        height: imageHeight,
        bytes: dataPlanes[0].bytes.buffer,
        order: img.ChannelOrder.bgra,
      );
    } else if (formatIndex == 1 || formatIndex == 4) {
      // YUV420 (Android) or NV21
      image = _convertYuv420ToImage(dataPlanes, imageWidth, imageHeight);
    } else if (formatIndex == 3 && dataPlanes.isNotEmpty) {
      // JPEG — already encoded
      return dataPlanes[0].bytes;
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
