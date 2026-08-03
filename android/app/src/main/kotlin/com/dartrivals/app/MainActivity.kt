package com.dartrivals.app

import com.cloudwebrtc.webrtc.FlutterWebRTCPlugin
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

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
    }
}
