import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show Uint8List, debugPrint, kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' show MediaStreamTrack, WebRTC;
// flutter_webrtc has no public factory for a track that was registered
// natively; MediaStreamTrackNative is the exact class getUserMedia's own
// tracks are built from (id/label/kind/enabled/ownerTag) — see
// media_stream_impl.dart setMediaTracks in flutter_webrtc 1.5.2.
// ignore: implementation_imports
import 'package:flutter_webrtc/src/native/media_stream_track_impl.dart'
    show MediaStreamTrackNative;

/// Bridge to the app-local "RtcFrames" native companion (RtcFramesPlugin on
/// iOS/Android): a WebRTC video track fed by the app-owned camera instead of
/// a WebRTC-managed capturer — the P2P twin of AgoraService.pushVideoFrame.
///
/// Flow: [createTrack] once per P2P session (native side registers the track
/// inside flutter_webrtc's localTracks under a fixed id), CameraFrameService
/// then calls [pushFrame] at its usual ≤16 fps cadence, [disposeTrack] on
/// teardown.
class RtcFramesService {
  RtcFramesService._();

  static const MethodChannel _channel =
      MethodChannel('com.dartrivals/rtc_frames');

  /// Fixed native-side track id (must match RtcFramesPlugin.TRACK_ID).
  static const String trackId = 'dartrivals-ext-cam';

  /// The native companion only exists on the mobile embeddings.
  static bool get isSupported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  static MediaStreamTrack? _track;
  static bool _pushErrorLogged = false;

  /// Last createTrack failure, kept so the P2P session can embed it in the
  /// end-of-call telemetry (rtc_v2_reports.reason) — remote diagnosis of a
  /// receive-only call without needing adb/Xcode on the device.
  static String? lastCreateError;

  // Bumped on every createTrack. A screen tearing down while its SUCCESSOR
  // already recreated the track (deferred-dispose overlap) must not destroy
  // the successor's track: dispose calls carry the generation they created.
  static int _generation = 0;

  /// Generation of the current track — capture right after [createTrack] and
  /// pass it back to [disposeTrack].
  static int get generation => _generation;

  /// Frames currently in the method channel. Mirrors the camera service's
  /// two-slot push pool: more than two in flight means the platform side is
  /// behind, and the frame is dropped instead of queueing another multi-MB
  /// copy.
  static int _inFlight = 0;

  static bool get hasTrack => _track != null;

  /// Create (or reuse) the injectable local video track. Returns null when
  /// unsupported or when the native side failed — callers then run a
  /// receive-only call.
  static Future<MediaStreamTrack?> createTrack() async {
    if (!isSupported) return null;
    // Generation bumps SYNCHRONOUSLY, before any await: a stale
    // disposeTrack racing this create (deferred-dispose overlap) must see
    // the new generation immediately — bumping after the native 'create'
    // let its guard pass and its native 'dispose' land AFTER our 'create',
    // killing the brand-new track (silent receive-only call).
    _generation++;
    try {
      // flutter_webrtc creates its native PeerConnectionFactory in its
      // 'initialize' method call; force it so the companion finds a factory
      // even before the first createPeerConnection.
      await WebRTC.initialize();
      final id = await _channel.invokeMethod<String>('create');
      if (id == null) {
        lastCreateError = 'native returned null id';
        _track = null;
        return null;
      }
      _track = MediaStreamTrackNative(id, id, 'video', true, '', const {});
      _pushErrorLogged = false;
      lastCreateError = null;
      return _track;
    } catch (e) {
      lastCreateError = e.toString();
      _track = null;
      debugPrint('[RtcFramesService] createTrack failed: $e');
      return null;
    }
  }

  /// Push one camera frame into the WebRTC video source. Fire-and-forget by
  /// design (mirrors the Agora push): drops the frame when the channel is
  /// busy, never throws.
  ///
  /// Android: [bytes] is tight planar I420 or NV21 ([format] 'i420'/'nv21'),
  /// [rotationDegrees] is the clockwise-to-upright rotation metadata.
  /// iOS: [bytes] is the raw BGRA plane ([format] 'bgra'), [bytesPerRow] its
  /// row stride, rotation 0 (frames already arrive upright).
  static void pushFrame(
    Uint8List bytes,
    int width,
    int height,
    int rotationDegrees, {
    String? format,
    int? bytesPerRow,
  }) {
    if (_track == null || _inFlight >= 2) return;
    _inFlight++;
    _channel.invokeMethod<void>('pushFrame', <String, dynamic>{
      'bytes': bytes,
      'width': width,
      'height': height,
      'rotation': rotationDegrees,
      'format': ?format,
      'bytesPerRow': ?bytesPerRow,
    }).catchError((Object e) {
      if (!_pushErrorLogged) {
        _pushErrorLogged = true;
        debugPrint('[RtcFramesService] pushFrame failed (logged once): $e');
      }
    }).whenComplete(() => _inFlight--);
  }

  /// Tear down the native track/source and unregister it from flutter_webrtc.
  /// Call AFTER the P2pRtcSession using it has been disposed.
  ///
  /// [ifGeneration] guards against the deferred-dispose overlap: pass the
  /// value captured after [createTrack] and the call becomes a no-op if a
  /// newer screen has already recreated the track.
  static Future<void> disposeTrack({int? ifGeneration}) async {
    if (ifGeneration != null && ifGeneration != _generation) {
      debugPrint(
          '[RtcFramesService] disposeTrack skipped: generation $ifGeneration is stale (current $_generation)');
      return;
    }
    _track = null;
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('dispose');
    } catch (e) {
      debugPrint('[RtcFramesService] disposeTrack failed: $e');
    }
  }
}
