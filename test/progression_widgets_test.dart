import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mobile/l10n/app_localizations.dart';
import 'package:mobile/models/progression.dart';
import 'package:mobile/providers/progression_provider.dart';
import 'package:mobile/screens/progression/progression_screen.dart';
import 'package:mobile/screens/progression/today_section.dart';
import 'package:mobile/screens/progression/match_found_screen.dart';
import 'package:mobile/models/head_to_head.dart';
import 'package:mobile/services/progression_service.dart';
import 'package:mobile/widgets/game_turn_ui.dart';
import 'package:mobile/widgets/progression/monogram_avatar.dart';
import 'package:mobile/widgets/progression/progression_widgets.dart';

/// No network in widget tests: the screen's refreshes are no-ops.
class _FakeProgression extends ProgressionProvider {
  @override
  Future<void> refreshSummary() async {}
  @override
  Future<void> refreshQuests() async {}
  @override
  Future<void> refreshContent() async {}
}

final _content = ProgressionContent.fromJson({
  'version': 'v1',
  'items': [
    {
      'id': 'avatar.couronne',
      'type': 'avatar',
      'name': {'fr': 'Couronne', 'en': 'Crown'},
      'source': {'kind': 'achievement', 'label': {'fr': 'succès', 'en': 'achievement'}},
      'render': {'kind': 'monogram', 'metal': 'or', 'shape': 'round', 'ornament': 'couronne'},
    },
    {
      'id': 'title.finisseur',
      'type': 'title',
      'name': {'fr': 'Finisseur', 'en': 'Finisher'},
      'source': {'kind': 'achievement', 'label': {'fr': 's', 'en': 'a'}},
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
    {'level': 15, 'itemIds': ['frame.laiton'], 'premiumItemIds': []},
  ],
});

Widget _app(Widget child, {ProgressionProvider? provider, Locale locale = const Locale('fr')}) {
  final app = MaterialApp(
    locale: locale,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );
  if (provider == null) return app;
  return ChangeNotifierProvider<ProgressionProvider>.value(value: provider, child: app);
}

void main() {
  testWidgets('MonogramAvatar paints every shape, engraving and ornament', (tester) async {
    for (final params in const [
      ('round', null, null, false),
      ('ecusson', 'guilloche', null, true),
      ('hexagone', 'carbone', null, false),
      ('round', 'cible', 'couronne', false),
      ('round', 'cadran', 'laurier', false),
    ]) {
      await tester.pumpWidget(_app(Center(
        child: MonogramAvatar(text: 'D16', metal: 'or', shape: params.$1, engraving: params.$2, ornament: params.$3, plate: params.$4, size: 96),
      )));
      await tester.pump();
      expect(tester.getSize(find.byType(MonogramAvatar)), const Size(96, 96));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('PlayerAvatar falls back to the rank badge without a provider or item', (tester) async {
    await tester.pumpWidget(_app(const Center(child: PlayerAvatar(rank: 'gold', size: 48))));
    await tester.pump();
    expect(find.byType(Image), findsOneWidget);
    expect(find.byType(MonogramAvatar), findsNothing);
  });

  testWidgets('PlayerAvatar draws the equipped monogram with the player text', (tester) async {
    final p = _FakeProgression()..debugSeed(content: _content);
    await tester.pumpWidget(_app(
      const Center(
        child: PlayerAvatar(
          rank: 'gold',
          size: 64,
          cosmetics: PublicCosmetics(level: 3, avatar: 'avatar.couronne', monogram: 'KD'),
        ),
      ),
      provider: p,
    ));
    await tester.pump();
    final mono = tester.widget<MonogramAvatar>(find.byType(MonogramAvatar));
    expect(mono.text, 'KD');
    expect(mono.ornament, 'couronne');
  });

  testWidgets('TitleText and LevelChip use the content and l10n', (tester) async {
    final p = _FakeProgression()..debugSeed(content: _content);
    await tester.pumpWidget(_app(
      const Column(children: [TitleText(titleId: 'title.finisseur'), TitleText(titleId: 'title.unknown'), LevelChip(level: 14)]),
      provider: p,
    ));
    await tester.pump();
    expect(find.text('Finisseur'), findsOneWidget);
    expect(find.text('Niv. 14'), findsOneWidget);
  });

  testWidgets('TodaySection hides until quests exist, then shows progress', (tester) async {
    final p = _FakeProgression()..debugSeed(content: _content);
    await tester.pumpWidget(_app(const TodaySection(), provider: p));
    await tester.pump();
    expect(find.text('Quêtes'), findsNothing);

    p.debugSeed(
      quests: QuestsSnapshot.fromJson({
        'daily': {
          'quests': [
            {'id': 'a', 'text': {'fr': 'A', 'en': 'A'}, 'progress': 1, 'threshold': 1, 'xp': 50, 'status': 'completed'},
            {'id': 'b', 'text': {'fr': 'B', 'en': 'B'}, 'progress': 0, 'threshold': 1, 'xp': 40},
            {'id': 'c', 'text': {'fr': 'C', 'en': 'C'}, 'progress': 0, 'threshold': 3, 'xp': 50},
          ],
        },
      }),
    );
    await tester.pump();
    expect(find.text('Quêtes'), findsOneWidget);
    expect(find.text('1 sur 3 · +90 XP à prendre'), findsOneWidget);
  });

  testWidgets('ProgressionScreen shows the level and the day tab', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final p = _FakeProgression()
      ..debugSeed(
        content: _content,
        summary: ProgressionSummary.fromJson({
          'level': 14,
          'xpIntoLevel': 812,
          'xpToNext': 1040,
          'nextRewards': {'level': 15, 'itemIds': ['frame.laiton'], 'premiumItemIds': []},
        }),
        quests: QuestsSnapshot.fromJson({
          'daily': {
            'rerollAvailable': true,
            'quests': [
              {'id': 'a', 'text': {'fr': 'Gagne une manche classée', 'en': 'Win a ranked leg'}, 'progress': 1, 'threshold': 1, 'xp': 60, 'status': 'completed'},
              {'id': 'b', 'text': {'fr': 'Marque 3 volées à 100+', 'en': 'Score 3 visits of 100+'}, 'progress': 1, 'threshold': 3, 'xp': 50},
            ],
          },
          'weekly': {
            'quests': [
              {'id': 'w', 'text': {'fr': 'Gagne 3 séries classées', 'en': 'Win 3 ranked series'}, 'progress': 2, 'threshold': 3, 'xp': 200},
            ],
          },
        }),
      );
    await tester.pumpWidget(ChangeNotifierProvider<ProgressionProvider>.value(
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
        home: const ProgressionScreen(),
      ),
    ));
    await tester.pump();
    await tester.pump();
    expect(tester.getSize(find.byType(ProgressionScreen)), const Size(390, 844));
    // Piste A (CONTRACT §14.14): the day tab only, the quest done folded.
    expect(find.text('Niveau 14'), findsOneWidget);
    expect(find.text('812 / 1\u202f040 XP'), findsOneWidget);
    expect(find.text('Marque 3 volées à 100+'), findsOneWidget);
    expect(find.text('Gagne 3 séries classées'), findsNothing);
    expect(find.text('1 terminée · +60 XP gagnés'), findsOneWidget);
    expect(find.byType(QuestRow), findsOneWidget);
  });

  testWidgets('FlightMarker and CardFrame render', (tester) async {
    final p = _FakeProgression()..debugSeed(content: _content);
    await tester.pumpWidget(_app(
      const Column(
        children: [
          FlightMarker(size: 24),
          SizedBox(width: 200, height: 100, child: CardFrame(frameId: 'frame.laiton', child: ColoredBox(color: Colors.black))),
        ],
      ),
      provider: p,
    ));
    await tester.pump();
    expect(find.byType(FlightMarker), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('XpProgressBar fills its share of the whole track, at full height', (tester) async {
    // Left-aligned column (loose width, the profile tile) and a row slot
    // (tight width, the end-of-match panel): the track keeps the whole
    // width, the fill 806 / 1580 of it and the bar's height.
    await tester.pumpWidget(const Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 200,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              XpProgressBar(key: Key('loose'), xpIntoLevel: 806, xpToNext: 1580, height: 4),
              Row(children: [Expanded(child: XpProgressBar(key: Key('tight'), xpIntoLevel: 1580, xpToNext: 1580))]),
              XpProgressBar(key: Key('empty'), xpIntoLevel: 10, xpToNext: 0),
            ],
          ),
        ),
      ),
    ));
    Size fill(String bar) => tester.getSize(
          find.descendant(of: find.byKey(Key(bar)), matching: find.byKey(const Key('xp-progress-fill'))).first,
        );
    Size child(String bar) => tester.getSize(
          find.descendant(of: find.byKey(Key(bar)), matching: find.byType(ColoredBox)).last,
        );
    expect(tester.getSize(find.byKey(const Key('loose'))), const Size(200, 4));
    expect(fill('loose'), const Size(200, 4));
    expect(child('loose').width, closeTo(200 * 806 / 1580, 0.01));
    expect(child('loose').height, 4);
    expect(child('tight'), const Size(200, 6));
    expect(child('empty'), const Size(0, 6));
    expect(tester.takeException(), isNull);
  });

  // ---- Agent 1 (suite) ----

  testWidgets('MatchFoundScreen shows the head-to-head line once loaded', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final p = _FakeProgression()..debugSeed(content: _content);
    await tester.pumpWidget(_app(
      MatchFoundScreen(
        subtitle: 'Série classée · BO3 · 501',
        me: const MatchFoundPlayer(username: 'Dodo180', rank: 'platinum', elo: 1619),
        opponent: const MatchFoundPlayer(username: 'Mika_180', rank: 'gold', elo: 1412),
        opponentId: 'opp',
        loadRecord: (_) async => const HeadToHeadRecord(wins: 7, losses: 5, encounters: 12),
      ),
      provider: p,
    ));
    await tester.pump();
    await tester.pump();
    // CONTRACT §14.13: « Bilan 7 – 5 », no « Votre » (tutoiement).
    expect(find.text('Bilan 7 – 5'), findsOneWidget);
    expect(find.text('Mika_180'), findsOneWidget);
  });

  testWidgets('MatchFoundScreen says "first meeting" with no history', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(
      MatchFoundScreen(
        subtitle: 's',
        me: const MatchFoundPlayer(username: 'A', rank: 'gold'),
        opponent: const MatchFoundPlayer(username: 'B', rank: 'gold'),
        opponentId: 'opp',
        loadRecord: (_) async => const HeadToHeadRecord(),
      ),
    ));
    await tester.pump();
    await tester.pump();
    expect(find.text('Première rencontre'), findsOneWidget);
  });

  testWidgets('the match header shows each player avatar next to the name', (tester) async {
    final p = _FakeProgression()..debugSeed(content: _content);
    p.debugSeedPlayer(
      'opp',
      const PlayerLook(rank: 'gold', cosmetics: PublicCosmetics(level: 9, avatar: 'avatar.couronne', monogram: 'MK', frame: 'frame.laiton')),
    );
    await tester.pumpWidget(_app(
      const TurnScoreHeader(
        myName: 'Dodo180',
        opponentName: 'Mika_180',
        myScore: 32,
        opponentScore: 0,
        showBadges: false,
        myAvatar: MatchAvatar(userId: 'me', rank: 'platinum', cosmetics: PublicCosmetics(level: 15)),
        opponentAvatar: MatchAvatar(userId: 'opp'),
      ),
      provider: p,
    ));
    await tester.pump();
    expect(find.byType(MatchAvatar), findsNWidgets(2));
    // The opponent's equipped monogram (from the player cache), mine = rank badge.
    expect(tester.widget<MonogramAvatar>(find.byType(MonogramAvatar)).text, 'MK');
    expect(tester.takeException(), isNull);
  });
}
