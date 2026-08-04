import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Dart facade of the native rolling replay buffer (ReplayBufferPlugin.kt /
/// .swift): the camera pipeline tees every match frame here, the native side
/// keeps a ring of self-contained 3s MP4 segments (~48s of my-turn camera),
/// and [captureRange] turns a wall-clock window into ONE clip file by
/// concatenating segments without re-encoding.
///
/// Frames only flow while [armed] — the camera service arms it for matches
/// and stops it on dispose, which also deletes the ring (clips survive in
/// their own directory).
class ReplayCapture {
  const ReplayCapture(this.path, this.startWallMs, this.durationMs);
  final String path;
  final int startWallMs;

  /// Length of the cut clip. Null from a native side that predates it.
  final int? durationMs;
}

class ReplayBufferService {
  static const _channel = MethodChannel('com.dartrivals/replay_buffer');

  static bool get isSupported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  static bool _armed = false;
  static bool get armed => _armed;

  // Encode ONLY during MY turn: the local camera films my own board, so the
  // opponent's turn produces dead footage — skipping it halves the encoder's
  // duty cycle (heat/battery) and the ring then holds ~60s of pure throwing.
  static bool _myTurn = true;

  /// Turn gate, driven by the game screen on every state change. Flipping to
  /// the opponent's turn closes the open segment so the ring stays tidy;
  /// flipping back simply lets frames flow again (the native side reopens on
  /// a fresh keyframe).
  static void setMyTurn(bool myTurn) {
    if (!_armed || myTurn == _myTurn) return;
    _myTurn = myTurn;
    if (!myTurn) {
      _channel.invokeMethod('pause').catchError((Object e) {
        debugPrint('[ReplayBufferService] pause failed: $e');
        return null;
      });
    }
  }

  // Same backpressure contract as RtcFramesService: the native side answers
  // AFTER consuming the frame; more than 2 in flight means it is behind and
  // the frame is dropped client-side (never queued).
  static int _inFlight = 0;
  static bool _pushErrorLogged = false;

  /// Whether a frame pushed right now would actually be consumed. The camera
  /// tee checks this BEFORE staging the frame: the Android tight-copy is
  /// ~1.4MB per frame, and paying it 24×/s during the opponent's whole turn
  /// just to have [pushFrame] drop the result was pure heat.
  static bool get wantsFrame =>
      _armed && _myTurn && _inFlight < 2 && isSupported;

  static void arm() {
    _armed = true;
    _myTurn = true;
  }

  /// Push one camera frame into the ring. Fire-and-forget by design: drops
  /// when the channel is busy, never throws.
  ///
  /// Android: [bytes] is tight planar I420 or NV21 ([format] 'i420'/'nv21'),
  /// [rotationDegrees] the clockwise-to-upright rotation metadata.
  /// iOS: [bytes] is the raw BGRA plane ([format] 'bgra'), [bytesPerRow] its
  /// row stride, rotation 0 (frames already arrive upright).
  static void pushFrame(
    Uint8List bytes,
    int width,
    int height,
    int rotationDegrees, {
    String format = 'nv21',
    int? bytesPerRow,
  }) {
    if (!_armed || !_myTurn || !isSupported) return;
    if (_inFlight >= 2) return;
    _inFlight++;
    _channel.invokeMethod('pushFrame', {
      'bytes': bytes,
      'width': width,
      'height': height,
      'rotation': rotationDegrees,
      'format': format,
      'bytesPerRow': ?bytesPerRow,
    }).catchError((Object e) {
      if (!_pushErrorLogged) {
        _pushErrorLogged = true;
        debugPrint('[ReplayBufferService] pushFrame failed: $e');
      }
      return null;
    }).whenComplete(() => _inFlight--);
  }

  /// Cut one clip covering [from, to] (bounds snap to segment edges, so the
  /// clip is a little wider than asked — that's the ±2s margin working for
  /// free). Null when the ring has nothing there. [startWallMs] is the wall
  /// clock of the clip's first frame — what the overlay timeline aligns on,
  /// [durationMs] the length the library shows next to the clip.
  static Future<ReplayCapture?> captureRange(DateTime from, DateTime to) async {
    if (!isSupported) return null;
    try {
      final res = await _channel.invokeMethod<Map>('capture', {
        'fromMs': from.millisecondsSinceEpoch,
        'toMs': to.millisecondsSinceEpoch,
      });
      final path = res?['path'] as String?;
      if (path == null) return null;
      return ReplayCapture(
        path,
        (res?['startWallMs'] as num?)?.toInt() ?? 0,
        (res?['durationMs'] as num?)?.toInt(),
      );
    } catch (e) {
      debugPrint('[ReplayBufferService] capture failed: $e');
      return null;
    }
  }

  /// Burns the broadcast overlay into [inPath] (short hardware re-encode,
  /// a few seconds for a ~25s clip). Returns the dressed clip path, or null
  /// on failure — callers keep the raw clip then.
  static Future<String?> renderOverlay({
    required String inPath,
    required Map<String, dynamic> timeline,
  }) async {
    if (!isSupported) return null;
    try {
      return await _channel.invokeMethod<String>('render', {
        'inPath': inPath,
        'timeline': jsonEncode(timeline),
      });
    } catch (e) {
      debugPrint('[ReplayBufferService] render failed: $e');
      return null;
    }
  }

  /// Stops encoding and deletes the ring segments (clips are kept).
  static Future<void> stop() async {
    _armed = false;
    if (!isSupported) return;
    try {
      await _channel.invokeMethod('stop');
    } catch (e) {
      debugPrint('[ReplayBufferService] stop failed: $e');
    }
  }
}
