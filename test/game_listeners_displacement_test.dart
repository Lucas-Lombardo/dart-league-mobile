import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/providers/game_provider.dart';
import 'package:mobile/providers/tournament_game_provider.dart';
import 'package:mobile/services/socket_service.dart';

const p1 = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const p2 = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const matchId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';

/// The 2026-10-24 stuck ranked match: a cancelled ranked search left
/// GameProvider's "listeners set up" flag on, a tournament then took over the
/// single-slot game_started / game_state_sync handlers and removed them on
/// reset — and the next ranked match never left "INITIALISATION DU MATCH…",
/// retry button included, because ensureListenersSetup trusted the flag.
void main() {
  setUp(() {
    SocketService.debugReset();
    SocketService.debugEmitOverride = (_, _) {};
  });

  tearDown(SocketService.debugReset);

  test('GameProvider re-registers after a tournament displaced and removed its handlers', () async {
    final game = GameProvider();
    final tournament = TournamentGameProvider();

    // Ranked search started then cancelled: listeners up, no match, no reset.
    game.ensureListenersSetup();

    // Tournament played and finished in the same session.
    await tournament.ensureListenersSetup();
    tournament.reset();
    expect(SocketService.ownsHandler('game_started', game), isFalse);

    // Next ranked match.
    game.ensureListenersSetup();
    game.initGame(matchId, p2, p1);
    SocketService.debugDispatch('game_state_sync', {
      'matchId': matchId,
      'player1Id': p1,
      'player2Id': p2,
      'player1Score': 472,
      'player2Score': 501,
      'currentPlayerId': p2,
      'dartsThrown': 0,
      'currentRoundThrows': [],
    });

    expect(game.gameStarted, isTrue);
    game.dispose();
    tournament.dispose();
  });

  test('TournamentGameProvider re-registers after GameProvider took its handlers', () async {
    final game = GameProvider();
    final tournament = TournamentGameProvider();

    await tournament.ensureListenersSetup();
    game.ensureListenersSetup();
    expect(SocketService.ownsHandler('game_state_sync', tournament), isFalse);

    await tournament.ensureListenersSetup();
    expect(SocketService.ownsHandler('game_started', tournament), isTrue);
    expect(SocketService.ownsHandler('game_state_sync', tournament), isTrue);
    game.dispose();
    tournament.dispose();
  });

  test('a provider that still owns its handlers is left untouched', () {
    final game = GameProvider();
    game.ensureListenersSetup();
    game.ensureListenersSetup();
    expect(SocketService.ownsHandler('game_started', game), isTrue);
    game.dispose();
  });
}
