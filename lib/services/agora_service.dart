import 'dart:async';
import 'dart:io';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
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

      // Disable flash/torch for captures
      try { await _engine!.setCameraTorchOn(false); } catch (_) {}
      
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
          publishMicrophoneTrack: false,
          autoSubscribeAudio: true,
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

  /// Toggle local video on/off
  static Future<void> toggleLocalVideo(RtcEngine engine, bool enabled) async {
    try {
      await engine.enableLocalVideo(enabled);
    } catch (e) {
      debugPrint('[AgoraService] toggleLocalVideo error: $e');
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

  /// Switch between front and back camera
  static Future<void> switchCamera(RtcEngine engine) async {
    try {
      await engine.switchCamera();
    } catch (e) {
      debugPrint('[AgoraService] switchCamera error: $e');
    }
  }

  /// Set camera to back camera (rear facing) with high capture resolution for AI snapshots.
  /// Capturer resolution (1280×720) is independent of the encoder resolution (640×480),
  /// so the video call bandwidth is unaffected while snapshots use full quality.
  static Future<void> setBackCamera(RtcEngine engine) async {
    try {
      await engine.setCameraCapturerConfiguration(
        const CameraCapturerConfiguration(
          cameraDirection: CameraDirection.cameraRear,
          format: VideoFormat(width: 1280, height: 720, fps: 15),
        ),
      );
    } catch (e) {
      debugPrint('[AgoraService] setBackCamera error: $e');
    }
  }

  /// Start camera preview without joining a channel
  static Future<void> startPreview(RtcEngine engine) async {
    try {
      await engine.startPreview();
    } catch (e) {
      debugPrint('[AgoraService] startPreview error: $e');
    }
  }

  /// Stop camera preview
  static Future<void> stopPreview(RtcEngine engine) async {
    try {
      await engine.stopPreview();
    } catch (e) {
      debugPrint('[AgoraService] stopPreview error: $e');
    }
  }

  /// Take a snapshot of the local video stream and return the file path.
  /// Uses Agora's takeSnapshot API. Returns null on failure.
  static Future<String?> takeLocalSnapshot(RtcEngine engine) async {
    RtcEngineEventHandler? handler;
    try {
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/agora_snap_${DateTime.now().millisecondsSinceEpoch}.jpg';

      final completer = Completer<String?>();
      bool handlerRemoved = false;

      void removeHandler() {
        if (!handlerRemoved && handler != null) {
          handlerRemoved = true;
          try {
            engine.unregisterEventHandler(handler);
          } catch (_) {}
        }
      }

      handler = RtcEngineEventHandler(
        onSnapshotTaken: (RtcConnection connection, int uid,
            String filePath, int width, int height, int errCode) {
          Future.microtask(removeHandler);
          if (!completer.isCompleted) {
            completer.complete(errCode == 0 ? filePath : null);
          }
        },
      );

      engine.registerEventHandler(handler);

      await engine.takeSnapshot(uid: 0, filePath: path);

      final result = await completer.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          Future.microtask(removeHandler);
          return null;
        },
      );

      return result;
    } catch (e) {
      if (handler != null) {
        try { engine.unregisterEventHandler(handler); } catch (_) {}
      }
      debugPrint('[AgoraService] takeLocalSnapshot error: $e');
      return null;
    }
  }

  /// Clean up old snapshot files from temp directory
  static Future<void> cleanupSnapshots() async {
    try {
      final dir = await getTemporaryDirectory();
      final files = dir.listSync();
      for (final file in files) {
        if (file is File && file.path.contains('agora_snap_')) {
          await file.delete();
        }
      }
    } catch (_) {}
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
