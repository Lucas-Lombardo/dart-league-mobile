import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/rtc_v2_config.dart';
import 'package:mobile/providers/spectator_provider.dart';
import 'package:mobile/services/match_video.dart';
import 'package:mobile/services/sfu_match_video.dart';
import 'package:mobile/services/socket_service.dart';

/// Match video over Cloudflare Realtime: the exchange with the backend
/// (publish → tracks → pull → answer), the server-only fallback to P2P, and
/// the spectator's camera state.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const rtc = MethodChannel('FlutterWebRTC.Method');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  const localSdp =
      'v=0\r\n'
      'm=audio 9 UDP/TLS/RTP/SAVPF 111\r\n'
      'a=mid:0\r\n'
      'a=sendonly\r\n'
      'm=video 9 UDP/TLS/RTP/SAVPF 96\r\n'
      'a=mid:1\r\n'
      'a=sendonly\r\n';

  late List<MethodCall> calls;
  late List<String> eventChannels;
  late List<MapEntry<String, dynamic>> requests;
  late List<MapEntry<String, dynamic>> emits;
  late Map<String, dynamic Function(dynamic)> replies;
  late int connections;

  void mockEvents(String channel) {
    eventChannels.add(channel);
    messenger.setMockMethodCallHandler(
      MethodChannel(channel),
      (_) async => null,
    );
  }

  Future<void> drain([int turns = 40]) async {
    for (var i = 0; i < turns; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    SocketService.debugReset();
    calls = [];
    eventChannels = [];
    requests = [];
    emits = [];
    connections = 0;
    replies = {
      'sfu_publish': (_) => {
        'ok': true,
        'sessionId': 'mine-1',
        'sdp': 'cf-answer',
      },
      'sfu_pull': (_) => {
        'ok': true,
        'sdp': 'cf-offer',
        'opponentSessionId': 'theirs-1',
        'tracks': [
          {'mid': '2', 'kind': 'video'},
          {'mid': '3', 'kind': 'audio'},
        ],
      },
      'sfu_answer': (_) => {'ok': true},
      'sfu_ready': (_) => {'ok': true},
      'sfu_failed': (_) => {'ok': true, 'transport': 'p2p'},
      'spectator_video_watch': (_) => {'ok': false, 'error': 'no_video_yet'},
    };
    SocketService.debugRequestOverride = (event, data) async {
      requests.add(MapEntry(event, data));
      final reply = replies[event];
      return reply?.call(data);
    };
    SocketService.debugEmitOverride = (event, data) {
      emits.add(MapEntry(event, data));
    };
    messenger.setMockMethodCallHandler(rtc, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'createVideoRenderer':
          final id = calls
              .where((c) => c.method == 'createVideoRenderer')
              .length;
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
        case 'addTransceiver':
        case 'addTrack':
          return {
            'transceiverId': 't$connections',
            'direction': 'sendonly',
            'mid': '',
            'senderId': 'sender$connections',
            'sender': {
              'senderId': 'sender$connections',
              'track': <String, dynamic>{},
              'rtpParameters': {
                'encodings': [],
                'headerExtensions': [],
                'codecs': [],
                'rtcp': {'cname': 'c', 'reducedSize': false},
              },
              'ownsTrack': false,
            },
            'receiver': {
              'receiverId': 'receiver$connections',
              'track': {
                'id': 'recv$connections',
                'label': 'recv',
                'kind': 'audio',
                'enabled': true,
              },
              'rtpParameters': {
                'encodings': [],
                'headerExtensions': [],
                'codecs': [],
                'rtcp': {'cname': 'c', 'reducedSize': false},
              },
            },
            'track': <String, dynamic>{},
            'rtpParameters': {
              'encodings': [],
              'headerExtensions': [],
              'codecs': [],
              'rtcp': {'cname': 'c', 'reducedSize': false},
            },
            'ownsTrack': false,
          };
        case 'createOffer':
          return {'type': 'offer', 'sdp': localSdp};
        case 'getLocalDescription':
          return {'type': 'offer', 'sdp': localSdp};
        case 'getIceGatheringState':
          return {'state': 'complete'};
        case 'createAnswer':
          return {'type': 'answer', 'sdp': 'my-answer'};
        case 'getStats':
          return {'stats': []};
        default:
          return null;
      }
    });
  });

  tearDown(() async {
    await drain();
    messenger.setMockMethodCallHandler(rtc, null);
    for (final channel in eventChannels) {
      messenger.setMockMethodCallHandler(MethodChannel(channel), null);
    }
    SocketService.debugReset();
    SocketService.debugRequestOverride = null;
    debugDefaultTargetPlatformOverride = null;
  });

  const sfuConfig = RtcV2Config(
    iceServers: [
      {
        'urls': ['stun:stun.cloudflare.com:3478'],
      },
    ],
    polite: false,
    sfu: SfuConfig(seriesId: 'series-1'),
  );

  group('RtcV2Config', () {
    test('parses the nested sfu block, and its absence means P2P', () {
      final sfu = RtcV2Config.tryParse({
        'iceServers': [
          {
            'urls': ['stun:x'],
          },
        ],
        'polite': true,
        'sfu': {'seriesId': 'abc'},
      });
      expect(sfu!.usesSfu, isTrue);
      expect(sfu.sfu!.seriesId, 'abc');

      final p2p = RtcV2Config.adopt({
        'rtcV2': {
          'iceServers': [
            {
              'urls': ['stun:x'],
            },
          ],
          'polite': true,
        },
      }, sfu);
      expect(
        p2p!.usesSfu,
        isFalse,
        reason: 'a later verdict without sfu = fallback',
      );

      // A payload without any rtcV2 block keeps the current verdict.
      expect(RtcV2Config.adopt({'foo': 1}, sfu)!.usesSfu, isTrue);
    });
  });

  test('reads the published tracks from the SDP m-lines', () {
    expect(SfuMatchVideo.sendTracksOf(localSdp), [
      {'mid': '0', 'kind': 'audio'},
      {'mid': '1', 'kind': 'video'},
    ]);
  });

  test(
    'publishes, then pulls and answers the opponent once announced',
    () async {
      final failures = <String>[];
      final video = SfuMatchVideo(
        matchId: 'leg-1',
        opponentId: 'opponent',
        configProvider: () => sfuConfig,
        onChanged: () {},
        onFailed: failures.add,
      );
      await video.start();
      await drain();

      final publish =
          requests.singleWhere((r) => r.key == 'sfu_publish').value as Map;
      expect(publish['matchId'], 'leg-1');
      expect(publish['sdp'], localSdp);
      expect(publish['tracks'], [
        {'mid': '0', 'kind': 'audio'},
        {'mid': '1', 'kind': 'video'},
      ]);
      expect(
        calls.any(
          (c) =>
              c.method == 'setRemoteDescription' &&
              c.arguments['description']['sdp'] == 'cf-answer',
        ),
        isTrue,
      );
      // Not pulled before the opponent is announced.
      expect(requests.where((r) => r.key == 'sfu_pull'), isEmpty);

      SocketService.debugDispatch('sfu_tracks', {
        'players': {
          'opponent': {
            'sessionId': 'theirs-1',
            'video': 'video',
            'audio': 'audio',
          },
        },
      });
      await drain(120);
      // The picture first, then the voice on its own (a silent mic must
      // never hold the picture back).
      final pulls = requests.where((r) => r.key == 'sfu_pull').toList();
      expect(pulls.map((r) => (r.value as Map)['kinds']), [
        ['video'],
        ['audio'],
      ]);
      expect(
        calls.any(
          (c) =>
              c.method == 'setRemoteDescription' &&
              c.arguments['description']['sdp'] == 'cf-offer',
        ),
        isTrue,
      );
      final answers = requests.where((r) => r.key == 'sfu_answer');
      expect(answers, hasLength(2));
      expect((answers.first.value as Map)['sdp'], 'my-answer');

      // The same announcement again does not pull twice.
      SocketService.debugDispatch('sfu_tracks', {
        'players': {
          'opponent': {
            'sessionId': 'theirs-1',
            'video': 'video',
            'audio': 'audio',
          },
        },
      });
      await drain();
      expect(requests.where((r) => r.key == 'sfu_pull'), hasLength(2));
      expect(failures, isEmpty);

      await video.stop();
      final report =
          emits.singleWhere((e) => e.key == 'rtc_v2_report').value as Map;
      expect(report['transport'], 'sfu');
      expect(report['matchId'], 'leg-1');
    },
  );

  test(
    'a series the server moved to P2P is reported, never switched locally',
    () async {
      replies['sfu_publish'] = (_) => {
        'ok': false,
        'error': 'not_sfu',
        'transport': 'p2p',
      };
      final failures = <String>[];
      final video = SfuMatchVideo(
        matchId: 'leg-1',
        opponentId: 'opponent',
        configProvider: () => sfuConfig,
        onChanged: () {},
        onFailed: failures.add,
      );
      await video.start();
      await drain();
      expect(failures, ['server_p2p_on_publish']);
      await video.stop();
    },
  );

  test(
    'MatchVideo starts on Cloudflare and follows the server to P2P',
    () async {
      final video = MatchVideo(
        matchId: 'leg-1',
        opponentId: 'opponent',
        configProvider: () => sfuConfig,
        onChanged: () {},
      );
      await video.setMicEnabled(true);
      await video.start();
      await drain();
      expect(video.transport, 'sfu');

      // Someone else's series: ignored.
      SocketService.debugDispatch('video_transport_changed', {
        'transport': 'p2p',
        'players': ['x', 'y'],
      });
      await drain();
      expect(video.transport, 'sfu');

      SocketService.debugDispatch('video_transport_changed', {
        'transport': 'p2p',
        'players': ['me', 'opponent'],
      });
      await drain(200);
      expect(video.transport, 'p2p');
      // The P2P session took over (its first offer went out on rtc_signal)…
      expect(emits.any((e) => e.key == 'rtc_signal'), isTrue);
      // …with the player's mic choice carried over.
      expect(
        calls.where(
          (c) =>
              c.method == 'mediaStreamTrackSetEnable' &&
              c.arguments['enabled'] == true,
        ),
        isNotEmpty,
      );
      // The Cloudflare session sent its terminal report on the way out.
      final report =
          emits.firstWhere((e) => e.key == 'rtc_v2_report').value as Map;
      expect(report['transport'], 'sfu');
      await video.stop();
    },
  );

  test(
    'MatchVideo asks the server when Cloudflare fails, then switches',
    () async {
      replies['sfu_publish'] = (_) => {
        'ok': false,
        'error': 'outage',
        'transport': 'p2p',
      };
      final video = MatchVideo(
        matchId: 'leg-1',
        opponentId: 'opponent',
        configProvider: () => sfuConfig,
        onChanged: () {},
      );
      await video.start();
      await drain(200);
      final failed =
          requests.singleWhere((r) => r.key == 'sfu_failed').value as Map;
      expect(failed['matchId'], 'leg-1');
      expect(video.transport, 'p2p');
      await video.stop();
    },
  );

  group('SpectatorProvider cameras', () {
    test(
      'follows the snapshot, the track announcements and the fallback',
      () async {
        final provider = SpectatorProvider();
        await provider.startSpectating('leg-1');
        expect(provider.camerasAvailable, isFalse);

        SocketService.debugDispatch('spectate_state', {
          'matchId': 'leg-1',
          'player1': {'id': 'p1', 'username': 'Dodo180', 'elo': 1000},
          'player2': {'id': 'p2', 'username': 'Kev_D', 'elo': 1000},
          'player1Score': 501,
          'player2Score': 501,
          'currentPlayerId': 'p1',
          'videoTransport': 'sfu',
          'videoPlayers': ['p1'],
        });
        expect(provider.camerasAvailable, isTrue);
        expect(provider.hasCameraFor('p1'), isFalse, reason: 'no frame yet');
        await Future<void>.delayed(const Duration(milliseconds: 700));
        await drain();
        expect(
          requests.where((r) => r.key == 'spectator_video_watch'),
          isNotEmpty,
        );

        // Another pair's fallback: ignored.
        SocketService.debugDispatch('video_transport_changed', {
          'transport': 'p2p',
          'players': ['x', 'y'],
        });
        expect(provider.camerasAvailable, isTrue);

        SocketService.debugDispatch('video_transport_changed', {
          'transport': 'p2p',
          'players': ['p1', 'p2'],
        });
        expect(provider.camerasAvailable, isFalse);
        provider.dispose();
      },
    );

    test('an older backend (no videoTransport) never offers cameras', () async {
      final provider = SpectatorProvider();
      await provider.startSpectating('leg-1');
      SocketService.debugDispatch('spectate_state', {
        'matchId': 'leg-1',
        'player1': {'id': 'p1', 'username': 'A', 'elo': 1000},
        'player2': {'id': 'p2', 'username': 'B', 'elo': 1000},
        'player1Score': 501,
        'player2Score': 501,
      });
      expect(provider.camerasAvailable, isFalse);
      provider.dispose();
    });
  });
}
