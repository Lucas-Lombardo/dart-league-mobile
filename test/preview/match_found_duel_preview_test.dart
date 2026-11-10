// Renders "Match found", piste B « Duel » (mockups docs/progression/ecrans/
// MtB, MtDeroule; CONTRACT §14.13) to PNG so it can be compared with the
// mockup without a device: the final screen (after 1.3 s, the ring on 3) on
// a 390 × 844 iPhone with its insets, the ghost, a player without items and
// no stakes, a small screen, and the frames of the 6 s scene.
// Not a test of behaviour — skipped unless run explicitly:
//
//   flutter test test/preview/match_found_duel_preview_test.dart \
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
import 'package:mobile/models/head_to_head.dart';
import 'package:mobile/models/progression.dart';
import 'package:mobile/providers/progression_provider.dart';
import 'package:mobile/screens/progression/match_found_screen.dart';
import 'package:mobile/services/progression_service.dart';
import 'package:mobile/utils/app_theme.dart';

const _enabled = bool.fromEnvironment('PREVIEW');
const _outDir = String.fromEnvironment('PREVIEW_OUT');

Future<void> _loadFonts() async {
  final fonts = Directory('${Directory.current.path}/assets/fonts');
  final loader = FontLoader(AppTheme.fontFamily);
  final files = fonts.listSync().whereType<File>().where((f) => f.path.endsWith('.ttf')).toList()
    ..sort((a, b) => a.path.compareTo(b.path));
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

/// The served content, with each item's asset copied where
/// ProgressionAssetCache looks for it.
Map<String, dynamic> _content(Directory cache) {
  final backend = '${Directory.current.parent.path}/backend';
  final dir = '$backend/src/progression/content';
  final assets = Directory('$backend/public/progression/items');
  Map<String, dynamic> read(String f) => jsonDecode(File('$dir/$f').readAsStringSync()) as Map<String, dynamic>;
  final items = [...read('items.json')['items'] as List, ...read('badges.json')['items'] as List]
      .cast<Map<String, dynamic>>();
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
  final levels = read('levels.json');
  return {
    'version': 'preview',
    'curve': levels['curve'],
    'prestige': levels['prestige'],
    'metals': read('metals.json')['metals'],
    'items': items,
    'levels': levels['levels'],
  };
}

const _n1 = PublicBadge(id: 'b1', badgeId: 'badge.daily-first', tier: 'gold', date: '2026-11-08');
const _b180 = PublicBadge(id: 'b2', badgeId: 'badge.machine-a-180', tier: 'gold');
const _moy = PublicBadge(id: 'b3', badgeId: 'badge.grosse-moyenne', tier: 'silver');

// MtB's two players (COMBOS A and C of gen_accueil8.py): liège / laiton /
// monogram T20 with the crown; dans le mille / légende / D16, one star.
const _me = MatchFoundPlayer(
  username: 'Dodo180',
  rank: 'gold',
  elo: 1409,
  isPremium: true,
  cosmetics: PublicCosmetics(
    level: 23,
    avatar: 'avatar.monogramme-acier',
    monogram: 'T20',
    frame: 'frame.laiton',
    background: 'background.liege',
    title: 'title.big-fish',
    badges: [_n1, _b180, _moy],
  ),
);
const _laFleche = MatchFoundPlayer(
  username: 'LaFleche',
  rank: 'platinum',
  elo: 1612,
  cosmetics: PublicCosmetics(
    level: 63,
    avatar: 'avatar.monogramme-legende',
    monogram: 'D16',
    frame: 'frame.legende',
    background: 'background.dans-le-mille',
    title: 'title.legende',
    badges: [_n1, _b180, _moy],
  ),
);

/// The stakes the server sends for 1 409 against 1 612 (EloService.stakesFor;
/// the mockup's +18 / −6 were placeholders).
MatchFoundScreen _ranked({String? record = 'Bilan 7 – 5'}) => MatchFoundScreen(
      subtitle: 'Série classée · BO3 · 501',
      me: _me,
      opponent: _laFleche,
      recordLine: record,
      eloIfWin: 56,
      eloIfLoss: -36,
    );

Widget _app(Widget child, ProgressionProvider p, GlobalKey key) => ChangeNotifierProvider<ProgressionProvider>.value(
      value: p,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.themeData,
        locale: const Locale('fr'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, navigator) => RepaintBoundary(key: key, child: navigator),
        home: child,
      ),
    );

/// Mounts [screen] on a [size] phone with its insets, lets the images load
/// WITHOUT moving the scene's clock, then shows the scene at each of [atMs].
/// One moment: writes `<name>.png`. Several: writes `<name>.png`, a strip of
/// the frames at a quarter of their size, each under its time.
Future<void> _shoot(
  WidgetTester tester,
  ProgressionProvider p,
  Widget screen,
  String name, {
  Size size = const Size(390, 844),
  double top = 47,
  double bottom = 34,
  List<int> atMs = const [3200],
}) async {
  tester.view.physicalSize = Size(size.width * 3, size.height * 3);
  tester.view.devicePixelRatio = 3;
  tester.view.padding = FakeViewPadding(top: top * 3, bottom: bottom * 3);
  final key = GlobalKey();
  await tester.pumpWidget(_app(KeyedSubtree(key: UniqueKey(), child: screen), p, key));
  // Localizations, asset images, SVG pictures and WebP textures resolve
  // asynchronously (real file IO): give them real time, not scene time.
  Future<void> load() => tester.runAsync(() async {
        for (var i = 0; i < 12; i++) {
          await tester.pump();
          await Future<void>.delayed(const Duration(milliseconds: 120));
        }
      });
  await load();
  var now = 0;
  final frames = <ui.Image>[];
  for (final ms in atMs) {
    await tester.pump(Duration(milliseconds: ms - now));
    now = ms;
    await load();
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await tester.runAsync(() => boundary.toImage(pixelRatio: 3));
    frames.add(image!);
  }
  final out = atMs.length == 1 ? frames.single : await tester.runAsync(() => _strip(frames, atMs));
  await tester.runAsync(() async {
    final bytes = await out!.toByteData(format: ui.ImageByteFormat.png);
    final file = File('$_outDir/$name.png');
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    debugPrint('wrote ${file.path}');
  });
}

/// The frames of the scene in a grid of 5, each under « 0,45 s ».
Future<ui.Image> _strip(List<ui.Image> frames, List<int> atMs) async {
  const cols = 5, pad = 24.0, label = 70.0, scale = 0.25;
  final w = frames.first.width * scale, h = frames.first.height * scale;
  final rows = (frames.length / cols).ceil();
  final width = cols * w + (cols + 1) * pad;
  final height = rows * (h + label) + (rows + 1) * pad;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..drawRect(Rect.fromLTWH(0, 0, width, height), Paint()..color = AppTheme.background);
  for (var i = 0; i < frames.length; i++) {
    final x = pad + (i % cols) * (w + pad);
    final y = pad + (i ~/ cols) * (h + label + pad);
    final seconds = (atMs[i] / 1000).toStringAsFixed(2).replaceAll('.', ',');
    final text = (ui.ParagraphBuilder(ui.ParagraphStyle(fontFamily: AppTheme.fontFamily, fontSize: 34, fontWeight: FontWeight.w800))
          ..pushStyle(ui.TextStyle(color: AppTheme.textPrimary))
          ..addText('$seconds s'))
        .build()
      ..layout(ui.ParagraphConstraints(width: w));
    canvas.drawParagraph(text, Offset(x, y + 10));
    final f = frames[i];
    canvas.drawImageRect(
      f,
      Rect.fromLTWH(0, 0, f.width.toDouble(), f.height.toDouble()),
      Rect.fromLTWH(x, y + label, w, h),
      Paint()..filterQuality = FilterQuality.high,
    );
  }
  return recorder.endRecording().toImage(width.round(), height.round());
}

void main() {
  late ProgressionProvider provider;

  setUpAll(() async {
    final cache = Directory.systemTemp.createTempSync('match-found-duel-preview-');
    ProgressionAssetCache.debugDirectory = cache;
    provider = ProgressionProvider()..debugSeed(content: ProgressionContent.fromJson(_content(cache)));
    MatchFoundScreen.debugLoadRecord = (_) async => const HeadToHeadRecord();
  });

  testWidgets('match found duel previews', (tester) async {
    await tester.runAsync(_loadFonts);
    addTearDown(tester.view.reset);

    // The final screen: everything in, the ring on 3.
    await _shoot(tester, provider, _ranked(), 'match_trouve_duel');
    // The scene, frame by frame.
    await _shoot(tester, provider, _ranked(), 'deroule', atMs: const [150, 450, 750, 1000, 1150, 1450, 2000, 3200, 4500, 5500]);
    await _shoot(
      tester,
      provider,
      const MatchFoundScreen(
        subtitle: 'Match fantôme · BO3 · 501',
        isGhost: true,
        recordLine: 'Son match du 2 nov. · moyenne 55,2',
        me: _me,
        opponent: MatchFoundPlayer(
          username: 'Bruno_T19',
          rank: 'gold',
          elo: 1398,
          cosmetics: PublicCosmetics(
            level: 41,
            avatar: 'avatar.trophee',
            frame: 'frame.obsidienne',
            background: 'background.carbone',
            title: 'title.machine-a-180',
            badges: [_b180, _moy],
          ),
        ),
        eloIfWin: 13,
        eloIfLoss: -12,
      ),
      'match_trouve_duel_fantome',
    );
    // An opponent without any item (steel, plain ground, rank badge: the
    // server still sends their level), no stakes (older server), first
    // meeting.
    await _shoot(
      tester,
      provider,
      const MatchFoundScreen(
        subtitle: 'Série classée · BO3 · 501',
        me: _me,
        opponent: MatchFoundPlayer(username: 'Newbie_42', rank: 'silver', elo: 905, cosmetics: PublicCosmetics(level: 3)),
        opponentId: 'u-new',
      ),
      'match_trouve_duel_sans_objet_sans_enjeu',
    );
    // Cosmetics unknown (match_found's lookup timed out): no level, the
    // card still holds together.
    await _shoot(
      tester,
      provider,
      const MatchFoundScreen(
        subtitle: 'Série classée · BO3 · 501',
        me: _me,
        opponent: MatchFoundPlayer(username: 'Newbie_42', rank: 'silver', elo: 905),
        eloIfWin: 102,
        eloIfLoss: -16,
      ),
      'match_trouve_duel_cosmetiques_inconnus',
    );
    // iPhone SE (375 × 667, 20 pt status bar, no home bar).
    await _shoot(tester, provider, _ranked(), 'match_trouve_duel_petit_ecran', size: const Size(375, 667), top: 20, bottom: 0);
    expect(tester.takeException(), isNull);
  }, skip: !_enabled);
}
