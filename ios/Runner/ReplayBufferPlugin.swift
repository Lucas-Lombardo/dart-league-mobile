import Flutter
import AVFoundation

/// Rolling replay buffer: encodes the camera frames the app already produces
/// (same BGRA buffers as the RTC push) into a ring of SELF-CONTAINED short MP4
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
  // 3s segments: capture bounds snap to segment edges, so the segment
  // length IS the worst-case clip preamble — 5s let a late dart-pull slip
  // into the clip head (2026-08-03 test).
  private static let segmentMs: Int64 = 3_000
  private static let ringSegments = 16
  private static let bitRate = 4_000_000

  // Match-proof retention — mirrors the Kotlin side: consecutive my-turn
  // segments are wall-clock contiguous, a wider gap is a turn boundary;
  // retained matches expire after the dispute window, capped in total size.
  private static let runGapMs: Int64 = 4_000
  private static let retentionTtlMs: Int64 = 48 * 60 * 60 * 1000
  private static let retentionCapBytes: Int64 = 2 * 1024 * 1024 * 1024

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

  // Match-proof retention: while non-nil, new segments land under
  // match_proof/<key>/, are never evicted, and each closed one appends a JSON
  // line to the dir's index.jsonl (crash-safe timeline for cutRuns).
  private var retainKey: String? = nil

  private var ringDir: URL {
    let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("replay_ring", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  private var retentionRoot: URL {
    let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("match_proof", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  private func retentionDir(_ key: String) -> URL {
    let safe = key.replacingOccurrences(
      of: "[^A-Za-z0-9_-]", with: "_", options: .regularExpression)
    let dir = retentionRoot.appendingPathComponent(safe, isDirectory: true)
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
    case "render":
      renderOverlay(call, result: result)
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
    case "beginRetention":
      let key = (call.arguments as? [String: Any])?["key"] as? String
      queue.async { [weak self] in
        if let self = self, let key = key {
          self.purgeRetention(keepKey: key)
          self.finishCurrentSegment()
          self.retainKey = key
        }
        DispatchQueue.main.async { result(nil) }
      }
    case "cutRuns":
      cutRuns(call, result: result)
    case "captureRetained":
      captureRetained(call, result: result)
    case "deleteRetention":
      let key = (call.arguments as? [String: Any])?["key"] as? String
      queue.async { [weak self] in
        if let self = self, let key = key {
          if self.retainKey == key { self.retainKey = nil }
          try? FileManager.default.removeItem(at: self.retentionDir(key))
        }
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
    let dir = retainKey.map { retentionDir($0) } ?? ringDir
    let url = dir.appendingPathComponent("seg_\(segmentIndex).mp4")
    segmentIndex += 1
    try? FileManager.default.removeItem(at: url)
    let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
    let settings: [String: Any] = [
      AVVideoCodecKey: AVVideoCodecType.h264,
      AVVideoWidthKey: width,
      AVVideoHeightKey: height,
      AVVideoCompressionPropertiesKey: [
        AVVideoAverageBitRateKey: Self.bitRate,
        // Must track the Dart side's camera fps
        // (CameraFrameService.cameraFps).
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
      // Matching strides (the common 720p case): one plane-sized memcpy
      // instead of `height` row copies.
      if bytesPerRow == dstStride && rowBytes == bytesPerRow {
        memcpy(dstBase, srcBase, min(bytes.count, height * dstStride))
        return
      }
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
    if let key = retainKey, url.deletingLastPathComponent() == retentionDir(key) {
      // Crash-safe index line, one per closed segment (see Kotlin mirror).
      let line = "{\"f\":\"\(url.lastPathComponent)\",\"s\":\(start),\"e\":\(end),\"r\":0}\n"
      let index = retentionDir(key).appendingPathComponent("index.jsonl")
      if let data = line.data(using: .utf8) {
        if let handle = try? FileHandle(forWritingTo: index) {
          handle.seekToEndOfFile()
          handle.write(data)
          try? handle.close()
        } else {
          try? data.write(to: index)
        }
      }
    } else {
      while segments.count > Self.ringSegments {
        let removed = segments.removeFirst()
        try? FileManager.default.removeItem(at: removed.url)
      }
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
    let startWallMs = picked[0].startWallMs
    if picked.allSatisfy({ $0.ready }) {
      compose(picked.map { $0.url }, startWallMs: startWallMs, result: result)
      return
    }
    if attempt >= 10 {
      // Compose what is ready rather than nothing.
      compose(
        picked.filter { $0.ready }.map { $0.url },
        startWallMs: startWallMs, result: result)
      return
    }
    queue.asyncAfter(deadline: .now() + 0.25) { [weak self] in
      self?.awaitSegmentsReady(fromMs: fromMs, toMs: toMs, attempt: attempt + 1, result: result)
    }
  }

  /// Passthrough concat — no decode, no re-encode. [outURL] overrides the
  /// default clips-dir destination (match-proof run clips live next to their
  /// retained segments); [completion], when given, replaces the FlutterResult
  /// delivery so cutRuns can chain sequential composes.
  private func compose(
    _ urls: [URL], startWallMs: Int64,
    outURL: URL? = nil,
    completion: ((_ path: String?, _ durationMs: Int64) -> Void)? = nil,
    result: FlutterResult? = nil
  ) {
    let finish: (String?, Int64) -> Void = { path, durationMs in
      if let completion = completion {
        completion(path, durationMs)
      } else if let result = result {
        DispatchQueue.main.async {
          result(
            path == nil
              ? nil
              : [
                "path": path!, "startWallMs": startWallMs,
                "durationMs": durationMs,
              ])
        }
      }
    }
    guard !urls.isEmpty else {
      finish(nil, 0)
      return
    }
    let composition = AVMutableComposition()
    guard let track = composition.addMutableTrack(
      withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
    else {
      finish(nil, 0)
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
      finish(nil, 0)
      return
    }
    // The composition cursor IS the clip's length — the concat is passthrough.
    let durationMs = Int64((CMTimeGetSeconds(cursor) * 1000).rounded())
    let out = outURL ?? clipsDir.appendingPathComponent("clip_\(nowMs()).mp4")
    try? FileManager.default.removeItem(at: out)
    export.outputURL = out
    export.outputFileType = .mp4
    export.exportAsynchronously {
      finish(export.status == .completed ? out.path : nil, durationMs)
    }
  }

  private func teardown(deleteRing: Bool) {
    finishCurrentSegment()
    if deleteRing {
      // Retained segments survive the stop — they are the match proof,
      // purged by TTL/cap or an explicit deleteRetention.
      let keep = retainKey.map { retentionDir($0) }
      for segment in segments
      where segment.url.deletingLastPathComponent() != keep {
        try? FileManager.default.removeItem(at: segment.url)
      }
      segments.removeAll()
      retainKey = nil
    }
  }

  /// Match-proof: one passthrough clip per my-turn run — see the Kotlin
  /// mirror for the contract. Reads index.jsonl so it survives a relaunch.
  private func cutRuns(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let key = (call.arguments as? [String: Any])?["key"] as? String else {
      result(nil)
      return
    }
    queue.async { [weak self] in
      guard let self = self else {
        DispatchQueue.main.async { result(nil) }
        return
      }
      if self.retainKey == key { self.finishCurrentSegment() }
      let dir = self.retentionDir(key)
      var retained: [(url: URL, start: Int64, end: Int64)] = []
      if let text = try? String(
        contentsOf: dir.appendingPathComponent("index.jsonl"), encoding: .utf8)
      {
        for line in text.split(separator: "\n") {
          guard let data = line.data(using: .utf8),
                let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                let name = obj["f"] as? String,
                let start = (obj["s"] as? NSNumber)?.int64Value,
                let end = (obj["e"] as? NSNumber)?.int64Value
          else { continue }
          let url = dir.appendingPathComponent(name)
          if FileManager.default.fileExists(atPath: url.path) {
            retained.append((url, start, end))
          }
        }
      }
      retained.sort { $0.start < $1.start }
      var runs: [[(url: URL, start: Int64, end: Int64)]] = []
      for segment in retained {
        if var last = runs.last, let tail = last.last,
           segment.start - tail.end <= Self.runGapMs
        {
          last.append(segment)
          runs[runs.count - 1] = last
        } else {
          runs.append([segment])
        }
      }
      let runsDir = dir.appendingPathComponent("clips", isDirectory: true)
      try? FileManager.default.createDirectory(
        at: runsDir, withIntermediateDirectories: true)
      var clips: [[String: Any]] = []
      // finishWriting on the last segment is asynchronous; composes chain
      // sequentially (one export at a time) and skip files with no track.
      func composeNext(_ index: Int) {
        if index >= runs.count {
          DispatchQueue.main.async { result(["clips": clips]) }
          return
        }
        let run = runs[index]
        let out = runsDir.appendingPathComponent("run_\(index).mp4")
        self.compose(
          run.map { $0.url }, startWallMs: run[0].start, outURL: out,
          completion: { path, durationMs in
            self.queue.async {
              if let path = path {
                clips.append([
                  "path": path,
                  "startWallMs": run[0].start,
                  "durationMs": durationMs,
                ])
              }
              composeNext(index + 1)
            }
          })
      }
      // Give the last writer's finishWriting a moment to land on disk.
      self.queue.asyncAfter(deadline: .now() + 0.3) { composeNext(0) }
    }
  }

  /// Like capture(), but over a RETAINED match instead of the live ring —
  /// for a turn-report flag arriving after the ring was stopped or after a
  /// relaunch. args: key, fromMs, toMs → {path, startWallMs, durationMs}?.
  private func captureRetained(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let key = args["key"] as? String,
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
      if self.retainKey == key { self.finishCurrentSegment() }
      let dir = self.retentionDir(key)
      var picked: [(url: URL, start: Int64, end: Int64)] = []
      if let text = try? String(
        contentsOf: dir.appendingPathComponent("index.jsonl"), encoding: .utf8)
      {
        for line in text.split(separator: "\n") {
          guard let data = line.data(using: .utf8),
                let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                let name = obj["f"] as? String,
                let start = (obj["s"] as? NSNumber)?.int64Value,
                let end = (obj["e"] as? NSNumber)?.int64Value
          else { continue }
          let url = dir.appendingPathComponent(name)
          if end >= fromMs && start <= toMs && FileManager.default.fileExists(atPath: url.path) {
            picked.append((url, start, end))
          }
        }
      }
      picked.sort { $0.start < $1.start }
      guard !picked.isEmpty else {
        DispatchQueue.main.async { result(nil) }
        return
      }
      // Small grace for the last writer's asynchronous finishWriting.
      self.queue.asyncAfter(deadline: .now() + 0.3) {
        self.compose(picked.map { $0.url }, startWallMs: picked[0].start, result: result)
      }
    }
  }

  /// Drop retained matches past the dispute window, then oldest-first past
  /// the total size cap. [keepKey] (the match being started) is never purged.
  private func purgeRetention(keepKey: String?) {
    let fm = FileManager.default
    guard let dirs = try? fm.contentsOfDirectory(
      at: retentionRoot, includingPropertiesForKeys: [.contentModificationDateKey],
      options: .skipsHiddenFiles)
    else { return }
    let keep = keepKey.map { retentionDir($0) }
    var entries: [(url: URL, modified: Date, size: Int64)] = []
    var totalBytes: Int64 = 0
    for dir in dirs {
      guard (try? dir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
      else { continue }
      let modified =
        (try? dir.resourceValues(forKeys: [.contentModificationDateKey]))?
          .contentModificationDate ?? .distantPast
      var size: Int64 = 0
      if let files = fm.enumerator(at: dir, includingPropertiesForKeys: [.fileSizeKey]) {
        for case let file as URL in files {
          size += Int64((try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
      }
      entries.append((dir, modified, size))
      totalBytes += size
    }
    let now = Date()
    for entry in entries.sorted(by: { $0.modified < $1.modified }) {
      if entry.url == keep { continue }
      let expired =
        now.timeIntervalSince(entry.modified) * 1000 > Double(Self.retentionTtlMs)
      let overCap = totalBytes > Self.retentionCapBytes
      if expired || overCap {
        totalBytes -= entry.size
        try? fm.removeItem(at: entry.url)
      }
    }
  }
}

// MARK: - Broadcast overlay burn-in
//
// Interprets the two timeline primitives (scoreboard, outro)
// with CoreAnimation layers composited by AVFoundation during a short
// re-encode — see replay_overlay_timeline.dart for the contract. Layout runs
// in a 720-wide design grid scaled to the render size; `isGeometryFlipped`
// gives the same top-left coordinates as the Android painter.
extension ReplayBufferPlugin {

  private var card: CGColor { UIColor(red: 0.063, green: 0.102, blue: 0.169, alpha: 0.95).cgColor }
  private var pill: CGColor { UIColor(red: 0.039, green: 0.063, blue: 0.110, alpha: 0.95).cgColor }
  private var bg: CGColor { UIColor(red: 0.047, green: 0.075, blue: 0.129, alpha: 1).cgColor }
  private var blue: CGColor { UIColor(red: 0.361, green: 0.643, blue: 0.902, alpha: 1).cgColor }
  private var pink: CGColor { UIColor(red: 0.863, green: 0.376, blue: 0.412, alpha: 1).cgColor }
  private var sky: CGColor { UIColor(red: 0.055, green: 0.647, blue: 0.914, alpha: 1).cgColor }
  private var muted: CGColor { UIColor(red: 0.561, green: 0.627, blue: 0.737, alpha: 1).cgColor }

  func renderOverlay(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let inPath = args["inPath"] as? String,
          let timelineJson = args["timeline"] as? String,
          let timelineData = timelineJson.data(using: .utf8),
          let timeline = (try? JSONSerialization.jsonObject(with: timelineData)) as? [String: Any]
    else {
      result(nil)
      return
    }
    // Own queue: a multi-second export must not stall the ring encoder.
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      self?.doRender(inPath: inPath, timeline: timeline, result: result)
    }
  }

  private func doRender(
    inPath: String, timeline: [String: Any], result: @escaping FlutterResult
  ) {
    // NSLog on purpose (visible from Console.app on a release/TestFlight
    // build): the render is the deferred pipeline's least observable stage.
    NSLog("ReplayBuffer: render start %@", inPath)
    let fail = { DispatchQueue.main.async { result(nil) } }
    let asset = AVURLAsset(url: URL(fileURLWithPath: inPath))
    guard let track = asset.tracks(withMediaType: .video).first else { return fail() }
    let composition = AVMutableComposition()
    guard let compTrack = composition.addMutableTrack(
      withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
    else { return fail() }
    do {
      try compTrack.insertTimeRange(
        CMTimeRange(start: .zero, duration: asset.duration), of: track, at: .zero)
    } catch { return fail() }

    let natural = track.naturalSize
    var transform = track.preferredTransform
    let displayRect = CGRect(origin: .zero, size: natural).applying(transform)
    let renderSize = CGSize(width: abs(displayRect.width), height: abs(displayRect.height))
    transform.tx -= displayRect.minX
    transform.ty -= displayRect.minY

    let videoComp = AVMutableVideoComposition()
    videoComp.renderSize = renderSize
    // Matches the ring's 15 fps capture cadence — a faster export would only
    // duplicate frames.
    videoComp.frameDuration = CMTime(value: 1, timescale: 15)
    let instruction = AVMutableVideoCompositionInstruction()
    instruction.timeRange = CMTimeRange(start: .zero, duration: composition.duration)
    let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compTrack)
    layerInstruction.setTransform(transform, at: .zero)
    instruction.layerInstructions = [layerInstruction]
    videoComp.instructions = [instruction]

    let parent = CALayer()
    parent.frame = CGRect(origin: .zero, size: renderSize)
    parent.isGeometryFlipped = true
    let videoLayer = CALayer()
    videoLayer.frame = parent.frame
    parent.addSublayer(videoLayer)
    let durationS = CMTimeGetSeconds(composition.duration)
    buildOverlayLayers(
      into: parent, timeline: timeline, size: renderSize, durationS: durationS)
    videoComp.animationTool = AVVideoCompositionCoreAnimationTool(
      postProcessingAsVideoLayer: videoLayer, in: parent)

    let out = clipsDir.appendingPathComponent("clip_\(nowMs())_brand.mp4")
    try? FileManager.default.removeItem(at: out)
    guard let export = AVAssetExportSession(
      asset: composition, presetName: AVAssetExportPresetHighestQuality)
    else { return fail() }
    export.outputURL = out
    export.outputFileType = .mp4
    export.videoComposition = videoComp
    export.exportAsynchronously {
      NSLog(
        "ReplayBuffer: render done status=%ld error=%@",
        export.status.rawValue, String(describing: export.error))
      DispatchQueue.main.async {
        result(export.status == .completed ? out.path : nil)
      }
    }
  }

  private func buildOverlayLayers(
    into parent: CALayer, timeline: [String: Any], size: CGSize, durationS: Double
  ) {
    // min: a landscape clip must scale from its HEIGHT — width-based scaling
    // blew the overlay up 2.7× there and buried the board. Portrait is
    // untouched (width is the min).
    let s = min(size.width, size.height) / 720.0
    let landscape = size.width > size.height

    // ── Scoreboard (slide in at 0.3s) — two facing cards under a centered
    // brand lockup: at feed-thumbnail size a pair of big centered numbers
    // still reads, which the old single-line lower third did not. Scores are
    // static (everything per-dart was cut 2026-08-03: unreliable impact
    // timing read worse than a still number). ──
    let me = timeline["me"] as? String ?? "YOU"
    let opp = timeline["opp"] as? String ?? ""
    let startScore = (timeline["startScore"] as? NSNumber)?.intValue ?? 0
    let oppScore = (timeline["oppScore"] as? NSNumber)?.intValue ?? 0
    let myLegs = (timeline["myLegs"] as? NSNumber)?.intValue ?? 0
    let oppLegs = (timeline["oppLegs"] as? NSNumber)?.intValue ?? 0
    let legsTarget = min(max((timeline["legsTarget"] as? NSNumber)?.intValue ?? 2, 1), 5)
    let shield = (timeline["logoPath"] as? String).flatMap {
      UIImage(contentsOfFile: $0)?.cgImage
    }
    let format = timeline["format"] as? String ?? "RANKED"

    // One animated group: the whole scoreboard slides in as a single block.
    let board = CALayer()
    board.frame = CGRect(origin: .zero, size: size)
    board.opacity = 0
    parent.addSublayer(board)

    if landscape {
      // Landscape: one compact TV-style lower third — the portrait pill +
      // facing cards stacked over the short axis covered the board.
      board.addSublayer(broadcastBar(
        size: size, s: s, format: format, shield: shield,
        me: me, opp: opp, myLegs: myLegs, oppLegs: oppLegs,
        legsTarget: legsTarget, myScore: startScore, oppScore: oppScore))
    } else {
      let cardH = 96 * s
      let cardW = (size.width - 32 * s - 14 * s) / 2
      let cardsTop = size.height - 84 * s - cardH

      board.addSublayer(brandPill(
        bottom: cardsTop - 10 * s, s: s, width: size.width,
        format: format, shield: shield))
      board.addSublayer(scoreCard(
        x: 16 * s, y: cardsTop, w: cardW, h: cardH, s: s, accent: blue,
        name: me, legs: myLegs, legsTarget: legsTarget, score: startScore, mine: true))
      board.addSublayer(scoreCard(
        x: 16 * s + cardW + 14 * s, y: cardsTop, w: cardW, h: cardH, s: s, accent: pink,
        name: opp, legs: oppLegs, legsTarget: legsTarget, score: oppScore, mine: false))
    }

    animate(board, key: "opacity", from: 0, to: 1, begin: 0.3, dur: 0.5)
    animate(board, key: "position.y", from: Double(board.position.y + 70 * s),
            to: Double(board.position.y), begin: 0.3, dur: 0.5)

    // ── Outro end card ──
    guard durationS > 2 else { return }
    let outroAt = durationS - 1.6
    let card = CALayer()
    card.frame = parent.frame
    card.backgroundColor = bg
    card.opacity = 0
    let cx = size.width / 2
    let cy = size.height * 0.42
    if let logoPath = timeline["logoPath"] as? String,
       let logo = UIImage(contentsOfFile: logoPath)?.cgImage {
      let h = 170 * s
      let w = h * CGFloat(logo.width) / CGFloat(logo.height)
      let logoLayer = CALayer()
      // No counter-flip: the geometry-flipped tree renders `contents`
      // correctly as-is (device-verified 2026-08-03 — the flip showed the
      // shield upside down).
      logoLayer.contents = logo
      logoLayer.frame = CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h)
      card.addSublayer(logoLayer)
    }
    card.addSublayer(textLayer(
      "DART RIVALS", x: 0, y: cy + 118 * s, w: size.width, size: 38 * s,
      color: UIColor.white.cgColor, align: .center))
    card.addSublayer(textLayer(
      timeline["handle"] as? String ?? "", x: 0, y: cy + 164 * s, w: size.width,
      size: 24 * s, color: sky, align: .center))
    parent.addSublayer(card)
    switchOpacity(card, to: 1, at: outroAt, dur: 0.35)
  }

  /// Shield + DART RIVALS + format, centered above the cards: the brand is
  /// on screen for the whole clip, not only on the 1.6s end card.
  private func brandPill(
    bottom: CGFloat, s: CGFloat, width: CGFloat, format: String, shield: CGImage?
  ) -> CALayer {
    let h = 46 * s
    let shieldH = 34 * s
    let shieldW = shield.map { shieldH * CGFloat($0.width) / CGFloat($0.height) } ?? 0
    let brandW = textWidth("DART RIVALS", size: 13 * s, tracking: 0.12)
    let formatW = textWidth(format, size: 11 * s, tracking: 0.08)
    let gap: CGFloat = shieldW > 0 ? 11 * s : 0
    let w = 36 * s + shieldW + gap + max(brandW, formatW)

    let layer = CALayer()
    layer.frame = CGRect(x: (width - w) / 2, y: bottom - h, width: w, height: h)
    layer.backgroundColor = pill
    layer.cornerRadius = h / 2
    layer.borderWidth = 1.5 * s
    layer.borderColor = UIColor.white.withAlphaComponent(0.14).cgColor

    var tx = 18 * s
    if let shield = shield {
      let shieldLayer = CALayer()
      shieldLayer.contents = shield
      shieldLayer.frame = CGRect(x: tx, y: (h - shieldH) / 2, width: shieldW, height: shieldH)
      layer.addSublayer(shieldLayer)
      tx += shieldW + gap
    }
    layer.addSublayer(textLayer(
      "DART RIVALS", x: tx, y: 8 * s, w: w - tx, size: 13 * s,
      color: UIColor.white.cgColor, align: .left, tracking: 0.12))
    layer.addSublayer(textLayer(
      format, x: tx, y: 25 * s, w: w - tx, size: 11 * s,
      color: muted, align: .left, tracking: 0.08))
    return layer
  }

  /// Landscape-only scoreboard: name · pips · score │ brand │ score · pips ·
  /// name in one bottom bar. Both sides get the width of the WIDER one, so
  /// the brand block sits exactly centered.
  private func broadcastBar(
    size: CGSize, s: CGFloat, format: String, shield: CGImage?,
    me: String, opp: String, myLegs: Int, oppLegs: Int, legsTarget: Int,
    myScore: Int, oppScore: Int
  ) -> CALayer {
    let h = 56 * s
    let pad = 17 * s
    let gap = 13 * s
    let accentW = 5 * s
    let nameCol = min(
      max(textWidth(me, size: 15 * s, tracking: 0.1),
          textWidth(opp, size: 15 * s, tracking: 0.1)),
      180 * s)
    let scoreCol = max(
      textWidth("\(myScore)", size: 34 * s, tracking: 0),
      textWidth("\(oppScore)", size: 34 * s, tracking: 0))
    let r = 4.5 * s
    let pipGap = 6 * s
    let pipsW = CGFloat(legsTarget) * 2 * r + CGFloat(legsTarget - 1) * pipGap
    let sideW = accentW + pad + nameCol + gap + pipsW + gap + scoreCol + pad
    let shieldH = 36 * s
    let shieldW = shield.map { shieldH * CGFloat($0.width) / CGFloat($0.height) } ?? 0
    let brandPad = 15 * s
    let brandGap: CGFloat = shieldW > 0 ? 11 * s : 0
    let brandTextW = max(
      textWidth("DART RIVALS", size: 13 * s, tracking: 0.12),
      textWidth(format, size: 11 * s, tracking: 0.08))
    let brandW = brandPad + shieldW + brandGap + brandTextW + brandPad
    let w = 2 * sideW + brandW

    let bar = CALayer()
    bar.frame = CGRect(
      x: (size.width - w) / 2, y: size.height - 17 * s - h, width: w, height: h)
    bar.backgroundColor = pill
    bar.cornerRadius = 9 * s
    bar.borderWidth = 1.5 * s
    bar.borderColor = UIColor.white.withAlphaComponent(0.14).cgColor
    bar.masksToBounds = true

    func rect(_ frame: CGRect, _ color: CGColor) {
      let layer = CALayer()
      layer.frame = frame
      layer.backgroundColor = color
      bar.addSublayer(layer)
    }
    // Player accents on the outer edges, brand block delimited in the middle.
    rect(CGRect(x: 0, y: 0, width: accentW, height: h), blue)
    rect(CGRect(x: w - accentW, y: 0, width: accentW, height: h), pink)
    rect(
      CGRect(x: sideW, y: 0, width: brandW, height: h),
      UIColor.white.withAlphaComponent(0.045).cgColor)
    let sep = UIColor.white.withAlphaComponent(0.10).cgColor
    rect(CGRect(x: sideW, y: 0, width: 1 * s, height: h), sep)
    rect(CGRect(x: sideW + brandW - 1 * s, y: 0, width: 1 * s, height: h), sep)

    var bx = sideW + brandPad
    if let shield = shield {
      let shieldLayer = CALayer()
      shieldLayer.contents = shield
      shieldLayer.frame = CGRect(
        x: bx, y: (h - shieldH) / 2, width: shieldW, height: shieldH)
      bar.addSublayer(shieldLayer)
      bx += shieldW + brandGap
    }
    bar.addSublayer(textLayer(
      "DART RIVALS", x: bx, y: 13 * s, w: brandTextW + 2 * s, size: 13 * s,
      color: UIColor.white.cgColor, align: .left, tracking: 0.12))
    bar.addSublayer(textLayer(
      format, x: bx, y: 30 * s, w: brandTextW + 2 * s, size: 11 * s,
      color: muted, align: .left, tracking: 0.08))

    func side(x0: CGFloat, accent: CGColor, name: String, legs: Int, score: Int,
              mine: Bool, mirrored: Bool) {
      let nameX: CGFloat, pipsX: CGFloat, scoreX: CGFloat
      if mirrored {
        scoreX = x0 + pad
        pipsX = scoreX + scoreCol + gap
        nameX = pipsX + pipsW + gap
      } else {
        nameX = x0 + pad
        pipsX = nameX + nameCol + gap
        scoreX = pipsX + pipsW + gap
      }
      bar.addSublayer(textLayer(
        name, x: nameX, y: 17 * s, w: nameCol, size: 15 * s,
        color: mine
          ? UIColor(red: 0.894, green: 0.929, blue: 0.980, alpha: 1).cgColor : muted,
        align: .center, tracking: 0.1))
      bar.addSublayer(textLayer(
        "\(score)", x: scoreX, y: 4 * s, w: scoreCol, size: 34 * s,
        color: mine
          ? UIColor.white.cgColor
          : UIColor(red: 0.725, green: 0.776, blue: 0.855, alpha: 1).cgColor,
        align: .center))
      var px = pipsX
      for i in 0..<legsTarget {
        let pip = CALayer()
        pip.frame = CGRect(x: px, y: h / 2 - r, width: 2 * r, height: 2 * r)
        pip.cornerRadius = r
        pip.backgroundColor = i < legs
          ? accent : UIColor.white.withAlphaComponent(0.18).cgColor
        bar.addSublayer(pip)
        px += 2 * r + pipGap
      }
    }
    side(x0: accentW, accent: blue, name: me, legs: myLegs, score: myScore,
         mine: true, mirrored: false)
    side(x0: sideW + brandW, accent: pink, name: opp, legs: oppLegs,
         score: oppScore, mine: false, mirrored: true)
    return bar
  }

  private func scoreCard(
    x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, s: CGFloat, accent: CGColor,
    name: String, legs: Int, legsTarget: Int, score: Int, mine: Bool
  ) -> CALayer {
    let layer = CALayer()
    layer.frame = CGRect(x: x, y: y, width: w, height: h)
    layer.backgroundColor = card
    layer.cornerRadius = 14 * s
    layer.masksToBounds = true

    let accentBar = CALayer()
    accentBar.frame = CGRect(x: 0, y: 0, width: w, height: 4 * s)
    accentBar.backgroundColor = accent
    layer.addSublayer(accentBar)

    layer.addSublayer(textLayer(
      name, x: 10 * s, y: 11 * s, w: w - 20 * s, size: 14 * s,
      color: mine
        ? UIColor(red: 0.894, green: 0.929, blue: 0.980, alpha: 1).cgColor : muted,
      align: .center, tracking: 0.1))
    layer.addSublayer(textLayer(
      "\(score)", x: 0, y: 34 * s, w: w, size: 40 * s,
      color: mine
        ? UIColor.white.cgColor
        : UIColor(red: 0.725, green: 0.776, blue: 0.855, alpha: 1).cgColor,
      align: .center))

    // Legs as pips: in a BO3 "one leg left to take" reads without counting.
    let r = 4.5 * s
    let pipGap = 6 * s
    let total = CGFloat(legsTarget) * 2 * r + CGFloat(legsTarget - 1) * pipGap
    var px = (w - total) / 2
    for i in 0..<legsTarget {
      let pip = CALayer()
      pip.frame = CGRect(x: px, y: 86 * s - r, width: 2 * r, height: 2 * r)
      pip.cornerRadius = r
      pip.backgroundColor = i < legs
        ? accent : UIColor.white.withAlphaComponent(0.18).cgColor
      layer.addSublayer(pip)
      px += 2 * r + pipGap
    }
    return layer
  }

  private func textWidth(_ string: String, size: CGFloat, tracking: CGFloat) -> CGFloat {
    var attrs: [NSAttributedString.Key: Any] =
      [.font: UIFont.systemFont(ofSize: size, weight: .heavy)]
    if tracking > 0 { attrs[.kern] = size * tracking }
    return (string as NSString).size(withAttributes: attrs).width
  }

  /// `tracking` mirrors the Android painter's letterSpacing (in ems);
  /// CATextLayer only honours it through an attributed string.
  private func textLayer(
    _ string: String, x: CGFloat, y: CGFloat, w: CGFloat,
    size: CGFloat, color: CGColor, align: CATextLayerAlignmentMode,
    tracking: CGFloat = 0
  ) -> CATextLayer {
    let layer = CATextLayer()
    let font = UIFont.systemFont(ofSize: size, weight: .heavy)
    if tracking > 0 {
      let paragraph = NSMutableParagraphStyle()
      paragraph.alignment = align == .center ? .center : (align == .right ? .right : .left)
      paragraph.lineBreakMode = .byTruncatingTail
      layer.string = NSAttributedString(string: string, attributes: [
        .font: font,
        .foregroundColor: UIColor(cgColor: color),
        .kern: size * tracking,
        .paragraphStyle: paragraph,
      ])
    } else {
      layer.string = string
    }
    layer.font = font
    layer.fontSize = size
    layer.foregroundColor = color
    layer.alignmentMode = align
    layer.frame = CGRect(x: x, y: y, width: w, height: size * 1.4)
    layer.contentsScale = 2
    layer.truncationMode = .end
    return layer
  }

  private func switchOpacity(
    _ layer: CALayer, to: Float, at: Double, dur: Double = 0.01
  ) {
    animate(layer, key: "opacity", from: Double(1 - to), to: Double(to), begin: at, dur: dur)
  }

  private func animate(
    _ layer: CALayer, key: String, from: Double, to: Double, begin: Double, dur: Double
  ) {
    let anim = CABasicAnimation(keyPath: key)
    anim.fromValue = from
    anim.toValue = to
    anim.beginTime = AVCoreAnimationBeginTimeAtZero + begin
    anim.duration = max(dur, 0.01)
    anim.fillMode = .both
    anim.isRemovedOnCompletion = false
    anim.timingFunction = CAMediaTimingFunction(name: .easeOut)
    layer.add(anim, forKey: "\(key)-\(begin)")
  }
}
