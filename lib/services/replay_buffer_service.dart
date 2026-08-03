import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Dart facade of the native rolling replay buffer (ReplayBufferPlugin.kt /
/// .swift): the camera pipeline tees every match frame here, the native side
/// keeps a ring of self-contained 5s MP4 segments (~60s of the local camera),
/// and [captureRange] turns a wall-clock window into ONE clip file by
/// concatenating segments without re-encoding.
///
/// Frames only flow while [armed] — the camera service arms it for matches
/// and stops it on dispose, which also deletes the ring (clips survive in
/// their own directory).
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
  /// free). Returns the MP4 path, or null when the ring has nothing there.
  static Future<String?> captureRange(DateTime from, DateTime to) async {
    if (!isSupported) return null;
    try {
      return await _channel.invokeMethod<String>('capture', {
        'fromMs': from.millisecondsSinceEpoch,
        'toMs': to.millisecondsSinceEpoch,
      });
    } catch (e) {
      debugPrint('[ReplayBufferService] capture failed: $e');
      return null;
    }
  }

  /// Convenience for "the turn that just ended".
  static Future<String?> captureLast(Duration window) {
    final now = DateTime.now();
    return captureRange(now.subtract(window), now);
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
