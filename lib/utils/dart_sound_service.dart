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

  // Preload order, most time-critical first. match_sound is the only one that
  // fires while the app is busy tearing down one screen and building another,
  // and it used to sit LAST behind ~1.6 MB of wavs — see [_ensurePlayer].
  static const _allAssets = <String>[
    _matchFound,
    _dartHit,
    _yourTurn,
    _turnFinished,
    _bust,
    _win,
    _lose,
  ];

  static final Map<String, AudioPlayer> _players = {};
  // In-flight load per asset, so concurrent plays of the same sound share one
  // load instead of racing two setSource calls on two players.
  static final Map<String, Future<void>> _loading = {};
  static AudioContext? _context;

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

  // playAndRecord + mixWithOthers (not ambient): ambient is silenced by the
  // iOS ring/silent switch, so with the ringer off the game was completely
  // mute. playAndRecord matches the WebRTC call's own session category, so the
  // two coexist instead of one stealing the session. See DartCallerService.
  static AudioContext _audioContext() => _context ??= AudioContext(
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

  /// Preloads every sound. Idempotent, and safe to call repeatedly: assets
  /// already loaded (or loading) are skipped.
  static Future<void> init() async {
    for (final asset in _allAssets) {
      await _ensurePlayer(asset);
    }
  }

  /// The player for ONE asset, loading it on first use.
  ///
  /// Deliberately per-asset rather than "load all seven, then play": the seven
  /// assets total ~1.8 MB of bundle copies over the platform channel, and
  /// making every sound wait for all of them meant match_sound — requested at
  /// the single busiest moment of the app, while the game screen is being
  /// built — could take so long to become playable that it effectively never
  /// played. A sound now waits only for itself.
  static Future<AudioPlayer?> _ensurePlayer(String asset) async {
    final loaded = _players[asset];
    if (loaded != null) return loaded;
    await (_loading[asset] ??= _load(asset));
    return _players[asset];
  }

  static Future<void> _load(String asset) async {
    try {
      final player = AudioPlayer();
      await player.setReleaseMode(ReleaseMode.stop);
      await player.setAudioContext(_audioContext());
      await player.setSource(AssetSource(asset));
      _players[asset] = player;
    } catch (e) {
      debugPrint('[DartSoundService] failed to load $asset: $e');
      // A failure (platform channel hiccup) must not be cached forever:
      // dropping the future lets the next play retry this asset.
      _loading.remove(asset);
    }
  }

  static Future<void> _play(String asset) async {
    final player = await _ensurePlayer(asset);
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
    _loading.clear();
  }
}
