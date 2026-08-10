import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import '../utils/storage_service.dart';
import 'api_service.dart';

/// Training-image collection for the dart-detection AI: when a scored frame
/// shows 3 darts (AutoScoringService decides), the RAW frame is copied to a
/// temp file and queued — nothing else happens mid-match. The JPEG encode and
/// the presigned PUT to R2 only run in [flush], fired on the match verdict
/// (same lifecycle as the deferred replay renders): a per-visit encode +
/// multi-MB upload during a live P2P call starved the call's audio and the
/// score round-trip (2026-08-09 on-device).
///
/// Must never get in the way of scoring: the frame is copied once at call
/// time, everything heavy is deferred, the upload is fire-and-forget (Wi-Fi
/// only, one retry) and every failure is silent. Frames that never get
/// flushed (app killed mid-match) are swept at next startup — a dataset
/// image is always expendable.
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
    // Orphans from a session that died before its flush. Deliberately
    // deleted, not resumed: resuming would re-introduce uploads at an
    // arbitrary point of the NEXT match.
    _sweepOrphans();
  }

  static Future<void> setShareEnabled(bool enabled) async {
    _shareEnabled = enabled;
    await StorageService.saveDatasetShareEnabled(enabled);
  }

  /// One capture write in flight at a time — a second one is simply dropped.
  static bool _writing = false;

  /// Frames queued for the end-of-match flush. Bounded so a long series
  /// can't fill the disk with raw frames (~3–8 MB each).
  static final List<_PendingCapture> _queue = [];
  static const int _maxQueued = 24;

  static bool _flushing = false;
  static int _fileSeq = 0;

  /// iOS path: BGRA (or RGBA fallback) pixels at native resolution.
  /// Copies the buffer synchronously — it belongs to the camera frame —
  /// then persists it in the background.
  static void capturePixels(
    Uint8List pixels,
    int width,
    int height, {
    required bool isBgra,
  }) {
    if (!isActive || _writing || _queue.length >= _maxQueued) return;
    _writing = true;
    _persist(
      Uint8List.fromList(pixels),
      _PendingCapture.pixels(width: width, height: height, isBgra: isBgra),
    );
  }

  /// Android path: raw YUV420 planes with their strides + rotation, exactly
  /// as captureYuv hands them to the native scorer. The three planes are
  /// copied into ONE buffer (y|u|v) so a single temp file holds the frame.
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
    if (!isActive || _writing || _queue.length >= _maxQueued) return;
    _writing = true;
    final bytes = Uint8List(yPlane.length + uPlane.length + vPlane.length)
      ..setAll(0, yPlane)
      ..setAll(yPlane.length, uPlane)
      ..setAll(yPlane.length + uPlane.length, vPlane);
    _persist(
      bytes,
      _PendingCapture.yuv(
        width: width,
        height: height,
        yLen: yPlane.length,
        uLen: uPlane.length,
        yRowStride: yRowStride,
        uvRowStride: uvRowStride,
        uvPixelStride: uvPixelStride,
        rotation: rotation,
      ),
    );
  }

  static Future<void> _persist(Uint8List bytes, _PendingCapture meta) async {
    try {
      final dir = await _pendingDir();
      final file = File(
          '${dir.path}/${DateTime.now().millisecondsSinceEpoch}_${_fileSeq++}.raw');
      await file.writeAsBytes(bytes, flush: false);
      meta.path = file.path;
      _queue.add(meta);
    } catch (e) {
      debugPrint('[DatasetCapture] persist dropped: $e');
    } finally {
      _writing = false;
    }
  }

  /// Deferred tail of every capture: encode + upload the queued frames, then
  /// delete them. Fired on the match verdict alongside the replay drain, with
  /// a dispose() fallback for abandons — the static guard makes repeats
  /// no-ops while a drain runs, and a rerun picks up whatever a checkout-race
  /// capture queued after the first pass.
  static Future<void> flush() async {
    if (_flushing) return;
    _flushing = true;
    try {
      // Snapshot the batch: the drain awaits network per frame and can still
      // be running when the NEXT match (rematch, deferred dispose) starts
      // queueing — draining the live queue would encode + upload the new
      // match's frames during its live call, the exact load this deferral
      // exists to avoid. The successor frames wait for that match's own
      // verdict flush.
      final batch = List.of(_queue);
      _queue.clear();
      while (batch.isNotEmpty) {
        final cap = batch.removeAt(0);
        final path = cap.path;
        if (path == null) continue;
        try {
          // isActive re-checked per frame: a presign refusal mid-drain kills
          // remoteEnabled and the rest of the queue must only be deleted.
          if (isActive) {
            final bytes = await File(path).readAsBytes();
            final jpeg = await compute(_encodeDatasetJpeg, cap.payload(bytes));
            if (jpeg != null) await _upload(jpeg);
          }
        } catch (e) {
          debugPrint('[DatasetCapture] flush dropped: $e');
        } finally {
          try {
            await File(path).delete();
          } catch (_) {}
        }
      }
    } finally {
      _flushing = false;
    }
  }

  static Future<Directory> _pendingDir() async {
    final tmp = await getTemporaryDirectory();
    return Directory('${tmp.path}/dataset_pending').create(recursive: true);
  }

  static Future<void> _sweepOrphans() async {
    try {
      final tmp = await getTemporaryDirectory();
      final dir = Directory('${tmp.path}/dataset_pending');
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
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

/// Metadata of one queued frame; the bytes live in [path] until the flush.
class _PendingCapture {
  String? path;
  final bool isYuv;
  final bool isBgra;
  final int width, height;
  final int yLen, uLen;
  final int yRowStride, uvRowStride, uvPixelStride, rotation;

  _PendingCapture.pixels(
      {required this.width, required this.height, required this.isBgra})
      : isYuv = false,
        yLen = 0,
        uLen = 0,
        yRowStride = 0,
        uvRowStride = 0,
        uvPixelStride = 0,
        rotation = 0;

  _PendingCapture.yuv({
    required this.width,
    required this.height,
    required this.yLen,
    required this.uLen,
    required this.yRowStride,
    required this.uvRowStride,
    required this.uvPixelStride,
    required this.rotation,
  })  : isYuv = true,
        isBgra = false;

  /// Rebuild the isolate payload from the file's bytes.
  _FramePayload payload(Uint8List bytes) {
    if (!isYuv) {
      return _FramePayload.pixels(bytes, width, height, isBgra: isBgra);
    }
    return _FramePayload.yuv(
      yPlane: Uint8List.sublistView(bytes, 0, yLen),
      uPlane: Uint8List.sublistView(bytes, yLen, yLen + uLen),
      vPlane: Uint8List.sublistView(bytes, yLen + uLen),
      width: width,
      height: height,
      yRowStride: yRowStride,
      uvRowStride: uvRowStride,
      uvPixelStride: uvPixelStride,
      rotation: rotation,
    );
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
