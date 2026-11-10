// Renders the ranked queue at 5 min with the ghost fallback (CONTRACT
// §14.12), card B (mockups docs/progression/ecrans/FgBp, FgBg) to PNG, on the
// real MatchmakingScreen:
// - carte_b_premium / carte_b_gratuit: 390 × 844 with an iPhone's insets,
//   the premium card and the free player's locked one (to compare with the
//   mockups);
// - carte_b_premium_lien / carte_b_gratuit_lien: after « Attendre », the
//   bottom link (with its crown for a free player);
// - file_5min, file_5min_lien (+ _long): the same premium screen without
//   insets, at 844 and 1180 pt high.
// (The home without the ghost tile comes from home_final_preview_test.dart.)
// Not a test of behaviour — skipped unless run explicitly:
//
//   flutter test test/preview/fantome_secours_preview_test.dart \
//     --dart-define=PREVIEW=true \
//     --dart-define=PREVIEW_OUT=/abs/dir
//
// The real content (backend/src/progression/content) and the real item
// assets (backend/public/progression/items) are loaded: the ghost wears the
// mockup's items (Kev_D20's combo of gen_accueil8.py, renamed Bruno_T19).
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
import 'package:mobile/models/user.dart';
import 'package:mobile/providers/auth_provider.dart';
import 'package:mobile/providers/matchmaking_provider.dart';
import 'package:mobile/providers/progression_provider.dart';
import 'package:mobile/providers/subscription_provider.dart';
import 'package:mobile/screens/ghost/ghost_models.dart';
import 'package:mobile/screens/ghost/ghost_service.dart';
import 'package:mobile/screens/matchmaking/matchmaking_screen.dart';
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
/// ProgressionAssetCache looks for it, plus the ghost's XP and delay.
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
    'xp': {'ghost': 40},
    'defs': {
      'ghost': [
        {'id': 'params', 'queueDelaySec': 300, 'matchXp': 40},
      ],
    },
  };
}

/// FgBp / FgBg's ghost: obsidian, carbon, the trophy, « Machine à 180 »,
/// two pinned badges, level 41.
const _ghostCosmetics = {
  'level': 41,
  'avatar': 'avatar.trophee',
  'frame': 'frame.obsidienne',
  'background': 'background.carbone',
  'title': 'title.machine-a-180',
  'badges': [
    {'id': 'b2', 'badgeId': 'badge.machine-a-180', 'tier': 'gold'},
    {'id': 'b3', 'badgeId': 'badge.grosse-moyenne', 'tier': 'silver'},
  ],
};

GhostOfferResponse _offer() => GhostOfferResponse.fromJson({
      'available': true,
      'queueDelaySec': 300,
      'offer': {
        'id': 'o-1',
        'expiresAt': DateTime.now().add(const Duration(minutes: 15)).toUtc().toIso8601String(),
        'bestOf': 3,
        'eloEligible': true,
        'eloMatchesLeft': 5,
        'eloIfWin': 13,
        'eloIfLoss': -12,
        'ghost': {
          'ownerId': 'u-1',
          'username': 'Bruno_T19',
          'elo': 1398,
          'rank': 'gold',
          'cosmetics': _ghostCosmetics,
          'playedAt': '2026-11-02T19:00:00.000Z',
          'average': 55.2,
        },
      },
    });

GhostOfferResponse _preview() => GhostOfferResponse.fromJson({
      'available': false,
      'reason': 'premium',
      'queueDelaySec': 300,
      'preview': {'username': 'Bruno_T19', 'rank': 'gold', 'elo': 1398, 'cosmetics': _ghostCosmetics},
    });

class _FakeAuth extends AuthProvider {
  final bool premium;
  _FakeAuth(this.premium);
  @override
  User? get currentUser => User(id: 'u-me', username: 'Dodo180', email: 'd@x.fr', elo: 1409, rank: 'gold', isPremium: premium);
}

class _FakeSubscription extends SubscriptionProvider {
  final bool premium;
  _FakeSubscription(this.premium);
  @override
  bool get isPremiumActive => premium;
  @override
  Future<void> refresh() async {}
}

class _FakeMatchmaking extends MatchmakingProvider {
  @override
  int get searchTime => 300;
  @override
  bool get isSearching => true;
  @override
  int get eloRange => 1500;
  @override
  Future<void> leaveQueue(String userId) async {}
}

Widget _app(Widget child, ProgressionProvider progression, {required bool premium}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>.value(value: _FakeAuth(premium)),
      ChangeNotifierProvider<SubscriptionProvider>.value(value: _FakeSubscription(premium)),
      ChangeNotifierProvider<MatchmakingProvider>.value(value: _FakeMatchmaking()),
      ChangeNotifierProvider<ProgressionProvider>.value(value: progression),
    ],
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
      home: child,
    ),
  );
}

/// Localizations, asset images, SVG pictures and WebP textures resolve
/// asynchronously (real file IO): real time, not test time.
Future<void> _settle(WidgetTester tester) async {
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
    debugPrint('wrote ${out.path}');
  });
}

void main() {
  late ProgressionProvider progression;

  setUpAll(() {
    final cache = Directory.systemTemp.createTempSync('fantome-carte-b-preview-');
    ProgressionAssetCache.debugDirectory = cache;
    progression = ProgressionProvider()..debugSeed(content: ProgressionContent.fromJson(_content(cache)));
  });

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(
      'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
      (_) async => const StandardMessageCodec().encodeMessage([null]),
    );
  });

  tearDown(() => GhostService.debugOffer = null);

  /// The queue at 5:00, then (`link`) the card folded by « Attendre ».
  Future<void> shoot(
    WidgetTester tester, {
    required bool premium,
    required String name,
    required String linkName,
    Size size = const Size(390, 844),
    double top = 47,
    double bottom = 34,
  }) async {
    GhostService.debugOffer = () async => premium ? _offer() : _preview();
    tester.view.physicalSize = Size(size.width * 3, size.height * 3);
    tester.view.devicePixelRatio = 3;
    tester.view.padding = FakeViewPadding(top: top * 3, bottom: bottom * 3);
    final key = GlobalKey();
    await tester.pumpWidget(
      _app(RepaintBoundary(key: key, child: MatchmakingScreen(key: UniqueKey())), progression, premium: premium),
    );
    await _settle(tester);
    await _write(tester, key, '$name.png');

    await tester.ensureVisible(find.text('Attendre'));
    await tester.tap(find.text('Attendre'));
    await _settle(tester);
    await _write(tester, key, '$linkName.png');
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  testWidgets('queue at 5 min, card B previews', (tester) async {
    await tester.runAsync(_loadFonts);
    addTearDown(tester.view.reset);
    await shoot(tester, premium: true, name: 'carte_b_premium', linkName: 'carte_b_premium_lien');
    await shoot(tester, premium: false, name: 'carte_b_gratuit', linkName: 'carte_b_gratuit_lien');
    for (final (size, suffix) in [(const Size(390, 844), ''), (const Size(390, 1180), '_long')]) {
      await shoot(
        tester,
        premium: true,
        name: 'file_5min$suffix',
        linkName: 'file_5min_lien$suffix',
        size: size,
        top: 0,
        bottom: 0,
      );
    }
    expect(tester.takeException(), isNull);
  }, skip: !_enabled);
}
