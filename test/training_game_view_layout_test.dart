import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/l10n/app_localizations.dart';
import 'package:mobile/l10n/app_localizations_en.dart';
import 'package:mobile/l10n/app_localizations_fr.dart';
import 'package:mobile/screens/training/logic/jdc_challenge_strategy.dart';
import 'package:mobile/screens/training/training_game_view.dart';
import 'package:mobile/services/auto_scoring_service.dart';
import 'package:mobile/widgets/game_turn_ui.dart';

/// Capture is what pulls the AUTO VALIDATION chip in — the tallest state of
/// the in-drill screen, and the one on screen for most of a visit.
class _ScoringStub extends AutoScoringService {
  _ScoringStub({required this.capturing});

  final bool capturing;

  @override
  bool get isCapturing => capturing;
}

/// Logical sizes of the phones the drill has to fit on, portrait then
/// landscape, plus the safe-area insets of the notched ones.
const _sizes = <String, (Size, EdgeInsets)>{
  'iPhone 15 Pro Max': (Size(430, 932), EdgeInsets.only(top: 59, bottom: 34)),
  'iPhone 14 Pro': (Size(393, 852), EdgeInsets.only(top: 59, bottom: 34)),
  'iPhone SE': (Size(375, 667), EdgeInsets.only(top: 20)),
  'small Android': (Size(320, 568), EdgeInsets.only(top: 24)),
  'landscape': (Size(852, 393), EdgeInsets.only(left: 59, right: 59)),
};

/// French is the longest of the two locales on every string that matters here.
final _locales = <Locale, AppLocalizations>{
  const Locale('en'): AppLocalizationsEn(),
  const Locale('fr'): AppLocalizationsFr(),
};

Future<void> _pumpDrill(
  WidgetTester tester,
  Size size,
  EdgeInsets padding, {
  required Locale locale,
  bool capturing = true,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(size: size, padding: padding),
        child: TrainingGameView(
          scoringService: _ScoringStub(capturing: capturing),
          strategy: JdcChallengeStrategy(),
          pending: const [],
          title: 'JDC Challenge',
          onConfirm: () {},
          onEditSlot: (_, _) {},
          onRemoveLast: () {},
          onSwitchCamera: () {},
          onToggleAi: () {},
        ),
      ),
    ),
  );
  // Localization delegates resolve async — the drill only builds on the
  // second frame.
  await tester.pump();
  // Guard against a vacuous test: without this the assertions pass just as
  // happily on an empty tree.
  expect(tester.getSize(find.byType(TrainingGameView)), size);
}

void main() {
  // The drill screen is read from the oche: every block must be on screen at
  // once, on every phone, in both orientations, in both locales.
  for (final entry in _sizes.entries) {
    final (size, padding) = entry.value;

    for (final locale in _locales.entries) {
      final l10n = locale.value;

      testWidgets('${entry.key} fits without scrolling in ${locale.key}', (
        tester,
      ) async {
        await _pumpDrill(tester, size, padding, locale: locale.key);

        // A RenderFlex overflow surfaces as a pending exception here.
        expect(tester.takeException(), isNull);
        expect(find.byType(Scrollable), findsNothing);

        // The action label wraps instead of being clipped, as it used to be
        // when the button sized itself intrinsically. The test font is far
        // wider than the real one, so passing here means real margin.
        final label = tester.renderObject<RenderParagraph>(
          find.text(l10n.trainingEndRoundEarly.toUpperCase()),
        );
        expect(label.didExceedMaxLines, isFalse);
      });
    }

    testWidgets('${entry.key} keeps the camera still when capture stops', (
      tester,
    ) async {
      const locale = Locale('fr');
      await _pumpDrill(tester, size, padding, locale: locale);
      final capturing = tester.getSize(find.byType(GameCameraPanel));

      await _pumpDrill(tester, size, padding, locale: locale, capturing: false);
      expect(tester.getSize(find.byType(GameCameraPanel)), capturing);
      expect(tester.takeException(), isNull);
    });
  }
}
