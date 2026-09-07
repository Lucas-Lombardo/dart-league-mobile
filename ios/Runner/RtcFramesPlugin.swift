import AVFoundation
import Flutter
import UIKit
import WebRTC

/// Native companion for the RTC v2 (P2P WebRTC) path.
///
/// The app owns the camera (CameraFrameService feeds the AI scorer), so the
/// WebRTC video track cannot use a WebRTC-managed capturer. This plugin
/// reaches into flutter_webrtc's singleton to create an RTCVideoSource-backed
/// track with a fixed id, registers it in the plugin's `localTracks` (exactly
/// like getUserMedia registers its camera track, LocalVideoTrack wrapper
/// included) so every Dart-side call (addTrack / replaceTrack / trackDispose)
/// resolves it, and exposes a `pushFrame` channel the camera service feeds
/// with the same BGRA buffers it feeds to the AI scorer.
///
/// Registered from AppDelegate on the `com.dartrivals/rtc_frames` channel —
/// same pattern as NativeInferencePlugin.
class RtcFramesPlugin: NSObject {
  static let trackId = "dartrivals-ext-cam"

  private var videoSource: RTCVideoSource?
  private var videoTrack: RTCVideoTrack?
  private var capturer: RTCVideoCapturer?
  // Reused staging buffer. Only ever touched on frameQueue: the queue is
  // serial, so the buffer is always fully consumed (toI420 copy) before the
  // next frame reuses it — a single one is safe.
  private var pixelBuffer: CVPixelBuffer?

  // The memcpy + libyuv toI420 of a ~1.5MB BGRA frame at ≤16fps is real CPU;
  // doing it on the platform thread competed with UI + every other channel
  // (and this codebase has an overheating history). Serial: preserves frame
  // order and the pixel-buffer reuse invariant. The FlutterResult is answered
  // only after the frame is consumed, so the Dart-side 2-in-flight cap keeps
  // acting as backpressure (excess frames drop client-side, nothing queues).
  private let frameQueue = DispatchQueue(label: "com.dartrivals.rtcframes", qos: .userInitiated)

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "create":
      create(result: result)
    case "pushFrame":
      pushFrame(call, result: result)
    case "dispose":
      disposeTrack(result: result)
    case "setAudioSessionProfile":
      setAudioSessionProfile(result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func create(result: @escaping FlutterResult) {
    guard let plugin = FlutterWebRTCPlugin.sharedSingleton() else {
      result(FlutterError(code: "no_plugin",
                          message: "flutter_webrtc plugin not registered",
                          details: nil))
      return
    }
    // The factory is created by the plugin's own 'initialize' method call;
    // the Dart side (RtcFramesService.createTrack) forces WebRTC.initialize()
    // before invoking us, so this should always be non-nil.
    guard let factory = plugin.peerConnectionFactory else {
      result(FlutterError(code: "no_factory",
                          message: "peerConnectionFactory not initialized",
                          details: nil))
      return
    }
    if videoTrack == nil {
      let source = factory.videoSource()
      let track = factory.videoTrack(with: source, trackId: RtcFramesPlugin.trackId)
      track.isEnabled = true
      videoSource = source
      videoTrack = track
      // RTCVideoSource is itself the RTCVideoCapturerDelegate; the capturer
      // instance only identifies the frame producer in the delegate call.
      capturer = RTCVideoCapturer(delegate: source)
    }
    plugin.localTracks?[RtcFramesPlugin.trackId] = LocalVideoTrack(track: videoTrack!)
    result(RtcFramesPlugin.trackId)
  }

  /// The board square to cut out of the frame before encoding, and the fixed
  /// size to scale it to (see OpponentVideoFraming on the Dart side). Parsed
  /// only when all six arguments are present and the square fits the frame;
  /// anything else means "stream the whole frame", never a partial crop.
  private struct Crop {
    let x: Int, y: Int, width: Int, height: Int, outWidth: Int, outHeight: Int
  }

  private func cropArgs(_ args: [String: Any], width: Int, height: Int) -> Crop? {
    guard let x = args["cropX"] as? Int,
          let y = args["cropY"] as? Int,
          let w = args["cropW"] as? Int,
          let h = args["cropH"] as? Int,
          let outW = args["outW"] as? Int,
          let outH = args["outH"] as? Int
    else { return nil }
    guard x >= 0, y >= 0, w > 0, h > 0, outW > 0, outH > 0,
          x + w <= width, y + h <= height
    else { return nil }
    return Crop(x: x, y: y, width: w, height: h, outWidth: outW, outHeight: outH)
  }

  /// args: bytes (BGRA), width, height, rotation (degrees), bytesPerRow
  /// (source row stride — camera buffers can be row-padded), and optionally
  /// cropX/cropY/cropW/cropH + outW/outH (board crop, see `cropArgs`).
  private func pushFrame(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let source = videoSource,
          let capturer = capturer,
          let args = call.arguments as? [String: Any],
          let bytes = args["bytes"] as? FlutterStandardTypedData,
          let width = args["width"] as? Int,
          let height = args["height"] as? Int,
          width > 0, height > 0
    else {
      result(nil)
      return
    }
    let rotation = (args["rotation"] as? Int) ?? 0
    let srcBytesPerRow = (args["bytesPerRow"] as? Int) ?? (width * 4)
    let crop = cropArgs(args, width: width, height: height)
    // `bytes.data` (immutable NSData) and source/capturer are captured by the
    // block, so a concurrent disposeTrack can't pull them out from under us.
    let data = bytes.data

    frameQueue.async { [weak self] in
      defer { DispatchQueue.main.async { result(nil) } }
      guard let self = self else { return }

      var pb: CVPixelBuffer?
      if let existing = self.pixelBuffer,
         CVPixelBufferGetWidth(existing) == width,
         CVPixelBufferGetHeight(existing) == height {
        pb = existing
      } else {
        CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                            kCVPixelFormatType_32BGRA, nil, &pb)
        self.pixelBuffer = pb
      }
      guard let pixelBuffer = pb else { return }

      CVPixelBufferLockBaseAddress(pixelBuffer, [])
      if let dst = CVPixelBufferGetBaseAddress(pixelBuffer) {
        let dstBytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let rowBytes = min(width * 4, min(srcBytesPerRow, dstBytesPerRow))
        data.withUnsafeBytes { (src: UnsafeRawBufferPointer) in
          guard let srcBase = src.baseAddress else { return }
          for row in 0..<height {
            let srcOff = row * srcBytesPerRow
            guard srcOff + rowBytes <= src.count else { break }
            memcpy(dst + row * dstBytesPerRow, srcBase + srcOff, rowBytes)
          }
        }
      }
      CVPixelBufferUnlockBaseAddress(pixelBuffer, [])

      // toI420 (libyuv) detaches the frame from our reused pixel buffer
      // before it crosses into the encoder, and hands the encoder its
      // preferred format regardless of hardware/software H264 path.
      // With a board crop, the same call also does the cut and the scale to
      // the fixed output size: RTCCVPixelBuffer's crop/adapt geometry is
      // applied by toI420 for BGRA sources (cropAndScaleTo, libyuv ARGBScale)
      // — so the encoder only ever sees outW×outH frames.
      let rtcBuffer: RTCCVPixelBuffer
      if let c = crop {
        rtcBuffer = RTCCVPixelBuffer(pixelBuffer: pixelBuffer,
                                     adaptedWidth: Int32(c.outWidth),
                                     adaptedHeight: Int32(c.outHeight),
                                     cropWidth: Int32(c.width),
                                     cropHeight: Int32(c.height),
                                     cropX: Int32(c.x),
                                     cropY: Int32(c.y))
      } else {
        rtcBuffer = RTCCVPixelBuffer(pixelBuffer: pixelBuffer)
      }
      let rtcRotation = RTCVideoRotation(rawValue: rotation) ?? ._0
      let timeNs = Int64(CACurrentMediaTime() * 1_000_000_000)
      let frame = RTCVideoFrame(buffer: rtcBuffer.toI420(),
                                rotation: rtcRotation,
                                timeStampNs: timeNs)
      source.capturer(capturer, didCapture: frame)
    }
  }

  /// Makes the match's loudspeaker profile WebRTC's OWN stored session
  /// configuration (`RTCAudioSessionConfiguration.webRTC()`), not just the
  /// live AVAudioSession state.
  ///
  /// WebRTC re-applies that stored configuration on its own whenever its
  /// audio unit (re)initializes — first when ICE connects and playout/record
  /// start, then after every interruption or route change (Bluetooth,
  /// headphones). The stock value is the phone-call profile: playAndRecord,
  /// `allowBluetooth` only, mode `voiceChat` — no `defaultToSpeaker`, so each
  /// re-apply moves the opponent's voice to the earpiece (useless with the
  /// phone propped up facing the board) and caps the level. flutter_webrtc's
  /// `setAppleAudioConfiguration` only touches the live session (it edits a
  /// COPY of this object), and its `setSpeakerphoneOn` reads `config.mode`
  /// from here — i.e. it forced voiceChat back on every call. Storing the
  /// profile makes both paths converge on: loudspeaker, videoChat (Apple's
  /// speakerphone profile — same voice-processing echo cancellation, full
  /// speaker level). Options mirror what setSpeakerphoneOn(true) applies so
  /// nothing flip-flops between the two. Idempotent; call before the first
  /// PeerConnection.
  private func setAudioSessionProfile(result: @escaping FlutterResult) {
    let config = RTCAudioSessionConfiguration.webRTC()
    config.category = AVAudioSession.Category.playAndRecord.rawValue
    config.categoryOptions = [
      .defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP, .allowAirPlay,
    ]
    config.mode = AVAudioSession.Mode.videoChat.rawValue
    RTCAudioSessionConfiguration.setWebRTC(config)
    result(nil)
  }

  private func disposeTrack(result: @escaping FlutterResult) {
    if let plugin = FlutterWebRTCPlugin.sharedSingleton() {
      plugin.localTracks?.removeObject(forKey: RtcFramesPlugin.trackId)
    }
    // Nil the ivars ON THE PLATFORM THREAD: a stale teardown block racing on
    // frameQueue must never undo a create() that ran meanwhile (the
    // deferred-dispose overlap), and main-thread reads of these ivars must
    // not race frameQueue writes. In-flight frame blocks captured
    // source/capturer locally and finish safely (ARC keeps them alive).
    videoTrack = nil
    videoSource = nil
    capturer = nil
    // Only pixelBuffer belongs to the frameQueue domain.
    frameQueue.async { [weak self] in
      self?.pixelBuffer = nil
      DispatchQueue.main.async { result(nil) }
    }
  }
}
