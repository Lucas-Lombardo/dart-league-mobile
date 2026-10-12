// Store listing screenshots for the App Store and the Play Store, rendered
// headlessly (no simulator): eight screens that tell the product story, in
// French and English, at every size the stores ask for. Not a test of
// behaviour — skipped unless run explicitly (its own flag, so a plain
// PREVIEW run of test/preview does not render the whole store set):
//
//   make store-screenshots
//   # or
//   flutter test test/preview/store \
//     --dart-define=STORE=true \
//     --dart-define=STORE_OUT=/abs/dir
//
// Output: <dir>/<ios|android>/<profile>/<fr|en>/NN_name.png + index.html.
// The scenes are the ones the sibling preview tests build (imported with a
// prefix so their own main() stays out of the way); the in-match camera panel
// shows board_frame.jpg, a frame from the owner's own board.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/l10n/app_localizations.dart';
import 'package:mobile/screens/game/match_end_view.dart';
import 'package:mobile/screens/training/training_select_screen.dart';
import 'package:mobile/services/replay_clips_store.dart';
import 'package:mobile/utils/app_theme.dart';
import 'package:mobile/widgets/elo_change_overlay.dart';

import '../home_preview_test.dart' as home;
import '../leaderboard_preview_test.dart' as leaderboard;
import '../match_screens_preview_test.dart' as match;
import '../stats_preview_test.dart' as stats;
import '../tournament_preview_test.dart' as tournament;
import 'store_harness.dart';

const _enabled = bool.fromEnvironment('STORE');
const _outDir = String.fromEnvironment('STORE_OUT');

class _Scene {
  final String name;
  final WidgetBuilder build;
  final Duration settle;
  const _Scene(this.name, this.build, {this.settle = Duration.zero});
}

/// The listing order: profile and modes, the AI-scored match, the win, the
/// ELO gain, then rankings, tournaments, stats and training.
List<_Scene> _scenes(Locale locale, Uint8List boardFrame, match.ScoringStub scoring) => [
      _Scene('01_home', (_) => const home.HomePreview()),
      _Scene(
        '02_match',
        (_) => Scaffold(
          backgroundColor: AppTheme.background,
          body: match.MyTurnPreview(
            scoring,
            cameraPreview: Image.memory(boardFrame, fit: BoxFit.cover),
          ),
        ),
      ),
      _Scene(
        '03_match_end',
        (context) {
          final l10n = AppLocalizations.of(context);
          return MatchEndView(
            didWin: true,
            title: l10n.victory,
            subtitle: l10n.provenLegend,
            scoreLine: '2 – 1',
            scoreCaption: l10n.bestOfN(3),
            panel: const match.EndPanel(),
            replayClips: [
              for (var i = 0; i < 3; i++)
                ReplayClip(path: 'clip$i.mp4', createdAt: DateTime.now()),
            ],
          );
        },
        settle: const Duration(seconds: 2),
      ),
      _Scene(
        '04_elo',
        (_) => EloChangeOverlay(oldElo: 1601, newElo: 1619, isWin: true, onDismiss: () {}),
        settle: const Duration(seconds: 3),
      ),
      _Scene('05_leaderboard', (_) => const leaderboard.LeaderboardPreview()),
      _Scene(
        '06_tournament',
        (_) => tournament.TournamentPreviewScene(english: locale.languageCode == 'en'),
      ),
      // Long enough for the impact boards to land their last dart.
      _Scene('07_stats', (_) => const stats.MatchesPreview(), settle: const Duration(seconds: 4)),
      _Scene('08_training', (_) => const TrainingSelectScreen()),
    ];

void main() {
  final boardFrame = File('${Directory.current.path}/test/preview/store/board_frame.jpg');

  for (final profile in storeProfiles) {
    testWidgets('store screenshots ${profile.platform.name}/${profile.name}', (tester) async {
      await tester.runAsync(loadPreviewFonts);
      final frame = boardFrame.readAsBytesSync();
      final scoring = match.ScoringStub();
      for (final locale in storeLocales) {
        for (final scene in _scenes(locale, frame, scoring)) {
          await captureStoreShot(
            tester,
            outDir: _outDir,
            profile: profile,
            locale: locale,
            name: scene.name,
            scene: scene.build,
            settle: scene.settle,
          );
        }
      }
      scoring.dispose();
    }, skip: !_enabled, timeout: const Timeout(Duration(minutes: 10)));
  }

  tearDownAll(() async {
    if (_enabled) await writeStoreIndex(_outDir);
  });
}
