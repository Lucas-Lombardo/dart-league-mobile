import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    application.registerForRemoteNotifications()

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// Plugins and the app's own channels are wired here, not in
  /// `didFinishLaunchingWithOptions`.
  ///
  /// Under the UIScene lifecycle the window — and with it the
  /// `FlutterViewController` this used to reach through
  /// `window?.rootViewController` — does not exist yet when the app delegate
  /// finishes launching. The implicit engine's registrar is the supported way
  /// in, and it is available before the first frame all the same.
  func didInitializeImplicitFlutterEngine(_ engineBridge: any FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let messenger = engineBridge.applicationRegistrar.messenger()

    let channel = FlutterMethodChannel(
      name: "com.dartrivals/native_inference",
      binaryMessenger: messenger
    )
    let plugin = NativeInferencePlugin()
    channel.setMethodCallHandler(plugin.handle)

    // RTC v2 (P2P): custom video-frame injection into flutter_webrtc.
    // Registered after GeneratedPluginRegistrant so FlutterWebRTCPlugin's
    // sharedSingleton exists.
    let rtcFramesChannel = FlutterMethodChannel(
      name: "com.dartrivals/rtc_frames",
      binaryMessenger: messenger
    )
    let rtcFramesPlugin = RtcFramesPlugin()
    rtcFramesChannel.setMethodCallHandler(rtcFramesPlugin.handle)

    // Replays: rolling ring buffer of the local camera (5s MP4 segments).
    let replayChannel = FlutterMethodChannel(
      name: "com.dartrivals/replay_buffer",
      binaryMessenger: messenger
    )
    let replayPlugin = ReplayBufferPlugin()
    replayChannel.setMethodCallHandler(replayPlugin.handle)

    // Thermal: live camera frame-rate throttle for the opponent's turn.
    let cameraThrottleChannel = FlutterMethodChannel(
      name: "com.dartrivals/camera_throttle",
      binaryMessenger: messenger
    )
    let cameraThrottlePlugin = CameraThrottlePlugin()
    cameraThrottleChannel.setMethodCallHandler(cameraThrottlePlugin.handle)
  }
}
