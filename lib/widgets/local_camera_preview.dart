import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'board_safe_video.dart';

/// Local camera preview that adapts to the current device orientation.
/// CameraController reports previewSize in sensor coordinates (typically
/// landscape), so portrait needs the dimensions swapped while landscape uses
/// them natively.
///
/// Sized by [BoardSafeVideo]: the dartboard is never cropped away, and the
/// letterboxing is the minimum that guarantees it.
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
    return BoardSafeVideo(
      sourceWidth: w,
      sourceHeight: h,
      child: CameraPreview(controller),
    );
  }
}
