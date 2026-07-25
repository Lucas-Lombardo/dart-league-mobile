import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;

import 'dart_detection_types.dart';
import 'detection_parsing.dart';

/// Persistent worker isolate for the model-output parse + NMS.
///
/// The ~194k-float tensor scan per inference ran on the Flutter UI isolate,
/// competing with rendering and the Agora frame push. Here it runs on a
/// long-lived worker: the caller sends the raw output bytes (one memcpy) and
/// gets back the handful of post-NMS [Detection]s.
///
/// Failure policy: the AI loop must NEVER hang or die on this path. Any
/// spawn/transport error fails the in-flight request, the caller falls back
/// to inline parsing, and up to [_maxRespawns] respawns are attempted before
/// the isolate is abandoned for the session (inline parsing from then on —
/// degraded, but scoring keeps working).
class OutputParseIsolate {
  OutputParseIsolate._();
  static final OutputParseIsolate instance = OutputParseIsolate._();

  Isolate? _isolate;
  SendPort? _toWorker;
  final _pending = <int, Completer<List<Detection>>>{};
  int _nextId = 0;
  int _respawns = 0;
  static const int _maxRespawns = 3;
  Future<void>? _spawning;

  /// Parse + NMS on the worker isolate. Returns null when the worker is
  /// unavailable — the caller should parse inline instead.
  Future<List<Detection>?> tryParse(
    Uint8List outputBytes, {
    required int numChannels,
    required int numElements,
    required double xScale,
    required double yScale,
  }) async {
    if (!await _ensureSpawned()) return null;
    final id = _nextId++;
    final completer = Completer<List<Detection>>();
    _pending[id] = completer;
    try {
      _toWorker!.send([id, outputBytes, numChannels, numElements, xScale, yScale]);
      return await completer.future;
    } catch (e) {
      _pending.remove(id);
      debugPrint('[OutputParseIsolate] request failed, parsing inline: $e');
      return null;
    }
  }

  Future<bool> _ensureSpawned() async {
    if (_toWorker != null) return true;
    if (_respawns >= _maxRespawns) return false;
    _spawning ??= _spawn();
    await _spawning;
    _spawning = null;
    return _toWorker != null;
  }

  Future<void> _spawn() async {
    _respawns++;
    try {
      final handshake = ReceivePort();
      final errors = ReceivePort();
      final exits = ReceivePort();
      _isolate = await Isolate.spawn(
        _workerMain,
        handshake.sendPort,
        debugName: 'output-parse',
        onError: errors.sendPort,
        onExit: exits.sendPort,
      );

      final fromWorker = ReceivePort();
      final ready = Completer<SendPort>();
      handshake.listen((msg) {
        if (msg is SendPort && !ready.isCompleted) ready.complete(msg);
      });
      final toWorker = await ready.future.timeout(const Duration(seconds: 5));
      toWorker.send(fromWorker.sendPort);

      fromWorker.listen((msg) {
        final list = msg as List;
        final completer = _pending.remove(list[0] as int);
        if (completer == null) return;
        if (list[1] is String) {
          completer.completeError(StateError(list[1] as String));
        } else {
          completer.complete((list[1] as List).cast<Detection>());
        }
      });

      void onDead(String why) {
        debugPrint('[OutputParseIsolate] worker died ($why) — '
            'pending requests fall back to inline parsing');
        _toWorker = null;
        _isolate = null;
        final stale = List.of(_pending.values);
        _pending.clear();
        for (final c in stale) {
          if (!c.isCompleted) c.completeError(StateError('parse isolate died'));
        }
      }

      errors.listen((e) => onDead('error: $e'));
      exits.listen((_) => onDead('exit'));

      _toWorker = toWorker;
      handshake.close();
    } catch (e) {
      debugPrint('[OutputParseIsolate] spawn failed: $e');
      _isolate?.kill(priority: Isolate.immediate);
      _isolate = null;
      _toWorker = null;
    }
  }

  /// Test/teardown hook — the singleton normally lives for the process.
  void dispose() {
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _toWorker = null;
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(StateError('disposed'));
    }
    _pending.clear();
  }

  static void _workerMain(SendPort handshake) {
    final inbox = ReceivePort();
    handshake.send(inbox.sendPort);
    SendPort? out;
    inbox.listen((msg) {
      if (msg is SendPort) {
        out = msg;
        return;
      }
      final list = msg as List;
      final id = list[0] as int;
      try {
        var bytes = list[1] as Uint8List;
        final numChannels = list[2] as int;
        final numElements = list[3] as int;
        final xScale = list[4] as double;
        final yScale = list[5] as double;
        if (bytes.offsetInBytes % 4 != 0) {
          bytes = Uint8List.fromList(bytes); // realign (rare)
        }
        final floats = bytes.buffer
            .asFloat32List(bytes.offsetInBytes, bytes.lengthInBytes ~/ 4);
        var detections = parseOutputFloats(
          floats,
          [1, numChannels, numElements],
          xScale: xScale,
          yScale: yScale,
        );
        detections = classSpecificNms(detections);
        out?.send([id, detections]);
      } catch (e) {
        out?.send([id, 'parse failed: $e']);
      }
    });
  }
}
