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

  static const _allAssets = <String>[
    _dartHit,
    _yourTurn,
    _turnFinished,
    _bust,
    _win,
    _lose,
  ];

  static final Map<String, AudioPlayer> _players = {};
  static Future<void>? _initFuture;

  /// Idempotent. Concurrent callers share the same in-flight init Future, so
  /// a burst of first-play calls won't race on setReleaseMode/setAudioContext.
  static Future<void> init() {
    return _initFuture ??= _doInit();
  }

  static Future<void> _doInit() async {
    // Why ambient: sound effects mix with Agora's playAndRecord audio session
    // instead of fighting it for control, and follow the system volume.
    final context = AudioContext(
      iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient),
      android: const AudioContextAndroid(),
    );
    for (final asset in _allAssets) {
      try {
        final player = AudioPlayer();
        await player.setReleaseMode(ReleaseMode.stop);
        await player.setAudioContext(context);
        await player.setSource(AssetSource(asset));
        _players[asset] = player;
      } catch (e) {
        debugPrint('[DartSoundService] failed to load $asset: $e');
      }
    }
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
