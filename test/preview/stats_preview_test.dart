// Renders the Stats tab (system D: header, Matchs / Entraînement segmented
// control, standing cards, form, record, breakdowns, records; training cards)
// to PNG so the screens can be reviewed without a device or a backend. The
// pure widgets are fed fake data; the self-loading sections are bypassed.
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
import 'package:mobile/models/stats_summary.dart';
import 'package:mobile/models/training.dart';
import 'package:mobile/screens/home/stats/comparison_section.dart';
import 'package:mobile/screens/home/stats/matches_stats_tab.dart';
import 'package:mobile/screens/home/stats/stats_filter_sheet.dart';
import 'package:mobile/screens/home/stats/stats_pages.dart';
import 'package:mobile/screens/home/stats/stats_widgets.dart';
import 'package:mobile/screens/home/training_stats_tab.dart';
import 'package:mobile/utils/app_theme.dart';
import 'package:mobile/widgets/design_system.dart';

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
  cohort: PercentileCohort(byRank: true, rank: 'platinum', size: 214, windowDays: 90, minLegs: 20),
  eligible: true,
  legs: 64,
  legsUntilEligible: 0,
  overall: 88,
  metrics: [
    PercentileEntry(key: PercentileMetric.average, value: 62.4, percentile: 78, median: 55, higherIsBetter: true),
    PercentileEntry(key: PercentileMetric.checkoutPct, value: 38.5, percentile: 91, median: 30, higherIsBetter: true),
    PercentileEntry(key: PercentileMetric.dartsToWinLeg, value: 18.2, percentile: 64, median: 20, higherIsBetter: false),
    PercentileEntry(key: PercentileMetric.tonRate, value: 32, percentile: 57, median: 28, higherIsBetter: true),
    PercentileEntry(key: PercentileMetric.bustRate, value: 4.1, percentile: 45, median: 4, higherIsBetter: false),
  ],
  strongest: PercentileMetric.checkoutPct,
  weakest: PercentileMetric.bustRate,
);

StatsSummary _summary() => StatsSummary(
      legs: 120,
      record: const StatsRecordLine(wins: 41, losses: 29, winRate: 58.6),
      form: const StatsForm(
        average: 61.8,
        previousAverage: 58.2,
        delta: 3.6,
        curve: [55, 57, 56, 59, 61, 60, 63, 62, 64, 61.8],
        sampleLegs: 20,
      ),
      scoring: const StatsScoring(
        average: 61.8,
        bestVisit: 180,
        totalVisits: 812,
        buckets: [
          StatsBucket(label: '180', count: 3),
          StatsBucket(label: '140+', count: 41),
          StatsBucket(label: '100+', count: 164),
          StatsBucket(label: '60+', count: 302),
          StatsBucket(label: '<60', count: 302),
        ],
      ),
      finishing: const StatsFinishing(
        checkoutPct: 38.5,
        doubles: [
          StatsRate(label: 'D20', hits: 22, attempts: 50, pct: 44),
          StatsRate(label: 'D16', hits: 19, attempts: 49, pct: 39),
          StatsRate(label: 'D8', hits: 9, attempts: 29, pct: 31),
          StatsRate(label: 'D10', hits: 4, attempts: 18, pct: 22),
          StatsRate(label: 'D18', hits: 2, attempts: 11, pct: 18),
        ],
      ),
      records: [
        StatsRecord(key: StatsRecordKey.bestCheckout, value: 121, matchId: 'm1', opponentUsername: 'DODO180', playedAt: DateTime(2026, 8, 12)),
        StatsRecord(key: StatsRecordKey.bestLeg, value: 15, matchId: 'm2', opponentUsername: 'Kev_Darts', playedAt: DateTime(2026, 8, 3)),
        StatsRecord(key: StatsRecordKey.bestLegAverage, value: 98.3, matchId: 'm3', opponentUsername: 'Marion_B', playedAt: DateTime(2026, 7, 28)),
        StatsRecord(key: StatsRecordKey.longestWinStreak, value: 7, matchId: 'm4'),
      ],
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

class _MatchesPreview extends StatelessWidget {
  const _MatchesPreview();

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
  await tester.pump();

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
    await _render(tester, const _MatchesPreview(), const Size(393, 2300), 'stats_matches');
  }, skip: !_enabled);

  testWidgets('stats training preview', (tester) async {
    await _render(tester, const _TrainingPreview(), const Size(393, 900), 'stats_training');
  }, skip: !_enabled);
}
