import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'dart_detection_service_stub.dart'
    if (dart.library.io) 'dart_detection_service.dart';
import 'dart_scoring_service.dart';
import 'detection_isolate_stub.dart'
    if (dart.library.io) 'detection_isolate.dart';

const double _dartMatchDist = 0.03;

/// Callback type for capturing a frame. Returns the file path of the
/// captured image, or null on failure. The caller is responsible for
/// providing the platform-specific capture logic (Agora snapshot,
/// camera takePicture, etc).
typedef CaptureFrameCallback = Future<String?> Function();

/// Optional callback to clean up a snapshot file after processing.
typedef CleanupFileCallback = Future<void> Function(String path);

/// Called when a new dart is detected in a slot (slot index, DartScore).
typedef OnDartDetectedCallback = void Function(int slotIndex, DartScore score);

class ConfirmedDart {
  final double x, y;
  final double confidence;
  final DartScore score;

  ConfirmedDart({
    required this.x,
    required this.y,
    required this.confidence,
    required this.score,
  });
}

/// Orchestrates the auto-scoring capture loop, model inference,
/// and sticky dart memory. Exposes state via ChangeNotifier.
///
/// On web: does nothing (auto-scoring not supported).
class AutoScoringService extends ChangeNotifier {
  final DetectionIsolate _isolate = DetectionIsolate();

  // Capture callback — injected by caller
  CaptureFrameCallback? _captureFrame;
  CleanupFileCallback? _cleanupFile;
  OnDartDetectedCallback? _onDartDetected;

  // Capture state
  bool _capturing = false;
  int _captureSeq = 0;
  bool _modelLoaded = false;
  String? _initError;

  // Game state — 3 dart slots
  List<DartScore?> _dartSlots = [null, null, null];
  int _turnTotal = 0;

  // Sticky dart memory
  List<ConfirmedDart?> _confirmedDarts = [null, null, null];
  int _prevDartCount = 0;

  // Zoom hint
  String? _zoomHint;

  // Inference timing
  int? _lastInferenceMs;

  // Dart removal detection — triggers "opponent turn" in unranked mode
  bool _dartsRemoved = false;

  // Getters
  bool get isCapturing => _capturing;
  bool get modelLoaded => _modelLoaded;
  String? get initError => _initError;
  List<DartScore?> get dartSlots => List.unmodifiable(_dartSlots);
  int get turnTotal => _turnTotal;
  String? get zoomHint => _zoomHint;
  int? get lastInferenceMs => _lastInferenceMs;
  bool get dartsRemoved => _dartsRemoved;
  int get detectedDartCount => _confirmedDarts.where((d) => d != null).length;

  /// Returns true if auto-scoring is supported on this platform
  static bool get isSupported => !kIsWeb;

  /// Initialize with a capture callback and optional file cleanup callback.
  /// [captureFrame] should return a file path to a captured image.
  /// [cleanupFile] optionally deletes the temp file after processing.
  Future<void> init({
    required CaptureFrameCallback captureFrame,
    CleanupFileCallback? cleanupFile,
    OnDartDetectedCallback? onDartDetected,
  }) async {
    _captureFrame = captureFrame;
    _cleanupFile = cleanupFile;
    _onDartDetected = onDartDetected;
    await _loadModel();
  }

  Future<void> _loadModel() async {
    if (!isSupported) return;
    try {
      await _isolate.start();
      _modelLoaded = true;
      _initError = null;
    } catch (e) {
      _initError = 'Model loading failed: $e';
      _modelLoaded = false;
    }
    notifyListeners();
  }

  /// Start the auto-capture loop
  void startCapture() {
    if (!_modelLoaded || _capturing) return;
    _capturing = true;
    _dartsRemoved = false;
    notifyListeners();
    _captureLoop();
  }

  /// Stop the auto-capture loop
  void stopCapture() {
    _capturing = false;
    notifyListeners();
  }

  /// Reset for a new turn — clears all dart slots and memory
  void resetTurn() {
    _dartSlots = [null, null, null];
    _turnTotal = 0;
    _confirmedDarts = [null, null, null];
    _prevDartCount = 0;
    _dartsRemoved = false;
    _zoomHint = null;
    _lastInferenceMs = null;
    notifyListeners();
  }

  /// Override a specific dart slot with a manual score (from edit modal)
  void overrideDart(int index, DartScore score) {
    if (index < 0 || index > 2) return;
    _dartSlots[index] = score;
    // Also update confirmed dart memory so it doesn't get overwritten
    _confirmedDarts[index] = ConfirmedDart(
      x: 0,
      y: 0,
      confidence: 1.0, // Manual override = max confidence
      score: score,
    );
    _turnTotal = _dartSlots.fold<int>(0, (sum, s) => sum + (s?.score ?? 0));
    notifyListeners();
  }

  /// Clear a specific dart slot
  void clearDart(int index) {
    if (index < 0 || index > 2) return;
    _dartSlots[index] = null;
    _confirmedDarts[index] = null;
    _turnTotal = _dartSlots.fold<int>(0, (sum, s) => sum + (s?.score ?? 0));
    notifyListeners();
  }

  Future<void> _captureLoop() async {
    while (_capturing) {
      final cycleSw = Stopwatch()..start();
      await _fireCapture();
      cycleSw.stop();
      print('[AutoScoring] Full cycle: ${cycleSw.elapsedMilliseconds} ms');
    }
  }

  Future<void> _fireCapture() async {
    if (_captureFrame == null) return;

    final seq = ++_captureSeq;
    String? imagePath;

    try {
      final captureSw = Stopwatch()..start();
      imagePath = await _captureFrame!();
      captureSw.stop();
      print('[AutoScoring] Snapshot capture: ${captureSw.elapsedMilliseconds} ms');

      if (imagePath == null || seq != _captureSeq || !_capturing) return;

      final stopwatch = Stopwatch()..start();
      final result = await _isolate.analyze(imagePath);
      stopwatch.stop();
      print('[AutoScoring] Isolate analyze: ${stopwatch.elapsedMilliseconds} ms');

      // Discard if a newer capture has been fired
      if (seq != _captureSeq || !_capturing) return;

      _lastInferenceMs = stopwatch.elapsedMilliseconds;

      final dartCount = result.dartTips.length;

      // Update zoom hint
      _updateZoomHint(result);

      // Detect dart removal (darts were on board, now 0)
      if (_prevDartCount > 0 && dartCount == 0) {
        _prevDartCount = 0;
        _dartsRemoved = true;
        notifyListeners();
        return;
      }
      _prevDartCount = dartCount;

      // Update confirmed darts with sticky memory
      _updateConfirmedDarts(result);

      // Clean up snapshot file to avoid filling temp dir
      if (_cleanupFile != null) {
        try {
          await _cleanupFile!(imagePath);
        } catch (_) {}
      }

      notifyListeners();
    } catch (e) {
      print('[AutoScoring] Capture error: $e');
    }
  }

  void _updateConfirmedDarts(ScoringResult result) {
    // Build detected darts list (only those with scores)
    final detected = <ConfirmedDart>[];
    for (int i = 0; i < result.dartTips.length && i < result.scores.length; i++) {
      detected.add(ConfirmedDart(
        x: result.dartTips[i].x,
        y: result.dartTips[i].y,
        confidence: result.dartTips[i].confidence,
        score: result.scores[i],
      ));
    }

    final matchedDetected = <int>{};

    // Pass 1: match detected darts to existing confirmed slots by proximity
    for (int s = 0; s < 3; s++) {
      if (_confirmedDarts[s] == null) continue;

      int bestIdx = -1;
      double bestDist = _dartMatchDist;
      for (int d = 0; d < detected.length; d++) {
        if (matchedDetected.contains(d)) continue;
        final dist = sqrt(
          pow(detected[d].x - _confirmedDarts[s]!.x, 2) +
          pow(detected[d].y - _confirmedDarts[s]!.y, 2),
        );
        if (dist < bestDist) {
          bestDist = dist;
          bestIdx = d;
        }
      }

      if (bestIdx >= 0) {
        matchedDetected.add(bestIdx);
        // Update position + score if confidence is equal or higher
        if (detected[bestIdx].confidence >= _confirmedDarts[s]!.confidence) {
          _confirmedDarts[s] = detected[bestIdx];
        }
      }
      // If not re-detected → keep as-is (sticky)
    }

    // Pass 2: add unmatched detected darts to empty slots
    for (int d = 0; d < detected.length; d++) {
      if (matchedDetected.contains(d)) continue;
      for (int s = 0; s < 3; s++) {
        if (_confirmedDarts[s] == null) {
          _confirmedDarts[s] = detected[d];
          print('[AutoScoring] New dart in slot $s: ${detected[d].score.formatted} conf=${detected[d].confidence.toStringAsFixed(2)}');
          // Notify caller so they can emit throw_dart immediately
          _onDartDetected?.call(s, detected[d].score);
          break;
        }
      }
    }

    // Sync display slots
    for (int i = 0; i < 3; i++) {
      _dartSlots[i] = _confirmedDarts[i]?.score;
    }
    _turnTotal = _dartSlots.fold<int>(0, (sum, s) => sum + (s?.score ?? 0));
  }

  void _updateZoomHint(ScoringResult result) {
    final calibs = result.calibrationPoints;
    if (calibs.length < 4) {
      _zoomHint = calibs.isEmpty ? 'Dartboard not detected' : 'Board not fully visible';
      return;
    }

    double minX = 1, maxX = 0, minY = 1, maxY = 0;
    for (final c in calibs) {
      minX = min(minX, c.x);
      maxX = max(maxX, c.x);
      minY = min(minY, c.y);
      maxY = max(maxY, c.y);
    }
    final spread = max(maxX - minX, maxY - minY);

    if (spread < 0.50) {
      _zoomHint = 'Zoom in — board too far';
    } else if (spread > 0.85) {
      _zoomHint = 'Zoom out — board too close';
    } else {
      _zoomHint = null;
    }
  }

  @override
  void dispose() {
    _capturing = false;
    _isolate.dispose();
    super.dispose();
  }
}
