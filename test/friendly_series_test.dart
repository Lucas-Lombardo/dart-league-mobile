import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:mobile/l10n/app_localizations.dart';
import 'package:mobile/providers/game_provider.dart';
import 'package:mobile/services/socket_service.dart';
import 'package:mobile/utils/friendly_match_launcher.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GameProvider game;
  late List<String> emitted;

  setUp(() {
    SocketService.debugReset();
    emitted = [];
    SocketService.debugEmitOverride = (event, data) => emitted.add(event);
    game = GameProvider()..ensureListenersSetup();
    game.initGame('leg1', 'p1', 'p2');
  });
  tearDown(() {
    game.dispose();
    SocketService.debugReset();
  });

  Map<String, dynamic> seriesFields({
    String matchId = 'leg1',
    int bestOf = 5,
  }) => {
    'matchId': matchId,
    'seriesId': 'series',
    'bestOf': bestOf,
    'isFriendly': true,
    'player1Id': 'p1',
    'player2Id': 'p2',
    'currentPlayerId': 'p1',
    'legNumber': 1,
    'player1LegsWon': 0,
    'player2LegsWon': 0,
    'legsNeeded': (bestOf ~/ 2) + 1,
  };

  test(
    'a friendly leg ends without enabling a rematch; the series end enables it',
    () {
      SocketService.debugDispatch('game_started', seriesFields());
      expect(game.isFriendly, isTrue);
      expect(game.bestOf, 5);
      SocketService.debugDispatch('game_won', {
        ...seriesFields(),
        'winnerId': 'p1',
        'isRankedSeries': true,
      });
      expect(game.gameEnded, isTrue);
      expect(game.matchOver, isFalse);
      game.requestRematch();
      expect(emitted, isNot(contains('rematch_request')));
      SocketService.debugDispatch('ranked_next_leg', {
        ...seriesFields(),
        'newMatchId': 'leg2',
        'legNumber': 2,
        'player1LegsWon': 1,
      });
      SocketService.debugDispatch('game_started', {
        ...seriesFields(matchId: 'leg2'),
        'legNumber': 2,
        'player1LegsWon': 1,
        'currentPlayerId': 'p2',
      });
      expect(game.matchId, 'leg2');
      expect(game.currentLeg, 2);
      expect(game.gameEnded, isFalse);
      SocketService.debugDispatch('ranked_match_won', {
        ...seriesFields(matchId: 'leg2'),
        'winnerId': 'p1',
        'player1LegsWon': 3,
      });
      expect(game.matchOver, isTrue);
      expect(game.isFriendly, isTrue);
      game.requestRematch();
      expect(emitted, contains('rematch_request'));
    },
  );

  test('a sync adopts a missed friendly leg and preserves its format', () {
    SocketService.debugDispatch('game_started', seriesFields(bestOf: 7));
    SocketService.debugDispatch('game_state_sync', {
      ...seriesFields(matchId: 'leg3', bestOf: 7),
      'legNumber': 3,
      'player1LegsWon': 1,
      'player2LegsWon': 1,
      'player1Score': 401,
      'player2Score': 301,
      'dartsThrown': 0,
    });
    expect(game.matchId, 'leg3');
    expect(game.currentLeg, 3);
    expect(game.bestOf, 7);
    expect(game.isFriendly, isTrue);
    expect(game.matchOver, isFalse);
  });

  test(
    'a series forfeit closes the series and retains the friendly result',
    () {
      SocketService.debugDispatch('game_started', seriesFields());
      SocketService.debugDispatch('player_forfeited', {
        ...seriesFields(),
        'winnerId': 'p2',
        'isRankedSeries': true,
        'player1LegsWon': 1,
        'player2LegsWon': 3,
      });
      expect(game.matchOver, isTrue);
      expect(game.isFriendly, isTrue);
      expect(game.opponentLegsWon, 3);
    },
  );

  test('match_ended heals a missed series result', () {
    SocketService.debugDispatch('game_started', seriesFields());
    SocketService.debugDispatch('match_ended', {
      ...seriesFields(),
      'winnerId': 'p2',
      'isRankedSeries': true,
      'player1LegsWon': 1,
      'player2LegsWon': 3,
    });
    expect(game.matchOver, isTrue);
    expect(game.isFriendly, isTrue);
    expect(game.winnerId, 'p2');
  });

  test('a BO1 still offers a rematch immediately after its only leg', () {
    SocketService.debugDispatch('game_started', {
      'matchId': 'leg1',
      'player1Id': 'p1',
      'currentPlayerId': 'p1',
      'isFriendly': true,
    });
    SocketService.debugDispatch('game_won', {
      'matchId': 'leg1',
      'winnerId': 'p1',
      'isFriendly': true,
    });
    expect(game.matchOver, isTrue);
    game.requestRematch();
    expect(emitted, contains('rematch_request'));
  });

  testWidgets('setup returns Cricket without score and BO7 on a small screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    ({String gameMode, int bestOf})? selected;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('fr'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                selected =
                    await showModalBottomSheet<({String gameMode, int bestOf})>(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => const FriendlyMatchSetupSheet(
                        friendUsername: 'Ami',
                        supportsCricket: true,
                        supportsSeries: true,
                      ),
                    );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(FriendlyMatchSetupSheet), findsOneWidget);
    for (final n in [1, 3, 5, 7]) {
      expect(find.text('BO$n'), findsOneWidget);
    }
    await tester.tap(find.text('Cricket'));
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(
      tester.element(find.byType(FriendlyMatchSetupSheet)),
    );
    await tester.tap(find.text(l10n.cricketNoScoreLabel));
    await tester.tap(find.text('BO7'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text(l10n.continueButton));
    await tester.tap(find.text(l10n.continueButton));
    await tester.pumpAndSettle();
    expect(selected, (gameMode: 'cricket_noscore', bestOf: 7));
    expect(tester.takeException(), isNull);
  });
}
