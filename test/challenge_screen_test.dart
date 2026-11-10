// The simplified daily challenge screen, B (docs/progression/ecrans/DefB1,
// DefB2, CONTRACT §14.10): the format's brief and board, the score to beat,
// the duel after the ranked try, the top 5, and the day that is over.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/l10n/app_localizations.dart';
import 'package:mobile/screens/challenge/challenge_api.dart';
import 'package:mobile/screens/challenge/challenge_mini_board.dart';
import 'package:mobile/screens/challenge/challenge_models.dart';
import 'package:mobile/screens/challenge/challenge_screen.dart';
import 'package:mobile/utils/app_theme.dart';

Map<String, dynamic> _format({String mode = 'cricket_marks', bool withBrief = true}) => {
      'id': 'cricket-30',
      'name': {'fr': 'Cricket · 30 fléchettes', 'en': 'Cricket · 30 darts'},
      'short': {'fr': 'Cricket · 30', 'en': 'Cricket · 30'},
      'rule': {
        'fr': '30 fléchettes sur 15 à 20 et le bull. Un triple = 3 marques, le 50 = 2.',
        'en': '30 darts at 15 to 20 and the bull. A treble = 3 marks, the bullseye = 2.',
      },
      if (withBrief) 'brief': {'fr': '15 à 20 et bull · triple = 3', 'en': '15–20 and bull · treble = 3'},
      if (withBrief)
        'board': {
          'segments': [
            {'numbers': [15, 16, 17, 18, 19, 20]},
          ],
          'bull': true,
        },
      'tag': {'fr': 'cricket', 'en': 'cricket'},
      'mode': mode,
      'params': {'darts': 30},
      'score': {'order': 'desc', 'unit': {'fr': 'marques', 'en': 'marks'}, 'max': 90},
      'tiebreak': {'order': 'desc', 'label': {'fr': 'triples', 'en': 'trebles'}},
      'durationMin': 4,
    };

ChallengeToday _today({
  Map<String, dynamic>? ranked,
  bool open = true,
  int players = 12,
  DateTime? endsAt,
  Map<String, dynamic>? format,
  String name = 'Cricket · 30 fléchettes',
}) =>
    ChallengeToday.fromJson({
      'date': '2026-11-09',
      'endsAt': (endsAt ?? DateTime.now().add(const Duration(hours: 14, minutes: 30))).toUtc().toIso8601String(),
      'format': {...(format ?? _format()), 'name': {'fr': name, 'en': name}},
      'board': {'rank': 'gold', 'ranks': ['gold'], 'open': open, 'players': players, 'eloBonus': 24},
      'players': 21,
      'ranked': ranked,
      'streak': {
        'current': 4,
        'best': 6,
        'freezeAvailable': true,
        'days': [
          for (var i = 3; i <= 9; i++) {'date': '2026-11-0$i', 'played': i >= 5 && i < 9, 'today': i == 9},
        ],
      },
      'remind': true,
      'yesterday': {'date': '2026-11-08', 'crownId': 'c1', 'board': 'gold', 'userId': 'u9', 'username': 'TripleTom', 'score': 44, 'verified': true},
    })!;

const _names = ['TripleTom', 'Kev_D20', 'LaFleche', 'Juju180', 'Mika_T19', 'Bruno_T19', 'Steph_D16', 'Zoe_Bull', 'Max180', 'Leo_D8', 'Ana_T20', 'Sam_S1'];

/// The rank board: [count] players, 41 then one less each; [me] = my place.
ChallengeLeaderboard _board({int count = 12, int? me, bool crown = true}) => ChallengeLeaderboard.fromJson({
      'date': '2026-11-09',
      'view': 'rank',
      'board': {'rank': 'gold', 'ranks': ['gold'], 'open': count >= 5, 'players': count},
      'counts': {'rank': count, 'all': 21, 'friends': 2},
      'rows': [
        for (var i = 1; i <= count; i++)
          if (i <= 50 || i == me)
            {
              'position': i,
              'userId': i == me ? 'me' : 'u$i',
              'username': i == me ? 'Dodo180' : _names[(i - 1) % _names.length],
              'rank': i.isOdd ? 'platinum' : 'gold',
              'score': 42 - i,
              'me': i == me,
              'crown': crown && i == 1,
            },
      ],
    });

Widget _app({Locale locale = const Locale('fr')}) => MaterialApp(
      theme: AppTheme.themeData,
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: const ChallengeScreen(),
    );

/// Seeds the store (and its reload) and the rank board, then opens the screen.
Future<void> _open(WidgetTester tester, ChallengeToday today, {ChallengeLeaderboard? board}) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  ChallengeStore.instance.debugSeed(today);
  ChallengeStore.instance.debugLoader = () async => today;
  final b = board ?? _board();
  ChallengeApi.debugLeaderboard = (view) async => b;
  await tester.pumpWidget(_app());
  await tester.pumpAndSettle();
}

double _scrollExtent(WidgetTester tester) =>
    tester.state<ScrollableState>(find.byType(Scrollable).first).position.maxScrollExtent;

void main() {
  tearDown(() {
    ChallengeStore.instance.debugLoader = null;
    ChallengeStore.instance.reset();
    ChallengeApi.debugLeaderboard = null;
  });

  group('models', () {
    test('a format carries its brief and the zones lit on the small board', () {
      final f = ChallengeFormat.fromJson(_format())!;
      expect(f.brief?.fr, '15 à 20 et bull · triple = 3');
      expect(f.board.all, isFalse);
      expect(f.board.lit(20, ChallengeRing.treble), isTrue);
      expect(f.board.lit(14, ChallengeRing.single), isFalse);
      expect(f.board.bullLit, isTrue);
      expect(f.board.numberLit(15), isTrue);
      expect(f.board.numberLit(1), isFalse);
    });

    test('an older server (no brief, no board): no brief, the whole board lit', () {
      final f = ChallengeFormat.fromJson(_format(withBrief: false))!;
      expect(f.brief, isNull);
      expect(f.board.all, isTrue);
      expect(f.board.lit(1, ChallengeRing.double), isTrue);
    });

    test('board selectors: numbers and rings narrow each other, garbage is dropped', () {
      final doubles = ChallengeBoardSpec.fromJson({
        'segments': [
          {'numbers': [20, 16, 8, 99, 'x'], 'rings': ['double', 'quad']},
          {'numbers': 'all'},
        ],
        'bull': false,
      })!;
      expect(doubles.segments, hasLength(1));
      expect(doubles.lit(16, ChallengeRing.double), isTrue);
      expect(doubles.lit(16, ChallengeRing.single), isFalse);
      expect(doubles.lit(1, ChallengeRing.double), isFalse);
      expect(doubles.bullLit, isFalse);
      final triples = ChallengeBoardSpec.fromJson({
        'segments': [
          {'rings': ['treble']},
        ],
      })!;
      expect(triples.lit(7, ChallengeRing.treble), isTrue);
      expect(triples.lit(7, ChallengeRing.single), isFalse);
      expect(ChallengeBoardSpec.fromJson({'segments': [], 'bull': true})!.numberLit(20), isFalse);
      expect(ChallengeBoardSpec.fromJson('all'), isNull);
      expect(ChallengeBoardSpec.fromJson({'all': true})!.all, isTrue);
    });
  });

  group('store: a day that is over', () {
    test('is never handed out, and a failed reload drops it', () async {
      final store = ChallengeStore.instance;
      store.debugSeed(_today(endsAt: DateTime.now().subtract(const Duration(minutes: 1))), userId: 'me');
      expect(store.today, isNull);
      expect(store.todayFor('me'), isNull);
      store.debugLoader = () async => throw Exception('offline');
      await store.refresh(userId: 'me');
      expect(store.today, isNull);
    });

    test('a failed reload keeps a snapshot whose day is still on', () async {
      final store = ChallengeStore.instance;
      store.debugSeed(_today(), userId: 'me');
      store.debugLoader = () async => throw Exception('offline');
      await store.refresh(userId: 'me');
      expect(store.todayFor('me')?.format.id, 'cricket-30');
    });
  });

  group('screen', () {
    testWidgets('before the try: format, score to beat, Play, top 5, nothing else, no scroll', (tester) async {
      await _open(tester, _today());
      expect(find.text('Défi du jour'), findsOneWidget);
      expect(find.text('4 j'), findsOneWidget);
      expect(find.byIcon(Icons.notifications_rounded), findsOneWidget);
      // Format card.
      expect(find.byType(ChallengeMiniBoard), findsOneWidget);
      expect(find.text('Cricket · 30 fléchettes'), findsOneWidget);
      expect(find.textContaining('15 à 20 et bull · triple = 3'), findsOneWidget);
      expect(find.textContaining('1 essai · caméra IA · fin dans 14 h'), findsOneWidget);
      // To beat.
      expect(find.text('À battre'), findsOneWidget);
      expect(find.text('marques'), findsOneWidget);
      expect(find.text('41'), findsNWidgets(2)); // the card and the first line
      expect(find.text('TripleTom'), findsNWidgets(2));
      // Play.
      expect(find.text('Jouer'), findsOneWidget);
      expect(find.text('+50 XP'), findsOneWidget);
      expect(find.text('N°1 : +24 ELO · top 10 % : +50 XP'), findsOneWidget);
      // Top 5 and its links.
      expect(find.text('Classement'), findsOneWidget);
      expect(find.text('Or'), findsOneWidget);
      expect(find.text('Tous'), findsOneWidget);
      expect(find.text('Amis'), findsOneWidget);
      expect(find.text('Mika_T19'), findsOneWidget);
      expect(find.text('Bruno_T19'), findsNothing);
      expect(find.text('Les 12 joueurs'), findsOneWidget);
      expect(find.text('N°1 d’hier'), findsOneWidget);
      // What left the screen.
      expect(find.text('Lancer le défi'), findsNothing);
      expect(find.text('Ta série'), findsNothing);
      expect(find.text('Rappel à 18 h'), findsNothing);
      expect(find.byType(Switch), findsNothing);
      expect(find.textContaining('Moins de 5 joueurs'), findsNothing);
      expect(_scrollExtent(tester), 0);
    });

    testWidgets('before the try, nobody yet: « Personne n’a encore joué », « Sois le premier »', (tester) async {
      await _open(tester, _today(players: 0, open: false), board: _board(count: 0));
      expect(find.text('Personne n’a encore joué'), findsOneWidget);
      expect(find.text('Sois le premier'), findsOneWidget);
      expect(find.text('À battre'), findsNothing);
      expect(find.text('Jouer'), findsOneWidget);
      expect(find.text('Aucun score pour l’instant.'), findsOneWidget);
      expect(find.textContaining('joueurs'), findsOneWidget); // only « Classement ouvert à 5 joueurs · 0/5 »
    });

    testWidgets('board not open yet: the count to 5 instead of the prizes, no crown', (tester) async {
      await _open(tester, _today(players: 3, open: false), board: _board(count: 3, crown: false));
      expect(find.text('Classement ouvert à 5 joueurs · 3/5'), findsOneWidget);
      expect(find.textContaining('+24 ELO'), findsNothing);
      expect(find.text('À battre'), findsOneWidget);
      expect(find.text('Les 3 joueurs'), findsOneWidget);
    });

    testWidgets('after the try, 2nd: me against the n°1, XP earned, practice', (tester) async {
      await _open(
        tester,
        _today(ranked: {'id': 'a1', 'status': 'submitted', 'score': 40, 'finished': true, 'position': 2, 'total': 12}),
        board: _board(me: 2),
      );
      expect(find.text('Toi'), findsOneWidget);
      expect(find.text('2ᵉ sur 12'), findsOneWidget);
      expect(find.text('vs'), findsOneWidget);
      expect(find.text('N°1'), findsOneWidget);
      expect(find.text('TripleTom'), findsNWidgets(2)); // duel + first line
      expect(find.text('+50 XP gagnés'), findsOneWidget);
      expect(find.text('Revoir mon essai'), findsOneWidget);
      expect(find.text('S’entraîner'), findsOneWidget);
      expect(find.text('· hors classement'), findsOneWidget);
      expect(find.text('Jouer'), findsNothing);
      expect(find.text('À battre'), findsNothing);
      expect(find.text('Dodo180 · toi'), findsOneWidget);
      expect(_scrollExtent(tester), 0);
    });

    testWidgets('after the try, 1st: against the n°2', (tester) async {
      await _open(
        tester,
        _today(ranked: {'id': 'a1', 'status': 'submitted', 'score': 41, 'finished': true, 'position': 1, 'total': 12}),
        board: _board(me: 1),
      );
      expect(find.text('1ᵉʳ sur 12'), findsOneWidget);
      expect(find.text('N°2'), findsOneWidget);
      expect(find.text('N°1'), findsNothing);
      expect(find.text('Kev_D20'), findsNWidgets(2));
    });

    testWidgets('after the try, alone: my tile only', (tester) async {
      await _open(
        tester,
        _today(players: 1, open: false, ranked: {'id': 'a1', 'status': 'submitted', 'score': 30, 'position': 1, 'total': 1}),
        board: _board(count: 1, me: 1, crown: false),
      );
      expect(find.text('Toi'), findsOneWidget);
      expect(find.text('vs'), findsNothing);
      expect(find.text('1ᵉʳ sur 1'), findsOneWidget);
      expect(find.text('1 joueur'), findsOneWidget);
    });

    testWidgets('beyond the top 5: my line added 6th with my real place', (tester) async {
      await _open(
        tester,
        _today(ranked: {'id': 'a1', 'status': 'submitted', 'score': 33, 'position': 9, 'total': 12}),
        board: _board(me: 9),
      );
      expect(find.text('Dodo180 · toi'), findsOneWidget);
      expect(find.text('9'), findsOneWidget);
      expect(find.text('Juju180'), findsOneWidget);
      expect(find.text('Bruno_T19'), findsNothing);
    });

    testWidgets('abandoned or excluded: the existing texts in my tile', (tester) async {
      await _open(tester, _today(ranked: {'id': 'a1', 'status': 'started'}));
      expect(find.text('Essai classé commencé mais pas terminé : il ne compte pas.'), findsOneWidget);
      expect(find.textContaining('XP gagnés'), findsNothing);
      expect(find.text('Revoir mon essai'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await _open(tester, _today(ranked: {'id': 'a1', 'status': 'excluded', 'excludedReason': 'no_proof'}));
      expect(find.text('Retiré du classement : ta vidéo n’est pas arrivée à temps.'), findsOneWidget);
      expect(find.text('+50 XP gagnés'), findsOneWidget);
    });

    testWidgets('a format this version cannot play: « Mets l’appli à jour », no button', (tester) async {
      await _open(tester, _today(format: _format(mode: 'darts_golf')));
      expect(find.text('Mets l’appli à jour pour jouer le format du jour.'), findsOneWidget);
      expect(find.text('Jouer'), findsNothing);
    });

    testWidgets('an older server without a brief: the short name stands in', (tester) async {
      await _open(tester, _today(format: _format(withBrief: false)));
      expect(find.textContaining('Cricket · 30'), findsWidgets);
      expect(find.textContaining('15 à 20 et bull'), findsNothing);
    });

    testWidgets('a day that is over and a failed reload: the error, never « Jouer »', (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      ChallengeStore.instance.debugSeed(_today(endsAt: DateTime.now().subtract(const Duration(minutes: 5))));
      ChallengeStore.instance.debugLoader = () async => throw Exception('offline');
      ChallengeApi.debugLeaderboard = (view) async => _board();
      await tester.pumpWidget(_app());
      // Before the reload answers: no day on screen.
      expect(find.text('Jouer'), findsNothing);
      await tester.pumpAndSettle();
      expect(find.text('Impossible de charger le défi.'), findsOneWidget);
      expect(find.text('Réessayer'), findsOneWidget);
      expect(find.text('Jouer'), findsNothing);
      expect(find.text('Cricket · 30 fléchettes'), findsNothing);

      // Retry once the network is back: today's challenge.
      ChallengeStore.instance.debugLoader = () async => _today(name: 'Bull');
      await tester.tap(find.text('Réessayer'));
      await tester.pumpAndSettle();
      expect(find.text('Bull'), findsOneWidget);
      expect(find.text('Jouer'), findsOneWidget);
    });

    testWidgets('the end of the day with the screen open reloads it', (tester) async {
      var loads = 0;
      await _open(tester, _today(endsAt: DateTime.now().add(const Duration(minutes: 3))));
      ChallengeStore.instance.debugLoader = () async {
        loads++;
        return _today(name: 'Bull');
      };
      await tester.pump(const Duration(minutes: 4));
      await tester.pumpAndSettle();
      expect(loads, 1);
      expect(find.text('Bull'), findsOneWidget);
    });

    testWidgets('ⓘ opens the full rule with what left the screen', (tester) async {
      await _open(tester, _today());
      await tester.tap(find.text('Cricket · 30 fléchettes'));
      await tester.pumpAndSettle();
      expect(find.text('Règle complète'), findsOneWidget);
      expect(find.text('30 fléchettes sur 15 à 20 et le bull. Un triple = 3 marques, le 50 = 2.'), findsOneWidget);
      expect(find.text('1 seul essai compte, les suivants sont de l’entraînement.'), findsOneWidget);
      expect(find.text('Caméra IA obligatoire. Si tu finis dans le top 3, ta session est filmée.'), findsOneWidget);
      expect(find.text('+50 XP pour jouer'), findsOneWidget);
      expect(find.text('+50 XP dans le top 10 %'), findsOneWidget);
      expect(find.text('N°1 Or : badge « N°1 du jour » et +24 ELO'), findsOneWidget);
    });

    testWidgets('the streak pill opens the week, the bell turns the reminder off', (tester) async {
      await _open(tester, _today());
      await tester.tap(find.text('4 j'));
      await tester.pumpAndSettle();
      expect(find.text('Ta série'), findsOneWidget);
      expect(find.text('1 gel de série en réserve'), findsOneWidget);
      Navigator.of(tester.element(find.text('Ta série'))).pop();
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.notifications_rounded));
      await tester.pump();
      expect(find.text('Rappel à 18 h désactivé'), findsOneWidget);
      expect(find.byIcon(Icons.notifications_off_outlined), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 3));
    });

    testWidgets('« Les 12 joueurs » opens the whole ranking with its counts', (tester) async {
      await _open(tester, _today());
      await tester.tap(find.text('Les 12 joueurs'));
      await tester.pumpAndSettle();
      expect(find.text('Classement du jour'), findsOneWidget);
      expect(find.text('Or · 12'), findsOneWidget);
      expect(find.text('Tous · 21'), findsOneWidget);
      expect(find.text('Sam_S1'), findsOneWidget);
    });
  });
}
