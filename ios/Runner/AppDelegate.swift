import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
    }
    application.registerForRemoteNotifications()

    GeneratedPluginRegistrant.register(with: self)

    let controller = window?.rootViewController as! FlutterViewController
    let channel = FlutterMethodChannel(
      name: "com.dartrivals/native_inference",
      binaryMessenger: controller.binaryMessenger
    )
    let plugin = NativeInferencePlugin()
    channel.setMethodCallHandler(plugin.handle)

    // RTC v2 (P2P): custom video-frame injection into flutter_webrtc.
    // Registered after GeneratedPluginRegistrant so FlutterWebRTCPlugin's
    // sharedSingleton exists.
    let rtcFramesChannel = FlutterMethodChannel(
      name: "com.dartrivals/rtc_frames",
      binaryMessenger: controller.binaryMessenger
    )
    let rtcFramesPlugin = RtcFramesPlugin()
    rtcFramesChannel.setMethodCallHandler(rtcFramesPlugin.handle)

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
