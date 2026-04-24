package com.dartrivals.app

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Paint
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.tensorflow.lite.Interpreter
import org.tensorflow.lite.gpu.GpuDelegate
import java.io.FileInputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.MappedByteBuffer
import java.nio.channels.FileChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * Native TFLite inference plugin for Android.
 *
 * DartsMind-style architecture:
 * - ExecutorService thread pool for inference (like dvExecutor)
 * - GPU delegate first, fallback to CPU with 4 threads
 * - volatile busy flag for thread safety (like detectInProgress)
 *
 * API (same as iOS):
 *   loadModel()                      → bool
 *   analyze(rgba, width, height)     → {output, xScale, yScale, imageWidth, imageHeight}
 */
class NativeInferencePlugin : FlutterPlugin, MethodChannel.MethodCallHandler {

    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private lateinit var flutterAssets: FlutterPlugin.FlutterAssets
    private var interpreter: Interpreter? = null

    // Handler for posting results back to the main/UI thread.
    // MethodChannel.Result must be called on the platform thread.
    private val mainHandler = Handler(Looper.getMainLooper())

    // DartsMind-style: dedicated executor for inference (like dvExecutor)
    private val dvExecutor: ExecutorService = Executors.newSingleThreadExecutor { r ->
        Thread(r, "dart-tflite-inference").apply { priority = Thread.MAX_PRIORITY }
    }

    @Volatile
    private var detectInProgress = false  // DartsMind: volatile detectInProgress flag

    private val modelInputSize = 1024

    // ---- Reusable inference buffers (allocated once) ----
    // Per-frame allocation of these was the #1 cause of the 800ms GC-bound stall.
    // Input tensor buffer: 1024 * 1024 * 3 * 4 = 12MB direct, sized for modelInputSize.
    private var inputBuffer: ByteBuffer? = null
    private var outputBuffer: ByteBuffer? = null
    private var outputElementCount: Int = 0
    // Reusable 1024x1024 IntArray for pulling pixels out of squareBitmap
    private val tensorPixels: IntArray = IntArray(modelInputSize * modelInputSize)

    // ---- Reusable raw-frame buffers (sized to the camera frame) ----
    // rawBitmap keeps ARGB_8888 pixels of the incoming YUV frame; re-created only
    // if the camera frame size changes.
    private var rawBitmap: Bitmap? = null
    private var rawPixels: IntArray? = null
    private var rawBitmapWidth = 0
    private var rawBitmapHeight = 0

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        flutterAssets = binding.flutterAssets
        channel = MethodChannel(binding.binaryMessenger, "com.dartrivals/native_inference")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        interpreter?.close()
        interpreter = null
        squareBitmap.recycle()
        rawBitmap?.recycle()
        rawBitmap = null
        rawPixels = null
        inputBuffer = null
        outputBuffer = null
        dvExecutor.shutdown()
    }

    // Allocate input/output ByteBuffers once the interpreter is ready.
    // Called from loadModel / loadModelFromFile after the interpreter is built.
    private fun prepareTensorBuffers(interp: Interpreter) {
        val sz = modelInputSize
        if (inputBuffer == null) {
            inputBuffer = ByteBuffer.allocateDirect(sz * sz * 3 * 4).order(ByteOrder.nativeOrder())
        }
        val outputShape = interp.getOutputTensor(0).shape()
        val elems = outputShape.fold(1) { acc, v -> acc * v }
        if (outputBuffer == null || elems != outputElementCount) {
            outputBuffer = ByteBuffer.allocateDirect(elems * 4).order(ByteOrder.nativeOrder())
            outputElementCount = elems
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "loadModel" -> {
                dvExecutor.execute { loadModel(result) }
            }
            "loadModelFile" -> {
                val path = call.arguments as? String
                if (path == null) {
                    result.error("INVALID_ARGS", "Expected file path string", null)
                    return
                }
                dvExecutor.execute { loadModelFromFile(path, result) }
            }
            "analyze" -> {
                val rgba = call.argument<ByteArray>("rgba")
                val width = call.argument<Int>("width")
                val height = call.argument<Int>("height")
                if (rgba == null || width == null || height == null) {
                    result.error("INVALID_ARGS", "Missing rgba/width/height", null)
                    return
                }
                if (detectInProgress) {
                    result.error("BUSY", "Inference in progress", null)
                    return
                }
                detectInProgress = true
                dvExecutor.execute {
                    try {
                        analyze(rgba, width, height, result)
                    } finally {
                        detectInProgress = false
                    }
                }
            }
            "analyzeYuv" -> {
                val yPlane = call.argument<ByteArray>("yPlane")
                val uPlane = call.argument<ByteArray>("uPlane")
                val vPlane = call.argument<ByteArray>("vPlane")
                val width = call.argument<Int>("width")
                val height = call.argument<Int>("height")
                val yRowStride = call.argument<Int>("yRowStride")
                val uvRowStride = call.argument<Int>("uvRowStride")
                val uvPixelStride = call.argument<Int>("uvPixelStride")
                val rotation = call.argument<Int>("rotation") ?: 0
                if (yPlane == null || uPlane == null || vPlane == null ||
                    width == null || height == null ||
                    yRowStride == null || uvRowStride == null || uvPixelStride == null) {
                    result.error("INVALID_ARGS", "Missing YUV plane data", null)
                    return
                }
                if (detectInProgress) {
                    result.error("BUSY", "Inference in progress", null)
                    return
                }
                detectInProgress = true
                dvExecutor.execute {
                    try {
                        analyzeYuv(yPlane, uPlane, vPlane, width, height,
                            yRowStride, uvRowStride, uvPixelStride, rotation, result)
                    } finally {
                        detectInProgress = false
                    }
                }
            }
            "analyzeFile" -> {
                val path = call.arguments as? String
                if (path == null) {
                    result.error("INVALID_ARGS", "Expected file path string", null)
                    return
                }
                if (detectInProgress) {
                    result.error("BUSY", "Inference in progress", null)
                    return
                }
                detectInProgress = true
                dvExecutor.execute {
                    try {
                        analyzeFile(path, result)
                    } finally {
                        detectInProgress = false
                    }
                }
            }
            else -> result.notImplemented()
        }
    }

    // ---- Model Loading (DartsMind: Detector.updateTensorData) ----

    private fun loadModel(result: MethodChannel.Result) {
        try {
            // Use FlutterAssets to get the correct path inside the APK.
            // Flutter bundles assets under "flutter_assets/" prefix — the raw
            // pubspec key "assets/models/t201.tflite" doesn't work with
            // Android's AssetManager directly.
            val assetKey = flutterAssets.getAssetFilePathBySubpath("assets/models/t201.tflite")
            android.util.Log.d("NativeInference", "Loading model from asset key: $assetKey")
            val modelBuffer = loadModelFile(assetKey)
            android.util.Log.d("NativeInference", "Model file loaded, size=${modelBuffer.capacity()} bytes")
            var interp: Interpreter? = null

            // DartsMind: try GPU first (updateTensorData$useGPU)
            // Match DartsMind's GpuDelegateFactory.Options exactly:
            //   precisionLossAllowed = true (enables FP16 for speed)
            //   inferencePreference = 0 (INFERENCE_PREFERENCE_FAST_SINGLE_ANSWER)
            try {
                val gpuOptions = GpuDelegate.Options()
                gpuOptions.setPrecisionLossAllowed(true)
                gpuOptions.setInferencePreference(0) // FAST_SINGLE_ANSWER
                val gpuDelegate = GpuDelegate(gpuOptions)
                val options = Interpreter.Options().addDelegate(gpuDelegate)
                interp = Interpreter(modelBuffer, options)
                android.util.Log.d("NativeInference", "Model loaded with GPU delegate")
            } catch (t: Throwable) {
                // Catch Throwable (not just Exception) to handle NoClassDefFoundError,
                // UnsatisfiedLinkError, etc. that R8/ProGuard stripping can cause.
                android.util.Log.w("NativeInference", "GPU failed: ${t.javaClass.simpleName}: ${t.message}")
                interp?.close()
                interp = null
            }

            // DartsMind: fallback CPU with 4 threads (updateTensorData$useCPU)
            if (interp == null) {
                val options = Interpreter.Options().setNumThreads(4)
                interp = Interpreter(modelBuffer, options)
                android.util.Log.d("NativeInference", "Model loaded on CPU with 4 threads")
            }

            interpreter = interp
            prepareTensorBuffers(interp)
            mainHandler.post { result.success(true) }
        } catch (t: Throwable) {
            // Catch Throwable to handle ALL errors including NoClassDefFoundError,
            // UnsatisfiedLinkError, native crashes during Interpreter creation, etc.
            android.util.Log.e("NativeInference", "Model load failed: ${t.javaClass.simpleName}: ${t.message}", t)
            mainHandler.post { result.error("MODEL_LOAD_ERROR", "${t.javaClass.simpleName}: ${t.message}", null) }
        }
    }

    private fun loadModelFile(assetPath: String): MappedByteBuffer {
        val fd = context.assets.openFd(assetPath)
        val inputStream = FileInputStream(fd.fileDescriptor)
        val fileChannel = inputStream.channel
        return fileChannel.map(FileChannel.MapMode.READ_ONLY, fd.startOffset, fd.declaredLength)
    }

    /// Load model from a file path (used on Android where Dart extracts the
    /// asset to a temp file to avoid AssetManager path issues).
    private fun loadModelFromFile(path: String, result: MethodChannel.Result) {
        try {
            val file = java.io.File(path)
            android.util.Log.d("NativeInference", "Loading model from file: $path (${file.length()} bytes)")
            val inputStream = FileInputStream(file)
            val fileChannel = inputStream.channel
            val modelBuffer = fileChannel.map(FileChannel.MapMode.READ_ONLY, 0, file.length())
            fileChannel.close()
            inputStream.close()
            var interp: Interpreter? = null

            // DartsMind: try GPU first (updateTensorData$useGPU)
            try {
                val gpuOptions = GpuDelegate.Options()
                gpuOptions.setPrecisionLossAllowed(true)
                gpuOptions.setInferencePreference(0) // FAST_SINGLE_ANSWER
                val gpuDelegate = GpuDelegate(gpuOptions)
                val options = Interpreter.Options().addDelegate(gpuDelegate)
                interp = Interpreter(modelBuffer, options)
                android.util.Log.d("NativeInference", "Model loaded with GPU delegate")
            } catch (t: Throwable) {
                android.util.Log.w("NativeInference", "GPU failed: ${t.javaClass.simpleName}: ${t.message}")
                interp?.close()
                interp = null
            }

            // DartsMind: fallback CPU with 4 threads (updateTensorData$useCPU)
            if (interp == null) {
                val options = Interpreter.Options().setNumThreads(4)
                interp = Interpreter(modelBuffer, options)
                android.util.Log.d("NativeInference", "Model loaded on CPU with 4 threads")
            }

            interpreter = interp
            prepareTensorBuffers(interp)
            mainHandler.post { result.success(true) }
        } catch (t: Throwable) {
            android.util.Log.e("NativeInference", "Model load from file failed: ${t.javaClass.simpleName}: ${t.message}", t)
            mainHandler.post { result.error("MODEL_LOAD_ERROR", "${t.javaClass.simpleName}: ${t.message}", null) }
        }
    }

    // ---- Inference (DartsMind: dvExecutor thread) ----

    private fun analyze(rgba: ByteArray, width: Int, height: Int, result: MethodChannel.Result) {
        val interp = interpreter
        if (interp == null) {
            mainHandler.post { result.error("NOT_LOADED", "Model not loaded", null) }
            return
        }

        try {
            val startTime = System.currentTimeMillis()

            // 1. Preprocess: RGBA → Float32 RGB [1024×1024×3]
            val inBuf = inputBuffer ?: ByteBuffer.allocateDirect(modelInputSize * modelInputSize * 3 * 4).order(ByteOrder.nativeOrder()).also { inputBuffer = it }
            val outBuf = outputBuffer ?: run {
                prepareTensorBuffers(interp)
                outputBuffer!!
            }
            preprocess(rgba, width, height, inBuf)
            val preprocessMs = System.currentTimeMillis() - startTime

            // 2. Run inference into reused output buffer
            outBuf.rewind()
            val inferStart = System.currentTimeMillis()
            interp.run(inBuf, outBuf)
            val inferenceMs = System.currentTimeMillis() - inferStart

            val totalMs = System.currentTimeMillis() - startTime
            println("[NativeInference-Android] ${totalMs}ms (preprocess=${preprocessMs} inference=${inferenceMs})")

            // 3. Extract output bytes
            outBuf.rewind()
            val outputBytes = ByteArray(outBuf.remaining())
            outBuf.get(outputBytes)

            // 4. Scale factors
            val xScale: Double = if (width >= height) 1.0 else height.toDouble() / width.toDouble()
            val yScale: Double = if (width >= height) width.toDouble() / height.toDouble() else 1.0

            val response = HashMap<String, Any>()
            response["output"] = outputBytes
            response["xScale"] = xScale
            response["yScale"] = yScale
            response["imageWidth"] = width
            response["imageHeight"] = height

            mainHandler.post { result.success(response) }
        } catch (e: Throwable) {
            mainHandler.post { result.error("INFERENCE_ERROR", e.message, null) }
        }
    }

    // ---- YUV Inference (DartsMind: ZLVideoCapture → Detector.detectVideoBuffer) ----

    // Reusable objects for convertToInputSizeBitmap (DartsMind: Detector fields)
    private var squareBitmap: Bitmap = Bitmap.createBitmap(1024, 1024, Bitmap.Config.ARGB_8888)
    private var squareCanvas: Canvas = Canvas(squareBitmap)
    private val scalePaint: Paint = Paint().apply {
        // Bilinear filtering matches DartsMind's Bitmap.createBitmap(..., matrix, filter=true).
        // Essential: tip positions must be stable across frames for the TipGroup
        // merge threshold (1.6px) — nearest-neighbor would cause jitter.
        isFilterBitmap = true
    }
    private val scaleMatrix: Matrix = Matrix()
    private var lastBitmapWidth = 0
    private var lastBitmapHeight = 0
    private var cachedRotation = Int.MIN_VALUE

    /**
     * DartsMind-style YUV→Bitmap→rotation→scale→inference pipeline.
     *
     * Matches DartsMind exactly:
     * 1. YUV → Bitmap (like imageProxy.toBitmap())
     * 2. Matrix.postRotate(rotationDegrees) with filter=true (bilinear)
     * 3. convertToInputSizeBitmap: Canvas + Matrix scale to 1024×1024
     * 4. Bitmap pixels → normalized Float32 tensor
     * 5. TFLite inference
     *
     * Using Bitmap APIs for rotation + scaling ensures bilinear interpolation,
     * which produces stable tip positions across frames (critical for TipGroup
     * merge threshold of 1.6px).
     */
    private fun analyzeYuv(
        yPlane: ByteArray, uPlane: ByteArray, vPlane: ByteArray,
        width: Int, height: Int,
        yRowStride: Int, uvRowStride: Int, uvPixelStride: Int,
        rotation: Int, result: MethodChannel.Result
    ) {
        val interp = interpreter
        if (interp == null) {
            mainHandler.post { result.error("NOT_LOADED", "Model not loaded", null) }
            return
        }

        try {
            val startTime = System.currentTimeMillis()

            // Step 1: YUV → ARGB Bitmap using integer math (BT.601).
            // Writes into reused IntArray + reused rawBitmap (no per-frame Bitmap.createBitmap).
            if (rawBitmap == null || rawBitmapWidth != width || rawBitmapHeight != height) {
                rawBitmap?.recycle()
                rawBitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                rawPixels = IntArray(width * height)
                rawBitmapWidth = width
                rawBitmapHeight = height
            }
            val pixels = rawPixels!!
            val bmp = rawBitmap!!
            yuvToArgbInt(
                yPlane, uPlane, vPlane, width, height,
                yRowStride, uvRowStride, uvPixelStride,
                pixels
            )
            bmp.setPixels(pixels, 0, width, 0, 0, width, height)

            // Step 2: Combined rotate + scale matrix draws directly into squareBitmap
            // — eliminates the intermediate rotatedBitmap (and its 3-4MB allocation).
            val sz = modelInputSize
            val bw: Int
            val bh: Int
            when (rotation % 360) {
                90, 270 -> { bw = height; bh = width }
                else -> { bw = width; bh = height }
            }
            squareCanvas.drawColor(Color.BLACK)
            if (rotation != cachedRotation || bw != lastBitmapWidth || bh != lastBitmapHeight) {
                cachedRotation = rotation
                lastBitmapWidth = bw
                lastBitmapHeight = bh
                val s = min(sz.toFloat() / bw, sz.toFloat() / bh)
                scaleMatrix.reset()
                // Rotate around origin, then translate back into positive quadrant,
                // then scale to fit into the 1024x1024 square.
                when (rotation % 360) {
                    90  -> { scaleMatrix.postRotate(90f);  scaleMatrix.postTranslate(height.toFloat(), 0f) }
                    180 -> { scaleMatrix.postRotate(180f); scaleMatrix.postTranslate(width.toFloat(), height.toFloat()) }
                    270 -> { scaleMatrix.postRotate(270f); scaleMatrix.postTranslate(0f, width.toFloat()) }
                    else -> { /* identity */ }
                }
                scaleMatrix.postScale(s, s)
            }
            squareCanvas.drawBitmap(bmp, scaleMatrix, scalePaint)
            val preprocessMs = System.currentTimeMillis() - startTime

            // Step 3: Bitmap pixels → normalized Float32 RGB tensor, into REUSED inputBuffer
            squareBitmap.getPixels(tensorPixels, 0, sz, 0, 0, sz, sz)
            val inBuf = inputBuffer ?: ByteBuffer.allocateDirect(sz * sz * 3 * 4).order(ByteOrder.nativeOrder()).also { inputBuffer = it }
            val outBuf = outputBuffer ?: run { prepareTensorBuffers(interp); outputBuffer!! }
            inBuf.rewind()
            val floatBuffer = inBuf.asFloatBuffer()
            val n = sz * sz
            var i = 0
            while (i < n) {
                val p = tensorPixels[i]
                floatBuffer.put(((p shr 16) and 0xFF) / 255.0f)
                floatBuffer.put(((p shr 8) and 0xFF) / 255.0f)
                floatBuffer.put((p and 0xFF) / 255.0f)
                i++
            }
            inBuf.rewind()

            // Step 4: Run TFLite inference into reused output buffer
            outBuf.rewind()
            val inferStart = System.currentTimeMillis()
            interp.run(inBuf, outBuf)
            val inferenceMs = System.currentTimeMillis() - inferStart

            val totalMs = System.currentTimeMillis() - startTime
            println("[NativeInference-Android] YUV-Bitmap: ${totalMs}ms (preprocess=${preprocessMs} inference=${inferenceMs})")

            outBuf.rewind()
            val outputBytes = ByteArray(outBuf.remaining())
            outBuf.get(outputBytes)

            // Scale factors based on rotated dimensions (DartsMind: Detector.detectVideoBuffer)
            val xScale: Double = if (bw >= bh) 1.0 else bh.toDouble() / bw.toDouble()
            val yScale: Double = if (bw >= bh) bw.toDouble() / bh.toDouble() else 1.0

            val response = HashMap<String, Any>()
            response["output"] = outputBytes
            response["xScale"] = xScale
            response["yScale"] = yScale
            response["imageWidth"] = bw
            response["imageHeight"] = bh

            mainHandler.post { result.success(response) }
        } catch (e: Throwable) {
            mainHandler.post { result.error("INFERENCE_ERROR", e.message, null) }
        }
    }

    // ---- File-based Inference (for camera setup) ----

    private fun analyzeFile(path: String, result: MethodChannel.Result) {
        try {
            val bitmap = android.graphics.BitmapFactory.decodeFile(path)
            if (bitmap == null) {
                mainHandler.post { result.error("FILE_ERROR", "Cannot decode image: $path", null) }
                return
            }
            val width = bitmap.width
            val height = bitmap.height
            val pixels = IntArray(width * height)
            bitmap.getPixels(pixels, 0, width, 0, 0, width, height)
            bitmap.recycle()

            // Convert ARGB int array to RGBA byte array
            val rgba = ByteArray(width * height * 4)
            for (i in pixels.indices) {
                val px = pixels[i]
                val off = i * 4
                rgba[off]     = ((px shr 16) and 0xFF).toByte() // R
                rgba[off + 1] = ((px shr 8) and 0xFF).toByte()  // G
                rgba[off + 2] = (px and 0xFF).toByte()           // B
                rgba[off + 3] = ((px shr 24) and 0xFF).toByte() // A
            }

            analyze(rgba, width, height, result)
        } catch (e: Throwable) {
            mainHandler.post { result.error("FILE_ERROR", e.message, null) }
        }
    }

    // ---- Preprocessing (DartsMind: convertToInputSizeBitmap) ----

    private fun preprocess(rgba: ByteArray, origW: Int, origH: Int, buffer: ByteBuffer) {
        val sz = modelInputSize
        val scale = min(sz.toDouble() / origW, sz.toDouble() / origH)
        val newW = (origW * scale + 0.5).roundToInt()
        val newH = (origH * scale + 0.5).roundToInt()

        val srcStride = origW * 4
        val invNewW = origW.toFloat() / newW
        val invNewH = origH.toFloat() / newH

        buffer.rewind()
        val floatBuffer = buffer.asFloatBuffer()

        for (y in 0 until sz) {
            if (y >= newH) {
                // Black padding rows
                for (x in 0 until sz * 3) floatBuffer.put(0.0f)
                continue
            }
            val srcY = min((y * invNewH).toInt(), origH - 1)
            val rowOffset = srcY * srcStride

            for (x in 0 until sz) {
                if (x >= newW) {
                    floatBuffer.put(0.0f); floatBuffer.put(0.0f); floatBuffer.put(0.0f)
                    continue
                }
                val srcX = min((x * invNewW).toInt(), origW - 1)
                val pxOff = rowOffset + srcX * 4
                floatBuffer.put((rgba[pxOff].toInt() and 0xFF) / 255.0f)
                floatBuffer.put((rgba[pxOff + 1].toInt() and 0xFF) / 255.0f)
                floatBuffer.put((rgba[pxOff + 2].toInt() and 0xFF) / 255.0f)
            }
        }

        buffer.rewind()
    }

    /**
     * Fast integer YUV420 → ARGB_8888 converter (BT.601 JFIF / full-range).
     *
     * Writes one 0xAARRGGBB int per pixel into [out]. [out] must have capacity
     * width*height. Uses 8-bit fixed-point integer math + shifts — no floats,
     * no allocations, no per-pixel bounds-checked array lookups beyond the
     * unavoidable plane reads.
     *
     * The coefficients match the original per-pixel float formulas exactly,
     * scaled by 256 and rounded so detection output is identical:
     *   R = y + 1.370705 (v-128)  →  y + ((351  v + 128) >> 8)
     *   G = y - 0.337633 (u-128) - 0.698001 (v-128)
     *                            →  y - (( 86  u + 179  v + 128) >> 8)
     *   B = y + 1.732446 (u-128)  →  y + ((443  u + 128) >> 8)
     * where u = U - 128, v = V - 128.
     *
     * This replaces the per-frame manual float loop that was taking ~600ms
     * and causing "Image buffer was dropped by garbage collector" log lines.
     */
    private fun yuvToArgbInt(
        yPlane: ByteArray, uPlane: ByteArray, vPlane: ByteArray,
        width: Int, height: Int,
        yRowStride: Int, uvRowStride: Int, uvPixelStride: Int,
        out: IntArray
    ) {
        var dstIdx = 0
        var sy = 0
        while (sy < height) {
            val yRowBase = sy * yRowStride
            val uvRowBase = (sy shr 1) * uvRowStride
            var sx = 0
            while (sx < width) {
                val yVal = yPlane[yRowBase + sx].toInt() and 0xFF
                val uvIdx = uvRowBase + (sx shr 1) * uvPixelStride
                val u = (uPlane[uvIdx].toInt() and 0xFF) - 128
                val v = (vPlane[uvIdx].toInt() and 0xFF) - 128

                var r = yVal + ((351 * v + 128) shr 8)
                var g = yVal - ((86 * u + 179 * v + 128) shr 8)
                var b = yVal + ((443 * u + 128) shr 8)
                if (r < 0) r = 0 else if (r > 255) r = 255
                if (g < 0) g = 0 else if (g > 255) g = 255
                if (b < 0) b = 0 else if (b > 255) b = 255

                out[dstIdx] = (0xFF shl 24) or (r shl 16) or (g shl 8) or b
                dstIdx++
                sx++
            }
            sy++
        }
    }
}
