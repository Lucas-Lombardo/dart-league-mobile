import 'dart:io';
import 'dart:typed_data';
import 'package:tflite_flutter/tflite_flutter.dart';

/// DartsMind defaults to CPU with 4 threads (Detector.java line 149:
/// actualDetectorDevice = DetectorDevice.CPU). GPU is only attempted
/// on Android when explicitly requested, and falls back to CPU on failure.
/// iOS Metal delegate crashes with t199/t201 models (EXC_BAD_ACCESS),
/// so we use CPU-only — matching DartsMind's default behaviour.
Future<Interpreter> loadModelNative({bool cpuOnly = false}) async {
  Interpreter? interpreter;

  // Android: try GPU delegate (same as DartsMind updateTensorData$useGPU)
  if (!cpuOnly && Platform.isAndroid) {
    try {
      final gpuOptions = InterpreterOptions()
        ..addDelegate(GpuDelegateV2());
      interpreter = await Interpreter.fromAsset(
        'assets/models/t201.tflite',
        options: gpuOptions,
      );
      print('[DartDetection] Model loaded with GPU delegate');
    } catch (e) {
      print('[DartDetection] GPU delegate failed ($e), falling back to CPU');
      interpreter = null;
    }
  }

  // CPU with 4 threads (DartsMind default: updateTensorData$useCPU)
  if (interpreter == null) {
    final cpuOptions = InterpreterOptions()..threads = 4;
    interpreter = await Interpreter.fromAsset(
      'assets/models/t201.tflite',
      options: cpuOptions,
    );
    print('[DartDetection] Model loaded on CPU with 4 threads');
  }

  return interpreter;
}

Future<Uint8List> readImageBytes(String imagePath) async {
  return await File(imagePath).readAsBytes();
}
