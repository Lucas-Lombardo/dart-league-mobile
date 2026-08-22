import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/models/season.dart';

/// The season payloads are parsed defensively: the home ring, the Rankings
/// card and the once-only recap all read these, and a partial answer must
/// show less rather than crash.
void main() {
  group('Season.fromJson', () {
    test('reads a closed season with champion and my standing', () {
      final season = Season.fromJson({
        'id': 's0',
        'number': 0,
        'status': 'closed',
        'startedAt': null,
        'endAt': '2026-07-31T21:59:00.000Z',
        'closedAt': '2026-07-31T22:00:00.000Z',
        'trophyModel': null,
        'playersCount': 604,
        'championId': 'u1',
        'hasReward': false,
        'champion': {'id': 'u1', 'username': 'Thib_180', 'elo': 2412, 'rank': 'master'},
        'myStanding': {'position': 21, 'elo': 1512, 'rank': 'gold', 'wins': 30, 'losses': 12},
      });

      expect(season.number, 0);
      expect(season.status, SeasonStatus.closed);
      expect(season.isClosed, isTrue);
      expect(season.startedAt, isNull);
      expect(season.endAt, DateTime.utc(2026, 7, 31, 21, 59));
      expect(season.hasReward, isFalse);
      expect(season.hasTrophyImage, isFalse);
      expect(season.playersCount, 604);
      expect(season.champion!.username, 'Thib_180');
      expect(season.champion!.elo, 2412);
      expect(season.myStanding!.position, 21);
      expect(season.myStanding!.rank, 'gold');
      expect(season.myStanding!.wins, 30);
    });

    test('reads an active season with a trophy and an end date', () {
      final season = Season.fromJson({
        'id': 's1',
        'number': 1,
        'status': 'active',
        'startedAt': '2026-08-01T00:00:00.000Z',
        'endAt': '2026-08-31T21:59:00.000Z',
        'trophyModel': 'podium',
        'hasReward': true,
      });

      expect(season.isActive, isTrue);
      expect(season.hasTrophyImage, isTrue);
      expect(season.trophyImageUrl, endsWith('/trophies/podium.png'));
      expect(season.trophyThumbUrl, endsWith('/trophies/podium-thumb.png'));
      expect(season.champion, isNull);
      expect(season.myStanding, isNull);

      final now = DateTime.utc(2026, 8, 22, 10);
      expect(season.timeLeft(now), const Duration(days: 9, hours: 11, minutes: 59));
      expect(season.progress(now), closeTo(0.69, 0.01));
    });

    test('survives an empty payload with sane defaults', () {
      final season = Season.fromJson(const {});
      expect(season.id, '');
      expect(season.number, 0);
      expect(season.status, SeasonStatus.scheduled);
      expect(season.hasReward, isFalse); // number 0 → no reward
      expect(season.timeLeft(), isNull);
      expect(season.progress(), isNull);
      expect(season.champion, isNull);
    });

    test('derives hasReward from the number when the flag is missing', () {
      expect(Season.fromJson({'number': 3}).hasReward, isTrue);
      expect(Season.fromJson({'number': 0}).hasReward, isFalse);
    });

    test('tolerates bad dates, numeric strings and unknown statuses', () {
      final season = Season.fromJson({
        'number': '2',
        'status': 'weird',
        'endAt': 'not-a-date',
        'playersCount': '312',
      });
      expect(season.number, 2);
      expect(season.status, SeasonStatus.scheduled);
      expect(season.endAt, isNull);
      expect(season.playersCount, 312);
    });

    test('timeLeft never goes negative once the end has passed', () {
      final season = Season.fromJson({
        'number': 1,
        'status': 'active',
        'startedAt': '2026-08-01T00:00:00.000Z',
        'endAt': '2026-08-31T21:59:00.000Z',
      });
      final later = DateTime.utc(2026, 9, 15);
      expect(season.timeLeft(later), Duration.zero);
      expect(season.progress(later), 1.0);
    });
  });

  group('SeasonStanding.fromJson', () {
    test('reads a line and defaults missing fields', () {
      final line = SeasonStanding.fromJson({'position': 14, 'elo': 1486, 'rank': 'gold', 'wins': 23, 'losses': 11});
      expect(line.position, 14);
      expect(line.elo, 1486);
      expect(line.rank, 'gold');
      expect(line.losses, 11);

      final empty = SeasonStanding.fromJson(const {});
      expect(empty.position, 0);
      expect(empty.rank, 'unranked');
      expect(empty.wins, 0);
    });
  });

  group('CurrentSeason.fromJson', () {
    test('reads season, next, leader and me', () {
      final current = CurrentSeason.fromJson({
        'season': {'id': 's1', 'number': 1, 'status': 'active', 'endAt': '2026-08-31T21:59:00.000Z', 'hasReward': true},
        'next': {'id': 's2', 'number': 2, 'status': 'scheduled', 'hasReward': true},
        'leader': {'id': 'u9', 'username': 'NoahTheBull', 'elo': 2318, 'rank': 'diamond'},
        'me': {'position': 14, 'elo': 1486, 'rank': 'gold', 'wins': 23, 'losses': 11},
      })!;
      expect(current.season.number, 1);
      expect(current.next!.number, 2);
      expect(current.next!.isScheduled, isTrue);
      expect(current.leader!.username, 'NoahTheBull');
      expect(current.me!.position, 14);
    });

    test('is null without a season, and tolerates null next/leader/me', () {
      expect(CurrentSeason.fromJson(const {}), isNull);
      final current = CurrentSeason.fromJson({
        'season': {'number': 0, 'status': 'active'},
        'next': null,
        'leader': null,
        'me': null,
      })!;
      expect(current.next, isNull);
      expect(current.leader, isNull);
      expect(current.me, isNull);
    });
  });

  group('SeasonRecap.fromJson', () {
    final payload = {
      'season': {'id': 's1', 'number': 1, 'status': 'closed', 'playersCount': 312, 'hasReward': true, 'endAt': '2026-08-31T21:59:00.000Z'},
      'standing': {'position': 14, 'elo': 1486, 'rank': 'gold', 'wins': 23, 'losses': 11, 'eloAfterReset': 1350, 'peakElo': 1512},
      'eloBefore': 1486,
      'eloAfter': 1350,
      'rankBefore': 'gold',
      'rankAfter': 'gold',
      'champion': {'id': 'u9', 'username': 'NoahTheBull', 'elo': 2318, 'rank': 'diamond'},
      'nextSeason': {'id': 's2', 'number': 2, 'status': 'active', 'startedAt': '2026-08-31T21:59:00.000Z', 'endAt': '2026-09-30T21:59:00.000Z', 'hasReward': true},
    };

    test('reads the full recap', () {
      final recap = SeasonRecap.fromJson(payload)!;
      expect(recap.season.number, 1);
      expect(recap.standing.position, 14);
      expect(recap.eloBefore, 1486);
      expect(recap.eloAfter, 1350);
      expect(recap.rankBefore, 'gold');
      expect(recap.rankAfter, 'gold');
      expect(recap.rankChanged, isFalse);
      expect(recap.peakElo, 1512);
      expect(recap.champion!.username, 'NoahTheBull');
      expect(recap.nextSeason!.number, 2);
      expect(recap.nextSeason!.endAt, DateTime.utc(2026, 9, 30, 21, 59));
    });

    test('flags a rank change', () {
      final recap = SeasonRecap.fromJson({...payload, 'rankBefore': 'diamond', 'rankAfter': 'platinum'})!;
      expect(recap.rankChanged, isTrue);
    });

    test('is null without season or standing, falls back inside the standing', () {
      expect(SeasonRecap.fromJson(const {}), isNull);
      expect(SeasonRecap.fromJson({'season': {'number': 1}}), isNull);
      final minimal = SeasonRecap.fromJson({
        'season': {'number': 1, 'status': 'closed'},
        'standing': {'position': 3, 'elo': 2240, 'rank': 'diamond', 'eloAfterReset': 1893},
      })!;
      expect(minimal.eloBefore, 2240);
      expect(minimal.eloAfter, 1893);
      expect(minimal.rankBefore, 'diamond');
      expect(minimal.peakElo, isNull);
      expect(minimal.champion, isNull);
      expect(minimal.nextSeason, isNull);
    });
  });
}
