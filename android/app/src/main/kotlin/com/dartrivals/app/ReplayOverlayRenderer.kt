package com.dartrivals.app

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PorterDuff
import android.graphics.RadialGradient
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.SurfaceTexture
import android.graphics.Typeface
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.media.MediaMuxer
import android.opengl.EGL14
import android.opengl.EGLConfig
import android.opengl.EGLContext
import android.opengl.EGLDisplay
import android.opengl.EGLExt
import android.opengl.EGLSurface
import android.opengl.GLES11Ext
import android.opengl.GLES20
import android.opengl.GLUtils
import android.os.Handler
import android.os.HandlerThread
import android.view.Surface
import org.json.JSONObject
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer

/**
 * Burns the broadcast overlay into a captured clip: decode → GL (video
 * frame + overlay texture) → hardware re-encode. The overlay is drawn with
 * Canvas in DISPLAY space (720-wide design grid) and mapped into the
 * source's pixel space with a Canvas matrix, so the GL pass needs no
 * rotation logic at all — the output MP4 keeps the source's orientation
 * hint, exactly like the raw clip.
 *
 * The renderer interprets the three timeline primitives (scoreboard, banner,
 * outro) and knows nothing about darts — see replay_overlay_timeline.dart
 * for the contract.
 */
class ReplayOverlayRenderer(private val timeline: JSONObject) {

    fun render(inPath: String, outPath: String) {
        val retriever = MediaMetadataRetriever()
        retriever.setDataSource(inPath)
        val rotation = retriever
            .extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)
            ?.toIntOrNull() ?: 0
        retriever.release()

        val extractor = MediaExtractor()
        extractor.setDataSource(inPath)
        var trackIndex = -1
        var inFormat: MediaFormat? = null
        for (i in 0 until extractor.trackCount) {
            val f = extractor.getTrackFormat(i)
            if ((f.getString(MediaFormat.KEY_MIME) ?: "").startsWith("video/")) {
                trackIndex = i
                inFormat = f
                break
            }
        }
        val format = inFormat ?: throw IllegalArgumentException("no video track")
        extractor.selectTrack(trackIndex)
        val srcW = format.getInteger(MediaFormat.KEY_WIDTH)
        val srcH = format.getInteger(MediaFormat.KEY_HEIGHT)
        val durationMs =
            if (format.containsKey(MediaFormat.KEY_DURATION))
                format.getLong(MediaFormat.KEY_DURATION) / 1000
            else 0L

        val encoder = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
        encoder.configure(
            MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, srcW, srcH).apply {
                setInteger(
                    MediaFormat.KEY_COLOR_FORMAT,
                    MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface,
                )
                setInteger(MediaFormat.KEY_BIT_RATE, 4_000_000)
                // Rate-control hint only (the cadence follows the decoded
                // samples) — matches the ring's 24 fps capture.
                setInteger(MediaFormat.KEY_FRAME_RATE, 24)
                setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 2)
            },
            null, null, MediaCodec.CONFIGURE_FLAG_ENCODE,
        )
        val encoderSurface = encoder.createInputSurface()
        encoder.start()

        val egl = EglWindow(encoderSurface)
        val painter = OverlayPainter(timeline, srcW, srcH, rotation, durationMs)
        var decoder: MediaCodec? = null
        var muxer: MediaMuxer? = null
        val callbackThread = HandlerThread("replay-render-cb").apply { start() }
        try {
            val gl = GlPrograms(srcW, srcH)
            val videoTex = gl.createExternalTexture()
            val surfaceTexture = SurfaceTexture(videoTex)
            surfaceTexture.setDefaultBufferSize(srcW, srcH)
            val frameLock = Object()
            var frameAvailable = false
            surfaceTexture.setOnFrameAvailableListener(
                {
                    synchronized(frameLock) {
                        frameAvailable = true
                        frameLock.notifyAll()
                    }
                },
                Handler(callbackThread.looper),
            )
            val decoderSurface = Surface(surfaceTexture)
            decoder = MediaCodec
                .createDecoderByType(format.getString(MediaFormat.KEY_MIME)!!)
                .apply {
                    configure(format, decoderSurface, null, 0)
                    start()
                }

            muxer = MediaMuxer(outPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            muxer.setOrientationHint(rotation)
            var muxTrack = -1
            var muxStarted = false
            val info = MediaCodec.BufferInfo()

            var inputDone = false
            var decodeDone = false
            var encodeDone = false
            val deadline = System.currentTimeMillis() + 120_000
            while (!encodeDone) {
                if (System.currentTimeMillis() > deadline) {
                    throw IllegalStateException("render timed out")
                }
                // 1. Feed the extractor into the decoder.
                if (!inputDone) {
                    val idx = decoder.dequeueInputBuffer(10_000)
                    if (idx >= 0) {
                        val buf = decoder.getInputBuffer(idx)!!
                        val size = extractor.readSampleData(buf, 0)
                        if (size < 0) {
                            decoder.queueInputBuffer(
                                idx, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM,
                            )
                            inputDone = true
                        } else {
                            decoder.queueInputBuffer(idx, 0, size, extractor.sampleTime, 0)
                            extractor.advance()
                        }
                    }
                }
                // 2. Pull one decoded frame, composite, push to the encoder.
                if (!decodeDone) {
                    val idx = decoder.dequeueOutputBuffer(info, 10_000)
                    if (idx >= 0) {
                        val eos = info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                        val hasFrame = info.size > 0
                        decoder.releaseOutputBuffer(idx, hasFrame)
                        if (hasFrame) {
                            synchronized(frameLock) {
                                var waited = 0L
                                while (!frameAvailable && waited < 3_000) {
                                    frameLock.wait(100)
                                    waited += 100
                                }
                                frameAvailable = false
                            }
                            surfaceTexture.updateTexImage()
                            gl.drawVideo(surfaceTexture, videoTex)
                            gl.drawOverlay(painter.frame(info.presentationTimeUs / 1000))
                            EGLExt.eglPresentationTimeANDROID(
                                egl.display, egl.surface, info.presentationTimeUs * 1000,
                            )
                            egl.swap()
                        }
                        if (eos) {
                            decodeDone = true
                            encoder.signalEndOfInputStream()
                        }
                    }
                }
                // 3. Drain the encoder into the muxer.
                while (true) {
                    val idx = encoder.dequeueOutputBuffer(info, 0)
                    when {
                        idx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                            muxTrack = muxer.addTrack(encoder.outputFormat)
                            muxer.start()
                            muxStarted = true
                        }
                        idx < 0 -> break
                        else -> {
                            val eos = info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                            if (info.size > 0 && muxStarted &&
                                info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG == 0
                            ) {
                                muxer.writeSampleData(
                                    muxTrack, encoder.getOutputBuffer(idx)!!, info,
                                )
                            }
                            encoder.releaseOutputBuffer(idx, false)
                            if (eos) {
                                encodeDone = true
                                break
                            }
                        }
                    }
                }
            }
        } finally {
            try { decoder?.stop(); decoder?.release() } catch (_: Exception) {}
            try { encoder.stop(); encoder.release() } catch (_: Exception) {}
            try { muxer?.stop() } catch (_: Exception) {}
            try { muxer?.release() } catch (_: Exception) {}
            try { extractor.release() } catch (_: Exception) {}
            egl.release()
            callbackThread.quitSafely()
        }
    }
}

/** EGL context + window surface on the encoder's input surface. */
private class EglWindow(windowSurface: Surface) {
    val display: EGLDisplay = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
    private var context: EGLContext
    var surface: EGLSurface

    init {
        val version = IntArray(2)
        check(EGL14.eglInitialize(display, version, 0, version, 1)) { "eglInitialize" }
        val attribs = intArrayOf(
            EGL14.EGL_RED_SIZE, 8,
            EGL14.EGL_GREEN_SIZE, 8,
            EGL14.EGL_BLUE_SIZE, 8,
            EGL14.EGL_ALPHA_SIZE, 8,
            EGL14.EGL_RENDERABLE_TYPE, EGL14.EGL_OPENGL_ES2_BIT,
            0x3142, 1, // EGL_RECORDABLE_ANDROID
            EGL14.EGL_NONE,
        )
        val configs = arrayOfNulls<EGLConfig>(1)
        val num = IntArray(1)
        check(EGL14.eglChooseConfig(display, attribs, 0, configs, 0, 1, num, 0) && num[0] > 0)
        context = EGL14.eglCreateContext(
            display, configs[0], EGL14.EGL_NO_CONTEXT,
            intArrayOf(EGL14.EGL_CONTEXT_CLIENT_VERSION, 2, EGL14.EGL_NONE), 0,
        )
        surface = EGL14.eglCreateWindowSurface(
            display, configs[0], windowSurface, intArrayOf(EGL14.EGL_NONE), 0,
        )
        check(EGL14.eglMakeCurrent(display, surface, surface, context)) { "makeCurrent" }
    }

    fun swap() {
        EGL14.eglSwapBuffers(display, surface)
    }

    fun release() {
        try {
            EGL14.eglMakeCurrent(
                display, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_CONTEXT,
            )
            EGL14.eglDestroySurface(display, surface)
            EGL14.eglDestroyContext(display, context)
            EGL14.eglTerminate(display)
        } catch (_: Exception) {}
    }
}

/** The two draw programs: external video texture, then the overlay bitmap. */
private class GlPrograms(private val width: Int, private val height: Int) {

    private val quad: FloatBuffer = floatBufferOf(
        -1f, -1f, 1f, -1f, -1f, 1f, 1f, 1f,
    )
    // Video texcoords: SurfaceTexture's transform matrix handles flips.
    private val videoTex: FloatBuffer = floatBufferOf(0f, 0f, 1f, 0f, 0f, 1f, 1f, 1f)
    // Overlay bitmap rows start at the TOP — flip V.
    private val overlayTex: FloatBuffer = floatBufferOf(0f, 1f, 1f, 1f, 0f, 0f, 1f, 0f)

    private val videoProgram = buildProgram(
        """
        attribute vec2 aPos; attribute vec2 aTex; varying vec2 vTex;
        uniform mat4 uTexMatrix;
        void main() {
          gl_Position = vec4(aPos, 0.0, 1.0);
          vTex = (uTexMatrix * vec4(aTex, 0.0, 1.0)).xy;
        }
        """,
        """
        #extension GL_OES_EGL_image_external : require
        precision mediump float; varying vec2 vTex;
        uniform samplerExternalOES uTexture;
        void main() { gl_FragColor = texture2D(uTexture, vTex); }
        """,
    )
    private val overlayProgram = buildProgram(
        """
        attribute vec2 aPos; attribute vec2 aTex; varying vec2 vTex;
        void main() { gl_Position = vec4(aPos, 0.0, 1.0); vTex = aTex; }
        """,
        """
        precision mediump float; varying vec2 vTex;
        uniform sampler2D uTexture;
        void main() { gl_FragColor = texture2D(uTexture, vTex); }
        """,
    )
    private val texMatrix = FloatArray(16)
    private var overlayTexId = -1

    fun createExternalTexture(): Int {
        val tex = IntArray(1)
        GLES20.glGenTextures(1, tex, 0)
        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, tex[0])
        setFilters(GLES11Ext.GL_TEXTURE_EXTERNAL_OES)
        return tex[0]
    }

    fun drawVideo(st: SurfaceTexture, texId: Int) {
        st.getTransformMatrix(texMatrix)
        GLES20.glViewport(0, 0, width, height)
        GLES20.glDisable(GLES20.GL_BLEND)
        GLES20.glUseProgram(videoProgram)
        GLES20.glUniformMatrix4fv(
            GLES20.glGetUniformLocation(videoProgram, "uTexMatrix"), 1, false, texMatrix, 0,
        )
        GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, texId)
        drawQuad(videoProgram, videoTex)
    }

    fun drawOverlay(bitmap: Bitmap) {
        if (overlayTexId < 0) {
            val tex = IntArray(1)
            GLES20.glGenTextures(1, tex, 0)
            overlayTexId = tex[0]
            GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, overlayTexId)
            setFilters(GLES20.GL_TEXTURE_2D)
            GLUtils.texImage2D(GLES20.GL_TEXTURE_2D, 0, bitmap, 0)
        } else {
            GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, overlayTexId)
            GLUtils.texSubImage2D(GLES20.GL_TEXTURE_2D, 0, 0, 0, bitmap)
        }
        GLES20.glEnable(GLES20.GL_BLEND)
        // Canvas bitmaps are premultiplied.
        GLES20.glBlendFunc(GLES20.GL_ONE, GLES20.GL_ONE_MINUS_SRC_ALPHA)
        GLES20.glUseProgram(overlayProgram)
        GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
        drawQuad(overlayProgram, overlayTex)
    }

    private fun drawQuad(program: Int, tex: FloatBuffer) {
        val aPos = GLES20.glGetAttribLocation(program, "aPos")
        val aTex = GLES20.glGetAttribLocation(program, "aTex")
        quad.position(0)
        GLES20.glVertexAttribPointer(aPos, 2, GLES20.GL_FLOAT, false, 0, quad)
        GLES20.glEnableVertexAttribArray(aPos)
        tex.position(0)
        GLES20.glVertexAttribPointer(aTex, 2, GLES20.GL_FLOAT, false, 0, tex)
        GLES20.glEnableVertexAttribArray(aTex)
        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
    }

    private fun setFilters(target: Int) {
        GLES20.glTexParameteri(target, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(target, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(target, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE)
        GLES20.glTexParameteri(target, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE)
    }

    private fun buildProgram(vertex: String, fragment: String): Int {
        fun compile(type: Int, src: String): Int {
            val shader = GLES20.glCreateShader(type)
            GLES20.glShaderSource(shader, src)
            GLES20.glCompileShader(shader)
            val ok = IntArray(1)
            GLES20.glGetShaderiv(shader, GLES20.GL_COMPILE_STATUS, ok, 0)
            check(ok[0] != 0) { "shader: " + GLES20.glGetShaderInfoLog(shader) }
            return shader
        }
        val program = GLES20.glCreateProgram()
        GLES20.glAttachShader(program, compile(GLES20.GL_VERTEX_SHADER, vertex))
        GLES20.glAttachShader(program, compile(GLES20.GL_FRAGMENT_SHADER, fragment))
        GLES20.glLinkProgram(program)
        val ok = IntArray(1)
        GLES20.glGetProgramiv(program, GLES20.GL_LINK_STATUS, ok, 0)
        check(ok[0] != 0) { "link: " + GLES20.glGetProgramInfoLog(program) }
        return program
    }

    private fun floatBufferOf(vararg values: Float): FloatBuffer =
        ByteBuffer.allocateDirect(values.size * 4)
            .order(ByteOrder.nativeOrder())
            .asFloatBuffer()
            .apply { put(values); position(0) }
}

/**
 * Draws the overlay for a given clip time into a bitmap in SOURCE pixel
 * space; all layout runs in a 720-wide DISPLAY design grid mapped through a
 * Canvas matrix, so rotated (portrait) video needs no special-casing
 * anywhere else.
 */
private class OverlayPainter(
    timeline: JSONObject,
    srcW: Int,
    srcH: Int,
    rotation: Int,
    private val durationMs: Long,
) {
    private val bitmap = Bitmap.createBitmap(srcW, srcH, Bitmap.Config.ARGB_8888)
    private val canvas = Canvas(bitmap)
    private val displayW: Float
    private val displayH: Float
    private val scale: Float

    private val format = timeline.optString("format", "RANKED")
    private val me = timeline.optString("me", "YOU")
    private val opp = timeline.optString("opp", "")
    private val myLegs = timeline.optInt("myLegs", 0)
    private val oppLegs = timeline.optInt("oppLegs", 0)
    private val legsTarget = timeline.optInt("legsTarget", 2)
    private val startScore = timeline.optInt("startScore", 0)
    private val oppScore = timeline.optInt("oppScore", 0)
    private val handle = timeline.optString("handle", "")
    private val bannerAtMs: Long
    private val bannerText: String
    private val logo: Bitmap? =
        timeline.optString("logoPath", "").takeIf { it.isNotEmpty() }?.let {
            try { BitmapFactory.decodeFile(it) } catch (_: Exception) { null }
        }

    private val fill = Paint(Paint.ANTI_ALIAS_FLAG)
    private val text = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        typeface = Typeface.DEFAULT_BOLD
    }

    companion object {
        private const val BRAND = "DART RIVALS"
        private const val CARD = 0xFF101A2B.toInt()
        private const val PILL = 0xFF0A101C.toInt()
        private const val BG = 0xFF0C1321.toInt()
        private const val BLUE = 0xFF5CA4E6.toInt()
        private const val PINK = 0xFFDC6069.toInt()
        private const val GOLD = 0xFFEAB308.toInt()
        private const val SKY = 0xFF0EA5E9.toInt()
        private const val MUTED = 0xFF8FA0BC.toInt()
    }

    init {
        val rotated = rotation == 90 || rotation == 270
        displayW = (if (rotated) srcH else srcW).toFloat()
        displayH = (if (rotated) srcW else srcH).toFloat()
        scale = displayW / 720f
        // Map display coordinates into the (possibly rotated) source frame,
        // so every draw below can think in upright 720-wide space.
        val m = Matrix()
        when (rotation) {
            90 -> { m.postRotate(-90f); m.postTranslate(0f, srcH.toFloat()) }
            180 -> { m.postRotate(180f); m.postTranslate(srcW.toFloat(), srcH.toFloat()) }
            270 -> { m.postRotate(90f); m.postTranslate(srcW.toFloat(), 0f) }
        }
        canvas.setMatrix(m)

        val banner = timeline.optJSONObject("banner")
        bannerAtMs = banner?.optLong("atMs", -1L) ?: -1L
        bannerText = banner?.optString("text", "") ?: ""
    }

    /** Renders the overlay state at [tMs] and returns the bitmap. */
    fun frame(tMs: Long): Bitmap {
        bitmap.eraseColor(Color.TRANSPARENT)
        drawScoreboard(tMs)
        drawBanner(tMs)
        drawOutro(tMs)
        return bitmap
    }

    private fun s(v: Float) = v * scale

    /**
     * Two facing cards under a centered brand lockup: at feed-thumbnail size
     * a pair of big centered numbers still reads, which the old single-line
     * lower third did not.
     */
    private fun drawScoreboard(tMs: Long) {
        val slide = ease(((tMs - 300) / 500f))
        if (slide <= 0f) return
        val alpha = (slide * 255).toInt()
        val lift = (1f - slide) * s(70f)
        val cardH = s(96f)
        val cardW = (displayW - s(32f) - s(14f)) / 2f
        val cardsTop = displayH - s(84f) - cardH + lift

        drawBrandPill(cardsTop - s(10f), alpha)
        drawCard(s(16f), cardsTop, cardW, cardH, alpha, BLUE, me, myLegs, startScore, true)
        drawCard(
            s(16f) + cardW + s(14f), cardsTop, cardW, cardH, alpha,
            PINK, opp, oppLegs, oppScore, false,
        )
    }

    /**
     * Shield + DART RIVALS + format, centered above the cards: the brand is
     * on screen for the whole clip, not only on the 1.6s end card.
     */
    private fun drawBrandPill(bottom: Float, alpha: Int) {
        val h = s(46f)
        val top = bottom - h
        val shieldH = s(34f)
        val shieldW = logo?.let { shieldH * it.width / it.height } ?: 0f
        text.textAlign = Paint.Align.LEFT
        text.textSize = s(13f)
        text.letterSpacing = 0.12f
        val brandW = text.measureText(BRAND)
        text.textSize = s(11f)
        text.letterSpacing = 0.08f
        val formatW = text.measureText(format)
        text.letterSpacing = 0f
        val gap = if (shieldW > 0f) s(11f) else 0f
        val w = s(36f) + shieldW + gap + kotlin.math.max(brandW, formatW)
        val x = (displayW - w) / 2f
        val pill = RectF(x, top, x + w, top + h)

        fill.shader = null
        fill.style = Paint.Style.FILL
        fill.color = PILL
        fill.alpha = (alpha * 0.95f).toInt()
        canvas.drawRoundRect(pill, h / 2, h / 2, fill)
        fill.style = Paint.Style.STROKE
        fill.strokeWidth = s(1.5f)
        fill.color = Color.WHITE
        fill.alpha = (alpha * 0.14f).toInt()
        canvas.drawRoundRect(pill, h / 2, h / 2, fill)
        fill.style = Paint.Style.FILL

        var tx = x + s(18f)
        logo?.let {
            fill.color = Color.WHITE
            fill.alpha = alpha
            canvas.drawBitmap(
                it, null,
                RectF(tx, top + (h - shieldH) / 2, tx + shieldW, top + (h + shieldH) / 2),
                fill,
            )
            tx += shieldW + gap
        }
        text.color = Color.WHITE
        text.alpha = alpha
        text.textSize = s(13f)
        text.letterSpacing = 0.12f
        canvas.drawText(BRAND, tx, top + s(21f), text)
        text.color = MUTED
        text.alpha = alpha
        text.textSize = s(11f)
        text.letterSpacing = 0.08f
        canvas.drawText(format, tx, top + s(36f), text)
        text.letterSpacing = 0f
    }

    private fun drawCard(
        x: Float, y: Float, w: Float, h: Float, alpha: Int,
        color: Int, name: String, legs: Int, score: Int, mine: Boolean,
    ) {
        val rect = RectF(x, y, x + w, y + h)
        // Clip to the rounded card so the accent keeps the top corners.
        val path = Path().apply { addRoundRect(rect, s(14f), s(14f), Path.Direction.CW) }
        canvas.save()
        canvas.clipPath(path)
        fill.shader = null
        fill.style = Paint.Style.FILL
        fill.color = CARD
        fill.alpha = (alpha * 0.95f).toInt()
        canvas.drawRect(rect, fill)
        fill.color = color
        fill.alpha = alpha
        canvas.drawRect(RectF(x, y, x + w, y + s(4f)), fill)
        canvas.restore()

        val cx = x + w / 2
        text.textAlign = Paint.Align.CENTER
        text.textSize = s(14f)
        text.letterSpacing = 0.1f
        text.color = if (mine) 0xFFE4EDFA.toInt() else MUTED
        text.alpha = alpha
        canvas.drawText(ellipsize(name, w - s(20f)), cx, y + s(25f), text)
        text.letterSpacing = 0f

        text.textSize = s(40f)
        text.color = if (mine) Color.WHITE else 0xFFB9C6DA.toInt()
        text.alpha = alpha
        canvas.drawText(score.toString(), cx, y + s(74f), text)

        // Legs as pips: in a BO3 "one leg left to take" reads without counting.
        val count = legsTarget.coerceIn(1, 5)
        val r = s(4.5f)
        val pipGap = s(6f)
        val totalW = count * 2 * r + (count - 1) * pipGap
        var px = cx - totalW / 2 + r
        for (i in 0 until count) {
            if (i < legs) {
                fill.color = color
                fill.alpha = alpha
            } else {
                fill.color = Color.WHITE
                fill.alpha = (alpha * 0.18f).toInt()
            }
            canvas.drawCircle(px, y + s(86f), r, fill)
            px += 2 * r + pipGap
        }
    }

    /** Truncates with the current text paint — long pseudos must not bleed. */
    private fun ellipsize(value: String, maxWidth: Float): String {
        if (text.measureText(value) <= maxWidth) return value
        var out = value
        while (out.length > 1 && text.measureText("$out…") > maxWidth) {
            out = out.dropLast(1)
        }
        return "$out…"
    }

    private fun drawBanner(tMs: Long) {
        if (bannerAtMs < 0 || tMs < bannerAtMs || tMs > bannerAtMs + 2200) return
        val age = tMs - bannerAtMs
        val inA = ease((age / 250f))
        val outA = if (age > 1950) 1f - (age - 1950) / 250f else 1f
        val alpha = (255 * inA * outA).toInt().coerceIn(0, 255)
        val cy = displayH * 0.42f
        val h = s(130f)
        fill.color = GOLD
        fill.alpha = alpha
        canvas.drawRect(0f, cy - h / 2, displayW, cy + h / 2, fill)
        text.color = 0xFF1A1608.toInt()
        text.alpha = alpha
        text.textAlign = Paint.Align.CENTER
        text.textSize = s(76f) * (0.9f + 0.1f * inA)
        canvas.drawText(bannerText, displayW / 2, cy + s(26f), text)
    }

    private fun drawOutro(tMs: Long) {
        if (durationMs <= 0) return
        val start = durationMs - 1600
        if (tMs < start) return
        val a = ease(((tMs - start) / 350f))
        fill.color = BG
        fill.alpha = (255 * a).toInt()
        canvas.drawRect(0f, 0f, displayW, displayH, fill)
        if (a < 0.6f) return
        val alpha = (255 * (a - 0.6f) / 0.4f).toInt().coerceIn(0, 255)
        val cx = displayW / 2
        val cy = displayH * 0.42f
        fill.shader = RadialGradient(
            cx, cy, s(230f),
            (SKY and 0x00FFFFFF) or (alpha / 4 shl 24), 0x000EA5E9,
            Shader.TileMode.CLAMP,
        )
        canvas.drawCircle(cx, cy, s(230f), fill)
        fill.shader = null
        logo?.let {
            val h = s(170f)
            val w = h * it.width / it.height
            fill.alpha = alpha
            canvas.drawBitmap(
                it, null,
                RectF(cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2), fill,
            )
        }
        text.textAlign = Paint.Align.CENTER
        text.color = Color.WHITE
        text.alpha = alpha
        text.textSize = s(38f)
        text.letterSpacing = 0.12f
        canvas.drawText("DART RIVALS", cx, cy + s(150f), text)
        text.letterSpacing = 0f
        text.color = SKY
        text.alpha = alpha
        text.textSize = s(24f)
        canvas.drawText(handle, cx, cy + s(190f), text)
    }

    private fun ease(t: Float): Float {
        val c = t.coerceIn(0f, 1f)
        return 1f - (1f - c) * (1f - c)
    }
}
