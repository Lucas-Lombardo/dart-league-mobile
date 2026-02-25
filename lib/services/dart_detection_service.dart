import 'dart:math';
import 'dart:typed_data';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import 'dart_scoring_service.dart';
import 'dart_detection_types.dart';
export 'dart_detection_types.dart';

const int _modelInputSize = 640;
const double _defaultConfThreshold = 0.25;
const double _calibMergeDist = 0.03;
const int _maxDarts = 3;
const double _dartMinConf = 0.30;
const double _dartNmsIouThreshold = 0.70;
const double _dartNmsMinDist = 0.008;

class DartDetectionService {
  Interpreter? _interpreter;
  bool _isLoaded = false;
  final bool useNativeDecode;

  DartDetectionService({this.useNativeDecode = true});

  // Pre-allocated buffers (reused across frames)
  Float32List? _inputBuffer;
  List<List<List<double>>>? _outputBuffer;

  bool get isLoaded => _isLoaded;

  Future<void> loadModel() async {
    if (_isLoaded) return;

    // Use Metal GPU on iOS, GPU on Android, fallback to CPU with threads
    if (Platform.isIOS) {
      try {
        final gpuOptions = InterpreterOptions()
          ..addDelegate(GpuDelegate());
        _interpreter = await Interpreter.fromAsset(
          'assets/models/best_float16.tflite',
          options: gpuOptions,
        );
        print('[DartDetection] Model loaded with Metal GPU delegate');
      } catch (e) {
        print('[DartDetection] Metal GPU failed ($e), falling back to CPU');
        _interpreter = null;
      }
    } else if (Platform.isAndroid) {
      try {
        final gpuOptions = InterpreterOptions()
          ..addDelegate(GpuDelegateV2());
        _interpreter = await Interpreter.fromAsset(
          'assets/models/best_float16.tflite',
          options: gpuOptions,
        );
        print('[DartDetection] Model loaded with GPU delegate');
      } catch (e) {
        print('[DartDetection] GPU delegate failed ($e), falling back to CPU');
        _interpreter = null;
      }
    }

    // Fallback: CPU with multi-threading
    if (_interpreter == null) {
      final cpuOptions = InterpreterOptions()..threads = 4;
      _interpreter = await Interpreter.fromAsset(
        'assets/models/best_float16.tflite',
        options: cpuOptions,
      );
      print('[DartDetection] Model loaded on CPU with 4 threads');
    }
    _isLoaded = true;

    // Pre-allocate input buffer
    _inputBuffer = Float32List(1 * _modelInputSize * _modelInputSize * 3);

    // Pre-allocate output buffer
    final outputTensors = _interpreter!.getOutputTensors();
    final outputShape = outputTensors[0].shape;
    _outputBuffer = List.generate(
      outputShape[0],
      (_) => List.generate(
        outputShape[1],
        (_) => List.filled(outputShape[2], 0.0),
      ),
    );

    final inputTensors = _interpreter!.getInputTensors();
    print('[DartDetection] Model loaded');
    print('[DartDetection] Input: ${inputTensors.map((t) => '${t.shape} ${t.type}').join(', ')}');
    print('[DartDetection] Output: ${outputTensors.map((t) => '${t.shape} ${t.type}').join(', ')}');
  }

  /// Load model from pre-loaded bytes (for use in background isolates
  /// where ServicesBinding / asset bundle is not available).
  void loadModelFromBuffer(Uint8List modelBytes) {
    if (_isLoaded) return;

    // CPU with multi-threading (GPU delegates often fail in isolates)
    final cpuOptions = InterpreterOptions()..threads = 4;
    _interpreter = Interpreter.fromBuffer(modelBytes, options: cpuOptions);
    print('[DartDetection] Model loaded from buffer on CPU with 4 threads');
    _isLoaded = true;

    // Pre-allocate input buffer
    _inputBuffer = Float32List(1 * _modelInputSize * _modelInputSize * 3);

    // Pre-allocate output buffer
    final outputTensors = _interpreter!.getOutputTensors();
    final outputShape = outputTensors[0].shape;
    _outputBuffer = List.generate(
      outputShape[0],
      (_) => List.generate(
        outputShape[1],
        (_) => List.filled(outputShape[2], 0.0),
      ),
    );

    final inputTensors = _interpreter!.getInputTensors();
    print('[DartDetection] Model loaded');
    print('[DartDetection] Input: ${inputTensors.map((t) => '${t.shape} ${t.type}').join(', ')}');
    print('[DartDetection] Output: ${outputTensors.map((t) => '${t.shape} ${t.type}').join(', ')}');
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _inputBuffer = null;
    _outputBuffer = null;
    _isLoaded = false;
  }

  /// Decode image bytes using dart:ui (native, much faster than `image` package).
  /// Downsamples at decode time if the image is larger than needed.
  Future<(Uint8List, int, int)> _decodeImageNative(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: _modelInputSize,
    );
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final w = image.width;
    final h = image.height;
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    return (byteData!.buffer.asUint8List(), w, h);
  }

  /// Decode image bytes using package:image (works in background isolates).
  (Uint8List, int, int) _decodeImagePure(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) throw Exception('Failed to decode image');
    // Resize down to reduce preprocessing work (similar to native targetWidth)
    final resized = decoded.width > _modelInputSize
        ? img.copyResize(decoded, width: _modelInputSize)
        : decoded;
    final rgba = resized.getBytes(order: img.ChannelOrder.rgba);
    return (Uint8List.fromList(rgba), resized.width, resized.height);
  }

  /// Letterbox RGBA pixel data directly into the pre-allocated Float32List.
  /// Single-pass: nearest-neighbor sampling, writes RGB into NHWC tensor.
  /// Returns (scale, padX, padY, origW, origH).
  (double, int, int, int, int) _preprocessDirect(
    Uint8List rgba, int origW, int origH,
  ) {
    final input = _inputBuffer!;
    const sz = _modelInputSize;
    const gray = 114.0 / 255.0;

    // Letterbox geometry
    final scale = min(sz / origW, sz / origH).toDouble();
    final newW = (origW * scale).round();
    final newH = (origH * scale).round();
    final padX = (sz - newW) ~/ 2;
    final padY = (sz - newH) ~/ 2;

    final srcStride = origW * 4; // RGBA bytes per row
    final invNewW = origW / newW; // map dest pixel -> source pixel
    final invNewH = origH / newH;

    int idx = 0;
    for (int y = 0; y < sz; y++) {
      final inY = y - padY;
      if (inY < 0 || inY >= newH) {
        // Padding row — fill with gray
        for (int x = 0; x < sz; x++) {
          input[idx] = gray;
          input[idx + 1] = gray;
          input[idx + 2] = gray;
          idx += 3;
        }
        continue;
      }
      final srcY = (inY * invNewH).toInt().clamp(0, origH - 1);
      final rowOffset = srcY * srcStride;

      for (int x = 0; x < sz; x++) {
        final inX = x - padX;
        if (inX < 0 || inX >= newW) {
          input[idx] = gray;
          input[idx + 1] = gray;
          input[idx + 2] = gray;
          idx += 3;
          continue;
        }
        final srcX = (inX * invNewW).toInt().clamp(0, origW - 1);
        final pixelOffset = rowOffset + srcX * 4;
        input[idx] = rgba[pixelOffset] / 255.0;
        input[idx + 1] = rgba[pixelOffset + 1] / 255.0;
        input[idx + 2] = rgba[pixelOffset + 2] / 255.0;
        idx += 3;
      }
    }
    return (scale, padX, padY, origW, origH);
  }

  /// Sort 4 calibration points into order: D20 (top), D6 (right), D3 (bottom), D11 (left)
  List<Detection> _sortCalibPoints(List<Detection> pts) {
    if (pts.length != 4) return pts;

    final indexed = List.generate(4, (i) => i);
    // Sort by Y to find top (min y) and bottom (max y)
    indexed.sort((a, b) => pts[a].y.compareTo(pts[b].y));
    final topIdx = indexed[0];
    final bottomIdx = indexed[3];

    // Remaining two: left (min x) and right (max x)
    final remaining = indexed.sublist(1, 3);
    int leftIdx, rightIdx;
    if (pts[remaining[0]].x < pts[remaining[1]].x) {
      leftIdx = remaining[0];
      rightIdx = remaining[1];
    } else {
      leftIdx = remaining[1];
      rightIdx = remaining[0];
    }

    return [pts[topIdx], pts[rightIdx], pts[bottomIdx], pts[leftIdx]];
  }

  /// Parse YOLOv8 output tensor into detections.
  /// Remaps from letterboxed model space to original image [0,1] coords.
  List<Detection> _parseOutput(
    List<List<List<double>>> output, {
    double confThreshold = _defaultConfThreshold,
    required double scale,
    required int padX,
    required int padY,
    required int origW,
    required int origH,
  }) {
    final detections = <Detection>[];

    // YOLOv8 TFLite output shape: [1, 6, 8400]
    final data = output[0]; // [6][8400]
    final numDetections = data[0].length;
    final numRows = data.length;
    final numClasses = numRows - 4; // first 4 are bbox

    for (int i = 0; i < numDetections; i++) {
      // Find best class
      double maxConf = 0;
      int bestClass = 0;
      for (int c = 0; c < numClasses; c++) {
        final conf = data[4 + c][i];
        if (conf > maxConf) {
          maxConf = conf;
          bestClass = c;
        }
      }

      if (maxConf < confThreshold) continue;

      // Model outputs normalized [0,1] coords in the letterboxed space
      // Convert: normalized -> pixel in model input -> remove padding -> undo scale -> normalize to original
      final rawX = data[0][i];
      final rawY = data[1][i];
      final rawW = data[2][i];
      final rawH = data[3][i];

      final pixelX = rawX * _modelInputSize;
      final pixelY = rawY * _modelInputSize;
      final pixelW = rawW * _modelInputSize;
      final pixelH = rawH * _modelInputSize;

      final xCenter = (pixelX - padX) / (scale * origW);
      final yCenter = (pixelY - padY) / (scale * origH);
      final width = pixelW / (scale * origW);
      final height = pixelH / (scale * origH);

      // Skip if outside image bounds
      if (xCenter < -0.01 || xCenter > 1.01 || yCenter < -0.01 || yCenter > 1.01) continue;

      detections.add(Detection(
        classId: bestClass,
        x: xCenter.clamp(0.0, 1.0),
        y: yCenter.clamp(0.0, 1.0),
        width: width,
        height: height,
        confidence: maxConf,
      ));
    }

    return detections;
  }

  /// Filter calibration detections: merge close duplicates, cap at 4
  List<Detection> _filterCalibPoints(List<Detection> calibs) {
    if (calibs.isEmpty) return calibs;

    final sorted = List<Detection>.from(calibs)
      ..sort((a, b) => b.confidence.compareTo(a.confidence));

    final kept = <Detection>[];
    for (final d in sorted) {
      bool tooClose = false;
      for (final k in kept) {
        final dist = sqrt(pow(d.x - k.x, 2) + pow(d.y - k.y, 2));
        if (dist < _calibMergeDist) {
          tooClose = true;
          break;
        }
      }
      if (!tooClose) kept.add(d);
      if (kept.length >= 4) break;
    }
    return kept;
  }

  /// Compute bounding-box IoU between two detections.
  static double _iou(Detection a, Detection b) {
    final aLeft = a.x - a.width / 2;
    final aRight = a.x + a.width / 2;
    final aTop = a.y - a.height / 2;
    final aBottom = a.y + a.height / 2;

    final bLeft = b.x - b.width / 2;
    final bRight = b.x + b.width / 2;
    final bTop = b.y - b.height / 2;
    final bBottom = b.y + b.height / 2;

    final interLeft = max(aLeft, bLeft);
    final interRight = min(aRight, bRight);
    final interTop = max(aTop, bTop);
    final interBottom = min(aBottom, bBottom);

    if (interLeft >= interRight || interTop >= interBottom) return 0.0;

    final interArea = (interRight - interLeft) * (interBottom - interTop);
    final aArea = a.width * a.height;
    final bArea = b.width * b.height;
    final unionArea = aArea + bArea - interArea;

    return unionArea > 0 ? interArea / unionArea : 0.0;
  }

  /// Filter dart detections: drop low confidence, NMS by IoU, cap at max.
  /// Returns (kept, logLines) — log lines are deferred so caller can decide whether to print.
  (List<Detection>, List<String>) _filterDarts(List<Detection> darts) {
    if (darts.isEmpty) return (darts, []);

    final logs = <String>[];

    // Sort by confidence descending, drop below threshold
    final sorted = List<Detection>.from(darts)
      ..sort((a, b) => b.confidence.compareTo(a.confidence));
    sorted.removeWhere((d) => d.confidence < _dartMinConf);

    logs.add('[Filter] Raw darts before NMS: ${sorted.length}');
    for (int i = 0; i < sorted.length; i++) {
      final d = sorted[i];
      logs.add('[Filter]   [$i] x=${d.x.toStringAsFixed(3)} y=${d.y.toStringAsFixed(3)} conf=${d.confidence.toStringAsFixed(2)}');
    }

    final kept = <Detection>[];
    for (final d in sorted) {
      bool suppressed = false;
      String? reason;
      for (final k in kept) {
        final iou = _iou(d, k);
        final dist = sqrt(pow(d.x - k.x, 2) + pow(d.y - k.y, 2));
        if (iou > _dartNmsIouThreshold) {
          suppressed = true;
          reason = 'IoU=${iou.toStringAsFixed(3)} > $_dartNmsIouThreshold with kept (${k.x.toStringAsFixed(3)},${k.y.toStringAsFixed(3)})';
          break;
        }
        if (dist < _dartNmsMinDist) {
          suppressed = true;
          reason = 'dist=${dist.toStringAsFixed(4)} < $_dartNmsMinDist with kept (${k.x.toStringAsFixed(3)},${k.y.toStringAsFixed(3)})';
          break;
        }
      }
      if (!suppressed) {
        kept.add(d);
      } else {
        logs.add('[Filter]   DROPPED x=${d.x.toStringAsFixed(3)} y=${d.y.toStringAsFixed(3)} conf=${d.confidence.toStringAsFixed(2)} — $reason');
      }
      if (kept.length >= _maxDarts) break;
    }
    return (kept, logs);
  }

  /// Fast entry point: takes pre-decoded RGBA bytes + dimensions.
  /// Skips file read and image decode — caller is responsible for decoding
  /// (e.g. on the main thread with native dart:ui).
  Future<ScoringResult> analyzeRgba(Uint8List rgba, int imgW, int imgH) async {
    if (!_isLoaded) {
      return ScoringResult(
        calibrationPoints: [],
        dartTips: [],
        scores: [],
        totalScore: 0,
        error: 'Model not loaded',
      );
    }

    final sw = Stopwatch()..start();

    // Preprocess: single-pass letterbox directly into pre-allocated Float32List
    final (scale, padX, padY, origW, origH) = _preprocessDirect(rgba, imgW, imgH);
    final preprocessMs = sw.elapsedMilliseconds;

    final inputTensor = _inputBuffer!.reshape([1, _modelInputSize, _modelInputSize, 3]);

    // Zero the output buffer
    final output = _outputBuffer!;
    for (final row in output) {
      for (final col in row) {
        col.fillRange(0, col.length, 0.0);
      }
    }

    // Run inference
    sw.reset();
    _interpreter!.run(inputTensor, output);
    final inferenceMs = sw.elapsedMilliseconds;

    // Parse detections
    sw.reset();
    var detections = _parseOutput(
      output,
      scale: scale,
      padX: padX,
      padY: padY,
      origW: origW,
      origH: origH,
    );
    final parseMs = sw.elapsedMilliseconds;

    // Separate calibration points and darts
    var calibPoints = detections.where((d) => d.classId == 1).toList();
    var dartTips = detections.where((d) => d.classId == 0).toList();

    // Filter calibration points (merge close duplicates, cap at 4)
    sw.reset();
    calibPoints = _filterCalibPoints(calibPoints);
    calibPoints = _sortCalibPoints(calibPoints);
    final (filteredDarts, filterLogs) = _filterDarts(dartTips);
    dartTips = filteredDarts;
    final filterMs = sw.elapsedMilliseconds;

    final totalMs = preprocessMs + inferenceMs + parseMs + filterMs;

    if (calibPoints.length < 4) {
      sw.stop();
      return ScoringResult(
        calibrationPoints: calibPoints,
        dartTips: dartTips,
        scores: [],
        totalScore: 0,
        imageWidth: imgW,
        imageHeight: imgH,
        error: 'Need 4 calibration points, found ${calibPoints.length}',
      );
    }

    if (dartTips.isEmpty) {
      sw.stop();
      return ScoringResult(
        calibrationPoints: calibPoints,
        dartTips: dartTips,
        scores: [],
        totalScore: 0,
        imageWidth: imgW,
        imageHeight: imgH,
        error: 'No darts detected',
      );
    }

    try {
      final calibXY = calibPoints.map((c) => [c.x, c.y]).toList();
      final scorer = DartScoringService(calibXY);
      final scores = dartTips.map((d) => scorer.score(d.x, d.y)).toList();
      sw.stop();
      final scoreMs = sw.elapsedMilliseconds;
      for (final line in filterLogs) {
        print(line);
      }
      print('---------------------');
      print('[Image] ${totalMs + scoreMs} ms | preprocess=$preprocessMs inference=$inferenceMs parse=$parseMs filter=$filterMs score=$scoreMs');
      print('[Image] ${scores.length} dart(s)');
      for (int i = 0; i < scores.length; i++) {
        final d = dartTips[i];
        final s = scores[i];
        print('[Dart $i] x=${d.x.toStringAsFixed(3)} y=${d.y.toStringAsFixed(3)} conf=${d.confidence.toStringAsFixed(2)} => ${s.formatted}');
      }
      print('---------------------');
      final total = scores.fold<int>(0, (sum, s) => sum + s.score);
      return ScoringResult(
        calibrationPoints: calibPoints,
        dartTips: dartTips,
        scores: scores,
        totalScore: total,
        imageWidth: imgW,
        imageHeight: imgH,
      );
    } catch (e) {
      return ScoringResult(
        calibrationPoints: calibPoints,
        dartTips: dartTips,
        scores: [],
        totalScore: 0,
        imageWidth: imgW,
        imageHeight: imgH,
        error: 'Scoring error: $e',
      );
    }
  }

  /// Main entry point: take a picture file, detect darts, compute scores
  Future<ScoringResult> analyzeImage(String imagePath) async {
    if (!_isLoaded) {
      return ScoringResult(
        calibrationPoints: [],
        dartTips: [],
        scores: [],
        totalScore: 0,
        error: 'Model not loaded',
      );
    }

    final sw = Stopwatch()..start();

    // Load image bytes
    final bytes = await File(imagePath).readAsBytes();
    final readMs = sw.elapsedMilliseconds;

    // Decode image
    sw.reset();
    final (Uint8List rgba, int imgW, int imgH) = useNativeDecode
        ? await _decodeImageNative(bytes)
        : _decodeImagePure(bytes);
    final decodeMs = sw.elapsedMilliseconds;

    // Preprocess: single-pass letterbox directly into pre-allocated Float32List
    sw.reset();
    final (scale, padX, padY, origW, origH) = _preprocessDirect(rgba, imgW, imgH);
    final preprocessMs = sw.elapsedMilliseconds;

    final inputTensor = _inputBuffer!.reshape([1, _modelInputSize, _modelInputSize, 3]);

    // Zero the output buffer
    final output = _outputBuffer!;
    for (final row in output) {
      for (final col in row) {
        col.fillRange(0, col.length, 0.0);
      }
    }

    // Run inference
    sw.reset();
    _interpreter!.run(inputTensor, output);
    final inferenceMs = sw.elapsedMilliseconds;

    // Parse detections (remap from letterboxed model space to original image)
    sw.reset();
    var detections = _parseOutput(
      output,
      scale: scale,
      padX: padX,
      padY: padY,
      origW: origW,
      origH: origH,
    );
    final parseMs = sw.elapsedMilliseconds;

    // Separate calibration points and darts
    var calibPoints =
        detections.where((d) => d.classId == 1).toList();
    var dartTips =
        detections.where((d) => d.classId == 0).toList();

    // Filter calibration points (merge close duplicates, cap at 4)
    sw.reset();
    calibPoints = _filterCalibPoints(calibPoints);

    // Sort calibration points: D20 (top), D6 (right), D3 (bottom), D11 (left)
    calibPoints = _sortCalibPoints(calibPoints);

    // Filter darts (merge close ones, max 3)
    final (filteredDarts, filterLogs) = _filterDarts(dartTips);
    dartTips = filteredDarts;
    final filterMs = sw.elapsedMilliseconds;

    final totalMs = readMs + decodeMs + preprocessMs + inferenceMs + parseMs + filterMs;


    // Score darts
    if (calibPoints.length < 4) {
      sw.stop();
      return ScoringResult(
        calibrationPoints: calibPoints,
        dartTips: dartTips,
        scores: [],
        totalScore: 0,
        imageWidth: imgW,
        imageHeight: imgH,
        error: 'Need 4 calibration points, found ${calibPoints.length}',
      );
    }

    if (dartTips.isEmpty) {
      sw.stop();
      return ScoringResult(
        calibrationPoints: calibPoints,
        dartTips: dartTips,
        scores: [],
        totalScore: 0,
        imageWidth: imgW,
        imageHeight: imgH,
        error: 'No darts detected',
      );
    }

    try {
      final calibXY =
          calibPoints.map((c) => [c.x, c.y]).toList();
      final scorer = DartScoringService(calibXY);
      final scores =
          dartTips.map((d) => scorer.score(d.x, d.y)).toList();
      sw.stop();
      final scoreMs = sw.elapsedMilliseconds;
      for (final line in filterLogs) {
        print(line);
      }
      print('---------------------');
      print('[Image] ${totalMs + scoreMs} ms | read=$readMs decode=$decodeMs preprocess=$preprocessMs inference=$inferenceMs parse=$parseMs filter=$filterMs score=$scoreMs');
      print('[Image] ${scores.length} dart(s)');
      for (int i = 0; i < scores.length; i++) {
        final d = dartTips[i];
        final s = scores[i];
        print('[Dart $i] x=${d.x.toStringAsFixed(3)} y=${d.y.toStringAsFixed(3)} conf=${d.confidence.toStringAsFixed(2)} => ${s.formatted}');
      }
      print('---------------------');
      final total = scores.fold<int>(0, (sum, s) => sum + s.score);

      return ScoringResult(
        calibrationPoints: calibPoints,
        dartTips: dartTips,
        scores: scores,
        totalScore: total,
        imageWidth: imgW,
        imageHeight: imgH,
      );
    } catch (e) {
      return ScoringResult(
        calibrationPoints: calibPoints,
        dartTips: dartTips,
        scores: [],
        totalScore: 0,
        imageWidth: imgW,
        imageHeight: imgH,
        error: 'Scoring error: $e',
      );
    }
  }
}
