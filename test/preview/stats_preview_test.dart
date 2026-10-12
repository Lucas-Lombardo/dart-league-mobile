// Renders the Stats tab (header, Matchs / Entraînement segmented control,
// level card, impacts, doubles, form, record, records; training cards) and a
// player's page to PNG so the screens can be reviewed without a device or a
// backend. The pure widgets are fed production figures exported on
// 2026-10-06; the self-loading sections are bypassed.
// Not a test of behaviour — skipped unless run explicitly:
//
//   flutter test test/preview/stats_preview_test.dart \
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
import 'package:mobile/models/player_percentiles.dart';
import 'package:mobile/models/player_profile_stats.dart';
import 'package:mobile/models/stats_summary.dart';
import 'package:mobile/models/training.dart';
import 'package:mobile/screens/home/stats/comparison_section.dart';
import 'package:mobile/screens/home/stats/matches_stats_tab.dart';
import 'package:mobile/screens/home/stats/stats_filter_sheet.dart';
import 'package:mobile/screens/home/stats/stats_pages.dart';
import 'package:mobile/screens/home/stats/stats_widgets.dart';
import 'package:mobile/screens/home/training_stats_tab.dart';
import 'package:mobile/screens/profile/player_stats_screen.dart';
import 'package:mobile/services/user_service.dart';
import 'package:mobile/utils/app_theme.dart';
import 'package:mobile/widgets/design_system.dart';
import 'package:mobile/widgets/player_card.dart';

import 'impacts_fixture.dart';

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

const _percentiles = PlayerPercentiles(
  cohort: PercentileCohort(byRank: true, rank: 'platinum', size: 20, windowDays: 90, minLegs: 10),
  eligible: true,
  legs: 208,
  legsUntilEligible: 0,
  level: PlayerLevel(
    overall: 40,
    metrics: [
      LevelEntry(key: LevelMetric.average, value: 47.7, percentile: 33, median: 48.9),
      LevelEntry(key: LevelMetric.first9, value: 52.7, percentile: 28, median: 55.2),
      LevelEntry(key: LevelMetric.scoringAverage, value: 54.5, percentile: 28, median: 55.7),
      LevelEntry(key: LevelMetric.finishingAverage, value: 33.4, percentile: 28, median: 35.2),
      LevelEntry(key: LevelMetric.checkoutPct, value: 13.8, percentile: 18, median: 18),
    ],
  ),
);

StatsSummary _summary() => StatsSummary(
      legs: 208,
      record: const StatsRecordLine(wins: 114, losses: 93, winRate: 55.1),
      form: const StatsForm(
        average: 45.9,
        previousAverage: 52,
        delta: -6.1,
        curve: [50.1, 49.3, 48.8, 45.4, 44.8, 40.1, 37.3, 39.6, 41.1, 39.2, 46.3, 50, 51.6, 48.3, 51.5, 45.5, 46.3, 47.2, 49.2, 46.7],
        sampleLegs: 20,
      ),
      scoring: const StatsScoring(average: 47.7, bestVisit: 180, totalVisits: 1791),
      finishing: const StatsFinishing(
        checkoutPct: 13.8,
        doubles: [
          StatsRate(label: 'D16', hits: 14, attempts: 98, pct: 14.3),
          StatsRate(label: 'D8', hits: 8, attempts: 83, pct: 9.6),
          StatsRate(label: 'D4', hits: 13, attempts: 71, pct: 18.3),
          StatsRate(label: 'D10', hits: 13, attempts: 69, pct: 18.8),
          StatsRate(label: 'D2', hits: 9, attempts: 61, pct: 14.8),
          StatsRate(label: 'D20', hits: 5, attempts: 59, pct: 8.5),
        ],
      ),
      records: [
        StatsRecord(key: StatsRecordKey.bestCheckout, value: 141, matchId: 'm1', opponentUsername: 'Dodo180', playedAt: DateTime(2026, 8, 3)),
        StatsRecord(key: StatsRecordKey.bestLeg, value: 18, matchId: 'm2', opponentUsername: 'Nico', playedAt: DateTime(2026, 8, 21)),
        StatsRecord(key: StatsRecordKey.bestLegAverage, value: 99.3, matchId: 'm3', opponentUsername: 'Dodo180', playedAt: DateTime(2026, 8, 3)),
        StatsRecord(key: StatsRecordKey.longestWinStreak, value: 11, matchId: 'm4', opponentUsername: 'Dodo180', playedAt: DateTime(2026, 8, 4)),
      ],
      impacts: vatiImpacts,
    );

/// lucas pdc paulhan, the profile the redesign was drawn from.
final _player = PlayerProfileStats(
  percentiles: const PlayerPercentiles(
    cohort: PercentileCohort(byRank: false, rank: 'master', size: 191, windowDays: 90, minLegs: 10),
    eligible: true,
    legs: 236,
    legsUntilEligible: 0,
    level: PlayerLevel(
      overall: 99.2,
      metrics: [
        LevelEntry(key: LevelMetric.average, value: 59.8, percentile: 99.2, median: 41.5),
        LevelEntry(key: LevelMetric.first9, value: 68.6, percentile: 99.2, median: 47.4),
        LevelEntry(key: LevelMetric.scoringAverage, value: 68.2, percentile: 99.7, median: 47.9),
        LevelEntry(key: LevelMetric.finishingAverage, value: 42.9, percentile: 97.1, median: 29.1),
        LevelEntry(key: LevelMetric.checkoutPct, value: 24.6, percentile: 97.1, median: 11.6),
      ],
    ),
  ),
  impacts: paulhanImpacts,
  doubles: const [
    StatsRate(label: 'D16', hits: 25, attempts: 102, pct: 24.5),
    StatsRate(label: 'D8', hits: 28, attempts: 92, pct: 30.4),
    StatsRate(label: 'D20', hits: 28, attempts: 84, pct: 33.3),
    StatsRate(label: 'D1', hits: 12, attempts: 83, pct: 14.5),
    StatsRate(label: 'D2', hits: 20, attempts: 64, pct: 31.3),
    StatsRate(label: 'Bull', hits: 2, attempts: 45, pct: 4.4),
    StatsRate(label: 'D10', hits: 14, attempts: 45, pct: 31.1),
  ],
);

final _playerStats = UserStats(
  totalMatches: 106,
  winRate: 83,
  averageScore: 59.5,
  threeDartAverage: 59.8,
  count180s: 17,
  currentStreak: 43,
  wins: 88,
  losses: 18,
  legsCounted: 236,
  biggestCheckout: 133,
  finishingDoublePercentage: 24.6,
);

TrainingTypeStats _training(TrainingType type, {int sessions = 0, num? best, num? avg, num? last, List<BotModeStats>? modes, num? winRate}) =>
    TrainingTypeStats(
      type: type,
      sessions: sessions,
      bestScore: best,
      averageScore: avg,
      lastScore: last,
      lastPlayedAt: null,
      totalDarts: 0,
      higherIsBetter: type.higherIsBetter,
      winRate: winRate,
      modes: modes,
    );

Widget _shell(AppLocalizations l10n, int tab, Widget body) {
  return Scaffold(
    body: SafeArea(
      bottom: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: DsScreenHeader(
              title: l10n.stats,
              actions: [DsIconButton(icon: Icons.history_rounded, onTap: () {})],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: StatsSegmentedControl(
              labels: [l10n.matchStatsTab, l10n.trainingStatsTab],
              index: tab,
              onChanged: (_) {},
            ),
          ),
          Expanded(child: body),
        ],
      ),
    ),
  );
}

class MatchesPreview extends StatelessWidget {
  const MatchesPreview({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _shell(
      l10n,
      0,
      StatsOverviewPage(
        summary: _summary(),
        comparison: const ComparisonCards(data: _percentiles),
        filterBar: StatsFilterBar(
          filter: const StatsFilter(period: StatsPeriod.last30Days, modes: {MatchMode.ranked}),
          onTap: () {},
        ),
      ),
    );
  }
}

/// The player page, composed the way PlayerStatsScreen lays it out. [profile]
/// null renders what an older backend (or a failed request) leaves behind.
class _PlayerPreview extends StatelessWidget {
  final PlayerProfileStats? profile;

  const _PlayerPreview({this.profile});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('lucas pdc paulhan'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: DsIconButton(icon: Icons.chat_bubble_outline_rounded, onTap: () {}),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PlayerCard(
              rank: 'master',
              username: 'lucas pdc paulhan',
              isPremium: true,
              subline: Text(l10n.master, style: AppTheme.caption.copyWith(fontSize: 13)),
              value: '2714',
              valueLabel: l10n.eloLabel,
              progress: 1,
            ),
            const SizedBox(height: 14),
            PlayerDartBlocks(profile: profile, stats: _playerStats, isSelf: false),
            PlayerRecordCard(stats: _playerStats),
            const SizedBox(height: 14),
            DsListRow(
              leading: const Icon(Icons.compare_arrows_rounded, size: 22, color: Color(0xFFCBD5E1)),
              title: l10n.headToHeadTitle,
              onTap: () {},
            ),
            const SizedBox(height: 28),
            OutlinedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
              label: Text(l10n.addFriendButton),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrainingPreview extends StatelessWidget {
  const _TrainingPreview();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cards = [
      _training(TrainingType.highScore, sessions: 12, best: 623, avg: 512.4, last: 540),
      _training(
        TrainingType.botTraining,
        sessions: 18,
        avg: 58.2,
        winRate: 0.61,
        modes: [
          BotModeStats(mode: '501', sessions: 11, winRate: 0.64, averageScore: 59.1, lastPlayedAt: null),
          BotModeStats(mode: '301', sessions: 4, winRate: 0.5, averageScore: 55.2, lastPlayedAt: null),
          BotModeStats(mode: 'cricket_score', sessions: 3, winRate: 0.67, averageScore: 2.4, lastPlayedAt: null),
        ],
      ),
      _training(TrainingType.importantDoubles, sessions: 5, best: 44, avg: 31.2, last: 38),
      _training(TrainingType.aroundTheClock),
    ];
    return _shell(
      l10n,
      1,
      SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DsSectionHeader(title: l10n.trainingStatsHeader),
            const SizedBox(height: 12),
            for (var i = 0; i < cards.length; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              TrainingStatCard(
                stats: cards[i],
                onTap: () {},
                onProgress: cards[i].type == TrainingType.importantDoubles ? () {} : null,
              ),
            ],
            const SizedBox(height: 14),
            ElevatedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.play_arrow_rounded, size: 20),
              label: Text(dsSentence(l10n.trainingStartNewSession)),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _render(WidgetTester tester, Widget page, Size size, String name) async {
  await tester.runAsync(_loadFonts);
  final key = GlobalKey();
  await tester.binding.setSurfaceSize(size);
  tester.view.devicePixelRatio = 2;
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
      home: RepaintBoundary(key: key, child: page),
    ),
  );
  await tester.runAsync(() async {
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  });
  // Long enough for the impact boards to land their last dart.
  await tester.pump(const Duration(seconds: 4));

  final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('$_outDir/$name.png');
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    debugPrint('wrote ${file.path}');
  });
  expect(tester.takeException(), isNull);
}

void main() {
  testWidgets('stats matches preview', (tester) async {
    await _render(tester, const MatchesPreview(), const Size(393, 2300), 'stats_matches');
  }, skip: !_enabled);

  testWidgets('player page preview', (tester) async {
    await _render(tester, _PlayerPreview(profile: _player), const Size(393, 1700), 'player_page');
  }, skip: !_enabled);

  testWidgets('player page preview, career figures only', (tester) async {
    await _render(tester, const _PlayerPreview(), const Size(393, 900), 'player_page_fallback');
  }, skip: !_enabled);

  testWidgets('stats training preview', (tester) async {
    await _render(tester, const _TrainingPreview(), const Size(393, 900), 'stats_training');
  }, skip: !_enabled);
}
