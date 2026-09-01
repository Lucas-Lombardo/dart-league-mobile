package com.dartrivals.app

import com.cloudwebrtc.webrtc.FlutterWebRTCPlugin
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.camera.media.ImageStreamReader

class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(NativeInferencePlugin())
        // Resolve THIS engine's FlutterWebRTCPlugin instance (registered by
        // GeneratedPluginRegistrant in super.configureFlutterEngine) — the
        // static sharedSingleton can point at the push-notification background
        // engine's instance, whose factory is never initialized.
        val webrtcPlugin =
            flutterEngine.plugins.get(FlutterWebRTCPlugin::class.java) as? FlutterWebRTCPlugin
        flutterEngine.plugins.add(RtcFramesPlugin(webrtcPlugin))
        flutterEngine.plugins.add(ReplayBufferPlugin())

        // Camera frame-delivery throttle (thermal): flips the vendored
        // camera_android patch's static gate — see ImageStreamReader.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.dartrivals/camera_throttle",
        ).setMethodCallHandler { call, result ->
            if (call.method == "set") {
                ImageStreamReader.throttleMinIntervalMs =
                    (call.argument<Number>("intervalMs") ?: 0).toLong()
                result.success(null)
            } else {
                result.notImplemented()
            }
        }
    }
}
