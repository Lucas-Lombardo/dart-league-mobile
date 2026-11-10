// Renders the simplified daily challenge (mockups docs/progression/ecrans/
// DefB1, DefB2, DefFormats) to PNG so it can be compared with the mockups
// without a device: before the ranked try and after it (390 × 844 with an
// iPhone's insets), the ⓘ sheet, and the small board of the 16 real formats.
// Not a test of behaviour — skipped unless run explicitly:
//
//   flutter test test/preview/challenge_screen_preview_test.dart \
//     --dart-define=PREVIEW=true \
//     --dart-define=PREVIEW_OUT=/abs/dir
//
// The formats are read from backend/src/progression/content/defs, and the
// item assets from backend/public/progression/items.
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
import 'package:mobile/screens/challenge/challenge_api.dart';
import 'package:mobile/screens/challenge/challenge_mini_board.dart';
import 'package:mobile/screens/challenge/challenge_models.dart';
import 'package:mobile/screens/challenge/challenge_screen.dart';
import 'package:mobile/services/progression_service.dart';
import 'package:mobile/utils/app_theme.dart';

const _enabled = bool.fromEnvironment('PREVIEW');
const _outDir = String.fromEnvironment('PREVIEW_OUT');

final _backend = '${Directory.current.parent.path}/backend';

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

Map<String, dynamic> _read(String file) =>
    jsonDecode(File('$_backend/src/progression/content/$file').readAsStringSync()) as Map<String, dynamic>;

/// The served content (items + metals for the avatars, the XP of the try).
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
    'defs': const <String, dynamic>{},
    'xp': {'ranked': 60, 'rankedWin': 40, 'friendly': 30, 'training': 30, 'ghost': 40, 'challenge': 50},
  };
}

List<Map<String, dynamic>> _formats() =>
    (_read('defs/challenge_formats.json')['items'] as List).cast<Map<String, dynamic>>();

/// DefB1/DefB2's data: Cricket · 30, the Gold board of 12, TripleTom first.
ChallengeToday _today({Map<String, dynamic>? ranked, int streak = 4}) => ChallengeToday.fromJson({
      'date': '2026-11-09',
      'endsAt': DateTime.now().add(const Duration(hours: 14, minutes: 30)).toUtc().toIso8601String(),
      'format': _formats().firstWhere((f) => f['id'] == 'cricket-30'),
      'board': {'rank': 'gold', 'ranks': ['gold'], 'open': true, 'players': 12, 'eloBonus': 24},
      'players': 21,
      'ranked': ranked,
      'streak': {
        'current': streak,
        'best': 6,
        'freezeAvailable': true,
        'days': [
          for (var i = 3; i <= 9; i++) {'date': '2026-11-0$i', 'played': i >= 5 && (i < 9 || ranked != null), 'today': i == 9},
        ],
      },
      'remind': true,
      'yesterday': {'date': '2026-11-08', 'crownId': 'c1', 'board': 'gold', 'userId': 'u1', 'username': 'TripleTom', 'score': 44, 'verified': true},
    })!;

const _tripleTom = {'level': 31, 'avatar': 'avatar.monogramme-acier', 'monogram': 'TT', 'frame': 'frame.laiton'};

ChallengeLeaderboard _board({bool withMe = false}) {
  final rows = <(String, String, int)>[
    ('TripleTom', 'platinum', 41),
    ('Kev_D20', 'gold', 40),
    ('LaFleche', 'gold', 39),
    if (withMe) ('Dodo180', 'gold', 38),
    ('Juju180', 'platinum', 36),
    ('Mika_T19', 'gold', 35),
    ('Bruno_T19', 'gold', 33),
  ];
  return ChallengeLeaderboard.fromJson({
    'date': '2026-11-09',
    'view': 'rank',
    'board': {'rank': 'gold', 'ranks': ['gold'], 'open': true, 'players': 12},
    'counts': {'rank': 12, 'all': 21, 'friends': 2},
    'rows': [
      for (var i = 0; i < rows.length; i++)
        {
          'position': i + 1,
          'userId': rows[i].$1 == 'Dodo180' ? 'me' : 'u${i + 1}',
          'username': rows[i].$1,
          'rank': rows[i].$2,
          'score': rows[i].$3,
          'me': rows[i].$1 == 'Dodo180',
          'crown': i == 0,
          if (i == 0) 'cosmetics': _tripleTom,
        },
    ],
  });
}

/// [key] wraps the whole navigator, so a bottom sheet is in the picture too.
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

/// The screen on a 390 × 844 iPhone (47 pt status bar, 34 pt home bar).
Future<void> _shootScreen(WidgetTester tester, ProgressionProvider p, ChallengeToday today, ChallengeLeaderboard board, String file,
    {Future<void> Function()? then, String? thenFile}) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  tester.view.padding = const FakeViewPadding(top: 47 * 3, bottom: 34 * 3);
  ChallengeStore.instance.debugSeed(today);
  ChallengeStore.instance.debugLoader = () async => today;
  ChallengeApi.debugLeaderboard = (view) async => board;
  final key = GlobalKey();
  await tester.pumpWidget(_app(const ChallengeScreen(), p, key));
  await _settle(tester);
  final scroll = tester.state<ScrollableState>(find.byType(Scrollable).first).position;
  debugPrint('$file: scroll extent ${scroll.maxScrollExtent} (0 = fits without scrolling)');
  await _write(tester, key, file);
  if (then != null) {
    await then();
    await _settle(tester);
    await _write(tester, key, thenFile!);
  }
}

/// The 16 formats' small boards with their name and brief (DefFormats).
class _Formats extends StatelessWidget {
  const _Formats();

  @override
  Widget build(BuildContext context) {
    final formats = _formats().map(ChallengeFormat.fromJson).whereType<ChallengeFormat>().toList();
    return Material(
      color: AppTheme.background,
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: GridView.count(
          crossAxisCount: 4,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio: 1.12,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (final f in formats)
              Container(
                padding: const EdgeInsets.fromLTRB(12, 18, 12, 12),
                decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(16)),
                child: Column(
                  children: [
                    ChallengeMiniBoard(spec: f.board, size: 126),
                    const SizedBox(height: 10),
                    Text(f.name.resolve(context), textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    Text(
                      f.brief?.resolve(context) ?? '',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 13, height: 1.35, fontWeight: FontWeight.w600, color: Color(0xFFCBD5E1)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

void main() {
  late ProgressionProvider provider;

  setUpAll(() async {
    final cache = Directory.systemTemp.createTempSync('challenge-preview-');
    ProgressionAssetCache.debugDirectory = cache;
    provider = ProgressionProvider()..debugSeed(content: ProgressionContent.fromJson(_content(cache)));
  });

  testWidgets('challenge screen previews', (tester) async {
    await tester.runAsync(_loadFonts);
    await _shootScreen(
      tester,
      provider,
      _today(),
      _board(),
      'defi_avant.png',
      then: () async {
        await tester.tap(find.text('Cricket · 30 fléchettes'));
        await tester.pumpAndSettle();
      },
      thenFile: 'defi_regle.png',
    );
    await tester.pumpWidget(const SizedBox());
    await _shootScreen(
      tester,
      provider,
      _today(
        streak: 5,
        ranked: {'id': 'a1', 'status': 'submitted', 'score': 38, 'finished': true, 'position': 4, 'total': 12},
      ),
      _board(withMe: true),
      'defi_apres.png',
    );
    await tester.pumpWidget(const SizedBox());

    tester.view.physicalSize = const Size(1320 * 2, 1200 * 2);
    tester.view.devicePixelRatio = 2;
    tester.view.padding = FakeViewPadding.zero;
    final key = GlobalKey();
    await tester.pumpWidget(_app(const _Formats(), provider, key));
    await _settle(tester);
    await _write(tester, key, 'defi_formats.png', ratio: 2);
    tester.view.reset();
    expect(tester.takeException(), isNull);
  }, skip: !_enabled);
}
