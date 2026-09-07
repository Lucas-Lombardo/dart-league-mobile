import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/l10n/app_localizations.dart';
import 'package:mobile/models/season.dart';
import 'package:mobile/widgets/design_system.dart';
import 'package:mobile/widgets/season_card.dart';
import 'package:mobile/widgets/trophy_image.dart';

/// The season card of the Rankings tab, in its three states: countdown +
/// time bar framed by the start/end dates, "end to be announced" without a
/// bar, and absent (the caller simply does not render it — nothing to test
/// on the widget). The season number is carried by the chips, not the card.
///
/// Two pumps are needed: AppLocalizations.delegate.load() is async, so the
/// first frame is empty. The test font (Ahem) is much wider than the real
/// one, so these layouts are a pessimistic bound only.
void main() {
  final now = DateTime.utc(2026, 8, 22, 10);

  Future<void> pumpCard(WidgetTester tester, Widget card, {Locale locale = const Locale('fr')}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
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
        home: Scaffold(body: Column(children: [card])),
      ),
    );
    await tester.pump();
    expect(find.byType(SeasonCard), findsOneWidget);
  }

  testWidgets('with an end date: countdown, prize, time bar and dates', (tester) async {
    final season = Season.fromJson({
      'number': 1,
      'status': 'active',
      'startedAt': '2026-08-01T00:00:00.000Z',
      'endAt': '2026-08-31T21:59:00.000Z',
      'trophyModel': null,
      'hasReward': true,
    });
    var tapped = false;
    await pumpCard(
      tester,
      SeasonCard(
        season: season,
        timeLeft: const Duration(days: 9, hours: 14),
        now: now,
        onTap: () => tapped = true,
      ),
    );

    expect(find.text('9 j 14 h'), findsOneWidget);
    expect(find.byIcon(Icons.schedule_outlined), findsOneWidget);
    expect(find.text('50 € + trophée'), findsOneWidget);
    expect(find.text('pour le n°1 à la fin de la saison'), findsOneWidget);
    expect(find.byType(DsProgressBar), findsOneWidget);
    expect(find.text('1er août'), findsOneWidget);
    expect(find.text('31 août'), findsOneWidget);
    expect(find.textContaining('fin à annoncer'), findsNothing);
    // No trophy model picked → no trophy render at all.
    expect(find.byType(TrophyImage), findsNothing);

    await tester.tap(find.byType(SeasonCard));
    expect(tapped, isTrue);
  });

  testWidgets('without an end date: end to be announced, no bar', (tester) async {
    final season = Season.fromJson({'number': 0, 'status': 'active', 'hasReward': false});
    await pumpCard(tester, SeasonCard(season: season, now: now));

    expect(find.text('fin à annoncer'), findsOneWidget);
    expect(find.byIcon(Icons.schedule_outlined), findsNothing);
    expect(find.byType(DsProgressBar), findsNothing);
    // Season 0 has no prize: the title falls back to the season name.
    expect(find.text('50 € + trophée'), findsNothing);
    expect(find.text('Saison 0'), findsOneWidget);
    expect(find.text('Pas de récompense'), findsOneWidget);
    expect(find.byType(TrophyImage), findsNothing);
  });

  testWidgets('a picked trophy model renders its thumbnail', (tester) async {
    final season = Season.fromJson({
      'number': 1,
      'status': 'active',
      'endAt': '2026-08-31T21:59:00.000Z',
      'trophyModel': 'classic',
      'hasReward': true,
    });
    await pumpCard(tester, SeasonCard(season: season, now: now));
    expect(find.byType(TrophyImage), findsOneWidget);
  });

  testWidgets('renders in English too', (tester) async {
    final season = Season.fromJson({
      'number': 2,
      'status': 'active',
      'startedAt': '2026-09-01T00:00:00.000Z',
      'endAt': '2026-09-30T21:59:00.000Z',
      'hasReward': true,
    });
    await pumpCard(
      tester,
      SeasonCard(season: season, timeLeft: const Duration(days: 3, hours: 2), now: DateTime.utc(2026, 9, 10)),
      locale: const Locale('en'),
    );
    expect(find.text('3 d 2 h'), findsOneWidget);
    expect(find.text('€50 + trophy'), findsOneWidget);
    expect(find.text('for the #1 at the end of the season'), findsOneWidget);
    expect(find.text('Sep 1'), findsOneWidget);
    expect(find.text('Sep 30'), findsOneWidget);
  });
}
