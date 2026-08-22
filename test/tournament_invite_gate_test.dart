import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:mobile/l10n/app_localizations.dart';
import 'package:mobile/models/tournament.dart';
import 'package:mobile/providers/auth_provider.dart';
import 'package:mobile/providers/game_provider.dart';
import 'package:mobile/providers/tournament_provider.dart';
import 'package:mobile/widgets/tournament_invite_gate.dart';

// The global "your tournament match is ready" prompt. Tournoi #4
// (2026-08-22): players spectating or chatting never saw their invite and
// were forfeited — the gate must surface it whatever screen is open, exactly
// once per invite, and step aside while a lobby owns the flow.
void main() {
  const me = 'me';

  TournamentMatch invite(String id, {DateTime? sentAt}) => TournamentMatch(
        id: id,
        tournamentId: 't1',
        tournamentName: 'Tournoi #4',
        roundNumber: 2,
        roundName: 'quarter_final',
        matchNumber: 1,
        player1Id: me,
        player1Username: 'Moi',
        player2Id: 'opp',
        player2Username: 'Louis DRF',
        status: 'waiting_for_players',
        player1Score: 0,
        player2Score: 0,
        bestOf: 3,
        player1Ready: false,
        player2Ready: false,
        inviteSentAt: sentAt ?? DateTime.now(),
      );

  late TournamentProvider tournaments;
  late GameProvider game;
  final navigatorKey = GlobalKey<NavigatorState>();

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tournaments = TournamentProvider();
    game = GameProvider();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider.value(value: tournaments),
          ChangeNotifierProvider.value(value: game),
        ],
        child: MaterialApp(
          navigatorKey: navigatorKey,
          locale: const Locale('fr'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => TournamentInviteGate(
            navigatorKey: navigatorKey,
            child: child ?? const SizedBox.shrink(),
          ),
          home: const Scaffold(body: Text('SPECTATE SCREEN')),
        ),
      ),
    );
    await tester.pump();
  }

  Finder promptTitle() => find.text('Ton match est prêt !');

  Future<void> settle(WidgetTester tester) async {
    await tester.pump(); // microtask-deferred evaluation → push
    await tester.pump(); // frame that mounts the pushed route
    await tester.pump(const Duration(milliseconds: 400)); // route transition
  }

  testWidgets('a new invite raises the prompt over whatever screen is open',
      (tester) async {
    await pumpApp(tester);
    expect(promptTitle(), findsNothing);

    tournaments.debugSeedPendingMatches([invite('m1')], myUserId: me);
    await settle(tester);

    expect(promptTitle(), findsOneWidget);
    expect(find.text('vs Louis DRF'), findsOneWidget);
    expect(find.text('Tournoi #4'), findsOneWidget);
    expect(find.text('Accepter et rejoindre'), findsOneWidget);
    // The screen underneath is still there — the prompt is an overlay.
    expect(find.text('SPECTATE SCREEN'), findsOneWidget);
    // Countdown runs from inviteSentAt (7-minute window).
    expect(find.textContaining('Temps restant: 06:5'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('"Plus tard" dismisses and the same invite never prompts again',
      (tester) async {
    await pumpApp(tester);
    tournaments.debugSeedPendingMatches([invite('m1')], myUserId: me);
    await settle(tester);
    expect(promptTitle(), findsOneWidget);

    await tester.tap(find.text('Plus tard'));
    await settle(tester);
    expect(promptTitle(), findsNothing);

    // Every poll re-delivers the same pending list.
    tournaments.debugSeedPendingMatches([invite('m1')]);
    await settle(tester);
    expect(promptTitle(), findsNothing);

    // A different invite does prompt.
    tournaments.debugSeedPendingMatches([invite('m2')]);
    await settle(tester);
    expect(promptTitle(), findsOneWidget);
  });

  testWidgets('held while a lobby is open, raised once it closes',
      (tester) async {
    await pumpApp(tester);
    tournaments.setMatchScreenOpen('previous');
    tournaments.debugSeedPendingMatches([invite('m1')], myUserId: me);
    await settle(tester);
    expect(promptTitle(), findsNothing);

    tournaments.setMatchScreenClosed('previous');
    await settle(tester);
    expect(promptTitle(), findsOneWidget);
  });

  testWidgets('closes itself when the invite leaves the pending list',
      (tester) async {
    await pumpApp(tester);
    tournaments.debugSeedPendingMatches([invite('m1')], myUserId: me);
    await settle(tester);
    expect(promptTitle(), findsOneWidget);

    // Sweep forfeited it (or the player readied from elsewhere).
    tournaments.debugSeedPendingMatches([]);
    await settle(tester);
    expect(promptTitle(), findsNothing);
  });

  testWidgets('an invite claimed by another path (push tap, chain) is silent',
      (tester) async {
    await pumpApp(tester);
    tournaments.markInviteHandled('m1');
    tournaments.debugSeedPendingMatches([invite('m1')], myUserId: me);
    await settle(tester);
    expect(promptTitle(), findsNothing);
  });

  testWidgets('half-window reminder re-raises a dismissed prompt',
      (tester) async {
    await pumpApp(tester);
    tournaments.debugSeedPendingMatches([invite('m1')], myUserId: me);
    await settle(tester);
    await tester.tap(find.text('Plus tard'));
    await settle(tester);
    expect(promptTitle(), findsNothing);

    // Backend nudge at 3:30, followed by the pending refresh it triggers.
    tournaments.debugEmitInviteReminder({'matchId': 'm1'});
    await tester.pump();
    tournaments.debugSeedPendingMatches([invite('m1')]);
    await settle(tester);
    expect(promptTitle(), findsOneWidget);
  });

  testWidgets('reminder while the prompt is on screen does not stack or repeat',
      (tester) async {
    await pumpApp(tester);
    tournaments.debugSeedPendingMatches([invite('m1')], myUserId: me);
    await settle(tester);
    expect(promptTitle(), findsOneWidget);

    tournaments.debugEmitInviteReminder({'matchId': 'm1'});
    await tester.pump();
    tournaments.debugSeedPendingMatches([invite('m1')]);
    await settle(tester);
    expect(promptTitle(), findsOneWidget);

    // Dismissing afterwards must not bring it straight back.
    await tester.tap(find.text('Plus tard'));
    await settle(tester);
    expect(promptTitle(), findsNothing);
  });

  testWidgets('reminder is ignored while the player is in that match lobby',
      (tester) async {
    await pumpApp(tester);
    tournaments.markInviteHandled('m1');
    tournaments.setMatchScreenOpen('m1');
    tournaments.debugSeedPendingMatches([invite('m1')], myUserId: me);
    await settle(tester);

    tournaments.debugEmitInviteReminder({'matchId': 'm1'});
    await tester.pump();
    tournaments.debugSeedPendingMatches([invite('m1')]);
    await settle(tester);
    expect(promptTitle(), findsNothing);

    // Leaving the lobby must not re-raise it either: the mark is intact.
    tournaments.setMatchScreenClosed('m1');
    await settle(tester);
    expect(promptTitle(), findsNothing);
  });

  test('nextUnhandledInvite skips handled ids, the excluded match and byes',
      () {
    final p = TournamentProvider();
    p.debugSeedPendingMatches([
      invite('a'),
      invite('b'),
      TournamentMatch(
        id: 'bye',
        tournamentId: 't1',
        roundNumber: 1,
        roundName: 'round_1',
        matchNumber: 9,
        player1Id: me,
        player2Id: null,
        status: 'waiting_for_players',
        player1Score: 0,
        player2Score: 0,
        bestOf: 3,
        player1Ready: false,
        player2Ready: false,
      ),
    ], myUserId: me);

    expect(p.nextUnhandledInvite()?.id, 'a');
    expect(p.nextUnhandledInvite(excludeMatchId: 'a')?.id, 'b');
    p.markInviteHandled('a');
    p.markInviteHandled('b');
    expect(p.nextUnhandledInvite(), isNull);
  });
}
