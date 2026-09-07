import 'package:audioplayers/audioplayers.dart';
import 'package:mobile/utils/app_audio_context.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// AppAudioContext.install() is what keeps audioplayers from resetting
/// AudioManager.mode / speakerphone underneath a live match call on Android
/// (opponent's voice dropping to the earpiece, 2026-09-06): the app context
/// must become the plugin-wide default at startup, and it must be the very
/// context every player passes later (equal contexts are a no-op natively).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const global = MethodChannel('xyz.luan/audioplayers.global');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    AppAudioContext.debugReset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(global, (call) async {
          calls.add(call);
          return null;
        });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(global, null);
  });

  test(
    'Android: installs the app context as the plugin default, once',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await AppAudioContext.install();
      await AppAudioContext.install();

      // audioplayers sends its own 'init' first; only the context call counts.
      final sets = calls.where((c) => c.method == 'setAudioContext').toList();
      expect(sets, hasLength(1));
      final args = Map<String, dynamic>.from(sets.single.arguments as Map);
      expect(args['audioFocus'], AndroidAudioFocus.none.value);
      // Whatever the default was, the installed context must keep the phone
      // in its normal state: the call (flutter_webrtc) owns mode/speakerphone.
      expect(args['audioMode'], AndroidAudioMode.normal.value);
      expect(args['isSpeakerphoneOn'], isFalse);
    },
  );

  test('iOS: leaves the global context alone', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await AppAudioContext.install();
    expect(calls.where((c) => c.method == 'setAudioContext'), isEmpty);
  });

  test('the Android context every player passes IS the installed one', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(AppAudioContext.instance.android, AppAudioContext.android);
    expect(AppAudioContext.android.audioFocus, AndroidAudioFocus.none);
    expect(
      AppAudioContext.instance.iOS.category,
      AVAudioSessionCategory.playAndRecord,
    );
    expect(
      AppAudioContext.instance.iOS.options,
      contains(AVAudioSessionOptions.defaultToSpeaker),
    );
  });
}
