import 'package:flutter/foundation.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:permission_handler/permission_handler.dart';

class AgoraService {
  static RtcEngine? _engine;

  /// Initialize the Agora RTC Engine with the provided App ID
  static Future<RtcEngine> initializeEngine(String appId) async {
    debugPrint('📹 Initializing Agora engine with appId: ${appId.substring(0, 8)}...');
    
    if (_engine != null) {
      debugPrint('⚠️ Engine already initialized, returning existing instance');
      return _engine!;
    }

    try {
      _engine = createAgoraRtcEngine();
      await _engine!.initialize(RtcEngineContext(
        appId: appId,
        channelProfile: ChannelProfileType.channelProfileCommunication,
      ));

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

      debugPrint('✅ Agora engine initialized successfully');
      return _engine!;
    } catch (e) {
      debugPrint('❌ Error initializing Agora engine: $e');
      rethrow;
    }
  }

  /// Request camera and microphone permissions
  static Future<bool> requestPermissions() async {
    debugPrint('📹 Requesting camera and microphone permissions');
    
    try {
      Map<Permission, PermissionStatus> statuses = await [
        Permission.camera,
        Permission.microphone,
      ].request();

      final cameraGranted = statuses[Permission.camera]?.isGranted ?? false;
      final micGranted = statuses[Permission.microphone]?.isGranted ?? false;

      debugPrint('📹 Camera permission: ${cameraGranted ? "granted" : "denied"}');
      debugPrint('📹 Microphone permission: ${micGranted ? "granted" : "denied"}');

      return cameraGranted && micGranted;
    } catch (e) {
      debugPrint('❌ Error requesting permissions: $e');
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
    debugPrint('📹 Joining Agora channel: $channelName with uid: $uid');
    
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
      
      debugPrint('✅ Successfully joined Agora channel');
    } catch (e) {
      debugPrint('❌ Error joining channel: $e');
      rethrow;
    }
  }

  /// Leave the current Agora channel
  static Future<void> leaveChannel(RtcEngine engine) async {
    debugPrint('📹 Leaving Agora channel');
    
    try {
      await engine.leaveChannel();
      debugPrint('✅ Successfully left Agora channel');
    } catch (e) {
      debugPrint('❌ Error leaving channel: $e');
    }
  }

  /// Toggle local video on/off
  static Future<void> toggleLocalVideo(RtcEngine engine, bool enabled) async {
    debugPrint('📹 Toggling local video: ${enabled ? "ON" : "OFF"}');
    
    try {
      await engine.enableLocalVideo(enabled);
      debugPrint('✅ Local video ${enabled ? "enabled" : "disabled"}');
    } catch (e) {
      debugPrint('❌ Error toggling video: $e');
    }
  }

  /// Toggle local audio on/off (mute/unmute)
  static Future<void> toggleLocalAudio(RtcEngine engine, bool muted) async {
    debugPrint('📹 Toggling local audio: ${muted ? "MUTED" : "UNMUTED"}');
    
    try {
      await engine.muteLocalAudioStream(muted);
      debugPrint('✅ Local audio ${muted ? "muted" : "unmuted"}');
    } catch (e) {
      debugPrint('❌ Error toggling audio: $e');
    }
  }

  /// Release the Agora engine and cleanup resources
  static Future<void> dispose() async {
    debugPrint('📹 Disposing Agora engine');
    
    if (_engine != null) {
      try {
        await _engine!.leaveChannel();
        await _engine!.release();
        _engine = null;
        debugPrint('✅ Agora engine disposed');
      } catch (e) {
        debugPrint('❌ Error disposing engine: $e');
      }
    }
  }
}
