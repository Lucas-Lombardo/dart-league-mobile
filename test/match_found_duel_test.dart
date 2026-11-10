// "Match found", piste B « Duel » (docs/progression/ecrans/MtB, MtDeroule;
// CONTRACT §14.13): the two S1 cards on a diagonal, the ELO in large, what
// the series is worth, the record, and a 6 s scene — cards at 0.3 / 0.6 s,
// the VS at 0.9 s, the rest at 1.3 s, 3-2-1 over the last 3 s — after which
// the navigation gate opens the match.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:mobile/l10n/app_localizations.dart';
import 'package:mobile/models/head_to_head.dart';
import 'package:mobile/models/user.dart';
import 'package:mobile/providers/auth_provider.dart';
import 'package:mobile/providers/matchmaking_provider.dart';
import 'package:mobile/screens/progression/match_found_screen.dart';
import 'package:mobile/widgets/matchmaking_navigation_gate.dart';
import 'package:mobile/widgets/progression/player_showcase_card.dart';

Widget _app(Widget child, {bool reduceMotion = false}) => MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, navigator) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
        child: navigator!,
      ),
      home: child,
    );

const _me = MatchFoundPlayer(username: 'Dodo180', rank: 'gold', elo: 1409);
const _opponent = MatchFoundPlayer(username: 'LaFleche', rank: 'platinum', elo: 1612, isPremium: true);

MatchFoundScreen _ranked({
  int? eloIfWin = 56,
  int? eloIfLoss = -36,
  Future<HeadToHeadRecord?> Function(String)? loadRecord,
}) =>
    MatchFoundScreen(
      subtitle: 'Série classée · BO3 · 501',
      me: _me,
      opponent: _opponent,
      opponentId: 'u-opp',
      eloIfWin: eloIfWin,
      eloIfLoss: eloIfLoss,
      loadRecord: loadRecord ?? (_) async => const HeadToHeadRecord(wins: 7, losses: 5, encounters: 12),
    );

/// Mounts the screen; its scene starts (t = 0) on the last pump here.
Future<void> _open(WidgetTester tester, Widget screen, {bool reduceMotion = false}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  // A fresh key: a second _open in the same test gets a new state.
  await tester.pumpWidget(_app(KeyedSubtree(key: UniqueKey(), child: screen), reduceMotion: reduceMotion));
  // Localizations resolve asynchronously: wait for the screen without
  // moving the clock.
  for (var i = 0; i < 10 && find.byType(MatchFoundScreen).evaluate().isEmpty; i++) {
    await tester.pump();
  }
  expect(find.byType(MatchFoundScreen), findsOneWidget);
  await tester.pump();
}

/// Moves the scene to [ms] after it started.
Future<void> _at(WidgetTester tester, int ms, {required List<int> clock}) async {
  await tester.pump(Duration(milliseconds: ms - clock[0]));
  clock[0] = ms;
}

double _opacity(WidgetTester tester, Key key) => tester.widget<FadeTransition>(find.byKey(key)).opacity.value;

Offset _slide(WidgetTester tester, Key key) => tester
    .widget<SlideTransition>(find.descendant(of: find.byKey(key), matching: find.byType(SlideTransition)))
    .position
    .value;

double _vsScale(WidgetTester tester) => tester
    .widget<ScaleTransition>(find.descendant(of: find.byKey(MatchFoundScreen.vsKey), matching: find.byType(ScaleTransition)))
    .scale
    .value;

String? _digit(WidgetTester tester) {
  final texts = tester
      .widgetList<Text>(find.descendant(of: find.byKey(MatchFoundScreen.countdownKey), matching: find.byType(Text)))
      .map((t) => t.data)
      .where((d) => d == '1' || d == '2' || d == '3');
  return texts.isEmpty ? null : texts.single;
}

class _FakeAuth extends AuthProvider {
  @override
  User? get currentUser => User(id: 'u-me', username: 'Dodo180', email: 'd@x.fr', elo: 1409, rank: 'gold');
}

/// A match found by the queue, driven by the test.
class _FakeMatchmaking extends MatchmakingProvider {
  bool found = false;
  String? id;

  @override
  bool get matchFound => found;
  @override
  String? get matchId => id;
  @override
  String? get opponentId => found ? 'u-opp' : null;
  @override
  String? get opponentUsername => 'LaFleche';
  @override
  int? get opponentElo => 1612;
  @override
  int? get playerElo => 1409;
  @override
  int? get eloIfWin => 56;
  @override
  int? get eloIfLoss => -36;
  @override
  bool get opponentPremium => true;

  void matched() {
    found = true;
    id = 'm-1';
    notifyListeners();
  }

  void aborted() {
    found = false;
    id = null;
    notifyListeners();
  }
}

void main() {
  group('the screen', () {
    testWidgets('ranked: both cards, ELO, ranks, « En jeu » and the record (tutoiement, no pronoun)', (tester) async {
      await _open(tester, _ranked());
      await tester.pump(const Duration(milliseconds: 3200));

      expect(find.text('Match trouvé'), findsOneWidget);
      expect(find.text('Série classée · BO3 · 501'), findsOneWidget);
      expect(find.text('TOI'), findsOneWidget);
      expect(find.text('ADVERSAIRE'), findsOneWidget);
      expect(find.byType(PlayerShowcaseCard), findsNWidgets(2));
      // Neither « Modifier » nor an XP bar: plain cards.
      expect(tester.widgetList<PlayerShowcaseCard>(find.byType(PlayerShowcaseCard)).every((c) => c.onEdit == null && c.footer == null), isTrue);
      // The opponent's crown (opponentPremium), not mine.
      expect(find.byType(PremiumCrown), findsOneWidget);
      expect(find.text('1\u202f409'), findsOneWidget);
      expect(find.text('1\u202f612'), findsOneWidget);
      expect(find.text('Or'), findsOneWidget);
      expect(find.text('Platine'), findsOneWidget);
      expect(find.text('VS'), findsOneWidget);
      expect(find.text('En jeu'), findsOneWidget);
      expect(find.text('+56 / −36 ELO', findRichText: true), findsOneWidget);
      expect(find.text('Bilan 7 – 5'), findsOneWidget);
      expect(find.text('Le match commence'), findsOneWidget);
      expect(find.textContaining('Votre'), findsNothing);
      expect(find.textContaining('contre lui'), findsNothing);
      // No skip button: nothing to tap.
      expect(find.byType(ButtonStyleButton), findsNothing);

      // The opponent's side is right-aligned, mine left-aligned.
      final screen = tester.getRect(find.byType(MatchFoundScreen));
      expect(tester.getTopLeft(find.text('TOI')).dx, closeTo(16, 0.5));
      expect(tester.getTopRight(find.text('ADVERSAIRE')).dx, closeTo(screen.width - 16, 0.5));
      expect(tester.getTopRight(find.text('1\u202f612')).dx, closeTo(screen.width - 16, 0.5));
      // The stakes bottom left, the ring bottom right, under the duel.
      expect(tester.getTopLeft(find.text('En jeu')).dx, closeTo(16, 0.5));
      expect(tester.getTopRight(find.text('Le match commence')).dx, closeTo(screen.width - 16, 0.5));
      expect(tester.getTopLeft(find.text('En jeu')).dy, greaterThan(tester.getBottomLeft(find.text('1\u202f612')).dy));
      expect(tester.takeException(), isNull);
    });

    testWidgets('no stakes (placement, an older server): no « En jeu » line, the record stays', (tester) async {
      await _open(tester, _ranked(eloIfWin: null, eloIfLoss: null));
      await tester.pump(const Duration(milliseconds: 2000));

      expect(find.text('En jeu'), findsNothing);
      expect(find.textContaining('ELO', findRichText: true), findsNothing);
      expect(find.text('Bilan 7 – 5'), findsOneWidget);
      // One known, the other not: still hidden, never half a line.
      await _open(tester, _ranked(eloIfWin: 18, eloIfLoss: null));
      await tester.pump(const Duration(milliseconds: 2000));
      expect(find.text('En jeu'), findsNothing);
    });

    testWidgets('ghost: « FANTÔME », its match as the record line, its stakes, no head-to-head call', (tester) async {
      var asked = 0;
      await _open(
        tester,
        MatchFoundScreen(
          subtitle: 'Match fantôme · BO3 · 501',
          isGhost: true,
          recordLine: 'Son match du 2 nov. · moyenne 55,2',
          me: _me,
          opponent: const MatchFoundPlayer(username: 'Bruno_T19', rank: 'gold', elo: 1398),
          opponentId: 'u-owner',
          eloIfWin: 13,
          eloIfLoss: -12,
          loadRecord: (_) async {
            asked++;
            return const HeadToHeadRecord(wins: 1, losses: 1, encounters: 2);
          },
        ),
      );
      await tester.pump(const Duration(milliseconds: 2000));

      expect(find.text('FANTÔME'), findsOneWidget);
      expect(find.text('ADVERSAIRE'), findsNothing);
      expect(find.text('Match fantôme · BO3 · 501'), findsOneWidget);
      expect(find.text('Son match du 2 nov. · moyenne 55,2'), findsOneWidget);
      expect(find.text('+13 / −12 ELO', findRichText: true), findsOneWidget);
      expect(find.textContaining('Bilan'), findsNothing);
      expect(asked, 0);
    });

    testWidgets('first meeting, no record at all, a failing record', (tester) async {
      await _open(tester, _ranked(loadRecord: (_) async => const HeadToHeadRecord()));
      await tester.pump(const Duration(milliseconds: 2000));
      expect(find.text('Première rencontre'), findsOneWidget);
      expect(find.textContaining('Bilan'), findsNothing);

      await _open(tester, _ranked(loadRecord: (_) async => null));
      await tester.pump(const Duration(milliseconds: 2000));
      expect(find.text('Première rencontre'), findsNothing);
      expect(find.textContaining('Bilan'), findsNothing);
      expect(find.text('En jeu'), findsOneWidget);

      await _open(tester, _ranked(loadRecord: (_) async => throw Exception('offline')));
      await tester.pump(const Duration(milliseconds: 2000));
      expect(find.textContaining('Bilan'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a player without any item keeps a real S1 card (steel, plain ground, rank badge)', (tester) async {
      await _open(
        tester,
        MatchFoundScreen(
          subtitle: 's',
          me: _me,
          opponent: const MatchFoundPlayer(username: 'Newbie', rank: 'silver', elo: 905),
        ),
      );
      await tester.pump(const Duration(milliseconds: 2000));
      final card = tester.widget<PlayerShowcaseCard>(
        find.ancestor(of: find.text('Newbie'), matching: find.byType(PlayerShowcaseCard)),
      );
      expect(card.cosmetics, isNull);
      expect(card.rank, 'silver');
      // The rim is the steel gradient, the art is the plain surface.
      final rim = tester
          .widgetList<Container>(find.descendant(of: find.byWidget(card), matching: find.byType(Container)))
          .map((c) => c.decoration)
          .whereType<BoxDecoration>()
          .firstWhere((d) => d.gradient is LinearGradient);
      expect((rim.gradient! as LinearGradient).colors.first, const Color(0xFFE2E8F0));
      expect(
        find.descendant(of: find.byWidget(card), matching: find.byWidgetPredicate((w) => w is ColoredBox && w.color == const Color(0xFF1E293B))),
        findsOneWidget,
      );
      expect(find.descendant(of: find.byWidget(card), matching: find.byType(Image)), findsWidgets);
    });

    testWidgets('the order of the scene: me 0.3 s, them 0.6 s, VS 0.9 s, the rest 1.3 s, 3-2-1 from 3 s', (tester) async {
      await _open(tester, _ranked());
      final clock = [0];

      await _at(tester, 250, clock: clock);
      expect(_opacity(tester, MatchFoundScreen.meKey), 0);
      expect(_opacity(tester, MatchFoundScreen.opponentKey), 0);
      expect(_slide(tester, MatchFoundScreen.meKey).dx, lessThan(-1));

      // My card slides in from the left.
      await _at(tester, 450, clock: clock);
      expect(_opacity(tester, MatchFoundScreen.meKey), greaterThan(0.5));
      expect(_slide(tester, MatchFoundScreen.meKey).dx, inExclusiveRange(-1.15, 0));
      expect(_opacity(tester, MatchFoundScreen.opponentKey), 0);

      // Theirs from the right; mine has landed.
      await _at(tester, 800, clock: clock);
      expect(_slide(tester, MatchFoundScreen.meKey), Offset.zero);
      expect(_opacity(tester, MatchFoundScreen.opponentKey), 1);
      expect(_slide(tester, MatchFoundScreen.opponentKey).dx, inExclusiveRange(0, 1.15));
      expect(_opacity(tester, MatchFoundScreen.vsKey), 0);

      // The VS drops (larger, then lands with a small bounce under 1).
      await _at(tester, 950, clock: clock);
      expect(_opacity(tester, MatchFoundScreen.vsKey), greaterThan(0));
      expect(_vsScale(tester), greaterThan(1.2));
      await _at(tester, 1150, clock: clock);
      expect(_vsScale(tester), lessThan(1));
      expect(_opacity(tester, MatchFoundScreen.myDetailsKey), 0);
      expect(_opacity(tester, MatchFoundScreen.stakesKey), 0);

      // Ranks, ELO, stakes and record fade in.
      await _at(tester, 1450, clock: clock);
      expect(_opacity(tester, MatchFoundScreen.myDetailsKey), inExclusiveRange(0, 1));
      await _at(tester, 1700, clock: clock);
      expect(_vsScale(tester), 1);
      for (final key in [MatchFoundScreen.myDetailsKey, MatchFoundScreen.opponentDetailsKey, MatchFoundScreen.stakesKey]) {
        expect(_opacity(tester, key), 1);
      }
      expect(_opacity(tester, MatchFoundScreen.countdownKey), 0);

      // 3, 2, 1.
      await _at(tester, 2950, clock: clock);
      expect(_opacity(tester, MatchFoundScreen.countdownKey), 0);
      await _at(tester, 3300, clock: clock);
      expect(_opacity(tester, MatchFoundScreen.countdownKey), 1);
      expect(_digit(tester), '3');
      await _at(tester, 4100, clock: clock);
      expect(_digit(tester), '2');
      await _at(tester, 5100, clock: clock);
      expect(_digit(tester), '1');
      await _at(tester, 6000, clock: clock);
      expect(_digit(tester), '1');
      expect(tester.takeException(), isNull);
    });

    testWidgets('reduced motion: everything is there at once, nothing slides; still 3-2-1 over 6 s', (tester) async {
      await _open(tester, _ranked(), reduceMotion: true);
      await tester.pump();

      for (final key in [
        MatchFoundScreen.meKey,
        MatchFoundScreen.opponentKey,
        MatchFoundScreen.vsKey,
        MatchFoundScreen.myDetailsKey,
        MatchFoundScreen.opponentDetailsKey,
        MatchFoundScreen.stakesKey,
        MatchFoundScreen.countdownKey,
      ]) {
        expect(_opacity(tester, key), 1, reason: '$key');
      }
      expect(_slide(tester, MatchFoundScreen.meKey), Offset.zero);
      expect(_slide(tester, MatchFoundScreen.opponentKey), Offset.zero);
      expect(_vsScale(tester), 1);
      expect(find.text('+56 / −36 ELO', findRichText: true), findsOneWidget);
      expect(_digit(tester), '3');

      final clock = [0];
      await _at(tester, 950, clock: clock);
      expect(_vsScale(tester), 1);
      await _at(tester, 3500, clock: clock);
      expect(_digit(tester), '3');
      await _at(tester, 4100, clock: clock);
      expect(_digit(tester), '2');
      await _at(tester, 5100, clock: clock);
      expect(_digit(tester), '1');
    });

    testWidgets('a short screen scales both sides down together, nothing overflows', (tester) async {
      tester.view.physicalSize = const Size(375, 560);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app(_ranked()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 3200));
      expect(tester.takeException(), isNull);
      // Painted size (after the FittedBox's scale), not the layout size.
      final me = tester.getRect(find.byType(PlayerShowcaseCard).first);
      final them = tester.getRect(find.byType(PlayerShowcaseCard).last);
      expect(me.width, closeTo(them.width, 0.01));
      expect(me.height, closeTo(them.height, 0.01));
      expect(me.height, lessThan(140));
      expect(them.bottom, lessThan(tester.getTopLeft(find.text('Le match commence')).dy));
      expect(find.text('Le match commence'), findsOneWidget);
    });
  });

  group('navigation (MatchmakingNavigationGate)', () {
    late GlobalKey<NavigatorState> navigatorKey;

    setUp(() {
      navigatorKey = GlobalKey<NavigatorState>();
      MatchmakingNavigationGate.debugGameScreen = (matchId, _) => Scaffold(body: Text('GAME $matchId'));
      MatchFoundScreen.debugLoadRecord = (_) async => const HeadToHeadRecord(wins: 7, losses: 5, encounters: 12);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(
        'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
        (_) async => const StandardMessageCodec().encodeMessage([null]),
      );
    });

    tearDown(() {
      MatchmakingNavigationGate.debugGameScreen = null;
      MatchFoundScreen.debugLoadRecord = null;
    });

    Future<_FakeMatchmaking> pumpGate(WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final matchmaking = _FakeMatchmaking();
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<MatchmakingProvider>.value(value: matchmaking),
          ChangeNotifierProvider<AuthProvider>.value(value: _FakeAuth()),
        ],
        child: MaterialApp(
          navigatorKey: navigatorKey,
          locale: const Locale('fr'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MatchmakingNavigationGate(navigatorKey: navigatorKey, child: child!),
          home: const Scaffold(body: Text('HOME')),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('HOME'), findsOneWidget);
      return matchmaking;
    }

    testWidgets('a ranked match: the duel with the server stakes, then the game at 6 s, not before', (tester) async {
      final matchmaking = await pumpGate(tester);
      matchmaking.matched();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 3000));

      expect(find.byType(MatchFoundScreen), findsOneWidget);
      expect(find.text('+56 / −36 ELO', findRichText: true), findsOneWidget);
      expect(find.byType(PremiumCrown), findsOneWidget);
      expect(find.text('Bilan 7 – 5'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 2900));
      expect(find.text('GAME m-1'), findsNothing);
      expect(find.byType(MatchFoundScreen), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();
      expect(find.text('GAME m-1'), findsOneWidget);
      expect(find.byType(MatchFoundScreen), findsNothing);
      // pushAndRemoveUntil: only the home under the game.
      expect(navigatorKey.currentState!.canPop(), isTrue);
      navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.text('HOME'), findsOneWidget);
    });

    testWidgets('a match cancelled during the screen closes it and never opens the game', (tester) async {
      final matchmaking = await pumpGate(tester);
      matchmaking.matched();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 2000));
      expect(find.byType(MatchFoundScreen), findsOneWidget);

      matchmaking.aborted();
      await tester.pumpAndSettle();
      expect(find.byType(MatchFoundScreen), findsNothing);
      expect(find.text('HOME'), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.textContaining('GAME'), findsNothing);
    });

    testWidgets('a ghost goes through the same 6 s', (tester) async {
      await pumpGate(tester);
      bool? opened;
      MatchmakingNavigationGate.openGhostMatch(
        matchFound: const MatchFoundScreen(
          subtitle: 'Match fantôme · BO3 · 501',
          isGhost: true,
          recordLine: 'Son match du 2 nov. · moyenne 55,2',
          me: _me,
          opponent: MatchFoundPlayer(username: 'Bruno_T19', rank: 'gold', elo: 1398),
          eloIfWin: 13,
          eloIfLoss: -12,
        ),
        destination: (_) => const Scaffold(body: Text('GHOST MATCH')),
      ).then((v) => opened = v);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 5900));
      expect(find.text('FANTÔME'), findsOneWidget);
      expect(find.text('GHOST MATCH'), findsNothing);

      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();
      expect(find.text('GHOST MATCH'), findsOneWidget);
      expect(find.byType(MatchFoundScreen), findsNothing);
      expect(opened, isTrue);
    });
  });
}
