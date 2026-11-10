// Renders the validated final home (mockups docs/progression/ecrans/AccFinal,
// AccFinalLong, AccFierte) to PNG so it can be compared with the mockups
// without a device: the home as it opens (390 × 844), the whole page, the S1
// player card with 3 item combinations, Match found and the profile top.
// Not a test of behaviour — skipped unless run explicitly:
//
//   flutter test test/preview/home_final_preview_test.dart \
//     --dart-define=PREVIEW=true \
//     --dart-define=PREVIEW_OUT=/abs/dir
//
// The real content (backend/src/progression/content) and the real item
// assets (backend/public/progression/items) are loaded, so metals, textures,
// emblems and badges are the ones the app downloads.
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
import 'package:mobile/models/match.dart';
import 'package:mobile/models/progression.dart';
import 'package:mobile/providers/progression_provider.dart';
import 'package:mobile/screens/challenge/challenge_api.dart';
import 'package:mobile/screens/challenge/challenge_entry.dart';
import 'package:mobile/screens/challenge/challenge_models.dart';
import 'package:mobile/screens/ghost/ghost_play_row.dart';
import 'package:mobile/screens/home/competitive_card.dart';
import 'package:mobile/screens/home/home_other_modes.dart';
import 'package:mobile/screens/home/home_quest_strip.dart';
import 'package:mobile/screens/league/league_models.dart';
import 'package:mobile/screens/league/league_store.dart';
import 'package:mobile/screens/league/league_widgets.dart';
import 'package:mobile/screens/progression/match_found_screen.dart';
import 'package:mobile/screens/profile/player_stats_screen.dart';
import 'package:mobile/screens/progression/progression_format.dart';
import 'package:mobile/services/progression_service.dart';
import 'package:mobile/utils/app_theme.dart';
import 'package:mobile/utils/rank_translation.dart';
import 'package:mobile/utils/rank_utils.dart';
import 'package:mobile/widgets/design_system.dart';
import 'package:mobile/widgets/home_tiles.dart';
import 'package:mobile/widgets/progression/player_showcase_card.dart';
import 'package:mobile/widgets/recent_matches_widget.dart';

const _enabled = bool.fromEnvironment('PREVIEW');
const _outDir = String.fromEnvironment('PREVIEW_OUT');
const _me = 'u-me';

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

/// The served content, built from the backend's data files, with each item's
/// asset copied where ProgressionAssetCache looks for it.
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
  final league = read('defs/league.json');
  return {
    'version': 'preview',
    'curve': levels['curve'],
    'prestige': levels['prestige'],
    'metals': read('metals.json')['metals'],
    'items': items,
    'levels': levels['levels'],
    'defs': {'league': league['items']},
    // The constants the server serves (XP_RULES, ghost.json, challenge).
    'xp': {'ranked': 60, 'rankedWin': 40, 'friendly': 30, 'training': 30, 'ghost': 40, 'challenge': 50},
  };
}

class _Combo {
  final String name;
  final String? title;
  final int level;
  final String frame;
  final String background;
  final String avatar;
  final String monogram;
  final List<PublicBadge> badges;
  final bool crown;
  final bool own;
  const _Combo(this.name, this.title, this.level, this.frame, this.background, this.avatar, this.monogram, this.badges,
      {this.crown = false, this.own = false});

  PublicCosmetics get cosmetics => PublicCosmetics(
        level: level,
        avatar: avatar,
        monogram: monogram,
        frame: frame,
        background: background,
        title: title,
        badges: badges,
      );
}

const _n1 = PublicBadge(id: 'b1', badgeId: 'badge.daily-first', tier: 'gold', date: '2026-11-08');
const _b180 = PublicBadge(id: 'b2', badgeId: 'badge.machine-a-180', tier: 'gold');
const _moy = PublicBadge(id: 'b3', badgeId: 'badge.grosse-moyenne', tier: 'silver');

// AccFierte's three columns: liège / laiton / monogram T20 (own, premium);
// carbone / obsidienne / trophy (premium); dans le mille / légende / 1 star.
const _combos = [
  _Combo('Dodo180', 'title.big-fish', 23, 'frame.laiton', 'background.liege', 'avatar.monogramme-acier', 'T20',
      [_n1, _b180, _moy], crown: true, own: true),
  _Combo('Kev_D20', 'title.machine-a-180', 41, 'frame.obsidienne', 'background.carbone', 'avatar.trophee', 'KD',
      [_b180, _moy], crown: true),
  _Combo('LaFleche', 'title.legende', 63, 'frame.legende', 'background.dans-le-mille', 'avatar.monogramme-legende', 'D16',
      [_n1, _b180, _moy]),
];

QuestsSnapshot _quests() => QuestsSnapshot.fromJson({
      'daily': {
        'periodKey': '2026-11-08',
        'quests': [
          {'id': 'q1', 'questId': 'q016', 'period': 'daily', 'text': {'fr': 'Marque une volée à 100+', 'en': 'Score a 100+ visit'}, 'progress': 1, 'threshold': 1, 'xp': 40, 'status': 'completed'},
          {'id': 'q2', 'questId': 'q021', 'period': 'daily', 'text': {'fr': '5 triples dans une partie', 'en': '5 trebles in a game'}, 'progress': 3, 'threshold': 5, 'xp': 40, 'status': 'active'},
          {'id': 'q3', 'questId': 'q030', 'period': 'daily', 'text': {'fr': 'Joue 2 matchs classés', 'en': 'Play 2 ranked matches'}, 'progress': 2, 'threshold': 2, 'xp': 30, 'status': 'completed'},
        ],
      },
      'weekly': {'periodKey': '2026-11-02', 'quests': []},
    });

Match _match(String id, String opponent, bool won, int my, int their, int elo, Duration ago) => Match(
      id: id,
      player1Id: _me,
      player2Id: 'u-$opponent',
      player1Username: 'Dodo180',
      player2Username: opponent,
      player1Score: my,
      player2Score: their,
      winnerId: won ? _me : 'u-$opponent',
      player1EloChange: elo,
      player2EloChange: -elo,
      createdAt: DateTime.now().subtract(ago),
      status: 'completed',
      matchType: 'ranked',
      seriesId: 's-$id',
      seriesPlayer1LegsWon: my,
      seriesPlayer2LegsWon: their,
    );

void _seedStores() {
  ChallengeStore.instance.debugSeed(
    ChallengeToday.fromJson({
      'date': '2026-11-08',
      'format': {
        'id': 'cricket-30',
        'name': {'fr': 'Cricket · 30 fléchettes', 'en': 'Cricket · 30 darts'},
        'short': {'fr': 'Cricket · 30', 'en': 'Cricket · 30'},
        'rule': {'fr': '30 fléchettes.', 'en': '30 darts.'},
        'tag': {'fr': 'cricket', 'en': 'cricket'},
        'mode': 'cricket_marks',
        'params': {'darts': 30},
        'score': {'order': 'desc', 'unit': {'fr': 'marques', 'en': 'marks'}, 'max': 90},
        'tiebreak': {'order': 'desc', 'label': {'fr': 'x', 'en': 'x'}},
        'durationMin': 4,
      },
      'board': {'rank': 'gold', 'ranks': ['gold'], 'open': true, 'players': 12, 'eloBonus': 24},
      'players': 40,
      'ranked': null,
      'streak': {'current': 0, 'best': 3, 'freezeAvailable': true, 'days': []},
    }),
  );
  LeagueStore.instance.debugSeed(LeagueSnapshot.fromJson({
    'enabled': true,
    'weekKey': '2026-11-02',
    'weekNumber': 45,
    'endsAt': DateTime.now().add(const Duration(hours: 20)).toUtc().toIso8601String(),
    'league': {'id': 'cuivre', 'order': 2, 'name': {'fr': 'Cuivre', 'en': 'Copper'}, 'color': '#E8A27A', 'colors': ['#E8A27A', '#8C4A26', '#D98C5F']},
    'ladder': [],
    'state': 'open',
    'group': {
      'id': 'g1',
      'size': 20,
      'promoteCount': 5,
      'relegateCount': 5,
      'standings': [
        for (var i = 1; i <= 20; i++)
          {'position': i, 'userId': i == 6 ? _me : 'u$i', 'username': 'P$i', 'points': 400 - i * 10, 'isMe': i == 6},
      ],
    },
    'me': {'position': 6, 'points': 340},
  }));
  GhostHomeStore.instance.debugSeed();
}

Widget _app(Widget child, ProgressionProvider p) => ChangeNotifierProvider<ProgressionProvider>.value(
      value: p,
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

/// The home tab as play_screen.dart builds it (same widgets, demo data).
class _HomeBody extends StatelessWidget {
  final bool scroll;
  const _HomeBody({this.scroll = true});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final p = context.watch<ProgressionProvider>();
    final xp = p.content?.xp;
    final a = _combos.first;
    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PlayerShowcaseCard(
          username: a.name,
          rank: 'gold',
          cosmetics: a.cosmetics,
          isPremium: true,
          level: a.level,
          onEdit: () {},
          footer: HomeQuestStrip.fromProvider(context),
        ),
        const SizedBox(height: 12),
        CompetitiveCard(
          leading: CompetitiveCard.rankImage(RankUtils.getRankIcon('gold')),
          label: '${l10n.competitiveModeTitle} · #17',
          value: formatXp(1409),
          progress: rankProgress('gold', 1409),
          caption: l10n.homeNextRankIn(RankTranslation.translate(l10n, nextRank('gold')), eloNeededForNextRank('gold', 1409)),
          actionLabel: l10n.play,
          actionXp: l10n.homeXpGain(xp!.ranked!),
          onTap: () {},
          liveRanked: 3,
          liveTotal: 3,
        ),
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              HomeSectionTitle(l10n.questsToday),
              HomeTileRow(children: [
                ChallengeTodayTile(xp: xp.challenge),
                LeagueTodayTile(xpForPosition: p.content?.leagueXpFor),
              ]),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // « Jouer autrement » without the ghost tile (CONTRACT §14.12).
        HomeOtherModes(xp: xp, onFriend: () {}, onLocal: () {}, onTraining: () {}),
        const SizedBox(height: 16),
        DsSectionHeader(title: l10n.recentMatches, actionLabel: l10n.viewAll, onAction: () {}),
        const SizedBox(height: 12),
        RecentMatchesWidget(
          userId: _me,
          matches: [
            _match('a', 'Kev_D20', true, 2, 1, 16, const Duration(hours: 2)),
            _match('b', 'LaFleche', false, 1, 2, -14, const Duration(days: 1)),
            _match('c', 'Juju180', true, 2, 0, 12, const Duration(days: 1, hours: 3)),
          ],
        ),
      ],
    );
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: DsBrandHeader(actions: [
                DsIconButton(icon: Icons.chat_bubble_outline_rounded, onTap: () {}),
                DsIconButton(icon: Icons.settings_outlined, onTap: () {}),
              ]),
            ),
            Expanded(
              child: SingleChildScrollView(
                physics: scroll ? null : const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                child: column,
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
          DsBottomBarItem(icon: Icons.emoji_events_outlined, label: l10n.tournament),
          DsBottomBarItem(icon: Icons.people_outline_rounded, label: l10n.friends),
          DsBottomBarItem(icon: Icons.trending_up_rounded, label: l10n.rankings),
        ],
      ),
    );
  }
}

/// The three AccFierte combinations, one card each (with the home strip on
/// the first, as in the mockup's first column).
class _Combos extends StatelessWidget {
  final int index;
  const _Combos(this.index);

  @override
  Widget build(BuildContext context) {
    final c = _combos[index];
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Align(
          alignment: Alignment.topCenter,
          child: PlayerShowcaseCard(
            username: c.name,
            rank: 'gold',
            cosmetics: c.cosmetics,
            isPremium: c.crown,
            level: c.level,
            onEdit: c.own ? () {} : null,
            footer: c.own ? HomeQuestStrip.fromProvider(context) : null,
          ),
        ),
      ),
    );
  }
}

/// The top of the profile: my card (with « Modifier »), then the rank row;
/// another player's card under it (no « Modifier »).
class _ProfileTop extends StatelessWidget {
  const _ProfileTop();

  @override
  Widget build(BuildContext context) {
    final a = _combos[0];
    final b = _combos[1];
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PlayerShowcaseCard(username: a.name, rank: 'gold', cosmetics: a.cosmetics, isPremium: true, onEdit: () {}),
            const SizedBox(height: 10),
            const ProfileRankRow(rank: 'gold', elo: 1409),
            const SizedBox(height: 28),
            PlayerShowcaseCard(username: b.name, rank: 'master', cosmetics: b.cosmetics, isPremium: true),
            const SizedBox(height: 10),
            const ProfileRankRow(rank: 'master', elo: 2512),
          ],
        ),
      ),
    );
  }
}

/// Compétitif in its other states: placement, Master, a match to resume
/// (nothing live), ranked locked by a tournament, a tournament match ready.
class _CompetitiveStates extends StatelessWidget {
  const _CompetitiveStates();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    Widget gap() => const SizedBox(height: 12);
    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CompetitiveCard(
              leading: CompetitiveCard.rankImage(RankUtils.getRankIcon('unranked')),
              label: '${l10n.competitiveModeTitle} · ${l10n.homePlacementLabel}',
              value: '2 / 4',
              progress: 0.5,
              caption: l10n.homePlacementLeft(2),
              actionLabel: l10n.play,
              onTap: () {},
              liveRanked: 1,
              liveTotal: 1,
            ),
            gap(),
            CompetitiveCard(
              leading: CompetitiveCard.rankImage(RankUtils.getRankIcon('master')),
              label: '${l10n.competitiveModeTitle} · #2',
              value: formatXp(2512),
              progress: 1,
              caption: l10n.maxRankReached,
              actionLabel: l10n.play,
              actionXp: l10n.homeXpGain(60),
              onTap: () {},
              liveTotal: 2,
            ),
            gap(),
            CompetitiveCard(
              leading: CompetitiveCard.rankImage(RankUtils.getRankIcon('gold')),
              label: '${l10n.competitiveModeTitle} · #17',
              value: formatXp(1409),
              progress: rankProgress('gold', 1409),
              caption: l10n.homeMatchInProgress('Kev_D20'),
              actionLabel: l10n.homeResume,
              onTap: () {},
            ),
            gap(),
            CompetitiveCard(
              leading: CompetitiveCard.rankImage(RankUtils.getRankIcon('gold')),
              label: '${l10n.activeTournament} · Samedi soir',
              value: formatXp(1409),
              progress: rankProgress('gold', 1409),
              caption: l10n.homeRankedLockedCaption,
              actionLabel: l10n.play,
            ),
            gap(),
            CompetitiveCard(
              leading: CompetitiveCard.iconDisc(Icons.emoji_events_outlined),
              label: '${l10n.tournament} · Demi-finale',
              value: 'Tournoi du samedi',
              largeValue: false,
              caption: l10n.homeTournamentReadyCaption,
              actionLabel: l10n.homeJoin,
              onTap: () {},
              liveRanked: 3,
              liveTotal: 5,
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _shoot(WidgetTester tester, ProgressionProvider p, Widget screen, Size size, String file) async {
  final key = GlobalKey();
  await tester.binding.setSurfaceSize(size);
  tester.view.devicePixelRatio = 3;
  await tester.pumpWidget(_app(RepaintBoundary(key: key, child: screen), p));
  // Localizations, asset images, SVG pictures and WebP textures resolve
  // asynchronously (real file IO): give them real time.
  await tester.runAsync(() async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
  });
  await tester.pump();
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
  late ProgressionProvider provider;

  setUpAll(() async {
    final cache = Directory.systemTemp.createTempSync('home-final-preview-');
    ProgressionAssetCache.debugDirectory = cache;
    provider = ProgressionProvider()
      ..debugSeed(
        content: ProgressionContent.fromJson(_content(cache)),
        summary: const ProgressionSummary(level: 23, xpIntoLevel: 1010, xpToNext: 1580),
        quests: _quests(),
      );
    _seedStores();
  });

  testWidgets('home final previews', (tester) async {
    await tester.runAsync(_loadFonts);
    await _shoot(tester, provider, const _HomeBody(), const Size(390, 844), 'accueil_final.png');
    await _shoot(tester, provider, const _HomeBody(scroll: false), const Size(390, 1030), 'accueil_final_long.png');
    await _shoot(tester, provider, const _Combos(0), const Size(390, 232), 'carte_s1_liege_laiton_monogramme.png');
    await _shoot(tester, provider, const _Combos(1), const Size(390, 188), 'carte_s1_carbone_obsidienne_trophee.png');
    await _shoot(tester, provider, const _Combos(2), const Size(390, 188), 'carte_s1_dans_le_mille_legende_etoile.png');
    await _shoot(
      tester,
      provider,
      MatchFoundScreen(
        subtitle: 'Série classée · BO3 · 501',
        recordLine: 'Bilan 7 – 5',
        me: MatchFoundPlayer(username: 'Dodo180', rank: 'gold', elo: 1409, cosmetics: _combos[0].cosmetics, isPremium: true),
        opponent: MatchFoundPlayer(username: 'LaFleche', rank: 'platinum', elo: 1612, cosmetics: _combos[2].cosmetics),
      ),
      const Size(390, 844),
      'match_trouve.png',
    );
    await _shoot(
      tester,
      provider,
      MatchFoundScreen(
        subtitle: 'Série classée · BO3 · 501',
        me: MatchFoundPlayer(username: 'Dodo180', rank: 'gold', elo: 1409, cosmetics: _combos[0].cosmetics, isPremium: true),
        opponent: MatchFoundPlayer(username: 'Kev_D20', rank: 'gold', elo: 1388, cosmetics: _combos[1].cosmetics),
      ),
      const Size(375, 520),
      'match_trouve_petit_ecran.png',
    );
    await _shoot(tester, provider, const _ProfileTop(), const Size(390, 520), 'profil_haut.png');
    await _shoot(tester, provider, const _CompetitiveStates(), const Size(390, 760), 'competitif_etats.png');
    expect(tester.takeException(), isNull);
  }, skip: !_enabled);
}
