package com.dartrivals.app

import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import com.cloudwebrtc.webrtc.FlutterWebRTCPlugin
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.camera.media.ImageStreamReader

class MainActivity : FlutterFragmentActivity() {
    // Game screens hide the system bars (GameSystemUi, game_system_ui.dart).
    private var systemBarsHidden = false

    private fun applySystemBars() {
        val controller = WindowCompat.getInsetsController(window, window.decorView)
        if (systemBarsHidden) {
            // A swipe from the edge shows them over the content for a few
            // seconds, then they hide again on their own.
            controller.systemBarsBehavior =
                WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            controller.hide(WindowInsetsCompat.Type.systemBars())
        } else {
            controller.show(WindowInsetsCompat.Type.systemBars())
        }
    }

    // Flutter's PlatformPlugin re-applies its own system UI mode on every
    // resume (clearing the legacy visibility flags), so hide them again after.
    override fun onPostResume() {
        super.onPostResume()
        if (systemBarsHidden) applySystemBars()
    }

    // Back from the notification shade, a permission prompt, another app's
    // overlay...
    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus && systemBarsHidden) applySystemBars()
    }

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

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.dartrivals/system_bars",
        ).setMethodCallHandler { call, result ->
            if (call.method == "setHidden") {
                systemBarsHidden = call.argument<Boolean>("hidden") ?: false
                applySystemBars()
                result.success(null)
            } else {
                result.notImplemented()
            }
        }
    }
}
