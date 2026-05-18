import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

/// Cover-fitted local camera preview that adapts to the current device
/// orientation. CameraController reports previewSize in sensor coordinates
/// (typically landscape), so portrait needs the dimensions swapped while
/// landscape uses them natively.
class LocalCameraPreview extends StatelessWidget {
  final CameraController controller;

  const LocalCameraPreview({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final previewSize = controller.value.previewSize!;
    final w = isLandscape ? previewSize.width : previewSize.height;
    final h = isLandscape ? previewSize.height : previewSize.width;
    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: w,
          height: h,
          child: ClipRect(
            child: OverflowBox(
              maxWidth: w,
              maxHeight: h,
              child: CameraPreview(controller),
            ),
          ),
        ),
      ),
    );
  }
}
