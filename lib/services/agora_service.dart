import 'dart:async';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

class AgoraService {
  static RtcEngine? _engine;

  /// Initialize the Agora RTC Engine with external video source enabled.
  /// The app controls the camera via Flutter's camera package and pushes
  /// frames to Agora through a custom video track (like DartsMind).
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

      // Enable external video source — app owns the camera, pushes frames manually
      await _engine!.getMediaEngine().setExternalVideoSource(
        enabled: true,
        useTexture: false,
        sourceType: ExternalVideoSourceType.videoFrame,
      );

      // Enable video & audio modules
      await _engine!.enableVideo();
      await _engine!.enableAudio();

      // Route audio through the speaker so iOS hardware volume buttons
      // control the same volume stream used by the app.
      await _engine!.setDefaultAudioRouteToSpeakerphone(true);

      // Adaptive orientation: the encoder uses each frame's own rotation
      // metadata instead of forcing a portrait rotation pass. fixedPortrait
      // was stacking with the iOS SDK's per-frame rotation handling and
      // making Android receivers see the iPhone stream rotated 90°.
      await _engine!.setVideoEncoderConfiguration(
        const VideoEncoderConfiguration(
          dimensions: VideoDimensions(width: 720, height: 960),
          frameRate: 15,
          bitrate: 0,
          mirrorMode: VideoMirrorModeType.videoMirrorModeDisabled,
          orientationMode: OrientationMode.orientationModeAdaptive,
        ),
      );

      return _engine!;
    } catch (e) {
      rethrow;
    }
  }

  /// Initialize the Agora RTC Engine for web (no external video source).
  /// On web, Agora handles the camera directly via its default capture.
  static Future<RtcEngine> initializeEngineWeb(String appId) async {
    if (_engine != null) {
      return _engine!;
    }

    try {
      _engine = createAgoraRtcEngine();
      await _engine!.initialize(RtcEngineContext(
        appId: appId,
        channelProfile: ChannelProfileType.channelProfileCommunication,
      ));

      await _engine!.setLogLevel(LogLevel.logLevelError);

      // Enable video & audio modules — Agora handles camera on web
      await _engine!.enableVideo();
      await _engine!.enableAudio();

      return _engine!;
    } catch (e) {
      rethrow;
    }
  }

  /// Create a custom video track for pushing external frames.
  static Future<int> createCustomVideoTrack() async {
    return await _engine!.createCustomVideoTrack();
  }

  /// Destroy a custom video track.
  static Future<void> destroyCustomVideoTrack(int trackId) async {
    try {
      await _engine!.destroyCustomVideoTrack(trackId);
    } catch (e) {
      debugPrint('[AgoraService] destroyCustomVideoTrack error: $e');
    }
  }

  /// Push an external video frame to the custom video track.
  static Future<void> pushVideoFrame({
    required ExternalVideoFrame frame,
    required int videoTrackId,
  }) async {
    try {
      await _engine!.getMediaEngine().pushVideoFrame(
        frame: frame,
        videoTrackId: videoTrackId,
      );
    } catch (_) {
      // Frame drops are expected under load — don't spam logs
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

  /// Join an Agora channel with the given token and channel name.
  /// When [customVideoTrackId] is provided, publishes the custom video track
  /// instead of the default camera track.
  static Future<void> joinChannel({
    required RtcEngine engine,
    required String token,
    required String channelName,
    required int uid,
    int? customVideoTrackId,
  }) async {
    try {
      await engine.joinChannel(
        token: token,
        channelId: channelName,
        uid: uid,
        options: ChannelMediaOptions(
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
          channelProfile: ChannelProfileType.channelProfileCommunication,
          publishMicrophoneTrack: false,
          autoSubscribeAudio: true,
          autoSubscribeVideo: true,
          // Custom video track: publish our frames, disable default camera
          publishCustomVideoTrack: customVideoTrackId != null,
          customVideoTrackId: customVideoTrackId,
          publishCameraTrack: customVideoTrackId == null,
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
    } catch (e) {
      debugPrint('[AgoraService] leaveChannel error: $e');
    }
  }

  /// Toggle local audio on/off (mute/unmute)
  static Future<void> toggleLocalAudio(RtcEngine engine, bool muted) async {
    try {
      await engine.muteLocalAudioStream(muted);
    } catch (e) {
      debugPrint('[AgoraService] toggleLocalAudio error: $e');
    }
  }

  /// Mute all remote audio streams (opponent's audio)
  static Future<void> muteAllRemoteAudio(RtcEngine engine, bool muted) async {
    try {
      await engine.muteAllRemoteAudioStreams(muted);
    } catch (e) {
      debugPrint('[AgoraService] muteAllRemoteAudio error: $e');
    }
  }

  /// Release the Agora engine and cleanup resources
  static Future<void> dispose() async {
    if (_engine != null) {
      try {
        await _engine!.leaveChannel();
        await _engine!.release();
      } catch (e) {
        debugPrint('[AgoraService] dispose error: $e');
      } finally {
        // Why: previously _engine = null lived inside the try block, so a
        // throw from release() could leave the static singleton pointing at a
        // dead engine. The next initializeEngine() would short-circuit and
        // return that dead engine, silently breaking publish on rejoin.
        _engine = null;
      }
    }
  }
}
