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
import 'package:mobile/widgets/design_system.dart';

/// The once-only end-of-season screens render from a recap payload alone
/// (system D: one card with the hero ELO, the rank band framed by its two
/// floors, the tiles, one primary button).
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

  testWidgets('SeasonRecapScreen shows the final ELO, the band, the tiles and the champion', (tester) async {
    await pumpScreen(tester, SeasonRecapScreen(recap: recap));
    expect(find.byType(SeasonRecapScreen), findsOneWidget);
    expect(find.text('SAISON 1 TERMINÉE'), findsOneWidget);
    expect(find.text('Votre bilan'), findsOneWidget);
    expect(find.text('ELO FINAL'), findsOneWidget);
    expect(find.text('1486'), findsOneWidget);
    expect(find.text('Or'), findsOneWidget);
    // The band is framed by the floor of the rank and of the next one.
    expect(find.text('Or · 1200'), findsOneWidget);
    expect(find.text('Platine · 1600'), findsOneWidget);
    expect(find.text('#14'), findsOneWidget);
    expect(find.text('SUR 312'), findsOneWidget);
    expect(find.text('23–11'), findsOneWidget);
    expect(find.text('1512'), findsOneWidget);
    expect(find.text('RECORD'), findsOneWidget);
    expect(find.text('CHAMPION DE LA SAISON 1'), findsOneWidget);
    expect(find.text('NoahTheBull'), findsOneWidget);
    expect(find.text('2318 ELO · remporte 50 € + le trophée'), findsOneWidget);
    expect(find.text('La saison 2 commence le 1er sept.'), findsOneWidget);
    expect(find.text('Voir mon nouvel ELO'), findsOneWidget);
    expect(find.text('Partager mon bilan'), findsOneWidget);
    // One filled primary block: the button to the new ELO.
    expect(find.byType(ElevatedButton), findsOneWidget);
    expect(find.byType(OutlinedButton), findsOneWidget);
    expect(find.byType(DsProgressBar), findsOneWidget);
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

  testWidgets('SeasonNewEloScreen shows the new ELO, the delta, the band and the lines', (tester) async {
    await pumpScreen(tester, SeasonNewEloScreen(recap: recap));
    expect(find.byType(SeasonNewEloScreen), findsOneWidget);
    expect(find.text('SAISON 2'), findsOneWidget);
    expect(find.text('La course repart'), findsOneWidget);
    expect(find.text('DÉPART SAISON 2'), findsOneWidget);
    expect(find.text('1350'), findsOneWidget);
    expect(find.text('-136'), findsOneWidget);
    expect(find.text('Or · 1200'), findsOneWidget);
    expect(find.text('Platine · 1600'), findsOneWidget);
    expect(find.textContaining('1486 → 1350'), findsOneWidget);
    expect(find.textContaining('Vous restez Or'), findsOneWidget);
    expect(find.text('Personne ne reste Maître : les Maîtres repartent Diamant'), findsOneWidget);
    expect(find.text('50 € + trophée pour le n°1 le 30 sept.'), findsOneWidget);
    expect(find.text('Jouer la saison 2'), findsOneWidget);
    expect(find.byType(ElevatedButton), findsOneWidget);
    expect(find.byType(DsProgressBar), findsOneWidget);
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
    expect(find.textContaining('Vous passez Platine'), findsOneWidget);
    expect(find.text('Platine · 1600'), findsOneWidget);
    expect(find.text('Diamant · 2000'), findsOneWidget);
    expect(find.text('50 € + trophée pour le n°1'), findsOneWidget);
  });
}
