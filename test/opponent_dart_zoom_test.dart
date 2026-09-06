import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/opponent_dart_zoom.dart';
import 'package:mobile/providers/game_provider.dart';
import 'package:mobile/services/socket_service.dart';

const p1 = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const p2 = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const matchId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';

/// The receiving side of the opponent-turn dart zoom (2026-09-06): the point
/// the thrower attaches to a dart reaches the provider on every event that
/// announces that dart, tells a new dart from a redraw, and is gone with the
/// visit.
void main() {
  late GameProvider game;

  setUp(() {
    SocketService.debugReset();
    SocketService.debugEmitOverride = (event, data) {};
    game = GameProvider();
    game.ensureListenersSetup();
    SocketService.debugDispatch('authenticated', {
      'userId': p1,
      'socketId': 's1',
      'supportsDartAck': true,
    });
    game.initGame(matchId, p1, p2);
    // The OPPONENT throws first: we are the ones watching.
    SocketService.debugDispatch('game_started', {
      'matchId': matchId,
      'currentPlayerId': p2,
      'player1Id': p1,
    });
  });

  tearDown(() {
    game.dispose();
    SocketService.debugReset();
  });

  Map<String, dynamic> scoreUpdated(List<String> throws, {Map<String, dynamic>? zoom}) => {
        'matchId': matchId,
        'player1Score': 501,
        'player2Score': 501 - throws.length,
        'currentPlayerId': p2,
        'dartsThrown': throws.length,
        'notation': throws.last,
        'currentRoundThrows': throws,
        'zoom': ?zoom,
      };

  test('parses only a sane point', () {
    expect(OpponentDartZoom.parse({'x': 0.2, 'y': 0.9}), isNotNull);
    expect(OpponentDartZoom.parse({'x': 0.2, 'y': 0.9, 'manual': true})!.manual, isTrue);
    expect(OpponentDartZoom.parse({'x': 1.2, 'y': 0.9}), isNull);
    expect(OpponentDartZoom.parse({'x': 'a', 'y': 0.9}), isNull);
    expect(OpponentDartZoom.parse(null), isNull);
    expect(OpponentDartZoom.parse('zoom'), isNull);
  });

  test('a score_updated with a point becomes the opponent dart zoom', () {
    expect(game.isMyTurn, isFalse);
    SocketService.debugDispatch(
      'score_updated',
      scoreUpdated(['T19'], zoom: {'x': 0.31, 'y': 0.72}),
    );
    final z = game.opponentDartZoom!;
    expect(z.notation, 'T19');
    expect(z.dartIndex, 1);
    expect(z.x, closeTo(0.31, 1e-9));
    expect(z.y, closeTo(0.72, 1e-9));
    expect(z.manual, isFalse);
    expect(game.opponentRoundThrows, ['T19']);
  });

  test('the same point twice is still two darts', () {
    SocketService.debugDispatch(
      'score_updated',
      scoreUpdated(['T19'], zoom: {'x': 0.5, 'y': 0.5}),
    );
    final first = game.opponentDartZoom!.seq;
    SocketService.debugDispatch(
      'score_updated',
      scoreUpdated(['T19', 'T19'], zoom: {'x': 0.5, 'y': 0.5}),
    );
    expect(game.opponentDartZoom!.seq, greaterThan(first));
    expect(game.opponentDartZoom!.dartIndex, 2);
  });

  test('a dart from an older app leaves the previous zoom alone', () {
    SocketService.debugDispatch(
      'score_updated',
      scoreUpdated(['T19'], zoom: {'x': 0.5, 'y': 0.5}),
    );
    final before = game.opponentDartZoom!;
    SocketService.debugDispatch('score_updated', scoreUpdated(['T19', 'S5']));
    expect(game.opponentDartZoom, same(before));
    expect(game.opponentRoundThrows, ['T19', 'S5']);
  });

  test('a typed score arrives flagged manual', () {
    SocketService.debugDispatch(
      'score_updated',
      scoreUpdated(['S20'], zoom: {'x': 0.5, 'y': 0.3, 'manual': true}),
    );
    expect(game.opponentDartZoom!.manual, isTrue);
  });

  test('their checkout dart rides on pending_win, their bust on pending_bust', () {
    SocketService.debugDispatch('pending_win', {
      'matchId': matchId,
      'playerId': p2,
      'finalDart': {'baseScore': 20, 'isDouble': true, 'isTriple': false, 'notation': 'D20'},
      'player1Score': 501,
      'player2Score': 0,
      'currentPlayerId': p2,
      'dartsThrown': 2,
      'zoom': {'x': 0.5, 'y': 0.1},
    });
    var z = game.opponentDartZoom!;
    expect(z.notation, 'D20');
    expect(z.dartIndex, 2);
    // Not OUR pending dialog.
    expect(game.pendingConfirmation, isFalse);

    SocketService.debugDispatch('pending_bust', {
      'matchId': matchId,
      'playerId': p2,
      'reason': 'bust',
      'notation': 'T20',
      'player1Score': 501,
      'player2Score': 40,
      'currentPlayerId': p2,
      'dartsThrown': 3,
      'zoom': {'x': 0.5, 'y': 0.2},
    });
    z = game.opponentDartZoom!;
    expect(z.notation, 'T20');
    expect(z.dartIndex, 3);
    expect(game.pendingConfirmation, isFalse);
  });

  test('the visit ending clears it', () {
    SocketService.debugDispatch(
      'score_updated',
      scoreUpdated(['T19'], zoom: {'x': 0.5, 'y': 0.5}),
    );
    expect(game.opponentDartZoom, isNotNull);
    SocketService.debugDispatch('round_complete', {
      'matchId': matchId,
      'currentPlayerId': p1,
      'player1Score': 501,
      'player2Score': 444,
    });
    expect(game.opponentDartZoom, isNull);
    expect(game.opponentRoundThrows, isEmpty);
  });
}
