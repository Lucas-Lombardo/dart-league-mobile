import 'package:audioplayers/audioplayers.dart';
import '../providers/game_provider.dart';

class DartSoundService {
  static final AudioPlayer _player = AudioPlayer();
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    await _player.setReleaseMode(ReleaseMode.stop);
    // Use ambient category so sound effects follow the system volume
    // and don't fight with Agora's playAndRecord audio session.
    await _player.setAudioContext(AudioContext(
      iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient),
      android: const AudioContextAndroid(),
    ));
    _initialized = true;
  }

  static Future<void> _play(String asset) async {
    if (!_initialized) await init();
    try {
      await _player.stop();
      await _player.play(AssetSource(asset));
    } catch (_) {}
  }

  static Future<void> playDartHit(int baseScore, ScoreMultiplier multiplier) async {
    await _play('sounds/dart_hit.mp3');
  }

  static Future<void> playYourTurn() async {
    await _play('sounds/your_turn.wav');
  }

  static Future<void> playTurnFinished() async {
    await _play('sounds/turn_finished.wav');
  }

  static Future<void> playBust() async {
    await _play('sounds/bust.wav');
  }

  static Future<void> playWin() async {
    await _play('sounds/win.wav');
  }

  static Future<void> playLose() async {
    await _play('sounds/lose.wav');
  }

  static void dispose() {
    _player.dispose();
    _initialized = false;
  }
}
