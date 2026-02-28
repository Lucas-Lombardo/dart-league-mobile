import 'dart:io';
import 'dart:typed_data';
import 'package:tflite_flutter/tflite_flutter.dart';

Future<Interpreter> loadModelNative({bool cpuOnly = false}) async {
  Interpreter? interpreter;

  // Use Metal GPU on iOS, GPU on Android, fallback to CPU with threads
  if (!cpuOnly && Platform.isIOS) {
    try {
      final gpuOptions = InterpreterOptions()
        ..addDelegate(GpuDelegate());
      interpreter = await Interpreter.fromAsset(
        'assets/models/best_float16.tflite',
        options: gpuOptions,
      );
      print('[DartDetection] Model loaded with Metal GPU delegate');
    } catch (e) {
      print('[DartDetection] Metal GPU failed ($e), falling back to CPU');
      interpreter = null;
    }
  } else if (!cpuOnly && Platform.isAndroid) {
    try {
      final gpuOptions = InterpreterOptions()
        ..addDelegate(GpuDelegateV2());
      interpreter = await Interpreter.fromAsset(
        'assets/models/best_float16.tflite',
        options: gpuOptions,
      );
      print('[DartDetection] Model loaded with GPU delegate');
    } catch (e) {
      print('[DartDetection] GPU delegate failed ($e), falling back to CPU');
      interpreter = null;
    }
  }

  // Fallback: CPU with multi-threading
  if (interpreter == null) {
    final cpuOptions = InterpreterOptions()..threads = 4;
    interpreter = await Interpreter.fromAsset(
      'assets/models/best_float16.tflite',
      options: cpuOptions,
    );
    print('[DartDetection] Model loaded on CPU with 4 threads');
  }

  return interpreter;
}

Future<Uint8List> readImageBytes(String imagePath) async {
  return await File(imagePath).readAsBytes();
}
