import 'package:permission_handler/permission_handler.dart';

/// Camera + microphone permissions for the match video call.
///
class MediaPermissions {
  /// Requests both permissions and reports whether BOTH were granted — a call
  /// with only one of the two is not something the game screen can start.
  static Future<bool> requestCameraAndMic() async {
    try {
      final statuses = await [
        Permission.camera,
        Permission.microphone,
      ].request();
      final cameraGranted = statuses[Permission.camera]?.isGranted ?? false;
      final micGranted = statuses[Permission.microphone]?.isGranted ?? false;
      return cameraGranted && micGranted;
    } catch (_) {
      return false;
    }
  }
}
