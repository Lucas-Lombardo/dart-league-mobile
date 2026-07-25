import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode, kIsWeb;
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import 'dart_detection_service_io.dart'
    if (dart.library.html) 'dart_detection_service_web.dart';

import 'dart_scoring_service.dart';
import 'dart_detection_types.dart';
import 'detection_parsing.dart';
import 'model_selector.dart';
export 'dart_detection_types.dart';

// ---------------------------------------------------------------------------
// DartsMind model constants  (Detector.java)
// Confidence/IoU thresholds and labels live in detection_parsing.dart so the
// parse isolate and the inline path share a single definition.
// ---------------------------------------------------------------------------
const int _modelInputSize = 1024;
const double _iouThresholdTip = kIouThresholdTip;
const int _maxDarts = 3;
const double _dartNmsMinDist = 0.004;

class DartDetectionService {
  Interpreter? _interpreter;
  bool _isLoaded = false;
  final bool useNativeDecode;

  DartDetectionService({this.useNativeDecode = true});

  Float32List? _inputBuffer;
  Uint8List? _outputBytes;
  List<int>? _outputShape;

  // Cached calibration (4 control points with flags).
  List<Detection>? _lastGoodCalib;

  bool get isLoaded => _isLoaded;

  Future<void> loadModel({bool cpuOnly = false}) async {
    if (_isLoaded) return;

    if (kIsWeb) {
      final cpuOptions = InterpreterOptions()..threads = 4;
      _interpreter = await Interpreter.fromAsset(
        ModelSelector.currentAsset,
        options: cpuOptions,
      );
      debugPrint('[DartDetection] Model loaded on web with CPU (4 threads)');
      _isLoaded = true;
    } else {
      _interpreter = await loadModelNative(cpuOnly: cpuOnly);
      _isLoaded = true;
    }

    _allocateBuffers();
  }

  void loadModelFromBuffer(Uint8List modelBytes) {
    if (_isLoaded) return;
    final cpuOptions = InterpreterOptions()..threads = 4;
    _interpreter = Interpreter.fromBuffer(modelBytes, options: cpuOptions);
    debugPrint('[DartDetection] Model loaded from buffer on CPU with 4 threads');
    _isLoaded = true;
    _allocateBuffers();
  }

  void loadModelFromFile(File modelFile, {int threads = 4}) {
    if (_isLoaded) return;
    final cpuOptions = InterpreterOptions()..threads = threads;
    _interpreter = Interpreter.fromFile(modelFile, options: cpuOptions);
    debugPrint('[DartDetection] Model loaded from file on CPU with $threads thread(s)');
    _isLoaded = true;
    _allocateBuffers();
  }

  void _allocateBuffers() {
    _inputBuffer = Float32List(1 * _modelInputSize * _modelInputSize * 3);
    final outputTensors = _interpreter!.getOutputTensors();
    final outputShape = outputTensors[0].shape;
    _outputShape = outputShape;
    final outputByteSize = outputShape.fold<int>(1, (a, b) => a * b) * 4;
    _outputBytes = Uint8List(outputByteSize);
    final inputTensors = _interpreter!.getInputTensors();
    debugPrint('[DartDetection] Model loaded');
    debugPrint(
        '[DartDetection] Input: ${inputTensors.map((t) => '${t.shape} ${t.type}').join(', ')}');
    debugPrint(
        '[DartDetection] Output: ${outputTensors.map((t) => '${t.shape} ${t.type}').join(', ')}');
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _inputBuffer = null;
    _outputBytes = null;
    _outputShape = null;
    _lastGoodCalib = null;
    _isLoaded = false;
  }

  // ---- Image decode -------------------------------------------------------

  Future<(Uint8List, int, int)> _decodeImageNative(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: _modelInputSize,
    );
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final w = image.width;
    final h = image.height;
    final byteData =
        await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    codec.dispose();
    return (byteData!.buffer.asUint8List(), w, h);
  }

  (Uint8List, int, int) _decodeImagePure(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) throw Exception('Failed to decode image');
    final resized = decoded.width > _modelInputSize
        ? img.copyResize(decoded, width: _modelInputSize)
        : decoded;
    final rgba = resized.getBytes(order: img.ChannelOrder.rgba);
    return (Uint8List.fromList(rgba), resized.width, resized.height);
  }

  // ---- Preprocessing (DartsMind: top-left scale, black background) --------

  /// Matches DartsMind's `convertToInputSizeBitmap` exactly:
  /// - Uniform scale to fit within 1024×1024
  /// - Anchored at top-left (0,0)
  /// - Black background (0.0) for padding
  /// - Normalises RGB to [0,1] by dividing by 255
  ///
  /// Returns (xScale, yScale, origW, origH) for coordinate remapping.
  (double, double, int, int) _preprocessDirect(
    Uint8List rgba,
    int origW,
    int origH,
  ) {
    final input = _inputBuffer!;
    const sz = _modelInputSize;

    // Uniform scale to fit within canvas (same as DartsMind)
    final scale = min(sz / origW, sz / origH).toDouble();
    final newW = (origW * scale).round();
    final newH = (origH * scale).round();

    // DartsMind coordinate remapping: xScale / yScale
    final double xScale;
    final double yScale;
    if (origW >= origH) {
      xScale = 1.0;
      yScale = origW / origH;
    } else {
      xScale = origH / origW;
      yScale = 1.0;
    }

    final srcStride = origW * 4; // RGBA bytes per row
    final invNewW = origW / newW; // map dest pixel → source pixel
    final invNewH = origH / newH;

    int idx = 0;
    for (int y = 0; y < sz; y++) {
      if (y >= newH) {
        // Black padding rows (below image)
        for (int x = 0; x < sz; x++) {
          input[idx] = 0.0;
          input[idx + 1] = 0.0;
          input[idx + 2] = 0.0;
          idx += 3;
        }
        continue;
      }
      final srcY = (y * invNewH).toInt().clamp(0, origH - 1);
      final rowOffset = srcY * srcStride;

      for (int x = 0; x < sz; x++) {
        if (x >= newW) {
          // Black padding columns (right of image)
          input[idx] = 0.0;
          input[idx + 1] = 0.0;
          input[idx + 2] = 0.0;
          idx += 3;
          continue;
        }
        final srcX = (x * invNewW).toInt().clamp(0, origW - 1);
        final pixelOffset = rowOffset + srcX * 4;
        input[idx] = rgba[pixelOffset] / 255.0;
        input[idx + 1] = rgba[pixelOffset + 1] / 255.0;
        input[idx + 2] = rgba[pixelOffset + 2] / 255.0;
        idx += 3;
      }
    }
    return (xScale, yScale, origW, origH);
  }

  // ---- Output parsing (DartsMind: findBestBox) ----------------------------

  /// Shared implementation in detection_parsing.dart (also run by the parse
  /// isolate — keep a single definition).
  List<Detection> _parseOutput(
    Float32List floats,
    List<int> shape, {
    required double xScale,
    required double yScale,
  }) =>
      parseOutputFloats(floats, shape, xScale: xScale, yScale: yScale);

  // ---- Class-specific NMS (DartsMind: classSpecificNMS) -------------------

  List<Detection> _classSpecificNMS(List<Detection> detections) =>
      classSpecificNms(detections);

  // ---- Control point extraction (extract4CPs equivalent) ------------------

  /// Select best 4 control points from p1-p8 detections.
  /// Picks highest-confidence per quadrant:
  ///   Q1 (upper-right): p1, p2   Q2 (lower-right): p3, p4
  ///   Q3 (lower-left):  p5, p6   Q4 (upper-left):  p7, p8
  List<Detection> _extract4CPs(List<Detection> controlPoints) {
    if (controlPoints.isEmpty) return [];

    final quadrants = <int, List<Detection>>{};
    for (final cp in controlPoints) {
      final q = cp.classId ~/ 2; // 0=Q1, 1=Q2, 2=Q3, 3=Q4
      quadrants.putIfAbsent(q, () => []).add(cp);
    }

    final selected = <Detection>[];
    for (int q = 0; q < 4; q++) {
      final group = quadrants[q];
      if (group == null || group.isEmpty) continue;
      group.sort((a, b) => b.confidence.compareTo(a.confidence));
      selected.add(group.first);
    }

    if (selected.length == 4) return selected;

    // Fallback: pick 4 best from different classes
    if (selected.length < 4 && controlPoints.length >= 4) {
      final sorted = List<Detection>.from(controlPoints)
        ..sort((a, b) => b.confidence.compareTo(a.confidence));
      final bestByClass = <int, Detection>{};
      for (final cp in sorted) {
        bestByClass.putIfAbsent(cp.classId, () => cp);
        if (bestByClass.length >= 4) break;
      }
      if (bestByClass.length >= 4) {
        return bestByClass.values.take(4).toList();
      }
    }

    return selected;
  }

  /// Fallback to cached calibration when < 4 points detected.
  List<Detection> _applyCalibFallback(List<Detection> current) {
    if (current.length >= 4) {
      _lastGoodCalib = List.of(current);
      return current;
    }

    if (current.isEmpty || _lastGoodCalib == null) return current;

    const matchDist = 0.04;
    final usedCached = <int>{};
    for (final det in current) {
      bool matched = false;
      for (int i = 0; i < _lastGoodCalib!.length; i++) {
        if (usedCached.contains(i)) continue;
        final dist = sqrt(
          pow(det.x - _lastGoodCalib![i].x, 2) +
              pow(det.y - _lastGoodCalib![i].y, 2),
        );
        if (dist < matchDist) {
          usedCached.add(i);
          matched = true;
          break;
        }
      }
      if (!matched) {
        _lastGoodCalib = null;
        return current;
      }
    }

    debugPrint(
        '[Calib] ${current.length}/4 control points match cache — using fallback');
    return _lastGoodCalib!;
  }

  // ---- Dart filtering -----------------------------------------------------

  (List<Detection>, List<String>) _filterDarts(List<Detection> darts) {
    if (darts.isEmpty) return (darts, []);

    final logs = <String>[];
    final sorted = List<Detection>.from(darts)
      ..sort((a, b) => b.confidence.compareTo(a.confidence));

    logs.add('[Filter] Raw tips before filtering: ${sorted.length}');

    final kept = <Detection>[];
    for (final d in sorted) {
      bool suppressed = false;
      for (final k in kept) {
        final iou = detectionIou(d, k);
        final dist = sqrt(pow(d.x - k.x, 2) + pow(d.y - k.y, 2));
        if (iou > _iouThresholdTip) {
          suppressed = true;
          break;
        }
        if (dist < _dartNmsMinDist) {
          suppressed = true;
          break;
        }
      }
      if (!suppressed) kept.add(d);
      if (kept.length >= _maxDarts) break;
    }
    return (kept, logs);
  }

  // ---- Main analysis entry points -----------------------------------------

  /// Core analysis: preprocess → inference → parse → filter → score.
  /// Parse raw TFLite output tensor into a [ScoringResult].
  /// Used by [NativeInference] to parse output from native-side inference.
  /// The model's output shape is [1, 13, 21504].
  ScoringResult parseRawOutput(
    Float32List outputFloats,
    double xScale,
    double yScale,
    int imgW,
    int imgH,
  ) {
    // Ensure output shape is set even if model wasn't loaded via this instance.
    _outputShape ??= [1, 13, 21504];
    return _analyze(outputFloats, xScale, yScale, imgW, imgH, 0, 0);
  }

  ScoringResult _analyze(
    Float32List outputFloats,
    double xScale,
    double yScale,
    int imgW,
    int imgH,
    int preprocessMs,
    int inferenceMs,
  ) {
    final sw = Stopwatch()..start();
    var detections = _parseOutput(
      outputFloats,
      _outputShape!,
      xScale: xScale,
      yScale: yScale,
    );
    detections = _classSpecificNMS(detections);
    final parseMs = sw.elapsedMilliseconds;
    return scoreParsedDetections(
      detections,
      imgW,
      imgH,
      preprocessMs: preprocessMs,
      inferenceMs: inferenceMs,
      parseMs: parseMs,
    );
  }

  /// Post-NMS pipeline: control-point selection, calibration fallback, dart
  /// filtering, homography + scoring. Public so [NativeInference] can feed it
  /// detections that were parsed + NMS'd on the worker isolate
  /// (output_parse_isolate.dart) instead of the UI isolate.
  ScoringResult scoreParsedDetections(
    List<Detection> detections,
    int imgW,
    int imgH, {
    int preprocessMs = 0,
    int inferenceMs = 0,
    int parseMs = 0,
  }) {
    final sw = Stopwatch()..start();
    var controlPoints = detections.where((d) => d.isControlPoint).toList();
    var dartTips = detections.where((d) => d.isTip).toList();

    controlPoints = _extract4CPs(controlPoints);
    controlPoints = _applyCalibFallback(controlPoints);

    final (filteredDarts, filterLogs) = _filterDarts(dartTips);
    dartTips = filteredDarts;
    final filterMs = sw.elapsedMilliseconds;

    if (controlPoints.length < 4) {
      return ScoringResult(
        calibrationPoints: controlPoints,
        dartTips: dartTips,
        scores: [],
        totalScore: 0,
        imageWidth: imgW,
        imageHeight: imgH,
        error: 'Need 4 control points, found ${controlPoints.length}',
      );
    }

    if (dartTips.isEmpty) {
      return ScoringResult(
        calibrationPoints: controlPoints,
        dartTips: dartTips,
        scores: [],
        totalScore: 0,
        imageWidth: imgW,
        imageHeight: imgH,
        error: 'No darts detected',
      );
    }

    try {
      final calibData =
          controlPoints.map((c) => [c.x, c.y, c.flag.toDouble()]).toList();
      final scorer = DartScoringService(calibData);
      final scores = dartTips.map((d) => scorer.score(d.x, d.y)).toList();
      sw.stop();
      final scoreMs = sw.elapsedMilliseconds;
      final totalMs = preprocessMs + inferenceMs + parseMs + filterMs + scoreMs;

      if (kDebugMode) {
        for (final line in filterLogs) {
          debugPrint(line);
        }
        debugPrint('---------------------');
        debugPrint(
            '[Image] ${totalMs}ms | preprocess=$preprocessMs inference=$inferenceMs parse=$parseMs filter=$filterMs score=$scoreMs');
        for (int i = 0; i < scores.length; i++) {
          final d = dartTips[i];
          final s = scores[i];
          debugPrint(
              '[Dart $i] x=${d.x.toStringAsFixed(3)} y=${d.y.toStringAsFixed(3)} conf=${d.confidence.toStringAsFixed(2)} => ${s.formatted}');
        }
        debugPrint('---------------------');
      }

      final total = scores.fold<int>(0, (sum, s) => sum + s.score);
      return ScoringResult(
        calibrationPoints: controlPoints,
        dartTips: dartTips,
        scores: scores,
        totalScore: total,
        imageWidth: imgW,
        imageHeight: imgH,
      );
    } catch (e) {
      return ScoringResult(
        calibrationPoints: controlPoints,
        dartTips: dartTips,
        scores: [],
        totalScore: 0,
        imageWidth: imgW,
        imageHeight: imgH,
        error: 'Scoring error: $e',
      );
    }
  }

  Future<ScoringResult> analyzeRgba(Uint8List rgba, int imgW, int imgH) async {
    if (!_isLoaded) {
      return ScoringResult(
          calibrationPoints: [],
          dartTips: [],
          scores: [],
          totalScore: 0,
          error: 'Model not loaded');
    }

    final sw = Stopwatch()..start();
    final (xScale, yScale, _, _) = _preprocessDirect(rgba, imgW, imgH);
    final preprocessMs = sw.elapsedMilliseconds;

    _outputBytes!.fillRange(0, _outputBytes!.length, 0);
    sw.reset();
    _interpreter!.run(_inputBuffer!.buffer, _outputBytes!);
    final inferenceMs = sw.elapsedMilliseconds;

    final outputFloats = _outputBytes!.buffer.asFloat32List();
    return _analyze(
        outputFloats, xScale, yScale, imgW, imgH, preprocessMs, inferenceMs);
  }

  Future<ScoringResult> analyzeImage(String imagePath) async {
    if (!_isLoaded) {
      return ScoringResult(
          calibrationPoints: [],
          dartTips: [],
          scores: [],
          totalScore: 0,
          error: 'Model not loaded');
    }

    final sw = Stopwatch()..start();
    final bytes = await readImageBytes(imagePath);
    final readMs = sw.elapsedMilliseconds;

    sw.reset();
    final (Uint8List rgba, int imgW, int imgH) = useNativeDecode
        ? await _decodeImageNative(bytes)
        : _decodeImagePure(bytes);
    final decodeMs = sw.elapsedMilliseconds;

    sw.reset();
    final (xScale, yScale, _, _) = _preprocessDirect(rgba, imgW, imgH);
    final preprocessMs = sw.elapsedMilliseconds;

    _outputBytes!.fillRange(0, _outputBytes!.length, 0);
    sw.reset();
    _interpreter!.run(_inputBuffer!.buffer, _outputBytes!);
    final inferenceMs = sw.elapsedMilliseconds;

    if (kDebugMode) {
      debugPrint('[Image] read=${readMs}ms decode=${decodeMs}ms');
    }

    final outputFloats = _outputBytes!.buffer.asFloat32List();
    return _analyze(outputFloats, xScale, yScale, imgW, imgH,
        preprocessMs + readMs + decodeMs, inferenceMs);
  }
}
