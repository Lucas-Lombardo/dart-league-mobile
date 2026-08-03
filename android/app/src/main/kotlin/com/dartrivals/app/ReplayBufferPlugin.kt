package com.dartrivals.app

import android.content.Context
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import android.os.Bundle
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.nio.ByteBuffer

/**
 * Rolling replay buffer: encodes the camera frames the app already produces
 * (same tight NV21/I420 buffers as the RTC push) into a ring of SELF-CONTAINED
 * short MP4 segments, and turns a wall-clock window into one clip by
 * concatenating segments WITHOUT re-encoding (MediaExtractor → MediaMuxer
 * passthrough).
 *
 * One continuous hardware encoder (MediaCodec AVC, one I-frame per segment);
 * the muxer rotates to a new file on each keyframe past the segment mark, so every
 * segment starts with an IDR and plays standalone. All state lives on the
 * dedicated handler thread — the platform thread only relays calls.
 *
 * Registered from MainActivity — same pattern as RtcFramesPlugin.
 */
class ReplayBufferPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {

    companion object {
        // 3s segments: capture bounds snap to segment edges, so the segment
        // length IS the worst-case clip preamble — 5s let a late dart-pull
        // slip into the clip head (2026-08-03 test). One IDR per segment.
        private const val SEGMENT_MS = 3_000L
        private const val RING_SEGMENTS = 16
        private const val BIT_RATE = 4_000_000
        private const val FRAME_RATE = 30
    }

    private lateinit var channel: MethodChannel
    private var appContext: Context? = null

    // Everything below is only touched on this thread.
    private val thread = HandlerThread("dartrivals-replay").apply { start() }
    private val handler = Handler(thread.looper)
    private val mainHandler = Handler(Looper.getMainLooper())

    private var codec: MediaCodec? = null
    // From INFO_OUTPUT_FORMAT_CHANGED — carries csd-0/1, reused by every
    // segment muxer.
    private var codecFormat: MediaFormat? = null
    private var encoderStartWallMs = 0L
    private var lastPtsUs = -1L
    // After a mid-GOP cut (capture), output P-frames reference a GOP the next
    // segment does not contain — drop them until the requested IDR arrives.
    private var awaitingIdr = false
    private var width = 0
    private var height = 0
    private var lastRotation = 0

    private var muxer: MediaMuxer? = null
    private var muxerTrack = -1
    private var segmentFile: File? = null
    private var segmentBasePtsUs = -1L
    private var segmentStartWallMs = 0L
    private var segmentRotation = 0
    private var lastSampleWallMs = 0L
    private var segmentIndex = 0

    private data class Segment(
        val file: File,
        val startWallMs: Long,
        val endWallMs: Long,
        val rotation: Int,
    )

    private val segments = ArrayDeque<Segment>()
    private val bufferInfo = MediaCodec.BufferInfo()

    private fun ringDir(): File =
        File(appContext!!.cacheDir, "replay_ring").apply { mkdirs() }

    private fun clipsDir(): File =
        File(appContext!!.cacheDir, "replay_clips").apply { mkdirs() }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "com.dartrivals/replay_buffer")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        handler.post { teardown(deleteRing = true) }
        thread.quitSafely()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pushFrame" -> pushFrame(call, result)
            "capture" -> capture(call, result)
            "render" -> renderOverlay(call, result)
            "pause" -> {
                // Turn gate: the Dart side stops sending frames for the
                // opponent's turn; close the open segment so the ring only
                // holds tidy my-turn footage, and make the next one start on
                // a fresh IDR (its P-frames would reference the old GOP).
                handler.post {
                    if (muxer != null) {
                        closeSegment()
                        awaitingIdr = true
                        try {
                            codec?.setParameters(Bundle().apply {
                                putInt(MediaCodec.PARAMETER_KEY_REQUEST_SYNC_FRAME, 0)
                            })
                        } catch (_: Exception) {}
                    }
                    mainHandler.post { result.success(null) }
                }
            }
            "stop" -> {
                handler.post {
                    teardown(deleteRing = true)
                    mainHandler.post { result.success(null) }
                }
            }
            else -> result.notImplemented()
        }
    }

    /** args: bytes (tight I420/NV21), width, height, rotation, format. */
    private fun pushFrame(call: MethodCall, result: MethodChannel.Result) {
        val bytes = call.argument<ByteArray>("bytes")
        val w = call.argument<Int>("width")
        val h = call.argument<Int>("height")
        if (bytes == null || w == null || h == null || w <= 0 || h <= 0 ||
            bytes.size < w * h * 3 / 2
        ) {
            result.success(null)
            return
        }
        val rotation = call.argument<Int>("rotation") ?: 0
        val format = call.argument<String>("format") ?: "nv21"
        handler.post {
            try {
                lastRotation = rotation
                ensureCodec(w, h)
                feedFrame(bytes, format)
                drainOutputs()
            } catch (e: Exception) {
                // A bad frame or a codec hiccup must never take the ring
                // down for the match; the encoder is rebuilt on next frame.
                android.util.Log.w("ReplayBuffer", "pushFrame failed: $e")
                teardown(deleteRing = false)
            }
            // Answered after consumption: keeps the Dart 2-in-flight cap
            // acting as backpressure (same contract as RtcFramesPlugin).
            mainHandler.post { result.success(null) }
        }
    }

    private fun ensureCodec(w: Int, h: Int) {
        if (codec != null && w == width && h == height) return
        teardown(deleteRing = false)
        width = w
        height = h
        val format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, w, h).apply {
            setInteger(
                MediaFormat.KEY_COLOR_FORMAT,
                MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420SemiPlanar,
            )
            setInteger(MediaFormat.KEY_BIT_RATE, BIT_RATE)
            setInteger(MediaFormat.KEY_FRAME_RATE, FRAME_RATE)
            // One IDR per segment = one boundary per GOP.
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, (SEGMENT_MS / 1000).toInt())
        }
        codec = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC).apply {
            configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            start()
        }
        encoderStartWallMs = System.currentTimeMillis()
        lastPtsUs = -1L
        awaitingIdr = false
    }

    private fun feedFrame(bytes: ByteArray, format: String) {
        val codec = codec ?: return
        val index = codec.dequeueInputBuffer(0)
        if (index < 0) return // encoder busy — dropping is the backpressure
        val input = codec.getInputBuffer(index) ?: return
        val ySize = width * height
        val needed = ySize * 3 / 2
        if (input.capacity() < needed) {
            codec.queueInputBuffer(index, 0, 0, 0, 0)
            return
        }
        input.clear()
        // Encoder wants NV12 (semi-planar UVUV); camera gives NV21 (VUVU)
        // or planar I420 — both are a cheap reorder of the chroma bytes.
        input.put(bytes, 0, ySize)
        if (format == "i420") {
            val uvSize = ySize / 4
            val uOff = ySize
            val vOff = ySize + uvSize
            for (i in 0 until uvSize) {
                input.put(bytes[uOff + i])
                input.put(bytes[vOff + i])
            }
        } else {
            var i = ySize
            val end = ySize + ySize / 2 - 1
            while (i < end) {
                input.put(bytes[i + 1])
                input.put(bytes[i])
                i += 2
            }
        }
        // Wall-clock-derived pts so a wall-clock capture window maps straight
        // onto sample times; strictly increasing for the codec's sake.
        val wallMs = System.currentTimeMillis()
        var ptsUs = (wallMs - encoderStartWallMs) * 1000
        if (ptsUs <= lastPtsUs) ptsUs = lastPtsUs + 1
        lastPtsUs = ptsUs
        codec.queueInputBuffer(index, 0, needed, ptsUs, 0)
    }

    private fun drainOutputs() {
        val codec = codec ?: return
        while (true) {
            val index = codec.dequeueOutputBuffer(bufferInfo, 0)
            when {
                index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED ->
                    codecFormat = codec.outputFormat
                index < 0 -> return
                else -> {
                    val buffer = codec.getOutputBuffer(index)
                    if (buffer != null) handleSample(buffer)
                    codec.releaseOutputBuffer(index, false)
                }
            }
        }
    }

    private fun handleSample(buffer: ByteBuffer) {
        if (bufferInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0) return
        val isKey = bufferInfo.flags and MediaCodec.BUFFER_FLAG_KEY_FRAME != 0
        if (awaitingIdr) {
            if (!isKey) return
            awaitingIdr = false
        }
        val sampleWallMs = encoderStartWallMs + bufferInfo.presentationTimeUs / 1000
        if (muxer == null) {
            if (!isKey || codecFormat == null) return // a segment must open on IDR
            openSegment(sampleWallMs)
        } else if (isKey && sampleWallMs - segmentStartWallMs >= SEGMENT_MS) {
            closeSegment()
            openSegment(sampleWallMs)
        }
        val muxer = muxer ?: return
        if (segmentBasePtsUs < 0) segmentBasePtsUs = bufferInfo.presentationTimeUs
        val info = MediaCodec.BufferInfo().apply {
            set(
                bufferInfo.offset,
                bufferInfo.size,
                bufferInfo.presentationTimeUs - segmentBasePtsUs,
                bufferInfo.flags,
            )
        }
        muxer.writeSampleData(muxerTrack, buffer, info)
        lastSampleWallMs = sampleWallMs
    }

    private fun openSegment(startWallMs: Long) {
        val file = File(ringDir(), "seg_${segmentIndex++}.mp4")
        file.delete()
        muxer = MediaMuxer(file.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4).apply {
            muxerTrack = addTrack(codecFormat!!)
            setOrientationHint(lastRotation)
            start()
        }
        segmentFile = file
        segmentBasePtsUs = -1L
        segmentStartWallMs = startWallMs
        segmentRotation = lastRotation
        lastSampleWallMs = startWallMs
    }

    private fun closeSegment() {
        val muxer = muxer ?: return
        this.muxer = null
        val file = segmentFile ?: return
        try {
            muxer.stop()
            muxer.release()
            segments.addLast(Segment(file, segmentStartWallMs, lastSampleWallMs, segmentRotation))
        } catch (e: Exception) {
            // A segment with zero samples can't stop() — just discard it.
            try { muxer.release() } catch (_: Exception) {}
            file.delete()
        }
        while (segments.size > RING_SEGMENTS) segments.removeFirst().file.delete()
    }

    /** args: fromMs, toMs (epoch millis) → {path, startWallMs}, or null. */
    private fun capture(call: MethodCall, result: MethodChannel.Result) {
        val fromMs = (call.argument<Number>("fromMs"))?.toLong()
        val toMs = (call.argument<Number>("toMs"))?.toLong()
        if (fromMs == null || toMs == null) {
            result.success(null)
            return
        }
        handler.post {
            var payload: Map<String, Any>? = null
            try {
                // Include the tail: close the open segment mid-GOP (its
                // samples are complete) and make the encoder restart the next
                // one on a fresh IDR.
                if (muxer != null) {
                    closeSegment()
                    awaitingIdr = true
                    try {
                        codec?.setParameters(Bundle().apply {
                            putInt(MediaCodec.PARAMETER_KEY_REQUEST_SYNC_FRAME, 0)
                        })
                    } catch (_: Exception) {}
                }
                val picked = segments.filter { it.endWallMs >= fromMs && it.startWallMs <= toMs }
                if (picked.isNotEmpty()) {
                    payload = mapOf(
                        "path" to concat(picked),
                        "startWallMs" to picked.first().startWallMs,
                    )
                }
            } catch (e: Exception) {
                android.util.Log.w("ReplayBuffer", "capture failed: $e")
            }
            mainHandler.post { result.success(payload) }
        }
    }

    /**
     * args: inPath, timeline (json) → path of the clip with the broadcast
     * overlay burned in. Runs on its OWN thread: a multi-second re-encode
     * must not stall the ring encoder's handler.
     */
    private fun renderOverlay(call: MethodCall, result: MethodChannel.Result) {
        val inPath = call.argument<String>("inPath")
        val timelineJson = call.argument<String>("timeline")
        if (inPath == null || timelineJson == null) {
            result.success(null)
            return
        }
        Thread {
            var outPath: String? = null
            try {
                val out = File(clipsDir(), "clip_${System.currentTimeMillis()}_brand.mp4")
                ReplayOverlayRenderer(org.json.JSONObject(timelineJson))
                    .render(inPath, out.absolutePath)
                outPath = out.absolutePath
            } catch (e: Exception) {
                android.util.Log.w("ReplayBuffer", "render failed: $e")
            }
            mainHandler.post { result.success(outPath) }
        }.start()
    }

    /** Passthrough concat — no decode, no re-encode. */
    private fun concat(picked: List<Segment>): String {
        val out = File(clipsDir(), "clip_${System.currentTimeMillis()}.mp4")
        val outMuxer = MediaMuxer(out.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        var outTrack = -1
        var started = false
        var offsetUs = 0L
        val copyBuffer = ByteBuffer.allocateDirect(1 shl 20)
        try {
            for (segment in picked) {
                val extractor = MediaExtractor()
                extractor.setDataSource(segment.file.absolutePath)
                var videoTrack = -1
                for (t in 0 until extractor.trackCount) {
                    val mime = extractor.getTrackFormat(t).getString(MediaFormat.KEY_MIME) ?: ""
                    if (mime.startsWith("video/")) {
                        videoTrack = t
                        break
                    }
                }
                if (videoTrack < 0) {
                    extractor.release()
                    continue
                }
                extractor.selectTrack(videoTrack)
                if (!started) {
                    outTrack = outMuxer.addTrack(extractor.getTrackFormat(videoTrack))
                    outMuxer.setOrientationHint(picked.first().rotation)
                    outMuxer.start()
                    started = true
                }
                var maxPtsUs = 0L
                while (true) {
                    copyBuffer.clear()
                    val size = extractor.readSampleData(copyBuffer, 0)
                    if (size < 0) break
                    val info = MediaCodec.BufferInfo().apply {
                        set(
                            0,
                            size,
                            extractor.sampleTime + offsetUs,
                            if (extractor.sampleFlags and MediaExtractor.SAMPLE_FLAG_SYNC != 0)
                                MediaCodec.BUFFER_FLAG_KEY_FRAME else 0,
                        )
                    }
                    outMuxer.writeSampleData(outTrack, copyBuffer, info)
                    if (extractor.sampleTime > maxPtsUs) maxPtsUs = extractor.sampleTime
                    extractor.advance()
                }
                extractor.release()
                offsetUs += maxPtsUs + 1_000_000L / FRAME_RATE
            }
        } finally {
            try {
                if (started) outMuxer.stop()
            } catch (_: Exception) {}
            try { outMuxer.release() } catch (_: Exception) {}
        }
        return out.absolutePath
    }

    private fun teardown(deleteRing: Boolean) {
        try { closeSegment() } catch (_: Exception) {}
        try {
            codec?.stop()
        } catch (_: Exception) {}
        try {
            codec?.release()
        } catch (_: Exception) {}
        codec = null
        codecFormat = null
        if (deleteRing) {
            segments.forEach { it.file.delete() }
            segments.clear()
            appContext?.let { File(it.cacheDir, "replay_ring").listFiles()?.forEach(File::delete) }
        }
    }
}
