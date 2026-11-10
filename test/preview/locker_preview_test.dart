// Renders the locker, piste A (mockups docs/progression/ecrans/CasA1, CasA2,
// CasObtenir) to PNG so it can be compared with the mockups without a device:
// the Avatars tab (390 × 844 with an iPhone's insets), the sheet of a locked
// item, « Essayer sur ma carte », the letters sheet, and the 7 cases of
// « Comment l'obtenir ».
// Not a test of behaviour — skipped unless run explicitly:
//
//   flutter test test/preview/locker_preview_test.dart \
//     --dart-define=PREVIEW=true \
//     --dart-define=PREVIEW_OUT=/abs/dir
//
// The real content (backend/src/progression/content) and the real item
// assets (backend/public/progression/items) are loaded.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:mobile/l10n/app_localizations.dart';
import 'package:mobile/models/progression.dart';
import 'package:mobile/models/season.dart';
import 'package:mobile/providers/auth_provider.dart';
import 'package:mobile/providers/progression_provider.dart';
import 'package:mobile/screens/achievements/achievement_models.dart';
import 'package:mobile/screens/onboarding/onboarding_models.dart';
import 'package:mobile/screens/progression/locker_screen.dart';
import 'package:mobile/screens/progression/locker_unlock.dart';
import 'package:mobile/services/progression_service.dart';
import 'package:mobile/utils/app_theme.dart';

const _enabled = bool.fromEnvironment('PREVIEW');
const _outDir = String.fromEnvironment('PREVIEW_OUT');

final _backend = '${Directory.current.parent.path}/backend';

Future<void> _loadFonts() async {
  final fonts = Directory('${Directory.current.path}/assets/fonts');
  final loader = FontLoader(AppTheme.fontFamily);
  final files = fonts.listSync().whereType<File>().where((f) => f.path.endsWith('.ttf')).toList()..sort((a, b) => a.path.compareTo(b.path));
  for (final f in files) {
    final bytes = await f.readAsBytes();
    loader.addFont(Future.value(ByteData.view(bytes.buffer)));
  }
  await loader.load();
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? File(Platform.resolvedExecutable).parent.parent.parent.path;
  final icons = File('$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (icons.existsSync()) {
    final l = FontLoader('MaterialIcons');
    final bytes = await icons.readAsBytes();
    l.addFont(Future.value(ByteData.view(bytes.buffer)));
    await l.load();
  }
}

Map<String, dynamic> _read(String file) =>
    jsonDecode(File('$_backend/src/progression/content/$file').readAsStringSync()) as Map<String, dynamic>;

/// The served content, with each item's asset copied where
/// ProgressionAssetCache looks for it.
Map<String, dynamic> _content(Directory cache) {
  final assets = Directory('$_backend/public/progression/items');
  final items = [..._read('items.json')['items'] as List, ..._read('badges.json')['items'] as List].cast<Map<String, dynamic>>();
  Directory('${cache.path}/progression/assets').createSync(recursive: true);
  for (final item in items) {
    for (final ext in const ['svg', 'webp', 'png']) {
      final f = File('${assets.path}/${item['id']}.$ext');
      if (!f.existsSync()) continue;
      f.copySync('${cache.path}/progression/assets/${item['id']}.preview.$ext');
      item['asset'] = {'url': '/progression/items/${item['id']}.$ext', 'format': ext, 'hash': 'preview'};
      break;
    }
  }
  final levels = _read('levels.json');
  return {
    'version': 'preview',
    'curve': levels['curve'],
    'prestige': levels['prestige'],
    'metals': _read('metals.json')['metals'],
    'items': items,
    'levels': levels['levels'],
    'events': _read('events.json')['events'],
    'defs': {'achievement': _read('defs/achievements.json')['items'], 'league': _read('defs/league.json')['items']},
  };
}

// CasA1's data: Dodo180, level 23, laiton / liège / Big Fish, Guilloché (DO).
const _owned = [
  'avatar.monogramme-acier',
  'avatar.flechette',
  'avatar.ecusson-cuivre',
  'avatar.flight',
  'avatar.guilloche',
  'avatar.170',
  'frame.laiton',
  'background.liege',
  'title.big-fish',
];

const _cosmetics = PublicCosmetics(
  level: 23,
  avatar: 'avatar.guilloche',
  monogram: 'DO',
  frame: 'frame.laiton',
  background: 'background.liege',
  title: 'title.big-fish',
  badges: [
    PublicBadge(id: 'b1', badgeId: 'badge.daily-first', tier: 'gold', date: '2026-11-08'),
    PublicBadge(id: 'b2', badgeId: 'badge.machine-a-180', tier: 'gold'),
    PublicBadge(id: 'b3', badgeId: 'badge.grosse-moyenne', tier: 'silver'),
  ],
);

class _Quiet extends ProgressionProvider {
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
}

/// [key] wraps the whole navigator, so a bottom sheet is in the picture too.
Widget _app(Widget child, ProgressionProvider p, AuthProvider auth, GlobalKey key) => MultiProvider(
  providers: [
    ChangeNotifierProvider<ProgressionProvider>.value(value: p),
    ChangeNotifierProvider<AuthProvider>.value(value: auth),
  ],
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    builder: (context, navigator) => RepaintBoundary(key: key, child: navigator),
    theme: AppTheme.themeData,
    locale: const Locale('fr'),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: child,
  ),
);

Future<void> _settle(WidgetTester tester) async {
  // Localizations, asset images and SVG pictures resolve asynchronously.
  await tester.runAsync(() async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
  });
  await tester.pump();
}

Future<void> _write(WidgetTester tester, GlobalKey key, String file, {double ratio = 3}) async {
  final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: ratio);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final out = File('$_outDir/$file');
    await out.writeAsBytes(bytes!.buffer.asUint8List());
    debugPrint('wrote ${out.path}');
  });
}

/// The 7 cases of CasObtenir, as the sheet resolves them.
class _Cases extends StatelessWidget {
  const _Cases();

  @override
  Widget build(BuildContext context) {
    final content = context.watch<ProgressionProvider>().content!;
    ItemDef item(String id) => content.item(id)!;
    final now = DateTime(2026, 11, 9, 10, 17);
    const curve = XpCurve(base: 200, perLevel: 60, capLevel: 50);
    final xp = curve.xpForLevel(23) + (curve.xpToNext(23) * 0.51).round();
    final bulls = LockerAchievementReward.find(content, item('avatar.cible'));
    final cases = <(String, ItemDef, LockerHowData)>[
      ('Niveau', item('avatar.flechettes-croisees'), LockerHowData(level: 23, xpTotal: xp, curve: curve, now: now)),
      (
        'Succès',
        item('avatar.cible'),
        LockerHowData(
          reward: bulls,
          achievement: Achievement(
            id: 'bulls',
            family: 'scoring',
            name: const LocalizedText(fr: 'Bulls', en: 'Bulls'),
            badgeId: 'badge.bulls',
            value: 64,
            tier: 'silver',
            steps: const [
              AchievementStep(tier: 'gold', threshold: 100, itemIds: ['avatar.cible']),
            ],
          ),
          now: now,
        ),
      ),
      ('Premium', item('avatar.carbone'), LockerHowData(level: 23, xpTotal: xp, curve: curve, now: now)),
      (
        'Ligue',
        item('background.or'),
        LockerHowData(
          leagueNames: lockerLeagueNames(content),
          currentLeague: const LocalizedText(fr: 'Cuivre', en: 'Copper'),
          now: now,
        ),
      ),
      (
        'Saison',
        item('avatar.saison-1'),
        LockerHowData(
          season: Season(id: 's1', number: 1, status: SeasonStatus.active, endAt: DateTime(2026, 11, 30, 20), hasReward: true),
          currentSeasonNumber: 1,
          now: now,
        ),
      ),
      ('Événement', item('background.hiver'), LockerHowData(event: lockerEvent(content, 'hiver-2026'), now: now)),
      (
        '7 premiers jours',
        item('frame.debutant'),
        LockerHowData(
          onboarding: const OnboardingStatus(status: 'none'),
          now: now,
        ),
      ),
    ];
    return Material(
      color: AppTheme.background,
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: GridView.count(
          crossAxisCount: 4,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio: 0.98,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (final (label, it, data) in cases)
              Builder(
                builder: (context) {
                  final how = resolveLockerHow(context, it, data);
                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(20)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          label.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 10),
                        LockerHowBox(how: how),
                        if (how.action != null) ...[
                          const SizedBox(height: 12),
                          LockerSheetButton(label: how.actionLabel ?? '', gold: how.goldAction, onTap: () {}),
                        ],
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

void main() {
  late ProgressionProvider provider;
  late AuthProvider auth;

  setUpAll(() async {
    final cache = Directory.systemTemp.createTempSync('locker-preview-');
    ProgressionAssetCache.debugDirectory = cache;
    final content = ProgressionContent.fromJson(_content(cache));
    const equipment = Equipment(avatar: 'avatar.guilloche', frame: 'frame.laiton', background: 'background.liege', title: 'title.big-fish');
    provider = _Quiet()
      ..debugSeed(
        content: content,
        summary: ProgressionSummary(
          level: 23,
          xpTotal: content.curve.xpForLevel(23) + (content.curve.xpToNext(23) * 0.51).round(),
          isPremium: true,
          equipment: equipment,
          cosmetics: _cosmetics,
        ),
        inventory: Inventory(
          items: [
            for (final id in _owned) InventoryItem.fromJson({'itemId': id, 'source': 'level'})!,
          ],
          equipment: equipment,
        ),
      );
    auth = AuthProvider()..updateUserFromJson({'id': 'u-me', 'username': 'Dodo180', 'rank': 'gold', 'elo': 1409});
  });

  testWidgets('locker previews', (tester) async {
    await tester.runAsync(_loadFonts);
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    tester.view.padding = const FakeViewPadding(top: 47 * 3, bottom: 34 * 3);
    final key = GlobalKey();
    await tester.pumpWidget(_app(const LockerScreen(), provider, auth, key));
    await _settle(tester);
    await _write(tester, key, 'casier_grille.png');

    // CasA2: the sheet of Fléchettes croisées (level 27).
    await tester.tap(find.byKey(const Key('locker-locked-avatar.flechettes-croisees')));
    await _settle(tester);
    await _write(tester, key, 'casier_fiche.png');

    await tester.tap(find.text('Essayer sur ma carte'));
    await _settle(tester);
    await _write(tester, key, 'casier_apercu.png');

    await tester.tap(find.byKey(const Key('locker-preview-tag')));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('locker-owned-avatar.guilloche')));
    await _settle(tester);
    await _write(tester, key, 'casier_lettres.png');
    Navigator.of(tester.element(find.text('Les lettres de ton avatar'))).pop();
    await _settle(tester);

    // The same two shelves on the other tabs.
    for (final (tab, file) in const [('Cadres', 'casier_cadres.png'), ('Fonds', 'casier_fonds.png'), ('Titres', 'casier_titres.png')]) {
      await tester.tap(find.text(tab));
      await _settle(tester);
      await _write(tester, key, file);
    }
    await tester.pumpWidget(const SizedBox());

    tester.view.physicalSize = const Size(1320 * 2, 720 * 2);
    tester.view.devicePixelRatio = 2;
    tester.view.padding = FakeViewPadding.zero;
    final key2 = GlobalKey();
    await tester.pumpWidget(_app(const _Cases(), provider, auth, key2));
    await _settle(tester);
    await _write(tester, key2, 'casier_7_cas.png', ratio: 2);
    tester.view.reset();
    expect(tester.takeException(), isNull);
  }, skip: !_enabled);
}
