// Renders the in-match screens (system D) to PNG so they can be reviewed
// without a device: my turn, the opponent's turn (composed from the same
// shared widgets the game screen uses), end of leg, end of match, the match
// stats card, the ELO overlay and the rank overlay. Not a test of behaviour —
// skipped unless run explicitly:
//
//   flutter test test/preview/match_screens_preview_test.dart \
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
import 'package:mobile/models/match_stats.dart';
import 'package:mobile/screens/game/leg_end_view.dart';
import 'package:mobile/screens/game/match_end_view.dart';
import 'package:mobile/services/auto_scoring_service.dart';
import 'package:mobile/services/dart_scoring_service.dart';
import 'package:mobile/services/replay_clips_store.dart';
import 'package:mobile/utils/app_theme.dart';
import 'package:mobile/widgets/auto_score_display.dart';
import 'package:mobile/widgets/design_system.dart';
import 'package:mobile/widgets/elo_change_overlay.dart';
import 'package:mobile/widgets/game_turn_ui.dart';
import 'package:mobile/widgets/logo_watermark.dart';
import 'package:mobile/widgets/match_stats_card.dart';
import 'package:mobile/widgets/rank_change_overlay.dart';
import 'package:mobile/widgets/turn_report_banner.dart';

const _enabled = bool.fromEnvironment('PREVIEW');
const _outDir = String.fromEnvironment('PREVIEW_OUT');

const _size = Size(393, 852);
const _padding = EdgeInsets.only(top: 59, bottom: 34);

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

DartScore _dart(int segment, String ring) {
  final mul = switch (ring) { 'triple' => 3, 'double' => 2, _ => 1 };
  return DartScore(
    score: segment * mul,
    segment: segment,
    ring: ring,
    radius: 0.5,
    angle: 0,
  );
}

/// One visit in progress (T20 counted, two darts to come), AI capturing.
class _ScoringStub extends AutoScoringService {
  @override
  bool get isCapturing => true;
  @override
  List<DartScore?> get dartSlots => [_dart(20, 'triple'), null, null];
  @override
  int get turnTotal => 60;
  @override
  bool get showRemoveDartsHint => false;
  @override
  bool get manualConfirmNeeded => false;
}

class _MyTurnPreview extends StatelessWidget {
  final AutoScoringService scoring;
  const _MyTurnPreview(this.scoring);

  @override
  Widget build(BuildContext context) {
    return AutoScoreGameView(
      scoringService: scoring,
      onConfirm: () {},
      pendingConfirmation: false,
      isAudioMuted: false,
      onToggleAudio: () {},
      onSwitchCamera: () {},
      onZoomIn: () {},
      onZoomOut: () {},
      currentZoom: 1.9,
      minZoom: 1,
      maxZoom: 4,
      onRemoveDart: (_) {},
      roundNumber: 7,
      onBack: () {},
      captureButton: ReplayCaptureButton(onCapture: () async => true),
      header: TurnScoreHeader(
        myName: 'Vati99',
        opponentName: 'DODO180',
        myScore: 355,
        opponentScore: 288,
        myAverage: 62.4,
        opponentAverage: 55.1,
        seriesTitle: 'BO3 · ${AppLocalizations.of(context).legNumber(2)}',
        myLegs: 1,
        opponentLegs: 0,
        showBadges: false,
        myTurn: true,
      ),
    );
  }
}

/// The opponent-turn X01 layout, composed from the same shared widgets
/// BaseGameScreenState.buildOpponentTurnScreenShared stacks (the real one
/// needs the providers and the RTC session).
class _OpponentTurnPreview extends StatelessWidget {
  const _OpponentTurnPreview();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final safeTop = MediaQuery.of(context).padding.top;
    final safeBottom = MediaQuery.of(context).padding.bottom;
    const throws = ['T20', 'T19'];
    final total = throws.fold<int>(0, (s, n) => s + notationPoints(n));
    return Container(
      color: AppTheme.gameBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: safeTop + 6),
          TurnScoreHeader(
            myName: 'Vati99',
            opponentName: 'DODO180',
            myScore: 355,
            opponentScore: 288,
            myAverage: 62.4,
            opponentAverage: 55.1,
            seriesTitle: 'BO3 · ${l10n.legNumber(2)}',
            myLegs: 1,
            opponentLegs: 0,
            showBadges: false,
            myTurn: false,
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SizedBox(
              height: gameCameraHeight(context),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(
                      color: AppTheme.gamePanelEmpty,
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.videocam_off_outlined, size: 40, color: AppTheme.textSecondary),
                            const SizedBox(height: 10),
                            Text(dsSentence(l10n.waitingUpper), style: AppTheme.caption),
                          ],
                        ),
                      ),
                    ),
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: AppTheme.opponentPink, width: 1.5),
                        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                      ),
                    ),
                    const Positioned(top: 12, left: 0, right: 0, child: Center(child: LogoWatermark())),
                    Positioned(
                      top: 10,
                      left: 10,
                      child: GameControlButton(icon: Icons.arrow_back_ios_new_rounded, onTap: () {}),
                    ),
                    Positioned(
                      top: 58,
                      left: 10,
                      child: GameChip(text: l10n.roundChip(7), color: AppTheme.textSecondary),
                    ),
                    Positioned(
                      top: 10,
                      right: 10,
                      child: Row(children: [
                        GameControlButton(icon: Icons.mic_off_rounded, color: AppTheme.opponentPink, onTap: () {}),
                        const SizedBox(width: 8),
                        GameControlButton(icon: Icons.cameraswitch_rounded, onTap: () {}),
                      ]),
                    ),
                    // The announcement band, frozen at full opacity.
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(16, 26, 16, 14),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              AppTheme.gameBackground.withValues(alpha: 0),
                              AppTheme.gameBackground.withValues(alpha: 0.92),
                              AppTheme.gameBackground.withValues(alpha: 0.96),
                            ],
                            stops: const [0, 0.38, 1],
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            const Text('T19', style: TextStyle(color: AppTheme.textPrimary, fontSize: 40, fontWeight: FontWeight.w800, letterSpacing: -0.8, height: 1)),
                            const SizedBox(width: 12),
                            Flexible(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.bottomLeft,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 4),
                                      child: Text(l10n.plusPts(57), style: const TextStyle(color: AppTheme.opponentPinkBright, fontSize: 20, fontWeight: FontWeight.w800, height: 1)),
                                    ),
                                    const SizedBox(width: 10),
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 2),
                                      child: DsPill(label: l10n.manualDartTag, color: AppTheme.textSecondary),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Text(l10n.dartOf(2), textAlign: TextAlign.right, maxLines: 1, softWrap: false, overflow: TextOverflow.fade, style: AppTheme.labelSmall.copyWith(height: 1)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                VisitLabelRow(label: l10n.visitOf('DODO180'), total: total, color: AppTheme.opponentPinkBright),
                const SizedBox(height: 10),
                SizedBox(
                  height: 74,
                  child: Row(
                    children: List.generate(3, (i) {
                      final notation = i < throws.length ? throws[i] : null;
                      return Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(left: i == 0 ? 0 : 10),
                          child: DartVisitChip(
                            notation: notation,
                            accent: AppTheme.surfaceLight,
                            highlighted: notation != null && i == throws.length - 1,
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          Padding(
            padding: EdgeInsets.fromLTRB(12, 8, 12, safeBottom + 10),
            child: const OpponentWarningBanner(),
          ),
        ],
      ),
    );
  }
}

MatchStats _fakeStats() => const MatchStats(
      matchId: 'm',
      legs: 3,
      me: MatchStatsSide(
        username: 'Vati99',
        average: 62.4,
        bestVisit: 140,
        count180: 1,
        doublesHit: 3,
        doublesAttempted: 8,
        checkoutPct: 37.5,
        bestCheckout: 84,
      ),
      opponent: MatchStatsSide(
        username: 'DODO180',
        average: 55.1,
        bestVisit: 121,
        count180: 0,
        doublesHit: 2,
        doublesAttempted: 8,
        checkoutPct: 25,
        bestCheckout: 40,
      ),
      windowAverage: 58.0,
    );

class _EndPanel extends StatelessWidget {
  const _EndPanel();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton(onPressed: () {}, child: Text(dsSentence(l10n.acceptResult))),
      ),
      const SizedBox(height: 10),
      SizedBox(
        width: double.infinity,
        height: 48,
        child: OutlinedButton.icon(
          onPressed: () {},
          style: OutlinedButton.styleFrom(foregroundColor: AppTheme.textSecondary, textStyle: gameButtonTextStyle.copyWith(fontSize: 14)),
          icon: const Icon(Icons.flag_outlined, size: 16),
          label: Text(dsSentence(l10n.reportPlayer)),
        ),
      ),
    ]);
  }
}

class _StatsCardPage extends StatelessWidget {
  const _StatsCardPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              MatchStatsCard(matchId: 'm', initialStats: _fakeStats()),
              const SizedBox(height: 24),
              WinningVisitBanner(onFlag: () {}, matchId: 'm', volleyScore: 121),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _render(
  WidgetTester tester,
  String name,
  Widget page, {
  Duration settle = Duration.zero,
  bool withPadding = false,
}) async {
  final key = GlobalKey();
  // Explicit MediaQuery: the test view's default physical size is 800×600,
  // which the screens would read as landscape.
  final Widget home = MediaQuery(
    data: MediaQueryData(
      size: _size,
      padding: withPadding ? _padding : EdgeInsets.zero,
    ),
    child: RepaintBoundary(key: key, child: page),
  );
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
      home: home,
    ),
  );
  // Localizations and asset images resolve asynchronously.
  await tester.runAsync(() async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  });
  // Two pumps: the first fires the delayed starts (count-up, haptics), the
  // second runs those animations to their end.
  if (settle > Duration.zero) {
    await tester.pump(settle);
    await tester.pump(settle);
  }
  await tester.pump();

  final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 3);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('$_outDir/$name.png');
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    debugPrint('wrote ${file.path}');
  });
  expect(tester.takeException(), isNull, reason: name);
}

void main() {
  testWidgets('match screens preview', (tester) async {
    await tester.runAsync(_loadFonts);
    await tester.binding.setSurfaceSize(_size);
    tester.view.devicePixelRatio = 3;

    final scoring = _ScoringStub();
    // The game screen hosts these in a Scaffold (buildLiveMatchBody), which
    // is what gives plain TextStyles the theme's font.
    await _render(
      tester,
      'en_jeu',
      Scaffold(backgroundColor: AppTheme.background, body: _MyTurnPreview(scoring)),
      withPadding: true,
    );
    await _render(
      tester,
      'en_jeu_adversaire',
      const Scaffold(backgroundColor: AppTheme.background, body: _OpponentTurnPreview()),
      withPadding: true,
    );
    await _render(
      tester,
      'fin_manche',
      LegEndView(
        wonLeg: true,
        myLegsWon: 1,
        opponentLegsWon: 0,
        legsNeeded: 2,
        secondsLeft: 6,
        onAttemptPop: () async => false,
      ),
    );
    await _render(
      tester,
      'fin_match',
      Builder(
        builder: (context) {
          final l10n = AppLocalizations.of(context);
          return MatchEndView(
            didWin: true,
            title: l10n.victory,
            subtitle: l10n.provenLegend,
            scoreLine: '2 – 1',
            scoreCaption: l10n.bestOfN(3),
            panel: const _EndPanel(),
            replayClips: [
              for (var i = 0; i < 3; i++)
                ReplayClip(path: 'clip$i.mp4', createdAt: DateTime.now()),
            ],
          );
        },
      ),
      settle: const Duration(seconds: 2),
    );
    await _render(tester, 'stats_card', const _StatsCardPage());
    await _render(
      tester,
      'elo',
      EloChangeOverlay(oldElo: 1601, newElo: 1619, isWin: true, onDismiss: () {}),
      settle: const Duration(seconds: 3),
    );
    await _render(
      tester,
      'rang',
      RankChangeOverlay(oldRank: 'platinum', newRank: 'diamond', onDismiss: () {}),
      settle: const Duration(seconds: 3),
    );
    scoring.dispose();
  }, skip: !_enabled);
}
