import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/l10n/app_localizations.dart';
import 'package:mobile/screens/onboarding/onboarding_bilan_screen.dart';
import 'package:mobile/screens/onboarding/onboarding_home_card.dart';
import 'package:mobile/screens/onboarding/onboarding_journey_screen.dart';
import 'package:mobile/screens/onboarding/onboarding_models.dart';
import 'package:mobile/screens/onboarding/onboarding_provider.dart';
import 'package:provider/provider.dart';

/// No network in widget tests: refreshes and "seen" are recorded, not sent.
class _FakeOnboarding extends OnboardingProvider {
  int refreshes = 0;
  int seen = 0;

  @override
  Future<void> refresh() async => refreshes++;

  @override
  Future<void> markBilanSeen() async => seen++;
}

Map<String, dynamic> _step(String id, int day, String fr, String status, String action, int xp,
        {Map<String, dynamic>? item, int premiumDays = 0}) =>
    {
      'id': id,
      'day': day,
      'title': {'fr': fr, 'en': fr},
      'status': status,
      'action': action,
      'xp': xp,
      'rewardItem': item,
      'premiumDays': premiumDays,
      'progress': status == 'done' ? 1 : 0,
      'threshold': 1,
    };

const _recrue = {'id': 'title.nouvelle-recrue', 'type': 'title', 'name': {'fr': 'Nouvelle recrue', 'en': 'New Recruit'}};
const _frame = {'id': 'frame.debutant', 'type': 'frame', 'name': {'fr': 'Débutant', 'en': 'Rookie'}};

/// Day 2 of the mockup DebutAccueil: 2 / 7, "Une volée à 60 ou plus".
OnboardingStatus _day2() => OnboardingStatus.fromJson({
      'active': true,
      'status': 'active',
      'day': 2,
      'doneCount': 2,
      'totalCount': 7,
      'currentStepId': 'visit-60',
      'premiumDays': 7,
      'steps': [
        _step('camera', 1, 'Régler ta caméra', 'done', 'bot_301', 50),
        _step('bot-301', 1, 'Un 301 contre un bot', 'done', 'bot_301', 100),
        _step('visit-60', 2, 'Une volée à 60 ou plus', 'open', 'bot_301', 80),
        _step('placement-1', 3, 'Ton premier match de placement', 'locked', 'placement', 150, item: _recrue),
        _step('challenge', 4, 'Le défi du jour', 'locked', 'challenge', 100),
        _step('friend', 5, 'Ajouter un ami', 'locked', 'friends', 100),
        _step('bilan', 7, 'Ton bilan de la semaine', 'locked', 'bilan', 150, item: _frame, premiumDays: 7),
      ],
    });

OnboardingStatus _completed() => OnboardingStatus.fromJson({
      'active': true,
      'status': 'completed',
      'day': 7,
      'doneCount': 7,
      'totalCount': 7,
      'premiumDays': 7,
      'premiumUntil': '2026-11-17T12:00:00.000Z',
      'bilanSeen': false,
      'bilan': {
        'matches': 14,
        'average': 44.6,
        'averageStart': 38.2,
        'averageDelta': 6.4,
        'bestVisit': 140,
        'rank': 'silver',
      },
      'steps': [
        _step('bilan', 7, 'Ton bilan de la semaine', 'done', 'bilan', 150, item: _frame, premiumDays: 7),
      ],
    });

Widget _app(Widget child, OnboardingProvider provider, {Locale locale = const Locale('fr')}) {
  return ChangeNotifierProvider<OnboardingProvider>.value(
    value: provider,
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: child)),
    ),
  );
}

void main() {
  group('home card', () {
    testWidgets('day 2: progress, today\'s step, its reward, Play and the premium at the end', (tester) async {
      final p = _FakeOnboarding()..debugSeed(_day2());
      await tester.pumpWidget(_app(const OnboardingHomeCard(), p));
      await tester.pump();
      await tester.pump();

      expect(tester.getSize(find.byType(OnboardingCard)).width, greaterThan(300));
      expect(find.text('Tes 7 premiers jours'), findsOneWidget);
      expect(find.text('2 / 7'), findsOneWidget);
      expect(find.text('Aujourd’hui · jour 2'), findsOneWidget);
      expect(find.text('Une volée à 60 ou plus'), findsOneWidget);
      expect(find.text('+80 XP'), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Jouer'), findsOneWidget);
      expect(find.text('Au bout : 7 jours de premium offerts'), findsOneWidget);
      // It asked for fresh data when it appeared.
      expect(p.refreshes, 1);
    });

    testWidgets('nothing left today: tomorrow\'s step, locked, no button', (tester) async {
      final json = {
        'active': true,
        'status': 'active',
        'day': 1,
        'doneCount': 2,
        'totalCount': 7,
        'currentStepId': null,
        'premiumDays': 7,
        'steps': [
          _step('camera', 1, 'Régler ta caméra', 'done', 'bot_301', 50),
          _step('bot-301', 1, 'Un 301 contre un bot', 'done', 'bot_301', 100),
          _step('visit-60', 2, 'Une volée à 60 ou plus', 'locked', 'bot_301', 80),
        ],
      };
      final p = _FakeOnboarding()..debugSeed(OnboardingStatus.fromJson(json));
      await tester.pumpWidget(_app(const OnboardingHomeCard(), p));
      await tester.pump();
      expect(find.text('Demain · jour 2'), findsOneWidget);
      expect(find.text('Une volée à 60 ou plus'), findsOneWidget);
      expect(find.byType(ElevatedButton), findsNothing);
      expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
    });

    testWidgets('the summary is ready: the card says so and opens it', (tester) async {
      final p = _FakeOnboarding()..debugSeed(_completed());
      await tester.pumpWidget(_app(const OnboardingHomeCard(), p));
      await tester.pump();
      expect(find.text('Ton bilan de la semaine est prêt'), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Voir'), findsOneWidget);
      // The premium footer is gone: it is granted now.
      expect(find.textContaining('Au bout'), findsNothing);
    });

    testWidgets('renders nothing without a running journey (old account, journey over)', (tester) async {
      final p = _FakeOnboarding()..debugSeed(OnboardingStatus.fromJson({'active': false, 'status': 'expired'}));
      await tester.pumpWidget(_app(const OnboardingHomeCard(), p));
      await tester.pump();
      expect(find.byType(OnboardingCard), findsNothing);
      expect(p.isActive, isFalse);
    });

    testWidgets('English', (tester) async {
      final p = _FakeOnboarding()..debugSeed(_day2());
      await tester.pumpWidget(_app(const OnboardingHomeCard(), p, locale: const Locale('en')));
      await tester.pump();
      expect(find.text('Your first 7 days'), findsOneWidget);
      expect(find.text('Today · day 2'), findsOneWidget);
      expect(find.text('At the end: 7 days of premium, on us'), findsOneWidget);
    });
  });

  group('journey screen', () {
    testWidgets('done, open with "Play now", locked with "opens tomorrow"; rewards spelled out', (tester) async {
      final p = _FakeOnboarding()..debugSeed(_day2());
      await tester.pumpWidget(ChangeNotifierProvider<OnboardingProvider>.value(
        value: p,
        child: MaterialApp(
          locale: const Locale('fr'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const OnboardingJourneyScreen(),
        ),
      ));
      await tester.pump();
      await tester.pump();
      expect(find.byType(OnboardingStepTile), findsWidgets);
      expect(find.text('Jour 2 · aujourd’hui'), findsOneWidget);
      expect(find.text('Jour 3 · s’ouvre demain'), findsOneWidget);
      expect(find.text('+150 XP · titre « Nouvelle recrue »'), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Jouer maintenant'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Ton bilan de la semaine'), 200);
      expect(find.text('+150 XP · 7 jours de premium · cadre de carte « Débutant »'), findsOneWidget);
    });
  });

  group('day-7 summary', () {
    testWidgets('matches, best visit, average and its progress, rank, premium and frame', (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final p = _FakeOnboarding()..debugSeed(_completed());
      await tester.pumpWidget(ChangeNotifierProvider<OnboardingProvider>.value(
        value: p,
        child: MaterialApp(
          locale: const Locale('fr'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const OnboardingBilanScreen(),
        ),
      ));
      await tester.pump();
      await tester.pump();

      expect(tester.getSize(find.byType(OnboardingBilanScreen)), const Size(390, 844));
      expect(find.text('7 étapes sur 7'), findsOneWidget);
      expect(find.text('Ta première semaine'), findsOneWidget);
      expect(find.text('14'), findsOneWidget);
      expect(find.text('140'), findsOneWidget);
      expect(find.text('44,6'), findsOneWidget);
      expect(find.textContaining('+6,4'), findsOneWidget);
      expect(find.textContaining('depuis le jour 1'), findsOneWidget);
      expect(find.text('Argent'), findsOneWidget); // the app's French rank name
      expect(find.text('7 jours de premium'), findsOneWidget);
      expect(find.textContaining('jusqu’au 17 novembre'), findsOneWidget);
      expect(find.text('Cadre Débutant'), findsOneWidget);
      expect(find.text('Partager mon bilan'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // "Continue" marks it seen.
      await tester.tap(find.widgetWithText(ElevatedButton, 'Continuer'));
      await tester.pump();
      expect(p.seen, 1);
    });

    testWidgets('a single match: no delta, no crash on missing numbers', (tester) async {
      final status = OnboardingStatus.fromJson({
        'active': true,
        'status': 'completed',
        'doneCount': 6,
        'totalCount': 6,
        'premiumDays': 7,
        'bilan': {'matches': 1, 'average': 30.0, 'averageStart': null, 'averageDelta': null, 'bestVisit': null, 'rank': 'unranked'},
        'steps': <dynamic>[],
      });
      await tester.pumpWidget(ChangeNotifierProvider<OnboardingProvider>.value(
        value: _FakeOnboarding()..debugSeed(status),
        child: MaterialApp(
          locale: const Locale('fr'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const OnboardingBilanScreen(),
        ),
      ));
      await tester.pump();
      await tester.pump();
      expect(find.text('30,0'), findsOneWidget);
      expect(find.textContaining('depuis le jour 1'), findsNothing);
      expect(find.text('—'), findsOneWidget);
      expect(find.text('Non classé'), findsOneWidget);
    });
  });

  test('status parsing is defensive', () {
    final s = OnboardingStatus.fromJson({
      'active': 'yes',
      'steps': [
        {'id': 'x', 'status': 'weird', 'title': 'not a map'},
        {'status': 'done'},
      ],
    });
    expect(s.active, isFalse);
    expect(s.steps, hasLength(1));
    expect(s.steps.single.isLocked, isTrue);
    expect(s.steps.single.action, 'none');
    expect(OnboardingStatus.fromJson(null).status, 'none');
  });
}
