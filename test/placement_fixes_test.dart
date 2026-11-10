import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/l10n/app_localizations.dart';
import 'package:mobile/providers/placement_provider.dart';
import 'package:mobile/screens/placement/checkout_hint_bar.dart';
import 'package:mobile/screens/placement/placement_camera_setup_screen.dart';
import 'package:mobile/screens/placement/placement_hub_screen.dart';
import 'package:provider/provider.dart';

/// The four placement bugs of the 2026-08-12 audit (Agent 2b):
///  1. the match was created before the camera setup and died meanwhile;
///  2. bot-turn / complete errors were swallowed (frozen bot, dead end);
///  3. a resumed match restarted the player at 501;
///  4. the double wall (suggested finish).

/// A server that fails on demand. `failures` transient errors before each
/// success; `permanent` makes the next call a refusal.
class _FakeApi extends PlacementApi {
  _FakeApi();

  int startCalls = 0;
  int botTurnCalls = 0;
  int completeCalls = 0;
  int failures = 0;
  String? permanent;
  final List<int?> visitIndexes = [];
  Map<String, dynamic> startResponse = {
    'matchId': 'm1',
    'botDifficulty': 1,
    'gameState': {'player1Score': 501, 'player2Score': 501, 'player1Rounds': <int>[], 'player2Rounds': <int>[]},
  };
  Map<String, dynamic> status = {
    'matchesPlayed': 0,
    'wins': 0,
    'losses': 0,
    'isComplete': false,
    'nextMatchNumber': 1,
    'nextBotDifficulty': 1,
    'nextBotName': 'Bot',
    'results': <dynamic>[],
  };
  Map<String, dynamic> active = {'active': false};

  Future<Map<String, dynamic>> _maybeFail(Map<String, dynamic> ok) async {
    final refusal = permanent;
    if (refusal != null) throw Exception(refusal);
    if (failures > 0) {
      failures--;
      throw Exception('Connection timeout - Please check your internet');
    }
    return ok;
  }

  @override
  Future<Map<String, dynamic>> getStatus() async => status;

  @override
  Future<Map<String, dynamic>> getActiveMatch() async => active;

  @override
  Future<Map<String, dynamic>> startMatch() {
    startCalls++;
    return _maybeFail(startResponse);
  }

  @override
  Future<Map<String, dynamic>> botTurn(
    String matchId, {
    int? playerRoundScore,
    List<String>? playerRoundThrows,
    bool? playerBusted,
    List<Map<String, dynamic>>? playerRoundDarts,
    int? visitIndex,
  }) {
    botTurnCalls++;
    visitIndexes.add(visitIndex);
    return _maybeFail({
      'botThrows': [
        {'baseScore': 20, 'isDouble': false, 'isTriple': true, 'score': 60, 'notation': 'T20'},
      ],
      'botNewScore': 441,
      'isCheckout': false,
      'isBust': false,
      'gameState': {'player1Score': 401, 'player2Score': 441},
    });
  }

  @override
  Future<Map<String, dynamic>> completeMatch(String matchId, String? winnerId, {int? player1Score}) {
    completeCalls++;
    return _maybeFail({
      'placementComplete': false,
      'placementStatus': {...status, 'matchesPlayed': 1, 'nextMatchNumber': 2},
    });
  }
}

PlacementProvider _provider(_FakeApi api) =>
    PlacementProvider(api: api, retryDelays: const [Duration.zero, Duration.zero]);

void main() {
  group('bug 2 — bot turn errors are retried, then surfaced', () {
    test('a transient failure is retried with the same visit index', () async {
      final api = _FakeApi();
      final p = _provider(api);
      await p.startMatch();
      api.failures = 2;
      final ok = await p.triggerBotTurn(playerRoundScore: 100, playerRoundThrows: ['T20', 'S20', 'S20']);
      expect(ok, isTrue);
      expect(api.botTurnCalls, 3);
      expect(api.visitIndexes, [0, 0, 0]);
      expect(p.player2Score, 441);
      expect(p.hasPendingBotTurn, isFalse);

      // The next visit is index 1.
      await p.triggerBotTurn(playerRoundScore: 60, playerRoundThrows: ['S20', 'S20', 'S20']);
      expect(api.visitIndexes.last, 1);
    });

    test('a failure that outlasts the retries is kept for "Retry", never swallowed', () async {
      final api = _FakeApi();
      final p = _provider(api);
      await p.startMatch();
      api.failures = 3;
      final ok = await p.triggerBotTurn(playerRoundScore: 100, playerRoundThrows: ['T20', 'S20', 'S20']);
      expect(ok, isFalse);
      expect(p.error, isNotNull);
      expect(p.errorIsPermanent, isFalse);
      expect(p.hasPendingBotTurn, isTrue);
      // The bot did not "play": its score did not move.
      expect(p.player2Score, 501);

      final retried = await p.retryBotTurn();
      expect(retried, isTrue);
      // Same visit, same index: a server that did record it replays its answer.
      expect(api.visitIndexes, [0, 0, 0, 0]);
      expect(p.player2Score, 441);
      expect(p.hasPendingBotTurn, isFalse);
    });

    test('a refusal (match forfeited under the player) is not retried', () async {
      final api = _FakeApi();
      final p = _provider(api);
      await p.startMatch();
      api.permanent = 'Error 400: Match not in progress';
      final ok = await p.triggerBotTurn(playerRoundScore: 100, playerRoundThrows: ['T20', 'S20', 'S20']);
      expect(ok, isFalse);
      expect(api.botTurnCalls, 1);
      expect(p.errorIsPermanent, isTrue);
    });

    test('saving the result is retried, and a failure keeps the match for "Retry"', () async {
      final api = _FakeApi();
      final p = _provider(api);
      await p.startMatch();
      api.failures = 3;
      expect(await p.completeMatch('u1', player1Score: 0), isNull);
      expect(p.currentMatchId, 'm1');
      expect(api.completeCalls, 3);
      final result = await p.completeMatch('u1', player1Score: 0);
      expect(result, isNotNull);
      expect(p.currentMatchId, isNull);
      expect(p.status?.matchesPlayed, 1);
    });

    test('"already completed" means an earlier attempt went through', () async {
      final api = _FakeApi();
      final p = _provider(api);
      await p.startMatch();
      api.permanent = 'Error 400: Match already completed';
      final result = await p.completeMatch('u1', player1Score: 0);
      expect(result, {'alreadyCompleted': true});
      expect(p.currentMatchId, isNull);
      expect(p.error, isNull);
    });
  });

  group('bug 3 — a resumed match keeps the player score', () {
    test('startMatch on a match in progress restores scores, rounds and visit index', () async {
      final api = _FakeApi()
        ..startResponse = {
          'matchId': 'm1',
          'botDifficulty': 2,
          'gameState': {
            'player1Score': 356,
            'player2Score': 380,
            'player1Rounds': [100, 0, 45],
            'player2Rounds': [60, 41, 20],
          },
        };
      final p = _provider(api);
      expect(await p.startMatch(), isTrue);
      expect(p.player1Score, 356);
      expect(p.player2Score, 380);
      expect(p.resumedPlayerRounds, [100, 0, 45]);
      expect(p.resumedBotRounds, [60, 41, 20]);
      await p.triggerBotTurn(playerRoundScore: 26, playerRoundThrows: ['S20', 'S5', 'S1']);
      // The server holds 3 visits: this one is the 4th.
      expect(api.visitIndexes, [3]);
    });

    test('an old server without rounds still starts at its scores', () async {
      final api = _FakeApi()
        ..startResponse = {
          'matchId': 'm1',
          'gameState': {'player1Score': 501, 'player2Score': 501},
        };
      final p = _provider(api);
      await p.startMatch();
      expect(p.resumedPlayerRounds, isEmpty);
      await p.triggerBotTurn(playerRoundScore: 60, playerRoundThrows: ['S20', 'S20', 'S20']);
      expect(api.visitIndexes, [0]);
    });
  });

  group('bug 1 — the match is created after the camera setup', () {
    Future<(List<Route<dynamic>>, _FakeApi, PlacementProvider)> pumpHub(
      WidgetTester tester, {
      Map<String, dynamic>? active,
    }) async {
      final api = _FakeApi();
      if (active != null) api.active = active;
      final provider = _provider(api);
      final pushed = <Route<dynamic>>[];
      await tester.pumpWidget(
        ChangeNotifierProvider<PlacementProvider>.value(
          value: provider,
          child: MaterialApp(
            locale: const Locale('fr'),
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            navigatorObservers: [_PushRecorder(pushed)],
            home: const PlacementHubScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      pushed.clear();
      return (pushed, api, provider);
    }

    /// The pushed camera screen, built without mounting it (no camera here).
    PlacementCameraSetupScreen cameraScreenOf(WidgetTester tester, Route<dynamic> route) {
      final page = route as MaterialPageRoute<dynamic>;
      final ctx = tester.element(find.byType(PlacementHubScreen));
      return page.builder(ctx) as PlacementCameraSetupScreen;
    }

    testWidgets('"Play" opens the camera first and creates nothing on the server', (tester) async {
      final (pushed, api, provider) = await pumpHub(tester);
      expect(tester.getSize(find.byType(PlacementHubScreen)).width, greaterThan(0));
      final l10n = await AppLocalizations.delegate.load(const Locale('fr'));
      await tester.tap(find.text(l10n.placementHubPlayMatch(1)));

      expect(pushed, hasLength(1));
      expect(api.startCalls, 0);
      final screen = cameraScreenOf(tester, pushed.single);
      expect(screen.beforeStart, isNotNull);

      // The camera screen calls it on "Play": that is when the match exists.
      expect(await screen.beforeStart!(), isTrue);
      expect(api.startCalls, 1);
      expect(provider.currentMatchId, 'm1');
    });

    testWidgets('resuming goes through the camera too, and re-arms the match on "Play"', (tester) async {
      final (pushed, api, _) = await pumpHub(tester, active: {
        'active': true,
        'matchId': 'm1',
        'botDifficulty': 1,
        'botName': 'Bot',
        'gameState': {'player1Score': 356, 'player2Score': 380, 'player1Rounds': [145], 'player2Rounds': [121]},
      });
      final l10n = await AppLocalizations.delegate.load(const Locale('fr'));
      await tester.tap(find.text(l10n.placementHubResumeMatch('Bot')));
      expect(pushed, hasLength(1));
      expect(api.startCalls, 0);
      expect(cameraScreenOf(tester, pushed.single).beforeStart, isNotNull);
    });
  });

  group('bug 4 — the suggested finish', () {
    test('book routes within the darts left', () {
      expect(suggestedCheckout(170, 3), ['T20', 'T20', 'Bull']);
      expect(suggestedCheckout(100, 3), ['T20', 'D20']);
      expect(suggestedCheckout(40, 1), ['D20']);
      expect(suggestedCheckout(50, 1), ['Bull']);
      expect(suggestedCheckout(3, 2), ['S1', 'D1']);
    });

    test('nothing when there is no finish this visit', () {
      expect(suggestedCheckout(171, 3), isNull);
      expect(suggestedCheckout(169, 3), isNull); // bogey
      expect(suggestedCheckout(100, 1), isNull); // not in one dart
      expect(suggestedCheckout(1, 3), isNull);
      expect(suggestedCheckout(40, 0), isNull);
      expect(CheckoutHintBar.maybe(remaining: 501, dartsLeft: 3), isNull);
    });

    testWidgets('the bar shows the route', (tester) async {
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('fr'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: CheckoutHintBar(remaining: 32, dartsLeft: 3)),
      ));
      await tester.pump();
      expect(find.text('Finish'), findsOneWidget);
      expect(find.text('D16'), findsOneWidget);
    });
  });
}

class _PushRecorder extends NavigatorObserver {
  final List<Route<dynamic>> pushed;
  _PushRecorder(this.pushed);

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => pushed.add(route);
}
