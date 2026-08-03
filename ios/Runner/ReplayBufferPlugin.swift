import Flutter
import AVFoundation

/// Rolling replay buffer: encodes the camera frames the app already produces
/// (same BGRA buffers as the RTC push) into a ring of SELF-CONTAINED 5s MP4
/// segments, and turns a wall-clock window into one clip by inserting the
/// matching segments into an AVMutableComposition exported PASSTHROUGH — no
/// re-encoding anywhere but the continuous hardware AVAssetWriter.
///
/// One AVAssetWriter per segment (a writer cannot split files): every segment
/// starts its own encoder session, so it opens on an IDR and plays standalone.
/// All state lives on the serial queue — the platform thread only relays.
///
/// Registered from AppDelegate on `com.dartrivals/replay_buffer` — same
/// pattern as RtcFramesPlugin.
class ReplayBufferPlugin: NSObject {
  private static let segmentMs: Int64 = 5_000
  private static let ringSegments = 12
  private static let bitRate = 3_000_000

  private let queue = DispatchQueue(label: "com.dartrivals.replay", qos: .utility)

  private struct Segment {
    let url: URL
    let startWallMs: Int64
    var endWallMs: Int64
    var ready: Bool
  }

  // Only touched on `queue`.
  private var segments: [Segment] = []
  private var writer: AVAssetWriter?
  private var input: AVAssetWriterInput?
  private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
  private var currentURL: URL?
  private var segmentStartWallMs: Int64 = 0
  private var lastFrameWallMs: Int64 = 0
  private var lastFramePts: Int64 = -1
  private var segmentIndex = 0

  private var ringDir: URL {
    let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("replay_ring", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  private var clipsDir: URL {
    let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("replay_clips", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  private func nowMs() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "pushFrame":
      pushFrame(call, result: result)
    case "capture":
      capture(call, result: result)
    case "pause":
      // Turn gate: the Dart side stops sending frames for the opponent's
      // turn; finalize the open segment so the ring only holds tidy my-turn
      // footage (the next pushFrame starts a fresh writer).
      queue.async { [weak self] in
        self?.finishCurrentSegment()
        DispatchQueue.main.async { result(nil) }
      }
    case "stop":
      queue.async { [weak self] in
        self?.teardown(deleteRing: true)
        DispatchQueue.main.async { result(nil) }
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// args: bytes (raw BGRA plane), width, height, bytesPerRow.
  private func pushFrame(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let data = args["bytes"] as? FlutterStandardTypedData,
          let width = args["width"] as? Int,
          let height = args["height"] as? Int,
          width > 0, height > 0
    else {
      result(nil)
      return
    }
    let bytesPerRow = args["bytesPerRow"] as? Int ?? width * 4
    queue.async { [weak self] in
      guard let self = self else {
        DispatchQueue.main.async { result(nil) }
        return
      }
      let now = self.nowMs()
      autoreleasepool {
        do {
          if self.writer == nil || now - self.segmentStartWallMs >= Self.segmentMs {
            self.finishCurrentSegment()
            try self.startSegment(width: width, height: height, now: now)
          }
          self.append(data.data, width: width, height: height, bytesPerRow: bytesPerRow, now: now)
        } catch {
          // A writer hiccup must never take the ring down for the match;
          // the next frame starts a fresh segment.
          NSLog("ReplayBuffer: pushFrame failed: \(error)")
          self.writer = nil
        }
      }
      // Answered after consumption: keeps the Dart 2-in-flight cap acting
      // as backpressure (same contract as RtcFramesPlugin).
      DispatchQueue.main.async { result(nil) }
    }
  }

  private func startSegment(width: Int, height: Int, now: Int64) throws {
    let url = ringDir.appendingPathComponent("seg_\(segmentIndex).mp4")
    segmentIndex += 1
    try? FileManager.default.removeItem(at: url)
    let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
    let settings: [String: Any] = [
      AVVideoCodecKey: AVVideoCodecType.h264,
      AVVideoWidthKey: width,
      AVVideoHeightKey: height,
      AVVideoCompressionPropertiesKey: [
        AVVideoAverageBitRateKey: Self.bitRate,
        AVVideoExpectedSourceFrameRateKey: 15,
      ],
    ]
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
    input.expectsMediaDataInRealTime = true
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
      assetWriterInput: input,
      sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: width,
        kCVPixelBufferHeightKey as String: height,
      ])
    writer.add(input)
    guard writer.startWriting() else { throw writer.error ?? NSError(domain: "replay", code: 1) }
    writer.startSession(atSourceTime: .zero)
    self.writer = writer
    self.input = input
    self.adaptor = adaptor
    self.currentURL = url
    self.segmentStartWallMs = now
    self.lastFramePts = -1
    self.lastFrameWallMs = now
  }

  private func append(_ bytes: Data, width: Int, height: Int, bytesPerRow: Int, now: Int64) {
    guard let input = input, let adaptor = adaptor, input.isReadyForMoreMediaData,
          let pool = adaptor.pixelBufferPool
    else { return } // encoder busy — dropping is the backpressure
    var pixelBuffer: CVPixelBuffer?
    guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer) == kCVReturnSuccess,
          let buffer = pixelBuffer
    else { return }
    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    guard let dstBase = CVPixelBufferGetBaseAddress(buffer) else { return }
    let dstStride = CVPixelBufferGetBytesPerRow(buffer)
    let rowBytes = min(width * 4, min(bytesPerRow, dstStride))
    bytes.withUnsafeBytes { (src: UnsafeRawBufferPointer) in
      guard let srcBase = src.baseAddress else { return }
      for row in 0..<height {
        let srcOffset = row * bytesPerRow
        guard srcOffset + rowBytes <= bytes.count else { break }
        memcpy(dstBase + row * dstStride, srcBase + srcOffset, rowBytes)
      }
    }
    // Wall-clock-derived pts (ms timescale) so a wall-clock capture window
    // maps straight onto segment times; strictly increasing for the writer.
    var pts = now - segmentStartWallMs
    if pts <= lastFramePts { pts = lastFramePts + 1 }
    lastFramePts = pts
    adaptor.append(buffer, withPresentationTime: CMTime(value: pts, timescale: 1000))
    lastFrameWallMs = now
  }

  private func finishCurrentSegment() {
    guard let writer = writer, let input = input, let url = currentURL else { return }
    let start = segmentStartWallMs
    let end = lastFrameWallMs
    self.writer = nil
    self.input = nil
    self.adaptor = nil
    self.currentURL = nil
    guard lastFramePts >= 0 else {
      writer.cancelWriting()
      try? FileManager.default.removeItem(at: url)
      return
    }
    segments.append(Segment(url: url, startWallMs: start, endWallMs: end, ready: false))
    while segments.count > Self.ringSegments {
      let removed = segments.removeFirst()
      try? FileManager.default.removeItem(at: removed.url)
    }
    input.markAsFinished()
    writer.finishWriting { [weak self] in
      self?.queue.async {
        guard let self = self else { return }
        if let i = self.segments.firstIndex(where: { $0.url == url }) {
          self.segments[i].ready = true
        }
      }
    }
  }

  /// args: fromMs, toMs (epoch millis) → clip path, or nil.
  private func capture(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let fromMs = (args["fromMs"] as? NSNumber)?.int64Value,
          let toMs = (args["toMs"] as? NSNumber)?.int64Value
    else {
      result(nil)
      return
    }
    queue.async { [weak self] in
      guard let self = self else {
        DispatchQueue.main.async { result(nil) }
        return
      }
      // Include the tail: close the open segment now; the next pushFrame
      // starts a fresh one.
      self.finishCurrentSegment()
      self.awaitSegmentsReady(fromMs: fromMs, toMs: toMs, attempt: 0, result: result)
    }
  }

  /// finishWriting is asynchronous — poll (bounded) until every involved
  /// segment is fully on disk before composing.
  private func awaitSegmentsReady(
    fromMs: Int64, toMs: Int64, attempt: Int, result: @escaping FlutterResult
  ) {
    let picked = segments.filter { $0.endWallMs >= fromMs && $0.startWallMs <= toMs }
    if picked.isEmpty {
      DispatchQueue.main.async { result(nil) }
      return
    }
    if picked.allSatisfy({ $0.ready }) {
      compose(picked.map { $0.url }, result: result)
      return
    }
    if attempt >= 10 {
      // Compose what is ready rather than nothing.
      compose(picked.filter { $0.ready }.map { $0.url }, result: result)
      return
    }
    queue.asyncAfter(deadline: .now() + 0.25) { [weak self] in
      self?.awaitSegmentsReady(fromMs: fromMs, toMs: toMs, attempt: attempt + 1, result: result)
    }
  }

  /// Passthrough concat — no decode, no re-encode.
  private func compose(_ urls: [URL], result: @escaping FlutterResult) {
    guard !urls.isEmpty else {
      DispatchQueue.main.async { result(nil) }
      return
    }
    let composition = AVMutableComposition()
    guard let track = composition.addMutableTrack(
      withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
    else {
      DispatchQueue.main.async { result(nil) }
      return
    }
    var cursor = CMTime.zero
    for url in urls {
      let asset = AVURLAsset(url: url)
      guard let source = asset.tracks(withMediaType: .video).first else { continue }
      track.preferredTransform = source.preferredTransform
      do {
        try track.insertTimeRange(
          CMTimeRange(start: .zero, duration: asset.duration), of: source, at: cursor)
        cursor = CMTimeAdd(cursor, asset.duration)
      } catch {
        NSLog("ReplayBuffer: insert failed: \(error)")
      }
    }
    guard cursor > .zero,
          let export = AVAssetExportSession(
            asset: composition, presetName: AVAssetExportPresetPassthrough)
    else {
      DispatchQueue.main.async { result(nil) }
      return
    }
    let out = clipsDir.appendingPathComponent("clip_\(nowMs()).mp4")
    try? FileManager.default.removeItem(at: out)
    export.outputURL = out
    export.outputFileType = .mp4
    export.exportAsynchronously {
      DispatchQueue.main.async {
        result(export.status == .completed ? out.path : nil)
      }
    }
  }

  private func teardown(deleteRing: Bool) {
    finishCurrentSegment()
    if deleteRing {
      for segment in segments {
        try? FileManager.default.removeItem(at: segment.url)
      }
      segments.removeAll()
    }
  }
}
