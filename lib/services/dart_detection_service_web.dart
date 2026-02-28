import 'dart:typed_data';
import 'package:tflite_flutter/tflite_flutter.dart';

Future<Interpreter> loadModelNative({bool cpuOnly = false}) async {
  throw UnsupportedError('loadModelNative should not be called on web');
}

Future<Uint8List> readImageBytes(String imagePath) async {
  throw UnsupportedError('File reading not supported on web platform');
}
