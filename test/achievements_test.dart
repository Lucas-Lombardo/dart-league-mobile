import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mobile/l10n/app_localizations.dart';
import 'package:mobile/models/progression.dart';
import 'package:mobile/providers/progression_provider.dart';
import 'package:mobile/screens/achievements/achievement_detail_screen.dart';
import 'package:mobile/screens/achievements/achievement_format.dart';
import 'package:mobile/screens/achievements/achievement_models.dart';
import 'package:mobile/screens/achievements/achievement_unlock_sheet.dart';
import 'package:mobile/screens/achievements/achievements_profile_tile.dart';
import 'package:mobile/screens/achievements/achievements_screen.dart';
import 'package:mobile/screens/achievements/badge_picker.dart';
import 'package:mobile/screens/progression/progression_format.dart';

/// A server-like achievement (GET /achievements).
Map<String, dynamic> _ach(
  String id, {
  String family = 'scoring',
  String? tier,
  double value = 0,
  Map<String, dynamic>? next,
  List<double> thresholds = const [1, 10, 100],
  bool unique = false,
  String format = 'int',
  String aggregate = 'count',
  double? rarity,
  List<Map<String, dynamic>>? labels,
}) =>
    {
      'id': id,
      'family': family,
      'sortOrder': 10,
      'name': {'fr': 'Nom $id', 'en': 'Name $id'},
      'description': {'fr': 'Desc', 'en': 'Desc'},
      'badgeId': 'badge.$id',
      'aiOnly': true,
      'format': format,
      'aggregate': aggregate,
      'unique': unique,
      'tier': tier,
      'value': value,
      'best': null,
      'next': next,
      'steps': unique
          ? [
              {'tier': 'unique', 'threshold': thresholds.first, 'xp': 500, 'itemIds': [], 'unlockedAt': tier == null ? null : '2026-10-04T20:00:00Z', 'rarity': rarity},
            ]
          : [
              for (var i = 0; i < 3; i++)
                {
                  'tier': ['bronze', 'silver', 'gold'][i],
                  'threshold': thresholds[i],
                  'xp': [100, 250, 500][i],
                  'itemIds': i == 2 ? ['title.machine-a-180'] : [],
                  'label': labels?[i],
                  'unlockedAt': (tier != null && i < ['bronze', 'silver', 'gold'].indexOf(tier) + 1) ? '2026-08-12T20:00:00Z' : null,
                  'rarity': [41.0, 12.0, 0.4][i],
                },
            ],
      'rarity': rarity,
      'unlockedAt': null,
      'requires': null,
    };

final _snapshot = {
  'families': [
    {'id': 'scoring', 'name': {'fr': 'Scoring', 'en': 'Scoring'}},
    {'id': 'finishing', 'name': {'fr': 'Finition', 'en': 'Finishing'}},
  ],
  'achievements': [
    _ach('machine-a-180', tier: 'silver', value: 37, next: {'tier': 'gold', 'threshold': 100, 'ratio': 0.37}, rarity: 41),
    _ach('finir-au-bull', family: 'finishing', tier: 'bronze', value: 8, thresholds: [1, 10, 50], next: {'tier': 'silver', 'threshold': 10, 'ratio': 0.8}),
    _ach('checkout-170', family: 'finishing', unique: true, thresholds: [1], next: {'tier': 'unique', 'threshold': 1, 'ratio': 0}, rarity: 0.4),
    {'id': 'broken'}, // dropped: no badge
  ],
  'unlocked': 2,
  'total': 3,
  'closestId': 'finir-au-bull',
};

class _FakeProgression extends ProgressionProvider {
  final List<List<String>> equipped = [];
  @override
  Future<void> refreshSummary() async {}
  @override
  Future<void> refreshInventory() async {}
  @override
  Future<void> refreshContent() async {}
  @override
  Future<bool> equip(EquipRequest request) async {
    equipped.add((request.body['badges'] as List).cast<String>());
    return true;
  }
}

final _content = ProgressionContent.fromJson({
  'version': 'v1',
  'items': [
    for (final id in ['machine-a-180', 'finir-au-bull', 'checkout-170'])
      {
        'id': 'badge.$id',
        'type': 'badge',
        'name': {'fr': 'Nom $id', 'en': 'Name $id'},
        'source': {'kind': 'achievement', 'label': {'fr': 's', 'en': 'a'}},
        'render': {'kind': 'badge', 'glyph': '180'},
      },
    {
      'id': 'title.machine-a-180',
      'type': 'title',
      'name': {'fr': 'Machine à 180', 'en': '180 Machine'},
      'source': {'kind': 'achievement', 'label': {'fr': 's', 'en': 'a'}},
    },
  ],
});

Widget _app(Widget child, {ProgressionProvider? provider, Locale locale = const Locale('fr')}) {
  final p = provider ?? (_FakeProgression()..debugSeed(content: _content));
  return ChangeNotifierProvider<ProgressionProvider>.value(
    value: p,
    child: MaterialApp(
      locale: locale,
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
}

void main() {
  group('models', () {
    test('parse the collection defensively', () {
      final s = AchievementsSnapshot.fromJson(_snapshot);
      expect(s.achievements.map((a) => a.id), ['machine-a-180', 'finir-au-bull', 'checkout-170']);
      expect(s.unlocked, 2);
      expect(s.closest?.id, 'finir-au-bull');
      final ton = s.achievements.first;
      expect(ton.tier, 'silver');
      expect(ton.next?.threshold, 100);
      expect(ton.steps.map((x) => x.done), [true, true, false]);
      expect(ton.badge.tier, 'silver');
      final unique = s.achievements.last;
      expect(unique.unique, isTrue);
      expect(unique.badge.tier, isNull);
      expect(AchievementsSnapshot.fromJson('nope').achievements, isEmpty);
      expect(Achievement.fromJson({'id': 'x', 'badgeId': 'badge.x', 'tier': 'platinum'})?.tier, isNull);
    });

    test('parse unlocks with their context and next reward', () {
      final list = AchievementUnlock.listFromJson({
        'unlocks': [
          {
            'id': 'u1',
            'achievementId': 'finir-au-bull',
            'tier': 'silver',
            'retro': false,
            'xp': 250,
            'itemIds': [],
            'context': {'matchId': 'm1', 'value': 50},
            'name': {'fr': 'Finir au bull', 'en': 'Bull Finish'},
            'badgeId': 'badge.finir-au-bull',
            'threshold': 10,
            'rarity': 4,
            'next': {'tier': 'gold', 'threshold': 50, 'itemIds': ['background.dans-le-mille']},
            'userBadgeId': 'ub1',
          },
          {'id': 'u2', 'achievementId': 'x', 'tier': 'diamond', 'badgeId': 'badge.x'},
        ],
      });
      expect(list, hasLength(1));
      final u = list.first;
      expect(u.matchId, 'm1');
      expect(u.contextValue, 50);
      expect(u.next?.tier, 'gold');
      expect(u.nextItemIds, ['background.dans-le-mille']);
      expect(u.badge.id, 'ub1');
    });

    test('parse the detail and its last occurrences', () {
      final d = AchievementDetail.fromJson({
        ..._ach('machine-a-180', tier: 'silver', value: 37),
        'recent': [
          {'at': '2026-11-07T20:14:00Z', 'value': 180, 'matchId': 'm1', 'opponent': {'id': 'o', 'username': 'Mika_180'}, 'legNumber': 2, 'hasCloudReplay': true},
          'junk',
        ],
      });
      expect(d?.recent, hasLength(1));
      expect(d!.recent.first.opponentName, 'Mika_180');
      expect(d.recent.first.legNumber, 2);
    });
  });

  testWidgets('formats values the French way', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(_app(Builder(builder: (c) {
      ctx = c;
      return const SizedBox();
    })));
    await tester.pumpAndSettle(); // l10n loads asynchronously
    expect(formatAchievementValue(ctx, 52.43, 'decimal'), '52,4');
    expect(formatAchievementValue(ctx, 60, 'percent'), '60 %');
    expect(formatAchievementValue(ctx, 100000, 'int'), formatXp(100000)); // grouped like the XP
    expect(formatRarity(ctx, 0.42), '0,4');
    final s = AchievementsSnapshot.fromJson(_snapshot);
    // No-break spaces: the tile's two lines break between the value and
    // « pour l’Or », never inside either.
    expect(achievementTileNote(ctx, s.achievements[0]), '37\u00A0/\u00A0100 pour\u00A0l’Or');
    expect(achievementTileNote(ctx, s.achievements[2]), '0,4\u00A0% des joueurs');
    // A gold tier shows the gold rarity, not the bronze one.
    final gold = Achievement.fromJson(_ach('volees-140', tier: 'gold', value: 120, rarity: 41))!;
    expect(gold.tierRarity, 0.4);
    expect(achievementTileNote(ctx, gold), '0,4\u00A0% des joueurs');
    // Lower is better: my best, then the target (never « 16 / 15 »).
    final flash = Achievement.fromJson(_ach(
      'manche-eclair',
      tier: 'bronze',
      value: 16,
      aggregate: 'min',
      thresholds: [18, 15, 12],
      next: {'tier': 'silver', 'threshold': 15, 'ratio': 0.938},
    ))!;
    expect(achievementProgress(ctx, flash), '16 → 15');
    expect(achievementTileNote(ctx, flash), '16\u00A0→\u00A015');
  });

  testWidgets('the collection shows the count, the closest tier and filters by family', (tester) async {
    await tester.pumpWidget(_app(AchievementsScreen(load: () async => AchievementsSnapshot.fromJson(_snapshot))));
    await tester.pumpAndSettle();
    expect(find.text('Succès'), findsOneWidget);
    expect(find.text('2 / 3'), findsOneWidget);
    expect(find.text('Le plus proche'), findsOneWidget);
    expect(find.text('Nom finir-au-bull · palier Argent'), findsOneWidget);
    expect(find.byType(AchievementTile), findsNWidgets(3));
    expect(find.text('37\u00A0/\u00A0100 pour\u00A0l’Or'), findsOneWidget);
    expect(find.text('À débloquer'), findsOneWidget);

    await tester.tap(find.text('Scoring'));
    await tester.pumpAndSettle();
    expect(find.byType(AchievementTile), findsOneWidget);
    expect(find.text('Le plus proche'), findsNothing);
  });

  testWidgets('the detail lists the tiers and the last occurrences', (tester) async {
    final a = AchievementsSnapshot.fromJson(_snapshot).achievements.first;
    await tester.pumpWidget(_app(AchievementDetailScreen(
      achievement: a,
      load: (_) async => AchievementDetail.fromJson({
        ..._ach('machine-a-180', tier: 'silver', value: 37, next: {'tier': 'gold', 'threshold': 100, 'ratio': 0.37}),
        'recent': [
          {'at': '2026-11-07T20:14:00Z', 'value': 180, 'matchId': 'm1', 'opponent': {'id': 'o', 'username': 'Mika_180'}, 'legNumber': 2},
        ],
      }),
    )));
    await tester.pumpAndSettle();
    expect(find.text('Nom machine-a-180'), findsOneWidget);
    expect(find.text('37'), findsOneWidget);
    expect(find.text('Bronze'), findsOneWidget);
    expect(find.text('Argent'), findsOneWidget);
    expect(find.text('Or'), findsOneWidget);
    expect(find.text('41 % des joueurs'), findsOneWidget);
    expect(find.text('0,4 % des joueurs'), findsOneWidget);
    expect(find.textContaining('titre Machine à 180'), findsOneWidget);
    expect(find.text('Seules les fléchettes validées par l’IA sans correction comptent.'), findsOneWidget);
    expect(find.text('contre Mika_180 · manche 2'), findsOneWidget);
    // No clip of that match on the phone nor in the cloud: no replay button.
    expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);
  });

  testWidgets('the unlock sheet shows the tier, the XP, the next reward and the pin', (tester) async {
    final u = AchievementUnlock.fromJson({
      'id': 'u1',
      'achievementId': 'machine-a-180',
      'tier': 'silver',
      'xp': 250,
      'name': {'fr': 'Machine à 180', 'en': '180 Machine'},
      'badgeId': 'badge.machine-a-180',
      'threshold': 10,
      'rarity': 12,
      'next': {'tier': 'gold', 'threshold': 100, 'itemIds': ['title.machine-a-180']},
      'userBadgeId': 'ub1',
    })!;
    final p = _FakeProgression()..debugSeed(content: _content, summary: const ProgressionSummary());
    await tester.pumpWidget(_app(AchievementUnlockSheet(unlocks: [u]), provider: p));
    await tester.pump();
    expect(find.text('Succès débloqué'), findsOneWidget);
    expect(find.text('Machine à 180'), findsOneWidget);
    expect(find.text('Palier Argent · 10'), findsOneWidget);
    expect(find.text('12 % des joueurs l’ont'), findsOneWidget);
    expect(find.text('+250 XP'), findsOneWidget);
    expect(find.text('« Machine à 180 »'), findsOneWidget);
    expect(find.text('au palier Or (100)'), findsOneWidget);
    await tester.tap(find.text('Épingler sur mon profil'));
    await tester.pumpAndSettle();
    expect(p.equipped, [
      ['ub1'],
    ]);
  });

  testWidgets('a batch of retroactive unlocks is announced in one sheet', (tester) async {
    final list = [
      for (var i = 0; i < 4; i++)
        AchievementUnlock.fromJson({
          'id': 'r$i',
          'achievementId': 'a$i',
          'tier': 'bronze',
          'retro': true,
          'xp': 100,
          'name': {'fr': 'A$i', 'en': 'A$i'},
          'badgeId': 'badge.machine-a-180',
        })!,
    ];
    await tester.pumpWidget(_app(AchievementUnlockSheet(unlocks: list)));
    await tester.pump();
    expect(find.text('Tes succès sont arrivés'), findsOneWidget);
    expect(find.text('4 succès débloqués d’après tes matchs passés.'), findsOneWidget);
    expect(find.text('+400 XP'), findsOneWidget);
    expect(find.text('Voir tous les succès'), findsOneWidget);
  });

  testWidgets('the Badges tab pins and unpins up to 3 badges', (tester) async {
    final p = _FakeProgression()
      ..debugSeed(
        content: _content,
        inventory: Inventory.fromJson({
          'items': [],
          'badges': [
            {'id': 'ub1', 'badgeId': 'badge.machine-a-180', 'tier': 'silver'},
            {'id': 'ub2', 'badgeId': 'badge.finir-au-bull', 'tier': 'bronze'},
            {'id': 'ub3', 'badgeId': 'badge.unknown', 'tier': 'gold'},
          ],
          'equipment': {'badges': ['ub2']},
        }),
      );
    await tester.pumpWidget(_app(const BadgePicker(), provider: p));
    await tester.pump();
    expect(find.text('1 / 3 épinglés'), findsOneWidget);
    // The unknown badge is hidden, the pinned one comes first.
    expect(find.byType(InkWell), findsNWidgets(2));
    await tester.tap(find.byKey(const ValueKey('badge-pick-ub1')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('badge-pick-ub2')));
    await tester.pump();
    expect(p.equipped, [
      ['ub2', 'ub1'],
      [],
    ]);
  });

  testWidgets('the profile tile shows my count', (tester) async {
    await tester.pumpWidget(_app(AchievementsProfileTile(load: () async => const AchievementsSummary(unlocked: 18, total: 60))));
    await tester.pumpAndSettle();
    expect(find.text('Succès'), findsOneWidget);
    expect(find.text('18 / 60'), findsOneWidget);
  });
}
