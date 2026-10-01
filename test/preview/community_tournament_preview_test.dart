// Renders the community-tournament screens to PNG (agenda with official and
// community rows, the creation form, the organiser panel before and after
// 8 players) so they can be reviewed without a device. Not a test of
// behaviour — skipped unless run explicitly:
//
//   flutter test test/preview/community_tournament_preview_test.dart \
//     --dart-define=PREVIEW=true \
//     --dart-define=PREVIEW_OUT=/abs/dir
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
import 'package:mobile/providers/subscription_provider.dart';
import 'package:mobile/providers/tournament_provider.dart';
import 'package:mobile/screens/home/community_organizer_panel.dart';
import 'package:mobile/screens/home/community_tournament_form_screen.dart';
import 'package:mobile/screens/home/tournament_screen.dart';
import 'package:mobile/utils/app_theme.dart';
import 'package:mobile/utils/tournament_registration_gate.dart';

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

class _SeededTournamentProvider extends TournamentProvider {
  final List<Tournament> upcoming;

  _SeededTournamentProvider(this.upcoming);

  @override
  List<Tournament> get upcomingTournaments => upcoming;
  @override
  List<Tournament> get registeredTournaments => const [];
  @override
  List<Tournament> get activeTournaments => const [];
  @override
  bool get isLoading => false;
  @override
  Future<void> loadMyTournaments() async {}
  @override
  Future<void> loadUpcomingTournaments() async {}
  @override
  Future<void> loadPendingMatches() async {}
}

Tournament _t(
  String id,
  String name,
  DateTime at, {
  required int max,
  required int current,
  String? organizer,
  int bestOf = 3,
  String? trophy,
}) {
  return Tournament(
    id: id,
    name: name,
    scheduledDate: at,
    status: 'registration_open',
    maxParticipants: max,
    currentParticipants: current,
    winnerEloReward: organizer == null ? 500 : 0,
    organizerId: organizer == null ? null : 'u-$organizer',
    organizerUsername: organizer,
    bestOf: bestOf,
    prizeType: trophy == null ? 'none' : 'trophy',
    trophyModel: trophy,
  );
}

Future<void> _shoot(
  WidgetTester tester,
  TournamentProvider provider,
  Widget screen,
  String file, {
  Size size = const Size(393, 852),
}) async {
  final key = GlobalKey();
  await tester.binding.setSurfaceSize(size);
  tester.view.devicePixelRatio = 3;
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => SubscriptionProvider()),
        ChangeNotifierProvider<TournamentProvider>.value(value: provider),
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
        home: RepaintBoundary(key: key, child: screen),
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
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 3);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final out = File('$_outDir/$file');
    await out.writeAsBytes(bytes!.buffer.asUint8List());
    debugPrint('wrote ${out.path}');
  });
  expect(tester.takeException(), isNull);
  await tester.pumpWidget(const SizedBox());
}

void main() {
  final now = DateTime.now();
  DateTime day(int offset, int h, int m) =>
      DateTime(now.year, now.month, now.day + offset, h, m);

  testWidgets('community agenda preview', (tester) async {
    await tester.runAsync(_loadFonts);
    final provider = _SeededTournamentProvider([
      _t('c1', 'Soirée du jeudi', day(0, 21, 0),
          max: 8, current: 5, organizer: 'Vati99'),
      _t('c2', 'Coupe des Flèches lyonnaises', day(1, 20, 30),
          max: 16, current: 12, organizer: 'Ninjanain'),
      _t('o1', 'Tournoi du Samedi', day(2, 18, 0),
          max: 32, current: 14, trophy: 'podium'),
      _t('c3', 'Tournoi des collègues', day(3, 19, 0),
          max: 8, current: 3, organizer: 'Dodo180', bestOf: 1),
    ]);
    await _shoot(
      tester,
      provider,
      const Scaffold(body: SafeArea(bottom: false, child: TournamentScreen())),
      'community_agenda.png',
    );
  }, skip: !_enabled);

  testWidgets('community form preview', (tester) async {
    await tester.runAsync(_loadFonts);
    await _shoot(
      tester,
      _SeededTournamentProvider(const []),
      const CommunityTournamentFormScreen(),
      'community_form.png',
    );
  }, skip: !_enabled);

  testWidgets('monthly limit popup preview', (tester) async {
    await tester.runAsync(_loadFonts);
    for (final (date, file) in [
      (now, 'monthly_limit_popup.png'),
      (DateTime(now.year, now.month + 1, 12), 'monthly_limit_popup_next.png'),
    ]) {
      await _shoot(
        tester,
        _SeededTournamentProvider(const []),
        Scaffold(
          backgroundColor: Colors.black54,
          body: Center(
            child: TournamentMonthlyLimitDialog(
              limit: 2,
              date: date,
              onLater: () {},
              onPremium: () {},
            ),
          ),
        ),
        file,
        size: const Size(393, 520),
      );
    }
  }, skip: !_enabled);

  testWidgets('organizer panel preview', (tester) async {
    await tester.runAsync(_loadFonts);
    final provider = _SeededTournamentProvider(const []);
    for (final (current, file) in [
      (5, 'community_panel_waiting.png'),
      (9, 'community_panel_ready.png'),
    ]) {
      await _shoot(
        tester,
        provider,
        Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: CommunityOrganizerPanel(
              tournament: _t('c1', 'Soirée du jeudi', day(0, 21, 0),
                  max: 16, current: current, organizer: 'Dodo180'),
              isRegistered: true,
              onChanged: () async {},
            ),
          ),
        ),
        file,
        size: const Size(393, 330),
      );
    }
  }, skip: !_enabled);
}
