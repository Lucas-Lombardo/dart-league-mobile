import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'dart_detection_service.dart';

const int _decodeTargetWidth = 1024;

/// Manages a persistent background isolate that loads the TFLite model once
/// and processes frames without blocking the UI thread.
///
/// Key optimisations:
/// - Uses TransferableTypedData for zero-copy RGBA transfer (O(1) instead of copying ~3MB).
/// - Uses 1 TFLite thread to avoid Flutter CPU-affinity contention in isolates.
/// - Loads model via Interpreter.fromFile (memory-mapped, same speed as fromAsset).
class DetectionIsolate {
  SendPort? _sendPort;
  Isolate? _isolate;
  bool _ready = false;
  bool _usingFallback = false;
  DartDetectionService? _fallbackService;
  final _pendingRequests = <int, Completer<ScoringResult>>{};
  int _nextId = 0;
  StreamSubscription? _subscription;

  bool get isReady => _ready;

  /// Spawn the isolate and wait for model to load.
  Future<void> start() async {
    _usingFallback = false;

    try {
      final receivePort = ReceivePort();

      // Write model asset to a temp file so the isolate can use
      // Interpreter.fromFile (memory-mapped, same speed as fromAsset).
      final modelData = await rootBundle.load('assets/models/t201.tflite');
      final tempDir = await getTemporaryDirectory();
      final modelFile = File('${tempDir.path}/t201.tflite');
      if (!modelFile.existsSync()) {
        await modelFile.writeAsBytes(modelData.buffer.asUint8List(), flush: true);
      }

      _isolate = await Isolate.spawn(
        _isolateEntry,
        _InitMessage(receivePort.sendPort, modelFile.path),
      );

      final portCompleter = Completer<SendPort>();
      final initCompleter = Completer<void>();

      _subscription = receivePort.listen((message) {
        if (message is SendPort) {
          if (!portCompleter.isCompleted) {
            portCompleter.complete(message);
          }
        } else if (message is _InitStatus) {
          if (!initCompleter.isCompleted) {
            if (message.ok) {
              initCompleter.complete();
            } else {
              initCompleter.completeError(
                Exception(message.error ?? 'Unknown isolate init error'),
              );
            }
          }
        } else if (message is _AnalyzeResponse) {
          final pending = _pendingRequests.remove(message.id);
          pending?.complete(message.result);
        }
      });

      _sendPort = await portCompleter.future.timeout(
        const Duration(seconds: 5),
      );
      await initCompleter.future.timeout(const Duration(seconds: 12));
      _ready = true;
    } catch (e) {
      // Fallback: run on main thread if isolate fails (e.g. TestFlight).
      _subscription?.cancel();
      _subscription = null;
      _isolate?.kill(priority: Isolate.immediate);
      _isolate = null;
      _sendPort = null;

      _fallbackService = DartDetectionService();
      await _fallbackService!.loadModel(cpuOnly: true);
      _usingFallback = true;
      _ready = true;
      debugPrint('[DetectionIsolate] Fallback to main-thread CPU model: $e');
    }
  }

  /// Decode image on main thread using fast native dart:ui, then send
  /// raw RGBA pixels to the isolate for preprocessing + inference.
  Future<(Uint8List, int, int)> _decodeNative(String imagePath) async {
    final bytes = await File(imagePath).readAsBytes();
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: _decodeTargetWidth,
    );
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final w = image.width;
    final h = image.height;
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    codec.dispose();
    return (byteData!.buffer.asUint8List(), w, h);
  }

  /// Analyze an image file (slow path — file I/O + decode).
  Future<ScoringResult> analyze(String imagePath) async {
    if (_usingFallback && _fallbackService != null) {
      return _fallbackService!.analyzeImage(imagePath);
    }

    if (!_ready || _sendPort == null) {
      return ScoringResult(
        calibrationPoints: [],
        dartTips: [],
        scores: [],
        totalScore: 0,
        error: 'Isolate not ready',
      );
    }

    final (Uint8List rgba, int w, int h) = await _decodeNative(imagePath);
    return analyzeRgba(rgba, w, h);
  }

  /// Analyze raw RGBA pixels directly — no file I/O.
  /// Uses TransferableTypedData for zero-copy transfer to the isolate.
  Future<ScoringResult> analyzeRgba(Uint8List rgba, int w, int h) async {
    if (_usingFallback && _fallbackService != null) {
      return _fallbackService!.analyzeRgba(rgba, w, h);
    }

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

    // Zero-copy transfer: O(1) instead of copying ~3MB RGBA data.
    final transferable = TransferableTypedData.fromList([rgba]);
    _sendPort!.send(_AnalyzeRgbaRequest(id, transferable, w, h));

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
    _fallbackService?.dispose();
    _fallbackService = null;
    _isolate = null;
    _sendPort = null;
    _ready = false;
    _usingFallback = false;
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
  @pragma('vm:entry-point')
  static void _isolateEntry(_InitMessage init) async {
    final port = ReceivePort();
    init.mainPort.send(port.sendPort);

    late final DartDetectionService service;
    try {
      // Load model from temp file with 1 thread.
      // 1 thread avoids Flutter CPU-affinity contention that can make
      // multi-threaded isolate inference 4-16x slower.
      service = DartDetectionService(useNativeDecode: false);
      service.loadModelFromFile(File(init.modelPath), threads: 1);
      init.mainPort.send(const _InitStatus(ok: true));
      debugPrint('[DetectionIsolate] Model loaded (1 thread, from file)');
    } catch (e) {
      init.mainPort.send(_InitStatus(ok: false, error: e.toString()));
      return;
    }

    await for (final message in port) {
      if (message is _AnalyzeRgbaRequest) {
        try {
          // Materialize the zero-copy transferred bytes.
          final rgba = message.transferable.materialize().asUint8List();
          final result = await service.analyzeRgba(
            rgba, message.width, message.height,
          );
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
  final String modelPath;
  _InitMessage(this.mainPort, this.modelPath);
}

class _AnalyzeRgbaRequest {
  final int id;
  final TransferableTypedData transferable;
  final int width;
  final int height;
  _AnalyzeRgbaRequest(this.id, this.transferable, this.width, this.height);
}

class _AnalyzeResponse {
  final int id;
  final ScoringResult result;
  _AnalyzeResponse(this.id, this.result);
}

class _InitStatus {
  final bool ok;
  final String? error;
  const _InitStatus({required this.ok, this.error});
}
