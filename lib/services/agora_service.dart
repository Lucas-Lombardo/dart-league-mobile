import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:permission_handler/permission_handler.dart';

class AgoraService {
  static RtcEngine? _engine;

  /// Initialize the Agora RTC Engine with the provided App ID
  static Future<RtcEngine> initializeEngine(String appId) async {
    
    if (_engine != null) {
      return _engine!;
    }

    try {
      _engine = createAgoraRtcEngine();
      await _engine!.initialize(RtcEngineContext(
        appId: appId,
        channelProfile: ChannelProfileType.channelProfileCommunication,
      ));

      // Suppress excessive debug logs - only show errors
      await _engine!.setLogLevel(LogLevel.logLevelError);

      // Enable video module
      await _engine!.enableVideo();
      await _engine!.enableAudio();
      
      // Set video configuration
      await _engine!.setVideoEncoderConfiguration(
        const VideoEncoderConfiguration(
          dimensions: VideoDimensions(width: 640, height: 480),
          frameRate: 15,
          bitrate: 0,
        ),
      );

      return _engine!;
    } catch (e) {
      rethrow;
    }
  }

  /// Request camera and microphone permissions
  static Future<bool> requestPermissions() async {
    
    try {
      Map<Permission, PermissionStatus> statuses = await [
        Permission.camera,
        Permission.microphone,
      ].request();

      final cameraGranted = statuses[Permission.camera]?.isGranted ?? false;
      final micGranted = statuses[Permission.microphone]?.isGranted ?? false;


      return cameraGranted && micGranted;
    } catch (e) {
      return false;
    }
  }

  /// Join an Agora channel with the given token and channel name
  static Future<void> joinChannel({
    required RtcEngine engine,
    required String token,
    required String channelName,
    required int uid,
  }) async {
    
    try {
      await engine.joinChannel(
        token: token,
        channelId: channelName,
        uid: uid,
        options: const ChannelMediaOptions(
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
          channelProfile: ChannelProfileType.channelProfileCommunication,
        ),
      );
      
    } catch (e) {
      rethrow;
    }
  }

  /// Leave the current Agora channel
  static Future<void> leaveChannel(RtcEngine engine) async {
    
    try {
      await engine.leaveChannel();
    } catch (_) {
      // Leave channel error
    }
  }

  /// Toggle local video on/off
  static Future<void> toggleLocalVideo(RtcEngine engine, bool enabled) async {
    
    try {
      await engine.enableLocalVideo(enabled);
    } catch (_) {
      // Toggle video error
    }
  }

  /// Toggle local audio on/off (mute/unmute)
  static Future<void> toggleLocalAudio(RtcEngine engine, bool muted) async {
    
    try {
      await engine.muteLocalAudioStream(muted);
    } catch (_) {
      // Toggle audio error
    }
  }

  /// Switch between front and back camera
  static Future<void> switchCamera(RtcEngine engine) async {
    
    try {
      await engine.switchCamera();
    } catch (_) {
      // Switch camera error
    }
  }

  /// Set camera to back camera (rear facing)
  static Future<void> setBackCamera(RtcEngine engine) async {
    try {
      // On mobile, switch to back camera
      await engine.setCameraCapturerConfiguration(
        const CameraCapturerConfiguration(
          cameraDirection: CameraDirection.cameraRear,
        ),
      );
    } catch (_) {
      // Set camera error
    }
  }

  /// Start camera preview without joining a channel
  static Future<void> startPreview(RtcEngine engine) async {
    try {
      await engine.startPreview();
    } catch (_) {
      // Start preview error
    }
  }

  /// Stop camera preview
  static Future<void> stopPreview(RtcEngine engine) async {
    try {
      await engine.stopPreview();
    } catch (_) {
      // Stop preview error
    }
  }

  /// Release the Agora engine and cleanup resources
  static Future<void> dispose() async {
    
    if (_engine != null) {
      try {
        await _engine!.leaveChannel();
        await _engine!.release();
        _engine = null;
      } catch (_) {
        // Dispose error
      }
    }
  }
}
