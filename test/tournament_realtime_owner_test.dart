import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/providers/tournament_provider.dart';

/// After a tournament match the app returns to a NEW home screen, and the
/// old one is disposed ~300 ms later: its stop used to kill the realtime the
/// new screen had just started (invites never reached the prompt).
void main() {
  test('a stop from a screen that no longer owns realtime is ignored', () {
    final tournaments = TournamentProvider();
    final oldHome = Object();
    final newHome = Object();

    tournaments.debugMarkRealtimeStarted(oldHome);
    // The new home takes over (startRealtime is a no-op when already
    // started, but it still records the owner).
    tournaments.startRealtime(owner: newHome);
    expect(tournaments.realtimeStarted, isTrue);

    tournaments.stopRealtime(owner: oldHome);
    expect(tournaments.realtimeStarted, isTrue,
        reason: 'the deferred dispose of the old home must not stop it');

    tournaments.stopRealtime(owner: newHome);
    expect(tournaments.realtimeStarted, isFalse);
  });

  test('an unowned stop (provider dispose) always stops', () {
    final tournaments = TournamentProvider();
    tournaments.debugMarkRealtimeStarted(Object());
    tournaments.stopRealtime();
    expect(tournaments.realtimeStarted, isFalse);
  });
}
