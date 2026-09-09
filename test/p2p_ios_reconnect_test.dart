import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/rtc_v2_config.dart';
import 'package:mobile/services/p2p_match_video.dart';
import 'package:mobile/services/socket_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const rtc = MethodChannel('FlutterWebRTC.Method');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;
  late List<Map<dynamic, dynamic>> signals;
  late List<String> eventChannels;
  late P2pMatchVideo video;
  late int connections;
  late int textures;

  void mockEvents(String channel) {
    eventChannels.add(channel);
    messenger.setMockMethodCallHandler(
      MethodChannel(channel),
      (_) async => null,
    );
  }

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    SocketService.debugReset();
    calls = [];
    signals = [];
    eventChannels = [];
    connections = 0;
    textures = 0;
    SocketService.debugEmitOverride = (event, data) {
      if (event == 'rtc_signal') signals.add(data['data'] as Map);
    };
    messenger.setMockMethodCallHandler(rtc, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'createVideoRenderer':
          final id = ++textures;
          mockEvents('FlutterWebRTC/Texture$id');
          return {'textureId': id};
        case 'createPeerConnection':
          final id = 'pc${++connections}';
          mockEvents('FlutterWebRTC/peerConnectionEvent$id');
          return {'peerConnectionId': id};
        case 'getUserMedia':
          return {
            'streamId': 'audio$connections',
            'audioTracks': [
              {
                'id': 'mic$connections',
                'label': 'mic',
                'kind': 'audio',
                'enabled': true,
              },
            ],
            'videoTracks': [],
          };
        case 'addTrack':
          return {
            'senderId': 'sender$connections',
            'track': <String, dynamic>{},
            'rtpParameters': {
              'encodings': [],
              'headerExtensions': [],
              'codecs': [],
              'rtcp': {},
            },
            'ownsTrack': false,
          };
        case 'createOffer':
          return {'type': 'offer', 'sdp': 'offer$connections'};
        case 'createAnswer':
          return {'type': 'answer', 'sdp': 'answer$connections'};
        case 'getStats':
          return {'stats': []};
        default:
          return null;
      }
    });
    video = P2pMatchVideo(
      matchId: 'match',
      opponentId: 'android-player',
      configProvider: () => const RtcV2Config(iceServers: [], polite: false),
      onChanged: () {},
    );
  });

  tearDown(() async {
    await video.stop();
    await Future<void>.delayed(Duration.zero);
    messenger.setMockMethodCallHandler(rtc, null);
    for (final channel in eventChannels) {
      messenger.setMockMethodCallHandler(MethodChannel(channel), null);
    }
    SocketService.debugReset();
    debugDefaultTargetPlatformOverride = null;
  });

  for (final micEnabled in [false, true]) {
    test(
      'iOS adopts the returning Android peer and preserves mic=$micEnabled',
      () async {
        await video.setMicEnabled(micEnabled);
        await video.start();
        await Future<void>.delayed(Duration.zero);
        expect(connections, 1);
        expect(
          signals.any((s) => s['type'] == 'offer' && s['gen'] == 0),
          isTrue,
        );

        SocketService.debugDispatch('rtc_signal', {
          'from': 'android-player',
          'data': {'type': 'offer', 'sdp': 'returning-peer', 'gen': 1},
        });
        // Drain the real session's asynchronous teardown, setup and SDP chain.
        for (
          var i = 0;
          i < 20 && !signals.any((s) => s['type'] == 'answer');
          i++
        ) {
          await Future<void>.delayed(Duration.zero);
        }
        expect(connections, 2);
        expect(textures, 2);
        expect(
          calls.where((c) => c.method == 'peerConnectionDispose'),
          hasLength(1),
        );
        expect(signals.where((s) => s['type'] == 'answer').single['gen'], 1);
        final micCalls = calls.where(
          (c) =>
              c.method == 'mediaStreamTrackSetEnable' &&
              c.arguments['trackId'] == 'mic2',
        );
        expect(micCalls, isNotEmpty);
        expect(micCalls.last.arguments['enabled'], micEnabled);
        expect(
          calls.where((c) => c.method == 'enableSpeakerphone'),
          hasLength(2),
        );
        // AVAudioSession itself is not exercised by a host Flutter test.

        // A late packet from the old connection cannot replace the resumed call.
        SocketService.debugDispatch('rtc_signal', {
          'from': 'android-player',
          'data': {'type': 'answer', 'sdp': 'stale', 'gen': 0},
        });
        await Future<void>.delayed(Duration.zero);
        expect(connections, 2);
        expect(
          calls.where(
            (c) =>
                c.method == 'setRemoteDescription' &&
                c.arguments['description']['sdp'] == 'stale',
          ),
          isEmpty,
        );
      },
    );
  }

  test('resume requested offline cannot reopen a stopped match', () async {
    await video.start();
    video.onAppResumed();
    await video.stop();
    video.onAppResumed();
    await Future<void>.delayed(Duration.zero);
    expect(connections, 1);
  });
}
