package com.dartrivals.app

import android.content.Context
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
    private var interpreter: Interpreter? = null

    // DartsMind-style: dedicated executor for inference (like dvExecutor)
    private val dvExecutor: ExecutorService = Executors.newSingleThreadExecutor { r ->
        Thread(r, "dart-tflite-inference").apply { priority = Thread.MAX_PRIORITY }
    }

    @Volatile
    private var detectInProgress = false  // DartsMind: volatile detectInProgress flag

    private val modelInputSize = 1024

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "com.dartrivals/native_inference")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        interpreter?.close()
        interpreter = null
        dvExecutor.shutdown()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "loadModel" -> {
                dvExecutor.execute { loadModel(result) }
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
            val modelBuffer = loadModelFile("assets/models/t201.tflite")
            var interp: Interpreter? = null

            // DartsMind: try GPU first (updateTensorData$useGPU)
            try {
                val gpuDelegate = GpuDelegate()
                val options = Interpreter.Options().addDelegate(gpuDelegate)
                interp = Interpreter(modelBuffer, options)
                println("[NativeInference-Android] Model loaded with GPU delegate")
            } catch (e: Exception) {
                println("[NativeInference-Android] GPU failed (${e.message}), falling back to CPU")
                interp?.close()
                interp = null
            }

            // DartsMind: fallback CPU with 4 threads (updateTensorData$useCPU)
            if (interp == null) {
                val options = Interpreter.Options().setNumThreads(4)
                interp = Interpreter(modelBuffer, options)
                println("[NativeInference-Android] Model loaded on CPU with 4 threads")
            }

            interpreter = interp
            result.success(true)
        } catch (e: Exception) {
            result.error("MODEL_LOAD_ERROR", e.message, null)
        }
    }

    private fun loadModelFile(assetPath: String): MappedByteBuffer {
        val fd = context.assets.openFd(assetPath)
        val inputStream = FileInputStream(fd.fileDescriptor)
        val fileChannel = inputStream.channel
        return fileChannel.map(FileChannel.MapMode.READ_ONLY, fd.startOffset, fd.declaredLength)
    }

    // ---- Inference (DartsMind: dvExecutor thread) ----

    private fun analyze(rgba: ByteArray, width: Int, height: Int, result: MethodChannel.Result) {
        val interp = interpreter
        if (interp == null) {
            result.error("NOT_LOADED", "Model not loaded", null)
            return
        }

        try {
            val startTime = System.currentTimeMillis()

            // 1. Preprocess: RGBA → Float32 RGB [1024×1024×3]
            val inputBuffer = preprocess(rgba, width, height)
            val preprocessMs = System.currentTimeMillis() - startTime

            // 2. Allocate output + run inference
            val outputShape = interp.getOutputTensor(0).shape()
            val outputSize = outputShape.fold(1) { acc, v -> acc * v }
            val outputBuffer = ByteBuffer.allocateDirect(outputSize * 4).order(ByteOrder.nativeOrder())

            val inferStart = System.currentTimeMillis()
            interp.run(inputBuffer, outputBuffer)
            val inferenceMs = System.currentTimeMillis() - inferStart

            val totalMs = System.currentTimeMillis() - startTime
            println("[NativeInference-Android] ${totalMs}ms (preprocess=${preprocessMs} inference=${inferenceMs})")

            // 3. Extract output bytes
            outputBuffer.rewind()
            val outputBytes = ByteArray(outputBuffer.remaining())
            outputBuffer.get(outputBytes)

            // 4. Scale factors
            val xScale: Double = if (width >= height) 1.0 else height.toDouble() / width.toDouble()
            val yScale: Double = if (width >= height) width.toDouble() / height.toDouble() else 1.0

            val response = HashMap<String, Any>()
            response["output"] = outputBytes
            response["xScale"] = xScale
            response["yScale"] = yScale
            response["imageWidth"] = width
            response["imageHeight"] = height

            result.success(response)
        } catch (e: Exception) {
            result.error("INFERENCE_ERROR", e.message, null)
        }
    }

    // ---- File-based Inference (for camera setup) ----

    private fun analyzeFile(path: String, result: MethodChannel.Result) {
        try {
            val bitmap = android.graphics.BitmapFactory.decodeFile(path)
            if (bitmap == null) {
                result.error("FILE_ERROR", "Cannot decode image: $path", null)
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
        } catch (e: Exception) {
            result.error("FILE_ERROR", e.message, null)
        }
    }

    // ---- Preprocessing (DartsMind: convertToInputSizeBitmap) ----

    private fun preprocess(rgba: ByteArray, origW: Int, origH: Int): ByteBuffer {
        val sz = modelInputSize
        val scale = min(sz.toDouble() / origW, sz.toDouble() / origH)
        val newW = (origW * scale + 0.5).roundToInt()
        val newH = (origH * scale + 0.5).roundToInt()

        val srcStride = origW * 4
        val invNewW = origW.toFloat() / newW
        val invNewH = origH.toFloat() / newH

        val buffer = ByteBuffer.allocateDirect(sz * sz * 3 * 4).order(ByteOrder.nativeOrder())
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
        return buffer
    }
}
