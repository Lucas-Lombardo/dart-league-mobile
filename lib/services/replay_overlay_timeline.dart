import 'package:flutter/services.dart' show rootBundle;
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../widgets/game_turn_ui.dart' show notationPoints;

/// Builds the burn-in overlay timeline for one captured visit — the ONLY
/// place that knows both the match and the clip. The native renderers
/// (ReplayOverlayRenderer.kt / the Swift twin) interpret four primitives and
/// know nothing about darts:
///
///   scoreboard  (always)      — lower third: format band + one row per
///                               player (name, legs, remaining score; mine
///                               steps down at each dart event)
///   dart        (per impact)  — popup chip "T20", timed on the AI impact
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
  required String? seriesTitle,
  required bool checkout,
  required String logoPath,
}) {
  // The provider's score is already reduced by the thrown darts (the server
  // applies each dart as it lands), so the visit's start = remaining + visit.
  final visitTotal =
      dartNotations.fold<int>(0, (sum, n) => sum + notationPoints(n));
  final startScore = myRemainingScore + visitTotal;

  final darts = <Map<String, dynamic>>[];
  var running = startScore;
  final count = dartTimes.length < dartNotations.length
      ? dartTimes.length
      : dartNotations.length;
  for (var i = 0; i < count; i++) {
    running -= notationPoints(dartNotations[i]);
    final atMs = dartTimes[i].millisecondsSinceEpoch - clipStartWallMs;
    if (atMs < 0) continue; // impact before the clip's first segment
    darts.add({'atMs': atMs, 'label': dartNotations[i], 'to': running});
  }

  Map<String, dynamic>? banner;
  final is180 = visitTotal == 180 && dartNotations.length >= 3;
  if ((is180 || checkout) && darts.isNotEmpty) {
    banner = {
      'atMs': (darts.last['atMs'] as int) + 700,
      'text': is180 ? '180' : 'GAME SHOT!',
    };
  }

  return {
    'format': seriesTitle?.toUpperCase() ?? 'RANKED',
    'me': myName.toUpperCase(),
    'opp': opponentName.toUpperCase(),
    'myLegs': myLegs,
    'oppLegs': opponentLegs,
    'startScore': startScore,
    'oppScore': opponentScore,
    'darts': darts,
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
