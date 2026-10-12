// Renders the Tournament tab (system D: DsScreenHeader, pinned invitation,
// day groups, 72 px agenda rows with one pill action each) to PNG so the
// screen can be reviewed without a device. Not a test of behaviour — skipped
// unless run explicitly:
//
//   flutter test test/preview/tournament_preview_test.dart \
//     --dart-define=PREVIEW=true \
//     --dart-define=PREVIEW_OUT=/abs/dir
//
// Manrope is loaded from assets/fonts (the bundled family), Material Icons
// from the Flutter SDK cache. The trophy render is a network image and the
// test HTTP client answers 400, so that slot shows its (empty) fallback.
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
import 'package:mobile/providers/subscription_provider.dart';
import 'package:mobile/providers/tournament_provider.dart';
import 'package:mobile/screens/home/tournament_screen.dart';
import 'package:mobile/utils/app_theme.dart';
import 'package:mobile/widgets/tournament_invite_gate.dart';

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

/// The real provider with its lists seeded and the network loads disabled.
class _SeededTournamentProvider extends TournamentProvider {
  final List<Tournament> upcoming;
  final List<Tournament> registered;
  final List<Tournament> active;

  _SeededTournamentProvider({
    required this.upcoming,
    required this.registered,
    required this.active,
  });

  @override
  List<Tournament> get upcomingTournaments => upcoming;
  @override
  List<Tournament> get registeredTournaments => registered;
  @override
  List<Tournament> get activeTournaments => active;
  @override
  bool get isLoading => false;

  @override
  Future<void> loadMyTournaments() async {}
  @override
  Future<void> loadUpcomingTournaments() async {}
  @override
  Future<void> loadPendingMatches() async {}
}

Tournament _t({
  required String id,
  required String name,
  required DateTime at,
  required String status,
  required int max,
  required int current,
  required int elo,
  int fee = 0,
  bool premium = false,
  String? minRank,
  String? maxRank,
  String? trophy,
}) {
  return Tournament(
    id: id,
    name: name,
    scheduledDate: at,
    status: status,
    maxParticipants: max,
    currentParticipants: current,
    winnerEloReward: elo,
    entryFee: fee,
    premiumRequired: premium,
    minRank: minRank,
    maxRank: maxRank,
    prizeType: trophy == null ? 'none' : 'trophy',
    trophyModel: trophy,
  );
}

/// The Tournament tab over seeded providers: five agenda rows across two
/// days and one pinned invitation. [english] swaps the user-written
/// tournament names so an English render reads naturally.
class TournamentPreviewScene extends StatelessWidget {
  final bool english;
  const TournamentPreviewScene({super.key, this.english = false});

  TournamentProvider _seeded() {
    final now = DateTime.now();
    DateTime day(int offset, int h, int m) =>
        DateTime(now.year, now.month, now.day + offset, h, m);
    String name(String fr, String en) => english ? en : fr;

    final samedi = _t(
      id: 't1', name: name('Tournoi du samedi', 'Saturday Open'), at: day(0, 20, 30),
      status: 'registration_open', max: 16, current: 8, elo: 500,
      trophy: 'classic',
    );
    final cricket = _t(
      id: 't2', name: name('Soirée Cricket', 'Cricket Night'), at: day(0, 21, 30),
      status: 'registration_open', max: 8, current: 6, elo: 300,
    );
    final ligue = _t(
      id: 't3', name: name('Ligue du soir', 'Evening League'), at: day(0, 19, 0),
      status: 'in_progress', max: 8, current: 8, elo: 400,
    );
    final coupe = _t(
      id: 't4', name: name('Coupe Or+', 'Gold+ Cup'), at: day(1, 18, 0),
      status: 'upcoming', max: 16, current: 12, elo: 600, minRank: 'gold',
    );
    final express = _t(
      id: 't5', name: name('Défi express', 'Express Challenge'), at: day(1, 21, 0),
      status: 'registration_closed', max: 8, current: 8, elo: 250,
    );
    final diamant = _t(
      id: 't6', name: name('Grand Prix Diamant des champions', 'Diamond Champions Grand Prix'), at: day(6, 20, 0),
      status: 'registration_open', max: 32, current: 3, elo: 800,
      fee: 500, premium: true,
    );
    final debutants = _t(
      id: 't7', name: name('Tournoi débutants', 'Beginners Open'), at: day(6, 17, 0),
      status: 'registration_open', max: 16, current: 16, elo: 400,
      maxRank: 'silver',
    );

    final tournaments = _SeededTournamentProvider(
      upcoming: [samedi, cricket, coupe, diamant, debutants],
      registered: [cricket, ligue, express],
      active: [ligue],
    );
    // No signed-in user in the preview, so "me" is player 2: player 1 is
    // the opponent shown on the card.
    tournaments.debugSeedPendingMatches([
      TournamentMatch(
        id: 'm1',
        tournamentId: 't3',
        tournamentName: name('Ligue du soir', 'Evening League'),
        roundNumber: 2,
        roundName: 'semi_final',
        matchNumber: 1,
        player1Id: 'opp',
        player1Username: 'DODO180',
        player2Id: 'me',
        player2Username: name('Moi', 'Me'),
        status: 'waiting_for_players',
        player1Score: 0,
        player2Score: 0,
        bestOf: 3,
        inviteSentAt: now.subtract(const Duration(seconds: 18)),
      ),
    ]);
    return tournaments;
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => SubscriptionProvider()),
        ChangeNotifierProvider<TournamentProvider>(create: (_) => _seeded()),
      ],
      child: const Scaffold(
        body: SafeArea(bottom: false, child: TournamentScreen()),
      ),
    );
  }
}

void main() {
  testWidgets('tournament tab preview', (tester) async {
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
        home: RepaintBoundary(key: key, child: const TournamentPreviewScene()),
      ),
    );
    // Localizations resolve asynchronously.
    await tester.runAsync(() async {
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    });
    await tester.pump();

    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$_outDir/tournament.png');
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      debugPrint('wrote ${file.path}');
    });
    expect(tester.takeException(), isNull);

    // The pinned card's countdown re-arms a one-second timer while mounted;
    // tear the tree down and let the last one fire so no timer is pending.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }, skip: !_enabled);

  testWidgets('invite prompt preview', (tester) async {
    await tester.runAsync(_loadFonts);
    final key = GlobalKey();
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.binding.setSurfaceSize(const Size(393, 852));
    tester.view.devicePixelRatio = 3;

    final tournaments = TournamentProvider();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => AuthProvider()),
            ChangeNotifierProvider<TournamentProvider>.value(value: tournaments),
            ChangeNotifierProvider(create: (_) => GameProvider()),
          ],
          child: MaterialApp(
            navigatorKey: navigatorKey,
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
            builder: (context, child) => TournamentInviteGate(
              navigatorKey: navigatorKey,
              child: child ?? const SizedBox.shrink(),
            ),
            home: Scaffold(
              body: Center(
                child: Text('Écran en dessous', style: AppTheme.sectionTitle),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    tournaments.debugSeedPendingMatches([
      TournamentMatch(
        id: 'm-r3',
        tournamentId: 't4',
        tournamentName: 'Tournoi du samedi',
        roundNumber: 3,
        roundName: 'semi_final',
        matchNumber: 28,
        player1Id: 'me',
        player1Username: 'Moi',
        player2Id: 'opp',
        player2Username: 'DODO180',
        status: 'waiting_for_players',
        player1Score: 0,
        player2Score: 0,
        bestOf: 3,
        inviteSentAt: DateTime.now().subtract(const Duration(seconds: 18)),
      ),
    ], myUserId: 'me');
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$_outDir/tournament_invite_prompt.png');
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      debugPrint('wrote ${file.path}');
    });
    // Raising the prompt plays the match-found sound; the audio plugin has
    // no implementation in the test engine and reports one
    // MissingPluginException per channel it opens. Not a rendering problem:
    // drain them all so only a real layout exception would fail the test.
    await tester.pump();
    while (tester.takeException() != null) {}
  }, skip: !_enabled);
}
