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
/// with the same BGRA buffers it pushes to Agora.
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

  /// args: bytes (BGRA), width, height, rotation (degrees), bytesPerRow
  /// (source row stride — camera buffers can be row-padded).
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
      let rtcBuffer = RTCCVPixelBuffer(pixelBuffer: pixelBuffer)
      let rtcRotation = RTCVideoRotation(rawValue: rotation) ?? ._0
      let timeNs = Int64(CACurrentMediaTime() * 1_000_000_000)
      let frame = RTCVideoFrame(buffer: rtcBuffer.toI420(),
                                rotation: rtcRotation,
                                timeStampNs: timeNs)
      source.capturer(capturer, didCapture: frame)
    }
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
