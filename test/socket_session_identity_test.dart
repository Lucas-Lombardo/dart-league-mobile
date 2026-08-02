import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/services/socket_service.dart';

/// Regression cover for the account-switch bug: the socket bakes its JWT in at
/// construction and is reused for the whole process, so signing out and back
/// in as another account left it authenticated as the PREVIOUS user. The
/// server then had no socket for the signed-in player — every match event
/// (invites, matchReadyUpdate, tournamentMatchStart, game_started) was dropped
/// while the app still looked online, and the events this app emitted were
/// attributed to the old account.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(SocketService.debugReset);
  tearDown(SocketService.debugReset);

  group('socket identity follows the signed-in user', () {
    test('a handshake naming another user is not adopted as the session socket',
        () {
      SocketService.setSessionUser('user-a');

      SocketService.debugDispatch('authenticated', {
        'userId': 'user-b',
        'supportsDartAck': true,
      });

      expect(SocketService.belongsToSession, isFalse);
      // Capabilities of a socket this user will never receive events on must
      // not be adopted either.
      expect(SocketService.supportsDartAck, isFalse);
    });

    test('a handshake naming the signed-in user is adopted', () {
      SocketService.setSessionUser('user-a');

      SocketService.debugDispatch('authenticated', {
        'userId': 'user-a',
        'supportsDartAck': true,
      });

      expect(SocketService.authenticatedUserId, 'user-a');
      expect(SocketService.supportsDartAck, isTrue);
    });

    test('switching account notifies session listeners so per-user state drops',
        () {
      var notified = 0;
      void listener() => notified++;
      SocketService.addSessionChangeListener(listener);

      SocketService.setSessionUser('user-a');
      expect(notified, 0, reason: 'first sign-in of the process is not a switch');

      SocketService.setSessionUser('user-b');
      expect(notified, 1);

      SocketService.setSessionUser('user-b');
      expect(notified, 1, reason: 'same user must not re-fire');

      SocketService.setSessionUser(null);
      expect(notified, 2, reason: 'sign-out is a session change too');

      SocketService.removeSessionChangeListener(listener);
    });
  });

  group('handler ownership', () {
    test('off() from a displaced owner leaves the live handler alone', () {
      final gameProvider = Object();
      final tournamentProvider = Object();
      var gameCalls = 0;
      var tournamentCalls = 0;

      // Both providers listen to the same event name; last one in owns the
      // single slot.
      SocketService.on('game_started', (_) => gameCalls++, owner: gameProvider);
      SocketService.on('game_started', (_) => tournamentCalls++,
          owner: tournamentProvider);

      // The idle provider resets (its reset() clears the same event list).
      SocketService.off('game_started', owner: gameProvider);

      SocketService.debugDispatch('game_started', {});
      expect(tournamentCalls, 1, reason: 'the live match must still be fed');
      expect(gameCalls, 0);

      // The owner of the live handler can still remove it.
      SocketService.off('game_started', owner: tournamentProvider);
      SocketService.debugDispatch('game_started', {});
      expect(tournamentCalls, 1);
    });
  });
}
