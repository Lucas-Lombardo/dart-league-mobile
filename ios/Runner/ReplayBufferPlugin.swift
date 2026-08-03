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
        AVVideoExpectedSourceFrameRateKey: 30,
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

  /// Passthrough concat — no decode, no re-encode.
  private func compose(
    _ urls: [URL], startWallMs: Int64, result: @escaping FlutterResult
  ) {
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
        result(
          export.status == .completed
            ? ["path": out.path, "startWallMs": startWallMs] : nil)
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

// MARK: - Broadcast overlay burn-in
//
// Interprets the three timeline primitives (scoreboard, banner, outro)
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
  private var gold: CGColor { UIColor(red: 0.918, green: 0.702, blue: 0.031, alpha: 1).cgColor }
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
    videoComp.frameDuration = CMTime(value: 1, timescale: 30)
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
      DispatchQueue.main.async {
        result(export.status == .completed ? out.path : nil)
      }
    }
  }

  private func buildOverlayLayers(
    into parent: CALayer, timeline: [String: Any], size: CGSize, durationS: Double
  ) {
    let s = size.width / 720.0

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

    let cardH = 96 * s
    let cardW = (size.width - 32 * s - 14 * s) / 2
    let cardsTop = size.height - 84 * s - cardH

    // One animated group: the whole scoreboard slides in as a single block.
    let board = CALayer()
    board.frame = CGRect(origin: .zero, size: size)
    board.opacity = 0
    parent.addSublayer(board)

    board.addSublayer(brandPill(
      bottom: cardsTop - 10 * s, s: s, width: size.width,
      format: timeline["format"] as? String ?? "RANKED", shield: shield))
    board.addSublayer(scoreCard(
      x: 16 * s, y: cardsTop, w: cardW, h: cardH, s: s, accent: blue,
      name: me, legs: myLegs, legsTarget: legsTarget, score: startScore, mine: true))
    board.addSublayer(scoreCard(
      x: 16 * s + cardW + 14 * s, y: cardsTop, w: cardW, h: cardH, s: s, accent: pink,
      name: opp, legs: oppLegs, legsTarget: legsTarget, score: oppScore, mine: false))

    animate(board, key: "opacity", from: 0, to: 1, begin: 0.3, dur: 0.5)
    animate(board, key: "position.y", from: Double(board.position.y + 70 * s),
            to: Double(board.position.y), begin: 0.3, dur: 0.5)

    // ── Banner ──
    if let banner = timeline["banner"] as? [String: Any],
       let bAt = (banner["atMs"] as? NSNumber).map({ $0.doubleValue / 1000.0 }) {
      let band = CALayer()
      band.frame = CGRect(
        x: 0, y: size.height * 0.42 - 65 * s, width: size.width, height: 130 * s)
      band.backgroundColor = gold
      band.opacity = 0
      band.addSublayer(textLayer(
        banner["text"] as? String ?? "", x: 0, y: 18 * s, w: size.width,
        size: 76 * s,
        color: UIColor(red: 0.102, green: 0.086, blue: 0.031, alpha: 1).cgColor,
        align: .center))
      parent.addSublayer(band)
      switchOpacity(band, to: 1, at: bAt, dur: 0.25)
      switchOpacity(band, to: 0, at: bAt + 1.95, dur: 0.25)
    }

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
