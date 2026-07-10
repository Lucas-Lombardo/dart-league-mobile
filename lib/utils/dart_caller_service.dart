import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'storage_service.dart';

/// Voice "caller" that announces completed-visit scores and checkout
/// requirements using the pre-recorded clips in assets/caller/ — one mp3 per
/// number (1..180), plus you-require.mp3 and no-score.mp3.
///
/// Unlike [DartSoundService] we do NOT preload a player per clip: there are
/// ~180 files and only a handful ever play in a match. Instead a single
/// [AudioPlayer] drains a short queue, so a multi-clip call
/// ("you require" → "121") plays back-to-back without the two clips
/// overlapping.
class DartCallerService {
  DartCallerService._();

  static const _basePath = 'caller';

  /// Numbers that cannot be finished in 501 double-out (plus everything > 170).
  static const Set<int> _bogeyNumbers = {169, 168, 166, 165, 163, 162, 159};

  static AudioPlayer? _player;
  static final List<String> _queue = [];
  static bool _playing = false;
  static StreamSubscription<void>? _completeSub;
  static Future<void>? _initFuture;

  /// Fail-safe for a completion event that never arrives (iOS audio-session
  /// interruption: incoming call, Siri). _playing would stay true forever and
  /// every later announcement would silently pile up in _queue — the caller
  /// went dead for the rest of the app session with no way back.
  static Timer? _playWatchdog;
  static const _maxClipDuration = Duration(seconds: 6);

  static bool _enabled = true;

  /// Whether the caller is currently on. Read by the game screen before it
  /// bothers computing a call; toggled from settings via [setEnabled].
  static bool get enabled => _enabled;

  /// Load the persisted on/off preference. Call once at startup.
  static Future<void> loadPreference() async {
    _enabled = await StorageService.getCallerEnabled();
  }

  /// Turn the caller on/off and persist the choice. Silences any queued/playing
  /// clip immediately when turned off.
  static Future<void> setEnabled(bool value) async {
    _enabled = value;
    await StorageService.saveCallerEnabled(value);
    if (!value) await stop();
  }

  /// Whether [score] is a finishable checkout in 501 double-out (2..170,
  /// excluding the bogey numbers). Callers that are not on a finish get no call.
  static bool isCheckout(int score) {
    if (score < 2 || score > 170) return false;
    return !_bogeyNumbers.contains(score);
  }

  /// Announce the total of a completed 3-dart visit. 0 → "no score".
  static Future<void> callScore(int score) async {
    if (!_enabled) return;
    if (score < 0 || score > 180) return;
    await _enqueue([score == 0 ? 'no-score' : '$score']);
  }

  /// Announce "you require [remaining]" when a checkout is on. No-op when the
  /// remaining score can't be finished (> 170, a bogey number, or < 2).
  static Future<void> callCheckout(int remaining) async {
    if (!_enabled) return;
    if (!isCheckout(remaining)) return;
    await _enqueue(['you-require', '$remaining']);
  }

  static Future<void> _enqueue(List<String> clips) async {
    await _ensureInit();
    if (_player == null) return;
    _queue.addAll(clips);
    if (!_playing) _playNext();
  }

  static Future<void> _ensureInit() => _initFuture ??= _doInit();

  static Future<void> _doInit() async {
    // playAndRecord (not ambient): ambient is silenced by the iOS ring/silent
    // switch, so with the ringer off — very common — the caller was mute for
    // the entire match. playAndRecord ignores the silent switch and is the
    // same category Agora's voice call already uses, so we don't take the
    // session away from it; mixWithOthers keeps both audible.
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
    try {
      final player = AudioPlayer();
      await player.setReleaseMode(ReleaseMode.stop);
      await player.setAudioContext(context);
      _completeSub = player.onPlayerComplete.listen((_) => _playNext());
      _player = player;
    } catch (e) {
      debugPrint('[DartCallerService] init failed: $e');
      // Don't cache the failed init: a transient platform-channel error used
      // to leave the caller permanently dead (the completed-with-error future
      // was reused forever). Next call retries.
      _initFuture = null;
    }
  }

  static void _playNext() {
    _playWatchdog?.cancel();
    _playWatchdog = null;
    final player = _player;
    if (player == null) {
      _playing = false;
      return;
    }
    if (_queue.isEmpty) {
      _playing = false;
      return;
    }
    _playing = true;
    final clip = _queue.removeAt(0);
    // If the completion event is lost, advance anyway.
    _playWatchdog = Timer(_maxClipDuration, () {
      debugPrint('[DartCallerService] watchdog: no completion for $clip');
      _playNext();
    });
    player.play(AssetSource('$_basePath/$clip.mp3')).catchError((Object e) {
      debugPrint('[DartCallerService] play($clip) failed: $e');
      _playNext(); // skip the broken clip so the queue keeps draining
    });
  }

  static Future<void> stop() async {
    _queue.clear();
    _playing = false;
    _playWatchdog?.cancel();
    _playWatchdog = null;
    try {
      await _player?.stop();
    } catch (_) {}
  }

  static Future<void> dispose() async {
    _queue.clear();
    _playing = false;
    _playWatchdog?.cancel();
    _playWatchdog = null;
    await _completeSub?.cancel();
    _completeSub = null;
    try {
      await _player?.dispose();
    } catch (_) {}
    _player = null;
    _initFuture = null;
  }
}
