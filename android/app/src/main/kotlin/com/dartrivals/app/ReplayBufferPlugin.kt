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
import java.util.UUID

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
        // Must track the Dart side's camera fps
        // (CameraFrameService.cameraFps) — rate-control hint and
        // concat frame gap both assume the real capture cadence.
        private const val FRAME_RATE = 15

        // ── Match-proof retention ──
        // The ring is turn-gated, so consecutive segments of one of my turns
        // are wall-clock contiguous; a gap wider than this is the opponent's
        // turn between two of mine — the run boundary cutRuns splits on.
        private const val RUN_GAP_MS = 4_000L
        // Retained matches live on disk until the dispute window closes...
        private const val RETENTION_TTL_MS = 48L * 60 * 60 * 1000
        // ...bounded in total so a heavy day of matches can't eat the phone.
        private const val RETENTION_CAP_BYTES = 2L * 1024 * 1024 * 1024
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
    private val encoderProgress = ReplayEncoderProgress()

    private data class Segment(
        val file: File,
        val startWallMs: Long,
        val endWallMs: Long,
        val rotation: Int,
    )

    private val segments = ArrayDeque<Segment>()
    private val bufferInfo = MediaCodec.BufferInfo()

    // Reusable chroma staging for feedFrame: interleaving through a local
    // ByteArray then ONE bulk put replaces ~345k per-byte ByteBuffer.put()
    // calls per frame (each paying position+bounds bookkeeping), 15×/s for
    // every my-turn frame of the match.
    private var chromaStaging = ByteArray(0)

    // Match-proof retention: while non-null, new segments are written under
    // match_proof/<key>/ and NEVER evicted — the whole match's my-turn footage
    // stays on disk (same encoder, same bitrate: zero extra heat, we just stop
    // throwing the files away). Each closed segment appends one JSON line to
    // the dir's index.jsonl, so cutRuns() can rebuild the timeline after the
    // app restarted.
    private var retainKey: String? = null

    private fun ringDir(): File =
        File(appContext!!.cacheDir, "replay_ring").apply { mkdirs() }

    private fun clipsDir(): File =
        File(appContext!!.cacheDir, "replay_clips").apply { mkdirs() }

    private fun retentionRoot(): File =
        File(appContext!!.cacheDir, "match_proof").apply { mkdirs() }

    /** [key] is an opaque id from Dart (matchId/seriesId); sanitize for FS. */
    private fun retentionDir(key: String): File =
        File(retentionRoot(), key.replace(Regex("[^A-Za-z0-9_-]"), "_"))
            .apply { mkdirs() }

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
            "beginRetention" -> {
                val key = call.argument<String>("key")
                handler.post {
                    if (key != null) {
                        // New match: make room first, then start retaining.
                        purgeRetention(keepKey = key)
                        // Close whatever the ring already holds (pre-match
                        // setup footage) so the retained dir starts clean.
                        if (muxer != null) closeSegment()
                        retainKey = key
                    }
                    mainHandler.post { result.success(null) }
                }
            }
            "cutRuns" -> cutRuns(call, result)
            "captureRetained" -> captureRetained(call, result)
            "deleteRetention" -> {
                val key = call.argument<String>("key")
                handler.post {
                    if (key != null) {
                        if (retainKey == key) retainKey = null
                        retentionDir(key).deleteRecursively()
                    }
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
                encoderProgress.frameSubmitted()
                feedFrame(bytes, format)
                drainOutputs()
                // Some hardware codecs stall without throwing: no input
                // buffers, no output, or no IDR after a turn boundary. Keep
                // the retained segments and recreate only the encoder.
                if (encoderProgress.stalled) {
                    android.util.Log.w("ReplayBuffer", "encoder stalled; restarting")
                    teardown(deleteRing = false)
                }
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
        val nextCodec = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
        try {
            nextCodec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            nextCodec.start()
            codec = nextCodec
        } catch (e: Exception) {
            nextCodec.release()
            throw e
        }
        encoderProgress.reset()
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
        // or planar I420 — both are a cheap reorder of the chroma bytes,
        // staged in a plain array and written with one bulk put.
        input.put(bytes, 0, ySize)
        val chromaSize = ySize / 2
        if (chromaStaging.size < chromaSize) chromaStaging = ByteArray(chromaSize)
        val staging = chromaStaging
        if (format == "i420") {
            val uvSize = ySize / 4
            val uOff = ySize
            val vOff = ySize + uvSize
            for (i in 0 until uvSize) {
                val d = i shl 1
                staging[d] = bytes[uOff + i]
                staging[d + 1] = bytes[vOff + i]
            }
        } else {
            var s = ySize
            var d = 0
            while (d < chromaSize - 1) {
                staging[d] = bytes[s + 1]
                staging[d + 1] = bytes[s]
                s += 2
                d += 2
            }
        }
        input.put(staging, 0, chromaSize)
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
        encoderProgress.sampleWritten()
    }

    private fun openSegment(startWallMs: Long) {
        val dir = retainKey?.let { retentionDir(it) } ?: ringDir()
        val file = File(dir, "seg_${UUID.randomUUID()}.mp4")
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
            // Retention: one crash-safe index line per closed segment, so the
            // timeline survives the app (cutRuns may run a relaunch later).
            val key = retainKey
            if (key != null && file.parentFile == retentionDir(key)) {
                try {
                    File(retentionDir(key), "index.jsonl").appendText(
                        "{\"f\":\"${file.name}\",\"s\":$segmentStartWallMs," +
                            "\"e\":$lastSampleWallMs,\"r\":$segmentRotation}\n",
                    )
                } catch (e: Exception) {
                    android.util.Log.w("ReplayBuffer", "index append failed: $e")
                }
            }
        } catch (e: Exception) {
            // A segment with zero samples can't stop() — just discard it.
            try { muxer.release() } catch (_: Exception) {}
            file.delete()
        }
        // Under retention the whole match is kept — the eviction that made
        // this a 48s ring is exactly what the match-proof feature removes.
        if (retainKey == null) {
            while (segments.size > RING_SEGMENTS) segments.removeFirst().file.delete()
        }
    }

    /**
     * args: fromMs, toMs (epoch millis), rotation (optional orientation-hint
     * override) → {path, startWallMs, durationMs}, or null.
     */
    private fun capture(call: MethodCall, result: MethodChannel.Result) {
        val fromMs = (call.argument<Number>("fromMs"))?.toLong()
        val toMs = (call.argument<Number>("toMs"))?.toLong()
        val rotationOverride = (call.argument<Number>("rotation"))?.toInt()
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
                    val (path, durationMs) = concat(picked, rotationOverride)
                    payload = mapOf(
                        "path" to path,
                        "startWallMs" to picked.first().startWallMs,
                        "durationMs" to durationMs,
                    )
                }
            } catch (e: Exception) {
                android.util.Log.w("ReplayBuffer", "capture failed: $e")
            }
            mainHandler.post { result.success(payload) }
        }
    }

    /**
     * Match-proof: turn a retained match's segments into one passthrough clip
     * PER TURN (the ring is turn-gated, so a wall-clock gap between segments
     * IS a turn boundary). Reads index.jsonl, so it works during the match,
     * after stop(), and after an app relaunch.
     *
     * args: key, rotation (optional calibration override) →
     * {clips: [{path, startWallMs, durationMs}]}.
     */
    private fun cutRuns(call: MethodCall, result: MethodChannel.Result) {
        val key = call.argument<String>("key")
        val rotationOverride = (call.argument<Number>("rotation"))?.toInt()
        if (key == null) {
            result.success(null)
            return
        }
        handler.post {
            var payload: Map<String, Any>? = null
            try {
                // Flush the segment in flight so the last visit is included.
                if (retainKey == key && muxer != null) {
                    closeSegment()
                    awaitingIdr = true
                }
                val dir = retentionDir(key)
                val index = File(dir, "index.jsonl")
                var complete = true
                val retained = mutableListOf<Segment>()
                if (index.exists()) {
                    index.forEachLine { line ->
                        try {
                            val obj = org.json.JSONObject(line)
                            val file = File(dir, obj.getString("f"))
                            if (file.exists()) {
                                retained.add(Segment(
                                    file,
                                    obj.getLong("s"),
                                    obj.getLong("e"),
                                    obj.optInt("r", 0),
                                ))
                            } else {
                                complete = false
                            }
                        } catch (_: Exception) { complete = false }
                    }
                }
                retained.sortBy { it.startWallMs }
                val runsDir = File(dir, "clips").apply { mkdirs() }
                val clips = mutableListOf<Map<String, Any>>()
                var run = mutableListOf<Segment>()
                var runIndex = 0
                fun flushRun() {
                    if (run.isEmpty()) return
                    val outFile = File(runsDir, "run_${runIndex++}.mp4")
                    try {
                        val (path, durationMs) = concat(run, rotationOverride, outFile)
                        clips.add(mapOf(
                            "path" to path,
                            "startWallMs" to run.first().startWallMs,
                            "durationMs" to durationMs,
                        ))
                    } catch (e: Exception) {
                        complete = false
                        outFile.delete()
                        android.util.Log.w("ReplayBuffer", "proof run export failed: $e")
                    }
                    run = mutableListOf()
                }
                for (segment in retained) {
                    if (run.isNotEmpty() &&
                        segment.startWallMs - run.last().endWallMs > RUN_GAP_MS
                    ) {
                        flushRun()
                    }
                    run.add(segment)
                }
                flushRun()
                payload = mapOf("clips" to clips, "complete" to complete)
            } catch (e: Exception) {
                android.util.Log.w("ReplayBuffer", "cutRuns failed: $e")
            }
            mainHandler.post { result.success(payload) }
        }
    }

    /**
     * Like capture(), but over a RETAINED match instead of the live ring —
     * for a turn-report flag arriving after the ring was stopped (end
     * screens) or after a relaunch. args: key, fromMs, toMs, rotation →
     * {path, startWallMs, durationMs} or null.
     */
    private fun captureRetained(call: MethodCall, result: MethodChannel.Result) {
        val key = call.argument<String>("key")
        val fromMs = (call.argument<Number>("fromMs"))?.toLong()
        val toMs = (call.argument<Number>("toMs"))?.toLong()
        val rotationOverride = (call.argument<Number>("rotation"))?.toInt()
        if (key == null || fromMs == null || toMs == null) {
            result.success(null)
            return
        }
        handler.post {
            var payload: Map<String, Any>? = null
            try {
                if (retainKey == key && muxer != null) closeSegment()
                val dir = retentionDir(key)
                val index = File(dir, "index.jsonl")
                val picked = mutableListOf<Segment>()
                if (index.exists()) {
                    index.forEachLine { line ->
                        try {
                            val obj = org.json.JSONObject(line)
                            val file = File(dir, obj.getString("f"))
                            val s = obj.getLong("s")
                            val e = obj.getLong("e")
                            if (file.exists() && e >= fromMs && s <= toMs) {
                                picked.add(Segment(file, s, e, obj.optInt("r", 0)))
                            }
                        } catch (_: Exception) {}
                    }
                }
                picked.sortBy { it.startWallMs }
                if (picked.isNotEmpty()) {
                    val (path, durationMs) = concat(picked, rotationOverride)
                    payload = mapOf(
                        "path" to path,
                        "startWallMs" to picked.first().startWallMs,
                        "durationMs" to durationMs,
                    )
                }
            } catch (e: Exception) {
                android.util.Log.w("ReplayBuffer", "captureRetained failed: $e")
            }
            mainHandler.post { result.success(payload) }
        }
    }

    /**
     * Drop retained matches past the dispute window, then oldest-first past
     * the total size cap. [keepKey] (the match being started) is never purged.
     */
    private fun purgeRetention(keepKey: String?) {
        try {
            val dirs = retentionRoot().listFiles { f -> f.isDirectory }
                ?.sortedBy { it.lastModified() } ?: return
            val now = System.currentTimeMillis()
            var totalBytes = 0L
            val sizes = HashMap<File, Long>()
            for (dir in dirs) {
                val size = dir.walkBottomUp().filter { it.isFile }.sumOf { it.length() }
                sizes[dir] = size
                totalBytes += size
            }
            for (dir in dirs) {
                val keep = keepKey != null && dir == retentionDir(keepKey)
                val expired = now - dir.lastModified() > RETENTION_TTL_MS
                val overCap = totalBytes > RETENTION_CAP_BYTES
                if (!keep && (expired || overCap)) {
                    totalBytes -= sizes[dir] ?: 0L
                    dir.deleteRecursively()
                }
            }
        } catch (e: Exception) {
            android.util.Log.w("ReplayBuffer", "purgeRetention failed: $e")
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
            // Info-level on purpose (visible in release logcat): the render
            // is the deferred pipeline's least observable stage.
            android.util.Log.i("ReplayBuffer", "render start $inPath")
            var outPath: String? = null
            try {
                val out = File(clipsDir(), "clip_${System.currentTimeMillis()}_brand.mp4")
                ReplayOverlayRenderer(org.json.JSONObject(timelineJson))
                    .render(inPath, out.absolutePath)
                outPath = out.absolutePath
            } catch (e: Exception) {
                android.util.Log.w("ReplayBuffer", "render failed: $e")
            }
            android.util.Log.i("ReplayBuffer", "render done -> $outPath")
            mainHandler.post { result.success(outPath) }
        }.start()
    }

    /** Passthrough concat — no decode, no re-encode. */
    /**
     * Returns the concatenated clip's path and its duration in milliseconds.
     * [rotationOverride], when non-null, wins over the segments' own stamps:
     * the caller learns the true board orientation from the AI calibration,
     * which can settle AFTER the oldest segments of the window were recorded.
     */
    private fun concat(
        picked: List<Segment>,
        rotationOverride: Int? = null,
        outFile: File? = null,
    ): Pair<String, Long> {
        val out = outFile ?: File(clipsDir(), "clip_${System.currentTimeMillis()}.mp4")
        out.delete()
        val outMuxer = MediaMuxer(out.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        var outTrack = -1
        var started = false
        var offsetUs = 0L
        val copyBuffer = ByteBuffer.allocateDirect(1 shl 20)
        try {
            for (segment in picked) {
                val extractor = MediaExtractor()
                try {
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
                        throw IllegalStateException("Retained segment has no video track")
                    }
                    extractor.selectTrack(videoTrack)
                    if (!started) {
                        outTrack = outMuxer.addTrack(extractor.getTrackFormat(videoTrack))
                        // One hint rules the whole clip. The caller's value is the
                        // authority when it has one (calibration, measured at cut
                        // time); otherwise segments can disagree — mid-match hint
                        // changes — so take the dominant rotation, not the first's.
                        val rotation = rotationOverride
                            ?: picked.groupingBy { it.rotation }
                                .eachCount().maxByOrNull { it.value }!!.key
                        android.util.Log.i("ReplayBuffer", "clip orientation hint=$rotation" +
                            (if (rotationOverride != null) " (from calibration)" else " (dominant segment)"))
                        outMuxer.setOrientationHint(rotation)
                        outMuxer.start()
                        started = true
                    }
                    var maxPtsUs = 0L
                    var samples = 0
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
                        samples++
                        if (extractor.sampleTime > maxPtsUs) maxPtsUs = extractor.sampleTime
                        extractor.advance()
                    }
                    check(samples > 0) { "Retained segment has no video samples" }
                    offsetUs += maxPtsUs + 1_000_000L / FRAME_RATE
                } finally {
                    extractor.release()
                }
            }
            check(started && offsetUs > 0) { "Empty proof export" }
            outMuxer.stop()
        } finally {
            try { outMuxer.release() } catch (_: Exception) {}
        }
        // offsetUs ended up on the last sample's end: that IS the clip length.
        return out.absolutePath to offsetUs / 1000
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
            // Retained segments (match_proof/<key>/) survive the stop: they
            // ARE the proof, purged by TTL/cap or an explicit deleteRetention.
            val keep = retainKey?.let { retentionDir(it) }
            segments.forEach { if (it.file.parentFile != keep) it.file.delete() }
            segments.clear()
            appContext?.let { File(it.cacheDir, "replay_ring").listFiles()?.forEach(File::delete) }
            retainKey = null
        }
    }
}
