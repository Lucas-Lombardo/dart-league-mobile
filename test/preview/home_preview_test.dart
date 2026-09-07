// Renders the home tab (system D: Manrope, player card, Compétitif row,
// mode tiles, live row, recent matches, bottom bar) to PNG so the screen can
// be reviewed without a device. Not a test of behaviour — skipped unless run
// explicitly:
//
//   flutter test test/preview/home_preview_test.dart \
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
import 'package:mobile/models/match.dart';
import 'package:mobile/utils/app_theme.dart';
import 'package:mobile/widgets/design_system.dart';
import 'package:mobile/widgets/live_matches_pill.dart';
import 'package:mobile/widgets/player_card.dart';
import 'package:mobile/widgets/recent_matches_widget.dart';

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

Match _match({
  required String id,
  required String opponent,
  required bool won,
  required int myLegs,
  required int theirLegs,
  required int elo,
  required DateTime at,
  bool premium = false,
  String type = 'ranked',
}) {
  return Match(
    id: id,
    player1Id: me,
    player2Id: 'u-$opponent',
    player1Username: 'Vati99',
    player2Username: opponent,
    player2IsPremium: premium,
    player1Score: myLegs,
    player2Score: theirLegs,
    winnerId: won ? me : 'u-$opponent',
    player1EloChange: elo,
    player2EloChange: -elo,
    createdAt: at,
    status: 'completed',
    matchType: type,
    seriesId: 's-$id',
    seriesPlayer1LegsWon: myLegs,
    seriesPlayer2LegsWon: theirLegs,
  );
}

class _HomePreview extends StatelessWidget {
  const _HomePreview();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final now = DateTime.now();
    final matches = [
      _match(id: 'a', opponent: 'DODO180', won: true, myLegs: 2, theirLegs: 1, elo: 18, at: now.subtract(const Duration(hours: 2)), premium: true),
      _match(id: 'b', opponent: 'Tomtom_180', won: false, myLegs: 1, theirLegs: 2, elo: -14, at: now.subtract(const Duration(days: 1, hours: 3))),
      _match(id: 'c', opponent: 'Kev_Darts', won: true, myLegs: 2, theirLegs: 0, elo: 11, at: now.subtract(const Duration(days: 3))),
      _match(id: 'd', opponent: 'Marion_B', won: true, myLegs: 2, theirLegs: 1, elo: 9, at: now.subtract(const Duration(days: 5))),
    ];
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: DsBrandHeader(
                actions: [
                  DsIconButton(icon: Icons.chat_bubble_outline_rounded, onTap: () {}, badge: const DsBadge(count: 2)),
                  DsIconButton(icon: Icons.settings_outlined, onTap: () {}),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    PlayerCard(
                      rank: 'platinum',
                      username: 'Vati99',
                      isPremium: true,
                      subline: Text('Platine · #39', style: AppTheme.caption.copyWith(fontSize: 13)),
                      value: '1601',
                      valueLabel: l10n.eloLabel,
                      progress: 1 / 400,
                      footerLeft: Text.rich(
                        TextSpan(
                          style: AppTheme.caption.copyWith(color: const Color(0xFFCBD5E1)),
                          children: const [
                            TextSpan(text: 'Diamant dans '),
                            TextSpan(text: '+399 pts', style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
                          ],
                        ),
                      ),
                      footerRight: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Saison 1 · 84 j', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.primaryLight)),
                          Icon(Icons.expand_more_rounded, size: 16, color: AppTheme.primaryLight),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    DsPrimaryRow(
                      icon: Icons.military_tech_outlined,
                      title: l10n.competitiveModeTitle,
                      subtitle: '${l10n.homeCompetitiveSubtitle} · 136 ${l10n.activityMatchesLabel(12).toLowerCase()}',
                      onTap: () {},
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(child: DsTile(icon: Icons.people_outline_rounded, label: l10n.friendModeTitle, onTap: () {})),
                        const SizedBox(width: 10),
                        Expanded(child: DsTile(icon: Icons.smartphone_outlined, label: l10n.localModeTitle, onTap: () {})),
                        const SizedBox(width: 10),
                        Expanded(child: DsTile(icon: Icons.fitness_center_rounded, label: l10n.trainingPlayCardTitle, onTap: () {})),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const LiveMatchesPill(count: 3),
                    const SizedBox(height: 28),
                    DsSectionHeader(title: l10n.recentMatches, actionLabel: l10n.viewAll, onAction: () {}),
                    const SizedBox(height: 12),
                    RecentMatchesWidget(matches: matches, userId: me),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: DsBottomBar(
        currentIndex: 2,
        onSelect: (_) {},
        centerLabel: l10n.play,
        items: [
          DsBottomBarItem(icon: Icons.bar_chart_rounded, label: l10n.stats),
          DsBottomBarItem(icon: Icons.emoji_events_outlined, label: l10n.tournament, badge: const DsBadge(count: 1)),
          DsBottomBarItem(icon: Icons.people_outline_rounded, label: l10n.friends),
          DsBottomBarItem(icon: Icons.trending_up_rounded, label: l10n.rankings),
        ],
      ),
    );
  }
}

void main() {
  testWidgets('home preview', (tester) async {
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
        home: RepaintBoundary(key: key, child: const _HomePreview()),
      ),
    );
    // Localizations and asset images (badge, shield) resolve asynchronously.
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
      final file = File('$_outDir/home.png');
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      debugPrint('wrote ${file.path}');
    });
    expect(tester.takeException(), isNull);
  }, skip: !_enabled);
}
