// Renders the Rankings tab (system D: header + friends toggle, season chips,
// season card, my card, podium, rows, pinned position, bottom bar) to PNG so
// the screen can be reviewed without a device. Not a test of behaviour —
// skipped unless run explicitly:
//
//   flutter test test/preview/leaderboard_preview_test.dart \
//     --dart-define=PREVIEW=true \
//     --dart-define=PREVIEW_OUT=/abs/dir
//
// Manrope is loaded from assets/fonts (the bundled family), Material Icons
// from the Flutter SDK cache.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/l10n/app_localizations.dart';
import 'package:mobile/models/season.dart';
import 'package:mobile/models/user.dart';
import 'package:mobile/screens/home/leaderboard_screen.dart';
import 'package:mobile/services/user_service.dart';
import 'package:mobile/utils/app_theme.dart';
import 'package:mobile/widgets/design_system.dart';
import 'package:mobile/widgets/season_card.dart';
import 'package:mobile/widgets/season_chips.dart';

const _enabled = bool.fromEnvironment('PREVIEW');
const _outDir = String.fromEnvironment('PREVIEW_OUT');

const me = 'u-me';

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

LeaderboardEntry _entry({
  required int position,
  required String name,
  required String rank,
  required int elo,
  required int wins,
  required int losses,
  bool premium = false,
  String? id,
}) {
  return LeaderboardEntry(
    user: User(
      id: id ?? 'u-$name',
      username: name,
      email: '',
      elo: elo,
      rank: rank,
      wins: wins,
      losses: losses,
      isPremium: premium,
    ),
    rank: position,
    wins: wins,
    losses: losses,
  );
}

class LeaderboardPreview extends StatelessWidget {
  final bool friends;
  const LeaderboardPreview({super.key, this.friends = false});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final now = DateTime(2026, 9, 7, 10);
    final seasons = [
      Season.fromJson({'number': 0, 'status': 'closed', 'hasReward': false, 'endAt': '2026-08-31T21:59:00.000Z'}),
      Season.fromJson({
        'number': 1,
        'status': 'active',
        'startedAt': '2026-08-31T22:00:00.000Z',
        'endAt': '2026-11-30T22:59:00.000Z',
        'hasReward': true,
      }),
      Season.fromJson({'number': 2, 'status': 'scheduled', 'hasReward': true}),
    ];
    final entries = [
      _entry(position: 1, name: 'Nico_Bull', rank: 'master', elo: 2412, wins: 61, losses: 12, premium: true),
      _entry(position: 2, name: 'Alex_501', rank: 'diamond', elo: 2140, wins: 52, losses: 20),
      _entry(position: 3, name: 'Sarah_T20', rank: 'diamond', elo: 2088, wins: 47, losses: 18, premium: true),
      _entry(position: 4, name: 'Tomtom_180', rank: 'diamond', elo: 2031, wins: 48, losses: 19, premium: true),
      _entry(position: 5, name: 'Julien_D', rank: 'platinum', elo: 1902, wins: 35, losses: 21),
      _entry(position: 6, name: 'Mika', rank: 'platinum', elo: 1877, wins: 29, losses: 14),
      _entry(position: 7, name: 'DODO180', rank: 'gold', elo: 1240, wins: 12, losses: 8, premium: true),
      _entry(position: 8, name: 'Vati99', rank: 'platinum', elo: 1601, wins: 12, losses: 5, id: me),
      _entry(position: 100, name: 'Un_pseudo_vraiment_long', rank: 'bronze', elo: 640, wins: 2, losses: 31),
    ];
    const standing = SeasonStanding(position: 39, elo: 1601, rank: 'gold', wins: 12, losses: 5);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: DsScreenHeader(
                title: l10n.rankings,
                actions: [
                  DsIconButton(
                    icon: Icons.people_outline_rounded,
                    iconColor: friends ? AppTheme.primaryLight : null,
                    onTap: () {},
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: SeasonChips(
                seasons: seasons,
                selectedNumber: 1,
                friendsOnly: friends,
                onSeasonSelected: (_) {},
                onSeeAll: () {},
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: SeasonCard(
                season: seasons[1],
                timeLeft: const Duration(days: 84, hours: 14),
                now: now,
                onTap: () {},
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                children: [
                  if (!friends) ...[
                    const LeaderboardMyCard(username: 'Vati99', standing: standing),
                    const SizedBox(height: 14),
                  ],
                  LeaderboardPodium(entries: entries.take(3).toList(), onTap: (_) {}),
                  const SizedBox(height: 6),
                  for (final e in entries.skip(3))
                    LeaderboardRow(entry: e, isCurrentUser: e.user.id == me, onTap: () {}),
                ],
              ),
            ),
            const LeaderboardPinnedRow(position: 39, username: 'Vati99', rank: 'platinum', elo: 1601),
          ],
        ),
      ),
      bottomNavigationBar: DsBottomBar(
        currentIndex: 4,
        onSelect: (_) {},
        centerLabel: l10n.play,
        items: [
          DsBottomBarItem(icon: Icons.bar_chart_rounded, label: l10n.stats),
          DsBottomBarItem(icon: Icons.emoji_events_outlined, label: l10n.tournament),
          DsBottomBarItem(icon: Icons.people_outline_rounded, label: l10n.friends),
          DsBottomBarItem(icon: Icons.trending_up_rounded, label: l10n.rankings),
        ],
      ),
    );
  }
}

Future<void> _render(WidgetTester tester, Widget screen, String name) async {
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
      home: RepaintBoundary(key: key, child: screen),
    ),
  );
  // Localizations and asset images (badges, shield) resolve asynchronously.
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
    final file = File('$_outDir/$name.png');
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    debugPrint('wrote ${file.path}');
  });
  expect(tester.takeException(), isNull);
}

void main() {
  testWidgets('leaderboard preview', (tester) async {
    await tester.runAsync(_loadFonts);
    await _render(tester, const LeaderboardPreview(), 'leaderboard');
    await _render(tester, const LeaderboardPreview(friends: true), 'leaderboard_friends');
  }, skip: !_enabled);
}
