// The locker, piste A « Deux rayons » (docs/progression/ecrans/CasA1, CasA2,
// CasObtenir, CONTRACT §14.11): « À toi » vs « À débloquer », the sheet of a
// locked item in its 7 cases, « Essayer sur ma carte », and the letters of a
// monogram avatar.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:mobile/l10n/app_localizations.dart';
import 'package:mobile/models/progression.dart';
import 'package:mobile/models/season.dart';
import 'package:mobile/providers/progression_provider.dart';
import 'package:mobile/screens/achievements/achievement_models.dart';
import 'package:mobile/screens/league/league_models.dart';
import 'package:mobile/screens/league/league_store.dart';
import 'package:mobile/screens/onboarding/onboarding_models.dart';
import 'package:mobile/screens/onboarding/onboarding_provider.dart';
import 'package:mobile/screens/progression/locker_letters_sheet.dart';
import 'package:mobile/screens/progression/locker_screen.dart';
import 'package:mobile/screens/progression/locker_unlock.dart';
import 'package:mobile/utils/app_theme.dart';
import 'package:mobile/widgets/progression/player_showcase_card.dart';

class _FakeProgression extends ProgressionProvider {
  final List<EquipRequest> equipped = [];
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
  @override
  Future<bool> equip(EquipRequest request) async {
    equipped.add(request);
    return true;
  }
}

Map<String, dynamic> _item(
  String id,
  String type,
  Map<String, dynamic> source,
  Map<String, dynamic> render, {
  String? name,
  bool premium = false,
}) => {
  'id': id,
  'type': type,
  'name': {'fr': name ?? id, 'en': name ?? id},
  'source': {
    ...source,
    'label': {'fr': 'label $id', 'en': 'label $id'},
  },
  'premium': premium,
  'render': render,
};

const _mono = {'kind': 'monogram', 'metal': 'acier', 'shape': 'round'};

Map<String, dynamic> _content({DateTime? eventStart, DateTime? eventEnd}) {
  final start = eventStart ?? DateTime.now().add(const Duration(days: 30));
  final end = eventEnd ?? start.add(const Duration(days: 24));
  return {
    'version': 'v1',
    'curve': {'base': 200, 'perLevel': 60, 'capLevel': 50},
    'items': [
      _item('avatar.monogramme-acier', 'avatar', {'kind': 'level', 'level': 2}, _mono, name: 'Monogramme Acier'),
      _item(
        'avatar.flechette',
        'avatar',
        {'kind': 'level', 'level': 8},
        {'kind': 'emblem', 'metal': 'acier', 'emblem': 'flechette'},
        name: 'Fléchette',
      ),
      _item(
        'avatar.guilloche',
        'avatar',
        {'kind': 'level', 'level': 22},
        {..._mono, 'metal': 'laiton', 'engraving': 'guilloche'},
        name: 'Guilloché',
      ),
      _item(
        'avatar.flechettes-croisees',
        'avatar',
        {'kind': 'level', 'level': 27},
        {'kind': 'emblem', 'metal': 'or', 'emblem': 'flechettes-croisees'},
        name: 'Fléchettes croisées',
      ),
      _item(
        'avatar.carbone',
        'avatar',
        {'kind': 'premium_level', 'level': 25},
        {..._mono, 'metal': 'tungstene', 'shape': 'hexagone'},
        name: 'Carbone',
        premium: true,
      ),
      _item(
        'avatar.cible',
        'avatar',
        {'kind': 'achievement', 'ref': 'bulls'},
        {'kind': 'emblem', 'metal': 'or', 'emblem': 'cible'},
        name: 'Cible',
      ),
      _item(
        'avatar.saison-1',
        'avatar',
        {'kind': 'season', 'ref': '1'},
        {..._mono, 'metal': 'platine', 'shape': 'ecusson'},
        name: 'Saison 1',
      ),
      _item(
        'background.or',
        'background',
        {'kind': 'league', 'ref': 'or'},
        {
          'kind': 'texture',
          'colors': ['#3A2E0B', '#EAB308'],
          'pattern': 'plain',
        },
        name: 'Or',
      ),
      _item(
        'background.hiver',
        'background',
        {'kind': 'event', 'ref': 'hiver-2026'},
        {
          'kind': 'texture',
          'colors': ['#0B1A2E', '#7DD3FC'],
          'pattern': 'dots',
        },
        name: 'Hiver',
      ),
      _item('frame.debutant', 'frame', {'kind': 'onboarding'}, {'kind': 'frame', 'metal': 'acier'}, name: 'Débutant'),
      _item('title.lanceur', 'title', {'kind': 'level', 'level': 27}, {}, name: 'Lanceur'),
      _item('title.machine-a-180', 'title', {'kind': 'achievement', 'ref': 'machine-a-180'}, {}, name: 'Machine à 180'),
      _item(
        'flight.damas',
        'flight',
        {'kind': 'premium_level', 'level': 40},
        {
          'kind': 'flight',
          'colors': ['#1E293B', '#94A3B8'],
          'pattern': 'metal',
          'metal': 'acier',
        },
        name: 'Damas',
        premium: true,
      ),
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
    'defs': {
      'achievement': [
        {
          'id': 'bulls',
          'family': 'scoring',
          'name': {'fr': 'Bulls', 'en': 'Bulls'},
          'description': {'fr': 'Touche le bull (25 ou 50) en match.', 'en': 'Hit the bull (25 or 50) in matches.'},
          'badgeId': 'badge.bulls',
          'tiers': [
            {'tier': 'bronze', 'threshold': 10, 'xp': 100, 'itemIds': []},
            {'tier': 'silver', 'threshold': 50, 'xp': 250, 'itemIds': []},
            {
              'tier': 'gold',
              'threshold': 100,
              'xp': 500,
              'itemIds': ['avatar.cible'],
            },
          ],
          'unique': null,
        },
      ],
      'league': [
        {
          'id': 'cuivre',
          'type': 'tier',
          'order': 2,
          'name': {'fr': 'Cuivre', 'en': 'Copper'},
        },
        {
          'id': 'or',
          'type': 'tier',
          'order': 3,
          'name': {'fr': 'Or', 'en': 'Gold'},
        },
      ],
    },
  };
}

const _curve = XpCurve(base: 200, perLevel: 60, capLevel: 50);

_FakeProgression _provider({
  int level = 23,
  bool premium = false,
  String? equippedAvatar = 'avatar.guilloche',
  List<String> owned = const ['avatar.monogramme-acier', 'avatar.flechette', 'avatar.guilloche'],
  Map<String, dynamic>? content,
}) {
  final equipment = Equipment(avatar: equippedAvatar);
  return _FakeProgression()..debugSeed(
    content: ProgressionContent.fromJson(content ?? _content()),
    summary: ProgressionSummary(
      level: level,
      xpTotal: _curve.xpForLevel(level) + 100,
      isPremium: premium,
      equipment: equipment,
      cosmetics: PublicCosmetics(level: level, avatar: equippedAvatar, monogram: 'DO'),
    ),
    inventory: Inventory(
      items: [
        for (final id in owned) InventoryItem.fromJson({'itemId': id, 'source': 'level', 'isNew': id == 'avatar.flechette'})!,
      ],
      equipment: equipment,
    ),
  );
}

Widget _app(ProgressionProvider p, {Widget home = const LockerScreen(), OnboardingProvider? onboarding}) {
  final app = MaterialApp(
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
  );
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ProgressionProvider>.value(value: p),
      if (onboarding != null) ChangeNotifierProvider<OnboardingProvider>.value(value: onboarding),
    ],
    child: app,
  );
}

Future<void> _open(WidgetTester tester, ProgressionProvider p, {OnboardingProvider? onboarding, String? tab}) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_app(p, onboarding: onboarding));
  await tester.pumpAndSettle();
  if (tab != null) {
    await tester.ensureVisible(find.text(tab));
    await tester.pumpAndSettle();
    await tester.tap(find.text(tab));
    await tester.pumpAndSettle();
  }
}

Future<void> _tapLocked(WidgetTester tester, String id) async {
  final tile = find.byKey(Key('locker-locked-$id'));
  await tester.ensureVisible(tile);
  await tester.pumpAndSettle();
  await tester.tap(tile);
  await tester.pumpAndSettle();
}

Finder _inSheet(Finder f) => find.descendant(of: find.byType(LockerUnlockSheet), matching: f);

LockerHow _how(WidgetTester tester) => tester.widget<LockerHowBox>(find.byType(LockerHowBox)).how;

bool _dashed(Widget w) => w is CustomPaint && w.foregroundPainter is LockerDashedBorderPainter;

void main() {
  tearDown(() {
    LockerUnlockSheet.debugAchievementLoader = null;
    LeagueStore.instance.debugLoader = null;
    LeagueStore.instance.reset();
  });

  group('grid', () {
    testWidgets('an item of mine and an item to unlock look different', (tester) async {
      await _open(tester, _provider());

      // « À toi 4 » (Ton rang + 3 avatars) and « À débloquer 4 ».
      expect(find.text('À toi'), findsOneWidget);
      expect(find.text('À débloquer'), findsOneWidget);
      expect(find.text('4'), findsNWidgets(2));

      // Mine: the name, no « niveau 2 », no dashed outline.
      final mine = find.byKey(const Key('locker-owned-avatar.monogramme-acier'));
      expect(find.descendant(of: mine, matching: find.text('Monogramme Acier')), findsOneWidget);
      expect(find.text('label avatar.monogramme-acier'), findsNothing);
      expect(find.descendant(of: mine, matching: find.byWidgetPredicate(_dashed)), findsNothing);

      // Locked: the condition instead of the name, a dashed outline, a lock.
      final locked = find.byKey(const Key('locker-locked-avatar.flechettes-croisees'));
      expect(find.descendant(of: locked, matching: find.text('Niv. 27')), findsOneWidget);
      expect(find.text('Fléchettes croisées'), findsNothing);
      expect(find.descendant(of: locked, matching: find.byWidgetPredicate(_dashed)), findsOneWidget);
      expect(find.descendant(of: locked, matching: find.byIcon(Icons.lock_outline_rounded)), findsOneWidget);
      expect(find.descendant(of: locked, matching: find.byType(ColorFiltered)), findsOneWidget);

      // The other short conditions; premium in gold with the crown.
      final premium = find.byKey(const Key('locker-locked-avatar.carbone'));
      expect(find.descendant(of: premium, matching: find.text('Premium')), findsOneWidget);
      expect(find.descendant(of: premium, matching: find.byType(PremiumCrown)), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('locker-locked-avatar.cible')), matching: find.text('Succès')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('locker-locked-avatar.saison-1')), matching: find.text('Saison 1')), findsOneWidget);

      // Equipped: one check, on Guilloché; the default is « Ton rang »; new = dot.
      expect(find.byKey(const Key('locker-equipped-check')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('locker-owned-avatar.guilloche')),
          matching: find.byKey(const Key('locker-equipped-check')),
        ),
        findsOneWidget,
      );
      expect(find.text('Ton rang'), findsOneWidget);

      // Gone: the count in the header, « Texte du monogramme », the hint.
      expect(find.textContaining('/'), findsNothing);
      expect(find.text('Texte du monogramme'), findsNothing);
      expect(find.textContaining('Touche un objet'), findsNothing);
      expect(find.byType(PlayerShowcaseCard), findsOneWidget);
      expect(find.text('Modifier'), findsNothing);
    });

    testWidgets('the other tabs follow the same rules (Fonds: league, event)', (tester) async {
      await _open(tester, _provider(), tab: 'Fonds');
      expect(find.text('Aucun'), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('locker-locked-background.or')), matching: find.text('Ligue')), findsOneWidget);
      expect(
        find.descendant(of: find.byKey(const Key('locker-locked-background.hiver')), matching: find.text('Événement')),
        findsOneWidget,
      );
      await tester.tap(find.text('Cadres'));
      await tester.pumpAndSettle();
      expect(find.descendant(of: find.byKey(const Key('locker-locked-frame.debutant')), matching: find.text('7 jours')), findsOneWidget);
    });

    testWidgets('a locked title shows its text and its condition, on a grey plate', (tester) async {
      await _open(tester, _provider(), tab: 'Titres');
      final lanceur = find.byKey(const Key('locker-locked-title.lanceur'));
      expect(find.descendant(of: lanceur, matching: find.text('Lanceur')), findsOneWidget);
      expect(find.descendant(of: lanceur, matching: find.text('Niv. 27')), findsOneWidget);
      expect(find.descendant(of: lanceur, matching: find.byKey(const Key('locker-title-plate'))), findsOneWidget);
      expect(find.descendant(of: lanceur, matching: find.byWidgetPredicate(_dashed)), findsOneWidget);
      expect(find.descendant(of: lanceur, matching: find.byIcon(Icons.lock_outline_rounded)), findsOneWidget);
      final machine = find.byKey(const Key('locker-locked-title.machine-a-180'));
      expect(find.descendant(of: machine, matching: find.text('Machine à 180')), findsOneWidget);
      expect(find.descendant(of: machine, matching: find.text('Succès')), findsOneWidget);
      // Other tabs keep the condition alone.
      await tester.ensureVisible(find.text('Avatars'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Avatars'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('locker-title-plate')), findsNothing);
      expect(find.text('Fléchettes croisées'), findsNothing);
    });

    testWidgets('tapping an item of mine equips it at once', (tester) async {
      final p = _provider();
      await _open(tester, p);
      await tester.tap(find.byKey(const Key('locker-owned-avatar.flechette')));
      await tester.pumpAndSettle();
      expect(p.equipped.single.body, {'avatar': 'avatar.flechette'});
      await tester.tap(find.byKey(const Key('locker-owned-default')));
      await tester.pumpAndSettle();
      expect(p.equipped.last.body, {'avatar': null});
    });
  });

  group('how to get it: the 7 cases', () {
    testWidgets('1 · level: sentence, where I stand, the bar, « Voir les niveaux »', (tester) async {
      await _open(tester, _provider());
      await _tapLocked(tester, 'avatar.flechettes-croisees');
      expect(_inSheet(find.text('Fléchettes croisées')), findsOneWidget);
      expect(_inSheet(find.text('Avatar à débloquer')), findsOneWidget);
      expect(_inSheet(find.text('Atteins le niveau 27')), findsOneWidget);
      expect(_inSheet(find.text('Tu es niveau 23 · encore 4 niveaux')), findsOneWidget);
      expect(_inSheet(find.text('Niv. 23')), findsOneWidget);
      expect(_inSheet(find.text('Niv. 27')), findsOneWidget);
      expect(_inSheet(find.text('Voir les niveaux')), findsOneWidget);
      expect(_inSheet(find.text('Essayer sur ma carte')), findsOneWidget);
      // The visual is in colour in the sheet.
      expect(_inSheet(find.byType(ColorFiltered)), findsNothing);
      // From the start of level 23 to level 27.
      final expected = 100 / (_curve.xpForLevel(27) - _curve.xpForLevel(23));
      expect(_how(tester).progress, closeTo(expected, 1e-9));
    });

    testWidgets('2 · premium: « Passer Premium » without it, now if the level is reached, the level case with it', (tester) async {
      await _open(tester, _provider());
      await _tapLocked(tester, 'avatar.carbone');
      expect(_inSheet(find.text('Premium, au niveau 25')), findsOneWidget);
      expect(_inSheet(find.text('Tu es niveau 23 · sans Premium')), findsOneWidget);
      expect(_inSheet(find.text('Passer Premium')), findsOneWidget);
      expect(_how(tester).goldAction, isTrue);
      expect(_how(tester).progress, isNull);

      await tester.pumpWidget(const SizedBox());
      await _open(tester, _provider(level: 30));
      await _tapLocked(tester, 'avatar.carbone');
      expect(_inSheet(find.text('Passe Premium : il est à toi tout de suite')), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await _open(tester, _provider(premium: true));
      await _tapLocked(tester, 'avatar.carbone');
      expect(_inSheet(find.text('Atteins le niveau 25')), findsOneWidget);
      expect(_how(tester).progress, closeTo(100 / (_curve.xpForLevel(25) - _curve.xpForLevel(23)), 1e-9));
      expect(_inSheet(find.text('Voir les niveaux')), findsOneWidget);
      expect(_inSheet(find.text('Passer Premium')), findsNothing);
    });

    testWidgets('3 · achievement: the tier that gives it, my counter, « Voir le succès »', (tester) async {
      LockerUnlockSheet.debugAchievementLoader = (id) async => Achievement(
        id: id,
        family: 'scoring',
        name: const LocalizedText(fr: 'Bulls', en: 'Bulls'),
        badgeId: 'badge.bulls',
        value: 64,
        tier: 'silver',
        steps: const [
          AchievementStep(tier: 'bronze', threshold: 10),
          AchievementStep(tier: 'silver', threshold: 50),
          AchievementStep(tier: 'gold', threshold: 100, itemIds: ['avatar.cible']),
        ],
      );
      await _open(tester, _provider());
      await _tapLocked(tester, 'avatar.cible');
      expect(_inSheet(find.text('Bulls, palier Or')), findsOneWidget);
      expect(_inSheet(find.text('Touche le bull (25 ou 50) en match.')), findsOneWidget);
      expect(_inSheet(find.text('64')), findsOneWidget);
      expect(_inSheet(find.text('100')), findsOneWidget);
      expect(_inSheet(find.text('Voir le succès')), findsOneWidget);
      expect(_how(tester).progress, closeTo(0.64, 1e-9));
    });

    testWidgets('3 · achievement offline: the sentence without the bar, no error', (tester) async {
      LockerUnlockSheet.debugAchievementLoader = (id) async => throw Exception('offline');
      await _open(tester, _provider());
      await _tapLocked(tester, 'avatar.cible');
      expect(_inSheet(find.text('Bulls, palier Or')), findsOneWidget);
      expect(_how(tester).progress, isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('4 · league: the league to reach, mine, « Voir ma ligue »', (tester) async {
      const snapshot = LeagueSnapshot(
        league: LeagueTier(
          id: 'cuivre',
          order: 2,
          name: LocalizedText(fr: 'Cuivre', en: 'Copper'),
        ),
      );
      LeagueStore.instance.debugSeed(snapshot);
      LeagueStore.instance.debugLoader = () async => snapshot;
      await _open(tester, _provider(), tab: 'Fonds');
      await _tapLocked(tester, 'background.or');
      expect(_inSheet(find.text('Fond à débloquer')), findsOneWidget);
      expect(_inSheet(find.text('Atteins la ligue Or')), findsOneWidget);
      expect(_inSheet(find.text('Tu es en ligue Cuivre')), findsOneWidget);
      expect(_inSheet(find.text('Voir ma ligue')), findsOneWidget);
    });

    testWidgets('5 · season: given at the end of the season, no button', (tester) async {
      await _open(tester, _provider());
      await _tapLocked(tester, 'avatar.saison-1');
      expect(_inSheet(find.text('Joue en classé pendant la saison 1')), findsOneWidget);
      expect(_inSheet(find.text('Donné à la fin de la saison')), findsOneWidget);
      expect(_how(tester).action, isNull);
    });

    testWidgets('6 · event: dates, « Pas encore commencé » before it', (tester) async {
      await _open(
        tester,
        _provider(
          content: _content(eventStart: DateTime(2030, 12, 11), eventEnd: DateTime(2031, 1, 4)),
        ),
        tab: 'Fonds',
      );
      await _tapLocked(tester, 'background.hiver');
      expect(_inSheet(find.text('Quête de l’événement de décembre')), findsOneWidget);
      expect(_inSheet(find.text('Du 11 déc. au 3 janv.')), findsOneWidget);
      expect(_inSheet(find.text('Pas encore commencé')), findsOneWidget);
      expect(_inSheet(find.text('Voir la quête')), findsNothing);
    });

    testWidgets('6 · event running: « Voir la quête »', (tester) async {
      final now = DateTime.now();
      await _open(
        tester,
        _provider(
          content: _content(eventStart: now.subtract(const Duration(days: 2)), eventEnd: now.add(const Duration(days: 9))),
        ),
        tab: 'Fonds',
      );
      await _tapLocked(tester, 'background.hiver');
      expect(_inSheet(find.text('Voir la quête')), findsOneWidget);
      expect(_how(tester).note, isNull);
    });

    testWidgets('7 · first 7 days: « Jour 3/7 » and the journey while it runs', (tester) async {
      final onboarding = OnboardingProvider()..debugSeed(const OnboardingStatus(active: true, status: 'active', day: 3));
      await _open(tester, _provider(), onboarding: onboarding, tab: 'Cadres');
      await _tapLocked(tester, 'frame.debutant');
      expect(_inSheet(find.text('Cadre à débloquer')), findsOneWidget);
      expect(_inSheet(find.text('Tes 7 premiers jours')), findsOneWidget);
      expect(_inSheet(find.text('Jour 3/7')), findsOneWidget);
      expect(_inSheet(find.text('Voir mon parcours')), findsOneWidget);
    });

    testWidgets('7 · first 7 days, an older account: reserved to new accounts', (tester) async {
      final onboarding = OnboardingProvider()..debugSeed(const OnboardingStatus(status: 'none'));
      await _open(tester, _provider(), onboarding: onboarding, tab: 'Cadres');
      await _tapLocked(tester, 'frame.debutant');
      expect(_inSheet(find.text('Réservé aux nouveaux comptes')), findsOneWidget);
      expect(_inSheet(find.text('Voir mon parcours')), findsNothing);
    });

    testWidgets('a flight never shows on the card: no « Essayer sur ma carte »', (tester) async {
      await _open(tester, _provider(), tab: 'Flights');
      await _tapLocked(tester, 'flight.damas');
      expect(_inSheet(find.text('Flight à débloquer')), findsOneWidget);
      expect(_inSheet(find.text('Essayer sur ma carte')), findsNothing);
    });
  });

  group('how to get it: the variants', () {
    late BuildContext ctx;
    final content = ProgressionContent.fromJson(_content());
    ItemDef item(String id) => content.item(id)!;

    Future<void> withContext(WidgetTester tester) async {
      await tester.pumpWidget(
        _app(
          _provider(),
          home: Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('season: its end date while it runs, « Plus disponible » once over', (tester) async {
      await withContext(tester);
      final running = Season(id: 's1', number: 1, status: SeasonStatus.active, endAt: DateTime(2026, 11, 30, 20), hasReward: true);
      var how = resolveLockerHow(ctx, item('avatar.saison-1'), LockerHowData(season: running, currentSeasonNumber: 1));
      expect(how.subtitle, 'Donné à la fin de la saison · 30 nov.');
      how = resolveLockerHow(
        ctx,
        item('avatar.saison-1'),
        LockerHowData(
          season: const Season(id: 's1', number: 1, status: SeasonStatus.closed, hasReward: true),
        ),
      );
      expect(how.subtitle, 'Plus disponible');
      how = resolveLockerHow(ctx, item('avatar.saison-1'), LockerHowData(currentSeasonNumber: 2));
      expect(how.subtitle, 'Plus disponible');
    });

    testWidgets('event over: « Terminé »; level reached but not mine: no « encore »', (tester) async {
      await withContext(tester);
      final ev = lockerEvent(
        ProgressionContent.fromJson(_content(eventStart: DateTime(2020, 12, 11), eventEnd: DateTime(2021, 1, 4))),
        'hiver-2026',
      );
      var how = resolveLockerHow(ctx, item('background.hiver'), LockerHowData(event: ev));
      expect(how.note, 'Terminé');
      expect(how.action, isNull);
      how = resolveLockerHow(ctx, item('avatar.flechettes-croisees'), LockerHowData(level: 30, xpTotal: 999999, curve: _curve));
      expect(how.subtitle, 'Tu es niveau 30');
      expect(how.progress, 1.0);
      // Half way through level 23, aiming at 27: about 12 %, not 75 %.
      final half = _curve.xpForLevel(23) + _curve.xpToNext(23) ~/ 2;
      how = resolveLockerHow(ctx, item('avatar.flechettes-croisees'), LockerHowData(level: 23, xpTotal: half, curve: _curve));
      expect(how.progress, closeTo(0.12, 0.01));
    });

    testWidgets('missing data: the sentence alone, never an error', (tester) async {
      await withContext(tester);
      final data = LockerHowData();
      expect(resolveLockerHow(ctx, item('avatar.flechettes-croisees'), data).subtitle, isNull);
      expect(resolveLockerHow(ctx, item('avatar.flechettes-croisees'), data).progress, isNull);
      expect(resolveLockerHow(ctx, item('background.or'), data).title, 'Label background.or');
      expect(resolveLockerHow(ctx, item('background.hiver'), data).title, 'Label background.hiver');
      expect(resolveLockerHow(ctx, item('avatar.cible'), data).title, 'Label avatar.cible');
      expect(resolveLockerHow(ctx, item('frame.debutant'), data).subtitle, isNull);
      final unknown = ItemDef.fromJson(_item('title.x', 'title', {'kind': 'referral'}, {}))!;
      final how = resolveLockerHow(ctx, unknown, data);
      expect(how.title, 'Label title.x');
      expect(how.action, isNull);
    });

    test('the tier of an achievement is found in the content, or from the item source', () {
      final r = LockerAchievementReward.find(content, item('avatar.cible'))!;
      expect((r.id, r.tier, r.threshold), ('bulls', 'gold', 100));
      expect(r.asAchievement.steps.map((s) => s.tier), ['bronze', 'silver', 'gold']);
      expect(LockerAchievementReward.find(null, item('avatar.cible')), isNull);
    });
  });

  group('try it on my card', () {
    testWidgets('shows the locked item on the card with « Aperçu »; the tag cancels, nothing is sent', (tester) async {
      final p = _provider();
      await _open(tester, p);
      PublicCosmetics? card() => tester.widget<PlayerShowcaseCard>(find.byType(PlayerShowcaseCard)).cosmetics;
      expect(card()?.avatar, 'avatar.guilloche');

      await _tapLocked(tester, 'avatar.flechettes-croisees');
      await tester.tap(find.text('Essayer sur ma carte'));
      await tester.pumpAndSettle();
      expect(find.byType(LockerUnlockSheet), findsNothing);
      expect(card()?.avatar, 'avatar.flechettes-croisees');
      expect(find.text('Aperçu'), findsOneWidget);

      await tester.tap(find.byKey(const Key('locker-preview-tag')));
      await tester.pumpAndSettle();
      expect(card()?.avatar, 'avatar.guilloche');
      expect(find.text('Aperçu'), findsNothing);
      expect(p.equipped, isEmpty);
    });

    testWidgets('touching another item cancels the preview too', (tester) async {
      final p = _provider();
      await _open(tester, p, tab: 'Fonds');
      await _tapLocked(tester, 'background.or');
      await tester.tap(find.text('Essayer sur ma carte'));
      await tester.pumpAndSettle();
      expect(tester.widget<PlayerShowcaseCard>(find.byType(PlayerShowcaseCard)).cosmetics?.background, 'background.or');
      await tester.tap(find.byKey(const Key('locker-owned-default')));
      await tester.pumpAndSettle();
      expect(find.text('Aperçu'), findsNothing);
      expect(tester.widget<PlayerShowcaseCard>(find.byType(PlayerShowcaseCard)).cosmetics?.background, isNull);
      expect(p.equipped, isEmpty); // « Aucun » was already equipped.
    });
  });

  group('the letters of my avatar', () {
    testWidgets('the pencil sits only on the equipped monogram avatar', (tester) async {
      await _open(tester, _provider());
      final pencil = find.byKey(const Key('locker-letters-pencil'));
      expect(pencil, findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('locker-owned-avatar.guilloche')), matching: pencil), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await _open(tester, _provider(equippedAvatar: 'avatar.flechette'));
      expect(find.byKey(const Key('locker-letters-pencil')), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await _open(tester, _provider(equippedAvatar: null));
      expect(find.byKey(const Key('locker-letters-pencil')), findsNothing);
    });

    testWidgets('the sheet: three choices with a preview, saved as the server expects', (tester) async {
      final p = _provider();
      await _open(tester, p);
      await tester.tap(find.byKey(const Key('locker-owned-avatar.guilloche')));
      await tester.pumpAndSettle();
      expect(find.text('Les lettres de ton avatar'), findsOneWidget);
      expect(find.text('Tes initiales'), findsOneWidget);
      expect(find.text('Ton double'), findsOneWidget);
      expect(find.text('Au choix'), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('letters-auto')), matching: find.text('DO')), findsOneWidget);

      await tester.tap(find.byKey(const Key('letters-double')));
      await tester.pumpAndSettle();
      expect(find.text('BULL'), findsOneWidget);
      expect(find.text('T20'), findsOneWidget);
      await tester.tap(find.text('D20'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      expect(p.equipped.single.body, {
        'monogram': {'kind': 'double', 'value': 'D20'},
      });

      await tester.tap(find.byKey(const Key('locker-owned-avatar.guilloche')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('letters-custom')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'ab');
      await tester.pumpAndSettle();
      expect(find.descendant(of: find.byKey(const Key('letters-custom')), matching: find.text('AB')), findsOneWidget);
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      expect(p.equipped.last.body, {
        'monogram': {'kind': 'initials', 'value': 'AB'},
      });

      await tester.tap(find.byKey(const Key('locker-owned-avatar.guilloche')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('letters-auto')));
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      expect(p.equipped.last.body, {'monogram': null});
    });

    test('automatic initials match the server', () {
      expect(lockerAutoInitials('Kev_D20'), 'KD');
      expect(lockerAutoInitials('LaFleche'), 'LF');
      expect(lockerAutoInitials('Dodo180'), 'DO');
      expect(lockerAutoInitials('180'), '18');
      expect(lockerAutoInitials('Éric_Dupont'), 'ED');
      expect(lockerAutoInitials('__'), '?');
    });

    test('only what the server accepts is offered', () {
      final re = RegExp(r'^(?:[DT](?:[1-9]|1[0-9]|20)|BULL)$');
      expect(lockerDoubles.every(re.hasMatch), isTrue);
    });
  });
}
