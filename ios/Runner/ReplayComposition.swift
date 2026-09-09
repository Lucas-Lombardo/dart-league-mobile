import AVFoundation

/// Passthrough exports share one size and transform for the whole track.
/// Keep chronological runs separate, including A → B → A rotations.
enum ReplayComposition {
  static func compatibleRuns(_ urls: [URL]) -> [[URL]] {
    var runs: [[URL]] = []
    var previous: AVAssetTrack?
    for url in urls {
      let asset = AVURLAsset(url: url)
      guard let track = asset.tracks(withMediaType: .video).first else {
        previous = nil
        continue
      }
      if let previous = previous,
         previous.naturalSize == track.naturalSize,
         previous.preferredTransform == track.preferredTransform {
        runs[runs.count - 1].append(url)
      } else {
        runs.append([url])
      }
      previous = track
    }
    return runs
  }

  /// Captures keep the first continuous compatible run. Keeping the prefix
  /// preserves startWallMs and avoids joining footage across a rotation.
  static func firstRun(_ urls: [URL]) -> AVMutableComposition? {
    guard let run = compatibleRuns(urls).first, run.first == urls.first else { return nil }
    let composition = AVMutableComposition()
    guard let target = composition.addMutableTrack(
      withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
    else { return nil }
    var cursor = CMTime.zero
    for url in run {
      let asset = AVURLAsset(url: url)
      guard let source = asset.tracks(withMediaType: .video).first else { return nil }
      if cursor == .zero { target.preferredTransform = source.preferredTransform }
      do {
        try target.insertTimeRange(
          CMTimeRange(start: .zero, duration: asset.duration), of: source, at: cursor)
        cursor = CMTimeAdd(cursor, asset.duration)
      } catch {
        NSLog("ReplayBuffer: insert failed: \(error)")
        return nil
      }
    }
    return cursor > .zero ? composition : nil
  }
}
