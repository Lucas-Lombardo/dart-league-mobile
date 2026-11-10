import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mobile/l10n/app_localizations.dart';
import 'package:mobile/l10n/app_localizations_en.dart';
import 'package:mobile/l10n/app_localizations_fr.dart';
import 'package:mobile/models/progression.dart';
import 'package:mobile/providers/progression_provider.dart';
import 'package:mobile/screens/league/league_models.dart';
import 'package:mobile/screens/league/league_result_screen.dart';
import 'package:mobile/screens/league/league_screen.dart';
import 'package:mobile/screens/league/league_store.dart';
import 'package:mobile/screens/league/league_widgets.dart';
import 'package:mobile/screens/progression/progression_format.dart';
import 'package:mobile/screens/progression/today_section.dart';

/// Weekly league (Agent 4): models against the backend's JSON, and the
/// league screen, the Monday screen and the home row with seeded data.

Map<String, dynamic> _tier(String id, int order, String fr, String en, String color) => {
      'id': id,
      'order': order,
      'name': {'fr': fr, 'en': en},
      'color': color,
      'colors': ['#E2E8F0', '#7B8798', '#CBD5E1'],
    };

final _ladder = [
  _tier('diamant', 5, 'Diamant', 'Diamond', '#67E8F9'),
  _tier('bois', 0, 'Bois', 'Wood', '#C9A27A'),
  _tier('acier', 1, 'Acier', 'Steel', '#CBD5E1'),
  _tier('cuivre', 2, 'Cuivre', 'Copper', '#E8A27A'),
  _tier('or', 3, 'Or', 'Gold', '#E6CC7A'),
  _tier('platine', 4, 'Platine', 'Platinum', '#E5E7EB'),
];

Map<String, dynamic> _row(int position, String name, int points, {bool isMe = false}) => {
      'position': position,
      'userId': 'u$position',
      'username': name,
      'elo': 1300,
      'rank': 'gold',
      'league': 'acier',
      'points': points,
      'isMe': isMe,
      'cosmetics': {'level': 3, 'monogram': 'AB', 'frame': null, 'badges': []},
    };

/// GET /league/me as the backend sends it (league.service.ts getMe).
Map<String, dynamic> _meJson() => {
      'enabled': true,
      'weekKey': '2026-11-09',
      'weekNumber': 46,
      'endsAt': DateTime.now().add(const Duration(days: 3)).toUtc().toIso8601String(),
      'nextStartsAt': DateTime.now().add(const Duration(days: 3, hours: 2)).toUtc().toIso8601String(),
      'league': _tier('acier', 1, 'Acier', 'Steel', '#CBD5E1'),
      'ladder': _ladder,
      'pointRules': [
        {'id': 'ranked', 'activity': 'game', 'points': 30, 'winBonus': 20, 'dailyCap': null, 'label': {'fr': 'Série classée', 'en': 'Ranked series'}},
        {'id': 'challenge', 'activity': 'challenge', 'points': 40, 'winBonus': 0, 'label': {'fr': 'Défi du jour', 'en': 'Daily challenge'}},
        {'id': 'training', 'activity': 'training', 'points': 10, 'winBonus': 0, 'dailyCap': 5, 'label': {'fr': 'Entraînement', 'en': 'Training'}},
      ],
      'hasResult': false,
      'state': 'open',
      'firstWeek': false,
      'group': {
        'id': 'g1',
        'size': 20,
        'promoteCount': 5,
        'relegateCount': 5,
        'promoteTo': _tier('cuivre', 2, 'Cuivre', 'Copper', '#E8A27A'),
        'relegateTo': _tier('bois', 0, 'Bois', 'Wood', '#C9A27A'),
        'standings': [
          _row(1, 'Kev_D20', 1240),
          _row(2, 'Mika_180', 1105),
          _row(3, 'Jo_Bull', 980),
          _row(4, 'Dodo180', 914, isMe: true),
          for (var i = 5; i <= 20; i++) _row(i, 'Player$i', 1000 - i * 40),
        ],
      },
      'me': {'position': 4, 'points': 914},
    };

/// GET /league/result → result.
Map<String, dynamic> _resultJson() => {
      'weekKey': '2026-11-02',
      'weekNumber': 45,
      'league': _tier('acier', 1, 'Acier', 'Steel', '#CBD5E1'),
      'leagueAfter': _tier('cuivre', 2, 'Cuivre', 'Copper', '#E8A27A'),
      'outcome': 'promoted',
      'position': 3,
      'groupSize': 20,
      'points': 1012,
      'xp': 200,
      'itemIds': ['title.grimpeur'],
      'badge': {'badgeId': 'badge.league-podium', 'tier': 'bronze'},
      'promotedWith': ['Mika_180'],
      'next': {'weekKey': '2026-11-09', 'groupSize': 20, 'endsAt': '2026-11-15T21:00:00.000Z'},
      'ladder': _ladder,
    };

final _content = ProgressionContent.fromJson({
  'version': 'v1',
  'items': [
    {
      'id': 'title.grimpeur',
      'type': 'title',
      'name': {'fr': 'Grimpeur', 'en': 'Climber'},
      'source': {'kind': 'league', 'ref': 'first-promotion', 'label': {'fr': 'ta première montée', 'en': 'your first promotion'}},
    },
    {
      'id': 'badge.league-podium',
      'type': 'badge',
      'name': {'fr': 'Podium de ligue', 'en': 'League Podium'},
      'source': {'kind': 'league', 'label': {'fr': 'podium', 'en': 'podium'}},
      'render': {'kind': 'badge', 'glyph': 'podium'},
    },
  ],
});

class _FakeProgression extends ProgressionProvider {
  @override
  Future<void> refreshSummary() async {}
  @override
  Future<void> refreshQuests() async {}
  @override
  Future<void> refreshContent() async {}
}

Widget _app(Widget child, {Locale locale = const Locale('fr'), bool scaffold = true}) {
  final provider = _FakeProgression()..debugSeed(content: _content);
  return ChangeNotifierProvider<ProgressionProvider>.value(
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
      home: scaffold ? Scaffold(body: child) : child,
    ),
  );
}

void main() {
  final store = LeagueStore.instance;
  LeagueSnapshot? next;

  setUp(() {
    next = null;
    store.debugLoader = () async => next ?? store.snapshot ?? const LeagueSnapshot(enabled: false);
    store.debugSeed(null);
  });

  group('models', () {
    test('LeagueSnapshot reads the backend payload', () {
      final s = LeagueSnapshot.fromJson(_meJson());
      expect(s.state, LeagueWeekState.open);
      expect(s.inGroup, isTrue);
      expect(s.weekNumber, 46);
      expect(s.ladder.map((t) => t.id), ['bois', 'acier', 'cuivre', 'or', 'platine', 'diamant']);
      expect(s.league?.name.fr, 'Acier');
      expect(s.league?.color, const Color(0xFFCBD5E1));
      expect(s.myPosition, 4);
      expect(s.myPoints, 914);
      expect(s.pointRules.first.winBonus, 20);
      final g = s.group!;
      expect(g.standings, hasLength(20));
      expect(g.standings[3].isMe, isTrue);
      expect(g.standings[0].cosmetics?.monogram, 'AB');
      expect(g.relegateFrom, 16);
      expect(g.promoteTo?.id, 'cuivre');
    });

    test('LeagueSnapshot survives a missing group, an unknown state, a server without league', () {
      final none = LeagueSnapshot.fromJson({'state': 'weird', 'firstWeek': true, 'league': _tier('bois', 0, 'Bois', 'Wood', 'bad')});
      expect(none.state, LeagueWeekState.none);
      expect(none.inGroup, isFalse);
      expect(none.firstWeek, isTrue);
      expect(none.league?.color, const Color(0xFFCBD5E1));
      expect(LeagueSnapshot.fromJson({'enabled': false}).enabled, isFalse);
      expect(LeagueSnapshot.fromJson(null).group, isNull);
      expect(LeagueSnapshot.fromJson({'group': {'standings': [{'nope': 1}]}}).group, isNull);
    });

    test('LeagueResult reads outcome, rewards and the next week', () {
      final r = LeagueResult.fromJson(_resultJson())!;
      expect(r.outcome, LeagueOutcome.promoted);
      expect(r.leagueAfter?.id, 'cuivre');
      expect(r.itemIds, ['title.grimpeur']);
      expect(r.badge?.badgeId, 'badge.league-podium');
      expect(r.badge?.tier, 'bronze');
      expect(r.nextGroupSize, 20);
      expect(r.promotedWith, ['Mika_180']);
      expect(LeagueResult.fromJson({'outcome': 'x'}), isNull);
      expect(LeagueResult.fromJson({'weekKey': 'w', 'outcome': 'teleported'})!.outcome, LeagueOutcome.stayed);
    });

    test('LeagueHistory reads finished weeks', () {
      final h = LeagueHistory.fromJson({
        'league': _tier('acier', 1, 'Acier', 'Steel', '#CBD5E1'),
        'best': _tier('cuivre', 2, 'Cuivre', 'Copper', '#E8A27A'),
        'promotions': 2,
        'weeks': [
          {'weekKey': '2026-11-02', 'weekNumber': 45, 'outcome': 'relegated', 'position': 18, 'groupSize': 20, 'points': 40, 'xp': 30},
          {'bad': true},
        ],
      });
      expect(h.best?.id, 'cuivre');
      expect(h.weeks, hasLength(1));
      expect(h.weeks.first.outcome, LeagueOutcome.relegated);
    });

    test('places and hours in both languages', () {
      final en = AppLocalizationsEn();
      final fr = AppLocalizationsFr();
      expect([1, 2, 3, 4, 11, 12, 13, 21, 22].map(en.leaguePlace).toList(),
          ['1st', '2nd', '3rd', '4th', '11th', '12th', '13th', '21st', '22nd']);
      expect([1, 2, 16].map(fr.leaguePlace).toList(), ['1ᵉʳ', '2ᵉ', '16ᵉ']);
      expect(fr.leagueEndsOn(fr.leagueWeekdayShort(7), fr.leagueHour(22)), 'fin dim. 22 h');
      expect(en.leagueEndsOn(en.leagueWeekdayShort(7), en.leagueHour(22)), 'ends Sun. 10 pm');
      expect(en.leagueHour(0), '12 am');
      expect(fr.leagueRelegateZone(16, 20, 'Bois'), '16 à 20 redescendent en Bois');
    });
  });

  group('screens', () {
    testWidgets('league screen: standings, zones, me, what scores', (tester) async {
      tester.view.physicalSize = const Size(1170, 6000);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      store.debugSeed(LeagueSnapshot.fromJson(_meJson()));
      await tester.pumpWidget(_app(const LeagueScreen(), scaffold: false));
      await tester.pump();
      await tester.pump();

      expect(find.text('Ligue Acier'), findsOneWidget);
      expect(find.text('fin dim. 22 h').evaluate().isNotEmpty || find.textContaining('fin ').evaluate().isNotEmpty, isTrue);
      expect(find.text('Kev_D20'), findsOneWidget);
      expect(find.text(formatXp(1240)), findsOneWidget);
      expect(find.text('Toi'), findsOneWidget);
      expect(find.text('montent en Ligue Cuivre'), findsOneWidget);
      expect(find.text('16 à 20 redescendent en Bois'), findsOneWidget);
      expect(find.text('Tout rapporte'), findsOneWidget);
      expect(find.text('Série classée 30 (+20 si gagnée) · Défi du jour 40 · Entraînement 10'), findsOneWidget);
      // The six bars of the ladder.
      for (final name in ['Bois', 'Acier', 'Cuivre', 'Or', 'Platine', 'Diamant']) {
        expect(find.text(name), findsWidgets);
      }
      // The promotion line sits right after 5th place, the relegation line before 16th.
      final up = tester.getTopLeft(find.text('montent en Ligue Cuivre')).dy;
      expect(up, greaterThan(tester.getTopLeft(find.text('Player5')).dy));
      expect(up, lessThan(tester.getTopLeft(find.text('Player6')).dy));
      final down = tester.getTopLeft(find.text('16 à 20 redescendent en Bois')).dy;
      expect(down, greaterThan(tester.getTopLeft(find.text('Player15')).dy));
      expect(down, lessThan(tester.getTopLeft(find.text('Player16')).dy));
    });

    testWidgets('league screen without a group: the first league starts on Monday', (tester) async {
      final json = _meJson()
        ..['state'] = 'none'
        ..['firstWeek'] = true
        ..['group'] = null
        ..['me'] = null
        ..['league'] = _tier('bois', 0, 'Bois', 'Wood', '#C9A27A');
      store.debugSeed(LeagueSnapshot.fromJson(json));
      await tester.pumpWidget(_app(const LeagueScreen(), scaffold: false));
      await tester.pump();
      await tester.pump();
      expect(find.text('Ta première ligue commence lundi'), findsOneWidget);
      expect(find.textContaining('Dans '), findsOneWidget);
      expect(find.text('Toi'), findsNothing);
    });

    testWidgets('Monday screen: promotion, place, XP, first-time items, podium badge', (tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final result = LeagueResult.fromJson(_resultJson())!;
      await tester.pumpWidget(_app(LeagueResultScreen(result: result), scaffold: false));
      await tester.pump();
      await tester.pump();
      expect(find.text('Semaine 45 terminée'), findsOneWidget);
      expect(find.text('Tu montes'), findsOneWidget);
      expect(find.text('Ligue Cuivre'), findsOneWidget);
      expect(find.text('3ᵉ'), findsOneWidget);
      expect(find.text('sur 20'), findsOneWidget);
      expect(find.text(formatXp(1012)), findsOneWidget);
      expect(find.text('+200'), findsOneWidget);
      expect(find.text('Titre « Grimpeur »'), findsOneWidget);
      expect(find.text('ta première montée'), findsOneWidget);
      expect(find.text('Badge Podium'), findsOneWidget);
      expect(find.textContaining('Mika_180 monte avec toi.'), findsOneWidget);
      expect(find.textContaining('20 joueurs'), findsOneWidget);
      expect(find.text('Voir ma nouvelle ligue'), findsOneWidget);
    });

    testWidgets('Monday screen in English, relegated, nothing new', (tester) async {
      final json = _resultJson()
        ..['outcome'] = 'relegated'
        ..['leagueAfter'] = _tier('bois', 0, 'Bois', 'Wood', '#C9A27A')
        ..['itemIds'] = <String>[]
        ..['badge'] = null
        ..['position'] = 18
        ..['xp'] = 30
        ..['next'] = null;
      await tester.pumpWidget(_app(LeagueResultScreen(result: LeagueResult.fromJson(json)!), locale: const Locale('en'), scaffold: false));
      await tester.pump();
      await tester.pump();
      expect(find.text('Relegated'), findsOneWidget);
      expect(find.text('Wood League'), findsOneWidget);
      expect(find.text('18th'), findsOneWidget);
      expect(find.text('Podium badge'), findsNothing);
      expect(find.text('Continue'), findsOneWidget);
    });

    testWidgets('home "Today" block: the league row after the quests, hidden without data', (tester) async {
      await tester.pumpWidget(_app(ListenableBuilder(
        listenable: store,
        builder: (context, _) => TodaySection(trailing: [if (LeagueTodayRow.isVisible()) const LeagueTodayRow()]),
      )));
      await tester.pump();
      expect(find.text('Ligue Acier'), findsNothing);

      store.debugSeed(LeagueSnapshot.fromJson(_meJson()));
      await tester.pump();
      expect(find.text('Ligue Acier'), findsOneWidget);
      expect(find.textContaining('4ᵉ · 914 pts · encore'), findsOneWidget);
      // 4th of 20 with points: in the promotion zone.
      expect(find.byIcon(Icons.keyboard_arrow_up_rounded), findsOneWidget);
    });

    testWidgets('store: a refresh keeps the last value on error and handles each result once', (tester) async {
      store.debugSeed(LeagueSnapshot.fromJson(_meJson()));
      store.debugLoader = () async => throw Exception('offline');
      await store.refresh();
      expect(store.visible?.myPosition, 4);
      expect(store.failed, isTrue);
      expect(store.isResultHandled('2026-11-02'), isFalse);
      store.markResultHandled('2026-11-02');
      expect(store.isResultHandled('2026-11-02'), isTrue);
      store.reset();
      expect(store.visible, isNull);
      expect(store.isResultHandled('2026-11-02'), isFalse);
    });
  });
}
