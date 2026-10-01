import 'package:flutter_test/flutter_test.dart';

import 'support/session_replay.dart';

/// Regression guard for the AI scorer: a real leg recorded in autoscoring_lab
/// (2026-09-06, iPhone 15 Pro, heavy model, 35 visits, 105 darts, no dart
/// corrected by the player) replayed through the app's current pipeline.
///
/// This session is the CLEAN case — nothing went wrong in it — so it proves
/// that a pipeline change does not break ordinary scoring; it cannot show an
/// improvement. Record sessions with errors in the lab for that, and replay
/// them with:
///   flutter test test/lab_session_replay_test.dart \
///       --dart-define=LAB_SESSION=/abs/path/to/session
void main() {
  const extra = String.fromEnvironment('LAB_SESSION');

  test('clean recorded leg still scores every dart', () async {
    final card =
        await SessionReplay.load('test/fixtures/lab_session_20260906').run();
    // ignore: avoid_print
    print(card.summary());
    expect(card.truthDarts, 105);
    expect(card.correct, 105, reason: card.summary());
    expect(card.extra, 0, reason: card.summary());
    expect(card.prematureClosures, 0, reason: card.summary());
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('replay an extra lab session (LAB_SESSION)', () async {
    if (extra.isEmpty) return;
    final card = await SessionReplay.load(extra).run();
    // ignore: avoid_print
    print(card.summary());
  }, timeout: const Timeout(Duration(minutes: 10)));
}
