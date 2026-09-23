import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/win_confirmation.dart';
import 'package:mobile/providers/game_provider.dart';
import 'package:mobile/providers/tournament_game_provider.dart';
import 'package:mobile/services/socket_service.dart';

const p1 = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const p2 = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const matchId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
Map<String, dynamic> confirmation({
  int seconds = 300,
  String phase = 'pending',
}) => {
  'playerId': p1, 'phase': phase, 'closesCall': true,
  // Intentionally different from the device clock.
  'serverNow': '2020-01-01T00:00:00.000Z',
  'deadline': DateTime.utc(
    2020,
  ).add(Duration(seconds: seconds)).toIso8601String(),
};
Map<String, dynamic> checkout() => {
  'matchId': matchId,
  'playerId': p1,
  'currentPlayerId': p1,
  'player1Score': 0,
  'player2Score': 100,
  'dartsThrown': 3,
  'currentRoundThrows': ['S20', 'S20', 'D20'],
  'finalDart': {'notation': 'D20'},
  'winConfirmation': confirmation(),
};

void main() {
  test(
    'uses the server clock, warns at 30 seconds and never decides the winner locally',
    () {
      final pending = WinConfirmation.fromJson(confirmation(seconds: 30))!;
      expect(pending.secondsLeft, inInclusiveRange(29, 30));
      expect(pending.warning, isTrue);
      expect(
        WinConfirmation.fromJson(confirmation(seconds: 31))!.warning,
        isFalse,
      );
      expect(
        WinConfirmation.fromJson(confirmation(seconds: 0))!.shouldCloseCall,
        isFalse,
      );
    },
  );

  for (final tournament in [false, true]) {
    group(tournament ? 'tournament checkout' : 'ranked/friendly checkout', () {
      late dynamic game;
      Future<void> start(String me) async {
        if (tournament) {
          game = TournamentGameProvider();
          await game.ensureListenersSetup();
          game.initTournamentGame(
            tournamentMatchId: 'series',
            gameMatchId: matchId,
            tournamentId: 'tournament',
            myUserId: me,
            opponentUserId: me == p1 ? p2 : p1,
            bestOf: 3,
            roundName: 'Final',
          );
        } else {
          game = GameProvider();
          game.ensureListenersSetup();
          game.initGame(matchId, me, me == p1 ? p2 : p1);
        }
        SocketService.debugDispatch('game_started', {
          'matchId': matchId,
          'currentPlayerId': p1,
          'player1Id': p1,
        });
      }

      setUp(() {
        SocketService.debugReset();
        SocketService.debugEmitOverride = (_, _) {};
      });
      tearDown(() {
        game.dispose();
        SocketService.debugReset();
      });

      test(
        'opponent immediately sees the winning dart, score and verification status',
        () async {
          await start(p2);
          SocketService.debugDispatch('pending_win', checkout());
          expect(game.opponentScore, 0);
          expect(game.myScore, 100);
          expect(game.opponentRoundThrows, ['S20', 'S20', 'D20']);
          expect(game.pendingConfirmation, isFalse);
          expect(game.winConfirmation.pending, isTrue);
          expect(game.gameEnded, isFalse);
        },
      );
      test(
        'opponent reconnect restores the winning visit without pending_win',
        () async {
          await start(p2);
          expect(game.opponentRoundThrows, isEmpty);
          SocketService.debugDispatch('game_state_sync', {
            ...checkout(),
            'pendingState': 'pending_win',
            'pendingPlayerId': p1,
          });
          expect(game.opponentRoundThrows, ['S20', 'S20', 'D20']);
          expect(game.opponentScore, 0);
          expect(game.winConfirmation.pending, isTrue);
          expect(game.pendingConfirmation, isFalse);
          // A later genuine correction must also replace the opponent visit.
          SocketService.debugDispatch('game_state_sync', {
            ...checkout(),
            'pendingState': null,
            'pendingPlayerId': null,
            'winConfirmation': null,
            'player1Score': 40,
            'dartsThrown': 2,
            'currentRoundThrows': ['S20', 'S20'],
          });
          expect(game.opponentRoundThrows, ['S20', 'S20']);
          expect(game.opponentScore, 40);
          expect(game.winConfirmation, isNull);
        },
      );
      test(
        'ordered pre-checkout sync then winning dart keeps confirmation open',
        () async {
          await start(p1);
          // The backend lock now guarantees this order even if its series read
          // overlaps the winning throw. A genuine correction still clears it.
          SocketService.debugDispatch('game_state_sync', {
            ...checkout(),
            'pendingState': null,
            'pendingPlayerId': null,
            'winConfirmation': null,
            'player1Score': 40,
            'dartsThrown': 2,
            'currentRoundThrows': ['S20', 'S20'],
          });
          SocketService.debugDispatch('pending_win', checkout());
          SocketService.debugDispatch('win_confirmation', {
            ...confirmation(),
            'matchId': matchId,
          });
          expect(game.pendingType, 'win');
          expect(game.pendingConfirmation, isTrue);
          expect(game.myScore, 0);
          expect(game.currentRoundThrows, ['S20', 'S20', 'D20']);
          expect(game.winConfirmation.pending, isTrue);
        },
      );
      test(
        'supports old server final-dart payloads without inventing a deadline',
        () async {
          await start(p2);
          SocketService.debugDispatch('score_updated', {
            'matchId': matchId,
            'currentPlayerId': p1,
            'player1Score': 40,
            'player2Score': 100,
            'dartsThrown': 2,
            'currentRoundThrows': ['S20', 'S20'],
          });
          SocketService.debugDispatch(
            'pending_win',
            checkout()
              ..remove('currentRoundThrows')
              ..remove('winConfirmation'),
          );
          expect(game.opponentRoundThrows, ['S20', 'S20', 'D20']);
          expect(game.winConfirmation.deadline, isNull);
        },
      );
      test(
        'mixed-version match keeps the modal without advertising automatic confirmation',
        () async {
          await start(p1);
          SocketService.debugDispatch(
            'pending_win',
            checkout()..['winConfirmation'] = null,
          );
          expect(game.pendingType, 'win');
          expect(game.winConfirmation.deadline, isNull);
          expect(game.winConfirmation.warning, isFalse);
          SocketService.debugDispatch('game_won', {
            'matchId': matchId,
            'winnerId': p1,
            'winConfirmation': null,
          });
          expect(game.gameEnded, isTrue);
          expect(game.pendingConfirmation, isFalse);
        },
      );
      test('winner retains the modal until the server confirms', () async {
        await start(p1);
        SocketService.debugDispatch('pending_win', checkout());
        expect(game.pendingType, 'win');
        SocketService.debugDispatch('game_won', {
          'matchId': matchId,
          'winnerId': p1,
          'loserId': p2,
          'winConfirmation': {
            ...confirmation(phase: 'confirmed'),
            'callClosed': true,
          },
        });
        expect(game.gameEnded, isTrue);
        expect(game.winnerId, p1);
        expect(game.pendingType, isNull);
        expect(game.pendingConfirmation, isFalse);
      });
      for (final legacyServer in [false, true]) {
        test('verification survives sync and reconnect without a deadline (legacy server: $legacyServer)', () async {
          await start(p2);
          final sync = <String, dynamic>{
            ...checkout(),
            'pendingState': 'pending_win',
            'pendingPlayerId': p1,
            'winConfirmation': null,
          };
          if (legacyServer) sync.remove('winConfirmation');
          // Reconnect without having received the initial pending_win event.
          SocketService.debugDispatch('game_state_sync', sync);
          expect(game.winConfirmation?.pending, isTrue);
          expect(game.winConfirmation?.playerId, p1);
          expect(game.winConfirmation.deadline, isNull);
          SocketService.debugDispatch('game_state_sync', sync);
          expect(game.winConfirmation?.pending, isTrue);
          expect(game.pendingConfirmation, isFalse);
          SocketService.debugDispatch('game_won', {
            'matchId': matchId, 'winnerId': p1, 'winConfirmation': null,
          });
          expect(game.winConfirmation, isNull);
          expect(game.gameEnded, isTrue);
        });
      }
      test('a compatibility downgrade keeps verification but removes the old deadline', () async {
        await start(p2);
        SocketService.debugDispatch('pending_win', checkout());
        expect(game.winConfirmation.deadline, isNotNull);
        SocketService.debugDispatch('game_state_sync', {
          ...checkout(), 'pendingState': 'pending_win',
          'pendingPlayerId': p1, 'winConfirmation': null,
        });
        expect(game.winConfirmation?.pending, isTrue);
        expect(game.winConfirmation.deadline, isNull);
        expect(game.winConfirmation.warning, isFalse);
      });
      test(
        'correction is visible to the opponent and removes the winning dart',
        () async {
          await start(p2);
          SocketService.debugDispatch('pending_win', checkout());
          SocketService.debugDispatch('win_confirmation', {
            'matchId': matchId,
            'playerId': p1,
            'phase': 'correcting',
            'deadline': null,
          });
          SocketService.debugDispatch('dart_undone', {
            'matchId': matchId,
            'playerId': p1,
            'currentPlayerId': p1,
            'player1Score': 40,
            'player2Score': 100,
            'dartsThrown': 2,
            'currentRoundThrows': ['S20', 'S20'],
          });
          expect(game.winConfirmation.correcting, isTrue);
          expect(game.winConfirmation.deadline, isNull);
          expect(game.opponentRoundThrows, ['S20', 'S20']);
          expect(game.opponentScore, 40);
          // Periodic/reconnect snapshots have no persisted correction clock.
          for (var i = 0; i < 2; i++) {
            SocketService.debugDispatch('game_state_sync', {
              ...checkout(), 'pendingState': null, 'pendingPlayerId': null,
              'winConfirmation': null, 'player1Score': 40, 'dartsThrown': 2,
              'currentRoundThrows': ['S20', 'S20'],
            });
            expect(game.winConfirmation?.correcting, isTrue);
            expect(game.winConfirmation.deadline, isNull);
          }
          SocketService.debugDispatch('round_complete', {
            'matchId': matchId,
            'nextPlayerId': p2,
            'player1Score': 40,
            'player2Score': 100,
          });
          expect(game.winConfirmation, isNull);
        },
      );
      test('a sync after a missed round_complete clears the correction notice', () async {
        await start(p2);
        SocketService.debugDispatch('win_confirmation', {
          'matchId': matchId, 'playerId': p1, 'phase': 'correcting',
          'deadline': null,
        });
        SocketService.debugDispatch('game_state_sync', {
          ...checkout(), 'pendingState': null, 'pendingPlayerId': null,
          'winConfirmation': null, 'currentPlayerId': p2,
          'player1Score': 40, 'dartsThrown': 0, 'currentRoundThrows': <String>[],
        });
        expect(game.winConfirmation, isNull);
      });
      test('a mixed-version undo starts the correction notice without a lifecycle event', () async {
        await start(p2);
        SocketService.debugDispatch('pending_win', checkout()..['winConfirmation'] = null);
        SocketService.debugDispatch('dart_undone', {
          'matchId': matchId, 'playerId': p1, 'removedDart': null,
        });
        expect(game.winConfirmation?.pending, isTrue);
        final corrected = <String, dynamic>{
          'matchId': matchId, 'playerId': p1, 'currentPlayerId': p1,
          'removedDart': 'D20', 'player1Score': 40, 'player2Score': 100,
          'dartsThrown': 2, 'currentRoundThrows': ['S20', 'S20'],
        };
        SocketService.debugDispatch('dart_undone', corrected);
        expect(game.winConfirmation?.correcting, isTrue);
        expect(game.winConfirmation.deadline, isNull);
        SocketService.debugDispatch('game_state_sync', {
          ...corrected, 'pendingState': null, 'pendingPlayerId': null,
          'winConfirmation': null,
        });
        expect(game.winConfirmation?.correcting, isTrue);
        SocketService.debugDispatch('round_complete', {
          'matchId': matchId, 'nextPlayerId': p2,
        });
        expect(game.winConfirmation, isNull);
      });
      test(
        'reconnect restores the modal, then an authoritative correction clears it',
        () async {
          await start(p1);
          final sync = {
            ...checkout(),
            'pendingState': 'pending_win',
            'pendingPlayerId': p1,
          };
          SocketService.debugDispatch('game_state_sync', sync);
          expect(game.pendingType, 'win');
          expect(game.winConfirmation.secondsLeft, inInclusiveRange(299, 300));
          SocketService.debugDispatch('game_state_sync', {
            ...sync,
            'pendingState': null,
            'pendingPlayerId': null,
            'winConfirmation': null,
            'dartsThrown': 2,
            'currentRoundThrows': ['S20', 'S20'],
            'player1Score': 40,
          });
          expect(game.pendingType, isNull);
          expect(game.pendingConfirmation, isFalse);
        },
      );
      test(
        'ignores confirmation events for another match and after reset',
        () async {
          await start(p1);
          SocketService.debugDispatch('win_confirmation', {
            ...confirmation(),
            'matchId': 'other',
          });
          expect(game.winConfirmation, isNull);
          game.reset();
          SocketService.debugDispatch('win_confirmation', {
            ...confirmation(),
            'matchId': matchId,
          });
          expect(game.winConfirmation, isNull);
        },
      );
    });
  }
}
