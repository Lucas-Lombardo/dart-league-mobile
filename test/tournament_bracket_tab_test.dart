import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:mobile/l10n/app_localizations.dart';
import 'package:mobile/models/tournament.dart';
import 'package:mobile/providers/tournament_provider.dart';
import 'package:mobile/screens/home/tournament_detail_screen.dart';
import 'package:mobile/widgets/tournament_bracket_tree.dart';

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
  DateTime? inviteSentAt,
}) {
  return TournamentMatch(
    id: id,
    tournamentId: 't1',
    roundNumber: round,
    roundName: roundName,
    matchNumber: number,
    player1Id: p1,
    player1Username: p1 == me ? 'DODO180' : p1?.toUpperCase(),
    player2Id: p2,
    player2Username: p2 == me ? 'DODO180' : p2?.toUpperCase(),
    status: status,
    player1Score: s1,
    player2Score: s2,
    winnerId: winner,
    bestOf: 3,
    nextMatchId: next,
    inviteSentAt: inviteSentAt,
  );
}

List<TournamentMatch> quarters() => [
  m(
    id: 'q1',
    round: 1,
    roundName: 'quarter_final',
    number: 1,
    p1: me,
    p2: 'steeltip',
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
    p1: 'vati99',
    p2: 'lucky26',
    status: 'completed',
    s1: 2,
    s2: 1,
    winner: 'vati99',
    next: 's1',
  ),
  m(
    id: 'q3',
    round: 1,
    roundName: 'quarter_final',
    number: 3,
    p1: 't20queen',
    p2: 'flight180',
    status: 'completed',
    s1: 2,
    winner: 't20queen',
    next: 's2',
  ),
  m(
    id: 'q4',
    round: 1,
    roundName: 'quarter_final',
    number: 4,
    p1: 'bullseye_max',
    p2: 'thedarter',
    status: 'completed',
    s1: 2,
    s2: 1,
    winner: 'bullseye_max',
    next: 's2',
  ),
];

TournamentMatch semi2() => m(
  id: 's2',
  round: 2,
  roundName: 'semi_final',
  number: 2,
  p1: 't20queen',
  p2: 'bullseye_max',
  status: 'in_progress',
  s1: 1,
  s2: 1,
  next: 'f',
);

Tournament tournament() => Tournament(
  id: 't1',
  name: 'Tournoi du Samedi',
  scheduledDate: DateTime(2026, 9, 6, 20, 30),
  status: 'in_progress',
  maxParticipants: 8,
  currentParticipants: 8,
  winnerEloReward: 500,
  currentRound: 2,
  totalRounds: 3,
);

Future<void> pumpTab(
  WidgetTester tester,
  List<TournamentMatch> bracket, {
  List<TournamentMatch> pending = const [],
  String? userId = me,
}) async {
  final provider = TournamentProvider();
  if (pending.isNotEmpty) {
    provider.debugSeedPendingMatches(pending, myUserId: me);
  }
  await tester.binding.setSurfaceSize(const Size(393, 852));
  await tester.pumpWidget(
    ChangeNotifierProvider<TournamentProvider>.value(
      value: provider,
      child: MaterialApp(
        locale: const Locale('fr'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: TournamentBracketTab(
            tournament: tournament(),
            bracket: bracket,
            live: const [],
            currentUserId: userId,
            onReturnedFromMatch: () async {},
          ),
        ),
      ),
    ),
  );
  // Localizations resolve asynchronously; one more frame for the marker
  // scroll callback.
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('finalist waiting for the other semi', (tester) async {
    await pumpTab(tester, [
      ...quarters(),
      m(
        id: 's1',
        round: 2,
        roundName: 'semi_final',
        number: 1,
        p1: me,
        p2: 'vati99',
        status: 'completed',
        s1: 2,
        s2: 1,
        winner: me,
        next: 'f',
      ),
      semi2(),
      m(id: 'f', round: 3, roundName: 'final', number: 1, p1: me),
    ]);

    expect(find.byType(TournamentBracketTree), findsOneWidget);
    expect(find.text('Vous êtes ici'), findsOneWidget);
    expect(find.text('Prochain match · Finale'), findsOneWidget);
    // The empty final slot is named after the match that fills it, in the
    // tree and in the card.
    expect(find.text('Gagnant demi 2'), findsNWidgets(2));
    expect(find.text('En direct'), findsOneWidget);
    expect(find.textContaining('T20QUEEN – BULLSEYE_MAX'), findsOneWidget);
    expect(find.text('Rejoindre le match'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('invited to the semi: join button and countdown', (tester) async {
    final semi = m(
      id: 's1',
      round: 2,
      roundName: 'semi_final',
      number: 1,
      p1: me,
      p2: 'vati99',
      status: 'waiting_for_players',
      next: 'f',
      inviteSentAt: DateTime.now().subtract(const Duration(minutes: 1)),
    );
    await pumpTab(
      tester,
      [
        ...quarters(),
        semi,
        semi2(),
        m(id: 'f', round: 3, roundName: 'final', number: 1),
      ],
      pending: [semi],
    );

    expect(find.text('Votre match · Demi-finale'), findsOneWidget);
    expect(find.text('Rejoindre le match'), findsOneWidget);
    expect(find.text('À toi de jouer'), findsOneWidget);
    expect(find.text('Gagnant demi 1'), findsOneWidget);
    expect(find.textContaining(RegExp(r'^0[0-6]:\d\d$')), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Dispose the countdown timer before the test ends.
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('eliminated in the semi', (tester) async {
    await pumpTab(tester, [
      ...quarters(),
      m(
        id: 's1',
        round: 2,
        roundName: 'semi_final',
        number: 1,
        p1: me,
        p2: 'vati99',
        status: 'completed',
        s1: 1,
        s2: 2,
        winner: 'vati99',
        next: 'f',
      ),
      semi2(),
      m(id: 'f', round: 3, roundName: 'final', number: 1, p1: 'vati99'),
    ]);

    expect(find.text('Éliminé ici'), findsOneWidget);
    expect(find.text('Éliminé en demi-finale'), findsOneWidget);
    expect(find.text('Battu 1 – 2'), findsOneWidget);
    expect(find.text('Rejoindre le match'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('spectator sees the tree without a card or marker', (
    tester,
  ) async {
    await pumpTab(tester, [
      ...quarters(),
      m(
        id: 's1',
        round: 2,
        roundName: 'semi_final',
        number: 1,
        p1: me,
        p2: 'vati99',
        status: 'completed',
        s1: 2,
        s2: 1,
        winner: me,
        next: 'f',
      ),
      semi2(),
      m(id: 'f', round: 3, roundName: 'final', number: 1, p1: me),
    ], userId: 'someone-else');

    expect(find.byType(TournamentBracketTree), findsOneWidget);
    expect(find.text('Vous êtes ici'), findsNothing);
    expect(find.text('Prochain match · Finale'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
