// Renders the real TournamentInviteGate prompt to PNG, with real fonts, so
// the screen can be reviewed without a device. Not a test of behaviour —
// skipped unless run explicitly:
//
//   flutter test test/preview/invite_prompt_preview_test.dart \
//     --dart-define=PREVIEW=true \
//     --dart-define=PREVIEW_OUT=/abs/dir \
//     --dart-define=PREVIEW_FONTS=/abs/dir/with/roboto-N.ttf
//
// The app declares fontFamily 'Inter' without bundling it, so on a phone it
// falls back to the system face (Roboto on Android). Here the Roboto files
// are registered under the 'Inter' family name so the theme resolves to them.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:mobile/l10n/app_localizations.dart';
import 'package:mobile/models/tournament.dart';
import 'package:mobile/providers/auth_provider.dart';
import 'package:mobile/providers/game_provider.dart';
import 'package:mobile/providers/tournament_provider.dart';
import 'package:mobile/utils/app_theme.dart';
import 'package:mobile/widgets/tournament_invite_gate.dart';

const _enabled = bool.fromEnvironment('PREVIEW');
const _outDir = String.fromEnvironment('PREVIEW_OUT');
const _fontsDir = String.fromEnvironment('PREVIEW_FONTS');

Future<void> _loadFonts() async {
  final dir = Directory(_fontsDir);
  final files = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.ttf')).toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  // 'Inter' is what the theme asks for; Material 3 button styles still
  // resolve to the typography default 'Roboto' — register both.
  for (final family in ['Inter', 'Roboto']) {
    final loader = FontLoader(family);
    for (final f in files) {
      final bytes = await f.readAsBytes();
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
    }
    await loader.load();
  }

  // Material icons live in the Flutter SDK cache.
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ??
      File(Platform.resolvedExecutable).parent.parent.parent.path;
  final icons = File('$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (icons.existsSync()) {
    final loader = FontLoader('MaterialIcons');
    final bytes = await icons.readAsBytes();
    loader.addFont(Future.value(ByteData.view(bytes.buffer)));
    await loader.load();
  }
}

/// The app theme, with the engine-default font of button labels pinned to
/// the loaded face. ButtonStyle.textStyle replaces (not merges) the text
/// theme, so on a phone those labels use the system font; in the test
/// engine "no family" means the blocky FlutterTest face.
ThemeData _previewTheme() {
  final base = AppTheme.themeData;
  WidgetStateProperty<TextStyle?>? pin(WidgetStateProperty<TextStyle?>? p) =>
      p == null
          ? null
          : WidgetStateProperty.resolveWith(
              (states) => p.resolve(states)?.copyWith(fontFamily: 'Inter'));
  return base.copyWith(
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: base.elevatedButtonTheme.style?.copyWith(
          textStyle: pin(base.elevatedButtonTheme.style?.textStyle)),
    ),
    textButtonTheme: TextButtonThemeData(
      style: base.textButtonTheme.style?.copyWith(
          textStyle: pin(base.textButtonTheme.style?.textStyle)),
    ),
  );
}

/// A stand-in for the spectator screen: same palette as the game UI, enough
/// to show the prompt sits over a live match.
class _FakeSpectateScreen extends StatelessWidget {
  const _FakeSpectateScreen();

  @override
  Widget build(BuildContext context) {
    Widget panel(String name, String score, Color color, {bool turn = false}) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
            decoration: BoxDecoration(
              color: AppTheme.gamePanel,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: turn ? color : Colors.transparent, width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(score, style: TextStyle(color: color, fontSize: 40, fontWeight: FontWeight.w800, height: 1.05)),
                const SizedBox(height: 6),
                const Text('T20 · T20 · 5', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
              ],
            ),
          ),
        );

    return Scaffold(
      backgroundColor: AppTheme.gameBackground,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.error.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.circle, size: 8, color: AppTheme.error),
                        SizedBox(width: 6),
                        Text('EN DIRECT', style: TextStyle(color: AppTheme.error, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
                      ],
                    ),
                  ),
                  const Spacer(),
                  const Text('Tournoi #4 · Demi-finale · Leg 2', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                  const SizedBox(width: 10),
                  const Icon(Icons.visibility_outlined, size: 16, color: AppTheme.textSecondary),
                  const SizedBox(width: 3),
                  const Text('2', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                ],
              ),
              const SizedBox(height: 14),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Center(
                    child: Container(
                      width: 280,
                      height: 280,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            Color(0xFFE8E2D2), Color(0xFFE8E2D2),
                            Color(0xFF111111), Color(0xFF111111),
                            Color(0xFF2B6D3A), Color(0xFF2B6D3A),
                            Color(0xFF1B1B1B), Color(0xFF1B1B1B),
                            Color(0xFFB91C1C), Color(0xFFB91C1C),
                            Color(0xFF111111), Color(0xFF111111),
                          ],
                          stops: [0, .07, .07, .10, .10, .14, .14, .60, .60, .66, .66, 1],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  panel('Ninjanain', '301', AppTheme.playerBlue, turn: true),
                  const SizedBox(width: 10),
                  panel('MCV93!', '188', AppTheme.opponentPink),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void main() {
  TournamentMatch invite({required DateTime sentAt}) => TournamentMatch(
        id: 'm-r3',
        tournamentId: 't4',
        tournamentName: 'Tournoi #4',
        roundNumber: 3,
        roundName: 'semi_final',
        matchNumber: 28,
        player1Id: 'me',
        player1Username: 'D_Contact',
        player2Id: 'opp',
        player2Username: 'Ninjanain',
        status: 'waiting_for_players',
        player1Score: 0,
        player2Score: 0,
        bestOf: 3,
        player1Ready: false,
        player2Ready: false,
        inviteSentAt: sentAt,
      );

  Future<void> render(WidgetTester tester, String name, DateTime sentAt) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final boundaryKey = GlobalKey();
    final tournaments = TournamentProvider();

    // iPhone 15/16-class logical size at 3x.
    tester.view.physicalSize = const Size(1179, 2556);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.runAsync(_loadFonts);

    await tester.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => AuthProvider()),
            ChangeNotifierProvider.value(value: tournaments),
            ChangeNotifierProvider(create: (_) => GameProvider()),
          ],
          child: MaterialApp(
            navigatorKey: navigatorKey,
            theme: _previewTheme(),
            debugShowCheckedModeBanner: false,
            locale: const Locale('fr'),
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => TournamentInviteGate(
              navigatorKey: navigatorKey,
              child: child ?? const SizedBox.shrink(),
            ),
            home: const _FakeSpectateScreen(),
          ),
        ),
      ),
    );
    await tester.pump();

    tournaments.debugSeedPendingMatches([invite(sentAt: sentAt)], myUserId: 'me');
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600)); // transition + pulse mid-way

    final boundary = boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final out = File('$_outDir/$name.png');
      await out.writeAsBytes(bytes!.buffer.asUint8List());
      // ignore: avoid_print
      print('PREVIEW wrote ${out.path} (${image.width}x${image.height})');
    });
  }

  testWidgets('invite prompt — fresh (6:58 left)', (tester) async {
    await render(tester, 'invite_prompt', DateTime.now().subtract(const Duration(seconds: 2)));
  }, skip: !_enabled);

  testWidgets('invite prompt — urgent (1:30 left)', (tester) async {
    await render(tester, 'invite_prompt_urgent', DateTime.now().subtract(const Duration(minutes: 5, seconds: 30)));
  }, skip: !_enabled);
}
