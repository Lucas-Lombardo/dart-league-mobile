import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/tournament.dart';
import 'package:mobile/utils/tournament_bracket_logic.dart';

// 8-player bracket, BO3. Quarter-finals done, semi 1 won by "me", semi 2 live,
// final: me vs the winner of semi 2.
const me = 'u-me';

TournamentMatch m({
  required String id,
  required int round,
  required String roundName,
  required int number,
  String? p1,
  String? p2,
  String status = 'pending',
  int s1 = 0,
  int s2 = 0,
  String? winner,
  String? next,
}) {
  return TournamentMatch(
    id: id,
    tournamentId: 't1',
    roundNumber: round,
    roundName: roundName,
    matchNumber: number,
    player1Id: p1,
    player1Username: p1,
    player2Id: p2,
    player2Username: p2,
    status: status,
    player1Score: s1,
    player2Score: s2,
    winnerId: winner,
    bestOf: 3,
    nextMatchId: next,
  );
}

List<TournamentMatch> sampleBracket({
  String semi1Status = 'completed',
  String? semi1Winner = me,
  String? finalP1 = me,
  int semi1Me = 2,
  int semi1Opp = 1,
}) {
  return [
    m(
      id: 'q1',
      round: 1,
      roundName: 'quarter_final',
      number: 1,
      p1: me,
      p2: 'steel',
      status: 'completed',
      s1: 2,
      winner: me,
      next: 's1',
    ),
    m(
      id: 'q2',
      round: 1,
      roundName: 'quarter_final',
      number: 2,
      p1: 'vati',
      p2: 'lucky',
      status: 'completed',
      s1: 2,
      s2: 1,
      winner: 'vati',
      next: 's1',
    ),
    m(
      id: 'q3',
      round: 1,
      roundName: 'quarter_final',
      number: 3,
      p1: 'queen',
      p2: 'flight',
      status: 'completed',
      s1: 2,
      winner: 'queen',
      next: 's2',
    ),
    m(
      id: 'q4',
      round: 1,
      roundName: 'quarter_final',
      number: 4,
      p1: 'bull',
      p2: 'darter',
      status: 'completed',
      s1: 2,
      s2: 1,
      winner: 'bull',
      next: 's2',
    ),
    m(
      id: 's1',
      round: 2,
      roundName: 'semi_final',
      number: 1,
      p1: me,
      p2: 'vati',
      status: semi1Status,
      s1: semi1Me,
      s2: semi1Opp,
      winner: semi1Winner,
      next: 'f',
    ),
    m(
      id: 's2',
      round: 2,
      roundName: 'semi_final',
      number: 2,
      p1: 'queen',
      p2: 'bull',
      status: 'in_progress',
      s1: 1,
      s2: 1,
      next: 'f',
    ),
    m(id: 'f', round: 3, roundName: 'final', number: 1, p1: finalP1),
  ];
}

void main() {
  group('BracketIndex', () {
    test('groups rounds, sorts matches and links feeders in slot order', () {
      final index = BracketIndex(sampleBracket());
      expect(index.rounds, [1, 2, 3]);
      expect(index.byRound[1]!.map((x) => x.id), ['q1', 'q2', 'q3', 'q4']);
      expect(index.feedersOf(index.byId['f']!).map((x) => x.id), ['s1', 's2']);
      expect(index.isRoundComplete(1), isTrue);
      expect(index.isRoundComplete(2), isFalse);
      expect(index.activeRound, 2);
      expect(index.isFinal(index.byId['f']!), isTrue);
    });

    test('names the unfinished feeder of an empty slot', () {
      final index = BracketIndex(sampleBracket());
      final f = index.byId['f']!;
      expect(index.pendingFeederOf(f)?.id, 's2');
      expect(index.feederForSlot(f, 1)?.id, 's2');
      expect(index.feederForSlot(f, 0)?.id, 's1');
    });
  });

  group('resolveTournamentFocus', () {
    test('finalist waiting for the other semi', () {
      final index = BracketIndex(sampleBracket());
      final focus = resolveTournamentFocus(
        index: index,
        userId: me,
        pendingMatches: const [],
      );
      expect(focus.kind, TournamentFocusKind.waiting);
      expect(focus.match?.id, 'f');
      expect(focus.dependency?.id, 's2');
    });

    test('invited to a match both players are known for → ready', () {
      final bracket = sampleBracket(
        semi1Status: 'waiting_for_players',
        semi1Winner: null,
        finalP1: null,
        semi1Me: 0,
        semi1Opp: 0,
      );
      final index = BracketIndex(bracket);
      final semi = index.byId['s1']!;
      final focus = resolveTournamentFocus(
        index: index,
        userId: me,
        pendingMatches: [semi],
      );
      expect(focus.kind, TournamentFocusKind.ready);
      expect(focus.match?.id, 's1');
    });

    test('same match without an invite → waiting, no dependency', () {
      final bracket = sampleBracket(
        semi1Status: 'pending',
        semi1Winner: null,
        finalP1: null,
        semi1Me: 0,
        semi1Opp: 0,
      );
      final focus = resolveTournamentFocus(
        index: BracketIndex(bracket),
        userId: me,
        pendingMatches: const [],
      );
      expect(focus.kind, TournamentFocusKind.waiting);
      expect(focus.dependency, isNull);
    });

    test('lost the semi → eliminated on that match', () {
      final bracket = sampleBracket(
        semi1Winner: 'vati',
        finalP1: 'vati',
        semi1Me: 1,
        semi1Opp: 2,
      );
      final focus = resolveTournamentFocus(
        index: BracketIndex(bracket),
        userId: me,
        pendingMatches: const [],
      );
      expect(focus.kind, TournamentFocusKind.eliminated);
      expect(focus.match?.id, 's1');
    });

    test('live leg to reconnect to → resumable', () {
      final bracket = sampleBracket(
        semi1Status: 'in_progress',
        semi1Winner: null,
        finalP1: null,
        semi1Me: 1,
        semi1Opp: 0,
      );
      final index = BracketIndex(bracket);
      final active = TournamentMatch(
        id: 's1',
        tournamentId: 't1',
        roundNumber: 2,
        roundName: 'semi_final',
        matchNumber: 1,
        status: 'in_progress',
        player1Score: 1,
        player2Score: 0,
        bestOf: 3,
        lastGameId: 'game-42',
      );
      final focus = resolveTournamentFocus(
        index: index,
        userId: me,
        pendingMatches: const [],
        activeMatch: active,
      );
      expect(focus.kind, TournamentFocusKind.resumable);
    });

    test('spectator or unknown user → none', () {
      final index = BracketIndex(sampleBracket());
      expect(
        resolveTournamentFocus(
          index: index,
          userId: 'nobody',
          pendingMatches: const [],
        ).isNone,
        isTrue,
      );
      expect(
        resolveTournamentFocus(
          index: index,
          userId: null,
          pendingMatches: const [],
        ).isNone,
        isTrue,
      );
    });

    test('won matches make the blue path', () {
      final index = BracketIndex(sampleBracket());
      expect(wonMatchIds(index, me), {'q1', 's1'});
    });
  });

  group('computeBracketLayout', () {
    test(
      'collapses finished rounds, keeps the last one, aligns parents on feeders',
      () {
        final index = BracketIndex(sampleBracket());
        final layout = computeBracketLayout(index);

        expect(layout.compactRounds, {1});
        expect(layout.columnWidth[1], 92);
        expect(layout.columnWidth[2], 124);
        expect(layout.columnWidth[3], 124);
        // Three columns, two gutters: 92 + 16 + 124 + 16 + 124.
        expect(layout.width, 372);

        final q1 = layout.byMatchId['q1']!;
        final q2 = layout.byMatchId['q2']!;
        final s1 = layout.byMatchId['s1']!;
        final s2 = layout.byMatchId['s2']!;
        final f = layout.byMatchId['f']!;
        expect(q1.y, 28); // top inset leaves room for the marker
        expect(q2.y, 28 + 53 + 16);
        expect(s1.centerY, closeTo((q1.centerY + q2.centerY) / 2, 0.001));
        expect(f.centerY, closeTo((s1.centerY + s2.centerY) / 2, 0.001));
        expect(s1.x, 92 + 16);
        expect(f.x, 92 + 16 + 124 + 16);
        // Everything fits a phone width once the horizontal padding is added.
        expect(layout.width + 20, lessThanOrEqualTo(393));
      },
    );

    test('never overlaps tiles of the same column', () {
      // 16 players: two full rounds of 8 and 4 matches.
      final bracket = <TournamentMatch>[];
      for (var i = 1; i <= 8; i++) {
        bracket.add(
          m(
            id: 'r$i',
            round: 1,
            roundName: 'round_of_16',
            number: i,
            p1: 'a$i',
            p2: 'b$i',
            next: 'q${(i + 1) ~/ 2}',
          ),
        );
      }
      for (var i = 1; i <= 4; i++) {
        bracket.add(
          m(
            id: 'q$i',
            round: 2,
            roundName: 'quarter_final',
            number: i,
            next: 's${(i + 1) ~/ 2}',
          ),
        );
      }
      for (var i = 1; i <= 2; i++) {
        bracket.add(
          m(id: 's$i', round: 3, roundName: 'semi_final', number: i, next: 'f'),
        );
      }
      bracket.add(m(id: 'f', round: 4, roundName: 'final', number: 1));

      final layout = computeBracketLayout(BracketIndex(bracket));
      for (final round in [1, 2, 3, 4]) {
        final tiles = layout.tiles.where((t) => t.round == round).toList();
        for (var i = 1; i < tiles.length; i++) {
          expect(tiles[i].y, greaterThanOrEqualTo(tiles[i - 1].bottom));
        }
      }
      expect(layout.compactRounds, isEmpty);
    });
  });
}
