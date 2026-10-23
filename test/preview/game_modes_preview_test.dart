// Renders the non-online game screens restyled to system D — the spectator
// match view and the end of a local (hot-seat) match — to PNG so they can be
// reviewed without a device. Not a test of behaviour; skipped unless run
// explicitly:
//
//   flutter test test/preview/game_modes_preview_test.dart \
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
import 'package:mobile/models/local_match_config.dart';
import 'package:mobile/screens/local_match/local_match_widgets.dart';
import 'package:mobile/screens/spectate/spectator_match_screen.dart';
import 'package:mobile/services/socket_service.dart';
import 'package:mobile/services/spectate_service.dart';
import 'package:mobile/utils/app_theme.dart';

const _enabled = bool.fromEnvironment('PREVIEW');
const _outDir = String.fromEnvironment('PREVIEW_OUT');

const _size = Size(393, 852);
const _small = Size(375, 667);
const _padding = EdgeInsets.only(top: 59, bottom: 34);

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

const _seed = LiveRankedSeries(
  seriesId: 's1',
  matchId: 'm1',
  legNumber: 2,
  bestOf: 3,
  player1LegsWon: 1,
  player2LegsWon: 0,
  player1: SpectatorPlayer(id: 'p1', username: 'Vati99', elo: 1601),
  player2: SpectatorPlayer(id: 'p2', username: 'DODO180', elo: 1580),
  spectatorCount: 12,
);

Future<void> _render(
  WidgetTester tester,
  String name,
  Widget page, {
  Size size = _size,
  Duration settle = Duration.zero,
  bool withPadding = false,
  void Function()? beforeCapture,
}) async {
  final key = GlobalKey();
  final Widget home = MediaQuery(
    data: MediaQueryData(
      size: size,
      padding: withPadding ? _padding : EdgeInsets.zero,
    ),
    child: RepaintBoundary(key: key, child: page),
  );
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
      home: home,
    ),
  );
  await tester.runAsync(() async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  });
  if (beforeCapture != null) {
    beforeCapture();
    await tester.runAsync(() async {
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    });
  }
  if (settle > Duration.zero) {
    await tester.pump(settle);
    await tester.pump(settle);
  }
  await tester.pump();

  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 3);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('$_outDir/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
  });
  expect(tester.takeException(), isNull, reason: name);
}

void main() {
  testWidgets('game modes preview', (tester) async {
    // The spectator screen builds a real SpectatorProvider, which wakes the
    // socket service (and its connectivity watcher) — stub the plugin
    // channels so the render isn't drowned in MissingPluginException.
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final name in const [
      'dev.fluttercommunity.plus/connectivity',
      'dev.fluttercommunity.plus/connectivity_status',
    ]) {
      messenger.setMockMethodCallHandler(
        MethodChannel(name),
        (call) async => null,
      );
    }
    await tester.runAsync(_loadFonts);
    tester.view.devicePixelRatio = 3;

    await tester.binding.setSurfaceSize(_size);
    await _render(
      tester,
      'spectateur',
      const SpectatorMatchScreen(
        matchId: 'm1',
        title: 'CLASSÉ',
        seedRanked: _seed,
      ),
      withPadding: true,
    );

    // Series on Cloudflare: the thrower's camera (not renderable off-device,
    // so this shows its "unavailable" fallback over the virtual board), the
    // Camera / Board toggle and the caller mute button.
    await _render(
      tester,
      'spectateur_cameras',
      const SpectatorMatchScreen(
        matchId: 'm1',
        title: 'CLASSÉ',
        seedRanked: _seed,
      ),
      withPadding: true,
      beforeCapture: () => SocketService.debugDispatch('spectate_state', {
        'matchId': 'm1',
        'player1': {'id': 'p1', 'username': 'Vati99', 'elo': 1601},
        'player2': {'id': 'p2', 'username': 'DODO180', 'elo': 1580},
        'player1Score': 301,
        'player2Score': 341,
        'currentPlayerId': 'p1',
        'currentRoundThrows': ['T20', 'T20'],
        'videoTransport': 'sfu',
        'videoPlayers': ['p1', 'p2'],
      }),
    );

    // The tightest phone we support: the board panel must still fit.
    await tester.binding.setSurfaceSize(_small);
    await _render(
      tester,
      'spectateur_petit',
      const SpectatorMatchScreen(
        matchId: 'm1',
        title: 'CLASSÉ',
        seedRanked: _seed,
      ),
      size: _small,
      withPadding: true,
    );

    await tester.binding.setSurfaceSize(_size);
    await _render(
      tester,
      'local_fin_match',
      LocalMatchEndView(
        config: const LocalMatchConfig(
          gameMode: LocalGameMode.cricket,
          player1Name: 'Lucas',
          player2Name: 'Marie',
        ),
        winner: 0,
        legsWon: const [2, 1],
        stats: [
          LocalMatchStatRow(
            label: 'Lucas',
            value: '2,41',
            color: AppTheme.playerBlueBright,
            icon: Icons.timeline_rounded,
          ),
          LocalMatchStatRow(
            label: 'Marie',
            value: '1,88',
            color: AppTheme.opponentPinkBright,
            icon: Icons.timeline_rounded,
          ),
        ],
        onRematch: () {},
        onBack: () {},
      ),
      settle: const Duration(seconds: 2),
    );

    await _render(
      tester,
      'local_banniere_tour',
      const Scaffold(
        backgroundColor: AppTheme.background,
        body: Stack(children: [LocalTurnBanner(name: 'Marie', safeTop: 0, player: 1)]),
      ),
      settle: const Duration(milliseconds: 400),
    );
  }, skip: !_enabled);
}
