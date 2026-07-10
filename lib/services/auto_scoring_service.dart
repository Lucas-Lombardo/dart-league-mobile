import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'dart_detection_service_stub.dart'
    if (dart.library.io) 'dart_detection_service.dart';
import 'dart_scoring_service.dart';
import 'native_inference.dart';

// ---------------------------------------------------------------------------
// DartsMind constants  (DVMind.java fields)
// ---------------------------------------------------------------------------
// Tips are transformed into DartsMind's dartboard space (340-unit square,
// centre at (170, 170), board edge radius 170) via the per-frame perspective
// matrix before mergeTips runs — see _autoScore. This makes a dart's CnfPoint
// position stable across frames even when the camera or board shift, which is
// what prevents the "same dart counted twice after board moves" duplicate.
//
// _tipMergeThresholdBoard is therefore the DartsMind value 1.6, in board
// units (≈0.94% of board radius). Tighter than this drops the second dart in
// tight triple-20 clusters; looser merges two physically distinct darts.
const double _tipMergeThresholdBoard = 1.6;
const int _maxTipHistory = 10;
const double _minPixelDiff = 0.445;
const double _maxPixelDiff = 8.0;
const double _maxShiftThreshold = 40.0;
const int _maxShiftFrames = 2;
const double _defaultZeroProximity = 3.0;
// DartsMind frame skipping (DVMind.java: everyXFrame = 2)
// Process every Nth frame to match DartsMind's frame rate control.
// Applied on both Android and iOS: even with CoreML/GPU delegates inference
// takes ~100–300ms, so processing every other frame keeps the UI responsive
// without hurting detection latency (still ~5fps net).
const int _everyXFrame = 2;

// ---------------------------------------------------------------------------
// Callbacks
// ---------------------------------------------------------------------------
typedef CaptureFrameCallback = Future<String?> Function();
typedef CaptureRgbaCallback = (Uint8List, int, int)? Function();
typedef CaptureBgraCallback = (Uint8List, int, int)? Function();

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
  int priority; // 0=normal, 1=low (demoted phantom)
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
  /// Dart-side fallback interpreter. Used only if the native plugin fails to
  /// load. Inference here blocks the main Dart isolate (~400ms on iOS).
  final DartDetectionService _detector = DartDetectionService(useNativeDecode: false);

  /// Native inference via platform channel — runs on a background thread
  /// (GCD on iOS, ExecutorService on Android) so the Flutter UI thread stays
  /// responsive even while AI is processing a frame.
  NativeInference? _nativeInference;

  // Capture state
  bool _capturing = false;
  // Bumped on every start/stop so a stale capture loop can detect it has been
  // superseded and exit (a stop→start in one tick otherwise leaves it alive).
  int _captureGeneration = 0;
  bool _inferenceInProgress = false;
  int _captureSeq = 0;
  bool _modelLoaded = false;
  bool _modelLoading = false;
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

  // Latest frame scores keyed by tip position for lookup
  Map<String, DartScore> _latestScores = {};

  // Shaking detection (DVMind.java: shiftValues, isShaking)
  List<double?> _shiftValues = [];
  bool _isShaking = false;
  final double _zeroProximity = _defaultZeroProximity;
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
  // Turn auto-confirm fires only when the board is **fully empty** for this
  // many consecutive frames. Two frames is too aggressive — model glitches
  // and hand occlusion can briefly drop tips even while darts are still in
  // the board, causing the turn to pass while the player has only retrieved
  // some of their darts. Three frames gives the model a real chance to
  // re-detect the remaining tips.
  static const int _autoConfirmThreshold = 3;
  int _prevDartCount = 0;
  // Require N consecutive empty frames after seeing darts before flagging
  // the board as cleared. A single empty frame is unreliable — the model
  // briefly loses tips when a hand obscures them, which used to trigger a
  // false "darts removed" → premature next-turn.
  int _consecutiveRemovalCount = 0;
  static const int _removalConfirmThreshold = 3;

  // One-shot "leftover darts" gate, armed at the start of each of our turns
  // (and at match start) so darts already in the board — previous visit left
  // in place, queue warm-up practice — don't get counted as this turn's
  // throws. The FIRST analyzed frame with a visible board decides: darts
  // present → hold scoring and show the "remove your darts" hint until the
  // board is confirmed empty; board clean → disarm immediately so a dart
  // thrown right at turn start is scored normally.
  bool _waitingForEmptyBoard = false;
  int _emptyBoardCheckCount = 0;
  static const int _emptyBoardCheckThreshold = 3;
  // Whether the armed gate has actually SEEN leftover darts (decision made on
  // the first board-visible frame). The "remove your darts" UI hint keys off
  // this, and it selects the gate's takeout phase: once true, only
  // [_emptyBoardCheckThreshold] consecutive empty frames clear the gate.
  bool _emptyBoardGateSawDarts = false;

  // Last snapshot of UI-visible state used to suppress no-op rebuilds.
  // notifyListeners() runs after every inference cycle, so without this the
  // whole game UI rebuilds 5x per second even when nothing changed.
  String _lastUiStateKey = '';

  // ---- Diagnostic scoring trace ------------------------------------------
  // When true, every analysed frame emits a full, self-contained block: raw
  // tips, every TipGroup and ShootGroup with the fields that drive dedup
  // (visibility, firstPassTime, priority, hasNearbyInvisibleShootsWhenCreated,
  // history fill), the counted total, the slots, and every lifecycle EVENT
  // (reattach / demote / assign / emit). Each line is prefixed "[AS f<frame>]"
  // so it greps cleanly and stays correctly ordered. Lines go through
  // debugPrintSynchronously so Flutter's debugPrint rate-limiter cannot drop
  // them (that limiter is a common cause of gappy logs). Toggle off to silence.
  static bool verboseScoringLog = true;
  int _logFrameSeq = 0;

  void _trace(String line) {
    if (!verboseScoringLog) return;
    debugPrintSynchronously('[AS f$_logFrameSeq] $line');
  }

  // Short, stable tail of a group id for readable logs (ids are long).
  static String _sid(String id) =>
      id.length <= 5 ? id : id.substring(id.length - 5);

  String _computeUiStateKey() {
    final b = StringBuffer();
    for (final s in _dartSlots) {
      b.write(s?.formatted ?? '_');
      b.write('|');
    }
    b.write(_turnTotal);
    b.write('|');
    b.write(_zoomHint ?? '');
    b.write('|');
    b.write(_dartsRemoved ? '1' : '0');
    b.write('|');
    b.write(_waitingForEmptyBoard ? '1' : '0');
    b.write(_emptyBoardGateSawDarts ? '1' : '0');
    return b.toString();
  }

  void _notifyIfChanged() {
    final key = _computeUiStateKey();
    if (key == _lastUiStateKey) return;
    _lastUiStateKey = key;
    notifyListeners();
  }

  // Getters
  bool get isCapturing => _capturing;
  bool get modelLoaded => _modelLoaded;
  bool get isModelLoading => _modelLoading;
  String? get initError => _initError;
  List<DartScore?> get dartSlots => List.unmodifiable(_dartSlots);
  int get turnTotal => _turnTotal;
  String? get zoomHint => _zoomHint;
  int? get lastInferenceMs => _lastInferenceMs;
  bool get dartsRemoved => _dartsRemoved;
  bool get waitingForEmptyBoard => _waitingForEmptyBoard;

  /// True only when the match-start gate is armed AND the camera has actually
  /// seen darts on the board — drives the "remove your darts" hint. A board
  /// that is already empty never shows the hint.
  bool get showRemoveDartsHint =>
      _waitingForEmptyBoard && _emptyBoardGateSawDarts;
  int get detectedDartCount => _getValidShootDetectionThisRound();
  static bool get isSupported => !kIsWeb;

  /// Arm the one-shot "leftover darts" gate. While armed, the AI continues
  /// running inference but won't emit dart detections or update the slot UI.
  /// The first analyzed frame with a visible board decides: darts present →
  /// show the "remove your darts" hint and wait for a confirmed-empty board;
  /// board clean → disarm right away so the turn's first throw scores
  /// normally. Called at match start and at the start of each of our turns.
  void waitForEmptyBoardOnce() {
    _waitingForEmptyBoard = true;
    _emptyBoardCheckCount = 0;
    _emptyBoardGateSawDarts = false;
    _notifyIfChanged();
  }

  // ---- DartsMind: getValidShootDetectionThisRound -------------------------
  int _getValidShootDetectionThisRound() {
    return _shootGroups.where((sg) => sg.priority == 0).length;
  }

  // ---- Model loading (DartsMind: Detector.setup → updateTensorData) ------
  Future<void> loadModel() async {
    if (!isSupported) return;
    // Idempotent + non-reentrant: skip if already loaded or a load is running.
    // The match screen calls this at init AND retries it mid-match when a prior
    // load failed (self-heal) — both must share a single in-flight load.
    if (_modelLoaded || _modelLoading) return;
    _modelLoading = true;
    // Retry transient native-plugin load failures (GPU/CoreML delegate init,
    // Android model-file extraction race, momentary memory pressure). Before
    // this, a single transient failure left _modelLoaded=false with no recovery,
    // so the AI stayed dead for the whole match and the only fix was restarting
    // the app.
    const maxAttempts = 3;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        // Drop any half-initialized native instance from a failed attempt.
        _nativeInference?.dispose();
        _nativeInference = null;
        if (!kIsWeb && Platform.isAndroid) {
          // Android: load via native plugin ONLY (DartsMind-style GPU/CPU
          // delegate). Do NOT also load _detector — two GPU delegates conflict.
          _nativeInference = NativeInference();
          await _nativeInference!.loadModel();
        } else {
          // iOS: prefer the native plugin so inference runs on a GCD background
          // queue instead of blocking the main Dart isolate. Fall back to the
          // Dart-side interpreter only if the native plugin fails to load.
          try {
            _nativeInference = NativeInference();
            await _nativeInference!.loadModel();
          } catch (e) {
            debugPrint(
                '[AutoScoring] iOS native load failed, falling back to Dart: $e');
            _nativeInference?.dispose();
            _nativeInference = null;
            await _detector.loadModel();
          }
        }
        _modelLoaded = true;
        _initError = null;
        break;
      } catch (e, stack) {
        _initError = 'Model loading failed: $e';
        _modelLoaded = false;
        debugPrint(
            '[AutoScoring] *** MODEL LOAD FAILED (attempt ${attempt + 1}/$maxAttempts): $e');
        debugPrint('[AutoScoring] $stack');
        if (attempt < maxAttempts - 1) {
          await Future.delayed(Duration(milliseconds: 600 * (attempt + 1)));
        }
      }
    }
    _modelLoading = false;
    notifyListeners();
  }

  // ---- Capture control ----------------------------------------------------
  void startCapture({
    required CaptureFrameCallback captureFrame,
    CaptureRgbaCallback? captureRgba,
    CaptureBgraCallback? captureBgra,
    CaptureYuvCallback? captureYuv,
    CleanupFileCallback? cleanupFile,
    OnDartDetectedCallback? onDartDetected,
    OnAutoConfirmCallback? onAutoConfirm,
  }) {
    if (!_modelLoaded || _capturing) return;
    _capturing = true;
    // Each loop owns a generation. A stop→start inside a single loop tick used
    // to leave the OLD loop running (it re-read _capturing == true after the
    // restart) and hold a disposed camera service; now the stale generation
    // exits on its next check.
    final generation = ++_captureGeneration;
    _dartsRemoved = false;
    _consecutiveEmptyBoardCount = 0;
    _consecutiveRemovalCount = 0;
    _frameCounter = 0;
    notifyListeners();
    _captureLoop(captureFrame, captureRgba, captureBgra, captureYuv, cleanupFile,
        onDartDetected, onAutoConfirm, generation);
  }

  void stopCapture() {
    _capturing = false;
    _captureGeneration++;
    notifyListeners();
  }

  /// DartsMind: clearDetectData
  void resetTurn() {
    _dartSlots = [null, null, null];
    _turnTotal = 0;
    _tipGroups = [];
    _shootGroups = [];
    _emptyBoardFlags = [];
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
    _consecutiveRemovalCount = 0;
    _frameCounter = 0;
    _zoomHint = null;
    _lastInferenceMs = null;
    notifyListeners();
  }

  /// Align the AI's slot bookkeeping with the number of darts the game layer
  /// accounts for ([accountedCount] = applied by the server + still in
  /// delivery). Slots beyond that count are cleared ONLY when no live shoot
  /// group is bound to them.
  ///
  /// Clearing a slot whose group survives in [_shootGroups] used to orphan
  /// that group: _assignSlots then re-assigned it to a free slot with
  /// firstEmit == true and fired onDartDetected a SECOND time for a dart that
  /// is physically still in the board — the dart-duplication bug. A dart that
  /// was emitted stays emitted; delivery is the provider's job (dartId + ack).
  void syncEmittedCount(int accountedCount) {
    for (int i = accountedCount; i < 3; i++) {
      if (_slotShootGroupIds[i] != null) continue;
      _dartSlots[i] = null;
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
    CaptureBgraCallback? captureBgra,
    CaptureYuvCallback? captureYuv,
    CleanupFileCallback? cleanupFile,
    OnDartDetectedCallback? onDartDetected,
    OnAutoConfirmCallback? onAutoConfirm,
    int generation,
  ) async {
    while (_capturing && generation == _captureGeneration) {
      // Yield to the event loop BEFORE inference so pending UI frames,
      // touch events, and setState callbacks can be processed.
      // This is critical because inference blocks the Dart thread for ~400ms.
      await Future.delayed(const Duration(milliseconds: 16)); // ~1 frame at 60fps

      if (!_capturing || generation != _captureGeneration) break;

      await _fireCapture(captureFrame, captureRgba, captureBgra, captureYuv,
          cleanupFile, onDartDetected, onAutoConfirm);

      // Yield AFTER inference too, so the results (notifyListeners) can
      // trigger widget rebuilds before the next cycle starts.
      await Future.delayed(const Duration(milliseconds: 16));
    }
  }

  Future<void> _fireCapture(
    CaptureFrameCallback captureFrame,
    CaptureRgbaCallback? captureRgba,
    CaptureBgraCallback? captureBgra,
    CaptureYuvCallback? captureYuv,
    CleanupFileCallback? cleanupFile,
    OnDartDetectedCallback? onDartDetected,
    OnAutoConfirmCallback? onAutoConfirm,
  ) async {
    if (_inferenceInProgress) return;
    final seq = ++_captureSeq;
    _logFrameSeq = seq;
    String? imagePath;

    try {
      _inferenceInProgress = true;

      // DartsMind frame skipping (DVMind.java everyXFrame) — both platforms.
      final bool isAndroid = !kIsWeb && Platform.isAndroid;
      _frameCounter++;
      if (_frameCounter % _everyXFrame != 0) {
        return; // Skip this frame — matches DartsMind's frameFlag logic
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
        // ── iOS path: native plugin (GCD background queue) preferred ──
        // Falls back to the Dart-side interpreter if native didn't load.
        // Try BGRA fast-path first — it skips the per-pixel BGRA→RGBA loop
        // that would otherwise run on the main isolate.
        final bgraData =
            (_nativeInference != null) ? captureBgra?.call() : null;
        if (bgraData != null) {
          final (bgra, w, h) = bgraData;
          result =
              await _nativeInference!.analyzeRgba(bgra, w, h, isBgra: true);
        } else {
          final rgbaData = captureRgba?.call();
          if (rgbaData != null) {
            final (rgba, w, h) = rgbaData;
            result = _nativeInference != null
                ? await _nativeInference!.analyzeRgba(rgba, w, h)
                : await _detector.analyzeRgba(rgba, w, h);
          } else {
            imagePath = await captureFrame();
            if (imagePath == null || seq != _captureSeq || !_capturing) {
              await _maybeCleanup(imagePath, cleanupFile);
              return;
            }
            result = _nativeInference != null
                ? await _nativeInference!.analyzeFile(imagePath)
                : await _detector.analyzeImage(imagePath);
          }
        }
      }
      infSw.stop();
      _lastInferenceMs = infSw.elapsedMilliseconds;

      if (seq != _captureSeq || !_capturing) {
        await _maybeCleanup(imagePath, cleanupFile);
        return;
      }

      final dartCount = result.dartTips.length;
      // Lightweight summary only when the full verbose trace is off — the
      // verbose dump (_dumpScoringState, end of _autoScore) already covers this.
      if (kDebugMode && !verboseScoringLog) {
        debugPrint(
            '[AutoScoring] ── frame #$seq ── ${_lastInferenceMs}ms ── $dartCount dart(s), ${result.calibrationPoints.length} CP ──');
        for (int i = 0; i < dartCount && i < result.scores.length; i++) {
          debugPrint('[AutoScoring]   dart[$i] => ${result.scores[i].formatted}');
        }
        if (result.error != null) {
          debugPrint('[AutoScoring]   error: ${result.error}');
        }
      }

      _updateZoomHint(result);

      // One-shot "leftover darts" gate (armed at turn start). The FIRST
      // analyzed frame with a visible board decides:
      //  - darts present → they can only be leftovers (previous visit left in
      //    the board, warm-up practice): show the "remove your darts" hint and
      //    hold scoring until the board is confirmed empty;
      //  - board clean → disarm immediately. Requiring several empty frames
      //    before disarming (the old behaviour) misread a dart thrown right at
      //    turn start as a leftover: the hint asked the player to pull a
      //    legitimate first throw, which was then never scored.
      if (_waitingForEmptyBoard) {
        final boardVisible = result.calibrationPoints.length >= 4;
        if (!_emptyBoardGateSawDarts) {
          // Decision frame — a frame without a visible board proves nothing,
          // keep waiting for the first usable look at the board.
          if (boardVisible) {
            if (dartCount > 0) {
              _emptyBoardGateSawDarts = true;
            } else {
              _waitingForEmptyBoard = false;
              _emptyBoardCheckCount = 0;
            }
          }
        } else if (boardVisible && dartCount == 0) {
          // Takeout phase: leftovers were seen. A single empty frame is
          // unreliable (hand occlusion while pulling darts), so require
          // several consecutive empty frames before scoring resumes.
          _emptyBoardCheckCount++;
          if (_emptyBoardCheckCount >= _emptyBoardCheckThreshold) {
            _waitingForEmptyBoard = false;
            _emptyBoardCheckCount = 0;
            _emptyBoardGateSawDarts = false;
          }
        } else if (dartCount > 0) {
          _emptyBoardCheckCount = 0;
        }
        _trace('GATE waitingForEmptyBoard tips=$dartCount cp=${result.calibrationPoints.length} '
            'sawDarts=${_emptyBoardGateSawDarts ? 1 : 0} '
            'emptyCount=$_emptyBoardCheckCount/$_emptyBoardCheckThreshold '
            '${_waitingForEmptyBoard ? "(frame not scored)" : "(gate cleared)"}');
        await _maybeCleanup(imagePath, cleanupFile);
        _notifyIfChanged();
        return;
      }

      // Auto-confirm
      final anyDartEmitted = _emittedSlots.any((e) => e);
      if (anyDartEmitted &&
          dartCount == 0 &&
          result.calibrationPoints.length >= 4) {
        _consecutiveEmptyBoardCount++;
        if (_consecutiveEmptyBoardCount >= _autoConfirmThreshold) {
          _consecutiveEmptyBoardCount = 0;
          _prevDartCount = 0;
          _trace('GATE auto-confirm (board empty $_autoConfirmThreshold frames) — submitting turn');
          await _maybeCleanup(imagePath, cleanupFile);
          onAutoConfirm?.call();
          return;
        }
      } else {
        _consecutiveEmptyBoardCount = 0;
      }

      // Dart removal detection — require N consecutive empty frames after
      // seeing darts. A single empty frame is unreliable: the model can
      // momentarily lose all tips when a hand or arm crosses the board.
      if (_prevDartCount > 0 && dartCount == 0) {
        _consecutiveRemovalCount++;
        if (_consecutiveRemovalCount >= _removalConfirmThreshold) {
          _consecutiveRemovalCount = 0;
          _prevDartCount = 0;
          _dartsRemoved = true;
          _trace('GATE darts removed (empty $_removalConfirmThreshold frames after darts)');
          await _maybeCleanup(imagePath, cleanupFile);
          _notifyIfChanged();
          return;
        }
        // Don't update _prevDartCount yet — keep accumulating empty frames
        // against the previous non-zero count.
        await _maybeCleanup(imagePath, cleanupFile);
        _notifyIfChanged();
        return;
      }
      _consecutiveRemovalCount = 0;
      _prevDartCount = dartCount;

      // ---- DartsMind autoScore pipeline -----------------------------------
      _autoScore(result, onDartDetected);

      await _maybeCleanup(imagePath, cleanupFile);
      _notifyIfChanged();
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

    // Build a per-frame perspective transform from the 4 calibration points
    // so tips can be remapped into DartsMind's dartboard space (170-centred,
    // 340-side) before mergeTips. Without this, a small board shift between
    // frames would make the same physical dart land at a different normalised
    // image position and create a duplicate TipGroup.
    DartScoringService? scorer;
    if (result.calibrationPoints.length >= 4) {
      try {
        final calibData = result.calibrationPoints
            .take(4)
            .map((c) => [c.x, c.y, c.flag.toDouble()])
            .toList();
        scorer = DartScoringService(calibData);
      } catch (_) {
        scorer = null;
      }
    }

    // Convert detected tips to CnfPoints in board space (DartsMind parity).
    // If no scorer is available this frame, skip the mergeTips pipeline —
    // we can't score without calibration anyway, so adding image-space tips
    // would just pollute the group state with non-comparable coordinates.
    final tipCnfPoints = <CnfPoint>[];
    _latestScores = {};
    if (scorer != null) {
      for (int i = 0; i < result.dartTips.length; i++) {
        final d = result.dartTips[i];
        final board = scorer.toBoard(d.x, d.y);
        tipCnfPoints.add(CnfPoint(board[0], board[1], d.confidence));
        if (i < result.scores.length) {
          // Key by *normalised* board coords (board / boardR) so it shares the
          // same space as Shoot.actualPoint, which is what _lookupScore uses.
          final nbx = board[0] / kBoardR;
          final nby = board[1] / kBoardR;
          _latestScores[
                  '${nbx.toStringAsFixed(4)},${nby.toStringAsFixed(4)}'] =
              result.scores[i];
        }
      }
    }

    if (tipCnfPoints.isEmpty) {
      _autoScoreNoTips(_nowSeconds());
    } else {
      // DartsMind: mergeTips → (internally calls analyseTipGroups → mergeShoots)
      _mergeTips(tipCnfPoints);
    }

    _pruneStaleGroups();
    _assignSlots(onDartDetected);

    _dumpScoringState(result, tipCnfPoints);
  }

  /// Full self-contained snapshot of one analysed frame — see [verboseScoringLog].
  /// Emitted AFTER the pipeline runs so it reflects the resulting group/slot
  /// state; lifecycle EVENT lines (reattach/demote/assign/emit) are logged
  /// inline during the pipeline and appear just above this block for the frame.
  void _dumpScoringState(ScoringResult result, List<CnfPoint> tipCnfPoints) {
    if (!verboseScoringLog) return;
    // Only dump frames where something is happening — a tip was detected, or a
    // group/dart is being tracked. Idle board-watching frames (no tips, no
    // groups) carry no information and would otherwise flood the log, so we
    // skip them. Lifecycle events (EMIT/demote/reattach) are logged separately
    // and always shown.
    final idle = tipCnfPoints.isEmpty &&
        _tipGroups.isEmpty &&
        _shootGroups.isEmpty;
    if (idle) return;
    _trace(
        '── ${_lastInferenceMs}ms | tips=${result.dartTips.length} cp=${result.calibrationPoints.length} '
        'shaking=${_isShaking ? 1 : 0} wait=${_waitingForEmptyBoard ? 1 : 0} ──');
    for (int i = 0; i < tipCnfPoints.length; i++) {
      final t = tipCnfPoints[i];
      final sc = (i < result.scores.length) ? result.scores[i].formatted : '?';
      _trace('  tip[$i] board=(${t.x.toStringAsFixed(1)},${t.y.toStringAsFixed(1)}) '
          'conf=${t.cnf.toStringAsFixed(2)} => $sc');
    }
    _trace('  TG count=${_tipGroups.length}');
    for (final tg in _tipGroups) {
      final a = tg.avgCnfP();
      final fill = '${tg.tips.whereType<CnfPoint>().length}/${tg.tips.length}';
      _trace('    TG ${_sid(tg.id)} '
          'pos=(${a?.x.toStringAsFixed(1) ?? "-"},${a?.y.toStringAsFixed(1) ?? "-"}) '
          'vis=${tg.visibility.name} fpt=${tg.firstPassTime != null ? 1 : 0} '
          'prio=${tg.priority} fill=$fill');
    }
    final counted = _getValidShootDetectionThisRound();
    _trace('  SG count=${_shootGroups.length} counted=$counted');
    for (final sg in _shootGroups) {
      final p = _shootGroupAvgPoint(sg);
      final nn = sg.shoots.whereType<Shoot>().length;
      final slot = _slotShootGroupIds.indexOf(sg.id);
      final slotStr = slot < 0
          ? '-'
          : '$slot${_emittedSlots[slot] ? "E" : ""}';
      _trace('    SG ${_sid(sg.id)} '
          'pos=(${p?[0].toStringAsFixed(3) ?? "-"},${p?[1].toStringAsFixed(3) ?? "-"}) '
          'size=${sg.shoots.length} nn=$nn '
          'nearInv=${sg.hasNearbyInvisibleShootsWhenCreated ? 1 : 0} '
          'prio=${sg.priority} slot=$slotStr');
    }
    final slots = _dartSlots.map((s) => s?.formatted ?? '-').join(',');
    final emitted = _emittedSlots.map((e) => e ? 1 : 0).join('');
    _trace('  slots=[$slots] total=$_turnTotal emitted=$emitted');
  }

  // Bound _tipGroups / _shootGroups so the per-frame inner loops in
  // mergeTips/analyseTipGroups stay constant-time over a long match.
  // Without this, noise-only TipGroups accumulate and the AI gets visibly
  // slower the longer a match runs.
  static const int _maxTipGroups = 30;
  static const int _maxShootGroups = 30;
  static const double _staleTipGroupSeconds = 3.0;

  void _pruneStaleGroups() {
    if (_tipGroups.isEmpty && _shootGroups.isEmpty) return;
    final now = _nowSeconds();

    // Drop tip groups that have gone invisible and haven't been seen for a while
    // and were never confirmed (firstPassTime == null). These are detector noise.
    _tipGroups.removeWhere((tg) =>
        tg.visibility == TipVisibility.invisible &&
        tg.firstPassTime == null &&
        (now - tg.latestVisibleTime) > _staleTipGroupSeconds);

    // Hard cap: keep the most recently created groups. Anything older is either
    // long-confirmed (already mirrored in _shootGroups) or stale noise.
    if (_tipGroups.length > _maxTipGroups) {
      _tipGroups.sort((a, b) => b.createdTime.compareTo(a.createdTime));
      _tipGroups = _tipGroups.take(_maxTipGroups).toList();
    }

    if (_shootGroups.length > _maxShootGroups) {
      _shootGroups.sort((a, b) => b.createdTime.compareTo(a.createdTime));
      _shootGroups = _shootGroups.take(_maxShootGroups).toList();
    }
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
      if (best != null && best.$3 <= _tipMergeThresholdBoard) {
        matched.add(best);
      } else if (best != null && best.$3 <= _tipMergeThresholdBoard * 2) {
        // Near-miss: a tip just outside the merge zone usually means detector
        // noise drifted further than expected. Log so we can tune the
        // threshold if the duplicate-dart bug resurfaces.
        _trace(
            'EVENT near-miss dist=${best.$3.toStringAsFixed(2)} '
            '(thr=${_tipMergeThresholdBoard.toStringAsFixed(2)}) — new TipGroup');
      }
    }

    // Step 2b: Split-blob reattach (duplicate-dart fix).
    // A single blurry dart is sometimes detected as one tip at the centroid of
    // what are really two darts. When the blob later resolves into two distinct
    // tips, both land in the near-miss band (1.6–3.2 board units) straddling the
    // original group: neither matches it (>1.6), so the original is orphaned and
    // BOTH tips spawn new groups — leaving original + 2 new = three counted darts
    // for two physical darts (the duplicate seen in the logs: slots 0/1/2 all S5).
    //
    // When an already-confirmed group would be orphaned this frame but two or
    // more still-unmatched tips sit in its near-miss band, treat it as a split:
    // reattach the orphaned group to its nearest near-miss tip so it absorbs one
    // split product instead of leaving it to spawn a new group. The other tip(s)
    // create new groups as usual. Net count stays correct.
    //
    // Guarded to confirmed groups (firstPassTime != null) only — an unconfirmed
    // group that splits never inflated the count, so it needs no special case.
    // Top-level only: orphaning is judged against the whole frame's tips.
    if (!isFromInside) {
      final reattachThreshold = _tipMergeThresholdBoard * 2;
      final matchedTipSet = matched.map((m) => m.$2).toSet();
      final matchedGroupSet = matched.map((m) => m.$1).toSet();
      for (int g = 0; g < _tipGroups.length; g++) {
        final tg = _tipGroups[g];
        if (tg.firstPassTime == null) continue;
        if (matchedGroupSet.contains(tg.id)) continue;
        final avg = tg.avgCnfP();
        if (avg == null) continue;
        final nearby = <(int, double)>[];
        for (int i = 0; i < size; i++) {
          if (matchedTipSet.contains(i)) continue;
          final dist = _distanceOf2Points(avg.x, avg.y, tips[i].x, tips[i].y);
          if (dist > _tipMergeThresholdBoard && dist <= reattachThreshold) {
            nearby.add((i, dist));
          }
        }
        if (nearby.length >= 2) {
          nearby.sort((a, b) => a.$2.compareTo(b.$2));
          final closest = nearby.first;
          matched.add((tg.id, closest.$1, closest.$2));
          matchedTipSet.add(closest.$1);
          matchedGroupSet.add(tg.id);
          _trace(
              'EVENT reattach TG ${_sid(tg.id)} absorbed split tip '
              'dist=${closest.$2.toStringAsFixed(2)} '
              '(${nearby.length} near-miss tips) — prevents phantom dart');
        }
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

        if (bestDist <= _tipMergeThresholdBoard && bestMerge != null) {
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
              _tipMergeThresholdBoard) {
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
    // Phase 8: Convert visible groups to Shoots via dartTipToShoot.
    // DartsMind: dartTipToShoot(170.0f, tipPosition) — divides board-space
    // (170-centred) by boardR to get normalised board coords centred at (1, 1).
    // _hasNearbyInvisibleShoots compares actualPoint against the 0.0588 (1/17)
    // threshold in that same normalised space.
    final shoots = <Shoot>[];
    for (final tg in visibleGroups) {
      final tip = tg.tips.firstOrNull;
      if (tip == null) continue;

      final shoot = Shoot(0, 0); // placeholder, score comes from detection
      shoot.visionId = tg.id;
      shoot.cnf = tip.cnf.toDouble();
      shoot.actualPoint = [tip.x / kBoardR, tip.y / kBoardR];
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

  // Frames a suspect (born-near-invisible) shoot group must survive before it
  // may be emitted — see _assignSlots. Must be strictly greater than the
  // demotion checkpoint below (length >= 4) so the duplicate demotion always
  // runs before a phantom could be committed (we cannot un-emit a dart).
  static const int _phantomConfirmFrames = 5;

  // ---- Duplicate-suppression / safe-emit tuning --------------------------
  // Duplicate radius in normalised board space (Shoot.actualPoint space,
  // boardR == 1). DartsMind's 1/17 ≈ 0.0588 — the band where a re-detected
  // phantom of the SAME physical dart lands: it escaped the 1.6-board-unit tip
  // merge (so it spawned its own group) yet is still close to the real dart.
  static const double _dupRadiusNorm = 0.058823529411764705;

  // A counted shoot group must be detected in at least this many frames before
  // it may be emitted. Filters brief detector flicker and very-fresh phantoms,
  // neither of which has accumulated real hits yet. We never un-emit (a shown
  // score must never change or vanish), so the first emit has to be trustworthy.
  // A counted group needs only 1 detection to emit — it already had to pass
  // the TipGroup clearVisible gate (≥2 detected tip frames) to become a Shoot,
  // so this isn't raw noise. Kept at 1 so normal scoring emits as fast as the
  // original pipeline; the contention wait below (which only triggers for a
  // genuinely co-located competitor) is what guards against duplicates, so it
  // adds latency ONLY in the rare contested case, never to ordinary darts.
  // On slow-frame devices (Android) a larger value here translates directly to
  // seconds of lag per dart, so it must stay small.
  static const int _emitMinHits = 1;

  // Generalised phantom suppression (revives DartsMind's maybeFake removal:
  // "a more certain dart appeared, remove the previous one"). Two counted
  // groups closer than _dupRadiusNorm are judged the same physical dart when
  // one is clearly more consistently detected: its fill ratio must lead by at
  // least _phantomFillRatioMargin AND it must have at least _phantomHitsMargin
  // more non-null hits and be solidly established (_phantomStrongMinHits). Two
  // genuinely distinct darts in a tight cluster are BOTH detected consistently
  // (similar high fill), so neither is demoted.
  static const double _phantomFillRatioMargin = 0.34;
  static const int _phantomHitsMargin = 2;
  static const int _phantomStrongMinHits = 4;

  // While two co-located counted groups are still young and comparably
  // detected we cannot yet tell "two real darts" from "one dart + its phantom",
  // so we hold BOTH back from emitting until either one is demoted (phantom
  // resolved) or the pair has lasted this many frames (both proven real → emit
  // both). Holding rather than emit-then-correct is what keeps a shown dart
  // from ever changing.
  static const int _contentionResolveFrames = 3;

  // ========================================================================
  // DartsMind: analyseShootGroups (faithful port of the duplicate-suppression
  // pass — DVMind.java analyseShootGroups, verified against dartsmindv2 bytecode)
  // ========================================================================
  void _analyseShootGroups(int shootCount) {
    // Duplicate suppression only runs when ≥2 darts were confirmed within ~1s
    // of each other (DartsMind: |last.createdTime - first.createdTime| < 1.0).
    // That is the only window in which one physical dart can spawn a phantom
    // second group; outside it, two darts that close in time are real.
    final p0Count = _shootGroups.where((sg) => sg.priority == 0).length;
    if (p0Count >= 2 &&
        _shootGroups.isNotEmpty &&
        (_shootGroups.last.createdTime - _shootGroups.first.createdTime).abs() <
            1.0) {
      for (final sg in _shootGroups) {
        if (sg.priority != 0) continue;
        // Suspect must be YOUNG (DartsMind: exactly 4 observations) — we use
        // >=4 so a missed frame can't let a phantom slip past the checkpoint;
        // priority=1 is sticky so re-checking later rounds is harmless.
        if (sg.shoots.length < 4) continue;
        // ...born next to a dart whose tip had just gone INVISIBLE (the split
        // signature; a genuine tight second dart is born beside a VISIBLE dart),
        if (!sg.hasNearbyInvisibleShootsWhenCreated) continue;
        // ...and WEAKLY detected (≤2 real hits). This is the guard that keeps a
        // real, solidly-tracked dart from ever being demoted.
        if (sg.shoots.whereType<Shoot>().length > 2) continue;
        final p = _shootGroupAvgPoint(sg);
        if (p == null) continue;
        // Is there a well-ESTABLISHED (≥7 frames) counted dart within 1/17
        // board-radius? Then this young/weak group is that dart's phantom.
        bool isDuplicate = false;
        for (final other in _shootGroups) {
          if (identical(other, sg)) continue;
          if (other.priority != 0) continue;
          if (other.shoots.length < 7) continue;
          final op = _shootGroupAvgPoint(other);
          if (op == null) continue;
          // DartsMind: 0.058823529411764705 ≈ 1/17.
          if (_distanceOf2Points(p[0], p[1], op[0], op[1]) <
              0.058823529411764705) {
            isDuplicate = true;
            break;
          }
        }
        if (isDuplicate) {
          sg.priority = 1;
          final tg = _tipGroups.where((t) => t.id == sg.id).firstOrNull;
          if (tg != null) tg.priority = 1;
          _trace(
              'EVENT demote SG ${_sid(sg.id)} (young size=${sg.shoots.length}, '
              'weak nn=${sg.shoots.whereType<Shoot>().length}, within 1/17 of an '
              'established dart) — not counted');
        }
      }
    }

    // Generalised duplicate suppression — the primary defence against one
    // physical dart being counted twice, and independent of the narrow rule
    // above. For every pair of counted groups within the duplicate radius, if
    // one is clearly more consistently detected than the other, the weaker one
    // is the same dart re-detected at a jittered position — demote it. Fill
    // ratio is age-invariant, so a real second dart thrown late (high fill, few
    // frames) is NOT mistaken for a phantom, and two tight darts (both high
    // fill) keep each other. Runs every frame and BEFORE _assignSlots, so a
    // phantom leaves the count before it could ever be emitted.
    for (final sg in _shootGroups) {
      if (sg.priority != 0) continue;
      // Never demote a dart that has already been shown to the user — its slot
      // is locked (we never retract), so keep it counted to stay consistent.
      final sgSlot = _slotShootGroupIds.indexOf(sg.id);
      if (sgSlot >= 0 && _emittedSlots[sgSlot]) continue;
      final p = _shootGroupAvgPoint(sg);
      if (p == null) continue;
      final sgFill = _sgFillRatio(sg);
      final sgHits = _sgNonNull(sg);
      for (final other in _shootGroups) {
        if (identical(other, sg)) continue;
        if (other.priority != 0) continue;
        final op = _shootGroupAvgPoint(other);
        if (op == null) continue;
        if (_distanceOf2Points(p[0], p[1], op[0], op[1]) >= _dupRadiusNorm) {
          continue;
        }
        // `other` clearly out-detects `sg` → `sg` is the phantom.
        if (_sgNonNull(other) >= _phantomStrongMinHits &&
            _sgNonNull(other) >= sgHits + _phantomHitsMargin &&
            _sgFillRatio(other) - sgFill >= _phantomFillRatioMargin) {
          sg.priority = 1;
          final tg = _tipGroups.where((t) => t.id == sg.id).firstOrNull;
          if (tg != null) tg.priority = 1;
          _trace('EVENT demote SG ${_sid(sg.id)} '
              '(phantom fill=${sgFill.toStringAsFixed(2)}/${sgHits}h vs '
              'SG ${_sid(other.id)} fill=${_sgFillRatio(other).toStringAsFixed(2)}/'
              '${_sgNonNull(other)}h within 1/17) — not counted');
          break;
        }
      }
    }

    // Remove shoot groups that have been all-null for too long (noise cleanup).
    _shootGroups.removeWhere((sg) {
      if (sg.priority != 0) return false;
      final recentNonNull =
          sg.shoots.reversed.take(5).whereType<Shoot>().length;
      return sg.shoots.length >= 5 && recentNonNull == 0;
    });
  }

  /// Average normalised position (Shoot.actualPoint space, boardR == 1) of a
  /// shoot group's non-null shoots — same averaging as _hasNearbyInvisibleShoots
  /// so all 1/17 distance comparisons share one coordinate space.
  List<double>? _shootGroupAvgPoint(ShootGroup sg) {
    double sx = 0, sy = 0;
    int n = 0;
    for (final s in sg.shoots.whereType<Shoot>()) {
      if (s.actualPoint != null && s.actualPoint!.length >= 2) {
        sx += s.actualPoint![0];
        sy += s.actualPoint![1];
        n++;
      }
    }
    if (n == 0) {
      final fp = sg.firstShoot.actualPoint;
      return (fp != null && fp.length >= 2) ? [fp[0], fp[1]] : null;
    }
    return [sx / n, sy / n];
  }

  /// Number of frames in which a shoot group was actually detected.
  int _sgNonNull(ShootGroup sg) => sg.shoots.whereType<Shoot>().length;

  /// Fraction of a shoot group's (capped) history in which it was detected.
  /// Age-invariant: a real dart — even one thrown late in the turn — has a high
  /// fill ratio because it is seen nearly every frame since it landed, whereas a
  /// phantom is sporadic and its ratio stays low. This is the signal that tells
  /// a phantom apart from a genuine second dart sitting in a tight cluster.
  double _sgFillRatio(ShootGroup sg) {
    if (sg.shoots.isEmpty) return 0.0;
    return _sgNonNull(sg) / sg.shoots.length;
  }

  /// True while another counted, not-yet-committed group sits within the
  /// duplicate radius and we cannot yet safely decide whether the two are two
  /// real darts or one dart plus its phantom. We hold [sg] back until either the
  /// phantom is demoted (drops out of the count) or the pair has lasted
  /// [_contentionResolveFrames] (both proven real → both emit). This is what
  /// lets us suppress duplicates without ever retracting a dart already shown.
  bool _hasUnresolvedNearbyCompetitor(ShootGroup sg) {
    final p = _shootGroupAvgPoint(sg);
    if (p == null) return false;
    for (final other in _shootGroups) {
      if (identical(other, sg)) continue;
      if (other.priority != 0) continue; // demoted → resolved
      final oIdx = _slotShootGroupIds.indexOf(other.id);
      if (oIdx >= 0 && _emittedSlots[oIdx]) continue; // already committed → resolved
      final op = _shootGroupAvgPoint(other);
      if (op == null) continue;
      if (_distanceOf2Points(p[0], p[1], op[0], op[1]) >= _dupRadiusNorm) {
        continue;
      }
      // Co-located, and `other` is neither demoted nor committed. While the
      // pair is still young, wait — the demotion pass needs a few frames to
      // expose a phantom's low fill ratio.
      final pairFrames = max(sg.shoots.length, other.shoots.length);
      if (pairFrames < _contentionResolveFrames) return true;
      // Old enough but `other` still clearly out-detects us → we are the likely
      // phantom; keep waiting (it will be demoted, or `other` emits first).
      if (_sgNonNull(other) > _sgNonNull(sg) &&
          _sgFillRatio(other) - _sgFillRatio(sg) >= _phantomFillRatioMargin) {
        return true;
      }
    }
    return false;
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
    // Intentionally do NOT re-score already-emitted slots. Once the AI has
    // committed to a score for a slot, we stick with it for the rest of the
    // turn. Detected tip positions wobble frame-to-frame, and on darts that
    // land near a segment boundary (e.g. between 1 and 20) the score would
    // otherwise flicker on the UI. Only overrideDart() — invoked by manual
    // user edits — can change a slot's score after it has been emitted.

    // Assign unassigned shoot groups to empty slots
    for (final sg in _shootGroups) {
      if (sg.priority != 0) continue;
      if (_slotShootGroupIds.contains(sg.id)) continue;

      // Universal settle gate. We never un-emit (constraint: a shown dart's
      // score must never change or vanish), so a dart is committed only once it
      // is safe on three counts:
      //  (a) it has been detected in at least _emitMinHits frames — filters
      //      detector flicker and very-fresh phantoms;
      //  (b) the legacy suspect delay still applies — a group born next to a
      //      dart whose tip had just gone invisible (the split signature) waits
      //      out the demotion checkpoint; and
      //  (c) no unresolved co-located competitor remains — we cannot yet tell a
      //      real second dart from this dart's phantom, so we hold until the
      //      duplicate suppressor demotes the loser or both prove real.
      // The common case — a clean, isolated dart — trips none of (b)/(c) and
      // emits as soon as it has _emitMinHits hits, so ordinary scoring stays
      // responsive.
      if (_sgNonNull(sg) < _emitMinHits) continue;
      if (sg.hasNearbyInvisibleShootsWhenCreated &&
          sg.shoots.length < _phantomConfirmFrames) {
        continue;
      }
      if (_hasUnresolvedNearbyCompetitor(sg)) continue;

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
          final firstEmit = !_emittedSlots[s];
          _trace('EVENT ${firstEmit ? "EMIT" : "assign"} slot$s <- '
              'SG ${_sid(sg.id)} ${score.formatted}');
          if (firstEmit) {
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
