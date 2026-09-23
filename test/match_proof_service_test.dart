import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile/services/match_proof_service.dart';
import 'package:mobile/services/replay_buffer_service.dart';
import 'package:mobile/services/socket_service.dart';
import 'package:mobile/utils/storage_service.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.dartrivals/replay_buffer');
  const leg1 = 'leg-1', leg2 = 'leg-2', series = 'series';
  late Directory temp;
  late List<String> requests;
  late List<String> deleted;
  late List<String> cuts;
  late List<String> failures;
  late bool exportComplete;
  late bool failSecondPut;
  late bool failConfirmation;
  late int serial;
  late MockClient client;
  const storage = FlutterSecureStorage();

  Future<Map<String, dynamic>> registry() async =>
      jsonDecode((await StorageService.getMatchProofRegistry())!)
          as Map<String, dynamic>;

  Future<void> prepare() async {
    await MatchProofService.startMatch(key: leg1);
    await MatchProofService.noteId(leg2);
    await MatchProofService.noteId(series);
  }

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SocketService.debugReset();
    FlutterSecureStorage.setMockInitialValues({'auth_token': 'test-token'});
    PackageInfo.setMockInitialValues(
      appName: 'test',
      packageName: 'test',
      version: '1.3.0',
      buildNumber: '1',
      buildSignature: '',
    );
    temp = await Directory.systemTemp.createTemp('proof-test-');
    requests = [];
    deleted = [];
    cuts = [];
    failures = [];
    exportComplete = true;
    failSecondPut = false;
    failConfirmation = false;
    serial = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          final args = call.arguments as Map?;
          if (call.method == 'deleteRetention') {
            deleted.add(args!['key'] as String);
          }
          if (call.method != 'cutRuns') return null;
          cuts.add(args!['key'] as String);
          final clips = <Map<String, dynamic>>[];
          for (var i = 0; i < 2; i++) {
            final file = File('${temp.path}/${args['key']}-$i.mp4');
            await file.writeAsBytes([i + 1]);
            clips.add({
              'path': file.path,
              'startWallMs': i * 10000,
              'durationMs': 1000,
            });
          }
          return {'clips': clips, 'complete': exportComplete};
        });
    client = MockClient((req) async {
      requests.add('${req.method} ${req.url.path}');
      if (req.url.path == '/match-proof/pending') {
        return http.Response(
          jsonEncode({
            'requests': [
              {'matchId': leg2, 'seriesId': series},
            ],
          }),
          200,
        );
      }
      if (req.method == 'PUT') {
        return http.Response(
          '',
          failSecondPut && req.bodyBytes.single == 2 ? 503 : 200,
        );
      }
      final body = jsonDecode(req.body) as Map;
      if (req.url.path == '/match-proof/presign') {
        serial++;
        return http.Response(
          jsonEncode({
            'url': 'https://storage.test/put/$serial',
            'key': 'match-proof/$leg2/user/$serial.mp4',
          }),
          200,
        );
      }
      if (req.url.path == '/match-proof/confirm' && failConfirmation) {
        return http.Response('{}', 503);
      }
      if (req.url.path == '/match-proof/failed') {
        failures.add(body['reason'] as String);
      }
      return http.Response('{"ok":true}', 200);
    });
  });

  tearDown(() async {
    MatchProofService.debugReset();
    await ReplayBufferService.stop();
    SocketService.debugReset();
    client.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await storage.deleteAll();
    await temp.delete(recursive: true);
    debugDefaultTargetPlatformOverride = null;
  });

  test(
    'transient request failures retry automatically with a bounded budget',
    () async {
      var calls = 0;
      final timers = <_ManualTimer>[];
      final unavailable = MockClient((req) async {
        calls++;
        return http.Response('{}', 503);
      });
      await runZoned(
        () => http.runWithClient(() async {
          await MatchProofService.checkPending();
          expect(calls, 1);
          var timer = timers.singleWhere((t) => t.isActive);
          expect(timer.duration, const Duration(seconds: 30));
          timer.fire();
          await MatchProofService.checkPending();
          expect(calls, 2);
          timer = timers.singleWhere((t) => t.isActive);
          expect(timer.duration, const Duration(seconds: 60));
          timer.fire();
          await MatchProofService.checkPending();
          expect(calls, 3);
          expect(timers.where((t) => t.isActive), isEmpty);
        }, () => unavailable),
        zoneSpecification: ZoneSpecification(
          createTimer: (self, parent, zone, duration, callback) {
            if (duration < const Duration(seconds: 30)) {
              return parent.createTimer(zone, duration, callback);
            }
            final timer = _ManualTimer(duration, () => zone.run(callback));
            timers.add(timer);
            return timer;
          },
        ),
      );
      unavailable.close();
    },
  );

  test(
    'simultaneous leg/series registrations survive storage read/write races',
    () async {
      await MatchProofService.startMatch(key: leg1);
      await Future.wait([
        MatchProofService.noteId(leg2),
        MatchProofService.noteId(series),
      ]);
      expect(
        (await registry())[leg1]['ids'],
        containsAll([leg1, leg2, series]),
      );
    },
  );

  test(
    'a partial upload keeps footage and only retries the missing clip',
    () async {
      await prepare();
      await http.runWithClient(() async {
        failSecondPut = true;
        await MatchProofService.checkPending();
        expect(deleted, isEmpty);
        expect(failures, ['partial_upload:1/2']);
        expect(requests.where((r) => r.startsWith('PUT')), hasLength(2));
        failSecondPut = false;
        await MatchProofService.checkPending();
        expect(requests.where((r) => r.startsWith('PUT')), hasLength(3));
        expect(deleted, [leg1]);
        expect(await registry(), isEmpty);
      }, () => client);
    },
  );

  test(
    'lost confirmation retries the uploaded object after app restart',
    () async {
      await prepare();
      await http.runWithClient(() async {
        failConfirmation = true;
        await MatchProofService.checkPending();
        expect(deleted, isEmpty);
        MatchProofService.debugReset();
        failConfirmation = false;
        await MatchProofService.checkPending();
        expect(requests.where((r) => r.startsWith('PUT')), hasLength(2));
        expect(requests.where((r) => r.endsWith('/presign')), hasLength(2));
        expect(deleted, [leg1]);
      }, () => client);
    },
  );

  test(
    'incomplete native export never deletes the source or its registry',
    () async {
      await prepare();
      exportComplete = false;
      await http.runWithClient(() async {
        await MatchProofService.checkPending();
        expect(deleted, isEmpty);
        expect(failures, ['partial_export']);
        expect(await registry(), contains(leg1));
        exportComplete = true;
        await MatchProofService.checkPending();
        expect(requests.where((r) => r.startsWith('PUT')), hasLength(2));
        expect(deleted, [leg1]);
      }, () => client);
    },
  );

  test('a dispute cannot cut or delete an actively recording series', () async {
    await prepare();
    ReplayBufferService.arm();
    await http.runWithClient(() async {
      await MatchProofService.checkPending();
      expect(cuts, isEmpty);
      expect(deleted, isEmpty);
      await ReplayBufferService.stop();
      await MatchProofService.checkPending();
      expect(cuts, [leg1]);
      expect(deleted, [leg1]);
    }, () => client);
  });

  test(
    'overlapping pending checks upload once and process every retention key',
    () async {
      await prepare();
      await MatchProofService.startMatch(key: leg2);
      await MatchProofService.noteId(series);
      await http.runWithClient(() async {
        await Future.wait([
          MatchProofService.checkPending(),
          MatchProofService.checkPending(),
        ]);
        expect(cuts, [leg1, leg2]);
        expect(deleted, [leg1, leg2]);
        expect(requests.where((r) => r.startsWith('PUT')), hasLength(4));
      }, () => client);
    },
  );

  test('returning to the app resumes an incomplete proof', () async {
    await prepare();
    await http.runWithClient(() async {
      failSecondPut = true;
      await MatchProofService.checkPending();
      failSecondPut = false;
      WidgetsBinding.instance.handleAppLifecycleStateChanged(
        AppLifecycleState.paused,
      );
      WidgetsBinding.instance.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      );
      await MatchProofService.checkPending();
      expect(deleted, [leg1]);
      expect(requests.where((r) => r.startsWith('PUT')), hasLength(3));
    }, () => client);
  });
}

class _ManualTimer implements Timer {
  _ManualTimer(this.duration, this.callback);
  final Duration duration;
  final void Function() callback;
  @override
  bool isActive = true;
  @override
  int tick = 0;
  @override
  void cancel() {
    isActive = false;
  }

  void fire() {
    if (!isActive) return;
    isActive = false;
    tick++;
    callback();
  }
}
