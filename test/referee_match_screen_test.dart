import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/l10n/app_localizations.dart';
import 'package:mobile/models/local_match_config.dart';
import 'package:mobile/models/referee_match.dart';
import 'package:mobile/screens/local_match/local_match_entry_screen.dart';
import 'package:mobile/screens/local_match/local_match_setup_screen.dart';
import 'package:mobile/screens/local_match/referee_match_screen.dart';
import 'package:mobile/screens/local_match/referee_match_setup_screen.dart';
import 'package:mobile/utils/app_theme.dart';

RefereeMatch game({int bestOf = 3}) => RefereeMatch(
  config: LocalMatchConfig(
    player1Name: 'Lucas',
    player2Name: 'Thomas',
    bestOf: bestOf,
  ),
);

void leave(RefereeMatch match, int remaining) {
  for (final total in [180, 180, 141 - remaining]) {
    match.setTotal(total);
    match.validateVisit();
    match.setTotal(0);
    match.validateVisit();
  }
}

Future<void> pump(
  WidgetTester tester,
  Widget screen, {
  Size size = const Size(393, 852),
  Locale locale = const Locale('fr'),
  double textScale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.themeData,
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(
          textScaler: TextScaler.linear(textScale),
          padding: size.height > 800
              ? const EdgeInsets.only(top: 59, bottom: 34)
              : const EdgeInsets.only(top: 24),
        ),
        child: child!,
      ),
      home: screen,
    ),
  );
  await tester.pumpAndSettle();
  expect(find.byType(screen.runtimeType), findsOneWidget);
}

Future<void> tap(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final fonts = FontLoader(AppTheme.fontFamily);
    for (final weight in ['Regular', 'SemiBold', 'Bold', 'ExtraBold']) {
      fonts.addFont(rootBundle.load('assets/fonts/Manrope-$weight.ttf'));
    }
    await fonts.load();
  });
  setUp(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMessageHandler(
      'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
      (_) async => const StandardMessageCodec().encodeMessage([null]),
    );
  });

  testWidgets('entry keeps the automatic setup accessible', (tester) async {
    await pump(tester, const LocalMatchEntryScreen());
    await tap(tester, 'local-automatic');
    expect(find.byType(LocalMatchSetupScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('entry → referee settings → a manual 501 with selected rules', (
    tester,
  ) async {
    await pump(tester, const LocalMatchEntryScreen());
    await tap(tester, 'local-referee');
    expect(find.byType(RefereeMatchSetupScreen), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('referee-name-0')),
      '  Alice  ',
    );
    await tester.enterText(find.byKey(const ValueKey('referee-name-1')), 'Bob');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tap(tester, 'referee-target-3');
    await tap(tester, 'referee-double-out');
    await tap(tester, 'referee-first-1');
    await tap(tester, 'referee-start');
    final match = tester
        .widget<RefereeMatchScreen>(find.byType(RefereeMatchScreen))
        .match;
    expect(match.config.player1Name, 'Alice');
    expect(match.config.player2Name, 'Bob');
    expect(match.config.startingScore, 501);
    expect(match.config.legsToWin, 3);
    expect(match.config.doubleOut, isFalse);
    expect(match.activePlayer, 1);
    expect(match.inputMode, RefereeInputMode.total);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    '131 → T15 announces 86, cross removes dart, direct validation keeps helper',
    (tester) async {
      final match = game();
      leave(match, 131);
      await pump(tester, RefereeMatchScreen(match: match));
      await tap(tester, 'referee-tab-darts');
      expect(find.text('En attente'), findsNWidgets(3));
      await tap(tester, 'referee-multiplier-3');
      await tap(tester, 'referee-dart-15');
      expect(find.text('T15'), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('referee-remaining')))
            .data,
        '86',
      );
      expect(match.scores.first, 131);
      await tap(tester, 'referee-remove-0');
      expect(match.draftDarts, isEmpty);
      expect(find.text('En attente'), findsNWidgets(3));
      await tap(tester, 'referee-multiplier-3');
      await tap(tester, 'referee-dart-15');
      await tap(tester, 'referee-validate');
      expect(match.scores.first, 86);
      expect(match.activePlayer, 1);
      expect(match.inputMode, RefereeInputMode.darts);
      expect(find.text('En attente'), findsNWidgets(3));
      await tap(tester, 'referee-undo');
      expect(match.activePlayer, 0);
      expect(match.scores.first, 131);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'numeric total changes provisional score before committing and averages after',
    (tester) async {
      final match = game();
      await pump(tester, RefereeMatchScreen(match: match));
      await tap(tester, 'referee-digit-6');
      await tap(tester, 'referee-digit-0');
      expect(match.scores.first, 501);
      expect(find.text('441'), findsOneWidget);
      await tap(tester, 'referee-validate');
      expect(match.scores.first, 441);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('referee-average-0')))
            .data,
        contains('60,0'),
      );
      await tap(tester, 'referee-history');
      expect(find.textContaining('501 − 60'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'switching a total to darts can be cancelled without losing the draft',
    (tester) async {
      final match = game()..setTotal(60);
      await pump(tester, RefereeMatchScreen(match: match));
      await tap(tester, 'referee-tab-darts');
      await tester.tap(find.widgetWithText(TextButton, 'Annuler').last);
      await tester.pumpAndSettle();
      expect(match.totalInput, '60');
      expect(match.inputMode, RefereeInputMode.total);
      await tap(tester, 'referee-tab-darts');
      await tester.tap(find.text('Recommencer le calcul'));
      await tester.pumpAndSettle();
      expect(match.inputMode, RefereeInputMode.darts);
      expect(match.draftDarts, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('bust confirmation can be cancelled and then committed', (
    tester,
  ) async {
    final match = game();
    leave(match, 41);
    match.setTotal(40);
    await pump(tester, RefereeMatchScreen(match: match));
    await tap(tester, 'referee-validate');
    await tester.tap(find.widgetWithText(TextButton, 'Annuler').last);
    await tester.pumpAndSettle();
    expect(match.totalInput, '40');
    expect(match.activePlayer, 0);
    await tap(tester, 'referee-validate');
    await tester.tap(
      find.widgetWithText(ElevatedButton, 'Valider la volée').last,
    );
    await tester.pumpAndSettle();
    expect(match.history.last.bust, isTrue);
    expect(match.scores.first, 41);
    expect(match.activePlayer, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('checkout confirmation, leg transition and undo stay coherent', (
    tester,
  ) async {
    final match = game();
    leave(match, 40);
    match.useDarts();
    match.enterDart(RefereeDart(20, 2));
    await pump(tester, RefereeMatchScreen(match: match));
    await tap(tester, 'referee-validate');
    expect(find.byKey(const ValueKey('referee-checkout-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('referee-checkout-2')), findsNothing);
    await tap(tester, 'referee-checkout-1');
    expect(match.legs.first, 1);
    await tap(tester, 'referee-next-leg');
    expect(match.activePlayer, 1);
    expect(match.scores, [501, 501]);
    expect(match.inputMode, RefereeInputMode.darts);
    await tap(tester, 'referee-undo');
    expect(match.legs.first, 0);
    expect(match.scores.first, 40);
    expect(tester.takeException(), isNull);
  });

  testWidgets('winning visit can be undone from the match result', (
    tester,
  ) async {
    final match = game(bestOf: 1);
    leave(match, 40);
    match.setTotal(40);
    await pump(tester, RefereeMatchScreen(match: match));
    await tap(tester, 'referee-validate');
    await tap(tester, 'referee-checkout-1');
    expect(match.winner, 0);
    await tap(tester, 'referee-undo-win');
    expect(match.winner, isNull);
    expect(match.scores.first, 40);
    expect(tester.takeException(), isNull);
  });

  for (final size in [
    const Size(320, 568),
    const Size(375, 667),
    const Size(393, 852),
    const Size(568, 320),
  ]) {
    for (final locale in [const Locale('fr'), const Locale('en')]) {
      testWidgets('both inputs fit $size / $locale with visible validation', (
        tester,
      ) async {
        final match = game();
        await pump(
          tester,
          RefereeMatchScreen(match: match),
          size: size,
          locale: locale,
        );
        expect(tester.takeException(), isNull);
        final button = find.byKey(const ValueKey('referee-validate'));
        expect(tester.getRect(button).bottom, lessThanOrEqualTo(size.height));
        await tap(tester, 'referee-tab-darts');
        expect(find.byKey(const ValueKey('referee-slot-2')), findsOneWidget);
        await tap(tester, 'referee-bull-50');
        expect(match.preview.points, 50);
        expect(tester.takeException(), isNull);
        expect(tester.getRect(button).bottom, lessThanOrEqualTo(size.height));
      });
    }
  }

  testWidgets(
    'the entire helper is visible without scrolling on a standard phone',
    (tester) async {
      final match = game()..useDarts();
      await pump(tester, RefereeMatchScreen(match: match));
      final bull = tester.getRect(
        find.byKey(const ValueKey('referee-bull-50')),
      );
      final validate = tester.getRect(
        find.byKey(const ValueKey('referee-validate')),
      );
      expect(bull.bottom, lessThanOrEqualTo(validate.top - 6));
      await tester.tap(find.byKey(const ValueKey('referee-bull-50')));
      await tester.pumpAndSettle();
      expect(match.preview.points, 50);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'default names and rules start a match; back requires confirmation',
    (tester) async {
      await pump(tester, const LocalMatchEntryScreen());
      await tap(tester, 'local-referee');
      await tap(tester, 'referee-start');
      final screen = tester.widget<RefereeMatchScreen>(
        find.byType(RefereeMatchScreen),
      );
      expect(screen.match.config.player1Name, 'Joueur 1');
      expect(screen.match.config.player2Name, 'Joueur 2');
      expect(screen.match.config.doubleOut, isTrue);
      expect(screen.match.config.legsToWin, 2);
      final ctx = tester.element(find.byType(RefereeMatchScreen));
      final l10n = AppLocalizations.of(ctx);
      await tester.tap(find.byIcon(Icons.arrow_back).last);
      await tester.pumpAndSettle();
      expect(find.text(l10n.leaveMatchWarning), findsOneWidget);
      await tester.tap(
        find.widgetWithText(
          OutlinedButton,
          l10n.stay[0].toUpperCase() + l10n.stay.substring(1).toLowerCase(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(RefereeMatchScreen), findsOneWidget);
      await tester.tap(find.byIcon(Icons.arrow_back).last);
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(
          ElevatedButton,
          l10n.leave[0].toUpperCase() + l10n.leave.substring(1).toLowerCase(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(RefereeMatchSetupScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('large text and long player names remain usable', (tester) async {
    final match = RefereeMatch(
      config: const LocalMatchConfig(
        player1Name: 'Alexandre Maximilien',
        player2Name: 'Christophe Guillaume',
      ),
    );
    await pump(tester, RefereeMatchScreen(match: match), textScale: 1.5);
    await tap(tester, 'referee-tab-darts');
    await tap(tester, 'referee-bull-25');
    expect(match.preview.points, 25);
    expect(tester.takeException(), isNull);
  });
}
