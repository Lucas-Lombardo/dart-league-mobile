import 'package:flutter/services.dart' show rootBundle;
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../widgets/game_turn_ui.dart' show notationPoints;

/// Builds the burn-in overlay timeline for one captured visit — the ONLY
/// place that knows both the match and the clip. The native renderers
/// (ReplayOverlayRenderer.kt / the Swift twin) interpret three primitives and
/// know nothing about darts:
///
///   scoreboard  (always)      — brand lockup (shield + DART RIVALS +
///                               format) over two facing cards, one per
///                               player (name, remaining score, leg pips),
///                               static for the whole clip
///   banner      (highlights)  — full-width gold band ("180", "GAME SHOT!")
///   outro       (always)      — end card: logo + DART RIVALS + @handle,
///                               timed natively over the last 1.6s
///
/// All coordinates/styling live natively in a 720×1280 design space; this
/// file only produces WHAT happens WHEN (ms relative to clip start).
Map<String, dynamic> buildReplayOverlayTimeline({
  required int clipStartWallMs,
  required List<DateTime> dartTimes,
  required List<String> dartNotations,
  required int myRemainingScore,
  required int opponentScore,
  required String myName,
  required String opponentName,
  required int myLegs,
  required int opponentLegs,
  required int legsTarget,
  required String? seriesTitle,
  required bool checkout,
  required String logoPath,
}) {
  // Everything per-dart was cut on 2026-08-03: AI impact timestamps lag the
  // on-screen throw unpredictably, so the score countdown AND the "T20"
  // popup chips landed on the wrong frames (the chip could even name a dart
  // that was not the one just thrown). The scoreboard now shows the visit's
  // END state for the whole clip; only the banner still uses impact times,
  // where it fires once, late, and a small lag is harmless.
  final visitTotal =
      dartNotations.fold<int>(0, (sum, n) => sum + notationPoints(n));

  final count = dartTimes.length < dartNotations.length
      ? dartTimes.length
      : dartNotations.length;
  final lastDartMs = count == 0
      ? null
      : dartTimes[count - 1].millisecondsSinceEpoch - clipStartWallMs;

  Map<String, dynamic>? banner;
  final is180 = visitTotal == 180 && dartNotations.length >= 3;
  if ((is180 || checkout) && lastDartMs != null && lastDartMs >= 0) {
    banner = {
      'atMs': lastDartMs + 700,
      'text': is180 ? '180' : 'GAME SHOT!',
    };
  }

  return {
    'format': seriesTitle?.toUpperCase() ?? 'RANKED',
    'me': myName.toUpperCase(),
    'opp': opponentName.toUpperCase(),
    'myLegs': myLegs,
    'oppLegs': opponentLegs,
    // Number of pips drawn per card: a BO3 shows two, so "one leg left to
    // take" reads without counting.
    'legsTarget': legsTarget,
    'startScore': myRemainingScore,
    'oppScore': opponentScore,
    'banner': ?banner,
    'handle': '@$myName',
    'logoPath': logoPath,
  };
}

/// The end card draws the real shield logo: flutter assets are not plain
/// files natively, so it is materialized once into the cache.
Future<String> materializeReplayLogo() async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/replay_logo.png');
  if (!await file.exists()) {
    final data = await rootBundle.load('assets/logo/logo-without-letters.png');
    await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
  }
  return file.path;
}
