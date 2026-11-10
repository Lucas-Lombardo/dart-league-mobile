// Renders the levels path by tiers of ten (piste C, mockup docs/progression/
// ecrans/R5C) and the quest journal in tabs (piste A, R6A) to PNG, so they
// can be compared with the mockups without a device: what the phone shows at
// opening (390 × 844 with an iPhone's insets), then the other states — a
// tier unfolded, a free player, past level 50, the quests done unfolded, the
// week and event tabs, the change of a quest.
// Not a test of behaviour — skipped unless run explicitly:
//
//   flutter test test/preview/parcours_progression_preview_test.dart \
//     --dart-define=PREVIEW=true
//
// (--dart-define=PREVIEW_OUT=/abs/dir to write elsewhere than
// docs/progression/captures/parcours_progression.) The real content
// (backend/src/progression/content) and item assets
// (backend/public/progression/items) are loaded.
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
import 'package:mobile/providers/progression_provider.dart';
import 'package:mobile/screens/progression/levels_path_screen.dart';
import 'package:mobile/screens/progression/progression_screen.dart';
import 'package:mobile/services/progression_service.dart';
import 'package:mobile/utils/app_theme.dart';

const _enabled = bool.fromEnvironment('PREVIEW');
const _outArg = String.fromEnvironment('PREVIEW_OUT');

final _root = Directory.current.parent.path;
final _backend = '$_root/backend';
final _outDir = _outArg.isNotEmpty ? _outArg : '$_root/docs/progression/captures/parcours_progression';

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
  };
}

class _Quiet extends ProgressionProvider {
  @override
  Future<void> refreshSummary() async {}
  @override
  Future<void> refreshQuests() async {}
  @override
  Future<void> refreshContent() async {}
  @override
  Future<bool> reroll(String userQuestId) async => true;
}

late ProgressionContent _catalog;

/// The mockups' player: level [level] at 51 %, the monogram « T20 ».
ProgressionSummary _summary(int level, {bool premium = true}) {
  final into = (_catalog.curve.xpToNext(level) * 0.51).round();
  return ProgressionSummary(
    level: level,
    xpTotal: _catalog.curve.xpForLevel(level) + into,
    xpIntoLevel: into,
    xpToNext: _catalog.curve.xpToNext(level),
    levelSeen: level,
    isPremium: premium,
    cosmetics: PublicCosmetics(level: level, monogram: 'T20'),
  );
}

/// R6A's quests (svg/gen_revue56.py `DAY`, `WEEK`, `DISC`), and the winter
/// event's when [event].
QuestsSnapshot _quests({bool event = false}) {
  final now = DateTime.now();
  final midnight = DateTime(now.year, now.month, now.day + 1);
  Map<String, dynamic> q(String id, String period, String fr, int progress, int threshold, int xp) => {
        'id': id,
        'questId': id,
        'period': period,
        'text': {'fr': fr, 'en': fr},
        'progress': progress,
        'threshold': threshold,
        'xp': xp,
        'status': progress >= threshold ? 'completed' : 'active',
      };
  return QuestsSnapshot.fromJson({
    'daily': {
      // « Nouvelles quêtes dans 6 h », as in the mockup.
      'endsAt': now.add(const Duration(hours: 6, minutes: 30)).toUtc().toIso8601String(),
      'rerollAvailable': true,
      'quests': [
        q('d1', 'daily', 'Marque une volée à 100+', 1, 1, 40),
        q('d2', 'daily', '5 triples dans une partie', 3, 5, 40),
        q('d3', 'daily', 'Joue le défi du jour', 0, 1, 40),
      ],
    },
    'weekly': {
      'endsAt': midnight.add(const Duration(days: 6)).toUtc().toIso8601String(),
      'quests': [
        q('w1', 'weekly', 'Termine 10 séries classées', 3, 10, 250),
        q('w2', 'weekly', 'Joue 5 jours différents', 1, 5, 200),
        q('w3', 'weekly', 'Bats un joueur mieux classé que toi', 1, 1, 250),
      ],
    },
    'discovery': {
      'quests': [
        q('x1', 'discovery', 'Joue une partie de Cricket', 0, 1, 100),
        q('x2', 'discovery', 'Regarde un match en spectateur', 0, 1, 50),
        q('x3', 'discovery', 'Fais un exercice de chaque famille (horloge, scoring, finitions, doubles)', 3, 4, 100),
        q('x4', 'discovery', 'Règle ta caméra', 1, 1, 50),
        q('x5', 'discovery', 'Termine ton placement', 1, 1, 150),
        q('x6', 'discovery', 'Ajoute un ami', 1, 1, 50),
      ],
    },
    if (event)
      'events': [
        {
          'eventId': 'hiver-2026',
          'name': {'fr': 'Hiver', 'en': 'Winter'},
          'endsAt': '2027-01-04T00:00:00+01:00',
          'quests': [
            q('e1', 'event', 'Gagne 5 séries classées pendant l’hiver', 2, 5, 150),
            q('e2', 'event', 'Joue 7 jours différents pendant l’hiver', 7, 7, 150),
          ],
        },
      ],
  });
}

_Quiet _provider(int level, {bool premium = true, bool event = false}) =>
    _Quiet()..debugSeed(content: _catalog, summary: _summary(level, premium: premium), quests: _quests(event: event));

Widget _app(Widget child, ProgressionProvider p, GlobalKey key) => ChangeNotifierProvider<ProgressionProvider>.value(
      value: p,
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

Future<void> _write(WidgetTester tester, GlobalKey key, String file) async {
  final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 3);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final out = File('$_outDir/$file');
    await out.writeAsBytes(bytes!.buffer.asUint8List());
    debugPrint('wrote ${out.path} (${image.width} × ${image.height})');
  });
}

Future<GlobalKey> _open(WidgetTester tester, Widget screen, ProgressionProvider p) async {
  final key = GlobalKey();
  // A fresh screen state each time (the previous tab or tier is not kept).
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(_app(screen, p, key));
  await _settle(tester);
  return key;
}

void main() {
  setUpAll(() {
    Directory(_outDir).createSync(recursive: true);
    final cache = Directory.systemTemp.createTempSync('parcours-preview-');
    ProgressionAssetCache.debugDirectory = cache;
    _catalog = ProgressionContent.fromJson(_content(cache));
  });

  testWidgets('parcours and progression previews', (tester) async {
    await tester.runAsync(_loadFonts);
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    tester.view.padding = const FakeViewPadding(top: 47 * 3, bottom: 34 * 3);
    addTearDown(tester.view.reset);

    // ── 5 · Parcours ──
    var key = await _open(tester, const LevelsPathScreen(), _provider(23));
    await _write(tester, key, 'parcours_ouverture.png');

    await tester.tap(find.byKey(const Key('path-tier-1')));
    await _settle(tester);
    await _write(tester, key, 'parcours_palier_termine_deplie.png');

    key = await _open(tester, const LevelsPathScreen(), _provider(23));
    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -600));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('path-tier-31')));
    await _settle(tester);
    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -300));
    await _settle(tester);
    await _write(tester, key, 'parcours_palier_a_venir_deplie.png');

    key = await _open(tester, const LevelsPathScreen(), _provider(23, premium: false));
    await tester.tap(find.byKey(const Key('path-tier-11')));
    await _settle(tester);
    await _write(tester, key, 'parcours_gratuit.png');

    key = await _open(tester, const LevelsPathScreen(), _provider(73));
    await _write(tester, key, 'parcours_niveau_73.png');

    // ── 6 · Progression ──
    key = await _open(tester, const ProgressionScreen(), _provider(23));
    await _write(tester, key, 'progression_ouverture.png');

    await tester.tap(find.byKey(const Key('quests-done-line')));
    await _settle(tester);
    await _write(tester, key, 'progression_terminees_depliees.png');

    await tester.tap(find.byKey(const Key('quest-tab-week')));
    await _settle(tester);
    await _write(tester, key, 'progression_semaine.png');

    await tester.tap(find.byKey(const Key('quest-tab-discover')));
    await _settle(tester);
    await _write(tester, key, 'progression_decouvrir.png');

    key = await _open(tester, const ProgressionScreen(initialTab: QuestTab.event), _provider(23, event: true));
    await _write(tester, key, 'progression_evenement.png');

    key = await _open(tester, const ProgressionScreen(), _provider(23));
    await tester.tap(find.byKey(const Key('quest-change-d2')));
    await _settle(tester);
    await _write(tester, key, 'progression_changer.png');

    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  }, skip: !_enabled);
}
