import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

import '../utils/storage_service.dart';
import 'api_service.dart';

/// Training-image collection for the dart-detection AI: when a scored frame
/// shows 3 darts (AutoScoringService decides), ONE native-resolution JPEG per
/// visit goes straight to R2 with a presigned PUT — the backend never sees
/// the bytes and nothing is stored in the app.
///
/// Must never get in the way of scoring: the frame is copied once at call
/// time, JPEG encoding runs in an isolate, the upload is fire-and-forget
/// (Wi-Fi only, one retry) and every failure is silent.
class DatasetCaptureService {
  /// Local Settings toggle (« Aider à améliorer l'IA ») — default ON,
  /// loaded at startup with the other preferences.
  static bool _shareEnabled = true;

  /// Remote kill-switch from /app/version-config (`datasetCaptureEnabled`).
  /// Fail-closed: stays off until the backend says otherwise, and drops back
  /// to off for the session when the backend refuses a presign (flag off,
  /// 10k dataset complete, or per-user quota reached).
  static bool remoteEnabled = false;

  static bool get shareEnabled => _shareEnabled;

  /// Should AutoScoringService bother capturing at all right now?
  static bool get isActive => _shareEnabled && remoteEnabled;

  static Future<void> loadPreference() async {
    _shareEnabled = await StorageService.getDatasetShareEnabled();
  }

  static Future<void> setShareEnabled(bool enabled) async {
    _shareEnabled = enabled;
    await StorageService.saveDatasetShareEnabled(enabled);
  }

  /// One capture in flight at a time — a second one is simply dropped.
  static bool _busy = false;

  /// iOS path: BGRA (or RGBA fallback) pixels at native resolution.
  /// Copies the buffer synchronously — it belongs to the camera frame —
  /// then encodes and uploads in the background.
  static void capturePixels(
    Uint8List pixels,
    int width,
    int height, {
    required bool isBgra,
  }) {
    if (!isActive || _busy) return;
    _busy = true;
    _encodeAndUpload(_FramePayload.pixels(
      Uint8List.fromList(pixels),
      width,
      height,
      isBgra: isBgra,
    ));
  }

  /// Android path: raw YUV420 planes with their strides + rotation, exactly
  /// as captureYuv hands them to the native scorer.
  static void captureYuv({
    required Uint8List yPlane,
    required Uint8List uPlane,
    required Uint8List vPlane,
    required int width,
    required int height,
    required int yRowStride,
    required int uvRowStride,
    required int uvPixelStride,
    required int rotation,
  }) {
    if (!isActive || _busy) return;
    _busy = true;
    _encodeAndUpload(_FramePayload.yuv(
      yPlane: Uint8List.fromList(yPlane),
      uPlane: Uint8List.fromList(uPlane),
      vPlane: Uint8List.fromList(vPlane),
      width: width,
      height: height,
      yRowStride: yRowStride,
      uvRowStride: uvRowStride,
      uvPixelStride: uvPixelStride,
      rotation: rotation,
    ));
  }

  static Future<void> _encodeAndUpload(_FramePayload payload) async {
    try {
      // Quality 95, native resolution, no crop — these images train a
      // detection model, sharpness beats file size.
      final jpeg = await compute(_encodeDatasetJpeg, payload);
      if (jpeg == null) return;
      await _upload(jpeg);
    } catch (e) {
      debugPrint('[DatasetCapture] dropped: $e');
    } finally {
      _busy = false;
    }
  }

  static Future<void> _upload(Uint8List jpeg) async {
    // Wi-Fi only — a dataset image is never worth mobile data.
    final connectivity = await Connectivity().checkConnectivity();
    if (!connectivity.contains(ConnectivityResult.wifi)) return;

    Map<String, dynamic> presign;
    try {
      final res =
          await ApiService.post('/dataset/presign', {'sizeBytes': jpeg.length});
      presign = res as Map<String, dynamic>;
    } catch (e) {
      // A refusal is the backend closing the tap (flag off, dataset complete,
      // user quota) — stop asking for the rest of the session. The flag
      // re-arms at the next version-config read.
      remoteEnabled = false;
      debugPrint('[DatasetCapture] presign refused, pausing: $e');
      return;
    }
    final url = presign['url'] as String;

    // The presigned PUT goes straight to R2 — no auth headers, and the
    // content type/length must match what was signed.
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final put = await http
            .put(
              Uri.parse(url),
              headers: {'Content-Type': 'image/jpeg'},
              body: jpeg,
            )
            .timeout(const Duration(seconds: 45));
        if (put.statusCode >= 200 && put.statusCode < 300) {
          debugPrint('[DatasetCapture] uploaded ${jpeg.length} bytes');
          return;
        }
      } catch (_) {}
    }
    debugPrint('[DatasetCapture] PUT failed twice, dropped');
  }
}

class _FramePayload {
  final Uint8List? pixels;
  final bool isBgra;
  final Uint8List? yPlane, uPlane, vPlane;
  final int width, height;
  final int yRowStride, uvRowStride, uvPixelStride, rotation;

  _FramePayload.pixels(this.pixels, this.width, this.height,
      {required this.isBgra})
      : yPlane = null,
        uPlane = null,
        vPlane = null,
        yRowStride = 0,
        uvRowStride = 0,
        uvPixelStride = 0,
        rotation = 0;

  _FramePayload.yuv({
    required this.yPlane,
    required this.uPlane,
    required this.vPlane,
    required this.width,
    required this.height,
    required this.yRowStride,
    required this.uvRowStride,
    required this.uvPixelStride,
    required this.rotation,
  })  : pixels = null,
        isBgra = false;
}

/// Runs in an isolate (compute). Mirrors CameraFrameService's file-capture
/// conversion — YUV420→RGB honouring the strides, then the sensor rotation —
/// but at quality 95 and native resolution for training use.
Uint8List? _encodeDatasetJpeg(_FramePayload p) {
  try {
    img.Image image;
    if (p.pixels != null) {
      image = img.Image.fromBytes(
        width: p.width,
        height: p.height,
        bytes: p.pixels!.buffer,
        order: p.isBgra ? img.ChannelOrder.bgra : img.ChannelOrder.rgba,
      );
    } else {
      image = img.Image(width: p.width, height: p.height);
      for (int y = 0; y < p.height; y++) {
        for (int x = 0; x < p.width; x++) {
          final yIndex = y * p.yRowStride + x;
          final uvIndex = (y ~/ 2) * p.uvRowStride + (x ~/ 2) * p.uvPixelStride;
          final yVal = p.yPlane![yIndex];
          final uVal = p.uPlane![uvIndex];
          final vVal = p.vPlane![uvIndex];
          final r = (yVal + 1.370705 * (vVal - 128)).clamp(0, 255).toInt();
          final g = (yVal - 0.337633 * (uVal - 128) - 0.698001 * (vVal - 128))
              .clamp(0, 255)
              .toInt();
          final b = (yVal + 1.732446 * (uVal - 128)).clamp(0, 255).toInt();
          image.setPixelRgba(x, y, r, g, b, 255);
        }
      }
      if (p.rotation == 90 || p.rotation == 180 || p.rotation == 270) {
        image = img.copyRotate(image, angle: p.rotation);
      }
    }
    return Uint8List.fromList(img.encodeJpg(image, quality: 95));
  } catch (_) {
    return null;
  }
}
