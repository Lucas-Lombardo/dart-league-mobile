import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import '../providers/game_provider.dart';

/// Why one AudioPlayer per asset (not a single shared player):
/// the previous implementation called `stop()` then `play()` on a single
/// shared AudioPlayer for every sound. When sounds fired in quick succession
/// (e.g. three dart hits → turn_finished → bust within ~2s) the concurrent
/// stop/play operations raced on the same player and the second sound would
/// cancel the first before it actually started, so playback became
/// intermittent. With one preloaded player per asset, calls to different
/// sounds don't share state and restarts of the same sound are a single
/// atomic seek+resume.
class DartSoundService {
  static const _dartHit = 'sounds/dart_hit.mp3';
  static const _yourTurn = 'sounds/your_turn.wav';
  static const _turnFinished = 'sounds/turn_finished.wav';
  static const _bust = 'sounds/bust.wav';
  static const _win = 'sounds/win.wav';
  static const _lose = 'sounds/lose.wav';
  static const _matchFound = 'sounds/match_sound.mp3';

  static const _allAssets = <String>[
    _dartHit,
    _yourTurn,
    _turnFinished,
    _bust,
    _win,
    _lose,
    _matchFound,
  ];

  static final Map<String, AudioPlayer> _players = {};
  static Future<void>? _initFuture;

  /// Idempotent. Concurrent callers share the same in-flight init Future, so
  /// a burst of first-play calls won't race on setReleaseMode/setAudioContext.
  static Future<void> init() {
    return _initFuture ??= _doInit();
  }

  static Future<void> _doInit() async {
    // playAndRecord + mixWithOthers (not ambient): ambient is silenced by the
    // iOS ring/silent switch, so with the ringer off the game was completely
    // mute. playAndRecord matches Agora's own session category, so the two
    // coexist instead of one stealing the session. See DartCallerService.
    final context = AudioContext(
      iOS: AudioContextIOS(
        category: AVAudioSessionCategory.playAndRecord,
        options: const {
          AVAudioSessionOptions.mixWithOthers,
          AVAudioSessionOptions.defaultToSpeaker,
          AVAudioSessionOptions.allowBluetooth,
        },
      ),
      android: const AudioContextAndroid(),
    );
    var loaded = 0;
    for (final asset in _allAssets) {
      try {
        final player = AudioPlayer();
        await player.setReleaseMode(ReleaseMode.stop);
        await player.setAudioContext(context);
        await player.setSource(AssetSource(asset));
        _players[asset] = player;
        loaded++;
      } catch (e) {
        debugPrint('[DartSoundService] failed to load $asset: $e');
      }
    }
    // A total failure (platform channel hiccup) must not be cached forever:
    // clearing the future lets the next play() retry the whole init.
    if (loaded == 0) _initFuture = null;
  }

  static Future<void> _play(String asset) async {
    if (_initFuture == null) {
      await init();
    } else {
      await _initFuture;
    }
    final player = _players[asset];
    if (player == null) return;
    try {
      await player.seek(Duration.zero);
      await player.resume();
    } catch (e) {
      debugPrint('[DartSoundService] play($asset) failed: $e');
    }
  }

  static Future<void> playDartHit(int baseScore, ScoreMultiplier multiplier) =>
      _play(_dartHit);
  static Future<void> playYourTurn() => _play(_yourTurn);
  static Future<void> playTurnFinished() => _play(_turnFinished);
  static Future<void> playBust() => _play(_bust);
  static Future<void> playWin() => _play(_win);
  static Future<void> playLose() => _play(_lose);
  static Future<void> playMatchFound() => _play(_matchFound);

  static Future<void> dispose() async {
    for (final player in _players.values) {
      try {
        await player.dispose();
      } catch (_) {}
    }
    _players.clear();
    _initFuture = null;
  }
}
