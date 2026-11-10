import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mobile/l10n/app_localizations.dart';
import 'package:mobile/models/match.dart';
import 'package:mobile/models/progression.dart';
import 'package:mobile/providers/progression_provider.dart';
import 'package:mobile/screens/challenge/challenge_entry.dart';
import 'package:mobile/screens/challenge/challenge_screen.dart';
import 'package:mobile/screens/chat/chat_thread_screen.dart';
import 'package:mobile/screens/league/league_models.dart';
import 'package:mobile/screens/progression/xp_summary_panel.dart';
import 'package:mobile/services/push_notification_service.dart';
import 'package:mobile/widgets/progression/progression_widgets.dart';
import 'package:mobile/widgets/recent_matches_widget.dart';

/// Finishing touches of the progression work (CONTRACT.md §14.7): the
/// nine-slice card frame, the avatar in lists without a rank, the league line
/// of the end-of-match screen and the cold-start push claim.

class _FakeProgression extends ProgressionProvider {
  _FakeProgression({this.feed});
  final XpFeed? feed;

  @override
  Future<void> refreshSummary() async {}
  @override
  Future<void> refreshQuests() async {}
  @override
  Future<void> refreshContent() async {}
  @override
  Future<XpFeed?> waitForXp(DateTime since, {String? expectRefId}) async => feed;
}

final _content = ProgressionContent.fromJson({
  'version': 'v1',
  'items': [
    {
      'id': 'avatar.couronne',
      'type': 'avatar',
      'name': {'fr': 'Couronne', 'en': 'Crown'},
      'source': {'kind': 'achievement', 'label': {'fr': 'succès', 'en': 'achievement'}},
      'render': {'kind': 'monogram', 'metal': 'or', 'shape': 'round'},
    },
    {
      'id': 'frame.laiton',
      'type': 'frame',
      'name': {'fr': 'Laiton', 'en': 'Brass'},
      'source': {'kind': 'level', 'level': 15, 'label': {'fr': 'niveau 15', 'en': 'level 15'}},
      'render': {'kind': 'frame', 'metal': 'laiton'},
    },
  ],
});

Widget _app(Widget child, {ProgressionProvider? provider, Locale locale = const Locale('fr')}) {
  final app = MaterialApp(
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
  if (provider == null) return app;
  return ChangeNotifierProvider<ProgressionProvider>.value(value: provider, child: app);
}

ProgressionProvider _seeded() => _FakeProgression()..debugSeed(content: _content);

const _frameOnly = PublicCosmetics(frame: 'frame.laiton', monogram: 'KD');

void main() {
  group('NineSliceFramePainter', () {
    const source = Size(240, 150);

    test('player card 358 × 150: corners 1:1, edges stretched on their own axis only', () {
      final cells = NineSliceFramePainter.cells(source, const Size(358, 150));
      expect(cells, hasLength(8)); // the empty centre is skipped
      final (topLeftSrc, topLeftDst) = cells[0];
      expect(topLeftSrc, const Rect.fromLTWH(0, 0, 30, 30));
      expect(topLeftDst, const Rect.fromLTWH(0, 0, 30, 30));
      final (topSrc, topDst) = cells[1];
      expect(topSrc, const Rect.fromLTRB(30, 0, 210, 30));
      expect(topDst, const Rect.fromLTRB(30, 0, 328, 30)); // wider, same height
      final (leftSrc, leftDst) = cells[3];
      expect(leftSrc.width, leftDst.width); // the side keeps its thickness
      final (bottomRightSrc, bottomRightDst) = cells[7];
      expect(bottomRightSrc, const Rect.fromLTRB(210, 120, 240, 150));
      expect(bottomRightDst, const Rect.fromLTRB(328, 120, 358, 150));
    });

    test('locker preview 358 × 90: the sides shrink in height, not in thickness', () {
      final cells = NineSliceFramePainter.cells(source, const Size(358, 90));
      final (leftSrc, leftDst) = cells[3];
      expect(leftSrc, const Rect.fromLTRB(0, 30, 30, 120));
      expect(leftDst, const Rect.fromLTRB(0, 30, 30, 60));
    });

    test('a card smaller than two corners scales everything down evenly', () {
      final cells = NineSliceFramePainter.cells(source, const Size(40, 40));
      // Corners of 20 × 20 meet: the edge cells are empty and left out.
      expect(cells.map((c) => c.$2), [
        const Rect.fromLTWH(0, 0, 20, 20),
        const Rect.fromLTWH(20, 0, 20, 20),
        const Rect.fromLTWH(0, 20, 20, 20),
        const Rect.fromLTWH(20, 20, 20, 20),
      ]);
      expect(NineSliceFramePainter.cells(source, Size.zero), isEmpty);
    });

    testWidgets('paints a picture on any card size', (tester) async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawRect(const Rect.fromLTWH(0, 0, 240, 150), Paint()..color = const Color(0xFFC9A646));
      final picture = recorder.endRecording();
      for (final size in const [Size(358, 150), Size(358, 90), Size(30, 30)]) {
        await tester.pumpWidget(Center(
          child: SizedBox.fromSize(
            size: size,
            child: CustomPaint(painter: NineSliceFramePainter(picture: picture, sourceSize: const Size(240, 150))),
          ),
        ));
        expect(tester.takeException(), isNull);
      }
      picture.dispose();
    });
  });

  group('avatar in lists that know no rank', () {
    test('wearsLook: an avatar or a frame this content knows', () {
      expect(FramedAvatar.wearsLook(_content, _frameOnly), isTrue);
      expect(FramedAvatar.wearsLook(_content, const PublicCosmetics(avatar: 'avatar.couronne')), isTrue);
      expect(FramedAvatar.wearsLook(_content, const PublicCosmetics(frame: 'frame.inconnu')), isFalse);
      expect(FramedAvatar.wearsLook(_content, null), isFalse);
      expect(FramedAvatar.wearsLook(null, _frameOnly), isFalse);
    });

    testWidgets('chat: a bare frame rings the initial; nothing worn = the old disc', (tester) async {
      await tester.pumpWidget(_app(
        const Row(children: [
          ChatAvatar(isSupport: false, username: 'kev', online: true, cosmetics: _frameOnly),
          ChatAvatar(isSupport: false, username: 'zoe', online: false),
        ]),
        provider: _seeded(),
      ));
      await tester.pump();
      expect(find.byType(FramedAvatar), findsOneWidget);
      expect(find.descendant(of: find.byType(FramedAvatar), matching: find.text('K')), findsOneWidget);
      expect(find.text('Z'), findsOneWidget);
      expect(tester.getSize(find.byType(ChatAvatar).first), const Size(40, 40));
    });

    testWidgets('history: the opponent avatar only when they wear one', (tester) async {
      Match match(Map<String, dynamic>? cosmetics) => Match.fromJson({
            'id': 'm1',
            'player1Id': 'me',
            'player2Id': 'op',
            'player1Username': 'Moi',
            'player2Username': 'Kev_D20',
            'player2Cosmetics': cosmetics,
            'status': 'completed',
            'matchType': 'ranked',
            'winnerId': 'me',
            'createdAt': '2026-11-08T10:00:00.000Z',
          });
      await tester.pumpWidget(_app(
        Column(children: [
          MatchRowTile(match: match({'frame': 'frame.laiton', 'monogram': 'KD'}), userId: 'me', onTap: () {}),
          MatchRowTile(match: match(null), userId: 'me', onTap: () {}),
        ]),
        provider: _seeded(),
      ));
      await tester.pump();
      expect(find.byType(FramedAvatar), findsOneWidget);
      expect(find.text('Kev_D20'), findsOneWidget); // next to its avatar
      expect(find.textContaining('Kev_D20'), findsNWidgets(2)); // "vs Kev_D20" on the other row
    });
  });

  group('end of match: league line', () {
    final feed = XpFeed(
      entries: [
        XpEntry(source: 'ranked_series', refId: 's1', amount: 60, label: LocalizedText.fromJson({'fr': 'Série classée', 'en': 'Ranked series'})),
      ],
      totalAmount: 60,
    );
    LeagueMatchDelta? delta(int before, int after) => LeagueMatchDelta.fromJson({
          'league': {'id': 'acier', 'order': 1, 'name': {'fr': 'Acier', 'en': 'Steel'}},
          'points': 50,
          'positionBefore': before,
          'positionAfter': after,
          'size': 20,
        });

    testWidgets('« Ligue Acier : +50 pts, tu passes de 6ᵉ à 4ᵉ. » under the XP card', (tester) async {
      await tester.pumpWidget(_app(
        XpSummaryPanel(since: DateTime(2026, 11, 8), loadLeague: (_) async => delta(6, 4)),
        provider: _FakeProgression(feed: feed),
      ));
      await tester.pump();
      await tester.pump();
      expect(find.text('Ligue Acier : +50 pts, tu passes de 6ᵉ à 4ᵉ.'), findsOneWidget);
    });

    testWidgets('same place, in English', (tester) async {
      await tester.pumpWidget(_app(
        XpSummaryPanel(since: DateTime(2026, 11, 8), loadLeague: (_) async => delta(1, 1)),
        provider: _FakeProgression(feed: feed),
        locale: const Locale('en'),
      ));
      await tester.pump();
      await tester.pump();
      expect(find.text('Steel League: +50 pts, you stay 1st.'), findsOneWidget);
    });

    testWidgets('no line without league points, and none on an old server', (tester) async {
      var calls = 0;
      await tester.pumpWidget(_app(
        XpSummaryPanel(
          since: DateTime(2026, 11, 8),
          loadLeague: (_) async {
            calls++;
            throw Exception('404');
          },
        ),
        provider: _FakeProgression(feed: feed),
      ));
      await tester.pump();
      await tester.pump();
      expect(calls, 1);
      expect(find.textContaining('Ligue'), findsNothing);
      expect(LeagueMatchDelta.fromJson({'league': {'id': 'acier'}, 'points': 0, 'positionBefore': 2, 'positionAfter': 2}), isNull);
      expect(LeagueMatchDelta.fromJson(null), isNull);
    });
  });

  group('cold-start push', () {
    tearDown(() => PushNotificationService.debugSetLaunchData(null));

    test('the launch tap is claimed once, by the consumer that wants it', () {
      final data = <String, dynamic>{'type': 'daily_challenge', 'date': '2026-11-08'};
      PushNotificationService.debugSetLaunchData(data);
      expect(PushNotificationService.claimLaunchData((d) => d['type'] == 'ghost_digest'), isNull);
      expect(PushNotificationService.claimLaunchData((d) => d['type'] == 'daily_challenge'), same(data));
      expect(PushNotificationService.claimLaunchData((d) => true), isNull);
    });

    testWidgets('the 18:00 push that cold-started the app opens the challenge, once', (tester) async {
      PushNotificationService.debugSetLaunchData(<String, dynamic>{'type': 'daily_challenge', 'date': '2026-11-08'});
      final pushed = <Route<dynamic>>[];
      final observer = _PushObserver(pushed);
      Widget app() => MaterialApp(
            navigatorObservers: [observer],
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(body: ChallengeHomeHooks()),
          );
      await tester.pumpWidget(app());
      await tester.pump();
      await tester.pump();
      expect(pushed.whereType<MaterialPageRoute<dynamic>>().length, 2); // home + the challenge
      expect(find.byType(ChallengeScreen, skipOffstage: false), findsOneWidget);
      // The home row mounting again (back from a match) does not reopen it.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(app());
      await tester.pump();
      await tester.pump();
      expect(find.byType(ChallengeScreen, skipOffstage: false), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    test('a listener that already acted on it marks it handled', () {
      final data = <String, dynamic>{'type': 'daily_challenge'};
      PushNotificationService.debugSetLaunchData(data);
      PushNotificationService.markHandled(<String, dynamic>{'type': 'daily_challenge'}); // another map
      PushNotificationService.markHandled(data);
      expect(PushNotificationService.claimLaunchData((d) => true), isNull);
    });
  });
}

class _PushObserver extends NavigatorObserver {
  _PushObserver(this.pushed);
  final List<Route<dynamic>> pushed;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => pushed.add(route);
}
