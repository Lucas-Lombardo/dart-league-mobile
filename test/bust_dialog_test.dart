import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/l10n/app_localizations.dart';
import 'package:mobile/providers/game_provider.dart';
import 'package:mobile/services/socket_service.dart';
import 'package:mobile/widgets/game_turn_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('online bust', () {
    late GameProvider game;
    setUp(() {
      SocketService.debugReset();
      SocketService.debugEmitOverride = (_, _) {};
      game = GameProvider();
      game.ensureListenersSetup();
      game.initGame('match', 'me', 'other');
      SocketService.debugDispatch('game_started', {
        'matchId': 'match',
        'currentPlayerId': 'me',
        'player1Id': 'me',
      });
    });
    tearDown(() {
      game.dispose();
      SocketService.debugReset();
    });

    for (final scenario in [
      (remaining: 130, valid: ['T20', 'T20'], bust: 'T20', total: 180),
      (remaining: 40, valid: <String>[], bust: 'T20', total: 60),
      (remaining: 20, valid: <String>[], bust: 'S20', total: 20),
      (remaining: 21, valid: <String>[], bust: 'S20', total: 20),
    ]) {
      test('${scenario.remaining}: ${scenario.valid} + ${scenario.bust}', () {
        SocketService.debugDispatch('score_updated', {
          'matchId': 'match',
          'currentPlayerId': 'me',
          'player1Score': scenario.remaining - visitPoints(scenario.valid),
          'player2Score': 501,
          'currentRoundThrows': scenario.valid,
          'dartsThrown': scenario.valid.length,
        });
        SocketService.debugDispatch('pending_bust', {
          'matchId': 'match',
          'playerId': 'me',
          'notation': scenario.bust,
        });
        final figures = pendingBustFigures(
          currentScore: game.myScore,
          currentRoundScore: game.currentRoundScore,
          pendingData: game.pendingData,
        );
        expect(figures, (
          remaining: scenario.remaining,
          visitTotal: scenario.total,
        ));
      });
    }

    test('sync with the busting dart included never fabricates figures', () {
      SocketService.debugDispatch('game_state_sync', {
        'matchId': 'match',
        'player1Id': 'me',
        'currentPlayerId': 'me',
        'player1Score': 10,
        'player2Score': 501,
        'currentRoundThrows': ['T20', 'T20', 'T20'],
        'dartsThrown': 3,
        'pendingState': 'pending_bust',
        'pendingPlayerId': 'me',
      });
      expect(game.pendingType, 'bust');
      expect(
        pendingBustFigures(
          currentScore: game.myScore,
          currentRoundScore: game.currentRoundScore,
          pendingData: game.pendingData,
        ),
        isNull,
      );
    });
  });

  for (final figures in [null, (remaining: 40, visitTotal: 60)]) {
    testWidgets('bust guidance remains visible with figures=$figures', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('fr'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(
            body: GameBustDialogContent(
              reason: 'Bust',
              remaining: figures?.remaining,
              visitTotal: figures?.visitTotal,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final widget = find.byType(GameBustDialogContent);
      expect(widget, findsOneWidget);
      final l10n = AppLocalizations.of(tester.element(widget));
      expect(find.text(l10n.confirmPassOrEdit), findsOneWidget);
      if (figures != null) {
        expect(find.text(l10n.bustFigures(40, 60)), findsOneWidget);
      }
    });
  }
}
