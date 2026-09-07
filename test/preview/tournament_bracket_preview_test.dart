// Renders the tournament detail's Tableau tab (tree + focus card) to PNG in
// its three player states, so the screen can be reviewed without a device.
// Not a test of behaviour — skipped unless run explicitly:
//
//   flutter test test/preview/tournament_bracket_preview_test.dart \
//     --dart-define=PREVIEW=true \
//     --dart-define=PREVIEW_OUT=/abs/dir \
//     --dart-define=PREVIEW_FONTS=/abs/dir/with/regular-and-bold.ttf
//
// The app declares fontFamily 'Inter' without bundling it, so on a phone it
// falls back to the system face. Here the given TTFs are registered under the
// 'Inter' and 'Roboto' family names so the theme resolves to them.
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
import 'package:mobile/providers/tournament_provider.dart';
import 'package:mobile/screens/home/tournament_detail_screen.dart';
import 'package:mobile/utils/app_theme.dart';

const _enabled = bool.fromEnvironment('PREVIEW');
const _outDir = String.fromEnvironment('PREVIEW_OUT');
const _fontsDir = String.fromEnvironment('PREVIEW_FONTS');

const me = 'u-me';

Future<void> _loadFonts() async {
  if (_fontsDir.isEmpty) return;
  final dir = Directory(_fontsDir);
  if (!dir.existsSync()) return;
  final files =
      dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.ttf'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  for (final family in ['Inter', 'Roboto']) {
    final loader = FontLoader(family);
    for (final f in files) {
      final bytes = await f.readAsBytes();
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
    }
    await loader.load();
  }
  final flutterRoot =
      Platform.environment['FLUTTER_ROOT'] ??
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

ThemeData _previewTheme() {
  final base = AppTheme.themeData;
  WidgetStateProperty<TextStyle?>? pin(WidgetStateProperty<TextStyle?>? p) =>
      p == null
      ? null
      : WidgetStateProperty.resolveWith(
          (states) => p.resolve(states)?.copyWith(fontFamily: 'Inter'),
        );
  return base.copyWith(
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: base.elevatedButtonTheme.style?.copyWith(
        textStyle: pin(base.elevatedButtonTheme.style?.textStyle),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: base.textButtonTheme.style?.copyWith(
        textStyle: pin(base.textButtonTheme.style?.textStyle),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: (base.outlinedButtonTheme.style ?? const ButtonStyle()).copyWith(
        textStyle: WidgetStateProperty.all(
          const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.bold),
        ),
      ),
    ),
  );
}

TournamentMatch m({
  required String id,
  required int round,
  required String roundName,
  required int number,
  String? p1,
  String? p2,
  String status = 'pending',
  int s1 = 0,
  int s2 = 0,
  String? winner,
  String? next,
  DateTime? inviteSentAt,
}) {
  return TournamentMatch(
    id: id,
    tournamentId: 't1',
    tournamentName: 'Tournoi du Samedi',
    roundNumber: round,
    roundName: roundName,
    matchNumber: number,
    player1Id: p1,
    player1Username: p1 == me ? 'DODO180' : p1?.toUpperCase(),
    player2Id: p2,
    player2Username: p2 == me ? 'DODO180' : p2?.toUpperCase(),
    status: status,
    player1Score: s1,
    player2Score: s2,
    winnerId: winner,
    bestOf: 3,
    nextMatchId: next,
    inviteSentAt: inviteSentAt,
  );
}

List<TournamentMatch> quarters() => [
  m(
    id: 'q1',
    round: 1,
    roundName: 'quarter_final',
    number: 1,
    p1: me,
    p2: 'steeltip',
    status: 'completed',
    s1: 2,
    winner: me,
    next: 's1',
  ),
  m(
    id: 'q2',
    round: 1,
    roundName: 'quarter_final',
    number: 2,
    p1: 'vati99',
    p2: 'lucky26',
    status: 'completed',
    s1: 2,
    s2: 1,
    winner: 'vati99',
    next: 's1',
  ),
  m(
    id: 'q3',
    round: 1,
    roundName: 'quarter_final',
    number: 3,
    p1: 't20queen',
    p2: 'flight180',
    status: 'completed',
    s1: 2,
    winner: 't20queen',
    next: 's2',
  ),
  m(
    id: 'q4',
    round: 1,
    roundName: 'quarter_final',
    number: 4,
    p1: 'bullseye_max',
    p2: 'thedarter',
    status: 'completed',
    s1: 2,
    s2: 1,
    winner: 'bullseye_max',
    next: 's2',
  ),
];

TournamentMatch semi2() => m(
  id: 's2',
  round: 2,
  roundName: 'semi_final',
  number: 2,
  p1: 't20queen',
  p2: 'bullseye_max',
  status: 'in_progress',
  s1: 1,
  s2: 1,
  next: 'f',
);

List<TournamentMatch> waitingBracket() => [
  ...quarters(),
  m(
    id: 's1',
    round: 2,
    roundName: 'semi_final',
    number: 1,
    p1: me,
    p2: 'vati99',
    status: 'completed',
    s1: 2,
    s2: 1,
    winner: me,
    next: 'f',
  ),
  semi2(),
  m(id: 'f', round: 3, roundName: 'final', number: 1, p1: me),
];

List<TournamentMatch> readyBracket() => [
  ...quarters(),
  m(
    id: 's1',
    round: 2,
    roundName: 'semi_final',
    number: 1,
    p1: me,
    p2: 'vati99',
    status: 'waiting_for_players',
    next: 'f',
    inviteSentAt: DateTime.now().subtract(const Duration(seconds: 48)),
  ),
  semi2(),
  m(id: 'f', round: 3, roundName: 'final', number: 1),
];

List<TournamentMatch> eliminatedBracket() => [
  ...quarters(),
  m(
    id: 's1',
    round: 2,
    roundName: 'semi_final',
    number: 1,
    p1: me,
    p2: 'vati99',
    status: 'completed',
    s1: 1,
    s2: 2,
    winner: 'vati99',
    next: 'f',
  ),
  semi2(),
  m(id: 'f', round: 3, roundName: 'final', number: 1, p1: 'vati99'),
];

Tournament tournament() => Tournament(
  id: 't1',
  name: 'Tournoi du Samedi',
  scheduledDate: DateTime(2026, 9, 6, 20, 30),
  status: 'in_progress',
  maxParticipants: 8,
  currentParticipants: 8,
  winnerEloReward: 500,
  currentRound: 2,
  totalRounds: 3,
);

void main() {
  Future<void> render(
    WidgetTester tester,
    String name,
    List<TournamentMatch> bracket, {
    List<TournamentMatch> pending = const [],
  }) async {
    final provider = TournamentProvider();
    if (pending.isNotEmpty) {
      provider.debugSeedPendingMatches(pending, myUserId: me);
    }
    final key = GlobalKey();
    await tester.binding.setSurfaceSize(const Size(393, 852));
    tester.view.devicePixelRatio = 3;
    await tester.pumpWidget(
      ChangeNotifierProvider<TournamentProvider>.value(
        value: provider,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: _previewTheme(),
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
            child: Scaffold(
              backgroundColor: AppTheme.background,
              body: TournamentBracketTab(
                tournament: tournament(),
                bracket: bracket,
                live: const [],
                currentUserId: me,
                onReturnedFromMatch: () async {},
              ),
            ),
          ),
        ),
      ),
    );
    // Localizations load asynchronously; the tree scrolls to the marker on
    // the frame after layout.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    // Real async work (raster, file IO) must leave the test's fake zone.
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$_outDir/$name.png');
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      debugPrint('wrote ${file.path}');
    });
  }

  testWidgets('tableau tab previews', (tester) async {
    await tester.runAsync(_loadFonts);
    await render(tester, 'tableau-attente', waitingBracket());
    final ready = readyBracket();
    await render(
      tester,
      'tableau-pret',
      ready,
      pending: [ready.firstWhere((x) => x.id == 's1')],
    );
    await render(tester, 'tableau-elimine', eliminatedBracket());
  }, skip: !_enabled);
}
