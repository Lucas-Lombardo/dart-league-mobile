import 'package:audioplayers/audioplayers.dart';
import '../providers/game_provider.dart';

class DartSoundService {
  static final AudioPlayer _player = AudioPlayer();
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    await _player.setReleaseMode(ReleaseMode.stop);
    _initialized = true;
  }

  static Future<void> playDartHit(int baseScore, ScoreMultiplier multiplier) async {
    if (!_initialized) await init();

    try {
      await _player.play(AssetSource('sounds/dart_hit.mp3'));
    } catch (_) {
      // Silently fail if sound can't play
    }
  }

  static void dispose() {
    _player.dispose();
    _initialized = false;
  }
}
