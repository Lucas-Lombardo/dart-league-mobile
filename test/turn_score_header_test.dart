import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/l10n/app_localizations.dart';
import 'package:mobile/services/auto_scoring_service.dart';
import 'package:mobile/utils/app_theme.dart';
import 'package:mobile/widgets/auto_score_display.dart';
import 'package:mobile/widgets/game_turn_ui.dart';

class _ScoringStub extends AutoScoringService {
  @override
  bool get isCapturing => true;
}

Future<void> _pumpMatch(
  WidgetTester tester, {
  required Size size,
  Locale locale = const Locale('fr'),
  double? mine = 120,
  double? opponent = 36,
  bool myTurn = true,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  final scoring = _ScoringStub();
  addTearDown(tester.view.reset);
  addTearDown(scoring.dispose);
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
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          padding: size.height > 800
              ? const EdgeInsets.only(top: 59, bottom: 34)
              : const EdgeInsets.only(top: 24),
        ),
        child: Material(
          child: AutoScoreGameView(
            scoringService: scoring,
            onConfirm: () {},
            onBack: () {},
            onToggleAudio: () {},
            onSwitchCamera: () {},
            localCameraPreview: const ColoredBox(color: Colors.white),
            header: TurnScoreHeader(
              myName: 'Dodo180',
              opponentName: 'Bot Or',
              myScore: 381,
              opponentScore: 465,
              myAverage: mine,
              opponentAverage: opponent,
              seriesTitle: locale.languageCode == 'fr'
                  ? 'BO3 · Manche 1'
                  : 'BO3 · Leg 1',
              showBadges: false,
              myTurn: myTurn,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  expect(tester.getSize(find.byType(AutoScoreGameView)), size);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // Ahem is wider than the shipped typeface. Measure the real match font.
    final loader = FontLoader(AppTheme.fontFamily);
    for (final weight in ['Regular', 'SemiBold', 'Bold', 'ExtraBold']) {
      loader.addFont(rootBundle.load('assets/fonts/Manrope-$weight.ttf'));
    }
    await loader.load();
  });

  for (final size in [
    const Size(320, 568),
    const Size(375, 667),
    const Size(393, 852),
    const Size(568, 320),
  ]) {
    for (final locale in [const Locale('fr'), const Locale('en')]) {
      testWidgets('$size / $locale fits with both maximum averages', (
        tester,
      ) async {
        await _pumpMatch(
          tester,
          size: size,
          locale: locale,
          mine: 180,
          opponent: 180,
        );
        expect(tester.takeException(), isNull);
        expect(find.byType(Scrollable), findsNothing);
        // The old header used 2 + 11 + 8 + 24 + 8 + 11 = 64 px.
        expect(
          tester.getSize(find.byType(TurnScoreHeader)).height,
          lessThanOrEqualTo(64.1),
        );
        for (final score in ['381', '465']) {
          expect(
            tester
                .renderObject<RenderParagraph>(find.text(score))
                .didExceedMaxLines,
            isFalse,
          );
        }
        final bottom = tester.getBottomRight(find.byType(AutoScoreGameView));
        expect(bottom.dy, size.height);
      });
    }
  }

  testWidgets('averages stay visible, coloured and fixed when turns change', (
    tester,
  ) async {
    await _pumpMatch(tester, size: const Size(393, 852));
    final text = find.text('Moy. 120.0  |  36.0', findRichText: true);
    expect(text, findsOneWidget);
    final label = tester.widget<Text>(
      find.descendant(of: find.byType(TurnAverages), matching: find.byType(Text)),
    );
    final spans = (label.textSpan! as TextSpan).children!.cast<TextSpan>();
    expect(spans[1].style!.color, AppTheme.playerBlueBright);
    expect(spans[3].style!.color, AppTheme.opponentPinkBright);
    final camera = tester.getRect(find.byType(GameCameraPanel));
    final averages = tester.getRect(find.byType(TurnAverages));
    await tester.pump(const Duration(seconds: 5));
    expect(text, findsOneWidget);
    await _pumpMatch(tester, size: const Size(393, 852), myTurn: false);
    expect(tester.getRect(find.byType(GameCameraPanel)), camera);
    expect(tester.getRect(find.byType(TurnAverages)), averages);
  });

  testWidgets('missing average keeps its player slot instead of showing zero', (
    tester,
  ) async {
    await _pumpMatch(tester, size: const Size(320, 568), mine: null);
    expect(find.text('Moy. —  |  36.0', findRichText: true), findsOneWidget);
    await _pumpMatch(tester, size: const Size(320, 568), opponent: null);
    expect(find.text('Moy. 120.0  |  —', findRichText: true), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('camera controls stay opaque over a white feed', (tester) async {
    await _pumpMatch(tester, size: const Size(320, 568));
    final controls = find.byType(GameControlButton);
    expect(controls, findsNWidgets(3));
    for (final control in controls.evaluate()) {
      final box = tester.widget<Container>(
        find.descendant(
          of: find.byWidget(control.widget),
          matching: find.byType(Container),
        ),
      );
      final decoration = box.decoration! as BoxDecoration;
      expect(decoration.color!.a, 1);
      expect(decoration.color, AppTheme.gameBackground);
      expect(tester.getSize(find.byWidget(control.widget)), const Size(40, 40));
    }
  });
}
