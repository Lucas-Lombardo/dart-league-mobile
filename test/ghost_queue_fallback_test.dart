// The ghost as the ranked queue's fallback (CONTRACT §14.12): no ghost
// tile on the home any more (« Jouer autrement » = 3 tiles of the same size),
// and in the queue card B at 5 min (mockups FgBp / FgBg): the ghost's player
// card faded with « FANTÔME », « Ses vraies fléchettes, rejouées », then
// « Jouer +40 XP » or « Attendre », which folds it into a link at the bottom
// for the rest of the search. A free player sees the same card blurred
// behind a gold lock, with « Premium » instead of « Jouer ».
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:mobile/l10n/app_localizations.dart';
import 'package:mobile/models/progression.dart';
import 'package:mobile/models/user.dart';
import 'package:mobile/providers/auth_provider.dart';
import 'package:mobile/providers/matchmaking_provider.dart';
import 'package:mobile/providers/progression_provider.dart';
import 'package:mobile/providers/subscription_provider.dart';
import 'package:mobile/screens/ghost/ghost_models.dart';
import 'package:mobile/screens/ghost/ghost_play_row.dart';
import 'package:mobile/screens/ghost/ghost_queue_offer.dart';
import 'package:mobile/screens/ghost/ghost_service.dart';
import 'package:mobile/screens/ghost/ghost_widgets.dart';
import 'package:mobile/screens/home/home_other_modes.dart';
import 'package:mobile/screens/matchmaking/matchmaking_screen.dart';
import 'package:mobile/utils/app_theme.dart';
import 'package:mobile/widgets/home_tiles.dart';
import 'package:mobile/widgets/progression/player_showcase_card.dart';

Widget _l10n(Widget home) => MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    );

class _FakeAuth extends AuthProvider {
  @override
  User? get currentUser => User(id: 'u-me', username: 'Dodo180', email: 'd@x.fr', elo: 1409, rank: 'gold', isPremium: true);
}

class _FakeSubscription extends SubscriptionProvider {
  bool premium;

  /// What the server says once the subscription screen is closed.
  bool premiumAfterRefresh = false;
  int refreshes = 0;
  _FakeSubscription({required this.premium});
  @override
  bool get isPremiumActive => premium;
  @override
  Future<void> refresh() async {
    refreshes++;
    if (premiumAfterRefresh && !premium) {
      premium = true;
      notifyListeners();
    }
  }
}

/// The queue clock, set by the test instead of ticking for 5 minutes.
class _FakeMatchmaking extends MatchmakingProvider {
  int seconds = 0;
  @override
  int get searchTime => seconds;
  @override
  bool get isSearching => true;
  @override
  Future<void> leaveQueue(String userId) async {}

  void at(int s) {
    seconds = s;
    notifyListeners();
  }
}

class _FakeProgression extends ProgressionProvider {
  @override
  Future<void> refreshSummary() async {}
  @override
  Future<void> refreshQuests() async {}
  @override
  Future<void> refreshContent() async {}
}

const _ghostCosmetics = {
  'level': 41,
  'avatar': 'avatar.trophee',
  'frame': 'frame.obsidienne',
  'background': 'background.carbone',
  'title': 'title.machine-a-180',
  'badges': [],
};

/// A free player past 5 min: the locked card's ghost, no offer.
GhostOfferResponse _preview() => GhostOfferResponse.fromJson({
      'available': false,
      'reason': 'premium',
      'queueDelaySec': 300,
      'preview': {'username': 'Bruno_T19', 'rank': 'gold', 'elo': 1398, 'cosmetics': _ghostCosmetics},
    });

GhostOfferResponse _offer({DateTime? expiresAt}) => GhostOfferResponse.fromJson({
      'available': true,
      'queueDelaySec': 300,
      'offer': {
        'id': 'o-1',
        'expiresAt': (expiresAt ?? DateTime.now().add(const Duration(minutes: 15))).toUtc().toIso8601String(),
        'bestOf': 3,
        'eloEligible': true,
        'eloMatchesLeft': 5,
        'eloIfWin': 13,
        'eloIfLoss': -12,
        'ghost': {
          'ownerId': 'u-1',
          'username': 'Bruno_T19',
          'elo': 1398,
          'rank': 'gold',
          'cosmetics': _ghostCosmetics,
          'playedAt': '2026-11-02T19:00:00.000Z',
          'average': 55.2,
        },
      },
    });

/// Every text the card shows, in order.
List<String> _cardTexts(WidgetTester tester) => tester
    .widgetList<Text>(find.descendant(of: find.byType(GhostQueueOfferCard), matching: find.byType(Text)))
    .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
    .where((t) => t.isNotEmpty)
    .toList();

Finder _link() => find.byType(GhostQueueLink);
Finder _linkButton() => find.descendant(of: _link(), matching: find.byType(TextButton));

void main() {
  group('home', () {
    testWidgets('« Jouer autrement »: 3 tiles of 56 pt, Entraînement across the second row, no ghost', (tester) async {
      await tester.pumpWidget(_l10n(const Scaffold(
        body: Center(
          child: SizedBox(
            width: 358,
            child: HomeOtherModes(xp: XpRules(friendly: 30, training: 30, ghost: 40), friendLocked: true),
          ),
        ),
      )));
      await tester.pumpAndSettle();

      final tiles = find.byType(HomeModeTile);
      expect(tiles, findsNWidgets(3));
      expect(
        tester.widgetList<HomeModeTile>(tiles).map((t) => t.label),
        ['Contre un ami', 'Match local', 'Entraînement'],
      );
      expect(find.textContaining('antôme'), findsNothing);
      expect(find.byType(GhostIcon), findsNothing);

      final friend = tester.getRect(tiles.at(0));
      final local = tester.getRect(tiles.at(1));
      final training = tester.getRect(tiles.at(2));
      for (final r in [friend, local, training]) {
        expect(r.height, 56);
      }
      // Same size on the first row, side by side; training takes the width.
      expect(friend.width, local.width);
      expect(friend.top, local.top);
      expect(training.width, 358);
      expect(training.width, closeTo(friend.width * 2 + 10, 0.01));
      expect(training.top, friend.bottom + 10);
      // XP and the friend tile's premium crown are unchanged.
      expect(find.text('+30 XP'), findsNWidgets(2));
      expect(find.text('sans XP'), findsOneWidget);
      expect(find.byType(PremiumCrown), findsOneWidget);
    });

    testWidgets('the ghost rows: resume a running match and the owner digest, nothing otherwise', (tester) async {
      GhostHomeStore.instance.debugSeed();
      await tester.pumpWidget(_l10n(const Scaffold(body: GhostHomeRows())));
      await tester.pump();
      await tester.pump();
      expect(find.byType(InkWell), findsNothing);

      GhostHomeStore.instance.debugSeed(
        active: GhostMatchState.fromJson({
          'id': 'g-1',
          'playerLegsWon': 1,
          'ghostLegsWon': 0,
          'ghost': {'username': 'Bruno_T19', 'elo': 1398},
        }),
        digest: GhostDigest.fromJson({
          'count': 3,
          'ghostWins': 2,
          'xp': 40,
          'games': [
            {'id': 'a', 'opponentUsername': 'Kev', 'ghostWon': true},
          ],
        }),
      );
      await tester.pump();
      expect(find.text('Reprendre le match fantôme'), findsOneWidget);
      expect(find.text('contre Bruno_T19 · fantôme · 1 – 0'), findsOneWidget);
      expect(find.text('Ton fantôme a joué 3 fois'), findsOneWidget);
      GhostHomeStore.instance.reset();
    });
  });

  group('queue: the ghost after 5 min', () {
    late int asked;
    late List<GhostOfferResponse> answers;
    late _FakeSubscription subscription;

    setUp(() {
      asked = 0;
      answers = [_offer()];
      GhostService.debugOffer = () async {
        asked++;
        return answers.length > 1 ? answers.removeAt(0) : answers.first;
      };
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(
        'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
        (_) async => const StandardMessageCodec().encodeMessage([null]),
      );
    });

    tearDown(() {
      GhostService.debugOffer = null;
      GhostQueueOfferController.debugOpenPremium = null;
    });

    Future<_FakeMatchmaking> pumpQueue(WidgetTester tester, {required bool premium}) async {
      await tester.binding.setSurfaceSize(const Size(390, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final matchmaking = _FakeMatchmaking();
      subscription = _FakeSubscription(premium: premium);
      final progression = _FakeProgression()
        ..debugSeed(
          content: ProgressionContent.fromJson({
            'version': 'v',
            'xp': {'ghost': 40},
            'defs': {
              'ghost': [
                {'id': 'params', 'queueDelaySec': 300, 'matchXp': 40},
              ],
            },
          }),
        );
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: _FakeAuth()),
          ChangeNotifierProvider<SubscriptionProvider>.value(value: subscription),
          ChangeNotifierProvider<MatchmakingProvider>.value(value: matchmaking),
          ChangeNotifierProvider<ProgressionProvider>.value(value: progression),
        ],
        child: _l10n(const MatchmakingScreen()),
      ));
      // Localizations load asynchronously; the search ring never settles.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      return matchmaking;
    }

    Future<void> at(WidgetTester tester, _FakeMatchmaking m, int seconds) async {
      m.at(seconds);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }

    Future<void> leave(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    }

    testWidgets('nothing at 299 s; at 300 s card B: the ghost\'s card, one line, two buttons', (tester) async {
      final m = await pumpQueue(tester, premium: true);
      await at(tester, m, 299);
      expect(asked, 0);
      expect(find.byType(GhostQueueShowcase), findsNothing);

      await at(tester, m, 300);
      expect(asked, 1);
      expect(find.text('PERSONNE DEPUIS 5\u00a0MIN'), findsOneWidget);
      // The real S1 card of the ghost, faded, with « FANTÔME » top left.
      final showcase = find.byType(GhostQueueShowcase);
      expect(showcase, findsOneWidget);
      final card = find.descendant(of: showcase, matching: find.byType(PlayerShowcaseCard));
      expect(card, findsOneWidget);
      final s1 = tester.widget<PlayerShowcaseCard>(card);
      expect(s1.username, 'Bruno_T19');
      expect(s1.cosmetics?.level, 41);
      expect(s1.cosmetics?.background, 'background.carbone');
      expect(s1.onEdit, isNull);
      expect(s1.footer, isNull);
      expect(tester.widget<Opacity>(find.ancestor(of: card, matching: find.byType(Opacity)).first).opacity, 0.62);
      expect(find.descendant(of: showcase, matching: find.byType(ImageFiltered)), findsNothing);
      expect(find.byType(GhostQueueLock), findsNothing);
      final chip = find.descendant(of: showcase, matching: find.text('FANTÔME'));
      expect(chip, findsOneWidget);
      final cardRect = tester.getRect(showcase);
      expect(tester.getTopLeft(find.ancestor(of: chip, matching: find.byType(Container)).first) - cardRect.topLeft,
          const Offset(10, 10));
      expect(find.byType(GhostReplayIcon), findsOneWidget);
      expect(find.text('Ses vraies fléchettes, rejouées'), findsOneWidget);

      // « Jouer +40 XP » takes the room, « Attendre » stays narrow.
      final play = find.widgetWithText(ElevatedButton, 'Jouer');
      final wait = find.widgetWithText(OutlinedButton, 'Attendre');
      expect(play, findsOneWidget);
      expect(find.descendant(of: play, matching: find.text('+40 XP')), findsOneWidget);
      expect(wait, findsOneWidget);
      expect(tester.getSize(play).height, 52);
      expect(tester.getSize(wait).height, 52);
      // (The test font draws every glyph as a square: « Attendre » is wider
      // here than in Manrope.)
      expect(tester.getSize(play).width, greaterThan(tester.getSize(wait).width));
      expect(tester.getSize(play).width + 8 + tester.getSize(wait).width, closeTo(358, 0.01));
      expect(tester.getRect(play).top, tester.getRect(wait).top);
      expect(find.text('Premium'), findsNothing);

      // Nothing else: no paragraph, no tiles, no ELO, no date.
      final texts = _cardTexts(tester);
      final words = texts.expand((t) => t.split(RegExp(r'[\s\u00a0]+'))).where((w) => w.isNotEmpty).toList();
      expect(words.length, lessThanOrEqualTo(17), reason: texts.join(' | '));
      for (final gone in ['oui', 'quêtes', 'ligue', '÷ 3', 'ELO', 'match du', '55,2', 'Victoire', 'caméra']) {
        expect(texts.where((t) => t.contains(gone)), isEmpty, reason: gone);
      }
      // Asked once: the next seconds reuse the answer.
      await at(tester, m, 301);
      expect(asked, 1);
      await leave(tester);
    });

    testWidgets('« Attendre » folds the card into a link that stays for the whole search', (tester) async {
      final m = await pumpQueue(tester, premium: true);
      await at(tester, m, 300);
      await tester.tap(find.text('Attendre'));
      await tester.pump();
      expect(find.byType(GhostQueueShowcase), findsNothing);
      final link = find.widgetWithText(TextButton, 'Jouer contre un fantôme');
      expect(link, findsOneWidget);
      // No crown for a premium player.
      expect(find.descendant(of: _link(), matching: find.byType(PremiumCrown)), findsNothing);
      // At the bottom, just above « Annuler la recherche ».
      final cancel = tester.getRect(find.widgetWithText(OutlinedButton, 'Annuler la recherche'));
      expect(tester.getRect(link).bottom, lessThanOrEqualTo(cancel.top));
      expect(cancel.top - tester.getRect(link).bottom, lessThan(12));

      await at(tester, m, 900);
      expect(find.byType(GhostQueueShowcase), findsNothing);
      expect(link, findsOneWidget);
      expect(asked, 1);

      // Changing one's mind: the card again.
      await tester.tap(link);
      await tester.pump();
      expect(find.byType(GhostQueueShowcase), findsOneWidget);
      expect(link, findsNothing);
      await leave(tester);
    });

    testWidgets('an offer past its time is asked anew when the link unfolds it', (tester) async {
      answers = [_offer(expiresAt: DateTime.now().subtract(const Duration(minutes: 1))), _offer()];
      final m = await pumpQueue(tester, premium: true);
      await at(tester, m, 300);
      await tester.tap(find.text('Attendre'));
      await tester.pump();
      await tester.tap(_linkButton());
      await tester.pump();
      await tester.pump();
      expect(asked, 2);
      expect(find.byType(GhostQueueShowcase), findsOneWidget);
      await leave(tester);
    });

    testWidgets('a free player: nothing before 5 min, then the same card blurred behind a lock, and « Premium »', (tester) async {
      answers = [_preview()];
      final m = await pumpQueue(tester, premium: false);
      await at(tester, m, 299);
      expect(asked, 0);
      expect(find.byType(GhostQueueShowcase), findsNothing);

      await at(tester, m, 300);
      expect(asked, 1);
      expect(find.text('PERSONNE DEPUIS 5\u00a0MIN'), findsOneWidget);
      final showcase = find.byType(GhostQueueShowcase);
      expect(showcase, findsOneWidget);
      expect(tester.widget<GhostQueueShowcase>(showcase).locked, isTrue);
      // The ghost's real card, blurred and partly greyed at 50 %.
      final card = find.descendant(of: showcase, matching: find.byType(PlayerShowcaseCard));
      expect(tester.widget<PlayerShowcaseCard>(card).username, 'Bruno_T19');
      final blur = find.ancestor(of: card, matching: find.byType(ImageFiltered));
      expect(blur, findsOneWidget);
      expect(find.ancestor(of: card, matching: find.byType(ColorFiltered)), findsOneWidget);
      expect(tester.widget<Opacity>(find.ancestor(of: blur, matching: find.byType(Opacity)).first).opacity, 0.5);
      // The gold lock in the middle, the chip still readable.
      final lock = find.byType(GhostQueueLock);
      expect(lock, findsOneWidget);
      expect(tester.getCenter(lock).dx, closeTo(tester.getCenter(showcase).dx, 0.5));
      expect(tester.getCenter(lock).dy, closeTo(tester.getCenter(showcase).dy, 0.5));
      expect(find.descendant(of: showcase, matching: find.text('FANTÔME')), findsOneWidget);
      expect(find.text('Ses vraies fléchettes, rejouées'), findsOneWidget);

      // « Premium » (gold outline, crown) instead of « Jouer », and « Attendre ».
      final premium = find.widgetWithText(OutlinedButton, 'Premium');
      expect(premium, findsOneWidget);
      expect(find.descendant(of: premium, matching: find.byType(PremiumCrown)), findsOneWidget);
      expect(
        tester.widget<OutlinedButton>(premium).style?.side?.resolve(const <WidgetState>{}),
        const BorderSide(color: AppTheme.accent, width: 1.5),
      );
      expect(find.widgetWithText(OutlinedButton, 'Attendre'), findsOneWidget);
      expect(find.text('Jouer'), findsNothing);
      expect(find.text('+40 XP'), findsNothing);
      await at(tester, m, 600);
      expect(asked, 1);
      await leave(tester);
    });

    testWidgets('a free player: « Attendre » folds it into the link, with a small crown', (tester) async {
      answers = [_preview()];
      final m = await pumpQueue(tester, premium: false);
      await at(tester, m, 300);
      await tester.tap(find.text('Attendre'));
      await tester.pump();
      expect(find.byType(GhostQueueShowcase), findsNothing);
      expect(find.widgetWithText(TextButton, 'Jouer contre un fantôme'), findsOneWidget);
      expect(find.descendant(of: _link(), matching: find.byType(PremiumCrown)), findsOneWidget);
      expect(find.descendant(of: _link(), matching: find.byType(GhostIcon)), findsOneWidget);
      // The link opens the locked card again.
      await tester.tap(_linkButton());
      await tester.pump();
      expect(find.byType(GhostQueueLock), findsOneWidget);
      expect(asked, 1);
      await leave(tester);
    });

    testWidgets('« Premium » opens the subscription; back as premium, the offer is asked and the premium card shows', (tester) async {
      answers = [_preview(), _offer()];
      var opened = 0;
      GhostQueueOfferController.debugOpenPremium = (context) async {
        opened++;
        subscription.premiumAfterRefresh = true;
      };
      final m = await pumpQueue(tester, premium: false);
      await at(tester, m, 300);
      expect(find.byType(GhostQueueLock), findsOneWidget);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Premium'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(opened, 1);
      expect(subscription.refreshes, 1);
      expect(asked, 2);
      expect(find.byType(GhostQueueLock), findsNothing);
      expect(tester.widget<GhostQueueShowcase>(find.byType(GhostQueueShowcase)).locked, isFalse);
      expect(find.widgetWithText(ElevatedButton, 'Jouer'), findsOneWidget);
      expect(find.text('+40 XP'), findsOneWidget);
      expect(find.text('Premium'), findsNothing);
      // One offer: the next seconds ask nothing more.
      await at(tester, m, 310);
      expect(asked, 2);
      await leave(tester);
    });

    testWidgets('« Premium » closed without buying: the locked card stays, nothing asked again', (tester) async {
      answers = [_preview()];
      GhostQueueOfferController.debugOpenPremium = (context) async {};
      final m = await pumpQueue(tester, premium: false);
      await at(tester, m, 300);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Premium'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(subscription.refreshes, 1);
      expect(asked, 1);
      expect(find.byType(GhostQueueLock), findsOneWidget);
      await at(tester, m, 400);
      expect(asked, 1);
      await leave(tester);
    });

    testWidgets('no ghost in the band: nothing, and the search goes on without asking again (premium or free)', (tester) async {
      for (final premium in [true, false]) {
        answers = [GhostOfferResponse.fromJson({'available': false, 'reason': 'none', 'queueDelaySec': 300})];
        asked = 0;
        final m = await pumpQueue(tester, premium: premium);
        await at(tester, m, 300);
        await at(tester, m, 600);
        expect(asked, 1);
        expect(find.byType(GhostQueueShowcase), findsNothing);
        expect(_link(), findsOneWidget);
        expect(_linkButton(), findsNothing);
        expect(find.text('Annuler la recherche'), findsOneWidget);
        await leave(tester);
      }
    });

    testWidgets('the server\'s « not yet » (queue joined a bit late) is asked again when it says', (tester) async {
      answers = [
        GhostOfferResponse.fromJson({'available': false, 'reason': 'queue_wait', 'retryInSec': 3, 'queueDelaySec': 300}),
        _offer(),
      ];
      final m = await pumpQueue(tester, premium: true);
      await at(tester, m, 300);
      expect(asked, 1);
      expect(find.byType(GhostQueueShowcase), findsNothing);
      await at(tester, m, 302);
      expect(asked, 1);
      await at(tester, m, 303);
      expect(asked, 2);
      expect(find.byType(GhostQueueShowcase), findsOneWidget);
      await leave(tester);
    });

    testWidgets('« S\'entraîner en attendant »: the short line, without « vous »', (tester) async {
      await pumpQueue(tester, premium: true);
      expect(find.text("Tu passes au match dès qu'un adversaire arrive."), findsOneWidget);
      expect(find.textContaining('vous'), findsNothing);
      await leave(tester);
    });
  });

  test('the XP of the button comes from the served content', () {
    expect(ghostMatchXpOf(null), isNull);
    expect(ghostMatchXpOf(ProgressionContent.fromJson({'version': 'v', 'xp': {'ghost': 40}})), 40);
    expect(
      ghostMatchXpOf(ProgressionContent.fromJson({
        'version': 'v',
        'defs': {
          'ghost': [
            {'id': 'params', 'matchXp': 45},
          ],
        },
      })),
      45,
    );
  });

  test('the queue delay comes from the served content, 5 min without it', () {
    expect(kGhostQueueDelay, 300);
    expect(ghostQueueDelayOf(null), 300);
    expect(ghostQueueDelayOf(ProgressionContent.fromJson({'version': 'v'})), 300);
    expect(
      ghostQueueDelayOf(ProgressionContent.fromJson({
        'version': 'v',
        'defs': {
          'ghost': [
            {'id': 'params', 'queueDelaySec': 120},
          ],
        },
      })),
      120,
    );
  });
}
