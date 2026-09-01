import AVFoundation
import Flutter

/// Camera capture-rate throttle (thermal). During the opponent's turn nothing
/// consumes more than ~1 fps (the P2P trickle keeping the peer's stall
/// watchdog fed), yet the stock camera session keeps producing 15 fps of BGRA
/// frames that each cost a ~3.7 MB method-channel copy into Dart. iOS has no
/// cheap frame-drop hook in the stock camera plugin, but it has something
/// better: the capture device's frame duration can be changed live, without
/// reconfiguring the session — so the sensor/ISP/channel pipeline all slow
/// down together at the source.
///
/// Contract with Dart (CameraFrameService): "set" {deviceId, fps}. fps is
/// clamped to what the active format supports; a failure is silent (the call
/// is purely thermal, never functional). The camera plugin re-applies its own
/// 15 fps cap whenever it reconfigures, which is exactly the un-throttled
/// state — so a stale throttle can only persist within a session, and Dart
/// always restores fps explicitly on the my-turn flip and on teardown.
class CameraThrottlePlugin: NSObject {
  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "set",
          let args = call.arguments as? [String: Any],
          let deviceId = args["deviceId"] as? String,
          let fps = args["fps"] as? Int, fps > 0
    else {
      result(nil)
      return
    }
    guard let device = AVCaptureDevice(uniqueID: deviceId) else {
      result(nil)
      return
    }
    // Clamp to the active format's supported range: asking for 2 fps on a
    // format whose floor is 3 must degrade gracefully, not throw.
    var target = Double(fps)
    for range in device.activeFormat.videoSupportedFrameRateRanges {
      target = min(max(target, range.minFrameRate), range.maxFrameRate)
    }
    do {
      try device.lockForConfiguration()
      let duration = CMTime(value: 1, timescale: CMTimeScale(target.rounded()))
      device.activeVideoMinFrameDuration = duration
      device.activeVideoMaxFrameDuration = duration
      device.unlockForConfiguration()
    } catch {
      NSLog("CameraThrottle: lockForConfiguration failed: \(error)")
    }
    result(nil)
  }
}
