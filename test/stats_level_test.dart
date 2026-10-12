import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/l10n/app_localizations.dart';
import 'package:mobile/models/player_percentiles.dart';
import 'package:mobile/models/player_profile_stats.dart';
import 'package:mobile/models/stats_impacts.dart';
import 'package:mobile/models/stats_summary.dart';
import 'package:mobile/screens/home/stats/comparison_section.dart';
import 'package:mobile/screens/home/stats/impacts_card.dart';
import 'package:mobile/screens/home/stats/level_card.dart';
import 'package:mobile/screens/profile/player_stats_screen.dart';
import 'package:mobile/services/user_service.dart';
import 'package:mobile/widgets/impact_board.dart';
import 'package:mobile/widgets/virtual_dartboard.dart';

/// The stats pages lead with five figures and two boards. What is pinned here
/// is what a player would notice being wrong: a figure placed against nobody,
/// a treble drawn in a single bed, a page left blank by an older backend.

Map<String, dynamic> _cohort({String scope = 'rank'}) => {
  'scope': scope,
  'rank': 'platinum',
  'size': 20,
  'windowDays': 90,
  'minLegs': 10,
};

Map<String, dynamic> _entry(String key, double value, [double? percentile]) => {
  'key': key,
  'value': value,
  'percentile': percentile,
  'median': percentile == null ? null : 50.0,
};

Map<String, dynamic> _percentilesJson({bool placed = true, bool eligible = true}) => {
  'cohort': _cohort(),
  'eligible': eligible,
  'legs': 208,
  'legsUntilEligible': 0,
  'overall': placed ? 40 : null,
  'metrics': <dynamic>[],
  'level': {
    'overall': placed ? 40 : null,
    'metrics': [
      _entry('average', 47.7, placed ? 33 : null),
      _entry('first9', 52.7, placed ? 28 : null),
      _entry('scoringAverage', 54.5, placed ? 28 : null),
      _entry('finishingAverage', 33.4, placed ? 28 : null),
      _entry('checkoutPct', 13.8, placed ? 18 : null),
    ],
  },
};

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
  // Localizations load asynchronously, and the boards run a finite animation.
  await tester.pumpAndSettle();
}

void main() {
  group('PlayerLevel', () {
    test('reads the five figures in the order the backend sends them', () {
      final level = PlayerPercentiles.fromJson(_percentilesJson()).level!;

      expect(level.metrics.map((m) => m.key), [
        LevelMetric.average,
        LevelMetric.first9,
        LevelMetric.scoringAverage,
        LevelMetric.finishingAverage,
        LevelMetric.checkoutPct,
      ]);
      expect(level.entry(LevelMetric.scoringAverage)!.value, 54.5);
      expect(level.topPercent, 60);
      expect(level.isPlaced, isTrue);
    });

    test('keeps a figure that cannot be placed yet, without a percentile', () {
      final level = PlayerPercentiles.fromJson(_percentilesJson(placed: false)).level!;

      expect(level.entry(LevelMetric.first9)!.value, 52.7);
      expect(level.entry(LevelMetric.first9)!.percentile, isNull);
      expect(level.isPlaced, isFalse);
      expect(level.topPercent, isNull);
    });

    test('drops a figure it does not know rather than rendering it raw', () {
      final json = _percentilesJson();
      (json['level']['metrics'] as List).add(_entry('somethingNewer', 12, 80));

      expect(PlayerPercentiles.fromJson(json).level!.metrics, hasLength(5));
    });

    test('never claims to beat nobody, or everybody', () {
      const bottom = LevelEntry(key: LevelMetric.average, value: 20, percentile: 0.2);
      const top = LevelEntry(key: LevelMetric.average, value: 80, percentile: 99.7);

      expect(bottom.beatsPercent, 1);
      expect(top.beatsPercent, 99);
    });

    test('is rebuilt from the radar axes when the backend predates it', () {
      final legacy = {
        'cohort': _cohort(),
        'eligible': true,
        'legs': 64,
        'legsUntilEligible': 0,
        'overall': 88,
        'metrics': [
          {'key': 'average', 'value': 62.4, 'percentile': 78, 'median': 55, 'higherIsBetter': true},
          {'key': 'checkoutPct', 'value': 38.5, 'percentile': 91, 'median': 30, 'higherIsBetter': true},
          {'key': 'bustRate', 'value': 4.1, 'percentile': 45, 'median': 4, 'higherIsBetter': false},
        ],
      };

      final level = PlayerPercentiles.fromJson(legacy).level!;

      // The two axes that are also headline figures; the bust rate is not one.
      expect(level.metrics.map((m) => m.key), [LevelMetric.average, LevelMetric.checkoutPct]);
      expect(level.entry(LevelMetric.average)!.percentile, 78);
      expect(level.topPercent, 12);
    });

    test('is absent for a player with nothing in the window', () {
      final json = _percentilesJson(eligible: false)..['level'] = null;

      expect(PlayerPercentiles.fromJson(json).level, isNull);
    });
  });

  group('StatsImpacts', () {
    test('reads both boards and what makes a dart a good one on each', () {
      final impacts = StatsImpacts.fromJson({
        'scoring': [
          {'radius': 0.6, 'angle': 4.7, 'treble': true},
          {'radius': 0.4, 'angle': 4.7, 'treble': false},
        ],
        'doubles': [
          {'radius': 0.97, 'angle': 0.9, 'hit': true},
        ],
      })!;

      expect(impacts.scoring.map((d) => d.good), [true, false]);
      expect(impacts.doubles.single.good, isTrue);
    });

    test('drops a dart that carries no position', () {
      final impacts = StatsImpacts.fromJson({
        'scoring': [
          {'radius': null, 'angle': 4.7, 'treble': true},
          {'radius': 0.4, 'angle': 4.7},
        ],
        'doubles': <dynamic>[],
      })!;

      expect(impacts.scoring, hasLength(1));
    });

    test('is null rather than two empty boards', () {
      expect(StatsImpacts.fromJson(null), isNull);
      expect(StatsImpacts.fromJson({'scoring': <dynamic>[], 'doubles': <dynamic>[]}), isNull);
    });

    test('rides along the summary and the player page', () {
      final block = {
        'scoring': [
          {'radius': 0.6, 'angle': 4.7, 'treble': true},
        ],
        'doubles': <dynamic>[],
      };

      final summary = StatsSummary.fromJson({'legs': 3, 'impacts': block});
      final page = PlayerProfileStats.fromJson({
        'percentiles': _percentilesJson(),
        'impacts': block,
        'doubles': [
          {'double': 'D16', 'hits': 25, 'attempts': 102, 'pct': 24.5},
        ],
      });

      expect(summary.impacts!.scoring, hasLength(1));
      expect(page.impacts!.scoring, hasLength(1));
      expect(page.doubles.single.label, 'D16');
      expect(page.percentiles.level, isNotNull);
    });
  });

  group('a real radius on the drawn board', () {
    // The scorer's own boundaries (dart_scoring_service).
    const trebleIn = 0.57;
    const trebleOut = 0.62882;
    const doubleIn = 0.94118;

    test('keeps a treble inside the drawn treble ring, edge to edge', () {
      expect(drawnRadius(trebleIn), closeTo(SpectatorDartboardPainter.tripleIn, 1e-9));
      expect(drawnRadius(trebleOut), closeTo(SpectatorDartboardPainter.tripleOut, 1e-9));

      final middle = drawnRadius((trebleIn + trebleOut) / 2);
      expect(middle, greaterThan(SpectatorDartboardPainter.tripleIn));
      expect(middle, lessThan(SpectatorDartboardPainter.tripleOut));
    });

    test('keeps a double inside the drawn double ring', () {
      expect(drawnRadius(doubleIn), closeTo(SpectatorDartboardPainter.doubleIn, 1e-9));
      expect(drawnRadius(1), closeTo(SpectatorDartboardPainter.doubleOut, 1e-9));
    });

    test('puts a miss past the double on the number ring, never off the board', () {
      final justOut = drawnRadius(1.1);
      expect(justOut, greaterThan(SpectatorDartboardPainter.doubleOut));
      expect(justOut, lessThan(1));
      expect(drawnRadius(3), 1);
    });

    test('never reorders two darts along a radius', () {
      var previous = -1.0;
      for (var r = 0.0; r <= 1.4; r += 0.01) {
        final drawn = drawnRadius(r);
        expect(drawn, greaterThanOrEqualTo(previous));
        previous = drawn;
      }
    });

    test('reads the angle the way the scorer wrote it: twenty is straight up', () {
      // Measured on production darts: the 20 segment sits at 4.70 rad.
      const top = DartImpact(radius: 0.6, angle: 3 * math.pi / 2);
      const right = DartImpact(radius: 0.6, angle: 0);

      final up = impactOffset(top, 100);
      final side = impactOffset(right, 100);

      expect(up.dy, lessThan(-40));
      expect(up.dx.abs(), lessThan(1e-6));
      expect(side.dx, greaterThan(40));
      expect(side.dy.abs(), lessThan(1e-6));
    });
  });

  group('LevelCard', () {
    testWidgets('shows the five figures, each against the cohort', (tester) async {
      await _pump(tester, LevelCard(data: PlayerPercentiles.fromJson(_percentilesJson())));

      expect(find.text('47.7'), findsOneWidget);
      expect(find.text('Top 60 %'), findsOneWidget);
      expect(find.text('Moy. 3 fléchettes · mieux que 33 % des joueurs Platine'), findsOneWidget);
      expect(find.text('9 premières fléchettes'), findsOneWidget);
      expect(find.text('Scoring, de 501 à 170'), findsOneWidget);
      expect(find.text('Finition, 170 et moins'), findsOneWidget);
      expect(find.text('13.8 %'), findsOneWidget);
      expect(find.text('mieux que 28 %'), findsNWidgets(3));
      expect(
        find.text('20 joueurs Platine comparés · 90 j · le trait marque la médiane'),
        findsOneWidget,
      );
    });

    testWidgets('names the wider cohort when the rank held too few players', (tester) async {
      final json = _percentilesJson()..['cohort'] = _cohort(scope: 'all');

      await _pump(tester, LevelCard(data: PlayerPercentiles.fromJson(json)));

      expect(find.text('Moy. 3 fléchettes · mieux que 33 % des joueurs'), findsOneWidget);
      expect(find.text('20 joueurs comparés · 90 j · le trait marque la médiane'), findsOneWidget);
    });

    testWidgets('keeps the figures and drops every claim when nothing can be placed', (
      tester,
    ) async {
      await _pump(
        tester,
        LevelCard(data: PlayerPercentiles.fromJson(_percentilesJson(placed: false))),
      );

      expect(find.text('47.7'), findsOneWidget);
      expect(find.text('54.5'), findsOneWidget);
      expect(find.text('Moy. 3 fléchettes'), findsOneWidget);
      expect(find.textContaining('mieux que'), findsNothing);
      expect(find.textContaining('Top'), findsNothing);
      expect(find.text('Sur les 90 derniers jours'), findsOneWidget);
    });

    testWidgets('gives way to the "not enough legs" card on the Stats tab', (tester) async {
      final json = _percentilesJson(placed: false, eligible: false)..['legsUntilEligible'] = 4;

      await _pump(tester, ComparisonCards(data: PlayerPercentiles.fromJson(json)));

      expect(find.byType(LevelCard), findsNothing);
      expect(find.text('47.7'), findsNothing);
    });
  });

  group('ImpactsCard', () {
    const impacts = StatsImpacts(
      scoring: [
        DartImpact(radius: 0.6, angle: 4.7, good: true),
        DartImpact(radius: 0.4, angle: 4.7),
        DartImpact(radius: 0.4, angle: 4.4),
      ],
      doubles: [
        DartImpact(radius: 0.97, angle: 0.9, good: true),
        DartImpact(radius: 1.1, angle: 0.9),
      ],
    );

    testWidgets('counts what each board shows', (tester) async {
      await _pump(tester, const ImpactsCard(impacts: impacts, self: true));

      expect(find.text('TES IMPACTS'), findsOneWidget);
      expect(find.text('1 triple sur 3'), findsOneWidget);
      expect(find.text('1 réussi sur 2'), findsOneWidget);
      expect(find.byType(ImpactBoard), findsNWidgets(2));
    });

    testWidgets('speaks of the other player on their page', (tester) async {
      await _pump(tester, const ImpactsCard(impacts: impacts, self: false));

      expect(find.text('SES IMPACTS'), findsOneWidget);
    });

    testWidgets('says so when one of the two boards has no located dart', (tester) async {
      await _pump(
        tester,
        ImpactsCard(impacts: StatsImpacts(scoring: impacts.scoring), self: true),
      );

      expect(find.text('Aucune fléchette localisée'), findsOneWidget);
    });

    testWidgets('replays its darts on tap without throwing', (tester) async {
      await _pump(tester, const ImpactsCard(impacts: impacts, self: true));

      await tester.tap(find.byType(ImpactBoard).first);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });

  group('the player page', () {
    final stats = UserStats(
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

    testWidgets('leads with the level, the boards and the doubles', (tester) async {
      final profile = PlayerProfileStats.fromJson({
        'percentiles': _percentilesJson(),
        'impacts': {
          'scoring': [
            {'radius': 0.6, 'angle': 4.7, 'treble': true},
          ],
          'doubles': <dynamic>[],
        },
        'doubles': [
          {'double': 'D16', 'hits': 25, 'attempts': 102, 'pct': 24.5},
        ],
      });

      await _pump(tester, PlayerDartBlocks(profile: profile, stats: stats, isSelf: false));

      expect(find.byType(LevelCard), findsOneWidget);
      expect(find.text('SES IMPACTS'), findsOneWidget);
      expect(find.text('D16'), findsOneWidget);
      // The career average belongs to the fallback only.
      expect(find.text('59.8'), findsNothing);
    });

    testWidgets('falls back to the career figures when the window has nothing', (tester) async {
      await _pump(tester, PlayerDartBlocks(profile: null, stats: stats, isSelf: false));

      expect(find.byType(LevelCard), findsNothing);
      expect(find.text('59.8'), findsOneWidget);
      expect(find.text('Moy. 3 fléchettes'), findsOneWidget);
      expect(find.text('24.6 %'), findsOneWidget);
    });

    testWidgets('labels the older per-visit figure for what it is', (tester) async {
      final older = UserStats(
        totalMatches: 10,
        winRate: 50,
        averageScore: 41.2,
        count180s: 0,
        currentStreak: 0,
        wins: 5,
        losses: 5,
      );

      await _pump(tester, PlayerDartBlocks(profile: null, stats: older, isSelf: false));

      expect(find.text('41.2'), findsOneWidget);
      expect(find.text('Moy./tour'), findsOneWidget);
    });

    testWidgets('sums the career up in one card', (tester) async {
      await _pump(tester, PlayerRecordCard(stats: stats));

      expect(find.text('BILAN'), findsOneWidget);
      expect(find.text('83.0 %'), findsOneWidget);
      expect(find.text('88 – 18'), findsOneWidget);
      expect(find.text('43'), findsOneWidget);
      expect(find.text('133'), findsOneWidget);
    });
  });
}
