// The levels path by tiers of ten (piste C, docs/progression/ecrans/R5C) and
// the quest journal in tabs (piste A, R6A), CONTRACT §14.14: tiers done /
// current / to come, unfolding a card, the premium column for a premium or a
// free player, past level 50; the tabs and their counts, the tab opened by
// default, the quests done folded then unfolded, changing a quest, the event
// tab, and opening the journal from the home strip and from the locker.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:mobile/l10n/app_localizations.dart';
import 'package:mobile/models/progression.dart';
import 'package:mobile/providers/progression_provider.dart';
import 'package:mobile/screens/home/home_quest_strip.dart';
import 'package:mobile/screens/progression/levels_path_screen.dart';
import 'package:mobile/screens/progression/locker_screen.dart';
import 'package:mobile/screens/progression/progression_screen.dart';
import 'package:mobile/utils/app_theme.dart';
import 'package:mobile/widgets/fit_text.dart';
import 'package:mobile/widgets/progression/player_showcase_card.dart' show PremiumCrown;
import 'package:mobile/widgets/progression/progression_widgets.dart';

class _FakeProgression extends ProgressionProvider {
  final rerolled = <String>[];
  bool rerollOk = true;

  @override
  Future<void> refreshSummary() async {}
  @override
  Future<void> refreshQuests() async {}
  @override
  Future<void> refreshContent() async {}
  @override
  Future<void> refreshInventory() async {}
  @override
  Future<void> markItemsSeen(List<String> itemIds) async {}

  /// As the server does: the quest is replaced, the day's change is used.
  @override
  Future<bool> reroll(String userQuestId) async {
    rerolled.add(userQuestId);
    if (!rerollOk) return false;
    final daily = quests!.daily;
    debugSeed(
      quests: quests!.withDaily(QuestSection(
        periodKey: daily.periodKey,
        endsAt: daily.endsAt,
        rerollAvailable: false,
        quests: [
          for (final q in daily.quests)
            q.id == userQuestId
                ? const UserQuest(id: 'new', questId: 'q999', period: 'daily', text: LocalizedText(fr: 'Quête neuve', en: 'New quest'), threshold: 2, xp: 40)
                : q,
        ],
      )),
    );
    return true;
  }
}

// ─── Content ─────────────────────────────────────────────────────────────────

Map<String, dynamic> _item(String id, String type, String name, {Map<String, dynamic>? source, Map<String, dynamic> render = const {}}) => {
      'id': id,
      'type': type,
      'name': {'fr': name, 'en': name},
      'source': source ?? {'kind': 'level', 'level': 2, 'label': {'fr': 'niveau', 'en': 'level'}},
      'render': render,
    };

/// Levels 2–49 give a title « Titre n », level 50 the Légende frame and
/// title, every fifth level a premium frame « Prime n »; one winter event.
Map<String, dynamic> _contentJson({DateTime? eventStart, DateTime? eventEnd}) {
  final start = eventStart ?? DateTime.now().subtract(const Duration(days: 2));
  final end = eventEnd ?? DateTime.now().add(const Duration(days: 9));
  return {
    'version': 'test',
    'curve': {'base': 200, 'perLevel': 60, 'capLevel': 50},
    'prestige': {'frameId': 'frame.legende', 'fromLevel': 50, 'everyLevels': 10},
    'items': [
      for (var l = 2; l < 50; l++) _item('title.t$l', 'title', 'Titre $l'),
      _item('frame.legende', 'frame', 'Légende', render: {'kind': 'frame', 'metal': 'legende'}),
      _item('title.legende', 'title', 'Légende'),
      for (var l = 5; l <= 50; l += 5) _item('frame.p$l', 'frame', 'Prime $l', render: {'kind': 'frame', 'metal': 'acier'}),
      _item(
        'background.hiver',
        'background',
        'Hiver',
        source: {'kind': 'event', 'ref': 'hiver-2026', 'label': {'fr': 'événement', 'en': 'event'}},
        render: {'kind': 'texture', 'colors': ['#1E293B', '#E2E8F0'], 'pattern': 'dots'},
      ),
    ],
    'levels': [
      for (var l = 1; l <= 50; l++)
        {
          'level': l,
          'itemIds': l == 1 ? <String>[] : (l == 50 ? ['frame.legende', 'title.legende'] : ['title.t$l']),
          'premiumItemIds': l % 5 == 0 ? ['frame.p$l'] : <String>[],
        },
    ],
    'events': [
      {
        'id': 'hiver-2026',
        'name': {'fr': 'Hiver', 'en': 'Winter'},
        'startsAt': start.toUtc().toIso8601String(),
        'endsAt': end.toUtc().toIso8601String(),
        'itemIds': ['background.hiver'],
        'questIds': ['e001'],
      },
    ],
  };
}

final _content = ProgressionContent.fromJson(_contentJson());
const _curve = XpCurve();

/// Level [level] at 51 %: level 23 → 806 / 1 580 XP, 774 to go.
ProgressionSummary _summary(int level, {bool premium = true}) {
  final into = (_curve.xpToNext(level) * 0.51).round();
  return ProgressionSummary(
    level: level,
    xpTotal: _curve.xpForLevel(level) + into,
    xpIntoLevel: into,
    xpToNext: _curve.xpToNext(level),
    levelSeen: level,
    isPremium: premium,
    cosmetics: PublicCosmetics(level: level, monogram: 'T20'),
  );
}

Map<String, dynamic> _q(String id, String period, String fr, int progress, int threshold, int xp) => {
      'id': id,
      'questId': id,
      'period': period,
      'text': {'fr': fr, 'en': fr},
      'progress': progress,
      'threshold': threshold,
      'xp': xp,
      'status': progress >= threshold ? 'completed' : 'active',
    };

/// R6A's quests: day 1/3, week 1/3, discover 3/6.
QuestsSnapshot _quests({
  bool dailyAllDone = false,
  bool weeklyAllDone = false,
  bool rerollAvailable = true,
  List<Map<String, dynamic>>? events,
}) {
  final now = DateTime.now();
  return QuestsSnapshot.fromJson({
    'daily': {
      'endsAt': now.add(const Duration(hours: 6, minutes: 30)).toUtc().toIso8601String(),
      'rerollAvailable': rerollAvailable,
      'quests': [
        _q('d1', 'daily', 'Marque une volée à 100+', 1, 1, 40),
        _q('d2', 'daily', '5 triples dans une partie', dailyAllDone ? 5 : 3, 5, 40),
        _q('d3', 'daily', 'Joue le défi du jour', dailyAllDone ? 1 : 0, 1, 40),
      ],
    },
    'weekly': {
      'endsAt': now.add(const Duration(days: 6, hours: 2)).toUtc().toIso8601String(),
      'quests': [
        _q('w1', 'weekly', 'Termine 10 séries classées', weeklyAllDone ? 10 : 3, 10, 250),
        _q('w2', 'weekly', 'Joue 5 jours différents', weeklyAllDone ? 5 : 1, 5, 200),
        _q('w3', 'weekly', 'Bats un joueur mieux classé que toi', 1, 1, 250),
      ],
    },
    'discovery': {
      'quests': [
        _q('x1', 'discovery', 'Joue une partie de Cricket', 0, 1, 100),
        _q('x2', 'discovery', 'Regarde un match en spectateur', 0, 1, 50),
        _q('x3', 'discovery', 'Fais un exercice de chaque famille', 3, 4, 100),
        _q('x4', 'discovery', 'Règle ta caméra', 1, 1, 50),
        _q('x5', 'discovery', 'Termine ton placement', 1, 1, 150),
        _q('x6', 'discovery', 'Ajoute un ami', 1, 1, 50),
      ],
    },
    'events': ?events,
  });
}

/// The winter event's quests (one to do, one done), ending [endsAt].
List<Map<String, dynamic>> _winter({DateTime? endsAt}) => [
      {
        'eventId': 'hiver-2026',
        'name': {'fr': 'Hiver', 'en': 'Winter'},
        'endsAt': (endsAt ?? DateTime.now().add(const Duration(days: 9))).toUtc().toIso8601String(),
        'quests': [
          _q('e1', 'event', 'Gagne 5 séries classées pendant l’hiver', 2, 5, 150),
          _q('e2', 'event', 'Joue 7 jours différents', 7, 7, 150),
        ],
      },
    ];

_FakeProgression _provider({int level = 23, bool premium = true, QuestsSnapshot? quests, ProgressionContent? content}) =>
    _FakeProgression()
      ..debugSeed(
        content: content ?? _content,
        summary: _summary(level, premium: premium),
        quests: quests ?? _quests(),
        inventory: const Inventory(),
      );

// ─── Harness (as home_final_test.dart: pump twice, assert the size) ─────────

Widget _app(Widget home, ProgressionProvider p) => ChangeNotifierProvider<ProgressionProvider>.value(
      value: p,
      child: MaterialApp(
        theme: AppTheme.themeData,
        locale: const Locale('fr'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
      ),
    );

Future<void> _open(WidgetTester tester, Widget home, ProgressionProvider p) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const SizedBox()); // a fresh screen state each time
  await tester.pumpWidget(_app(home, p));
  await tester.pump();
  await tester.pumpAndSettle();
  expect(tester.getSize(find.byType(home.runtimeType)), const Size(390, 844));
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Finder _row(int level) => find.byKey(Key('path-level-$level'));
Finder _in(Finder parent, Finder f) => find.descendant(of: parent, matching: f);

/// The row's screen-reader label: « Niveau 23, Titre 23, Atteint ».
String _label(WidgetTester tester, int level) =>
    tester.widget<Semantics>(_in(_row(level), find.byType(Semantics)).first).properties.label ?? '';

bool _silhouetted(WidgetTester tester, int level) => _in(_row(level), find.byType(ColorFiltered)).evaluate().isNotEmpty;

Finder _tab(QuestTab t) => find.byKey(Key('quest-tab-${t.name}'));

/// The tab drawn as selected (the slate pill).
QuestTab _selected(WidgetTester tester) {
  for (final t in QuestTab.values) {
    final f = _in(_tab(t), find.byType(AnimatedContainer));
    if (f.evaluate().isEmpty) continue;
    final deco = tester.widget<AnimatedContainer>(f).decoration as BoxDecoration?;
    if (deco?.color == AppTheme.surfaceLight) return t;
  }
  throw StateError('no tab selected');
}

void main() {
  group('5 · Parcours by tiers of ten', () {
    test('tiers, their state and the prestige levels', () {
      final tiers = LevelsPathScreen.tiers(_content);
      expect(tiers.map((t) => (t.from, t.to)), [(1, 10), (11, 20), (21, 30), (31, 40), (41, 50)]);
      expect(tiers.map((t) => t.stateFor(23)), [PathTierState.done, PathTierState.done, PathTierState.current, PathTierState.locked, PathTierState.locked]);
      // Level 30: its tier is done, the next one holds level 31.
      expect(tiers[2].stateFor(30), PathTierState.done);
      expect(tiers[3].stateFor(30), PathTierState.current);
      expect(tiers[2].reached(23), 3);
      expect(tiers.every((t) => t.stateFor(50) == PathTierState.done), isTrue);
      expect(LevelsPathScreen.prestigeLevels(_content, 23), [60, 70, 80]);
      expect(LevelsPathScreen.prestigeLevels(_content, 73), [60, 70, 80, 90]);
    });

    testWidgets('tiers done folded and ticked, the current one open, the next ones locked', (tester) async {
      await _open(tester, const LevelsPathScreen(), _provider());
      expect(find.text('Niv. 23'), findsOneWidget);
      // Done: « Niveaux 1 – 10 · 10 / 10 », the ten rewards in small, no rows.
      expect(find.text('Niveaux 1 – 10'), findsOneWidget);
      expect(find.text('Niveaux 11 – 20'), findsOneWidget);
      expect(find.text('10 / 10'), findsNWidgets(2));
      expect(find.byKey(const Key('path-minis-1')), findsOneWidget);
      expect(_in(find.byKey(const Key('path-minis-1')), find.byType(ColorFiltered)), findsNothing);
      expect(_row(5), findsNothing);
      // Current: 21 – 30, 3 / 10, one row per level.
      expect(find.text('Niveaux 21 – 30'), findsOneWidget);
      expect(find.text('3 / 10'), findsOneWidget);
      for (var l = 21; l <= 30; l++) {
        expect(_row(l), findsOneWidget);
      }
      // To come: dashed, 0 / 10, folded; then prestige.
      expect(find.text('Niveaux 31 – 40'), findsOneWidget);
      expect(find.text('Niveaux 41 – 50'), findsOneWidget);
      expect(find.text('0 / 10'), findsNWidgets(2));
      expect(_row(31), findsNothing);
      expect(find.text('Prestige · une étoile tous les 10 niveaux'), findsOneWidget);
    });

    testWidgets('reached, next and to come look different', (tester) async {
      await _open(tester, const LevelsPathScreen(), _provider());
      // Reached: in colour, ticked.
      expect(_label(tester, 23), 'Niveau 23, Titre 23, Atteint');
      expect(_silhouetted(tester, 23), isFalse);
      // Next: blue outline, the XP bar and what is left.
      expect(_label(tester, 24), contains('774 XP'));
      expect(_in(_row(24), find.text('774 XP')), findsOneWidget);
      final next = tester.widget<Container>(_in(_row(24), find.byType(Container)).first);
      expect((next.decoration! as BoxDecoration).border, Border.all(color: AppTheme.primaryLight, width: 1.5));
      expect(_silhouetted(tester, 24), isFalse);
      // To come: grey silhouette and a lock.
      expect(_label(tester, 26), 'Niveau 26, Titre 26, Verrouillé');
      expect(_silhouetted(tester, 26), isTrue);
      expect(_in(_row(26), find.byIcon(Icons.lock_outline_rounded)), findsOneWidget);
      expect(_in(_row(23), find.byIcon(Icons.check_rounded)), findsOneWidget);
    });

    testWidgets('the current tier shows at opening, without scrolling, even under four tiers done', (tester) async {
      // Level 23: on screen as it is, nothing moves.
      await _open(tester, const LevelsPathScreen(), _provider());
      expect(tester.getRect(find.byKey(const Key('path-tier-1'))).top, greaterThanOrEqualTo(60));
      expect(tester.getRect(_row(24)).bottom, lessThanOrEqualTo(844));
      // Level 49: the list jumps just enough for my next level, the title stays.
      await _open(tester, const LevelsPathScreen(), _provider(level: 49));
      expect(find.text('9 / 10'), findsOneWidget);
      expect(tester.getRect(find.text('Niveaux 41 – 50')).top, greaterThanOrEqualTo(60));
      expect(tester.getRect(_row(50)).bottom, lessThanOrEqualTo(844));
      expect(_label(tester, 50), contains('XP'));
    });

    testWidgets('touching a tier done unfolds its ten rows, then folds them back', (tester) async {
      await _open(tester, const LevelsPathScreen(), _provider());
      await _tap(tester, find.byKey(const Key('path-tier-1')));
      expect(find.byKey(const Key('path-minis-1')), findsNothing);
      expect(_label(tester, 1), 'Niveau 1, Avatar de rang, fond uni, Atteint');
      for (var l = 1; l <= 10; l++) {
        expect(_label(tester, l), endsWith('Atteint'));
      }
      await _tap(tester, find.byKey(const Key('path-tier-1')));
      expect(_row(5), findsNothing);
      expect(find.byKey(const Key('path-minis-1')), findsOneWidget);
    });

    testWidgets('touching a tier to come unfolds it, everything still locked', (tester) async {
      await _open(tester, const LevelsPathScreen(), _provider());
      await _tap(tester, find.byKey(const Key('path-tier-31')));
      for (var l = 31; l <= 40; l++) {
        expect(_label(tester, l), endsWith('Verrouillé'));
        expect(_silhouetted(tester, l), isTrue);
      }
      // The prestige card too, before level 50: no star level is « next ».
      await _tap(tester, find.byKey(const Key('path-prestige')));
      for (final l in const [60, 70, 80]) {
        expect(_label(tester, l), endsWith('Verrouillé'));
      }
    });

    testWidgets('premium player: the premium items of the levels reached are in colour', (tester) async {
      await _open(tester, const LevelsPathScreen(), _provider(premium: true));
      await _tap(tester, find.byKey(const Key('path-tier-11')));
      expect(_in(_row(15), find.byKey(const Key('path-premium-mine'))), findsOneWidget);
      expect(_in(_row(20), find.byKey(const Key('path-premium-mine'))), findsOneWidget);
      // Not reached yet: in silhouette, with the crown.
      expect(_in(_row(25), find.byKey(const Key('path-premium-locked'))), findsOneWidget);
      expect(_in(_row(25), find.byType(PremiumCrown)), findsOneWidget);
    });

    testWidgets('free player: every premium item stays in silhouette', (tester) async {
      await _open(tester, const LevelsPathScreen(), _provider(premium: false));
      await _tap(tester, find.byKey(const Key('path-tier-11')));
      expect(find.byKey(const Key('path-premium-mine')), findsNothing);
      expect(_in(_row(15), find.byKey(const Key('path-premium-locked'))), findsOneWidget);
      expect(_in(_row(20), find.byKey(const Key('path-premium-locked'))), findsOneWidget);
    });

    testWidgets('level 50 names its two items once, « Légende · cadre et titre »', (tester) async {
      await _open(tester, const LevelsPathScreen(), _provider(level: 45));
      expect(_label(tester, 50), 'Niveau 50, Légende\u00a0· cadre et titre, Verrouillé');
    });

    testWidgets('past 50: every tier folded and ticked, the prestige card open, the same star on each level', (tester) async {
      await _open(tester, const LevelsPathScreen(), _provider(level: 73));
      expect(find.text('Niv. 73'), findsOneWidget);
      expect(find.text('10 / 10'), findsNWidgets(5));
      for (final from in const [1, 11, 21, 31, 41]) {
        expect(find.byKey(Key('path-minis-$from')), findsOneWidget);
      }
      expect(find.text('Prestige · une étoile tous les 10 niveaux'), findsOneWidget);
      expect(_label(tester, 60), 'Niveau 60, Étoile de prestige 1\u00a0· Cadre\u00a0Légende, Atteint');
      expect(_label(tester, 70), endsWith('Atteint'));
      // 80 is next: 7 levels of 3 200 XP minus 51 % of one.
      expect(_label(tester, 80), contains('20\u202f768 XP'));
      expect(_label(tester, 90), endsWith('Verrouillé'));
      // Every star level draws one star, of one size (no « ★3 » next to two stars).
      for (final l in const [60, 70, 80, 90]) {
        final star = tester.widget<PrestigeStars>(find.byKey(Key('path-star-$l')));
        expect((star.count, star.size, star.maxDrawn), (1, 20.0, 5));
      }
      expect(tester.getRect(_row(80)).bottom, lessThanOrEqualTo(844));
    });

    testWidgets('level 50 exactly: the prestige card is the open one', (tester) async {
      await _open(tester, const LevelsPathScreen(), _provider(level: 50));
      expect(find.text('10 / 10'), findsNWidgets(5));
      expect(_label(tester, 60), contains('XP'));
      expect(find.byIcon(Icons.lock_outline_rounded), findsNWidgets(2)); // 70, 80
    });
  });

  group('6 · Progression in tabs', () {
    testWidgets('the level card, the three tabs with done / total, the day tab first', (tester) async {
      await _open(tester, const ProgressionScreen(), _provider());
      expect(find.text('23'), findsOneWidget);
      expect(find.text('Niveau 23'), findsOneWidget);
      expect(find.text('806 / 1\u202f580 XP'), findsOneWidget);
      expect(find.text('Parcours'), findsOneWidget);
      expect(_in(_tab(QuestTab.day), find.text('Jour')), findsOneWidget);
      expect(_in(_tab(QuestTab.day), find.text('1/3')), findsOneWidget);
      expect(_in(_tab(QuestTab.week), find.text('1/3')), findsOneWidget);
      expect(_in(_tab(QuestTab.discover), find.text('3/6')), findsOneWidget);
      expect(_tab(QuestTab.event), findsNothing);
      expect(_selected(tester), QuestTab.day);
      expect(find.text('Nouvelles quêtes dans 6 h'), findsOneWidget);
      expect(find.text('1 changement'), findsOneWidget);
      // Only the quests to do; no league card any more.
      expect(find.byType(QuestRow), findsNWidgets(2));
      expect(find.text('Marque une volée à 100+'), findsNothing);
      expect(find.textContaining('Ligue'), findsNothing);
    });

    testWidgets('each tab: its quests and its line', (tester) async {
      await _open(tester, const ProgressionScreen(), _provider());
      await _tap(tester, _tab(QuestTab.week));
      expect(_selected(tester), QuestTab.week);
      expect(find.text('Encore 6 j'), findsOneWidget);
      expect(find.text('Termine 10 séries classées'), findsOneWidget);
      expect(find.text('1 changement'), findsNothing);
      await _tap(tester, _tab(QuestTab.discover));
      expect(find.text('Une seule fois'), findsOneWidget);
      expect(find.byType(QuestRow), findsNWidgets(3));
      expect(find.text('3 terminées · +250 XP gagnés'), findsOneWidget);
    });

    testWidgets('opens on the first tab with a quest left to do', (tester) async {
      expect(ProgressionScreen.defaultTab(_quests()), QuestTab.day);
      expect(ProgressionScreen.defaultTab(_quests(dailyAllDone: true)), QuestTab.week);
      expect(ProgressionScreen.defaultTab(_quests(dailyAllDone: true, weeklyAllDone: true)), QuestTab.discover);
      expect(ProgressionScreen.defaultTab(null), QuestTab.day);
      await _open(tester, const ProgressionScreen(), _provider(quests: _quests(dailyAllDone: true)));
      expect(_selected(tester), QuestTab.week);
      expect(find.text('Joue 5 jours différents'), findsOneWidget);
    });

    testWidgets('the quests done fold into one line, which unfolds them', (tester) async {
      await _open(tester, const ProgressionScreen(), _provider());
      expect(find.text('1 terminée · +40 XP gagnés'), findsOneWidget);
      expect(find.text('Marque une volée à 100+'), findsNothing);
      await _tap(tester, find.byKey(const Key('quests-done-line')));
      expect(find.text('Marque une volée à 100+'), findsOneWidget);
      expect(find.byType(QuestRow), findsNWidgets(3));
      await _tap(tester, find.byKey(const Key('quests-done-line')));
      expect(find.text('Marque une volée à 100+'), findsNothing);
    });

    testWidgets('the swap icon sits on the daily quests that can change; changing one uses the day’s change', (tester) async {
      final p = _provider();
      await _open(tester, const ProgressionScreen(), p);
      expect(find.byKey(const Key('quest-change-d2')), findsOneWidget);
      expect(find.byKey(const Key('quest-change-d3')), findsOneWidget);
      expect(find.text('Changer une quête (1 par jour)'), findsNothing);

      // Cancelled: nothing sent.
      await _tap(tester, find.byKey(const Key('quest-change-d2')));
      expect(find.text('Changer cette quête ?'), findsOneWidget);
      await _tap(tester, find.text('Annuler'));
      expect(p.rerolled, isEmpty);

      await _tap(tester, find.byKey(const Key('quest-change-d2')));
      await _tap(tester, find.text('Changer'));
      expect(p.rerolled, ['d2']);
      expect(find.text('Quête neuve'), findsOneWidget);
      // The change is used: no icon left, « 0 changement ».
      expect(find.byKey(const Key('quest-change-new')), findsNothing);
      expect(find.byKey(const Key('quest-change-d3')), findsNothing);
      expect(find.text('0 changement'), findsOneWidget);
    });

    testWidgets('no icon on the week, on a quest done, or once the change is used', (tester) async {
      await _open(tester, const ProgressionScreen(), _provider(quests: _quests(rerollAvailable: false)));
      expect(find.byIcon(Icons.repeat_rounded), findsOneWidget); // the « 0 changement » line only
      expect(find.text('0 changement'), findsOneWidget);
      final q = _quests();
      expect(ProgressionScreen.canChange(q, q.weekly.quests.first), isFalse);
      expect(ProgressionScreen.canChange(q, q.daily.quests.first), isFalse); // done
      expect(ProgressionScreen.canChange(q, q.daily.quests[1]), isTrue);
    });

    testWidgets('a refused change says so', (tester) async {
      final p = _provider()..rerollOk = false;
      await _open(tester, const ProgressionScreen(), p);
      await _tap(tester, find.byKey(const Key('quest-change-d3')));
      await _tap(tester, find.text('Changer'));
      expect(find.text('Impossible de changer cette quête'), findsOneWidget);
    });

    testWidgets('event quests: a 4th tab « Événement » with its dates', (tester) async {
      await _open(tester, const ProgressionScreen(), _provider(quests: _quests(events: _winter())));
      expect(_tab(QuestTab.event), findsOneWidget);
      expect(_in(_tab(QuestTab.event), find.text('1/2')), findsOneWidget);
      expect(_selected(tester), QuestTab.day);
      await _tap(tester, _tab(QuestTab.event));
      // (The test font is wide: a long title may end on « … » after a whole word.)
      expect(find.textContaining('Gagne 5 séries'), findsOneWidget);
      expect(find.textContaining(RegExp(r'^Du .+ au .+$')), findsOneWidget);
      expect(find.text('1 terminée · +150 XP gagnés'), findsOneWidget);
    });

    testWidgets('no event tab without event quests, nor once the event is over', (tester) async {
      expect(ProgressionScreen.tabsFor(_quests()), [QuestTab.day, QuestTab.week, QuestTab.discover]);
      final over = _quests(events: _winter(endsAt: DateTime.now().subtract(const Duration(minutes: 1))));
      expect(ProgressionScreen.tabsFor(over), isNot(contains(QuestTab.event)));
      // Asked for, absent: the first tab with a quest to do.
      await _open(tester, const ProgressionScreen(initialTab: QuestTab.event), _provider());
      expect(_tab(QuestTab.event), findsNothing);
      expect(_selected(tester), QuestTab.day);
    });

    testWidgets('a long quest is never cut inside a word', (tester) async {
      const text = 'Fais un exercice de chaque famille (horloge, scoring, finitions, doubles)';
      await tester.pumpWidget(_app(const Center(child: SizedBox(width: 150, child: FitText(text, maxLines: 2, minFontSize: 11, wholeWords: true))), _provider()));
      await tester.pump();
      final shown = tester.widget<Text>(find.byType(Text)).data!;
      expect(shown == text || (shown.endsWith('…') && text.startsWith('${shown.substring(0, shown.length - 1)} ')), isTrue, reason: shown);
    });
  });

  group('opening the journal', () {
    testWidgets('the home strip opens its quest’s tab', (tester) async {
      expect(HomeQuestPick.of(_quests()).tab, QuestTab.day);
      expect(HomeQuestPick.of(_quests(dailyAllDone: true)).tab, QuestTab.week);
      expect(HomeQuestPick.of(_quests(dailyAllDone: true, weeklyAllDone: true)).tab, isNull);

      final p = _provider(quests: _quests(dailyAllDone: true));
      await _open(
        tester,
        Scaffold(body: Center(child: HomeQuestStrip(summary: p.summary, quests: p.quests))),
        p,
      );
      // The weekly quest closest to done: 3 / 10.
      await _tap(tester, find.textContaining('Termine 10 séries classées'));
      expect(tester.widget<ProgressionScreen>(find.byType(ProgressionScreen)).initialTab, QuestTab.week);
      expect(_selected(tester), QuestTab.week);
    });

    testWidgets('the strip wins over the default tab', (tester) async {
      // Daily quests to do, the week asked: the week opens.
      await _open(tester, const ProgressionScreen(initialTab: QuestTab.week), _provider());
      expect(_selected(tester), QuestTab.week);
      // The player's own tap wins over both.
      await _tap(tester, _tab(QuestTab.discover));
      expect(_selected(tester), QuestTab.discover);
    });

    testWidgets('« Voir la quête » of a locker event item opens the event tab', (tester) async {
      await _open(tester, const LockerScreen(), _provider(quests: _quests(events: _winter())));
      await _tap(tester, find.text('Fonds'));
      await _tap(tester, find.byKey(const Key('locker-locked-background.hiver')));
      await _tap(tester, find.text('Voir la quête'));
      expect(tester.widget<ProgressionScreen>(find.byType(ProgressionScreen)).initialTab, QuestTab.event);
      expect(_selected(tester), QuestTab.event);
      expect(find.textContaining('Gagne 5 séries'), findsOneWidget);
    });
  });
}
