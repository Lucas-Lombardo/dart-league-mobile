import Flutter
import Accelerate

/// Native TFLite inference plugin for iOS.
///
/// Runs the full preprocess + inference pipeline on a high-priority GCD queue
/// so the Flutter UI thread is never blocked.
///
/// Delegate fallback: CoreML (Neural Engine) → Metal (GPU) → CPU 4 threads.
/// Reuses preprocessing buffers across frames to avoid ~16MB of per-frame
/// allocation that was causing iOS to lag behind Android's GPU-delegated path.
///
/// API:
///   loadModel()                      → bool
///   analyze(rgba, width, height)     → {output, xScale, yScale, imageWidth, imageHeight}
class NativeInferencePlugin: NSObject {

    private enum DelegateKind { case coreml, metal, cpu }

    private var interpreter: OpaquePointer?   // TfLiteInterpreter*
    private var model: OpaquePointer?         // TfLiteModel*
    // TfLiteDelegate is a fully-defined struct (see common.h), so Swift maps
    // pointers to it as UnsafeMutablePointer<TfLiteDelegate>, not OpaquePointer.
    private var delegate: UnsafeMutablePointer<TfLiteDelegate>?
    private var delegateKind: DelegateKind = .cpu
    private let inferenceQueue = DispatchQueue(label: "com.dartrivals.tflite", qos: .userInitiated)
    private let modelInputSize = 1024
    private var isBusy = false

    // MARK: - Reusable preprocessing buffers
    // Sized lazily on first frame, reused after. Camera resolution is fixed
    // during a session so allocation only happens once.
    private var bufW: Int = 0
    private var bufH: Int = 0
    private var resizedRGBA: [UInt8] = []
    private var rF: [Float] = []
    private var gF: [Float] = []
    private var bF: [Float] = []
    // Fixed 1024×1024×3 input tensor canvas — always the same size.
    private lazy var inputCanvas: [Float] = [Float](repeating: 0, count: modelInputSize * modelInputSize * 3)

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
            // Optional flag: true when the source bytes are in BGRA order
            // (iOS camera native format). Lets us skip the BGRA→RGBA per-pixel
            // loop on the Dart main isolate and do the channel swap here on
            // the GCD background queue instead.
            let isBgra = (args["isBgra"] as? Bool) ?? false
            guard !isBusy else {
                result(FlutterError(code: "BUSY", message: "Inference in progress", details: nil))
                return
            }
            isBusy = true
            inferenceQueue.async { [weak self] in
                self?.analyze(rgba: rgbaData.data, width: width, height: height, isBgra: isBgra, result: result)
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
        // numThreads applies to any ops the delegate falls back on the CPU
        // for, so it's still useful when a delegate is attached.
        TfLiteInterpreterOptionsSetNumThreads(options, 4)

        // Try CoreML first (Neural Engine on A12+ → fastest path).
        // Falls back to Metal (GPU), then CPU 4 threads.
        if let coreml = createCoreMLDelegate() {
            TfLiteInterpreterOptionsAddDelegate(options, coreml)
            delegate = coreml
            delegateKind = .coreml
            print("[NativeInference-iOS] CoreML delegate enabled")
        } else if let metal = createMetalDelegate() {
            TfLiteInterpreterOptionsAddDelegate(options, metal)
            delegate = metal
            delegateKind = .metal
            print("[NativeInference-iOS] Metal delegate enabled (CoreML unavailable)")
        } else {
            print("[NativeInference-iOS] No GPU/NE delegate — CPU 4 threads")
        }

        interpreter = TfLiteInterpreterCreate(model, options)
        TfLiteInterpreterOptionsDelete(options)

        guard interpreter != nil else {
            TfLiteModelDelete(model); model = nil
            deleteDelegateIfAny()
            result(FlutterError(code: "INTERPRETER_ERROR", message: "TfLiteInterpreterCreate failed", details: nil))
            return
        }

        guard TfLiteInterpreterAllocateTensors(interpreter) == kTfLiteOk else {
            TfLiteInterpreterDelete(interpreter); interpreter = nil
            TfLiteModelDelete(model); model = nil
            deleteDelegateIfAny()
            result(FlutterError(code: "ALLOC_ERROR", message: "AllocateTensors failed", details: nil))
            return
        }

        print("[NativeInference-iOS] Model loaded (delegate=\(delegateKind))")
        result(true)
    }

    private func createCoreMLDelegate() -> UnsafeMutablePointer<TfLiteDelegate>? {
        var opts = TfLiteCoreMlDelegateOptions(
            // AllDevices: also use CoreML on devices without Neural Engine.
            // The delegate transparently runs on CPU/GPU there. Switch to
            // `DevicesWithNeuralEngine` if older-device perf regresses.
            enabled_devices: TfLiteCoreMlDelegateAllDevices,
            coreml_version: 3,
            max_delegated_partitions: 0,
            min_nodes_per_partition: 2
        )
        return TfLiteCoreMlDelegateCreate(&opts)
    }

    private func createMetalDelegate() -> UnsafeMutablePointer<TfLiteDelegate>? {
        // TFLGpuDelegateOptionsDefault() is declared in metal_delegate.h but
        // not exported from the TensorFlowLiteCMetal.framework binary in 2.12.0
        // — calling it produces "Undefined symbol: _TFLGpuDelegateOptionsDefault"
        // at link time. We replicate the documented defaults inline.
        var opts = TFLGpuDelegateOptions(
            allow_precision_loss: true,                      // FP16 (matches Android GPU options)
            wait_type: TFLGpuDelegateWaitTypeActive,         // lowest latency
            enable_quantization: true                         // header default
        )
        return TFLGpuDelegateCreate(&opts)
    }

    private func deleteDelegateIfAny() {
        guard let d = delegate else { return }
        switch delegateKind {
        case .coreml: TfLiteCoreMlDelegateDelete(d)
        case .metal:  TFLGpuDelegateDelete(d)
        case .cpu:    break
        }
        delegate = nil
        delegateKind = .cpu
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

    private func analyze(rgba: Data, width: Int, height: Int, isBgra: Bool = false, result: @escaping FlutterResult) {
        guard let interpreter = interpreter else {
            result(FlutterError(code: "NOT_LOADED", message: "Model not loaded", details: nil))
            return
        }

        let sw = CFAbsoluteTimeGetCurrent()

        // 1. Preprocess RGBA/BGRA → Float32 RGB [1024×1024×3] (into reused inputCanvas)
        preprocess(rgba: rgba, origW: width, origH: height, isBgra: isBgra)
        let preprocessMs = Int((CFAbsoluteTimeGetCurrent() - sw) * 1000)

        // 2. Copy reused canvas to input tensor + invoke
        let inputTensor = TfLiteInterpreterGetInputTensor(interpreter, 0)
        inputCanvas.withUnsafeBytes { buf in
            TfLiteTensorCopyFromBuffer(inputTensor, buf.baseAddress!, buf.count)
        }

        let inferSw = CFAbsoluteTimeGetCurrent()
        guard TfLiteInterpreterInvoke(interpreter) == kTfLiteOk else {
            result(FlutterError(code: "INVOKE_ERROR", message: "Invoke failed", details: nil))
            return
        }
        let inferenceMs = Int((CFAbsoluteTimeGetCurrent() - inferSw) * 1000)

        // 3. Read output tensor. Allocate fresh Data here so the bytes Flutter
        // sends back aren't mutated by a concurrent next-frame inference.
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
        guard interpreter != nil else {
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

    /// Resize RGBA/BGRA to fit 1024×1024 using vImage (hardware-accelerated),
    /// strip alpha, normalize RGB to [0,1] Float32 using vDSP, then interleave
    /// into the reused `inputCanvas` Float32 buffer.
    ///
    /// When `isBgra == true`, the input bytes are read as B,G,R,A and the
    /// channel order is corrected here (no per-pixel work on the Flutter side).
    private func preprocess(rgba: Data, origW: Int, origH: Int, isBgra: Bool = false) {
        let sz = modelInputSize
        let scale = min(Double(sz) / Double(origW), Double(sz) / Double(origH))
        let newW = Int(Double(origW) * scale + 0.5)
        let newH = Int(Double(origH) * scale + 0.5)

        // Reallocate scratch buffers only when the camera resolution changes.
        // In practice this happens once at session start.
        if newW != bufW || newH != bufH {
            bufW = newW
            bufH = newH
            resizedRGBA = [UInt8](repeating: 0, count: newW * newH * 4)
            let pix = newW * newH
            rF = [Float](repeating: 0, count: pix)
            gF = [Float](repeating: 0, count: pix)
            bF = [Float](repeating: 0, count: pix)
        }

        // 1. vImage resize RGBA (hardware-accelerated, no manual loops)
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

        // 2. Strided UInt8 → Float32 for each channel, normalize to [0, 1].
        // BGRA layout: byte 0 = B, byte 1 = G, byte 2 = R, byte 3 = A.
        // RGBA layout: byte 0 = R, byte 1 = G, byte 2 = B, byte 3 = A.
        let pixelCount = newW * newH
        resizedRGBA.withUnsafeBufferPointer { buf in
            let base = buf.baseAddress!
            let rOffset = isBgra ? 2 : 0
            let bOffset = isBgra ? 0 : 2
            vDSP_vfltu8(base + rOffset, 4, &rF, 1, vDSP_Length(pixelCount))
            vDSP_vfltu8(base + 1,       4, &gF, 1, vDSP_Length(pixelCount))
            vDSP_vfltu8(base + bOffset, 4, &bF, 1, vDSP_Length(pixelCount))
        }
        var div: Float = 255.0
        vDSP_vsdiv(rF, 1, &div, &rF, 1, vDSP_Length(pixelCount))
        vDSP_vsdiv(gF, 1, &div, &gF, 1, vDSP_Length(pixelCount))
        vDSP_vsdiv(bF, 1, &div, &bF, 1, vDSP_Length(pixelCount))

        // 3. Interleave R,G,B into 1024×1024×3 canvas (zero-padded on right/bottom).
        // Use raw pointers to skip Swift's bounds-checked subscripting per element.
        let rowFloats = sz * 3
        inputCanvas.withUnsafeMutableBufferPointer { outPtr in
            // Zero pre-existing content only where this frame won't overwrite.
            // Padding columns (x >= newW within first newH rows) and padding
            // rows (y >= newH) need zeros. Simplest correct approach: zero the
            // whole canvas before writing. memset on the underlying floats is
            // ~1ms for 12MB on modern iPhones.
            outPtr.baseAddress!.update(repeating: 0, count: sz * sz * 3)

            rF.withUnsafeBufferPointer { rPtr in
                gF.withUnsafeBufferPointer { gPtr in
                    bF.withUnsafeBufferPointer { bPtr in
                        let rBase = rPtr.baseAddress!
                        let gBase = gPtr.baseAddress!
                        let bBase = bPtr.baseAddress!
                        let outBase = outPtr.baseAddress!
                        for y in 0..<newH {
                            let srcOff = y * newW
                            var dst = outBase + y * rowFloats
                            for x in 0..<newW {
                                let s = srcOff + x
                                dst[0] = rBase[s]
                                dst[1] = gBase[s]
                                dst[2] = bBase[s]
                                dst += 3
                            }
                        }
                    }
                }
            }
        }
    }

    deinit {
        if let i = interpreter { TfLiteInterpreterDelete(i) }
        if let m = model { TfLiteModelDelete(m) }
        deleteDelegateIfAny()
    }
}
