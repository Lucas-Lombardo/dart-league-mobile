import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'dart_detection_service_stub.dart'
    if (dart.library.io) 'dart_detection_service.dart';
import 'dart_scoring_service.dart';
import 'detection_isolate_stub.dart'
    if (dart.library.io) 'detection_isolate.dart';

const double _dartMatchDist = 0.03;
const Duration _minCycleInterval = Duration(milliseconds: 800);

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

  // Which slots have already fired _onDartDetected (prevents duplicate socket events)
  List<bool> _emittedSlots = [false, false, false];

  // Which slots have been manually overridden (AI must not overwrite them)
  List<bool> _manualOverrideSlots = [false, false, false];

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

  /// Load the AI model. Call this once before startCapture().
  Future<void> loadModel() async {
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

  /// Start the auto-capture loop.
  /// [captureFrame] returns a file path to the captured image.
  /// [cleanupFile] optionally deletes the temp file after processing.
  /// [onDartDetected] called when a new dart is confirmed in a slot.
  void startCapture({
    required CaptureFrameCallback captureFrame,
    CleanupFileCallback? cleanupFile,
    OnDartDetectedCallback? onDartDetected,
  }) {
    if (!_modelLoaded || _capturing) return;
    _capturing = true;
    _dartsRemoved = false;
    notifyListeners();
    _captureLoop(captureFrame, cleanupFile, onDartDetected);
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
    _emittedSlots = [false, false, false];
    _manualOverrideSlots = [false, false, false];
    _prevDartCount = 0;
    _dartsRemoved = false;
    _zoomHint = null;
    _lastInferenceMs = null;
    notifyListeners();
  }

  /// Sync emitted slot state with the backend's dart count (e.g. after undo).
  /// Rolls back any slots beyond [confirmedCount] so the AI can re-detect them.
  void syncEmittedCount(int confirmedCount) {
    for (int i = confirmedCount; i < 3; i++) {
      _dartSlots[i] = null;
      _confirmedDarts[i] = null;
      _emittedSlots[i] = false;
      _manualOverrideSlots[i] = false;
    }
    _turnTotal = _dartSlots.fold<int>(0, (sum, s) => sum + (s?.score ?? 0));
    notifyListeners();
  }

  /// Override a specific dart slot with a manual score (from edit modal)
  void overrideDart(int index, DartScore score) {
    if (index < 0 || index > 2) return;
    _dartSlots[index] = score;
    _manualOverrideSlots[index] = true;
    // Preserve the original physical position if the AI already detected this
    // dart, so Pass 1 continues to consume/match that tip on subsequent frames
    // and it doesn't bleed into the next empty slot in Pass 2.
    final existingX = _confirmedDarts[index]?.x ?? 0.0;
    final existingY = _confirmedDarts[index]?.y ?? 0.0;
    _confirmedDarts[index] = ConfirmedDart(
      x: existingX,
      y: existingY,
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
    _emittedSlots[index] = false;
    _manualOverrideSlots[index] = false;
    _turnTotal = _dartSlots.fold<int>(0, (sum, s) => sum + (s?.score ?? 0));
    notifyListeners();
  }

  Future<void> _captureLoop(
    CaptureFrameCallback captureFrame,
    CleanupFileCallback? cleanupFile,
    OnDartDetectedCallback? onDartDetected,
  ) async {
    while (_capturing) {
      final cycleSw = Stopwatch()..start();
      await _fireCapture(captureFrame, cleanupFile, onDartDetected);

      // Enforce minimum interval to avoid hammering the camera API
      final remaining = _minCycleInterval.inMilliseconds - cycleSw.elapsedMilliseconds;
      if (remaining > 0 && _capturing) {
        await Future.delayed(Duration(milliseconds: remaining));
      }
    }
  }

  Future<void> _fireCapture(
    CaptureFrameCallback captureFrame,
    CleanupFileCallback? cleanupFile,
    OnDartDetectedCallback? onDartDetected,
  ) async {
    final seq = ++_captureSeq;
    String? imagePath;

    try {
      imagePath = await captureFrame();

      if (imagePath == null || seq != _captureSeq || !_capturing) {
        await _maybeCleanup(imagePath, cleanupFile);
        return;
      }

      final result = await _isolate.analyze(imagePath);

      // Discard if a newer capture has been fired
      if (seq != _captureSeq || !_capturing) {
        await _maybeCleanup(imagePath, cleanupFile);
        return;
      }

      _lastInferenceMs = 0;

      final dartCount = result.dartTips.length;

      // Update zoom hint
      _updateZoomHint(result);

      // Detect dart removal (darts were on board, now 0)
      if (_prevDartCount > 0 && dartCount == 0) {
        _prevDartCount = 0;
        _dartsRemoved = true;
        await _maybeCleanup(imagePath, cleanupFile);
        notifyListeners();
        return;
      }
      _prevDartCount = dartCount;

      // Update confirmed darts with sticky memory
      _updateConfirmedDarts(result, onDartDetected);

      // Clean up snapshot file to avoid filling temp dir
      await _maybeCleanup(imagePath, cleanupFile);

      notifyListeners();
    } catch (e) {
      await _maybeCleanup(imagePath, cleanupFile);
      print('[AutoScoring] Capture error: $e');
    }
  }

  Future<void> _maybeCleanup(String? path, CleanupFileCallback? cleanupFile) async {
    if (path == null || cleanupFile == null) return;
    try {
      await cleanupFile(path);
    } catch (_) {}
  }

  void _updateConfirmedDarts(ScoringResult result, OnDartDetectedCallback? onDartDetected) {
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
        // For manually overridden slots: consume the physical dart tip so it
        // doesn't leak into the next empty slot in Pass 2, but keep the
        // user's score intact.
        if (_manualOverrideSlots[s]) continue;
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
        if (_confirmedDarts[s] == null && !_manualOverrideSlots[s]) {
          _confirmedDarts[s] = detected[d];
          print('[AutoScoring] New dart in slot $s: ${detected[d].score.formatted} conf=${detected[d].confidence.toStringAsFixed(2)}');
          // Only emit once per slot per turn — prevents duplicate socket events
          // on brief occlusion (dart disappears then reappears in same slot)
          if (!_emittedSlots[s]) {
            _emittedSlots[s] = true;
            onDartDetected?.call(s, detected[d].score);
          }
          break;
        }
      }
    }

    // Sync display slots (skip manually overridden slots)
    for (int i = 0; i < 3; i++) {
      if (!_manualOverrideSlots[i]) {
        _dartSlots[i] = _confirmedDarts[i]?.score;
      }
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
