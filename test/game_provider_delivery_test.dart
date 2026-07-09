import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/providers/game_provider.dart';
import 'package:mobile/services/socket_service.dart';

const p1 = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const p2 = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const matchId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';

/// Everything the client must get right so a thrown dart is never lost:
/// it carries an id, it is re-sent until the server acks it, the turn cannot
/// be committed while one is in flight, and a late/stale server echo can never
/// free a slot that a real dart already occupies.
///
/// The counterpart backend tests live in
/// backend/src/game-state/dart-delivery.spec.ts — together they cover the
/// protocol that fixes the "threw 26, scored 21" report.
void main() {
  late List<({String event, Map<String, dynamic> data})> sent;
  late GameProvider game;

  /// Everything emitted so far for [event].
  List<Map<String, dynamic>> emitsOf(String event) =>
      sent.where((e) => e.event == event).map((e) => e.data).toList();

  /// The server's positive ack for a dart the client sent.
  void ackDart(Map<String, dynamic> throwPayload, {required int appliedIndex}) {
    SocketService.debugDispatch('throw_dart_ack', {
      'matchId': matchId,
      'dartId': throwPayload['dartId'],
      'applied': true,
      'appliedIndex': appliedIndex,
    });
  }

  setUp(() {
    sent = [];
    SocketService.debugReset();
    SocketService.debugEmitOverride = (event, data) {
      sent.add((event: event, data: Map<String, dynamic>.from(data as Map)));
    };

    game = GameProvider();
    game.ensureListenersSetup();
    // The server announces its capabilities on authentication. Without this the
    // client stays on the legacy fire-and-forget path — see the last group.
    SocketService.debugDispatch('authenticated', {
      'userId': p1,
      'socketId': 's1',
      'supportsDartAck': true,
    });
    game.initGame(matchId, p1, p2);
    // game_started makes it our turn and fixes the score mapping.
    SocketService.debugDispatch('game_started', {
      'matchId': matchId,
      'currentPlayerId': p1,
      'player1Id': p1,
    });
  });

  tearDown(() {
    game.dispose();
    SocketService.debugReset();
  });

  group('every dart is delivery-tracked', () {
    test('throw_dart carries a unique dartId and its turn index', () async {
      await game.throwDart(baseScore: 20, multiplier: ScoreMultiplier.single);
      await game.throwDart(baseScore: 1, multiplier: ScoreMultiplier.single);

      final throws = emitsOf('throw_dart');
      expect(throws, hasLength(2));
      expect(throws[0]['dartIndex'], 0);
      expect(throws[1]['dartIndex'], 1);
      expect(throws[0]['dartId'], isNotEmpty);
      expect(throws[1]['dartId'], isNot(throws[0]['dartId']));
      expect(game.unackedDartCount, 2);
    });

    test('an acked dart leaves the pending queue', () async {
      await game.throwDart(baseScore: 20, multiplier: ScoreMultiplier.single);
      expect(game.unackedDartCount, 1);

      ackDart(emitsOf('throw_dart').single, appliedIndex: 0);

      expect(game.unackedDartCount, 0);
      expect(game.ackedDartsThisRound, 1);
    });

    test('an emit that throws (dead socket) keeps the dart queued for retry', () async {
      SocketService.debugEmitOverride = (_, _) => throw Exception('Socket not connected');

      await game.throwDart(baseScore: 5, multiplier: ScoreMultiplier.single);

      // The dart is NOT dropped: it waits in the pending queue. Before the fix
      // the guard was rolled back and the dart vanished with the UI still
      // showing it.
      expect(game.unackedDartCount, 1);
    });
  });

  group('the turn cannot be committed while a dart is in flight', () {
    test('confirmRound defers instead of sending a short round', () async {
      await game.throwDart(baseScore: 20, multiplier: ScoreMultiplier.single);
      await game.throwDart(baseScore: 1, multiplier: ScoreMultiplier.single);
      await game.throwDart(baseScore: 5, multiplier: ScoreMultiplier.single);
      expect(game.unackedDartCount, 3);

      game.confirmRound();

      // Nothing committed yet — the in-flight darts are re-sent first.
      expect(emitsOf('confirm_round'), isEmpty);
      expect(emitsOf('end_round_early'), isEmpty);
    });

    test('once every dart is echoed, confirm_round states the dart count', () async {
      for (final s in [20, 1, 5]) {
        await game.throwDart(baseScore: s, multiplier: ScoreMultiplier.single);
      }
      final throws = emitsOf('throw_dart');
      for (var i = 0; i < 3; i++) {
        ackDart(throws[i], appliedIndex: i);
      }
      SocketService.debugDispatch('score_updated', {
        'matchId': matchId,
        'player1Score': 475,
        'player2Score': 501,
        'currentPlayerId': p1,
        'dartsThrown': 3,
        'currentRoundThrows': ['S20', 'S1', 'S5'],
      });

      game.confirmRound();

      final confirms = emitsOf('confirm_round');
      expect(confirms, hasLength(1));
      expect(confirms.single['dartCount'], 3);
      // The visit really was 26 — this is the number the user watched land.
      expect(game.currentRoundScore, 26);
    });

    test('a confirm_round_rejected re-sends the un-acked darts', () async {
      await game.throwDart(baseScore: 20, multiplier: ScoreMultiplier.single);
      final firstAttempt = emitsOf('throw_dart').length;

      SocketService.debugDispatch('confirm_round_rejected', {
        'matchId': matchId,
        'reason': 'dart_count_mismatch',
        'serverDartsThrown': 0,
        'clientDartCount': 1,
      });

      expect(emitsOf('throw_dart').length, greaterThan(firstAttempt));
      // Re-sent with the SAME id, so the server dedups instead of double-scoring.
      final throws = emitsOf('throw_dart');
      expect(throws.last['dartId'], throws.first['dartId']);
    });
  });

  group('a stale echo can never free an occupied dart slot', () {
    test('score_updated lagging behind does not lower the emit guard', () async {
      for (final s in [20, 1, 5]) {
        await game.throwDart(baseScore: s, multiplier: ScoreMultiplier.single);
      }
      expect(game.unackedDartCount, 3);

      // The echo for dart 2 arrives after dart 3 was emitted.
      SocketService.debugDispatch('score_updated', {
        'matchId': matchId,
        'player1Score': 480,
        'player2Score': 501,
        'currentPlayerId': p1,
        'dartsThrown': 2,
        'currentRoundThrows': ['S20', 'S1'],
      });

      // A 4th dart must still be refused: three are accounted for.
      await game.throwDart(baseScore: 20, multiplier: ScoreMultiplier.single);
      expect(emitsOf('throw_dart'), hasLength(3));
    });

    test('an event from a different match is ignored', () async {
      SocketService.debugDispatch('score_updated', {
        'matchId': 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
        'player1Score': 3,
        'player2Score': 7,
        'currentPlayerId': p2,
        'dartsThrown': 2,
      });

      expect(game.myScore, 501);
      expect(game.opponentScore, 501);
      expect(game.isMyTurn, isTrue);
    });
  });

  group('reconnect reconciles with the server', () {
    test('a dart the server never received is re-delivered, not left phantom', () async {
      await game.throwDart(baseScore: 20, multiplier: ScoreMultiplier.single);
      await game.throwDart(baseScore: 1, multiplier: ScoreMultiplier.single);
      final throws = emitsOf('throw_dart');
      ackDart(throws[0], appliedIndex: 0);
      // Dart 2 was lost: it is still pending.
      expect(game.unackedDartCount, 1);

      final before = emitsOf('throw_dart').length;
      SocketService.debugDispatch('game_state_sync', {
        'matchId': matchId,
        'player1Id': p1,
        'player1Score': 481,
        'player2Score': 501,
        'currentPlayerId': p1,
        'dartsThrown': 1,
        'currentRoundThrows': ['S20'],
        'currentRoundDartIds': [throws[0]['dartId']],
        'pendingState': null,
      });

      // The missing dart is re-emitted with its original id.
      final after = emitsOf('throw_dart');
      expect(after.length, greaterThan(before));
      expect(after.last['dartId'], throws[1]['dartId']);
    });

    test('a sync whose dart ids cover our queue settles it without re-sending', () async {
      await game.throwDart(baseScore: 20, multiplier: ScoreMultiplier.single);
      final sentDart = emitsOf('throw_dart').single;
      final before = emitsOf('throw_dart').length;

      // The ack was lost but the server clearly has the dart.
      SocketService.debugDispatch('game_state_sync', {
        'matchId': matchId,
        'player1Id': p1,
        'player1Score': 481,
        'player2Score': 501,
        'currentPlayerId': p1,
        'dartsThrown': 1,
        'currentRoundThrows': ['S20'],
        'currentRoundDartIds': [sentDart['dartId']],
        'pendingState': null,
      });

      expect(game.unackedDartCount, 0);
      expect(emitsOf('throw_dart').length, before);
    });

    test('a pending win missed during a drop is restored from the sync', () async {
      SocketService.debugDispatch('game_state_sync', {
        'matchId': matchId,
        'player1Id': p1,
        'player1Score': 0,
        'player2Score': 200,
        'currentPlayerId': p1,
        'dartsThrown': 2,
        'currentRoundThrows': ['S20', 'D20'],
        'pendingState': 'pending_win',
        'pendingPlayerId': p1,
        'pendingReason': 'checkout',
      });

      // Without this the board sat at "reste 0" with no confirm dialog until
      // the turn timer forfeited someone.
      expect(game.pendingConfirmation, isTrue);
      expect(game.pendingType, 'win');
    });

    test('a pending bust for the OPPONENT never opens our dialog', () async {
      SocketService.debugDispatch('game_state_sync', {
        'matchId': matchId,
        'player1Id': p1,
        'player1Score': 100,
        'player2Score': 50,
        'currentPlayerId': p2,
        'dartsThrown': 2,
        'currentRoundThrows': ['S20', 'S20'],
        'pendingState': 'pending_bust',
        'pendingPlayerId': p2,
        'pendingReason': 'score_below_zero',
      });

      expect(game.pendingType, isNull);
    });
  });

  group('round completion resets delivery state', () {
    test('round_complete clears the pending queue and the guards', () async {
      await game.throwDart(baseScore: 20, multiplier: ScoreMultiplier.single);
      expect(game.unackedDartCount, 1);

      SocketService.debugDispatch('round_complete', {
        'matchId': matchId,
        'nextPlayerId': p2,
        'player1Score': 481,
        'player2Score': 501,
      });

      expect(game.unackedDartCount, 0);
      expect(game.ackedDartsThisRound, 0);
      expect(game.currentRoundThrows, isEmpty);
      expect(game.isMyTurn, isFalse);
    });

    test('darts are refused when it is not our turn', () async {
      SocketService.debugDispatch('round_complete', {
        'matchId': matchId,
        'nextPlayerId': p2,
        'player1Score': 501,
        'player2Score': 501,
      });

      await game.throwDart(baseScore: 20, multiplier: ScoreMultiplier.single);

      expect(emitsOf('throw_dart'), isEmpty);
    });
  });

  group('bare invalid_throw does not corrupt the turn', () {
    test('a payload with only a message leaves currentPlayerId intact', () async {
      SocketService.debugDispatch('invalid_throw', {
        'message': 'Invalid throw - not your turn or game not found',
      });

      // Before the fix this nulled currentPlayerId, so isMyTurn flipped to
      // false and the board froze until the corrective sync landed.
      expect(game.isMyTurn, isTrue);
      expect(game.currentPlayerId, p1);
    });
  });

  // A backend that never announced supportsDartAck cannot deduplicate darts.
  // Retrying an un-acked dart there would score it again on every attempt —
  // strictly worse than the bug this whole protocol fixes. So the client must
  // fall back to exactly the old fire-and-forget behaviour. This is what makes
  // a backend rollback (or a mobile-before-backend deploy) safe.
  group('against a legacy backend (no supportsDartAck)', () {
    setUp(() {
      // Re-authenticate as an old server: no capability flag.
      SocketService.debugDispatch('authenticated', {'userId': p1, 'socketId': 's1'});
    });

    test('the capability is off', () {
      expect(SocketService.supportsDartAck, isFalse);
    });

    test('throw_dart carries no dartId and no dartIndex', () async {
      await game.throwDart(baseScore: 20, multiplier: ScoreMultiplier.single);

      final sentDart = emitsOf('throw_dart').single;
      expect(sentDart.containsKey('dartId'), isFalse);
      expect(sentDart.containsKey('dartIndex'), isFalse);
      expect(game.unackedDartCount, 0); // nothing tracked, nothing to retry
    });

    test('confirm_round carries no dartCount and does not defer', () async {
      for (final s in [20, 1, 5]) {
        await game.throwDart(baseScore: s, multiplier: ScoreMultiplier.single);
      }
      // A legacy backend still echoes the round through score_updated; that
      // echo is the only thing that fills currentRoundThrows here.
      SocketService.debugDispatch('score_updated', {
        'matchId': matchId,
        'player1Score': 475,
        'player2Score': 501,
        'currentPlayerId': p1,
        'dartsThrown': 3,
        'currentRoundThrows': ['S20', 'S1', 'S5'],
      });

      game.confirmRound();

      final confirms = emitsOf('confirm_round');
      expect(confirms, hasLength(1));
      expect(confirms.single.containsKey('dartCount'), isFalse);
    });

    test('a dart is emitted exactly once and never re-sent', () async {
      await game.throwDart(baseScore: 20, multiplier: ScoreMultiplier.single);
      final before = emitsOf('throw_dart').length;

      // Anything that would normally trigger the retry pump.
      game.confirmRound();
      SocketService.debugDispatch('game_state_sync', {
        'matchId': matchId,
        'player1Id': p1,
        'player1Score': 501,
        'player2Score': 501,
        'currentPlayerId': p1,
        'dartsThrown': 0,
        'currentRoundThrows': <String>[],
      });

      expect(emitsOf('throw_dart').length, before);
    });

    test('losing the socket turns the capability back off', () async {
      // Back to a capable server…
      SocketService.debugDispatch('authenticated', {
        'userId': p1,
        'socketId': 's1',
        'supportsDartAck': true,
      });
      expect(SocketService.supportsDartAck, isTrue);

      // …then the socket drops. Until the next 'authenticated' we must assume
      // the worst, because a rollback may have happened underneath us.
      SocketService.debugReset();
      expect(SocketService.supportsDartAck, isFalse);
    });
  });
}
