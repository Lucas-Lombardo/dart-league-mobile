import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart'
    show
        AppleAudioCategory,
        AppleAudioCategoryOption,
        AppleAudioConfiguration,
        AppleAudioMode,
        Helper;

import 'rtc_frames_service.dart';

/// Audio routing of a match call, shared by both transports (P2P and
/// Cloudflare): the phone is propped up facing the board, so every sound —
/// the opponent's voice, the caller, the jingles — must come out of the
/// loudspeaker at full level.
class MatchAudioRoute {
  MatchAudioRoute._();

  static bool get _isIOS =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// iOS: WebRTC's stock session profile is voiceChat — the phone-call
  /// profile: earpiece unless overridden, loudspeaker output capped near
  /// earpiece level. With the phone propped up facing the board that turned
  /// the opponent AND every app sound into a whisper, the match-found jingle
  /// first: it is still playing when the call opens ~1s after match_found.
  /// videoChat is Apple's speakerphone profile — same voice-processing echo
  /// cancellation, full speaker level. Two steps, both before the first
  /// PeerConnection: store the profile as WebRTC's OWN configuration (what
  /// its audio unit re-applies whenever it starts — the live session state
  /// alone is overwritten the moment ICE connects), then apply it live so
  /// the jingle already plays through the loudspeaker.
  static Future<void> prepare() async {
    if (!_isIOS) return;
    await RtcFramesService.installAppleAudioSessionProfile();
    await _applyAppleAudioProfile();
  }

  /// The match's iOS session profile. Options mirror the set flutter_webrtc's
  /// setSpeakerphoneOn(true) applies, so the two never flip-flop; the same
  /// values are stored natively as WebRTC's own configuration
  /// (RtcFramesService.installAppleAudioSessionProfile).
  static AppleAudioConfiguration get _appleAudioProfile =>
      AppleAudioConfiguration(
        appleAudioCategory: AppleAudioCategory.playAndRecord,
        appleAudioCategoryOptions: {
          AppleAudioCategoryOption.allowBluetooth,
          AppleAudioCategoryOption.allowBluetoothA2DP,
          AppleAudioCategoryOption.allowAirPlay,
          AppleAudioCategoryOption.defaultToSpeaker,
        },
        appleAudioMode: AppleAudioMode.videoChat,
      );

  static Future<void> _applyAppleAudioProfile() async {
    try {
      await Helper.setAppleAudioConfiguration(_appleAudioProfile);
    } catch (e) {
      debugPrint('MatchAudioRoute: apple audio configuration failed: $e');
    }
  }

  /// Remote audio through the loudspeaker (WebRTC's default on both
  /// platforms is the earpiece). Called after every connect and again on
  /// connected.
  ///
  /// Android: selects AudioSwitch's Speakerphone device (the call runs in
  /// MODE_IN_COMMUNICATION with speakerphone on). Nothing else in the app may
  /// touch AudioManager mid-match — audioplayers did, see AppAudioContext.
  /// iOS: setSpeakerphoneOn also re-applies WebRTC's stored mode (videoChat
  /// once installed natively, voiceChat if that failed), so the videoChat
  /// profile is applied again right after it.
  static Future<void> routeToLoudspeaker() async {
    try {
      await Helper.setSpeakerphoneOn(true);
    } catch (e) {
      debugPrint('MatchAudioRoute: setSpeakerphoneOn failed: $e');
    }
    if (_isIOS) await _applyAppleAudioProfile();
  }
}
