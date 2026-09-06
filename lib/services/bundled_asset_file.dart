import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Copy a bundled asset to the temp directory and return the file — the way
/// Android gets a model (or a reference image) to the native plugin, which
/// cannot resolve Flutter asset keys through AssetManager reliably.
///
/// One file per asset basename, written once and reused: the native side
/// keys its "same model — reusing" shortcut on the PATH, so every caller
/// that wants the same asset must land on the same file.
Future<File> bundledAssetToTempFile(String asset) async {
  final data = await rootBundle.load(asset);
  final tempDir = await getTemporaryDirectory();
  final file = File('${tempDir.path}/${asset.split('/').last}');
  if (!file.existsSync()) {
    await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
  }
  return file;
}
