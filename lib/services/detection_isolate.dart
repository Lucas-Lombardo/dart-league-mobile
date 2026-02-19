import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'dart_detection_service.dart';
import 'dart_detection_types.dart';

/// Manages a persistent background isolate that loads the TFLite model once
/// and processes images without blocking the UI thread.
class DetectionIsolate {
  SendPort? _sendPort;
  Isolate? _isolate;
  bool _ready = false;
  final _pendingRequests = <int, Completer<ScoringResult>>{};
  int _nextId = 0;
  StreamSubscription? _subscription;

  bool get isReady => _ready;

  /// Spawn the isolate and wait for model to load.
  Future<void> start() async {
    final receivePort = ReceivePort();

    // Load model bytes on the main thread (has access to asset bundle),
    // then pass them to the isolate so it can use Interpreter.fromBuffer.
    final modelData = await rootBundle.load('assets/models/best_float16.tflite');
    final modelBytes = modelData.buffer.asUint8List();

    _isolate = await Isolate.spawn(
      _isolateEntry,
      _InitMessage(receivePort.sendPort, modelBytes),
    );

    final completer = Completer<SendPort>();
    _subscription = receivePort.listen((message) {
      if (message is SendPort) {
        completer.complete(message);
      } else if (message is _AnalyzeResponse) {
        final pending = _pendingRequests.remove(message.id);
        pending?.complete(message.result);
      }
    });

    _sendPort = await completer.future;
    _ready = true;
  }

  /// Analyze an image in the background isolate.
  /// Returns the scoring result without blocking the UI thread.
  /// Times out after 8 seconds to prevent the capture loop from hanging
  /// if the isolate crashes or stalls mid-inference.
  Future<ScoringResult> analyze(String imagePath) async {
    if (!_ready || _sendPort == null) {
      return ScoringResult(
        calibrationPoints: [],
        dartTips: [],
        scores: [],
        totalScore: 0,
        error: 'Isolate not ready',
      );
    }

    final id = _nextId++;
    final completer = Completer<ScoringResult>();
    _pendingRequests[id] = completer;
    _sendPort!.send(_AnalyzeRequest(id, imagePath));
    return completer.future.timeout(
      const Duration(seconds: 8),
      onTimeout: () {
        _pendingRequests.remove(id);
        return ScoringResult(
          calibrationPoints: [],
          dartTips: [],
          scores: [],
          totalScore: 0,
          error: 'Inference timeout',
        );
      },
    );
  }

  void dispose() {
    _subscription?.cancel();
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _sendPort = null;
    _ready = false;
    // Complete any pending requests with error
    for (final c in _pendingRequests.values) {
      c.complete(ScoringResult(
        calibrationPoints: [],
        dartTips: [],
        scores: [],
        totalScore: 0,
        error: 'Isolate disposed',
      ));
    }
    _pendingRequests.clear();
  }

  /// Entry point for the background isolate.
  static void _isolateEntry(_InitMessage init) async {
    final port = ReceivePort();
    init.mainPort.send(port.sendPort);

    // Load model from pre-loaded bytes (no asset bundle needed in isolate)
    final service = DartDetectionService(useNativeDecode: false);
    service.loadModelFromBuffer(init.modelBytes);
    print('[DetectionIsolate] Model loaded in background isolate');

    await for (final message in port) {
      if (message is _AnalyzeRequest) {
        try {
          final result = await service.analyzeImage(message.imagePath);
          init.mainPort.send(_AnalyzeResponse(message.id, result));
        } catch (e) {
          init.mainPort.send(_AnalyzeResponse(
            message.id,
            ScoringResult(
              calibrationPoints: [],
              dartTips: [],
              scores: [],
              totalScore: 0,
              error: 'Isolate error: $e',
            ),
          ));
        }
      }
    }
  }
}

class _InitMessage {
  final SendPort mainPort;
  final Uint8List modelBytes;
  _InitMessage(this.mainPort, this.modelBytes);
}

class _AnalyzeRequest {
  final int id;
  final String imagePath;
  _AnalyzeRequest(this.id, this.imagePath);
}

class _AnalyzeResponse {
  final int id;
  final ScoringResult result;
  _AnalyzeResponse(this.id, this.result);
}
