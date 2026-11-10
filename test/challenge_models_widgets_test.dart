import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/l10n/app_localizations.dart';
import 'package:mobile/screens/challenge/challenge_api.dart';
import 'package:mobile/screens/challenge/challenge_entry.dart';
import 'package:mobile/screens/challenge/challenge_models.dart';
import 'package:mobile/screens/challenge/challenge_session_screen.dart';
import 'package:mobile/screens/challenge/challenge_story.dart';
import 'package:mobile/screens/challenge/challenge_widgets.dart';
import 'package:mobile/screens/challenge/logic/challenge_engine.dart';
import 'package:mobile/screens/progression/today_section.dart';

final _format = {
  'id': 'score-max-15',
  'name': {'fr': 'Score max · 15 fléchettes', 'en': 'Max score · 15 darts'},
  'short': {'fr': 'Score max · 15', 'en': 'Max score · 15'},
  'rule': {'fr': '5 volées.', 'en': '5 visits.'},
  'tag': {'fr': 'scoring', 'en': 'scoring'},
  'mode': 'high_score',
  'params': {'visits': 5},
  'dayParams': <String, dynamic>{},
  'score': {'order': 'desc', 'unit': {'fr': 'points', 'en': 'points'}, 'max': 900},
  'tiebreak': {'order': 'desc', 'label': {'fr': 'meilleure volée', 'en': 'best visit'}},
  'durationMin': 2,
};

Map<String, dynamic> _todayJson({Map<String, dynamic>? ranked, int streak = 12}) => {
      'date': '2026-11-10',
      // Relative: a day that is over is never shown (ChallengeStore).
      'endsAt': DateTime.now().add(const Duration(hours: 10)).toUtc().toIso8601String(),
      'format': _format,
      'board': {'rank': 'platinum', 'ranks': ['platinum'], 'open': true, 'players': 9, 'eloBonus': 20},
      'players': 41,
      'ranked': ranked,
      'practiceCount': 0,
      'streak': {
        'current': streak,
        'best': 20,
        'freezeAvailable': true,
        'days': [
          for (var i = 4; i <= 10; i++) {'date': '2026-11-${i.toString().padLeft(2, '0')}', 'played': i < 10, 'today': i == 10},
        ],
      },
      'remind': true,
      'yesterday': {'date': '2026-11-09', 'crownId': 'c1', 'board': 'platinum', 'userId': 'u9', 'username': 'Kev_D20', 'score': 612, 'verified': true},
      'proofPending': [
        {'attemptId': 'a1', 'date': '2026-11-10', 'status': 'requested'},
      ],
    };

Widget _app(Widget child, {Locale locale = const Locale('fr')}) => MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );

void main() {
  group('models', () {
    test('today: format, board, streak, yesterday and pending videos', () {
      final t = ChallengeToday.fromJson(_todayJson())!;
      expect(t.format.id, 'score-max-15');
      expect(t.format.playable, isTrue);
      expect(t.format.lowerIsBetter, isFalse);
      expect(t.board.eloBonus, 20);
      expect(t.rankedAvailable, isTrue);
      expect(t.streak.days, hasLength(7));
      expect(t.streak.days.last.today, isTrue);
      expect(t.yesterday!.username, 'Kev_D20');
      expect(t.proofPending.single.attemptId, 'a1');
    });

    test('a format of a newer mode is shown but not playable', () {
      final f = ChallengeFormat.fromJson({..._format, 'mode': 'darts_golf'})!;
      expect(f.playable, isFalse);
    });

    test('garbage never throws', () {
      expect(ChallengeToday.fromJson(null), isNull);
      expect(ChallengeToday.fromJson({'date': 3, 'format': 'x'}), isNull);
      expect(ChallengeLeaderboard.fromJson('nope').rows, isEmpty);
      expect(ChallengePodium.fromJson(42).available, isFalse);
      expect(ChallengeResult.fromJson({'format': _format, 'attempt': {}}), isNull);
      expect(ChallengeSession.fromJson([]), isNull);
    });

    test('leaderboard rows and counts', () {
      final lb = ChallengeLeaderboard.fromJson({
        'date': '2026-11-10',
        'view': 'friends',
        'counts': {'rank': 9, 'all': 41, 'friends': 3},
        'rows': [
          {'position': 1, 'userId': 'u1', 'username': 'Kev_D20', 'rank': 'platinum', 'score': 612, 'crown': true},
          {'position': 2, 'userId': 'u2', 'username': 'Me', 'score': 587, 'me': true},
          {'username': 'no id'},
        ],
      });
      expect(lb.view, ChallengeView.friends);
      expect(lb.countFriends, 3);
      expect(lb.rows, hasLength(2));
      expect(lb.rows.first.crown, isTrue);
      expect(lb.rows.last.me, isTrue);
    });

    test('result: score, standing, passed players, proof', () {
      final r = ChallengeResult.fromJson({
        'date': '2026-11-10',
        'format': _format,
        'attempt': {'id': 'a1', 'ranked': true, 'status': 'submitted', 'score': 587, 'perVisit': [140, 100, 180, 67, 100], 'finished': true},
        'standing': {'board': 'platinum', 'position': 2, 'total': 9, 'rankPct': 22, 'allPosition': 4, 'allTotal': 41},
        'passed': [
          {'username': 'Steph_D16', 'score': 571},
          {'username': 'Bruno_T19', 'score': 540},
        ],
        'leader': {'username': 'Kev_D20', 'score': 612},
        'streak': {'current': 13, 'best': 20},
        'xp': [
          {'source': 'challenge', 'amount': 50},
        ],
        'proof': {'required': true, 'status': 'requested'},
      })!;
      expect(r.bestVisit, 180);
      expect(r.standing!.position, 2);
      expect(r.passed.map((p) => p.username), ['Steph_D16', 'Bruno_T19']);
      expect(r.xp, 50);
      expect(r.proofRequired, isTrue);
    });

    test('a visit outgoing to the server carries origin and time', () {
      final v = ChallengeVisitRecord(1000, [
        const ChallengeThrow(ChallengeDartT20.t20, ai: true),
        const ChallengeThrow(ChallengeDartT20.miss),
        const ChallengeThrow(ChallengeDartT20.t20, fixed: true),
      ]);
      expect(v.toJson(), {
        't': 1000,
        'darts': [
          {'n': 'T20', 'ai': true},
          {'n': 'M', 'ai': false},
          {'n': 'T20', 'ai': false, 'fix': true},
        ],
      });
    });

    test('the session video seek lands a few seconds before the visit', () {
      const clips = [ChallengeClip('a', startWallMs: 1000, durationMs: 60000), ChallengeClip('b', startWallMs: 70000, durationMs: 60000)];
      final first = challengeSeekFor(clips, 30000)!;
      expect(first.clip, 0);
      expect(first.offset, const Duration(seconds: 17));
      final second = challengeSeekFor(clips, 75000)!;
      expect(second.clip, 1);
      expect(second.offset, Duration.zero);
      expect(challengeSeekFor(clips, null), isNull);
    });
  });

  group('widgets', () {
    tearDown(() => ChallengeStore.instance.reset());

    testWidgets('home row: format, streak, then the place once played', (tester) async {
      ChallengeStore.instance.debugSeed(ChallengeToday.fromJson(_todayJson()), userId: 'me');
      await tester.pumpWidget(_app(const TodaySection(leading: [ChallengeTodayRow()])));
      await tester.pump();
      await tester.pump();
      expect(tester.getSize(find.byType(ChallengeTodayRow)).height, 60);
      expect(find.text('Défi du jour'), findsOneWidget);
      expect(find.text('Score max · 15'), findsOneWidget);
      expect(find.text('12 j'), findsOneWidget);

      ChallengeStore.instance.debugSeed(
        ChallengeToday.fromJson(_todayJson(ranked: {'id': 'a1', 'status': 'submitted', 'score': 587, 'position': 2, 'total': 9})),
        userId: 'me',
      );
      await tester.pump();
      expect(find.text('Score max · 15 · 2ᵉ / 9'), findsOneWidget);
    });

    testWidgets('leaderboard row: crown, and "not finished" for a capped fewest-darts score', (tester) async {
      final clock = ChallengeFormat.fromJson({..._format, 'mode': 'atc', 'params': {'cap': 99}, 'score': {'order': 'asc'}})!;
      await tester.pumpWidget(_app(Column(children: [
        ChallengeRowTile(row: const ChallengeRow(position: 1, userId: 'u1', username: 'Kev_D20', score: 42, crown: true), format: clock),
        ChallengeRowTile(row: const ChallengeRow(position: 2, userId: 'u2', username: 'Late', score: 100), format: clock),
      ])));
      await tester.pump();
      await tester.pump();
      expect(find.text('42'), findsOneWidget);
      expect(find.text('non fini'), findsOneWidget);
      expect(find.byIcon(Icons.workspace_premium_outlined), findsOneWidget);
    });

    testWidgets('story card 9:16 with score, place and streak', (tester) async {
      final r = ChallengeResult.fromJson({
        'date': '2026-11-10',
        'format': _format,
        'attempt': {'id': 'a1', 'ranked': true, 'score': 587},
        'standing': {'board': 'platinum', 'position': 2, 'total': 9, 'rankPct': 10, 'open': true},
        'streak': {'current': 13},
      })!;
      await tester.pumpWidget(_app(FittedBox(child: ChallengeStoryCard(result: r, username: 'Dodo180', rank: 'platinum'))));
      await tester.pump();
      await tester.pump();
      expect(find.text('587'), findsOneWidget);
      expect(find.text('top 10 %'), findsOneWidget);
      expect(find.text('2ᵉ Platine'), findsOneWidget);
      expect(find.text('série 13 j'), findsOneWidget);
      expect(find.text('Fais mieux que moi.'), findsOneWidget);
      expect(tester.getSize(find.byType(ChallengeStoryCard)), const Size(360, 640));
    });

    testWidgets('ordinals and board names in both languages', (tester) async {
      late BuildContext fr;
      await tester.pumpWidget(_app(Builder(builder: (c) {
        fr = c;
        return const SizedBox();
      })));
      await tester.pump();
      expect(challengeOrdinal(fr, 1), '1ᵉʳ');
      expect(challengeOrdinal(fr, 2), '2ᵉ');
      expect(challengeBoardName(AppLocalizations.of(fr), 'diamond'), contains('·'));
      late BuildContext en;
      await tester.pumpWidget(_app(Builder(builder: (c) {
        en = c;
        return const SizedBox();
      }), locale: const Locale('en')));
      await tester.pump();
      expect(challengeOrdinal(en, 2), '2nd');
      expect(challengeOrdinal(en, 13), '13th');
      expect(challengeOrdinal(en, 21), '21st');
    });
  });
}

/// Short names for the darts of the payload test.
class ChallengeDartT20 {
  static const t20 = _T20();
  static const miss = _Miss();
}

class _T20 extends ChallengeDart {
  const _T20() : super(20, 3, 60);
}

class _Miss extends ChallengeDart {
  const _Miss() : super(0, 0, 0);
}
