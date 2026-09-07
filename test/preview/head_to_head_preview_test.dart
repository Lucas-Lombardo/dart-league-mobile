// Renders the head-to-head screen (system D: versus card, duel figures,
// recent meetings as match rows) to PNG so the screen can be reviewed without
// a device. Not a test of behaviour — skipped unless run explicitly:
//
//   flutter test test/preview/head_to_head_preview_test.dart \
//     --dart-define=PREVIEW=true \
//     --dart-define=PREVIEW_OUT=/abs/dir
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/l10n/app_localizations.dart';
import 'package:mobile/models/head_to_head.dart';
import 'package:mobile/screens/profile/head_to_head_screen.dart';
import 'package:mobile/utils/app_theme.dart';

const _enabled = bool.fromEnvironment('PREVIEW');
const _outDir = String.fromEnvironment('PREVIEW_OUT');

Future<void> _loadFonts() async {
  final fonts = Directory('${Directory.current.path}/assets/fonts');
  if (fonts.existsSync()) {
    final loader = FontLoader(AppTheme.fontFamily);
    final files = fonts
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.ttf'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final f in files) {
      final bytes = await f.readAsBytes();
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
    }
    await loader.load();
  }
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ??
      File(Platform.resolvedExecutable).parent.parent.parent.path;
  final icons = File(
    '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
  if (icons.existsSync()) {
    final loader = FontLoader('MaterialIcons');
    final bytes = await icons.readAsBytes();
    loader.addFont(Future.value(ByteData.view(bytes.buffer)));
    await loader.load();
  }
}

HeadToHead _data() {
  final now = DateTime.now();
  return HeadToHead(
    opponent: const HeadToHeadOpponent(
      id: 'u-dodo',
      username: 'Tomtom_180',
      elo: 1487,
      rank: 'platinum',
      isPremium: true,
    ),
    record: const HeadToHeadRecord(wins: 7, losses: 4, encounters: 11),
    byMode: const [
      HeadToHeadModeRecord(mode: 'ranked', wins: 5, losses: 3),
      HeadToHeadModeRecord(mode: 'friendly', wins: 2, losses: 1),
    ],
    legs: 26,
    me: const HeadToHeadPlayer(
      average: 58.4,
      bestVisit: 180,
      count180: 6,
      tons: 21,
      bestCheckout: 121,
      checkoutPct: 34.5,
      legsWon: 15,
    ),
    them: const HeadToHeadPlayer(
      average: 54.1,
      bestVisit: 140,
      count180: 3,
      tons: 17,
      bestCheckout: 96,
      checkoutPct: 28.0,
      legsWon: 11,
    ),
    recent: [
      HeadToHeadEncounter(
        matchId: 'm1',
        mode: 'ranked',
        gameMode: 'x01',
        playedAt: now.subtract(const Duration(hours: 3)),
        won: true,
        myLegs: 2,
        theirLegs: 1,
        myAverage: 61.2,
        theirAverage: 55.8,
        eloChange: 17,
      ),
      HeadToHeadEncounter(
        matchId: 'm2',
        mode: 'friendly',
        gameMode: 'x01',
        playedAt: now.subtract(const Duration(days: 1, hours: 5)),
        won: false,
        myLegs: 0,
        theirLegs: 2,
        myAverage: 49.9,
        theirAverage: 60.4,
      ),
      HeadToHeadEncounter(
        matchId: 'm3',
        mode: 'ranked',
        gameMode: 'x01',
        playedAt: now.subtract(const Duration(days: 6)),
        eloChange: 0,
      ),
    ],
  );
}

void main() {
  testWidgets('head to head preview', (tester) async {
    await tester.runAsync(_loadFonts);
    final key = GlobalKey();
    await tester.binding.setSurfaceSize(const Size(393, 852));
    tester.view.devicePixelRatio = 3;
    await tester.pumpWidget(
      MaterialApp(
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
        home: RepaintBoundary(
          key: key,
          child: HeadToHeadScreen(
            opponentId: 'u-dodo',
            opponentUsername: 'Tomtom_180',
            initialData: _data(),
          ),
        ),
      ),
    );
    await tester.runAsync(() async {
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    });
    await tester.pump();

    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$_outDir/head_to_head.png');
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      debugPrint('wrote ${file.path}');
    });
    expect(tester.takeException(), isNull);
  }, skip: !_enabled);
}
