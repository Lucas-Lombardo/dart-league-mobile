import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/screens/ghost/ghost_models.dart';

void main() {
  group('ghost models (defensive JSON)', () {
    test('reads an offer, and treats a missing offer as unavailable', () {
      final res = GhostOfferResponse.fromJson({
        'available': true,
        'queueDelaySec': 30,
        'peak': {'fromHour': 18, 'toHour': 22},
        'offer': {
          'id': 'o-1',
          'expiresAt': '2026-11-08T12:15:00.000Z',
          'bestOf': 3,
          'eloEligible': true,
          'eloMatchesLeft': 4,
          'eloIfWin': 13,
          'eloIfLoss': -12,
          'ghost': {
            'ownerId': 'u-1',
            'username': 'Bruno_T19',
            'elo': 1598,
            'rank': 'gold',
            'cosmetics': {'level': 7, 'monogram': 'BT', 'badges': []},
            'playedAt': '2026-10-28T19:00:00.000Z',
            'average': 55.2,
          },
        },
      });
      expect(res.available, isTrue);
      expect(res.offer!.ghost.username, 'Bruno_T19');
      expect(res.offer!.eloIfWin, 13);
      expect(res.offer!.ghost.cosmetics?.level, 7);
      expect(res.queueDelaySec, 30);

      // §14.12: not in the queue, or not for long enough yet.
      final wait = GhostOfferResponse.fromJson({'available': false, 'reason': 'queue_wait', 'retryInSec': 12, 'queueDelaySec': 300});
      expect(wait.reason, GhostUnavailable.queueWait);
      expect(wait.retryInSec, 12);
      expect(wait.queueDelaySec, 300);
      expect(GhostOfferResponse.fromJson({'reason': 'queue_only'}).reason, GhostUnavailable.queueOnly);
      expect(GhostOfferResponse.fromJson({}).queueDelaySec, kGhostQueueDelay);

      final none = GhostOfferResponse.fromJson({'available': false, 'reason': 'daily_limit'});
      expect(none.available, isFalse);
      expect(none.reason, GhostUnavailable.dailyLimit);
      // Claims to be available but has no offer: not available.
      expect(GhostOfferResponse.fromJson({'available': true}).available, isFalse);
      // An unknown reason from a newer server is not a crash.
      expect(GhostOfferResponse.fromJson({'reason': 'something_new'}).reason, GhostUnavailable.unknown);
      expect(GhostOfferResponse.fromJson('garbage').available, isFalse);
    });

    test('reads a visit answer: verdict, ghost reply, leg end', () {
      final r = GhostVisitResult.fromJson({
        'duplicate': false,
        'visit': {'leg': 0, 'index': 3, 'score': 40, 'busted': false, 'checkout': true, 'remaining': 0},
        'ghostVisits': [
          {
            'leg': 1,
            'index': 0,
            'score': 85,
            'remaining': 416,
            'darts': [
              {'notation': 'T20', 'radius': 0.6, 'angle': 4.7, 'delayMs': 1500},
              {'notation': 'S20', 'delayMs': 2600},
              {'notation': 'S5', 'radius': 0.8, 'angle': 4.4, 'delayMs': 'bad'},
            ],
          },
        ],
        'legEnded': {'leg': 0, 'winner': 'player'},
        'match': {
          'id': 'g-1',
          'status': 'in_progress',
          'currentLeg': 1,
          'legStarter': 'ghost',
          'turn': 'player',
          'playerLegsWon': 1,
          'ghostRemaining': 416,
          'ghost': {'username': 'Bruno_T19', 'elo': 1598},
        },
      })!;
      expect(r.visitCheckout, isTrue);
      expect(r.visitRemaining, 0);
      expect(r.legEndedIndex, 0);
      expect(r.legWonByPlayer, isTrue);
      expect(r.ghostVisits.single.darts.map((d) => d.notation), ['T20', 'S20', 'S5']);
      expect(r.ghostVisits.single.darts[1].radius, isNull); // old dart: bed centre
      expect(r.ghostVisits.single.darts[2].delayMs, 1500); // bad value → default
      expect(r.match.ghostStartsLeg, isTrue);
      expect(r.match.isOver, isFalse);
      expect(r.match.playerLegsWon, 1);
    });

    test('reads the end of a match and the ELO status', () {
      final m = GhostMatchState.fromJson({
        'id': 'g-1',
        'status': 'finished',
        'turn': 'over',
        'ghost': {'username': 'x', 'elo': 1500},
        'end': {
          'won': true,
          'endReason': 'played',
          'playerLegsWon': 2,
          'ghostLegsWon': 1,
          'eloStatus': 'held',
          'eloDelta': 13,
          'proofRequired': true,
          'average': 57.8,
        },
      })!;
      expect(m.isOver, isTrue);
      expect(m.end!.eloHeld, isTrue);
      expect(m.end!.eloApplied, isFalse);
      expect(m.end!.eloDelta, 13);
      expect(GhostMatchState.fromJson({'status': 'finished'}), isNull); // no id
    });

    test('posts a dart with its AI reading and clock, a typed dart without', () {
      final ai = const GhostPostedDart(
        notation: 'T20',
        aiNotation: 'S20',
        telemetry: {'radius': 0.6, 'angle': 4.7},
        t: 1700000000000,
      ).toJson();
      expect(ai, {
        'notation': 'T20',
        'source': 'ai',
        'aiNotation': 'S20',
        'radius': 0.6,
        'angle': 4.7,
        't': 1700000000000,
      });
      final typed = const GhostPostedDart(notation: 'S5', telemetry: {'radius': 0.1}).toJson();
      expect(typed, {'notation': 'S5', 'source': 'manual'});
    });

    test('reads the owner digest', () {
      final d = GhostDigest.fromJson({
        'count': 3,
        'ghostWins': 2,
        'ghostLosses': 1,
        'xp': 40,
        'source': {'playedAt': '2026-10-30T19:00:00.000Z', 'average': 52.4},
        'beatenBy': {'username': 'LéoD20', 'userId': 'u-9', 'darts': 4},
        'games': [
          {'id': 'a', 'opponentId': 'u-1', 'opponentUsername': 'Sam_Shot', 'ghostWon': true, 'ghostLegs': 1, 'opponentLegs': 0},
          {'id': 'b', 'opponentId': 'u-9', 'opponentUsername': 'LéoD20', 'ghostWon': false},
          {'id': 'c', 'opponentId': 'u-3', 'opponentUsername': 'Big_Jim', 'ghostWon': true},
        ],
      });
      expect(d.isEmpty, isFalse);
      expect(d.games.where((g) => g.ghostWon), hasLength(2));
      expect(d.beatenByDarts, 4);
      expect(GhostDigest.fromJson(null).isEmpty, isTrue);
    });
  });

  test('a free player past 5 min: reason premium and the preview of a ghost, never an offer', () {
    final res = GhostOfferResponse.fromJson({
      'available': false,
      'reason': 'premium',
      'queueDelaySec': 300,
      'preview': {
        'username': 'Bruno_T19',
        'rank': 'gold',
        'elo': 1398,
        'cosmetics': {'level': 41, 'avatar': 'avatar.trophee', 'badges': []},
      },
    });
    expect(res.available, isFalse);
    expect(res.offer, isNull);
    expect(res.reason, GhostUnavailable.premium);
    expect(res.preview!.username, 'Bruno_T19');
    expect(res.preview!.rank, 'gold');
    expect(res.preview!.elo, 1398);
    expect(res.preview!.cosmetics?.level, 41);
    // Defensive: a preview without a name, or of another reason, is none.
    expect(GhostOfferResponse.fromJson({'reason': 'premium', 'preview': {'elo': 1}}).preview, isNull);
    expect(GhostOfferResponse.fromJson({'reason': 'premium', 'preview': 'x'}).preview, isNull);
    expect(GhostOfferResponse.fromJson({'reason': 'none', 'preview': {'username': 'A'}}).preview, isNull);
    final minimal = GhostPreview.fromJson({'username': 'A'})!;
    expect(minimal.rank, 'unranked');
    expect(minimal.cosmetics, isNull);
  });
}
