import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// The ONE audioplayers context of the app, shared by every [AudioPlayer]
/// ([DartSoundService]'s per-asset players and [DartCallerService]'s single
/// player). Two rules keep the match call's audio routing intact:
///
///  1. **Android: install it ONCE at startup** ([install]), never per player.
///     audioplayers applies a player's context by writing
///     `AudioManager.mode` and `AudioManager.isSpeakerphoneOn` GLOBALLY —
///     but only when the context differs from the plugin's default
///     (WrappedPlayer.updateAudioContext, audioplayers_android 5.3.0). A
///     sound loading lazily during a match therefore reset the phone to
///     mode NORMAL / speakerphone OFF underneath the WebRTC call, and the
///     opponent's voice (a VOICE_COMMUNICATION stream) moved to the
///     earpiece while the caller and every SFX (MEDIA streams) stayed on
///     the loudspeaker — reported 2026-09-06, on both sides of the match.
///     Installing the context as the plugin default at startup, before any
///     player exists, makes every later per-player `setAudioContext` a
///     no-op (equal contexts return early), so nothing ever touches the
///     AudioManager mid-match again.
///
///  2. **Every player passes the same context.** Two different contexts on
///     Android would put one of them back on the "differs from the default"
///     path of rule 1.
///
/// Why these values:
///  - iOS `playAndRecord` + `mixWithOthers` (not ambient): ambient is
///    silenced by the ring/silent switch, so with the ringer off the game
///    was completely mute. playAndRecord is the WebRTC call's own category,
///    so the two coexist instead of one stealing the session;
///    `defaultToSpeaker` keeps the loudspeaker; the per-player call on iOS
///    is global anyway (audioplayers_darwin says so in its own log line).
///  - Android `audioFocus: none`: the match call (flutter_webrtc's
///    AudioSwitchManager) requests AUDIOFOCUS_GAIN the moment it opens,
///    about a second after match_found — and a player that HOLDS focus then
///    gets AUDIOFOCUS_LOSS, on which audioplayers pauses it. That is how
///    the match-found jingle died during its own first second. Short SFX
///    and caller clips need no focus (and shouldn't interrupt the player's
///    music either); playback itself never required it.
class AppAudioContext {
  AppAudioContext._();

  static const AudioContextAndroid android = AudioContextAndroid(
    audioFocus: AndroidAudioFocus.none,
  );

  static AudioContext? _instance;

  static AudioContext get instance => _instance ??= AudioContext(
    iOS: AudioContextIOS(
      category: AVAudioSessionCategory.playAndRecord,
      options: const {
        AVAudioSessionOptions.mixWithOthers,
        AVAudioSessionOptions.defaultToSpeaker,
        AVAudioSessionOptions.allowBluetooth,
      },
    ),
    android: android,
  );

  static bool _installed = false;

  /// Makes [instance] the plugin-wide default on Android (rule 1 above).
  /// Call once from main() before any AudioPlayer is created; later calls
  /// are no-ops. Deliberately NOT done on iOS: there the per-player
  /// `setAudioContext` calls already apply the session category, and doing
  /// it at launch would configure the audio session before the first sound
  /// for no benefit.
  static Future<void> install() async {
    if (_installed) return;
    _installed = true;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    await AudioPlayer.global.setAudioContext(instance);
  }

  @visibleForTesting
  static void debugReset() {
    _installed = false;
  }
}
