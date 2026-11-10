import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mobile/l10n/app_localizations.dart';
import 'package:mobile/models/progression.dart';
import 'package:mobile/providers/progression_provider.dart';
import 'package:mobile/screens/achievements/achievement_models.dart';
import 'package:mobile/screens/progression/level_up_screen.dart';
import 'package:mobile/screens/progression/levels_path_screen.dart';
import 'package:mobile/widgets/progression/progression_widgets.dart';

/// Tour 5 (CONTRACT.md §14.8): the flat cost past level 50, the prestige
/// stars on the Légende frame, the achievement tiers under review.

class _FakeProgression extends ProgressionProvider {
  @override
  Future<void> refreshSummary() async {}
  @override
  Future<void> refreshQuests() async {}
  @override
  Future<void> refreshContent() async {}
  @override
  Future<void> markLevelSeen(int level) async {}
}

final _content = ProgressionContent.fromJson({
  'version': 'v5',
  'curve': {'base': 200, 'perLevel': 60, 'capLevel': 50},
  'prestige': {'frameId': 'frame.legende', 'fromLevel': 50, 'everyLevels': 10},
  'items': [
    {
      'id': 'frame.legende',
      'type': 'frame',
      'name': {'fr': 'Légende', 'en': 'Legend'},
      'source': {'kind': 'level', 'level': 50, 'label': {'fr': 'niveau 50', 'en': 'level 50'}},
      'render': {'kind': 'frame', 'metal': 'legende', 'corners': true},
    },
    {
      'id': 'frame.laiton',
      'type': 'frame',
      'name': {'fr': 'Laiton', 'en': 'Brass'},
      'source': {'kind': 'level', 'level': 15, 'label': {'fr': 'niveau 15', 'en': 'level 15'}},
      'render': {'kind': 'frame', 'metal': 'laiton'},
    },
  ],
  'levels': [
    {
      'level': 50,
      'itemIds': ['frame.legende'],
      'premiumItemIds': [],
    },
  ],
});

Widget _app(Widget child, ProgressionProvider provider) => ChangeNotifierProvider<ProgressionProvider>.value(
      value: provider,
      child: MaterialApp(
        locale: const Locale('fr'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      ),
    );

ProgressionProvider _seeded({ProgressionSummary? summary}) =>
    _FakeProgression()..debugSeed(content: _content, summary: summary);

int _starsShown(WidgetTester tester) =>
    tester.widgetList<PrestigeStars>(find.byType(PrestigeStars)).fold(0, (n, w) => n + w.count);

void main() {
  group('XP curve past level 50', () {
    test('every level after 50 costs 3 200 XP, like the server', () {
      const curve = XpCurve();
      expect(curve.xpToNext(50), 3200);
      expect(curve.xpToNext(51), 3200);
      expect(curve.xpToNext(120), 3200);
      expect(curve.xpForLevel(50), 83300);
      expect(curve.xpForLevel(51), 86500);
      expect(curve.xpForLevel(60), 86500 + 9 * 3200);
      expect(_content.curve.capLevel, 50);
    });

    test('a server curve without capLevel keeps growing (older backend)', () {
      final curve = XpCurve.fromJson({'base': 200, 'perLevel': 60});
      expect(curve.capLevel, isNull);
      expect(curve.xpToNext(120), 7400);
      expect(XpCurve.fromJson(null).capLevel, 50);
    });
  });

  group('PrestigeDef', () {
    const p = PrestigeDef(frameId: 'frame.legende');

    test('one star every 10 levels past 50', () {
      expect(p.starsFor(50), 0);
      expect(p.starsFor(59), 0);
      expect(p.starsFor(60), 1);
      expect(p.starsFor(69), 1);
      expect(p.starsFor(70), 2);
      expect(p.starsFor(125), 7);
      expect(p.isStarLevel(60), isTrue);
      expect(p.isStarLevel(65), isFalse);
      expect(p.isStarLevel(50), isFalse);
      expect(p.nextStarLevel(55), 60);
      expect(p.nextStarLevel(60), 70);
      expect(p.levelOfStar(3), 80);
    });

    test('only on the Légende frame, and data-driven', () {
      expect(p.starsOn('frame.legende', 72), 2);
      expect(p.starsOn('frame.laiton', 72), 0);
      expect(p.starsOn(null, 72), 0);
      expect(PrestigeDef.fromJson(null), isNull);
      expect(PrestigeDef.fromJson({'frameId': 'frame.legende', 'fromLevel': 0, 'everyLevels': 10}), isNull);
      expect(_content.prestigeStars('frame.legende', 81), 3);
      expect(ProgressionContent.fromJson({'version': 'old'}).prestigeStars('frame.legende', 81), 0);
    });
  });

  group('Parcours des niveaux', () {
    test('tiers 1 → 50, then the prestige levels up to two stars past mine', () {
      expect(LevelsPathScreen.tiers(_content).map((t) => (t.from, t.to)), [(1, 10), (11, 20), (21, 30), (31, 40), (41, 50)]);
      expect(LevelsPathScreen.prestigeLevels(_content, 12), [60, 70, 80]);
      expect(LevelsPathScreen.prestigeLevels(_content, 73), [60, 70, 80, 90]);
      // Without prestige data: no prestige card.
      expect(LevelsPathScreen.prestigeLevels(ProgressionContent.fromJson({'version': 'old'}), 52), isEmpty);
    });

    testWidgets('names the star of level 60', (tester) async {
      await tester.pumpWidget(_app(
        const LevelsPathScreen(),
        _seeded(summary: const ProgressionSummary(level: 61, levelSeen: 61)),
      ));
      await tester.pump();
      await tester.pump();
      expect(find.text('Étoile de prestige 1\u00a0· Cadre\u00a0Légende'), findsOneWidget);
    });
  });

  group('Prestige stars on the Légende frame', () {
    testWidgets('CardFrame: floor((level − 50) / 10) stars, Légende only', (tester) async {
      Future<void> card(String frame, int level) => tester.pumpWidget(_app(
            SizedBox(
              width: 358,
              height: 150,
              child: CardFrame(frameId: frame, level: level, child: const ColoredBox(color: Colors.black)),
            ),
            _seeded(),
          ));
      await card('frame.legende', 72);
      await tester.pump();
      expect(tester.getSize(find.byType(CardFrame)), const Size(358, 150));
      expect(_starsShown(tester), 2);
      await card('frame.legende', 59);
      await tester.pump();
      expect(find.byType(PrestigeStars), findsNothing);
      await card('frame.laiton', 99);
      await tester.pump();
      expect(find.byType(PrestigeStars), findsNothing);
    });

    testWidgets('FramedAvatar: the plate on the ring, one star when tiny', (tester) async {
      Future<void> avatar(double size, int level) => tester.pumpWidget(_app(
            Center(
              child: FramedAvatar(
                rank: 'gold',
                size: size,
                cosmetics: PublicCosmetics(level: level, frame: 'frame.legende', monogram: 'DO'),
              ),
            ),
            _seeded(),
          ));
      await avatar(36, 80);
      await tester.pump();
      expect(tester.getSize(find.byType(FramedAvatar)), const Size(36, 36));
      expect(_starsShown(tester), 3);
      await avatar(20, 80);
      await tester.pump();
      expect(_starsShown(tester), 1);
      await avatar(36, 50);
      await tester.pump();
      expect(find.byType(PrestigeStars), findsNothing);
    });

    testWidgets('Niveau gagné announces the star at 60', (tester) async {
      await tester.pumpWidget(_app(
        const LevelUpScreen(level: 60),
        _seeded(
          summary: const ProgressionSummary(
            level: 60,
            levelSeen: 59,
            xpToNext: 3200,
            cosmetics: PublicCosmetics(level: 60, frame: 'frame.legende', monogram: 'DO'),
          ),
        ),
      ));
      await tester.pump();
      await tester.pump();
      expect(find.text('Étoile de prestige 1'), findsOneWidget);
      expect(find.text('Une étoile de plus sur ton cadre Légende.'), findsOneWidget);
      expect(find.text('Prochaine étoile de prestige au niveau 70'), findsOneWidget);
    });

    testWidgets('Niveau gagné without a star past 50: the next star level', (tester) async {
      await tester.pumpWidget(_app(
        const LevelUpScreen(level: 55),
        _seeded(summary: const ProgressionSummary(level: 55, levelSeen: 54, xpToNext: 3200)),
      ));
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('Étoile de prestige'), findsNothing);
      expect(find.text('Prochaine étoile de prestige au niveau 60'), findsOneWidget);
    });
  });

  test('achievement tiers under review are read defensively', () {
    final a = Achievement.fromJson({
      'id': 'grosse-moyenne',
      'badgeId': 'badge.grosse-moyenne',
      'family': 'scoring',
      'pendingReview': true,
      'steps': [
        {'tier': 'bronze', 'threshold': 45, 'unlockedAt': '2026-11-01T10:00:00Z'},
        {'tier': 'silver', 'threshold': 60, 'pending': true},
        {'tier': 'gold', 'threshold': 75},
      ],
    })!;
    expect(a.pendingReview, isTrue);
    expect(a.steps.map((s) => s.pending), [false, true, false]);
    // An older server (no key): nothing pending.
    final old = Achievement.fromJson({'id': 'x', 'badgeId': 'badge.x', 'steps': [{'tier': 'bronze', 'threshold': 1}]})!;
    expect(old.pendingReview, isFalse);
    expect(old.steps.single.pending, isFalse);
  });
}
