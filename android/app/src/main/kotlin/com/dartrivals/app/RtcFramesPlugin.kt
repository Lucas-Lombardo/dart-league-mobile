package com.dartrivals.app

import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.os.SystemClock
import com.cloudwebrtc.webrtc.FlutterWebRTCPlugin
import com.cloudwebrtc.webrtc.MethodCallHandlerImpl
import com.cloudwebrtc.webrtc.video.LocalVideoTrack
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.webrtc.JavaI420Buffer
import org.webrtc.NV21Buffer
import org.webrtc.VideoFrame
import org.webrtc.VideoSource
import org.webrtc.VideoTrack
import java.nio.ByteBuffer
import kotlin.math.min

/**
 * Native companion for the RTC v2 (P2P WebRTC) path.
 *
 * The app owns the camera (CameraFrameService feeds the AI scorer), so the
 * WebRTC video track cannot use a WebRTC-managed capturer. This plugin reaches
 * into flutter_webrtc's singleton to create a VideoSource-backed track with a
 * fixed id, registers it in the plugin's localTracks (same LocalVideoTrack
 * wrapper getUserMedia uses) so every Dart-side call (addTrack / replaceTrack /
 * trackDispose) resolves it, and exposes a `pushFrame` channel the camera
 * service feeds with the same tight I420/NV21 buffers it pushes to Agora.
 *
 * Registered from MainActivity — same pattern as NativeInferencePlugin.
 * org.webrtc classes come from `compileOnly io.github.webrtc-sdk:android`
 * (see app build.gradle.kts) — at runtime they are provided by flutter_webrtc's
 * own dependency, so the versions must stay in lock-step.
 */
class RtcFramesPlugin(
    // The FlutterWebRTCPlugin instance attached to OUR engine, resolved by
    // MainActivity from the engine's plugin registry. NEVER use
    // FlutterWebRTCPlugin.sharedSingleton here: its constructor overwrites
    // the static on every instantiation, and the push-notification background
    // isolate registers a second instance whose factory is never initialized
    // — reaching through the singleton returned no_factory while the main
    // engine's own instance was perfectly healthy (2026-08-02 prod test).
    private val webrtcPlugin: FlutterWebRTCPlugin?,
) : FlutterPlugin, MethodChannel.MethodCallHandler {

    companion object {
        const val TRACK_ID = "dartrivals-ext-cam"
    }

    private lateinit var channel: MethodChannel
    private var videoSource: VideoSource? = null
    private var videoTrack: VideoTrack? = null

    // NV21→I420 (libyuv full-frame conversion + a 1.4MB direct-buffer
    // allocation) runs on the CALLING thread inside libwebrtc's
    // onFrameCaptured — verified in the 144.7559.09 AAR bytecode. At 15fps
    // on the platform thread that competed with UI + every other channel
    // (and this codebase has an overheating history). Serial HandlerThread =
    // frame order preserved; the result is answered only after the frame is
    // consumed, so the Dart-side 2-in-flight cap keeps acting as
    // backpressure. Mirrors the iOS frameQueue.
    private val frameThread = HandlerThread("dartrivals-rtc-frames").apply { start() }
    private val frameHandler = Handler(frameThread.looper)
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "com.dartrivals/rtc_frames")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        release()
        // After release()'s posted disposals drain.
        frameThread.quitSafely()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "create" -> create(result)
            "pushFrame" -> pushFrame(call, result)
            "dispose" -> {
                disposeTrack()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    /**
     * flutter_webrtc keeps its MethodCallHandlerImpl (the StateProvider owning
     * localTracks and the PeerConnectionFactory) in a private field with no
     * public accessor for putLocalTrack, so this is the one reflective seam.
     * Safe under R8: the plugin ships `-keep class com.cloudwebrtc.webrtc.**`
     * consumer rules, so the field name survives minification.
     */
    private fun webrtcHandler(): MethodCallHandlerImpl? {
        // No sharedSingleton fallback: that static is exactly the
        // background-isolate-hijacked instance documented above — better to
        // fail loudly into telemetry than silently reach the wrong engine.
        val plugin = webrtcPlugin ?: return null
        return try {
            val field = FlutterWebRTCPlugin::class.java.getDeclaredField("methodCallHandler")
            field.isAccessible = true
            field.get(plugin) as? MethodCallHandlerImpl
        } catch (e: Exception) {
            null
        }
    }

    private fun create(result: MethodChannel.Result) {
        val handler = webrtcHandler()
        if (handler == null) {
            result.error("no_handler", "flutter_webrtc plugin/handler unreachable", null)
            return
        }
        // The factory is created by flutter_webrtc's native 'initialize',
        // which has run by now because the Dart side creates the
        // RTCPeerConnection before asking for this track.
        val factory = handler.peerConnectionFactory
        if (factory == null) {
            result.error("no_factory", "flutter_webrtc factory not initialized", null)
            return
        }
        if (videoTrack == null) {
            val source = factory.createVideoSource(false)
            // Canonical custom-capture contract: mark the source live before
            // frames arrive — a source never "started" can drop every frame.
            source.capturerObserver.onCapturerStarted(true)
            val track = factory.createVideoTrack(TRACK_ID, source)
            track.setEnabled(true)
            videoSource = source
            videoTrack = track
        }
        handler.putLocalTrack(TRACK_ID, LocalVideoTrack(videoTrack!!))
        result.success(TRACK_ID)
    }

    /**
     * args: bytes (tight planar I420 or NV21, no row padding), width, height,
     * rotation (clockwise degrees to upright — same semantic as the Agora
     * push), format ('i420' | 'nv21').
     */
    private fun pushFrame(call: MethodCall, result: MethodChannel.Result) {
        val source = videoSource
        val bytes = call.argument<ByteArray>("bytes")
        val width = call.argument<Int>("width")
        val height = call.argument<Int>("height")
        if (source == null || bytes == null || width == null || height == null ||
            width <= 0 || height <= 0
        ) {
            result.success(null)
            return
        }
        val rotation = call.argument<Int>("rotation") ?: 0
        val format = call.argument<String>("format") ?: "nv21"
        // libyuv reads w*h*1.5 bytes unconditionally on the NV21 path — a
        // short buffer would be a NATIVE overread (SIGSEGV, not a Java
        // exception the catch below could see).
        if (bytes.size < width * height * 3 / 2) {
            result.success(null)
            return
        }

        frameHandler.post {
            try {
                val buffer: VideoFrame.Buffer = if (format == "i420") {
                    // JavaI420Buffer.allocate uses tight strides (y=width,
                    // u/v=width/2 for even dimensions), matching our packed
                    // input.
                    val i420 = JavaI420Buffer.allocate(width, height)
                    val ySize = width * height
                    val uvSize = (width / 2) * (height / 2)
                    putPlane(bytes, 0, ySize, i420.dataY)
                    putPlane(bytes, ySize, uvSize, i420.dataU)
                    putPlane(bytes, ySize + uvSize, uvSize, i420.dataV)
                    i420
                } else {
                    // Zero-copy wrap: the byte[] decoded from the method
                    // channel is exclusively ours (conversion happens in
                    // onFrameCaptured, on THIS thread).
                    NV21Buffer(bytes, width, height, null)
                }
                val frame = VideoFrame(buffer, rotation, SystemClock.elapsedRealtimeNanos())
                source.capturerObserver.onFrameCaptured(frame)
                frame.release()
            } catch (_: Exception) {
                // A malformed frame must never take the channel down; the
                // next frame is at most ~60ms away.
            }
            // FlutterJNI requires responses on the platform thread; answering
            // only after consumption keeps the Dart 2-in-flight backpressure.
            mainHandler.post { result.success(null) }
        }
    }

    private fun putPlane(src: ByteArray, offset: Int, length: Int, dst: ByteBuffer) {
        val d = dst.duplicate()
        d.clear()
        d.put(src, offset, min(length, min(src.size - offset, d.remaining())))
    }

    private fun disposeTrack() {
        // Removes the entry from localTracks (does NOT dispose the track).
        try {
            webrtcHandler()?.trackDispose(TRACK_ID)
        } catch (_: Exception) {
        }
        release()
    }

    private fun release() {
        // Nil the fields ON THE PLATFORM THREAD (a subsequent create() can't
        // be undone by a stale teardown), but run the actual disposals on
        // frameHandler so any in-flight frame finishes against a live
        // source first (serial queue = ordered after it).
        val track = videoTrack
        val source = videoSource
        videoTrack = null
        videoSource = null
        frameHandler.post {
            try {
                track?.dispose()
            } catch (_: Exception) {
            }
            try {
                source?.dispose()
            } catch (_: Exception) {
            }
        }
    }
}
