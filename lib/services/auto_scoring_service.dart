import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'dart_detection_service_stub.dart'
    if (dart.library.io) 'dart_detection_service.dart';
import 'dart_scoring_service.dart';
import 'native_inference.dart';

// ---------------------------------------------------------------------------
// DartsMind constants  (DVMind.java fields)
// ---------------------------------------------------------------------------
// DartsMind's tipMergeThreshold = 1.6 lives in *dartboard* space (340-unit
// square, board edge radius = 170, scoring coord centred at (170, 170)).
// DVMind.autoScore transforms each tip via the perspective matrix and
// d9 = 340 / (0.8 * bufferW) before mergeTips runs, so 1 dartboard unit
// equals 0.8 / 340 ≈ 0.00235 of the normalised image side.
//
// We keep tips in normalised image [0, 1] coords (no perspective remap before
// mergeTips), so the threshold sits in the same space.  The detector's
// per-dart noise between consecutive frames is ~0.003, and on some Android
// devices it spikes to ~0.004 — when the threshold sits at the noise floor,
// same-dart matches are rejected and we spawn duplicate TipGroups that turn
// into a second ShootGroup and land in the next slot ("S12, S12" duplication).
// We use a larger margin (~2× the noise floor) to absorb that variance while
// still staying below the per-frame NMS distance for adjacent real darts.
const double _tipMergeThresholdNorm = 0.006; // image-coord space, empirically tuned
const int _maxTipHistory = 10;
const double _minPixelDiff = 0.445;
const double _maxPixelDiff = 8.0;
const double _maxShiftThreshold = 40.0;
const int _maxShiftFrames = 2;
const double _defaultZeroProximity = 3.0;
// DartsMind: no fixed interval — runs inference back-to-back.
// CameraX's STRATEGY_KEEP_ONLY_LATEST + detectInProgress flag means it
// processes as fast as inference allows (~200-400ms per frame = 2.5-5 fps).
// We mirror this: small gap between cycles to yield to UI, but no artificial delay.
const Duration _minCycleInterval = Duration(milliseconds: 50);

// DartsMind Android: frame skipping (DVMind.java: everyXFrame = 2)
// Process every Nth frame to match DartsMind's frame rate control.
const int _androidEveryXFrame = 2;

// ---------------------------------------------------------------------------
// Callbacks
// ---------------------------------------------------------------------------
typedef CaptureFrameCallback = Future<String?> Function();
typedef CaptureRgbaCallback = (Uint8List, int, int)? Function();

/// Android YUV capture callback — returns raw YUV planes for native processing.
/// Matches DartsMind's ZLVideoCapture: raw ImageProxy → native dvExecutor.
typedef CaptureYuvCallback = ({
  Uint8List yPlane,
  Uint8List uPlane,
  Uint8List vPlane,
  int width,
  int height,
  int yRowStride,
  int uvRowStride,
  int uvPixelStride,
  int rotation,
})? Function();
typedef CleanupFileCallback = Future<void> Function(String path);
typedef OnDartDetectedCallback = void Function(int slotIndex, DartScore score);
typedef OnAutoConfirmCallback = void Function();

// ---------------------------------------------------------------------------
// CnfPoint – confidence point (DartsMind: CnfPoint.java)
// ---------------------------------------------------------------------------
class CnfPoint {
  final double x, y, cnf;
  CnfPoint(this.x, this.y, this.cnf);
}

// ---------------------------------------------------------------------------
// TipVisibility  (DartsMind: TipVisibility.java)
// ---------------------------------------------------------------------------
enum TipVisibility { clearVisible, blinkVisible, invisible }

// ---------------------------------------------------------------------------
// TipGroup – tracks a single physical dart tip across frames
// (DartsMind: TipGroup.java — exact fields)
// ---------------------------------------------------------------------------
class TipGroup {
  final String id;
  List<CnfPoint?> tips; // detection history, null = not detected
  double? firstPassTime; // seconds
  double? latestPassTime; // seconds
  double createdTime; // seconds
  double latestVisibleTime; // seconds
  TipVisibility visibility;
  int priority; // 0=normal, 1=low (maybeFake)
  bool? maybeFake;
  CnfPoint? fixedAvgCnfP;

  TipGroup({required this.id, required List<CnfPoint?> initialTips})
      : tips = initialTips,
        createdTime = _nowSeconds(),
        latestVisibleTime = _nowSeconds(),
        visibility = TipVisibility.invisible,
        priority = 0;

  /// Average position across all non-null tips (exact copy of TipGroup.avgCnfP)
  CnfPoint? avgCnfP() {
    final nonNull = tips.whereType<CnfPoint>().toList();
    if (nonNull.isEmpty) return null;
    if (fixedAvgCnfP != null) {
      return CnfPoint(fixedAvgCnfP!.x, fixedAvgCnfP!.y, fixedAvgCnfP!.cnf);
    }
    final n = nonNull.length.toDouble();
    final avgX = nonNull.fold(0.0, (s, p) => s + p.x) / n;
    final avgY = nonNull.fold(0.0, (s, p) => s + p.y) / n;
    final avgCnf = nonNull.fold(0.0, (s, p) => s + p.cnf) / n;
    return CnfPoint(avgX, avgY, avgCnf);
  }
}

// ---------------------------------------------------------------------------
// Shoot – a scored dart (DartsMind: Shoot.java — relevant fields)
// ---------------------------------------------------------------------------
class Shoot {
  final int multiple; // 0=miss, 1=single, 2=double, 3=triple
  final int zoneNumber; // 1-20, 25=bull, 26=miss
  String? visionId;
  int? visionPriority;
  double? cnf;
  List<double>? actualPoint; // [normX, normY]
  DartScore? dartScore; // Flutter-side score object

  Shoot(this.multiple, this.zoneNumber, {this.dartScore});
}

// ---------------------------------------------------------------------------
// ShootGroup – tracks a confirmed dart across frames
// (DartsMind: ShootGroup.java — exact structure)
// ---------------------------------------------------------------------------
class ShootGroup {
  final Shoot firstShoot;
  final String id;
  List<Shoot?> shoots;
  int priority;
  final double createdTime;
  bool hasNearbyInvisibleShootsWhenCreated;

  ShootGroup(this.firstShoot)
      : id = firstShoot.visionId ?? '',
        shoots = [firstShoot],
        priority = 0,
        createdTime = _nowSeconds(),
        hasNearbyInvisibleShootsWhenCreated = false;

  /// Average position across non-null shoots, re-scored
  /// (exact copy of ShootGroup.avgShoot — uses boardR = 1.0)
  Shoot avgShoot() {
    final nonNull = shoots.whereType<Shoot>().toList();
    if (nonNull.isEmpty) return firstShoot;
    final n = nonNull.length.toDouble();
    double sc = 0;
    for (final s in nonNull) {
      sc += s.cnf ?? 0;
    }
    // DartsMind: dartTipToShoot(1.0f, avgPoint) — already normalised
    final avg = firstShoot;
    avg.visionId = id;
    avg.visionPriority = priority;
    avg.cnf = sc / n;
    return avg;
  }
}

// ---------------------------------------------------------------------------
// ConfirmedDart (kept for slot display compatibility)
// ---------------------------------------------------------------------------
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

double _nowSeconds() => DateTime.now().millisecondsSinceEpoch / 1000.0;

// ---------------------------------------------------------------------------
// AutoScoringService
// ---------------------------------------------------------------------------
class AutoScoringService extends ChangeNotifier {
  /// Direct inference on the calling thread. On iOS the CPU interpreter runs
  /// at ~400ms which blocks the Dart event loop, but the camera preview is
  /// rendered by the native platform layer and stays smooth. We yield to the
  /// event loop between inference cycles so Flutter widgets can rebuild.
  final DartDetectionService _detector = DartDetectionService(useNativeDecode: false);

  /// Android: native inference via platform channel (DartsMind-style YUV pipeline).
  NativeInference? _nativeInference;

  // Capture state
  bool _capturing = false;
  bool _inferenceInProgress = false;
  int _captureSeq = 0;
  bool _modelLoaded = false;
  String? _initError;

  // DartsMind Android: frame counter for everyXFrame skip
  int _frameCounter = 0;

  // Game state — 3 dart slots
  List<DartScore?> _dartSlots = [null, null, null];
  int _turnTotal = 0;

  // DartsMind state (DVMind.java fields)
  List<TipGroup> _tipGroups = [];
  List<ShootGroup> _shootGroups = [];
  List<bool> _emptyBoardFlags = [];
  bool _shouldAutoSwitchWhenEmptyBoard = false;

  // Latest frame scores keyed by tip position for lookup
  Map<String, DartScore> _latestScores = {};

  // Shaking detection (DVMind.java: shiftValues, isShaking)
  List<double?> _shiftValues = [];
  bool _isShaking = false;
  double _zeroProximity = _defaultZeroProximity;
  CnfPoint? _prevBoardCenter; // for shift computation

  // Slot assignment
  List<String?> _slotShootGroupIds = [null, null, null];
  List<bool> _emittedSlots = [false, false, false];
  List<bool> _manualOverrideSlots = [false, false, false];
  List<bool> _removedSlots = [false, false, false];

  // UI state
  String? _zoomHint;
  int? _lastInferenceMs;
  bool _dartsRemoved = false;
  int _consecutiveEmptyBoardCount = 0;
  static const int _autoConfirmThreshold = 2;
  int _prevDartCount = 0;

  // Getters
  bool get isCapturing => _capturing;
  bool get modelLoaded => _modelLoaded;
  String? get initError => _initError;
  List<DartScore?> get dartSlots => List.unmodifiable(_dartSlots);
  int get turnTotal => _turnTotal;
  String? get zoomHint => _zoomHint;
  int? get lastInferenceMs => _lastInferenceMs;
  bool get dartsRemoved => _dartsRemoved;
  int get detectedDartCount => _getValidShootDetectionThisRound();
  static bool get isSupported => !kIsWeb;

  // ---- DartsMind: getValidShootDetectionThisRound -------------------------
  int _getValidShootDetectionThisRound() {
    return _shootGroups.where((sg) => sg.priority == 0).length;
  }

  // ---- Model loading (DartsMind: Detector.setup → updateTensorData) ------
  Future<void> loadModel() async {
    if (!isSupported) return;
    try {
      if (!kIsWeb && Platform.isAndroid) {
        // Android: load via native plugin ONLY (DartsMind-style GPU/CPU delegate).
        // Do NOT also load _detector — having two GPU delegates causes conflicts.
        _nativeInference = NativeInference();
        await _nativeInference!.loadModel();
      } else {
        // iOS: load Dart-side interpreter (CPU only, works perfectly)
        await _detector.loadModel();
      }
      _modelLoaded = true;
      _initError = null;
    } catch (e, stack) {
      _initError = 'Model loading failed: $e';
      _modelLoaded = false;
      debugPrint('[AutoScoring] *** MODEL LOAD FAILED: $e');
      debugPrint('[AutoScoring] $stack');
    }
    notifyListeners();
  }

  // ---- Capture control ----------------------------------------------------
  void startCapture({
    required CaptureFrameCallback captureFrame,
    CaptureRgbaCallback? captureRgba,
    CaptureYuvCallback? captureYuv,
    CleanupFileCallback? cleanupFile,
    OnDartDetectedCallback? onDartDetected,
    OnAutoConfirmCallback? onAutoConfirm,
  }) {
    if (!_modelLoaded || _capturing) return;
    _capturing = true;
    _dartsRemoved = false;
    _consecutiveEmptyBoardCount = 0;
    _frameCounter = 0;
    notifyListeners();
    _captureLoop(captureFrame, captureRgba, captureYuv, cleanupFile, onDartDetected, onAutoConfirm);
  }

  void stopCapture() {
    _capturing = false;
    notifyListeners();
  }

  /// DartsMind: clearDetectData
  void resetTurn() {
    _dartSlots = [null, null, null];
    _turnTotal = 0;
    _tipGroups = [];
    _shootGroups = [];
    _emptyBoardFlags = [];
    _shouldAutoSwitchWhenEmptyBoard = false;
    _shiftValues = [];
    _isShaking = false;
    _prevBoardCenter = null;
    _slotShootGroupIds = [null, null, null];
    _emittedSlots = [false, false, false];
    _manualOverrideSlots = [false, false, false];
    _removedSlots = [false, false, false];
    _prevDartCount = 0;
    _dartsRemoved = false;
    _consecutiveEmptyBoardCount = 0;
    _frameCounter = 0;
    _zoomHint = null;
    _lastInferenceMs = null;
    notifyListeners();
  }

  void syncEmittedCount(int confirmedCount) {
    for (int i = confirmedCount; i < 3; i++) {
      _dartSlots[i] = null;
      _slotShootGroupIds[i] = null;
      _emittedSlots[i] = false;
      _manualOverrideSlots[i] = false;
      _removedSlots[i] = false;
    }
    _turnTotal = _dartSlots.fold<int>(0, (sum, s) => sum + (s?.score ?? 0));
    notifyListeners();
  }

  void overrideDart(int index, DartScore score) {
    if (index < 0 || index > 2) return;
    _dartSlots[index] = score;
    _manualOverrideSlots[index] = true;
    _turnTotal = _dartSlots.fold<int>(0, (sum, s) => sum + (s?.score ?? 0));
    notifyListeners();
  }

  void clearDart(int index) {
    if (index < 0 || index > 2) return;
    _dartSlots[index] = null;
    _slotShootGroupIds[index] = null;
    _emittedSlots[index] = false;
    _manualOverrideSlots[index] = false;
    _removedSlots[index] = false;
    _turnTotal = _dartSlots.fold<int>(0, (sum, s) => sum + (s?.score ?? 0));
    notifyListeners();
  }

  void removeDart(int index) {
    if (index < 0 || index > 2) return;
    _dartSlots[index] = null;
    _emittedSlots[index] = false;
    _manualOverrideSlots[index] = false;
    _removedSlots[index] = true;
    _turnTotal = _dartSlots.fold<int>(0, (sum, s) => sum + (s?.score ?? 0));
    notifyListeners();
  }

  // ---- Capture loop -------------------------------------------------------
  Future<void> _captureLoop(
    CaptureFrameCallback captureFrame,
    CaptureRgbaCallback? captureRgba,
    CaptureYuvCallback? captureYuv,
    CleanupFileCallback? cleanupFile,
    OnDartDetectedCallback? onDartDetected,
    OnAutoConfirmCallback? onAutoConfirm,
  ) async {
    while (_capturing) {
      // Yield to the event loop BEFORE inference so pending UI frames,
      // touch events, and setState callbacks can be processed.
      // This is critical because inference blocks the Dart thread for ~400ms.
      await Future.delayed(const Duration(milliseconds: 16)); // ~1 frame at 60fps

      if (!_capturing) break;

      await _fireCapture(
          captureFrame, captureRgba, captureYuv, cleanupFile, onDartDetected, onAutoConfirm);

      // Yield AFTER inference too, so the results (notifyListeners) can
      // trigger widget rebuilds before the next cycle starts.
      await Future.delayed(const Duration(milliseconds: 16));
    }
  }

  Future<void> _fireCapture(
    CaptureFrameCallback captureFrame,
    CaptureRgbaCallback? captureRgba,
    CaptureYuvCallback? captureYuv,
    CleanupFileCallback? cleanupFile,
    OnDartDetectedCallback? onDartDetected,
    OnAutoConfirmCallback? onAutoConfirm,
  ) async {
    if (_inferenceInProgress) return;
    final seq = ++_captureSeq;
    String? imagePath;

    try {
      _inferenceInProgress = true;

      // DartsMind Android: frame skipping (DVMind.java everyXFrame)
      final bool isAndroid = !kIsWeb && Platform.isAndroid;
      if (isAndroid) {
        _frameCounter++;
        if (_frameCounter % _androidEveryXFrame != 0) {
          return; // Skip this frame — matches DartsMind's frameFlag logic
        }
      }

      final infSw = Stopwatch()..start();
      ScoringResult result;

      if (isAndroid && captureYuv != null && _nativeInference != null) {
        // ── Android path: DartsMind-style native YUV pipeline ──
        // Raw YUV → native (YUV→Bitmap→rotation→preprocess→inference)
        // Matches ZLVideoCapture → Detector.detectVideoBuffer exactly.
        final yuvData = captureYuv();
        if (yuvData == null || seq != _captureSeq || !_capturing) return;
        result = await _nativeInference!.analyzeYuv(
          yPlane: yuvData.yPlane,
          uPlane: yuvData.uPlane,
          vPlane: yuvData.vPlane,
          width: yuvData.width,
          height: yuvData.height,
          yRowStride: yuvData.yRowStride,
          uvRowStride: yuvData.uvRowStride,
          uvPixelStride: yuvData.uvPixelStride,
          rotation: yuvData.rotation,
        );
      } else {
        // ── iOS path: unchanged RGBA pipeline (works perfectly) ──
        final rgbaData = captureRgba?.call();
        if (rgbaData != null) {
          final (rgba, w, h) = rgbaData;
          result = await _detector.analyzeRgba(rgba, w, h);
        } else {
          imagePath = await captureFrame();
          if (imagePath == null || seq != _captureSeq || !_capturing) {
            await _maybeCleanup(imagePath, cleanupFile);
            return;
          }
          result = await _detector.analyzeImage(imagePath);
        }
      }
      infSw.stop();
      _lastInferenceMs = infSw.elapsedMilliseconds;

      if (seq != _captureSeq || !_capturing) {
        await _maybeCleanup(imagePath, cleanupFile);
        return;
      }

      final dartCount = result.dartTips.length;
      debugPrint(
          '[AutoScoring] ── frame #$seq ── ${_lastInferenceMs}ms ── $dartCount dart(s), ${result.calibrationPoints.length} CP ──');
      for (int i = 0; i < dartCount && i < result.scores.length; i++) {
        final s = result.scores[i];
        debugPrint('[AutoScoring]   dart[$i] => ${s.formatted}');
      }
      if (result.error != null) {
        debugPrint('[AutoScoring]   error: ${result.error}');
      }

      _updateZoomHint(result);

      // Auto-confirm
      final allDartsEmitted = _emittedSlots.every((e) => e);
      if (allDartsEmitted &&
          dartCount == 0 &&
          result.calibrationPoints.length >= 4) {
        _consecutiveEmptyBoardCount++;
        if (_consecutiveEmptyBoardCount >= _autoConfirmThreshold) {
          _consecutiveEmptyBoardCount = 0;
          _prevDartCount = 0;
          await _maybeCleanup(imagePath, cleanupFile);
          onAutoConfirm?.call();
          return;
        }
      } else {
        _consecutiveEmptyBoardCount = 0;
      }

      // Dart removal detection
      if (_prevDartCount > 0 && dartCount == 0) {
        _prevDartCount = 0;
        _dartsRemoved = true;
        await _maybeCleanup(imagePath, cleanupFile);
        notifyListeners();
        return;
      }
      _prevDartCount = dartCount;

      // ---- DartsMind autoScore pipeline -----------------------------------
      _autoScore(result, onDartDetected);

      await _maybeCleanup(imagePath, cleanupFile);
      notifyListeners();
    } catch (e) {
      await _maybeCleanup(imagePath, cleanupFile);
      debugPrint('[AutoScoring] Capture error: $e');
    } finally {
      _inferenceInProgress = false;
    }
  }

  // ========================================================================
  // DartsMind autoScore pipeline
  // ========================================================================

  void _autoScore(ScoringResult result, OnDartDetectedCallback? onDartDetected) {
    // Compute board center shift for shaking detection
    if (result.calibrationPoints.length >= 4) {
      final cx = result.calibrationPoints.fold(0.0, (s, d) => s + d.x) /
          result.calibrationPoints.length;
      final cy = result.calibrationPoints.fold(0.0, (s, d) => s + d.y) /
          result.calibrationPoints.length;
      if (_prevBoardCenter != null) {
        final shift = sqrt(pow(cx - _prevBoardCenter!.x, 2) +
            pow(cy - _prevBoardCenter!.y, 2));
        _addShiftValue(shift * 1024.0);
      }
      _prevBoardCenter = CnfPoint(cx, cy, 1.0);
    } else {
      _addShiftValue(null);
    }

    // Convert detected tips to CnfPoints
    final tipCnfPoints = <CnfPoint>[];
    for (int i = 0; i < result.dartTips.length; i++) {
      final d = result.dartTips[i];
      tipCnfPoints.add(CnfPoint(d.x, d.y, d.confidence));
    }

    // Store scores indexed by tip position for later lookup
    _latestScores = {};
    for (int i = 0; i < result.dartTips.length && i < result.scores.length; i++) {
      final d = result.dartTips[i];
      _latestScores['${d.x.toStringAsFixed(4)},${d.y.toStringAsFixed(4)}'] =
          result.scores[i];
    }

    if (tipCnfPoints.isEmpty) {
      _autoScoreNoTips(_nowSeconds());
    } else {
      // DartsMind: mergeTips → (internally calls analyseTipGroups → mergeShoots)
      _mergeTips(tipCnfPoints);
    }

    _assignSlots(onDartDetected);
  }

  /// DartsMind: autoScore$noTips (exact port from line 259-287)
  void _autoScoreNoTips(double now) {
    if (_tipGroups.isEmpty) {
      return;
    }
    if (!_isShaking) {
      // Add null to each existing tip group (mark absence)
      final size = _tipGroups.length;
      for (int i = 0; i < size; i++) {
        _tipGroups[i].tips.add(null);
        if (_tipGroups[i].tips.length > _maxTipHistory) {
          // Smart removal: if second tip is non-null, remove first; else remove second
          _tipGroups[i].tips.removeAt(
              _tipGroups[i].tips.length > 1 && _tipGroups[i].tips[1] != null
                  ? 0
                  : 1);
        }
      }
      _analyseTipGroups();
    }
    _addEmptyBoardFlag(_getValidShootDetectionThisRound() >= 8 && !_isShaking);
  }

  // ========================================================================
  // DartsMind: mergeTips (exact port from line 1037-1145)
  // ========================================================================
  void _mergeTips(List<CnfPoint> tips, {bool isFromInside = false}) {
    // matched = List of (tipGroupId, tipIndex, distance)
    final matched = <(String, int, double)>[];

    // Step 1: Skip secondary camera matching (mobile is single camera)
    // (DartsMind lines 1040-1056: match tips from non-"sc" cameras — not applicable)

    // Step 2: For each unmatched tip, find closest existing group within threshold
    final size = tips.length;
    for (int i = 0; i < size; i++) {
      // Check if already matched
      if (matched.any((m) => m.$2 == i)) continue;

      (String, int, double)? best;
      final groupSize = _tipGroups.length;
      for (int g = 0; g < groupSize; g++) {
        final avg = _tipGroups[g].avgCnfP();
        if (avg == null) continue;
        final dist = _distanceOf2Points(avg.x, avg.y, tips[i].x, tips[i].y);
        if (best == null || dist < best.$3) {
          best = (_tipGroups[g].id, i, dist);
        }
      }
      if (best != null && best.$3 <= _tipMergeThresholdNorm) {
        matched.add(best);
      } else if (best != null && best.$3 <= _tipMergeThresholdNorm * 2) {
        // Near-miss: a tip just outside the merge zone usually means detector
        // noise drifted further than expected. Log so we can tune the
        // threshold if the duplicate-dart bug resurfaces.
        debugPrint(
            '[AutoScoring] tip near-miss: dist=${best.$3.toStringAsFixed(5)} '
            '(threshold=${_tipMergeThresholdNorm.toStringAsFixed(5)}) — new TipGroup will be created');
      }
    }

    // Step 3: Add matched tips to their groups
    for (final m in matched) {
      final idx = _tipGroups.indexWhere((tg) => tg.id == m.$1);
      if (idx >= 0) {
        _tipGroups[idx].tips.add(tips[m.$2]);
      }
    }

    // Step 4: Unmatched groups get null (not from recursive call)
    if (!isFromInside) {
      final matchedGroupIds = matched.map((m) => m.$1).toSet();
      final groupSize = _tipGroups.length;
      for (int i = 0; i < groupSize; i++) {
        if (!matchedGroupIds.contains(_tipGroups[i].id)) {
          _tipGroups[i].tips.add(null);
        }
        // Keep history ≤ 10 (DartsMind smart removal)
        if (_tipGroups[i].tips.length > _maxTipHistory) {
          _tipGroups[i].tips.removeAt(
              _tipGroups[i].tips.length > 1 && _tipGroups[i].tips[1] != null
                  ? 0
                  : 1);
        }
      }
    }

    // Step 5: Unmatched tips → new groups (DartsMind: recursive for multiple)
    final matchedTipIndices = matched.map((m) => m.$2).toSet();
    final unmatchedTips = <CnfPoint>[];
    for (int i = 0; i < size; i++) {
      if (!matchedTipIndices.contains(i)) {
        unmatchedTips.add(tips[i]);
      }
    }

    if (unmatchedTips.isEmpty) {
      _analyseTipGroups();
      return;
    }
    if (unmatchedTips.length == 1) {
      _tipGroups.add(TipGroup(
        id: _generateId(),
        initialTips: [unmatchedTips[0]],
      ));
      _analyseTipGroups();
    } else {
      // DartsMind: create group for first, recurse with rest
      _tipGroups.add(TipGroup(
        id: _generateId(),
        initialTips: [unmatchedTips[0]],
      ));
      final rest = unmatchedTips.sublist(1).map((p) => CnfPoint(p.x, p.y, p.cnf)).toList();
      _mergeTips(rest, isFromInside: true);
    }
  }

  // ========================================================================
  // DartsMind: mergeShoots (exact port from line 962-1034)
  // ========================================================================
  void _mergeShoots(List<Shoot> shoots) {
    if (shoots.isEmpty) {
      if (_shootGroups.isEmpty) return;
      // Add null to each group (mark absence)
      final size = _shootGroups.length;
      for (int i = 0; i < size; i++) {
        _shootGroups[i].shoots.add(null);
        if (_shootGroups[i].shoots.length > 10) {
          _shootGroups[i].shoots.removeAt(
              _shootGroups[i].shoots.length > 1 &&
                      _shootGroups[i].shoots[1] != null
                  ? 0
                  : 1);
        }
      }
      return;
    }

    if (_shootGroups.isEmpty) {
      // First time: create a ShootGroup for each shoot
      for (final shoot in shoots) {
        _shootGroups.add(ShootGroup(shoot));
      }
      _shouldAutoSwitchWhenEmptyBoard = true;
      _analyseShootGroups(shoots.length);
      return;
    }

    // Match existing groups by visionId
    final size = _shootGroups.length;
    for (int i = 0; i < size; i++) {
      int matchIdx = -1;
      for (int j = 0; j < shoots.length; j++) {
        if (shoots[j].visionId == _shootGroups[i].id) {
          matchIdx = j;
          break;
        }
      }
      if (matchIdx >= 0) {
        _shootGroups[i].shoots.add(shoots[matchIdx]);
      } else {
        _shootGroups[i].shoots.add(null);
      }
      if (_shootGroups[i].shoots.length > 10) {
        _shootGroups[i].shoots.removeAt(
            _shootGroups[i].shoots.length > 1 &&
                    _shootGroups[i].shoots[1] != null
                ? 0
                : 1);
      }
    }

    // Find shoots not matched to any existing group
    final existingIds = _shootGroups.map((sg) => sg.id).toList();
    final newShoots = <Shoot>[];
    for (final shoot in shoots) {
      if (!existingIds.contains(shoot.visionId)) {
        newShoots.add(shoot);
      }
    }
    if (newShoots.isNotEmpty) {
      for (final shoot in newShoots) {
        final sg = ShootGroup(shoot);
        sg.hasNearbyInvisibleShootsWhenCreated =
            _hasNearbyInvisibleShoots(shoot);
        _shootGroups.add(sg);
      }
      _shouldAutoSwitchWhenEmptyBoard = true;
    }
    _analyseShootGroups(shoots.length);
  }

  // ========================================================================
  // DartsMind: checkShaking (exact port from line 308-378)
  // ========================================================================
  bool _checkShaking() {
    final recent = _shiftValues.length >= 9
        ? _shiftValues.sublist(_shiftValues.length - 9)
        : _shiftValues;
    final nonNull = recent.whereType<double>().toList();

    if (nonNull.length < 9 || nonNull.length / recent.length < 0.8) {
      return false;
    }

    // Check if any value is near zero
    bool hasNearZero = nonNull.any((v) => v.abs() <= _zeroProximity);
    if (!hasNearZero) return false;

    // Check if too many values exceed max shift threshold
    int exceedCount = 0;
    for (final v in nonNull) {
      if (v.abs() > _maxShiftThreshold) {
        exceedCount++;
        if (exceedCount >= _maxShiftFrames) return false;
      }
    }

    // Compute consecutive differences
    final diffs = <double>[];
    for (int i = 1; i < nonNull.length; i++) {
      diffs.add(nonNull[i] - nonNull[i - 1]);
    }

    // Classify each diff as +1, -1, or 0
    final classified = <int>[];
    for (final d in diffs) {
      if (d > _minPixelDiff && d <= _maxPixelDiff) {
        classified.add(1);
      } else if (d < -_minPixelDiff && d.abs() <= _maxPixelDiff) {
        classified.add(-1);
      } else {
        classified.add(0);
      }
    }

    // Count non-zero entries
    final nonZero = classified.where((c) => c != 0).toList();
    if (nonZero.length < 3) return false;

    // Count direction changes
    int changes = 0;
    for (int i = 1; i < nonZero.length; i++) {
      if (nonZero[i] != nonZero[i - 1]) changes++;
    }

    return changes >= 3;
  }

  /// DartsMind: addShiftValue (exact port from line 137-147)
  void _addShiftValue(double? v) {
    _shiftValues.add(v);
    if (_shiftValues.length > 18) {
      _shiftValues.removeAt(0);
    }
    _isShaking = _checkShaking();
  }

  // ========================================================================
  // DartsMind: analyseTipGroups (exact port from DVMind.java lines 682-1131)
  // ========================================================================
  void _analyseTipGroups() {
    if (_tipGroups.isEmpty) return;

    final now = _nowSeconds();

    // Phase 1: Compute visibility for each group based on 85% non-null ratio
    // Then collapse tips to their average (DartsMind replaces tips with [avg])
    for (int i = _tipGroups.length - 1; i >= 0; i--) {
      final tg = _tipGroups[i];
      // Skip groups that don't have enough history yet (tipThreshold = 2)
      if (tg.tips.length < 2) continue;
      final threshold85 = tg.tips.length * 0.85;
      final nonNullCount =
          tg.tips.whereType<CnfPoint>().length.toDouble();
      final avg = tg.avgCnfP();
      if (avg == null) continue;

      // Collapse tip history to single averaged point
      tg.tips = [avg];

      if (nonNullCount >= threshold85) {
        // ClearVisible: ≥85% of history was non-null
        tg.visibility = TipVisibility.clearVisible;
        if (tg.firstPassTime == null) {
          if (_isShaking) {
            // Ignore new tip during shaking
          } else {
            tg.firstPassTime = now;
          }
        }
        tg.latestPassTime = now;
        tg.latestVisibleTime = now;
      } else if (nonNullCount <= 1.0 || nonNullCount >= threshold85) {
        // Invisible: ≤1 detection or exactly at threshold
        tg.visibility = TipVisibility.invisible;
      } else {
        // BlinkVisible: between 1 and 85%
        tg.visibility = TipVisibility.blinkVisible;
        tg.latestVisibleTime = now;
      }
    }

    // Phase 2: Find newly-appeared groups (firstPassTime == now)
    var newGroups = _tipGroups
        .where((tg) => tg.firstPassTime == now)
        .map((tg) => _copyTipGroup(tg))
        .toList();

    // Find existing groups (firstPassTime != now, not null, priority ≤ 1)
    final existingGroups = _tipGroups
        .where((tg) =>
            tg.firstPassTime != now &&
            tg.firstPassTime != null &&
            tg.priority <= 1)
        .map((tg) => _copyTipGroup(tg))
        .toList();

    // Phase 3: Merge new groups that overlap with existing groups
    if (newGroups.isNotEmpty && existingGroups.isNotEmpty) {
      final toRemoveIds = <String>[];

      for (final newTg in newGroups) {
        final newAvg = newTg.tips.firstOrNull;
        if (newAvg == null) continue;

        (String, String, double)? bestMerge; // (newId, existingId, minCreatedTime)
        double bestDist = 100.0;

        for (final exTg in existingGroups) {
          final exAvg = exTg.tips.firstOrNull;
          if (exAvg == null) continue;
          final dist = _distanceOf2Points(
              newAvg.x, newAvg.y, exAvg.x, exAvg.y);
          if (dist < bestDist) {
            bestDist = dist;
            bestMerge = (newTg.id, exTg.id,
                min(newTg.createdTime, exTg.createdTime));
          }
        }

        if (bestDist <= _tipMergeThresholdNorm && bestMerge != null) {
          // Merge: combine tips, re-average, update existing group
          final exIdx =
              _tipGroups.indexWhere((tg) => tg.id == bestMerge!.$2);
          if (exIdx >= 0) {
            final exAvg = _tipGroups[exIdx].tips.firstOrNull;
            if (exAvg != null) {
              _tipGroups[exIdx].tips = [exAvg, newAvg];
              final merged = _tipGroups[exIdx].avgCnfP();
              if (merged != null) _tipGroups[exIdx].tips = [merged];
              _tipGroups[exIdx].createdTime = bestMerge.$3;
            }
            toRemoveIds.add(newTg.id);
          }
        }
      }

      if (toRemoveIds.isNotEmpty) {
        _tipGroups.removeWhere((tg) => toRemoveIds.contains(tg.id));
        // Re-collect new groups after merge
        newGroups = _tipGroups
            .where((tg) => tg.firstPassTime == now)
            .map((tg) => _copyTipGroup(tg))
            .toList();
      }
    }

    // Phase 4: Check if new groups overlap with each other
    if (newGroups.length >= 2) {
      final toRemoveIds = <String>[];
      for (int i = 0; i < newGroups.length; i++) {
        for (int j = i + 1; j < newGroups.length; j++) {
          final a = newGroups[i].tips.firstOrNull;
          final b = newGroups[j].tips.firstOrNull;
          if (a == null || b == null) continue;
          if (_distanceOf2Points(a.x, a.y, b.x, b.y) <=
              _tipMergeThresholdNorm) {
            // Merge j into i in the main tipGroups
            final iIdx =
                _tipGroups.indexWhere((tg) => tg.id == newGroups[j].id);
            if (iIdx >= 0) {
              final iAvg = _tipGroups[iIdx].tips.firstOrNull;
              if (iAvg != null) {
                _tipGroups[iIdx].tips = [iAvg, a];
                final merged = _tipGroups[iIdx].avgCnfP();
                if (merged != null) _tipGroups[iIdx].tips = [merged];
                _tipGroups[iIdx].createdTime =
                    min(newGroups[i].createdTime, newGroups[j].createdTime);
              }
            }
            toRemoveIds.add(newGroups[i].id);
            newGroups.removeAt(i);
            i--;
            break;
          }
        }
      }
      if (toRemoveIds.isNotEmpty) {
        _tipGroups.removeWhere((tg) => toRemoveIds.contains(tg.id));
        newGroups = _tipGroups
            .where((tg) => tg.firstPassTime == now)
            .map((tg) => _copyTipGroup(tg))
            .toList();
      }
    }

    // Phase 5: checkStability (3 rounds with increasing timeSpan)
    // For single camera: primarily validates groups, dual-cam merging skipped
    var stableGroups = _checkStability(newGroups, 0.65);
    if (stableGroups.isNotEmpty) {
      stableGroups = _checkStability(stableGroups, 1.15);
      if (stableGroups.isNotEmpty) {
        _checkStability(stableGroups, 1.6);
      }
    }

    // Phase 6: Restore priority for dual-cam confirmed groups (skip for single cam)

    // Phase 7: Collect ClearVisible groups with firstPassTime, sort by createdTime desc
    final visibleGroups = _tipGroups
        .where((tg) =>
            tg.visibility == TipVisibility.clearVisible &&
            tg.firstPassTime != null)
        .toList()
      ..sort((a, b) => b.createdTime.compareTo(a.createdTime));
    // Phase 8: Convert visible groups to Shoots via dartTipToShoot
    // (In DartsMind: dartTipToShoot(170.0f, tipPosition))
    // In our architecture, scoring happens in the detection service,
    // so we pass tip group info through to _assignSlots via shoot groups.
    final shoots = <Shoot>[];
    for (final tg in visibleGroups) {
      final tip = tg.tips.firstOrNull;
      if (tip == null) continue;

      final shoot = Shoot(0, 0); // placeholder, score comes from detection
      shoot.visionId = tg.id;
      shoot.cnf = tip.cnf.toDouble();
      shoot.actualPoint = [tip.x.toDouble(), tip.y.toDouble()];
      shoots.add(shoot);
    }
    _mergeShoots(shoots);
  }

  TipGroup _copyTipGroup(TipGroup tg) {
    final copy = TipGroup(
      id: tg.id,
      initialTips: tg.tips.map((t) => t != null ? CnfPoint(t.x, t.y, t.cnf) : null).toList(),
    );
    copy.firstPassTime = tg.firstPassTime;
    copy.latestPassTime = tg.latestPassTime;
    copy.createdTime = tg.createdTime;
    copy.latestVisibleTime = tg.latestVisibleTime;
    copy.visibility = tg.visibility;
    copy.priority = tg.priority;
    copy.maybeFake = tg.maybeFake;
    return copy;
  }

  // ========================================================================
  // DartsMind: checkStability (from DVMind.java line 1663)
  // For single camera: validates groups created within timeSpan of each other.
  // The dual-camera merging logic (bulk of the method) is skipped.
  // ========================================================================
  List<TipGroup> _checkStability(List<TipGroup> inputGroups, double timeSpan) {
    if (inputGroups.isEmpty) return [];

    final groups = inputGroups.map((tg) => _copyTipGroup(tg)).toList();

    for (final g in groups) {
      if (g.priority != 0) continue;

      // Find other tipGroups created within timeSpan
      final nearby = <TipGroup>[];
      for (final tg in _tipGroups) {
        if (tg.priority > 1) continue;
        if (tg.firstPassTime == null) continue;
        final timeDiff = (tg.createdTime - g.createdTime).abs();
        if (timeDiff <= min(1.15, timeSpan)) {
          nearby.add(tg);
        }
      }

      // Dual-camera merging logic — skipped for single camera
      // (DartsMind lines L70-L3ac: only runs when dvExtraCamConnector.isPaired)
    }

    return groups;
  }

  // DartsMind: checkStabilityFurther — only runs for as2ndCam (dual camera).
  // Skipped: mobile app is single camera.

  // ========================================================================
  // DartsMind: analyseShootGroups (dumped method — minimal stub)
  // ========================================================================
  void _analyseShootGroups(int shootCount) {
    // Remove shoot groups that have been all-null for too long
    _shootGroups.removeWhere((sg) {
      if (sg.priority != 0) return false;
      final recentNonNull =
          sg.shoots.reversed.take(5).whereType<Shoot>().length;
      return sg.shoots.length >= 5 && recentNonNull == 0;
    });
  }

  // ========================================================================
  // DartsMind: hasNearbyInvisibleShoots (exact port from line 878-906)
  // ========================================================================
  bool _hasNearbyInvisibleShoots(Shoot shoot) {
    if (shoot.actualPoint == null || shoot.actualPoint!.length < 2) return false;

    for (final sg in _shootGroups) {
      if (sg.priority != 0) continue;

      // Get ShootGroup avg position
      final nonNull = sg.shoots.whereType<Shoot>().toList();
      if (nonNull.isEmpty) continue;
      double sx = 0, sy = 0;
      int n = 0;
      for (final s in nonNull) {
        if (s.actualPoint != null && s.actualPoint!.length >= 2) {
          sx += s.actualPoint![0];
          sy += s.actualPoint![1];
          n++;
        }
      }
      if (n == 0) continue;

      final dist = _distanceOf2Points(
          shoot.actualPoint![0], shoot.actualPoint![1], sx / n, sy / n);
      // DartsMind: 0.058823529411764705 ≈ 1/17
      if (dist <= 0.058823529411764705) {
        // Check if the corresponding tip group is invisible
        final tg = _tipGroups.where((t) => t.id == sg.id).firstOrNull;
        if (tg != null && tg.visibility == TipVisibility.invisible) {
          return true;
        }
      }
    }
    return false;
  }

  // ========================================================================
  // DartsMind: addEmptyBoardFlag (simplified — original dumped)
  // ========================================================================
  void _addEmptyBoardFlag(bool isEmpty) {
    _emptyBoardFlags.add(isEmpty);
    if (_emptyBoardFlags.length > 20) {
      _emptyBoardFlags.removeAt(0);
    }
  }

  // ========================================================================
  // Slot assignment — maps shoot groups to game UI
  // ========================================================================
  /// Look up a DartScore for a shoot group by matching its tip position
  /// against the latest frame's scored detections.
  DartScore? _lookupScore(ShootGroup sg) {
    // Try the latest non-null shoot first
    final latestShoot =
        sg.shoots.reversed.whereType<Shoot>().firstOrNull;
    if (latestShoot?.dartScore != null) return latestShoot!.dartScore;

    // Fall back to position-based lookup from latest frame scores
    final point = latestShoot?.actualPoint ??
        sg.firstShoot.actualPoint;
    if (point == null || point.length < 2) return null;

    // Exact key match
    final key = '${point[0].toStringAsFixed(4)},${point[1].toStringAsFixed(4)}';
    if (_latestScores.containsKey(key)) return _latestScores[key];

    // Closest match within threshold
    DartScore? best;
    double bestDist = 0.02; // max search distance
    for (final entry in _latestScores.entries) {
      final parts = entry.key.split(',');
      if (parts.length != 2) continue;
      final sx = double.tryParse(parts[0]);
      final sy = double.tryParse(parts[1]);
      if (sx == null || sy == null) continue;
      final dist = _distanceOf2Points(point[0], point[1], sx, sy);
      if (dist < bestDist) {
        bestDist = dist;
        best = entry.value;
      }
    }
    return best;
  }

  void _assignSlots(OnDartDetectedCallback? onDartDetected) {
    // Update existing slot scores from their shoot groups
    for (int s = 0; s < 3; s++) {
      final sgId = _slotShootGroupIds[s];
      if (sgId == null) continue;
      if (_manualOverrideSlots[s]) continue;
      if (_removedSlots[s]) continue;

      final sg = _shootGroups.where((g) => g.id == sgId).firstOrNull;
      if (sg == null) continue;

      final newScore = _lookupScore(sg);
      if (newScore != null) {
        final changed = _dartSlots[s]?.formatted != newScore.formatted;
        _dartSlots[s] = newScore;
        // Store dartScore on latest shoot for future lookups
        final latest = sg.shoots.reversed.whereType<Shoot>().firstOrNull;
        if (latest != null) latest.dartScore = newScore;

        if (changed && _emittedSlots[s]) {
          onDartDetected?.call(s, newScore);
        }
      }
    }

    // Assign unassigned shoot groups to empty slots
    for (final sg in _shootGroups) {
      if (sg.priority != 0) continue;
      if (_slotShootGroupIds.contains(sg.id)) continue;

      final score = _lookupScore(sg);
      if (score == null) continue;

      // Store dartScore on the shoot
      final latest = sg.shoots.reversed.whereType<Shoot>().firstOrNull;
      if (latest != null) latest.dartScore = score;

      for (int s = 0; s < 3; s++) {
        if (_slotShootGroupIds[s] == null &&
            !_manualOverrideSlots[s] &&
            !_removedSlots[s]) {
          _slotShootGroupIds[s] = sg.id;
          _dartSlots[s] = score;
          debugPrint(
              '[AutoScoring] Dart assigned to slot $s: ${score.formatted}');
          if (!_emittedSlots[s]) {
            _emittedSlots[s] = true;
            onDartDetected?.call(s, score);
          }
          break;
        }
      }
    }

    _turnTotal = _dartSlots.fold<int>(0, (sum, s) => sum + (s?.score ?? 0));
  }

  // ---- Helpers ------------------------------------------------------------

  static double _distanceOf2Points(double x1, double y1, double x2, double y2) {
    return sqrt(pow(x1 - x2, 2) + pow(y1 - y2, 2));
  }

  int _idCounter = 0;
  String _generateId() =>
      'tg_${_idCounter++}_${DateTime.now().millisecondsSinceEpoch}';

  Future<void> _maybeCleanup(
      String? path, CleanupFileCallback? cleanupFile) async {
    if (path == null || cleanupFile == null) return;
    try {
      await cleanupFile(path);
    } catch (_) {}
  }

  void _updateZoomHint(ScoringResult result) {
    final calibs = result.calibrationPoints;
    if (calibs.length < 4) {
      _zoomHint =
          calibs.isEmpty ? 'Dartboard not detected' : 'Board not fully visible';
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
    if (spread < 0.35) {
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
    _detector.dispose();
    _nativeInference?.dispose();
    _nativeInference = null;
    super.dispose();
  }
}
