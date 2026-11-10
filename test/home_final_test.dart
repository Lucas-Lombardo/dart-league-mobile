// The validated final home (docs/progression/ecrans/AccFinal*, CONTRACT
// §14.9): the S1 player card, the quest strip, Compétitif (K1), the
// « Aujourd'hui » and « Jouer autrement » tiles, and the XP read from the
// server's content.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:mobile/l10n/app_localizations.dart';
import 'package:mobile/models/progression.dart';
import 'package:mobile/providers/progression_provider.dart';
import 'package:mobile/screens/challenge/challenge_api.dart';
import 'package:mobile/screens/challenge/challenge_entry.dart';
import 'package:mobile/screens/challenge/challenge_models.dart';
import 'package:mobile/screens/home/competitive_card.dart';
import 'package:mobile/screens/home/home_quest_strip.dart';
import 'package:mobile/screens/league/league_models.dart';
import 'package:mobile/screens/league/league_store.dart';
import 'package:mobile/screens/league/league_widgets.dart';
import 'package:mobile/widgets/home_tiles.dart';
import 'package:mobile/widgets/progression/metal.dart';
import 'package:mobile/widgets/progression/player_showcase_card.dart';

class _FakeProgression extends ProgressionProvider {
  @override
  Future<void> refreshSummary() async {}
  @override
  Future<void> refreshQuests() async {}
  @override
  Future<void> refreshContent() async {}
}

Map<String, dynamic> _item(String id, String type, Map<String, dynamic> render) => {
      'id': id,
      'type': type,
      'name': {'fr': id, 'en': id},
      'source': {'kind': 'level', 'level': 2, 'label': {'fr': 'n', 'en': 'l'}},
      'render': render,
    };

final _contentJson = <String, dynamic>{
  'version': 'v1',
  'prestige': {'frameId': 'frame.legende', 'fromLevel': 50, 'everyLevels': 10},
  'items': [
    _item('frame.legende', 'frame', {'kind': 'frame', 'metal': 'legende'}),
    _item('frame.obsidienne', 'frame', {'kind': 'frame', 'metal': 'obsidienne'}),
    {..._item('title.big-fish', 'title', {}), 'name': {'fr': 'Big Fish', 'en': 'Big Fish'}},
    _item('avatar.monogramme-acier', 'avatar', {'kind': 'monogram', 'metal': 'acier', 'shape': 'round'}),
  ],
  'defs': {
    'league': [
      {'id': 'cuivre', 'type': 'tier'},
      {
        'id': 'settings',
        'type': 'settings',
        'xpByPosition': [
          {'to': 10, 'xp': 100},
          {'to': 3, 'xp': 200},
          {'to': 5, 'xp': 150},
          {'to': 20, 'xp': 30},
        ],
      },
    ],
  },
  'xp': {'ranked': 60, 'rankedWin': 40, 'friendly': 30, 'training': 30, 'ghost': 40, 'challenge': 50},
};

Widget _app(Widget child, {ProgressionProvider? provider}) {
  final app = MaterialApp(
    locale: const Locale('fr'),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: child)),
  );
  if (provider == null) return app;
  return ChangeNotifierProvider<ProgressionProvider>.value(value: provider, child: app);
}

UserQuest _q(String id, int progress, int threshold, {String status = 'active', String period = 'daily', int xp = 40}) =>
    UserQuest(
      id: id,
      questId: id,
      period: period,
      text: LocalizedText(fr: 'quête $id', en: 'quest $id'),
      progress: progress,
      threshold: threshold,
      xp: xp,
      status: status,
    );

void main() {
  group('content', () {
    test('reads the XP of each way of playing, null when the server has none', () {
      final c = ProgressionContent.fromJson(_contentJson);
      expect(c.xp?.ranked, 60);
      expect(c.xp?.friendly, 30);
      expect(c.xp?.ghost, 40);
      expect(c.xp?.challenge, 50);
      expect(ProgressionContent.fromJson({'version': 'old'}).xp, isNull);
      expect(XpRules.fromJson({'ranked': 'x', 'training': -3})?.ranked, isNull);
      expect(XpRules.fromJson({'ranked': 'x', 'training': -3})?.training, isNull);
    });

    test('the league XP of a place follows the bands of league.json', () {
      final c = ProgressionContent.fromJson(_contentJson);
      expect(c.leagueXpFor(1), 200);
      expect(c.leagueXpFor(4), 150);
      expect(c.leagueXpFor(6), 100);
      expect(c.leagueXpFor(20), 30);
      expect(c.leagueXpFor(21), 0);
      expect(ProgressionContent.fromJson({'version': 'v'}).leagueXpFor(1), isNull);
    });
  });

  group('quest strip', () {
    test('picks the daily quest closest to done, then a weekly one, then none', () {
      var pick = HomeQuestPick.of(QuestsSnapshot(
        daily: QuestSection(quests: [_q('a', 1, 5), _q('b', 3, 5), _q('c', 1, 1, status: 'completed'), _q('d', 3, 5)]),
      ));
      expect(pick.quest?.id, 'b');
      expect(pick.weekly, isFalse);
      expect((pick.dailyDone, pick.dailyTotal), (1, 4));

      pick = HomeQuestPick.of(QuestsSnapshot(
        daily: QuestSection(quests: [_q('a', 1, 1, status: 'completed')]),
        weekly: QuestSection(quests: [_q('w1', 1, 10, period: 'weekly'), _q('w2', 6, 10, period: 'weekly')]),
      ));
      expect(pick.quest?.id, 'w2');
      expect(pick.weekly, isTrue);

      pick = HomeQuestPick.of(QuestsSnapshot(daily: QuestSection(quests: [_q('a', 1, 1, status: 'completed')])));
      expect(pick.quest, isNull);
    });

    testWidgets('shows the quest, its progress, its XP and the daily count', (tester) async {
      await tester.pumpWidget(_app(HomeQuestStrip(
        summary: const ProgressionSummary(level: 3, xpIntoLevel: 100, xpToNext: 400),
        quests: QuestsSnapshot(daily: QuestSection(quests: [_q('a', 3, 5), _q('b', 1, 1, status: 'completed'), _q('c', 0, 2)])),
      )));
      await tester.pumpAndSettle();
      expect(find.text('Quête : quête a'), findsOneWidget);
      expect(find.text(' · 3/5'), findsOneWidget);
      expect(find.text('+40 XP'), findsOneWidget);
      expect(find.text('1/3'), findsOneWidget);
    });

    testWidgets('says the daily quests are done when nothing is left', (tester) async {
      await tester.pumpWidget(_app(HomeQuestStrip(
        quests: QuestsSnapshot(daily: QuestSection(quests: [_q('a', 1, 1, status: 'completed')])),
      )));
      await tester.pumpAndSettle();
      expect(find.text('Quêtes du jour terminées'), findsOneWidget);
      expect(find.text('1/1'), findsOneWidget);
    });

    testWidgets('draws nothing before the APIs answer', (tester) async {
      await tester.pumpWidget(_app(const HomeQuestStrip()));
      await tester.pumpAndSettle();
      expect(find.byType(Text), findsNothing);
    });
  });

  group('player card (S1)', () {
    testWidgets('name, crown, title plate, level hexagon and « Modifier » on my own card', (tester) async {
      final p = _FakeProgression()..debugSeed(content: ProgressionContent.fromJson(_contentJson));
      var edited = 0;
      await tester.pumpWidget(_app(
        PlayerShowcaseCard(
          username: 'Dodo180',
          rank: 'gold',
          isPremium: true,
          cosmetics: const PublicCosmetics(level: 23, monogram: 'DO', title: 'title.big-fish', avatar: 'avatar.monogramme-acier'),
          onEdit: () => edited++,
        ),
        provider: p,
      ));
      await tester.pumpAndSettle();
      expect(find.text('Dodo180'), findsOneWidget);
      expect(find.text('Big Fish'), findsOneWidget);
      expect(find.byType(PremiumCrown), findsOneWidget);
      expect(find.bySemanticsLabel('Niv. 23'), findsOneWidget);
      expect(tester.getSize(find.byType(PlayerShowcaseCard)).height, PlayerShowcaseCard.artHeight + 2 * PlayerShowcaseCard.rim);
      await tester.tap(find.text('Modifier'));
      expect(edited, 1);
    });

    testWidgets("someone else's card: no « Modifier », no crown, prestige stars on Légende", (tester) async {
      final p = _FakeProgression()..debugSeed(content: ProgressionContent.fromJson(_contentJson));
      await tester.pumpWidget(_app(
        const PlayerShowcaseCard(
          username: 'LaFleche',
          rank: 'platinum',
          cosmetics: PublicCosmetics(level: 63, frame: 'frame.legende'),
        ),
        provider: p,
      ));
      await tester.pumpAndSettle();
      expect(find.text('Modifier'), findsNothing);
      expect(find.byType(PremiumCrown), findsNothing);
      expect(find.bySemanticsLabel('★ 1'), findsOneWidget);
    });

    testWidgets('without progression: the rank badge, no hexagon', (tester) async {
      await tester.pumpWidget(_app(const PlayerShowcaseCard(username: 'Old', rank: 'gold')));
      await tester.pumpAndSettle();
      expect(find.byType(LevelHexagon), findsNothing);
      expect(find.byType(Image), findsOneWidget);
    });

    test('dark text on light metals, light text on obsidian', () {
      expect(PlayerShowcaseCard.isDarkMetal(MetalPalette.fallback['obsidienne']!), isTrue);
      expect(PlayerShowcaseCard.isDarkMetal(MetalPalette.fallback['laiton']!), isFalse);
      expect(PlayerShowcaseCard.isDarkMetal(MetalPalette.fallback['legende']!), isFalse);
      expect(PlayerShowcaseCard.isDarkMetal(MetalPalette.fallback['acier']!), isFalse);
    });
  });

  group('Compétitif (K1)', () {
    Widget card({VoidCallback? onTap, int ranked = 0, int total = 0, String? xp}) => CompetitiveCard(
          leading: const SizedBox.square(dimension: 48),
          label: 'Compétitif · #17',
          value: '1 409',
          progress: 0.6,
          caption: 'Platine dans 191 pts',
          actionLabel: 'Jouer',
          actionXp: xp,
          onTap: onTap,
          liveRanked: ranked,
          liveTotal: total,
        );

    testWidgets('134 pt, the play slot, its XP and the live ranked matches', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_app(card(onTap: () => taps++, ranked: 3, total: 4, xp: '+60 XP')));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(CompetitiveCard)).height, 134);
      expect(find.text('Compétitif · #17'), findsOneWidget);
      expect(find.text('Platine dans 191 pts'), findsOneWidget);
      expect(find.text('+60 XP'), findsOneWidget);
      expect(find.text('3 matchs classés en direct'), findsOneWidget);
      expect(find.text('Regarder'), findsOneWidget);
      await tester.tap(find.text('Jouer'));
      expect(taps, 1);
    });

    testWidgets('nothing live: the same strip, a quiet line, nothing to tap', (tester) async {
      await tester.pumpWidget(_app(card(onTap: () {})));
      await tester.pumpAndSettle();
      expect(find.text('Aucun match classé en direct'), findsOneWidget);
      expect(find.text('Regarder'), findsNothing);
      expect(tester.getSize(find.byType(CompetitiveCard)).height, 134);
    });

    testWidgets('tournament matches only: the existing « N matchs en direct »', (tester) async {
      await tester.pumpWidget(_app(card(onTap: () {}, total: 2)));
      await tester.pumpAndSettle();
      expect(find.text('2 matchs en direct'), findsOneWidget);
      expect(find.text('Regarder'), findsOneWidget);
    });

    testWidgets('locked (ranked blocked by a tournament): a lock, no XP', (tester) async {
      await tester.pumpWidget(_app(card()));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
    });
  });

  group('tiles', () {
    tearDown(() {
      ChallengeStore.instance.debugSeed(null);
      LeagueStore.instance.reset();
    });

    testWidgets('« Jouer autrement »: XP, « sans XP » and the premium crown', (tester) async {
      await tester.pumpWidget(_app(const HomeTileRow(children: [
        HomeModeTile(icon: Icon(Icons.smartphone_outlined), label: 'Match local', xp: 'sans XP', mutedXp: true),
        HomeModeTile(icon: Icon(Icons.people), label: 'Match fantôme', xp: '+40 XP', premium: true),
      ])));
      await tester.pumpAndSettle();
      expect(find.text('sans XP'), findsOneWidget);
      expect(find.text('+40 XP'), findsOneWidget);
      expect(find.byType(PremiumCrown), findsOneWidget);
      expect(tester.getSize(find.byType(HomeModeTile).first).height, 56);
    });

    testWidgets('« Défi du jour »: the format and its XP, blue until played', (tester) async {
      ChallengeStore.instance.debugSeed(
        ChallengeToday.fromJson({
          'date': '2026-11-08',
          'format': {
            'id': 'cricket-30',
            'name': {'fr': 'Cricket · 30 fléchettes', 'en': 'Cricket · 30 darts'},
            'short': {'fr': 'Cricket · 30', 'en': 'Cricket · 30'},
            'rule': {'fr': 'r', 'en': 'r'},
            'tag': {'fr': 't', 'en': 't'},
            'mode': 'cricket_marks',
            'params': {'darts': 30},
            'score': {'order': 'desc', 'unit': {'fr': 'marques', 'en': 'marks'}, 'max': 90},
            'tiebreak': {'order': 'desc', 'label': {'fr': 'x', 'en': 'x'}},
            'durationMin': 4,
          },
          'ranked': null,
        }),
      );
      await tester.pumpWidget(_app(const ChallengeTodayTile(xp: 50)));
      await tester.pumpAndSettle();
      expect(find.text('Défi du jour'), findsOneWidget);
      expect(find.text('+50 XP'), findsOneWidget);
      expect(find.textContaining('Cricket · 30'), findsOneWidget);
      expect(find.byWidgetPredicate((w) => w is HomeTodayTile && w.accent), findsOneWidget);
    });

    testWidgets('« Ligue … »: the place and the XP that place pays', (tester) async {
      LeagueStore.instance.debugSeed(LeagueSnapshot.fromJson({
        'enabled': true,
        'weekKey': '2026-11-02',
        'league': {'id': 'cuivre', 'order': 2, 'name': {'fr': 'Cuivre', 'en': 'Copper'}, 'color': '#E8A27A', 'colors': []},
        'state': 'open',
        'group': {'id': 'g', 'size': 20, 'standings': []},
        'me': {'position': 6, 'points': 120},
      }));
      final c = ProgressionContent.fromJson(_contentJson);
      await tester.pumpWidget(_app(LeagueTodayTile(xpForPosition: c.leagueXpFor)));
      await tester.pumpAndSettle();
      expect(find.text('Ligue Cuivre'), findsOneWidget);
      expect(find.text('+100 XP'), findsOneWidget);
    });
  });
}
