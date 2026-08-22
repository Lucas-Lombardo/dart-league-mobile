import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:mobile/l10n/app_localizations.dart';
import 'package:mobile/models/season.dart';
import 'package:mobile/providers/auth_provider.dart';
import 'package:mobile/providers/season_provider.dart';
import 'package:mobile/screens/season/season_new_elo_screen.dart';
import 'package:mobile/screens/season/season_recap_screen.dart';

/// The once-only end-of-season screens render from a recap payload alone;
/// the rank band places both marks on the backend thresholds.
void main() {
  final recap = SeasonRecap.fromJson({
    'season': {'id': 's1', 'number': 1, 'status': 'closed', 'playersCount': 312, 'hasReward': true, 'endAt': '2026-08-31T21:59:00.000Z'},
    'standing': {'position': 14, 'elo': 1486, 'rank': 'gold', 'wins': 23, 'losses': 11, 'eloAfterReset': 1350, 'peakElo': 1512},
    'eloBefore': 1486,
    'eloAfter': 1350,
    'rankBefore': 'gold',
    'rankAfter': 'gold',
    'champion': {'id': 'u9', 'username': 'NoahTheBull', 'elo': 2318, 'rank': 'diamond'},
    'nextSeason': {'id': 's2', 'number': 2, 'status': 'active', 'startedAt': '2026-08-31T21:59:00.000Z', 'endAt': '2026-09-30T21:59:00.000Z', 'hasReward': true},
  })!;

  Future<void> pumpScreen(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider(create: (_) => SeasonProvider()),
        ],
        child: MaterialApp(
          locale: const Locale('fr'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: screen,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2)); // entrance animations done
  }

  test('rankBandFraction places ratings on the backend thresholds', () {
    expect(rankBandFraction(1486), closeTo(0.434, 0.001));
    expect(rankBandFraction(1350), closeTo(0.38, 0.001));
    expect(rankBandFraction(0), 0);
    expect(rankBandFraction(800), closeTo(0.16, 0.001)); // Silver floor
    expect(rankBandFraction(2400), closeTo(0.80, 0.001)); // Master floor
    expect(rankBandFraction(3000), 1);
    expect(rankBandFraction(9999), 1);
    // Monotonic.
    var previous = 0.0;
    for (var elo = 0; elo <= 3000; elo += 10) {
      final f = rankBandFraction(elo);
      expect(f, greaterThanOrEqualTo(previous));
      previous = f;
    }
  });

  testWidgets('SeasonRecapScreen shows the final line, the tiles and the champion', (tester) async {
    await pumpScreen(tester, SeasonRecapScreen(recap: recap));
    expect(find.byType(SeasonRecapScreen), findsOneWidget);
    expect(find.text('SAISON 1 TERMINÉE'), findsOneWidget);
    expect(find.text('Votre bilan'), findsOneWidget);
    expect(find.text('Or'), findsOneWidget);
    expect(find.text('#14'), findsOneWidget);
    expect(find.text('sur 312'), findsOneWidget);
    expect(find.text('1486'), findsOneWidget);
    expect(find.text('23–11'), findsOneWidget);
    expect(find.text('1512'), findsOneWidget);
    expect(find.text('record'), findsOneWidget);
    expect(find.text('CHAMPION DE LA SAISON 1'), findsOneWidget);
    expect(find.text('NoahTheBull'), findsOneWidget);
    expect(find.text('2318 ELO · remporte 50 € + le trophée'), findsOneWidget);
    expect(find.text('La saison 2 commence le 1er sept.'), findsOneWidget);
    expect(find.text('Voir mon nouvel ELO'), findsOneWidget);
    expect(find.text('Partager mon bilan'), findsOneWidget);
  });

  testWidgets('SeasonRecapScreen for Season 0: champion without prize', (tester) async {
    final s0 = SeasonRecap.fromJson({
      'season': {'number': 0, 'status': 'closed', 'playersCount': 604, 'hasReward': false, 'endAt': '2026-07-31T21:59:00.000Z'},
      'standing': {'position': 21, 'elo': 1512, 'rank': 'gold', 'wins': 30, 'losses': 12, 'eloAfterReset': 1369},
      'champion': {'username': 'Thib_180', 'elo': 2412, 'rank': 'master'},
      'nextSeason': {'number': 1, 'status': 'active'},
    })!;
    await pumpScreen(tester, SeasonRecapScreen(recap: s0));
    expect(find.text('CHAMPION DE LA SAISON 0'), findsOneWidget);
    expect(find.text('2412 ELO'), findsOneWidget);
    expect(find.textContaining('remporte'), findsNothing);
  });

  testWidgets('SeasonNewEloScreen shows before → after, the band and the three lines', (tester) async {
    await pumpScreen(tester, SeasonNewEloScreen(recap: recap));
    expect(find.byType(SeasonNewEloScreen), findsOneWidget);
    expect(find.text('SAISON 2'), findsOneWidget);
    expect(find.text('La course repart'), findsOneWidget);
    expect(find.text('1486'), findsOneWidget);
    expect(find.text('1350'), findsOneWidget);
    expect(find.text('Fin saison 1'), findsOneWidget);
    expect(find.text('Départ saison 2'), findsOneWidget);
    expect(find.text('1486 · avant'), findsOneWidget);
    expect(find.text('1350 · départ'), findsOneWidget);
    for (final tier in ['BRONZE', 'ARGENT', 'OR', 'PLATINE', 'DIAMANT', 'MAÎTRE']) {
      expect(find.text(tier), findsOneWidget);
    }
    expect(find.textContaining('Vous restez'), findsOneWidget);
    expect(find.text('Personne ne reste Maître : les Maîtres repartent Diamant'), findsOneWidget);
    expect(find.text('50 € + trophée pour le n°1 le 30 sept.'), findsOneWidget);
    expect(find.text('Jouer la saison 2'), findsOneWidget);
  });

  testWidgets('SeasonNewEloScreen says "you are now" on a rank change and drops the date without one', (tester) async {
    final changed = SeasonRecap.fromJson({
      'season': {'number': 1, 'status': 'closed', 'hasReward': true},
      'standing': {'position': 3, 'elo': 2240, 'rank': 'diamond', 'eloAfterReset': 1893},
      'rankBefore': 'diamond',
      'rankAfter': 'platinum',
      'nextSeason': {'number': 2, 'status': 'active'},
    })!;
    await pumpScreen(tester, SeasonNewEloScreen(recap: changed));
    expect(find.textContaining('Vous passez'), findsOneWidget);
    expect(find.text('50 € + trophée pour le n°1'), findsOneWidget);
  });
}
