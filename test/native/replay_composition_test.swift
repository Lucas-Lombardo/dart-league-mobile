import AVFoundation

@main
enum ReplayCompositionTests {
  static func segment(_ url: URL, width: Int, height: Int,
                      transform: CGAffineTransform = .identity) throws {
    let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
      AVVideoCodecKey: AVVideoCodecType.h264,
      AVVideoWidthKey: width, AVVideoHeightKey: height,
    ])
    input.transform = transform
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
      sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: width,
        kCVPixelBufferHeightKey as String: height,
      ])
    writer.add(input)
    precondition(writer.startWriting(), "\(String(describing: writer.error))")
    writer.startSession(atSourceTime: .zero)
    var buffer: CVPixelBuffer?
    precondition(CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
      == kCVReturnSuccess)
    CVPixelBufferLockBaseAddress(buffer!, [])
    memset(CVPixelBufferGetBaseAddress(buffer!)!, 0x80,
           CVPixelBufferGetBytesPerRow(buffer!) * height)
    CVPixelBufferUnlockBaseAddress(buffer!, [])
    for i in 0..<3 {
      let deadline = Date().addingTimeInterval(10)
      while !input.isReadyForMoreMediaData && Date() < deadline { usleep(1_000) }
      precondition(input.isReadyForMoreMediaData)
      precondition(adaptor.append(buffer!, withPresentationTime: CMTime(value: Int64(i), timescale: 15)))
    }
    writer.endSession(atSourceTime: CMTime(value: 3, timescale: 15))
    input.markAsFinished()
    let done = DispatchSemaphore(value: 0)
    writer.finishWriting { done.signal() }
    precondition(done.wait(timeout: .now() + 15) == .success)
    precondition(writer.status == .completed, "\(String(describing: writer.error))")
  }

  static func main() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let a = dir.appendingPathComponent("a.mp4")
    let b = dir.appendingPathComponent("b.mp4")
    let c = dir.appendingPathComponent("c.mp4")
    let d = dir.appendingPathComponent("d.mp4")
    try segment(a, width: 64, height: 32)
    try segment(b, width: 64, height: 32)
    try segment(c, width: 32, height: 64)
    try segment(d, width: 64, height: 32,
                transform: CGAffineTransform(rotationAngle: .pi))
    precondition(ReplayComposition.compatibleRuns([a, b]) == [[a, b]])
    precondition(ReplayComposition.compatibleRuns([a, b, c, a]) == [[a, b], [c], [a]])
    precondition(ReplayComposition.compatibleRuns([a, d]) == [[a], [d]])
    precondition(ReplayComposition.firstRun([]) == nil)
    print("PASS: dimensions and transforms split continuous runs, including A-B-A")

    let composition = ReplayComposition.firstRun([a, b, c, a])!
    let expected = CMTimeAdd(AVURLAsset(url: a).duration, AVURLAsset(url: b).duration)
    precondition(abs(CMTimeGetSeconds(composition.duration - expected)) < 0.001)
    precondition(composition.tracks(withMediaType: .video).count == 1)
    let export = AVAssetExportSession(asset: composition,
      presetName: AVAssetExportPresetPassthrough)!
    let output = dir.appendingPathComponent("out.mp4")
    export.outputURL = output
    export.outputFileType = .mp4
    let done = DispatchSemaphore(value: 0)
    export.exportAsynchronously { done.signal() }
    precondition(done.wait(timeout: .now() + 15) == .success)
    precondition(export.status == .completed, "\(String(describing: export.error))")
    let asset = AVURLAsset(url: output)
    let track = asset.tracks(withMediaType: .video).first!
    precondition(track.naturalSize == CGSize(width: 64, height: 32))
    precondition(abs(CMTimeGetSeconds(asset.duration - expected)) < 0.001)
    let reader = try AVAssetReader(asset: asset)
    let frames = AVAssetReaderTrackOutput(track: track, outputSettings: [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    ])
    reader.add(frames)
    precondition(reader.startReading())
    var count = 0
    while let sample = frames.copyNextSampleBuffer() {
      let image = CMSampleBufferGetImageBuffer(sample)!
      precondition(CVPixelBufferGetWidth(image) == 64 && CVPixelBufferGetHeight(image) == 32)
      count += 1
    }
    precondition(reader.status == .completed && count == 6)
    print("PASS: passthrough exports and decodes all six compatible frames")
  }
}
