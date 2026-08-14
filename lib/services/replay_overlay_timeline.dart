import 'package:flutter/services.dart' show rootBundle;
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Builds the burn-in overlay timeline for one captured visit — the ONLY
/// place that knows both the match and the clip. The native renderers
/// (ReplayOverlayRenderer.kt / the Swift twin) interpret two primitives and
/// know nothing about darts:
///
///   scoreboard  (always)      — brand lockup (shield + DART RIVALS +
///                               format) over two facing cards, one per
///                               player (name, remaining score, leg pips),
///                               static for the whole clip
///   outro       (always)      — end card: logo + DART RIVALS + @handle,
///                               timed natively over the last 1.6s
///
/// All coordinates/styling live natively in a 720×1280 design space; this
/// file only produces WHAT happens WHEN (ms relative to clip start).
///
/// Everything per-dart was cut on 2026-08-03: AI impact timestamps lag the
/// on-screen throw unpredictably, so anything timed on them landed on the
/// wrong frames. The scoreboard shows the visit's END state for the whole
/// clip. (The "180"/"GAME SHOT!" gold band went too, 2026-08-13: it covered
/// the board and added nothing.)
Map<String, dynamic> buildReplayOverlayTimeline({
  required int myRemainingScore,
  required int opponentScore,
  required String myName,
  required String opponentName,
  required int myLegs,
  required int opponentLegs,
  required int legsTarget,
  required String? seriesTitle,
  required String logoPath,
}) {
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
