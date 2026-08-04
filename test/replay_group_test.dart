import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/replay_group.dart';

/// One clip as `GET /replays/mine` sends it.
Map<String, dynamic> clip(
  String id, {
  String? key,
  String? opponent,
  String matchType = 'ranked',
  int? bestOf,
  int? myLegs,
  int? oppLegs,
  String outcome = 'won',
  String? name,
  int? turnTotal = 100,
  int? durationMs,
  String createdAt = '2026-08-03T21:22:00.000Z',
}) =>
    {
      'id': id,
      'url': 'https://r2/$id.mp4',
      'name': name,
      // Still returned by the API; the app no longer reads it.
      'type': 'manual',
      'turnTotal': turnTotal,
      'durationMs': durationMs,
      'createdAt': createdAt,
      'match': key == null
          ? null
          : {
              'key': key,
              'opponent': opponent,
              'matchType': matchType,
              'tournamentName': null,
              'bestOf': bestOf,
              'myLegs': myLegs,
              'opponentLegs': oppLegs,
              'outcome': outcome,
            },
    };

void main() {
  group('groupReplayClips', () {
    test('collapses the legs of one series into a single group', () {
      final groups = groupReplayClips([
        clip('c1', key: 'series-1', opponent: 'VATI99', bestOf: 3, myLegs: 2, oppLegs: 1),
        clip('c2', key: 'series-1', opponent: 'VATI99', bestOf: 3, myLegs: 2, oppLegs: 1),
        clip('c3', key: 'series-1', opponent: 'VATI99', bestOf: 3, myLegs: 2, oppLegs: 1),
      ]);

      expect(groups, hasLength(1));
      expect(groups.first.clips.map((c) => c.id), ['c1', 'c2', 'c3']);
      expect(groups.first.opponent, 'VATI99');
      expect(groups.first.hasLegs, isTrue);
      expect(groups.first.myLegs, 2);
    });

    test('keeps the order in which matches first appear', () {
      final groups = groupReplayClips([
        clip('c1', key: 'series-2', opponent: 'B'),
        clip('c2', key: 'series-1', opponent: 'A'),
        clip('c3', key: 'series-2', opponent: 'B'),
      ]);

      expect(groups.map((g) => g.key), ['series-2', 'series-1']);
      expect(groups.first.clips.map((c) => c.id), ['c1', 'c3']);
    });

    test('gathers every match-less clip into one group', () {
      final groups = groupReplayClips([
        clip('c1', key: 'series-1', opponent: 'A'),
        clip('c2'),
        clip('c3'),
      ]);

      expect(groups.map((g) => g.key), ['series-1', ReplayGroup.orphanKey]);
      final orphans = groups.last;
      expect(orphans.isOrphan, isTrue);
      expect(orphans.clips.map((c) => c.id), ['c2', 'c3']);
      expect(orphans.opponent, isNull);
      expect(orphans.outcome, isNull);
    });

    test('reads the clip fields the rows render', () {
      final groups = groupReplayClips([
        clip('c1',
            key: 'm1', opponent: 'A', name: '  Mon 180  ', turnTotal: 180),
      ]);

      final entry = groups.first.clips.single;
      expect(entry.turnTotal, 180);
      expect(entry.name, 'Mon 180');
      expect(entry.hasName, isTrue);
    });

    test('labels the clip duration, and stays silent without one', () {
      String? labelOf(int? durationMs) => groupReplayClips([
            clip('c1', key: 'm1', durationMs: durationMs),
          ]).first.clips.single.durationLabel;

      expect(labelOf(11400), '0:11');
      expect(labelOf(62000), '1:02');
      // Clips uploaded before the app sent a duration, and a zero the
      // encoder never filled in: the row shows the time alone.
      expect(labelOf(null), isNull);
      expect(labelOf(0), isNull);
    });

    test('counts the days left before the retention sweep', () {
      final now = DateTime.now();
      ReplayEntry entryAgedDays(int days) => groupReplayClips([
            clip('c1',
                key: 'm1',
                createdAt:
                    now.subtract(Duration(days: days)).toIso8601String()),
          ]).first.clips.single;

      // Whole days only, so a clip captured a minute ago has 29 full days
      // left, not 30 — the countdown never promises more than it holds.
      expect(entryAgedDays(0).daysLeft(30), 29);
      // 23 days old → 6 left, i.e. under the 7-day badge threshold.
      expect(entryAgedDays(23).daysLeft(30), 6);
      // Its last day: still listed, but the next sweep takes it.
      expect(entryAgedDays(30).daysLeft(30), 0);
      expect(entryAgedDays(31).daysLeft(30), lessThan(0));
    });

    test('a still-running match has no legs to show', () {
      final groups = groupReplayClips([
        clip('c1', key: 'm1', opponent: 'A', outcome: 'pending'),
      ]);

      expect(groups.first.outcome, 'pending');
      expect(groups.first.hasLegs, isFalse);
    });

    test('survives a clip with neither name nor total', () {
      final groups = groupReplayClips([
        clip('c1', key: 'm1', opponent: 'A', name: null, turnTotal: null),
      ]);

      final entry = groups.first.clips.single;
      expect(entry.hasName, isFalse);
      expect(entry.turnTotal, isNull);
    });
  });
}
