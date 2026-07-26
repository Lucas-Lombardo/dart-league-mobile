import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import '../providers/game_provider.dart';
import 'storage_service.dart';

/// User-facing sound categories (Settings > Sounds). Each play method below
/// belongs to exactly one category; disabling a category mutes its sounds
/// everywhere without touching call sites.
enum SoundCategory {
  dartHit, // dart_hit
  turn, // your_turn + turn_finished
  gameEffects, // bust + win + lose
  matchFound, // match_sound
}

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

  static final Map<SoundCategory, bool> _categoryEnabled = {
    for (final c in SoundCategory.values) c: true,
  };

  static bool isEnabled(SoundCategory category) => _categoryEnabled[category]!;

  static Future<void> setEnabled(SoundCategory category, bool enabled) async {
    _categoryEnabled[category] = enabled;
    await StorageService.saveSoundEnabled('sound_${category.name}', enabled);
  }

  /// Called once at startup (main.dart), like DartCallerService.loadPreference.
  static Future<void> loadPreferences() async {
    for (final c in SoundCategory.values) {
      _categoryEnabled[c] = await StorageService.getSoundEnabled('sound_${c.name}');
    }
  }

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

  static Future<void> _playIfEnabled(SoundCategory category, String asset) {
    if (!isEnabled(category)) return Future.value();
    return _play(asset);
  }

  static Future<void> playDartHit(int baseScore, ScoreMultiplier multiplier) =>
      _playIfEnabled(SoundCategory.dartHit, _dartHit);
  static Future<void> playYourTurn() =>
      _playIfEnabled(SoundCategory.turn, _yourTurn);
  static Future<void> playTurnFinished() =>
      _playIfEnabled(SoundCategory.turn, _turnFinished);
  static Future<void> playBust() =>
      _playIfEnabled(SoundCategory.gameEffects, _bust);
  static Future<void> playWin() =>
      _playIfEnabled(SoundCategory.gameEffects, _win);
  static Future<void> playLose() =>
      _playIfEnabled(SoundCategory.gameEffects, _lose);
  static Future<void> playMatchFound() =>
      _playIfEnabled(SoundCategory.matchFound, _matchFound);

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
