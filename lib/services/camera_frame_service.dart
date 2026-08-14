import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show DeviceOrientation;
import 'package:path_provider/path_provider.dart';
import 'package:image/image.dart' as img;

import 'replay_buffer_service.dart';
import 'rtc_frames_service.dart';
import '../utils/storage_service.dart';

/// Owns the Flutter camera during gameplay and distributes frames to both
/// the P2P video call and AI scoring (for dart detection).
///
/// The app controls the camera via CameraX (here Flutter's camera package)
/// and pushes the frames it captures into the WebRTC track itself, rather
/// than letting the RTC stack own the camera.
class CameraFrameService {
  CameraController? _controller;
  // Online match: frames go to RtcFramesService (WebRTC track). False in solo
  // modes (training, placement), where only the AI consumes them.
  bool _p2pMode = false;
  bool _isStreaming = false;
  bool _disposed = false;

  // Session-wide camera frame rate. D8 capped it at 15 (no consumer takes
  // more: the AI pulls ≤4/s, the RTC push is throttled to ~15 via
  // _minPushInterval, the ring encodes at the camera rate). Match modes
  // briefly ran at 24 for smoother shareable clips (2026-08-03), but the
  // 2026-08-10 thermal audit showed the extra 60% of per-frame pipeline was
  // paid for the WHOLE match — including the opponent's turn, where the ring
  // doesn't encode — so it's back to 15 everywhere: clips trade a bit of
  // smoothness for a phone that stops throttling mid-match. Public: the
  // camera-setup screens and the P2P encoder cap reference it so the value
  // has ONE Dart home (it moved twice in a week; every desync re-opens a
  // heat leak). The native encoder hints still mirror it by hand
  // (ReplayBufferPlugin.FRAME_RATE, the iOS writer/export settings,
  // ReplayOverlayRenderer) — keep them in step.
  static const int cameraFps = 15;

  // Push cadence into the call: time-based (~16 fps max), robust to whatever
  // rate the camera actually delivers. The old skip-every-2nd-frame counter
  // assumed a 30 fps stream, which the D8 cap makes wrong.
  DateTime? _lastPushAt;
  static const Duration _minPushInterval = Duration(milliseconds: 60);
  // P2P cadence while the turn gate is closed (opponent's turn): nobody
  // displays our stream, but the peer's media watchdog samples framesDecoded
  // every 3s and reads 6s of silence as a frozen call — a fully muted sender
  // triggered a PeerConnection rebuild loop every opponent turn (review
  // 2026-08-10). ~1 fps keeps the watchdog fed for ~7% of the full-rate
  // encode/copy cost.
  static const Duration _gatedPushInterval = Duration(seconds: 1);

  // Reusable push buffer. Allocating 1.4 MB (Android YUV) / 3.7 MB (iOS
  // BGRA) per pushed frame, 15×/s for a whole match, was a constant GC feed —
  // the same allocation pressure behind the June "5s per dart" regression.
  // A single slot suffices: the method channel serializes the bytes during
  // pushFrame, so the buffer is free again the moment it returns.
  Uint8List? _pushBufferSlot;
  // Replay tee staging buffer — see _pushFrameToReplay.
  Uint8List? _replayBuffer;
  // The frame currently staged in [_replayBuffer] (+ its format), so the P2P
  // push can reuse that tight copy instead of filling a second identical one
  // (thermal audit 2026-08-10: the double fill was ~1.4MB of extra memcpy on
  // every my-turn frame). Safe because the method channel serializes both
  // sends synchronously. Cleared on every camera callback.
  CameraImage? _replayStagedFrame;
  String? _replayStagedFormat;
  bool _replayMode = false;

  // Cache the latest frame for AI scoring capture
  CameraImage? _latestFrame;

  // Whether the AI capture loop currently wants frames (see [setAiActive]).
  bool _aiActive = true;
  int? _sensorOrientation;
  bool _firstPushLogged = false;
  DeviceOrientation? _lastLoggedOrientation;

  // Which physical lens is currently open. Follows the persisted preference on
  // start and flips via [switchCamera].
  CameraLensDirection _lensDirection = CameraLensDirection.back;
  bool _switching = false;

  CameraController? get controller => _controller;
  bool get isInitialized => _controller?.value.isInitialized ?? false;
  CameraLensDirection get lensDirection => _lensDirection;

  // --- ANDROID-ONLY device-orientation-aware frame rotation -----------------
  // Android delivers image-stream frames in FIXED sensor coordinates that do
  // NOT follow the device's physical rotation, so in landscape the board ends
  // up sideways (90°/270°) and the detector loses calibration points. We
  // compensate for the current physical orientation so the board is always fed
  // to the model upright (0°) or flipped (180°) — both of which it handles —
  // but never sideways.
  //
  // iOS uses NONE of this. Its camera plugin already delivers frames rotated to
  // the active device orientation, so the board is upright at 0° in every
  // orientation. The iOS capture paths pass a hard-coded 0 and are kept
  // byte-for-byte identical to the pre-landscape behaviour — applying any
  // rotation there would tip the already-upright board sideways (a 20 read as
  // a 6).

  /// UI rotation away from portraitUp, in degrees. Same table as
  /// camera_android's DeviceOrientationManager.getVideoOrientation — the
  /// plugin that hands us both the frames and the orientation, so its
  /// convention is the one that has to be matched.
  static int _deviceRotationDegreesOf(DeviceOrientation? orientation) {
    switch (orientation) {
      case DeviceOrientation.landscapeRight:
        return 90;
      case DeviceOrientation.portraitDown:
        return 180;
      case DeviceOrientation.landscapeLeft:
        return 270;
      case DeviceOrientation.portraitUp:
      default:
        return 0;
    }
  }

  /// Pure form of [_effectiveRotation], shared with the camera-setup screens:
  /// the clockwise rotation (degrees) that lands the raw Android sensor frame
  /// board-upright. Setup used to hard-code 0 here, which fed the model a
  /// sideways board on every portrait phone — the detector then lost
  /// calibration points and the placement gate never unlocked.
  ///
  /// This is camera_android's own getVideoOrientation, reimplemented: UI angle
  /// (negated for a front lens, whose sensor faces the other way) plus the
  /// sensor mount angle. The hand-rolled version it replaces special-cased
  /// landscape with a flat +180 and was right only for a BACK lens: on the
  /// FRONT lens both landscape orientations came out exactly 180° off, which
  /// is the upside-down landscape replay reported on Android 2026-08-14 (20 at
  /// the bottom, 3 at the top). portraitDown was 180° off on both lenses.
  static int uprightRotationFor({
    required int sensorOrientation,
    required DeviceOrientation? deviceOrientation,
    bool isFrontFacing = false,
  }) {
    final angle = _deviceRotationDegreesOf(deviceOrientation);
    final signed = isFrontFacing ? -angle : angle;
    return (signed + sensorOrientation + 720) % 360;
  }

  /// ANDROID-ONLY clockwise rotation (degrees) for the raw sensor frame so the
  /// board is upright — for the model AND as the push rotation metadata
  /// (both share the same "rotate CW to upright" semantic).
  /// Must never be called on the iOS paths — those pass a literal 0.
  int _effectiveRotation() {
    final o = _controller?.value.deviceOrientation;
    final rot = uprightRotationFor(
      sensorOrientation: _sensorOrientation ?? 0,
      deviceOrientation: o,
      isFrontFacing: _lensDirection == CameraLensDirection.front,
    );
    // Snapshotted for [rotationDiagnostics]: an "upside-down replay" report is
    // only answerable if the inputs the decision was made from are in the log
    // next to the decision itself.
    _lastSensorOrientation = _sensorOrientation;
    _lastDeviceOrientation = o;
    _lastLens = _lensDirection;
    _lastEffectiveRotation = rot;
    if (o != _lastLoggedOrientation) {
      final changed = _lastLoggedOrientation != null;
      _lastLoggedOrientation = o;
      debugPrint('[CameraFrameService] deviceOrientation=$o '
          'sensor=$_sensorOrientation lens=$_lensDirection '
          'effectiveRotation=$rot');
      // The phone physically turned, so the raw sensor frame turned with it
      // and any calibration measured before is about a scene that no longer
      // exists. Dropping it falls back to the (orientation-aware) sensor value
      // for the frame or two it takes the AI to measure the new pose — keeping
      // it would stamp landscape footage with a portrait hint.
      if (changed) invalidateBoardTilt();
    }
    return rot;
  }

  // --- Calibration-derived replay orientation (Android only) ----------------
  // The replay ring stores RAW sensor frames and relies on the MP4 rotation
  // hint to play them upright. Deriving that hint from [_effectiveRotation]
  // lies on mounted phones: rotation lock ON with the phone strapped sideways
  // pointing at the board reads as "portrait", the hint comes out 90 on
  // content that is already upright, and every replay plays sideways —
  // while scoring stays correct, because the homography absorbs any board
  // angle, so nothing in the match ever exposes it. The AI calibration is
  // the one witness of where the 20 actually is in the frame, so the replay
  // hint is derived from it and only falls back to the sensor guess until
  // the first calibration lands. Static on purpose: the camera-setup screen
  // measures on its own instance before the match instance exists, and the
  // physical mount doesn't change between the two.
  static int? _calibrationUprightRotation;
  static int _uprightCandidate = -1;
  static int _uprightStreak = 0;
  static double? _lastMeasuredTilt;
  static int? _lastMeasuredAnalysisRotation;

  // Inputs of the last [_effectiveRotation], for [rotationDiagnostics].
  static int? _lastSensorOrientation;
  static DeviceOrientation? _lastDeviceOrientation;
  static CameraLensDirection? _lastLens;
  static int? _lastEffectiveRotation;

  /// Report a fresh board-orientation measurement from the AI calibration.
  /// [analysisRotation] is the clockwise rotation that was applied to the raw
  /// frame before inference; [tiltDegrees] the board's clockwise tilt
  /// measured in that analyzed frame (see [BoardFraming.tiltDegrees]). Their
  /// difference is the rotation that plays the RAW frame board-upright,
  /// quantized to the nearest 90° (all an MP4 hint can encode).
  ///
  /// The FIRST measurement is adopted at once, because the alternative is the
  /// sensor guess and this is strictly better than it: the subtraction cancels
  /// out whatever [analysisRotation] was, right or wrong, so the result only
  /// depends on where the 20 actually is. Only CHANGING an established value
  /// waits for 3 consecutive agreeing measurements, so one bad calibration
  /// frame can't flip the ring's orientation mid-match.
  static void reportBoardTilt({
    required int analysisRotation,
    required double tiltDegrees,
  }) {
    final upright = (analysisRotation - tiltDegrees) % 360;
    final quantized = (((upright + 360) % 360 + 45) ~/ 90) * 90 % 360;
    _lastMeasuredTilt = tiltDegrees;
    _lastMeasuredAnalysisRotation = analysisRotation;
    if (quantized == _uprightCandidate) {
      _uprightStreak++;
    } else {
      _uprightCandidate = quantized;
      _uprightStreak = 1;
    }
    final adopt = _calibrationUprightRotation == null || _uprightStreak >= 3;
    if (adopt && _calibrationUprightRotation != quantized) {
      debugPrint('[CameraFrameService] replay rotation hint from calibration: '
          '$quantized° (analysisRotation=$analysisRotation '
          'tilt=${tiltDegrees.toStringAsFixed(1)}°)');
      _calibrationUprightRotation = quantized;
    }
  }

  /// Forget the measured board orientation — see the caller in
  /// [_effectiveRotation]. The next AI frame re-establishes it immediately.
  static void invalidateBoardTilt() {
    _calibrationUprightRotation = null;
    _uprightCandidate = -1;
    _uprightStreak = 0;
  }

  /// The best known "rotate the raw frame CW by this to see the 20 on top",
  /// or null before any calibration has landed. Read when a clip is CUT, not
  /// only when frames are pushed: the ring stamps each segment with whatever
  /// was known while it was recording, so a clip spanning the moment the
  /// calibration first landed used to inherit the sensor guess from its
  /// older (dominant) segments.
  static int? get calibratedUprightRotation => _calibrationUprightRotation;

  /// Every input the replay orientation decision rests on, in one line. Logged
  /// when a clip is cut so an "upside-down replay" report names its own cause
  /// instead of costing a reproduction session.
  static String get rotationDiagnostics =>
      'calibrated=$_calibrationUprightRotation '
      '(streak=$_uprightStreak candidate=$_uprightCandidate '
      'lastTilt=${_lastMeasuredTilt?.toStringAsFixed(1)} '
      'lastAnalysisRotation=$_lastMeasuredAnalysisRotation) '
      'sensorGuess=$_lastEffectiveRotation '
      '(sensorOrientation=$_lastSensorOrientation '
      'deviceOrientation=$_lastDeviceOrientation lens=$_lastLens)';

  /// Initialize the camera. When [p2pMode] is true, frames are pushed to
  /// [RtcFramesService.pushFrame] for the video call. Leave it false for solo
  /// modes (training, placement) where the local camera preview is shown
  /// directly via the exposed [controller] and only AI scoring needs the
  /// frame stream.
  ///
  /// [replayRing] additionally tees every frame into the native replay ring
  /// buffer (see ReplayBufferService) — match modes only.
  Future<void> initialize({
    bool p2pMode = false,
    bool replayRing = false,
  }) async {
    _p2pMode = p2pMode;
    _replayMode = replayRing && ReplayBufferService.isSupported;
    if (_replayMode) ReplayBufferService.arm();

    // Honour the persisted front/back choice (set from the camera-setup screen
    // or a previous in-game switch). Defaults to the back camera.
    final useFront = await StorageService.getUseFrontCamera();
    final requested =
        useFront ? CameraLensDirection.front : CameraLensDirection.back;

    if (!await _openCamera(requested)) return;
    if (_disposed) return;

    // Start the image stream — each frame goes to the call + cached for AI
    await _awaitStream(_startImageStream());
  }

  /// Open (or re-open) the physical camera for the given [requested] lens.
  /// Falls back to the back camera, then any camera, when that lens is
  /// unavailable, and records the lens actually opened in [_lensDirection] /
  /// [_sensorOrientation]. Returns false if no camera could be initialised.
  Future<bool> _openCamera(CameraLensDirection requested) async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      debugPrint('[CameraFrameService] No cameras available');
      return false;
    }

    final selected = cameras.firstWhere(
      (c) => c.lensDirection == requested,
      orElse: () => cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      ),
    );
    _lensDirection = selected.lensDirection;
    _sensorOrientation = selected.sensorOrientation;
    debugPrint(
        '[CameraFrameService] platform=${Platform.isIOS ? "iOS" : "Android"} '
        'camera=${selected.name} lens=$_lensDirection '
        'sensorOrientation=$_sensorOrientation');

    CameraController buildController() => CameraController(
          selected,
          ResolutionPreset.high, // 720p
          enableAudio: false, // WebRTC owns audio — avoid iOS AVAudioSession conflict
          // DartsMind caps its camera at 8–16 fps; the sensor default (~30)
          // doubles the whole per-frame pipeline for nothing: the AI consumes
          // ≤4 frames/s and the video encoder is configured for 15 fps.
          // iOS: applied by camera_avfoundation via activeVideoM{in,ax}FrameDuration.
          // Android: applied by our vendored camera_android patch (see
          // packages/camera_android — stock only applies fps while recording).
          fps: cameraFps,
          imageFormatGroup: Platform.isAndroid
              ? ImageFormatGroup.yuv420
              : ImageFormatGroup.bgra8888,
        );

    // Initialize with retries. When a match is found mid-training, the training
    // screen still owns the camera and only releases it from its dispose() —
    // which Flutter defers until *our* (the match screen's) push transition
    // completes (~300ms), after which CameraController.dispose() frees the
    // device asynchronously. So the camera can keep throwing "already in use"
    // for up to ~1s after navigation. A single quick retry (the old behaviour)
    // gave up long before then, leaving the match with dead video + AI until
    // the app was restarted. Retry across the whole release window instead.
    // The match screen shows its loading state until this returns, so the only
    // visible effect is a slightly longer "Starting camera…".
    const maxAttempts = 8;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      if (_disposed) return false;
      _controller = buildController();
      try {
        await _controller!.initialize();
        break;
      } catch (e) {
        await _controller?.dispose();
        _controller = null;
        if (attempt == maxAttempts - 1) {
          debugPrint('[CameraFrameService] init failed after $maxAttempts attempts: $e');
          return false;
        }
        debugPrint(
            '[CameraFrameService] init failed (attempt ${attempt + 1}/$maxAttempts), '
            'retrying in 400ms: $e');
        await Future.delayed(const Duration(milliseconds: 400));
      }
    }
    // dispose() may have raced in during the (now longer) retry window. It sets
    // _disposed first and owns tearing down the controller it saw, so bail here
    // rather than dereference _controller! (which it may already have nulled) or
    // start a stream on a controller that is being disposed.
    if (_disposed) return false;
    final preview = _controller!.value.previewSize;
    debugPrint(
        '[CameraFrameService] previewSize=${preview?.width}x${preview?.height}');

    // Disable flash
    try {
      await _controller!.setFlashMode(FlashMode.off);
    } catch (_) {}

    return true;
  }

  /// Flip between the back and front camera during gameplay. Tears down the
  /// current controller, opens the other lens, resumes streaming to call + AI,
  /// and persists the choice so it carries to the next screen and next launch.
  /// No-op while a switch is already in flight or after [dispose].
  Future<void> switchCamera() async {
    if (_disposed || _switching) return;
    _switching = true;
    try {
      final target = _lensDirection == CameraLensDirection.front
          ? CameraLensDirection.back
          : CameraLensDirection.front;

      // Tear down the current controller. Null it out FIRST so any widget
      // rebuild that races with us reads a null controller (and renders its
      // placeholder) instead of touching a disposed one.
      // Await the stop: the controller must be out of streaming state before
      // it is disposed, and before the new lens starts its own stream.
      await _awaitStream(_stopImageStream());
      final old = _controller;
      _controller = null;
      _latestFrame = null;
      _firstPushLogged = false;
      await old?.dispose();
      if (_disposed) return;

      if (!await _openCamera(target)) return;
      if (_disposed) return;
      await _awaitStream(_startImageStream());

      // Persist the lens actually opened (the target may have fallen back to
      // back when the device has no camera for that direction).
      await StorageService.saveUseFrontCamera(
          _lensDirection == CameraLensDirection.front);
    } finally {
      _switching = false;
    }
  }

  // Serialises every image-stream transition, and records the DESIRED state
  // rather than acting on it immediately.
  //
  // CameraController.start/stopImageStream are async, and both plugins
  // (camera_android, camera_avfoundation) keep a SINGLE platform-side frame
  // controller. Fire-and-forget calls could therefore overlap: a stop still in
  // flight when the next start ran finished last and tore down the freshly
  // started stream (its cancel nulls the plugin's frame controller and cancels
  // the new platform subscription). The camera then delivered no frames at all,
  // silently. A hot-seat turn change did exactly that — stopCapture() then
  // startCapture() in the same event-loop turn — so auto-scoring was dead for
  // the next player until an unrelated clean stop/start (a manual dart edit)
  // rebuilt the stream.
  //
  // Queueing the transitions also coalesces that stop→start pair into a no-op:
  // the stream simply keeps running across the turn change.
  Future<void> _streamQueue = Future<void>.value();
  bool _wantStreaming = false;

  Future<void> _startImageStream() => _setStreaming(true);

  Future<void> _stopImageStream() => _setStreaming(false);

  Future<void> _setStreaming(bool want) {
    _wantStreaming = want;
    final op = _streamQueue.then((_) => _applyStreamingState()).catchError(
        (Object e) =>
            debugPrint('[CameraFrameService] stream transition failed: $e'));
    _streamQueue = op;
    return op;
  }

  /// Await a queued transition without letting a wedged platform call block
  /// teardown: a camera plugin that never answers must not freeze a lens
  /// switch, nor keep the device locked for the next screen (which retries
  /// "camera already in use" for a limited window — see [_openCamera]).
  Future<void> _awaitStream(Future<void> op) =>
      op.timeout(const Duration(seconds: 2), onTimeout: () {});

  Future<void> _applyStreamingState() async {
    final controller = _controller;
    final want = _wantStreaming &&
        !_disposed &&
        controller != null &&
        controller.value.isInitialized;
    if (want == _isStreaming) return;

    if (want) {
      _isStreaming = true;
      try {
        await controller.startImageStream(_onCameraImage);
      } catch (e) {
        _isStreaming = false;
        debugPrint('[CameraFrameService] startImageStream failed: $e');
      }
    } else {
      _isStreaming = false;
      try {
        await controller?.stopImageStream();
      } catch (_) {}
    }
  }

  void _onCameraImage(CameraImage image) {
    if (_disposed || !_isStreaming) return;

    // Cache latest frame for AI capture
    _latestFrame = image;

    // Cap the push cadence at ~16 fps regardless of the actual camera rate
    // (the encoder runs at 15 fps; a device that ignores the fps cap must
    // not double the copy work).
    // The replay ring takes every camera frame (the session cap is 15 fps);
    // its tee runs first so the transport push below can reuse its staging
    // copy on the frames both consume.
    _replayStagedFrame = null;
    if (_replayMode) _pushFrameToReplay(image);
    final now = DateTime.now();
    final pushInterval = _p2pMode && !RtcFramesService.sendActive
        ? _gatedPushInterval
        : _minPushInterval;
    if (_lastPushAt != null &&
        now.difference(_lastPushAt!) < pushInterval) {
      return;
    }
    _lastPushAt = now;

    if (_p2pMode) _pushFrameToP2p(image);
  }

  /// Replay ring tee — third consumer of the same frames. Own staging buffer:
  /// the pooled buffer belongs to the transport push, and the method channel
  /// serializes synchronously, so this buffer is reusable as soon as the call
  /// returns.
  void _pushFrameToReplay(CameraImage image) {
    // The service only consumes frames of MY turn (and drops when the channel
    // is behind) — bail before the staging copy, not after.
    if (!ReplayBufferService.wantsFrame) return;
    try {
      if (Platform.isAndroid) {
        final ySize = image.width * image.height;
        final uvSize = (image.width ~/ 2) * (image.height ~/ 2);
        final needed = ySize + uvSize * 2;
        var buffer = _replayBuffer;
        if (buffer == null || buffer.length < needed) {
          buffer = Uint8List(needed);
          _replayBuffer = buffer;
        }
        final format = _fillTightYuv(image, buffer);
        _replayStagedFrame = image;
        _replayStagedFormat = format;
        ReplayBufferService.pushFrame(
          buffer,
          image.width,
          image.height,
          // Calibration-derived hint when available — the sensor guess is
          // wrong on rotation-locked mounted phones (see reportBoardTilt).
          _calibrationUprightRotation ?? _effectiveRotation(),
          format: format,
        );
      } else {
        final plane = image.planes[0];
        ReplayBufferService.pushFrame(
          plane.bytes,
          image.width,
          image.height,
          0,
          format: 'bgra',
          bytesPerRow: plane.bytesPerRow,
        );
      }
    } catch (e) {
      debugPrint('[CameraFrameService] replay pushFrame error: $e');
    }
  }

  /// Send the frame to the RtcFrames native companion (WebRTC video source).
  /// The method channel serializes the bytes synchronously during pushFrame,
  /// so the pooled buffer is reusable as soon as the call returns;
  /// back-pressure (drop when the platform side is behind) lives in
  /// RtcFramesService.
  void _pushFrameToP2p(CameraImage image) {
    // No turn-gate bail here: the gate lives in _onCameraImage's cadence
    // switch (full rate on my turn, ~1 fps trickle on the opponent's — the
    // peer's stall watchdog needs SOME frames to keep flowing).
    if (!RtcFramesService.hasTrack) return;
    try {
      if (Platform.isAndroid) {
        final Uint8List buffer;
        final String format;
        if (identical(_replayStagedFrame, image)) {
          // The replay tee already tight-copied this exact frame — both
          // channel sends serialize synchronously, so one staging copy
          // serves the two of them.
          buffer = _replayBuffer!;
          format = _replayStagedFormat!;
        } else {
          final ySize = image.width * image.height;
          final uvSize = (image.width ~/ 2) * (image.height ~/ 2);
          buffer = _pushBuffer(ySize + uvSize * 2);
          format = _fillTightYuv(image, buffer);
        }
        final rotation = _effectiveRotation();
        if (!_firstPushLogged) {
          _firstPushLogged = true;
          debugPrint('[CameraFrameService] first P2P push: '
              '${image.width}x${image.height} format=$format rotation=$rotation');
        }
        RtcFramesService.pushFrame(
          buffer,
          image.width,
          image.height,
          rotation,
          format: format,
        );
      } else {
        // iOS: BGRA8888, frames already upright in every orientation →
        // rotation 0. The raw plane bytes go
        // straight through (single copy inside the method-channel codec);
        // the native side strips any row padding via bytesPerRow.
        final plane = image.planes[0];
        if (!_firstPushLogged) {
          _firstPushLogged = true;
          debugPrint('[CameraFrameService] first P2P push: '
              '${image.width}x${image.height} format=bgra '
              'bytesPerRow=${plane.bytesPerRow}');
        }
        RtcFramesService.pushFrame(
          plane.bytes,
          image.width,
          image.height,
          0,
          format: 'bgra',
          bytesPerRow: plane.bytesPerRow,
        );
      }
    } catch (e) {
      debugPrint('[CameraFrameService] p2p pushFrame error: $e');
    }
  }

  /// Return the pooled push buffer, reallocating only when the frame size
  /// changed (camera resolution is fixed within a session).
  Uint8List _pushBuffer(int length) {
    var buf = _pushBufferSlot;
    if (buf == null || buf.length != length) {
      buf = Uint8List(length);
      _pushBufferSlot = buf;
    }
    return buf;
  }

  /// Tight-copy [image]'s YUV planes into [buffer] and return the format tag
  /// ('i420' | 'nv21') every native consumer expects. Single home for the
  /// pixelStride dispatch (DartsMind's YUVHelper heuristic: 1 → planar I420,
  /// 2 → interleaved NV21) shared by the replay tee and both transport
  /// pushes — it used to be copy-pasted at each call site.
  String _fillTightYuv(CameraImage image, Uint8List buffer) {
    final uvPixelStride = image.planes[1].bytesPerPixel ?? 1;
    if (uvPixelStride == 1) {
      _fillI420Buffer(image, buffer);
      return 'i420';
    }
    _fillNv21Buffer(image, buffer);
    return 'nv21';
  }

  /// Fill [buffer] with planar I420 (Y + U + V), padding removed.
  /// Used when pixelStride == 1 (true planar YUV420). [buffer] comes from the
  /// push pool and is already sized ySize + 2*uvSize.
  void _fillI420Buffer(CameraImage image, Uint8List buffer) {
    final w = image.width;
    final h = image.height;
    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];

    final ySize = w * h;
    final uvSize = (w ~/ 2) * (h ~/ 2);

    // Copy Y plane, removing row padding
    final yRowStride = yPlane.bytesPerRow;
    if (yRowStride == w) {
      buffer.setRange(0, ySize, yPlane.bytes);
    } else {
      for (int row = 0; row < h; row++) {
        buffer.setRange(row * w, row * w + w, yPlane.bytes, row * yRowStride);
      }
    }

    // Copy U plane, removing row padding
    final uvRowStride = uPlane.bytesPerRow;
    final uvW = w ~/ 2;
    final uvH = h ~/ 2;
    if (uvRowStride == uvW) {
      buffer.setRange(ySize, ySize + uvSize, uPlane.bytes);
    } else {
      for (int row = 0; row < uvH; row++) {
        buffer.setRange(ySize + row * uvW, ySize + row * uvW + uvW, uPlane.bytes, row * uvRowStride);
      }
    }

    // Copy V plane, removing row padding
    if (uvRowStride == uvW) {
      buffer.setRange(ySize + uvSize, ySize + uvSize * 2, vPlane.bytes);
    } else {
      for (int row = 0; row < uvH; row++) {
        buffer.setRange(ySize + uvSize + row * uvW, ySize + uvSize + row * uvW + uvW, vPlane.bytes, row * uvRowStride);
      }
    }
  }

  /// Fill [buffer] with NV21 (Y plane + interleaved VU) from interleaved UV
  /// planes. Used when pixelStride == 2 (NV21/NV12 from Android camera).
  /// DartsMind's YUVHelper handles this case explicitly.
  void _fillNv21Buffer(CameraImage image, Uint8List buffer) {
    final w = image.width;
    final h = image.height;
    final yPlane = image.planes[0];
    final vPlane = image.planes[2]; // V plane — in NV21, VU pairs are interleaved

    final ySize = w * h;
    // NV21: Y plane followed by interleaved V,U pairs
    final vuSize = (w ~/ 2) * (h ~/ 2) * 2;

    // Copy Y plane
    final yRowStride = yPlane.bytesPerRow;
    if (yRowStride == w) {
      buffer.setRange(0, ySize, yPlane.bytes);
    } else {
      for (int row = 0; row < h; row++) {
        buffer.setRange(row * w, row * w + w, yPlane.bytes, row * yRowStride);
      }
    }

    // Copy interleaved VU data from the V plane (which contains V,U,V,U,... with pixelStride=2)
    // On Android with NV21, planes[2] (V) starts 1 byte before planes[1] (U) and they share the same buffer
    final vuRowStride = vPlane.bytesPerRow;
    final uvH = h ~/ 2;
    if (vuRowStride == w) {
      final copyLen = min(vuSize, vPlane.bytes.length);
      buffer.setRange(ySize, ySize + copyLen, vPlane.bytes);
      // A short V plane used to leave zeros here (fresh allocation); with a
      // pooled buffer, clear the tail explicitly so no stale chroma leaks in.
      if (copyLen < vuSize) buffer.fillRange(ySize + copyLen, ySize + vuSize, 0);
    } else {
      for (int row = 0; row < uvH; row++) {
        final rowBytes = min(w, vPlane.bytes.length - row * vuRowStride);
        if (rowBytes <= 0) {
          buffer.fillRange(ySize + row * w, ySize + vuSize, 0);
          break;
        }
        buffer.setRange(ySize + row * w, ySize + row * w + rowBytes, vPlane.bytes, row * vuRowStride);
        if (rowBytes < w) {
          buffer.fillRange(ySize + row * w + rowBytes, ySize + (row + 1) * w, 0);
        }
      }
    }
  }

  /// Capture the latest frame as a JPEG file for AI scoring.
  /// Returns the file path, or null if no frame is available.
  /// DartsMind applies rotation via Matrix.postRotate(rotationDegrees) before AI.
  Future<String?> captureFrame() async {
    final frame = _latestFrame;
    if (frame == null) return null;

    try {
      // Convert CameraImage to JPEG in an isolate to avoid blocking UI
      final jpegBytes = await compute(_convertCameraImageToJpeg, _CaptureData(
        planes: frame.planes.map((p) => _PlaneData(
          bytes: Uint8List.fromList(p.bytes),
          bytesPerRow: p.bytesPerRow,
          bytesPerPixel: p.bytesPerPixel,
          width: p.width,
          height: p.height,
        )).toList(),
        width: frame.width,
        height: frame.height,
        formatIndex: frame.format.group.index,
        // Android compensates for device orientation; iOS frames already arrive
        // upright, so it passes 0 — exactly as before the landscape change.
        sensorOrientation: Platform.isAndroid ? _effectiveRotation() : 0,
      ));

      if (jpegBytes == null) return null;

      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/cam_frame_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await File(path).writeAsBytes(jpegBytes);
      return path;
    } catch (e) {
      debugPrint('[CameraFrameService] captureFrame error: $e');
      return null;
    }
  }

  /// iOS-only: capture the latest frame as raw BGRA bytes (camera native format).
  /// Returns (bgraBytes, width, height) or null if unavailable / non-iOS.
  ///
  /// Skips the per-pixel BGRA→RGBA conversion that `captureRgba` does on the
  /// main isolate. The native plugin does the channel swap on its background
  /// queue (vDSP), so all the heavy work stays off the UI thread.
  (Uint8List, int, int)? captureBgra() {
    if (!Platform.isIOS) return null;
    final frame = _latestFrame;
    if (frame == null) return null;

    try {
      final bgra = frame.planes[0].bytes;
      final w = frame.width;
      final h = frame.height;
      final stride = frame.planes[0].bytesPerRow;

      // Zero-copy: row stride matches packed width.
      if (stride == w * 4) return (bgra, w, h);

      // Strip per-row padding only — single setRange per row, no per-pixel work.
      final tight = Uint8List(w * h * 4);
      final rowBytes = w * 4;
      for (int y = 0; y < h; y++) {
        tight.setRange(y * rowBytes, y * rowBytes + rowBytes, bgra, y * stride);
      }
      return (tight, w, h);
    } catch (e) {
      debugPrint('[CameraFrameService] captureBgra error: $e');
      return null;
    }
  }

  /// Capture the latest frame as raw RGBA pixels directly — no file I/O.
  /// Returns (rgbaBytes, width, height) or null if no frame is available.
  /// This is the fast path matching DartsMind: camera buffer → model directly.
  ///
  /// DartsMind rotates the bitmap using imageProxy.getImageInfo().getRotationDegrees()
  /// before sending to AI. We do the same here: on Android, the sensor is typically
  /// landscape (90° rotated), so we rotate to ensure the image is always portrait.
  (Uint8List, int, int)? captureRgba() {
    final frame = _latestFrame;
    if (frame == null) return null;

    try {
      if (Platform.isIOS) {
        // iOS: BGRA8888 — convert to RGBA in place
        final bgra = frame.planes[0].bytes;
        final w = frame.width;
        final h = frame.height;
        final stride = frame.planes[0].bytesPerRow;
        final rgba = Uint8List(w * h * 4);
        for (int y = 0; y < h; y++) {
          final srcRow = y * stride;
          final dstRow = y * w * 4;
          for (int x = 0; x < w; x++) {
            final si = srcRow + x * 4;
            final di = dstRow + x * 4;
            rgba[di] = bgra[si + 2];     // R <- B channel
            rgba[di + 1] = bgra[si + 1]; // G
            rgba[di + 2] = bgra[si];     // B <- R channel
            rgba[di + 3] = bgra[si + 3]; // A
          }
        }
        // iOS frames already arrive upright in every device orientation, so no
        // rotation is applied here — identical to the pre-landscape behaviour.
        return (rgba, w, h);
      } else {
        // Android: YUV420 — convert to RGBA
        final yPlane = frame.planes[0];
        final uPlane = frame.planes[1];
        final vPlane = frame.planes[2];
        final w = frame.width;
        final h = frame.height;
        final yRowStride = yPlane.bytesPerRow;
        final uvRowStride = uPlane.bytesPerRow;
        final uvPixelStride = uPlane.bytesPerPixel ?? 1;

        // Rotate so the board is upright for the model in any device
        // orientation (portrait OR landscape) — see _effectiveRotation.
        final rotation = _effectiveRotation();

        if (rotation == 90) {
          // Rotate 90° CW: (x, y) → (h-1-y, x), output is h×w
          final outW = h;
          final outH = w;
          final rgba = Uint8List(outW * outH * 4);
          for (int sy = 0; sy < h; sy++) {
            for (int sx = 0; sx < w; sx++) {
              final yVal = yPlane.bytes[sy * yRowStride + sx];
              final uvIdx = (sy ~/ 2) * uvRowStride + (sx ~/ 2) * uvPixelStride;
              final uVal = uPlane.bytes[uvIdx];
              final vVal = vPlane.bytes[uvIdx];
              // Destination after 90° CW rotation
              final dx = h - 1 - sy;
              final dy = sx;
              final di = (dy * outW + dx) * 4;
              rgba[di] = (yVal + 1.370705 * (vVal - 128)).clamp(0, 255).toInt();
              rgba[di + 1] = (yVal - 0.337633 * (uVal - 128) - 0.698001 * (vVal - 128)).clamp(0, 255).toInt();
              rgba[di + 2] = (yVal + 1.732446 * (uVal - 128)).clamp(0, 255).toInt();
              rgba[di + 3] = 255;
            }
          }
          return (rgba, outW, outH);
        } else if (rotation == 270) {
          // Rotate 270° CW (= 90° CCW): (x, y) → (y, w-1-x), output is h×w
          final outW = h;
          final outH = w;
          final rgba = Uint8List(outW * outH * 4);
          for (int sy = 0; sy < h; sy++) {
            for (int sx = 0; sx < w; sx++) {
              final yVal = yPlane.bytes[sy * yRowStride + sx];
              final uvIdx = (sy ~/ 2) * uvRowStride + (sx ~/ 2) * uvPixelStride;
              final uVal = uPlane.bytes[uvIdx];
              final vVal = vPlane.bytes[uvIdx];
              final dx = sy;
              final dy = w - 1 - sx;
              final di = (dy * outW + dx) * 4;
              rgba[di] = (yVal + 1.370705 * (vVal - 128)).clamp(0, 255).toInt();
              rgba[di + 1] = (yVal - 0.337633 * (uVal - 128) - 0.698001 * (vVal - 128)).clamp(0, 255).toInt();
              rgba[di + 2] = (yVal + 1.732446 * (uVal - 128)).clamp(0, 255).toInt();
              rgba[di + 3] = 255;
            }
          }
          return (rgba, outW, outH);
        } else {
          // 0 or 180 — no dimension swap needed
          final rgba = Uint8List(w * h * 4);
          for (int sy = 0; sy < h; sy++) {
            for (int sx = 0; sx < w; sx++) {
              final yVal = yPlane.bytes[sy * yRowStride + sx];
              final uvIdx = (sy ~/ 2) * uvRowStride + (sx ~/ 2) * uvPixelStride;
              final uVal = uPlane.bytes[uvIdx];
              final vVal = vPlane.bytes[uvIdx];
              final int dx, dy;
              if (rotation == 180) {
                dx = w - 1 - sx;
                dy = h - 1 - sy;
              } else {
                dx = sx;
                dy = sy;
              }
              final di = (dy * w + dx) * 4;
              rgba[di] = (yVal + 1.370705 * (vVal - 128)).clamp(0, 255).toInt();
              rgba[di + 1] = (yVal - 0.337633 * (uVal - 128) - 0.698001 * (vVal - 128)).clamp(0, 255).toInt();
              rgba[di + 2] = (yVal + 1.732446 * (uVal - 128)).clamp(0, 255).toInt();
              rgba[di + 3] = 255;
            }
          }
          return (rgba, w, h);
        }
      }
    } catch (e) {
      debugPrint('[CameraFrameService] captureRgba error: $e');
      return null;
    }
  }

  /// Capture the latest frame as raw YUV planes for native-side processing.
  /// Android only — returns (yPlane, uPlane, vPlane, width, height,
  /// yRowStride, uvRowStride, uvPixelStride, rotation) or null.
  /// This matches DartsMind's flow: raw camera data → native conversion.
  ({
    Uint8List yPlane,
    Uint8List uPlane,
    Uint8List vPlane,
    int width,
    int height,
    int yRowStride,
    int uvRowStride,
    int uvPixelStride,
    int rotation,
  })? captureYuvPlanes() {
    final frame = _latestFrame;
    if (frame == null || !Platform.isAndroid) return null;

    try {
      // Pass plane bytes directly — MethodChannel serialization copies them once
      // into a Kotlin ByteArray. The extra Uint8List.fromList() call used to
      // copy them a second time (~1.4MB/frame at 720p) for no benefit.
      return (
        yPlane: frame.planes[0].bytes,
        uPlane: frame.planes[1].bytes,
        vPlane: frame.planes[2].bytes,
        width: frame.width,
        height: frame.height,
        yRowStride: frame.planes[0].bytesPerRow,
        uvRowStride: frame.planes[1].bytesPerRow,
        uvPixelStride: frame.planes[1].bytesPerPixel ?? 1,
        rotation: _effectiveRotation(),
      );
    } catch (e) {
      debugPrint('[CameraFrameService] captureYuvPlanes error: $e');
      return null;
    }
  }

  // --- Zoom controls ---

  Future<double> getMinZoomLevel() async {
    if (_controller == null || !_controller!.value.isInitialized) return 1.0;
    return await _controller!.getMinZoomLevel();
  }

  Future<double> getMaxZoomLevel() async {
    if (_controller == null || !_controller!.value.isInitialized) return 1.0;
    return await _controller!.getMaxZoomLevel();
  }

  Future<void> setZoomLevel(double zoom) async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    await _controller!.setZoomLevel(zoom);
  }

  /// Pause the camera (e.g. when app goes to background).
  void pause() {
    _stopImageStream();
  }

  /// Whether an online call consumes our frames continuously — the opponent
  /// watches our live video even between turns, so the stream must never be
  /// gated on AI activity in these modes.
  bool get _callAttached => _p2pMode;

  /// Resume the camera (e.g. when app comes back to foreground).
  void resume() {
    if (_disposed) return;
    // Don't resurrect a stream that [setAiActive] deliberately stopped.
    if (_aiActive || _callAttached) _startImageStream();
  }

  /// Gate the image stream on AI activity — DartsMind never burns pixel work
  /// while detection is off, and neither should we. When the AI capture loop
  /// stops (score confirmation/edit, opponent's turn, AI disabled) and no
  /// call is attached, the image stream is stopped entirely: the
  /// per-frame YUV marshaling into Dart (~40MB/s of buffer copies at 720p/30)
  /// is the biggest CONSTANT cost of a match, running even when nothing
  /// consumes the frames. The camera preview widget is unaffected.
  ///
  /// In online matches (a P2P call attached) this is a stream no-op — the
  /// opponent watches our live video between turns — but the flag is still
  /// recorded so [resume] behaves consistently.
  void setAiActive(bool active) {
    _aiActive = active;
    if (_disposed) return;
    if (active) {
      // Always record the intent — gating on the CURRENT stream state would
      // drop this start when a stop is still queued, leaving the stream off.
      _startImageStream();
    } else if (!_callAttached) {
      _stopImageStream();
      _latestFrame = null;
    }
  }

  /// Release all resources.
  Future<void> dispose() async {
    _disposed = true;
    await _awaitStream(_stopImageStream());
    _latestFrame = null;

    await _controller?.dispose();
    _controller = null;
    // The P2P track itself is owned by the game screen (RtcFramesService) —
    // only stop feeding it here.
    _p2pMode = false;
    if (_replayMode) {
      _replayMode = false;
      // Stops the native encoder and deletes the ring; produced clips live
      // in their own directory and survive.
      ReplayBufferService.stop();
    }
  }
}

// --- Isolate-safe data classes for JPEG conversion ---

class _PlaneData {
  final Uint8List bytes;
  final int bytesPerRow;
  final int? bytesPerPixel;
  final int? width;
  final int? height;

  _PlaneData({
    required this.bytes,
    required this.bytesPerRow,
    required this.bytesPerPixel,
    required this.width,
    required this.height,
  });
}

class _CaptureData {
  final List<_PlaneData> planes;
  final int width;
  final int height;
  final int formatIndex;
  final int sensorOrientation;

  _CaptureData({
    required this.planes,
    required this.width,
    required this.height,
    required this.formatIndex,
    this.sensorOrientation = 0,
  });
}

/// Convert a camera frame to JPEG. Runs in a separate isolate.
/// DartsMind applies Matrix.postRotate(rotationDegrees) before AI processing.
Uint8List? _convertCameraImageToJpeg(_CaptureData data) {
  try {
    img.Image image;

    // ImageFormatGroup indices: 0=unknown, 1=yuv420, 2=bgra8888, 3=jpeg, 4=nv21
    if (data.formatIndex == 2) {
      // BGRA8888 (iOS)
      image = img.Image.fromBytes(
        width: data.width,
        height: data.height,
        bytes: data.planes[0].bytes.buffer,
        order: img.ChannelOrder.bgra,
      );
    } else if (data.formatIndex == 1 || data.formatIndex == 4) {
      // YUV420 (Android) or NV21
      image = _convertYuv420ToImage(data.planes, data.width, data.height);
    } else if (data.formatIndex == 3 && data.planes.isNotEmpty) {
      // JPEG — already encoded
      return data.planes[0].bytes;
    } else {
      return null;
    }

    // Apply rotation to ensure portrait orientation (like DartsMind's Matrix.postRotate)
    if (data.sensorOrientation == 90) {
      image = img.copyRotate(image, angle: 90);
    } else if (data.sensorOrientation == 180) {
      image = img.copyRotate(image, angle: 180);
    } else if (data.sensorOrientation == 270) {
      image = img.copyRotate(image, angle: 270);
    }

    return Uint8List.fromList(img.encodeJpg(image, quality: 85));
  } catch (e) {
    return null;
  }
}

img.Image _convertYuv420ToImage(List<_PlaneData> planes, int width, int height) {
  final yPlane = planes[0];
  final uPlane = planes[1];
  final vPlane = planes[2];

  final image = img.Image(width: width, height: height);

  final yRowStride = yPlane.bytesPerRow;
  final uvRowStride = uPlane.bytesPerRow;
  final uvPixelStride = uPlane.bytesPerPixel ?? 1;

  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final yIndex = y * yRowStride + x;
      final uvIndex = (y ~/ 2) * uvRowStride + (x ~/ 2) * uvPixelStride;

      final yVal = yPlane.bytes[yIndex];
      final uVal = uPlane.bytes[uvIndex];
      final vVal = vPlane.bytes[uvIndex];

      final r = (yVal + 1.370705 * (vVal - 128)).clamp(0, 255).toInt();
      final g = (yVal - 0.337633 * (uVal - 128) - 0.698001 * (vVal - 128))
          .clamp(0, 255)
          .toInt();
      final b = (yVal + 1.732446 * (uVal - 128)).clamp(0, 255).toInt();

      image.setPixelRgba(x, y, r, g, b, 255);
    }
  }

  return image;
}
