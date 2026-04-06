import Flutter
import Accelerate

/// Native TFLite inference plugin for iOS.
///
/// Runs the full preprocess + inference pipeline on a high-priority GCD queue
/// so the Flutter UI thread is never blocked.
///
/// API:
///   loadModel()                      → bool
///   analyze(rgba, width, height)     → {output, xScale, yScale, imageWidth, imageHeight}
class NativeInferencePlugin: NSObject {

    private var interpreter: OpaquePointer?   // TfLiteInterpreter*
    private var model: OpaquePointer?         // TfLiteModel*
    private let inferenceQueue = DispatchQueue(label: "com.dartrivals.tflite", qos: .userInitiated)
    private let modelInputSize = 1024
    private var isBusy = false

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "loadModel":
            inferenceQueue.async { [weak self] in
                self?.loadModel(result: result)
            }
        case "analyze":
            guard let args = call.arguments as? [String: Any],
                  let rgbaData = args["rgba"] as? FlutterStandardTypedData,
                  let width = args["width"] as? Int,
                  let height = args["height"] as? Int else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing rgba/width/height", details: nil))
                return
            }
            guard !isBusy else {
                result(FlutterError(code: "BUSY", message: "Inference in progress", details: nil))
                return
            }
            isBusy = true
            inferenceQueue.async { [weak self] in
                self?.analyze(rgba: rgbaData.data, width: width, height: height, result: result)
                self?.isBusy = false
            }
        case "analyzeFile":
            guard let path = call.arguments as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "Expected file path string", details: nil))
                return
            }
            guard !isBusy else {
                result(FlutterError(code: "BUSY", message: "Inference in progress", details: nil))
                return
            }
            isBusy = true
            inferenceQueue.async { [weak self] in
                self?.analyzeFile(path: path, result: result)
                self?.isBusy = false
            }
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Model Loading

    private func loadModel(result: @escaping FlutterResult) {
        guard let modelPath = findModelPath() else {
            result(FlutterError(code: "MODEL_NOT_FOUND", message: "t201.tflite not found in bundle", details: nil))
            return
        }

        model = TfLiteModelCreateFromFile(modelPath)
        guard model != nil else {
            result(FlutterError(code: "MODEL_LOAD_ERROR", message: "TfLiteModelCreateFromFile failed", details: nil))
            return
        }

        let options = TfLiteInterpreterOptionsCreate()
        TfLiteInterpreterOptionsSetNumThreads(options, 4)

        interpreter = TfLiteInterpreterCreate(model, options)
        TfLiteInterpreterOptionsDelete(options)

        guard interpreter != nil else {
            TfLiteModelDelete(model); model = nil
            result(FlutterError(code: "INTERPRETER_ERROR", message: "TfLiteInterpreterCreate failed", details: nil))
            return
        }

        guard TfLiteInterpreterAllocateTensors(interpreter) == kTfLiteOk else {
            TfLiteInterpreterDelete(interpreter); interpreter = nil
            TfLiteModelDelete(model); model = nil
            result(FlutterError(code: "ALLOC_ERROR", message: "AllocateTensors failed", details: nil))
            return
        }

        print("[NativeInference-iOS] Model loaded (CPU, 4 threads)")
        result(true)
    }

    private func findModelPath() -> String? {
        // Flutter bundles assets at Frameworks/App.framework/flutter_assets/
        for dir in [
            "Frameworks/App.framework/flutter_assets/assets/models/t201",
            "flutter_assets/assets/models/t201",
            "t201"
        ] {
            if let p = Bundle.main.path(forResource: dir, ofType: "tflite") { return p }
        }
        return nil
    }

    // MARK: - Inference

    private func analyze(rgba: Data, width: Int, height: Int, result: @escaping FlutterResult) {
        guard let interpreter = interpreter else {
            result(FlutterError(code: "NOT_LOADED", message: "Model not loaded", details: nil))
            return
        }

        let sw = CFAbsoluteTimeGetCurrent()

        // 1. Preprocess RGBA → Float32 RGB [1024×1024×3]
        let inputData = preprocess(rgba: rgba, origW: width, origH: height)
        let preprocessMs = Int((CFAbsoluteTimeGetCurrent() - sw) * 1000)
        print("[NativeInference-iOS] preprocess detail: \(preprocessMs)ms for \(width)x\(height) rgba=\(rgba.count) bytes")

        // 2. Copy to input tensor + invoke
        let inputTensor = TfLiteInterpreterGetInputTensor(interpreter, 0)
        inputData.withUnsafeBytes { buf in
            TfLiteTensorCopyFromBuffer(inputTensor, buf.baseAddress!, buf.count)
        }

        let inferSw = CFAbsoluteTimeGetCurrent()
        guard TfLiteInterpreterInvoke(interpreter) == kTfLiteOk else {
            result(FlutterError(code: "INVOKE_ERROR", message: "Invoke failed", details: nil))
            return
        }
        let inferenceMs = Int((CFAbsoluteTimeGetCurrent() - inferSw) * 1000)

        // 3. Read output tensor
        let outputTensor = TfLiteInterpreterGetOutputTensor(interpreter, 0)
        let outputByteSize = TfLiteTensorByteSize(outputTensor)
        var outputData = Data(count: outputByteSize)
        outputData.withUnsafeMutableBytes { buf in
            TfLiteTensorCopyToBuffer(outputTensor, buf.baseAddress!, outputByteSize)
        }

        // 4. Scale factors for coordinate remapping
        let xScale: Double = width >= height ? 1.0 : Double(height) / Double(width)
        let yScale: Double = width >= height ? Double(width) / Double(height) : 1.0

        let totalMs = Int((CFAbsoluteTimeGetCurrent() - sw) * 1000)
        print("[NativeInference-iOS] \(totalMs)ms (preprocess=\(preprocessMs) inference=\(inferenceMs))")

        result([
            "output": FlutterStandardTypedData(bytes: outputData),
            "xScale": xScale,
            "yScale": yScale,
            "imageWidth": width,
            "imageHeight": height,
        ] as [String: Any])
    }

    // MARK: - File-based Inference (for camera setup)

    private func analyzeFile(path: String, result: @escaping FlutterResult) {
        guard let interpreter = interpreter else {
            result(FlutterError(code: "NOT_LOADED", message: "Model not loaded", details: nil))
            return
        }
        guard let imageData = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let uiImage = UIImage(data: imageData),
              let cgImage = uiImage.cgImage else {
            result(FlutterError(code: "FILE_ERROR", message: "Cannot read image: \(path)", details: nil))
            return
        }

        let width = cgImage.width
        let height = cgImage.height

        // Render CGImage to RGBA buffer
        let bytesPerRow = width * 4
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &rgba, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            result(FlutterError(code: "DECODE_ERROR", message: "Cannot create bitmap context", details: nil))
            return
        }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        let rgbaData = Data(rgba)
        analyze(rgba: rgbaData, width: width, height: height, result: result)
    }

    // MARK: - Preprocessing (vImage resize + vDSP normalize)

    /// Resize RGBA to fit 1024×1024 using vImage (hardware-accelerated),
    /// strip alpha, normalize RGB to [0,1] Float32 using vDSP.
    /// Fast even in debug builds because vImage/vDSP are pre-compiled system libraries.
    private func preprocess(rgba: Data, origW: Int, origH: Int) -> Data {
        let sz = modelInputSize
        let scale = min(Double(sz) / Double(origW), Double(sz) / Double(origH))
        let newW = Int(Double(origW) * scale + 0.5)
        let newH = Int(Double(origH) * scale + 0.5)

        // 1. vImage resize RGBA (hardware-accelerated, no manual loops)
        var resizedRGBA = [UInt8](repeating: 0, count: newW * newH * 4)
        rgba.withUnsafeBytes { srcBuf in
            guard let srcPtr = srcBuf.baseAddress else { return }
            var srcBuffer = vImage_Buffer(
                data: UnsafeMutableRawPointer(mutating: srcPtr),
                height: vImagePixelCount(origH),
                width: vImagePixelCount(origW),
                rowBytes: origW * 4
            )
            resizedRGBA.withUnsafeMutableBytes { dstBuf in
                var dstBuffer = vImage_Buffer(
                    data: dstBuf.baseAddress!,
                    height: vImagePixelCount(newH),
                    width: vImagePixelCount(newW),
                    rowBytes: newW * 4
                )
                vImageScale_ARGB8888(&srcBuffer, &dstBuffer, nil, vImage_Flags(kvImageNoFlags))
            }
        }

        // 2. Strip alpha: RGBA → contiguous RGB UInt8
        //    Use vDSP to convert to Float and normalize in one pass
        let pixelCount = newW * newH
        let rgbCount = pixelCount * 3
        var rgbU8 = [UInt8](repeating: 0, count: rgbCount)

        // Planar extraction (no per-pixel loop — just stride-copy via vDSP)
        // RGBA layout: [R,G,B,A, R,G,B,A, ...] — extract R,G,B with stride 4
        var rF = [Float](repeating: 0, count: pixelCount)
        var gF = [Float](repeating: 0, count: pixelCount)
        var bF = [Float](repeating: 0, count: pixelCount)
        resizedRGBA.withUnsafeBufferPointer { buf in
            let base = buf.baseAddress!
            // Convert strided UInt8 channels directly to Float32
            vDSP_vfltu8(base,       4, &rF, 1, vDSP_Length(pixelCount))  // R (stride 4)
            vDSP_vfltu8(base + 1,   4, &gF, 1, vDSP_Length(pixelCount))  // G
            vDSP_vfltu8(base + 2,   4, &bF, 1, vDSP_Length(pixelCount))  // B
        }
        var div: Float = 255.0
        vDSP_vsdiv(rF, 1, &div, &rF, 1, vDSP_Length(pixelCount))
        vDSP_vsdiv(gF, 1, &div, &gF, 1, vDSP_Length(pixelCount))
        vDSP_vsdiv(bF, 1, &div, &bF, 1, vDSP_Length(pixelCount))

        // 3. Interleave R,G,B into 1024×1024×3 canvas (zero-padded)
        let totalFloats = sz * sz * 3
        var output = [Float](repeating: 0, count: totalFloats)

        for y in 0..<newH {
            let srcOff = y * newW
            let dstOff = y * sz * 3
            for x in 0..<newW {
                let si = srcOff + x
                let di = dstOff + x * 3
                output[di]     = rF[si]
                output[di + 1] = gF[si]
                output[di + 2] = bF[si]
            }
        }

        return output.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    deinit {
        if let i = interpreter { TfLiteInterpreterDelete(i) }
        if let m = model { TfLiteModelDelete(m) }
    }
}
