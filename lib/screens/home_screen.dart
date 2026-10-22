import 'dart:async' show unawaited;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../widgets/design_system.dart';
import '../widgets/update_banner.dart';
import '../l10n/app_localizations.dart';
import '../utils/app_navigator.dart';
import '../providers/chat_provider.dart';
import '../providers/referral_provider.dart';
import '../providers/friends_provider.dart';
import '../providers/tournament_provider.dart';
import '../providers/season_provider.dart';
import '../services/match_proof_service.dart';
import '../services/meta_events_service.dart';
import '../services/push_notification_service.dart';
import 'season/season_recap_screen.dart';
import '../main.dart' show routeObserver;
import 'chat/received_messages_screen.dart';
import 'chat/chat_thread_screen.dart';
import 'home/play_screen.dart';
import 'home/stats_screen.dart';
import 'home/leaderboard_screen.dart';
import 'home/friends_screen.dart';
import 'home/tournament_screen.dart';
import 'settings/settings_screen.dart';


class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with RouteAware {
  int _currentIndex = 2; // Start at Play (now index 2)
  final _refreshNotifier = ValueNotifier<int>(0);
  TournamentProvider? _tournamentProvider;
  SeasonProvider? _seasonProvider;
  /// The once-only recap is on screen (or being fetched) — never stack two.
  bool _recapBusy = false;

  final List<Widget> _fixedScreens = const [
    StatsScreen(),
    TournamentScreen(),
    FriendsScreen(),
    LeaderboardScreen(),
  ];

  @override
  void initState() {
    super.initState();
    // Start tournament real-time once we're in the authenticated shell. This
    // wires the socket listeners (previously never called) + the polling
    // fallback so users actually learn when their match is ready.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final tp = context.read<TournamentProvider>();
      _tournamentProvider = tp;
      tp.startRealtime(
        myUserId: context.read<AuthProvider>().currentUser?.id,
        owner: this,
      );

      // Referral: the "I have a code" entry points on the Premium screen and
      // the daily-limit card need eligibility resolved before they can decide
      // whether to render at all.
      context.read<ReferralProvider>().refreshEligibility();

      // Match proof: attach the capture_match listener for the app's
      // lifetime, and sweep for result disputes that were filed while this
      // device was offline (their footage is still retained locally).
      unawaited(MatchProofService.checkPending());

      // Seasons: the home player card and the Rankings tab read the
      // provider; no socket event, so it refreshes here and on didPopNext.
      // It also carries the "open the Rankings tab on season N" intent.
      final seasons = context.read<SeasonProvider>();
      _seasonProvider = seasons;
      seasons.addListener(_onSeasonStandingsRequest);
      seasons.refresh();
      // Once-only end-of-season screens: on launch, and when the
      // "season_ended" push is opened. Also routes "friend_online" taps.
      _maybeShowSeasonRecap();
      PushNotificationService.addOpenedListener(_onPushOpened);

      // Chat: unread badge + realtime routing, and "new message" push taps
      // deep-link straight into the thread.
      final chat = context.read<ChatProvider>();
      chat.init();
      chat.onOpenThreadFromPush = (counterpartId, username) {
        if (!mounted) return;
        AppNavigator.toScreen(
          context,
          ChatThreadScreen(
            counterpartId: counterpartId,
            username: username ?? AppLocalizations.of(context).teamDartRivals,
          ),
        );
      };

      // iOS tracking prompt, once per install. Asked here rather than at
      // launch: on a cold first frame the system alert lands before the user
      // knows what the app is and gets dismissed by reflex, and a refusal is
      // final — Apple never asks twice. Refusing it costs Meta ad attribution
      // on iOS, so it's worth the good moment.
      unawaited(MetaEventsService.requestTrackingConsent());
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context)!);
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    // Tear down on logout (HomeScreen is removed from the tree). Owned: a
    // home screen replaced by a newer one (return from a match) must not
    // stop the realtime the newer one runs.
    _tournamentProvider?.stopRealtime(owner: this);
    _seasonProvider?.removeListener(_onSeasonStandingsRequest);
    PushNotificationService.removeOpenedListener(_onPushOpened);
    _refreshNotifier.dispose();
    super.dispose();
  }

  void _onPushOpened(Map<String, dynamic> data) {
    // "Your friend is online" → the Friends tab, where the green dot and the
    // Défier button are.
    if (data['type'] == 'friend_online') {
      if (mounted && _currentIndex != 3) setState(() => _currentIndex = 3);
      return;
    }
    if (data['type'] != 'season_ended') return;
    _seasonProvider?.refresh();
    _maybeShowSeasonRecap();
  }

  /// GET /seasons/recap → push the recap (fade) when there is one the user
  /// has not acknowledged. The new-ELO screen marks it seen and pops back
  /// here; didPopNext then refreshes the profile and the season.
  Future<void> _maybeShowSeasonRecap() async {
    if (_recapBusy) return;
    final seasons = _seasonProvider;
    if (seasons == null) return;
    _recapBusy = true;
    try {
      final recap = await seasons.fetchRecap();
      if (!mounted || recap == null) return;
      await Navigator.of(context).push(SeasonRecapScreen.route(recap));
    } finally {
      _recapBusy = false;
    }
  }

  /// "Final standings ›" on the home card / a poster's "Standings ›": switch
  /// to the Rankings tab, which consumes the requested season on mount.
  void _onSeasonStandingsRequest() {
    if (!mounted || _seasonProvider?.standingsRequest == null) return;
    if (_currentIndex != 4) setState(() => _currentIndex = 4);
  }

  @override
  void didPopNext() {
    // A route was popped and HomeScreen is now visible again — refresh after frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _refreshNotifier.value++;
      context.read<AuthProvider>().checkAuthStatus();
      context.read<SeasonProvider>().refresh();
    });
  }

  List<Widget> get _screens => [
    _fixedScreens[0],
    _fixedScreens[1],
    PlayScreen(refreshNotifier: _refreshNotifier),
    _fixedScreens[2],
    _fixedScreens[3],
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Shell header: the brand on the Play tab only. Every other tab
            // draws its own DsScreenHeader (title + contextual actions).
            if (_currentIndex == 2)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: DsBrandHeader(
                  actions: [
                    Consumer<ChatProvider>(
                      builder: (context, chat, _) => DsIconButton(
                        icon: Icons.chat_bubble_outline_rounded,
                        tooltip: l10n.receivedMessagesTitle,
                        badge: chat.unreadTotal > 0
                            ? DsBadge(count: chat.unreadTotal)
                            : null,
                        onTap: () => AppNavigator.toScreen(
                            context, const ReceivedMessagesScreen()),
                      ),
                    ),
                    DsIconButton(
                      icon: Icons.settings_outlined,
                      tooltip: l10n.settingsTooltip,
                      onTap: () => AppNavigator.toScreen(
                          context, const SettingsScreen()),
                    ),
                  ],
                ),
              ),
            // "Update available" banner — self-gating (renders nothing unless an
            // update is available and not dismissed).
            const UpdateBanner(),
            Expanded(child: _screens[_currentIndex]),
          ],
        ),
      ),
      bottomNavigationBar: DsBottomBar(
        currentIndex: _currentIndex,
        onSelect: (index) => setState(() => _currentIndex = index),
        centerLabel: l10n.play,
        items: [
          DsBottomBarItem(icon: Icons.bar_chart_rounded, label: l10n.stats),
          DsBottomBarItem(
            icon: Icons.emoji_events_outlined,
            label: l10n.tournament,
            badge: Consumer<TournamentProvider>(
              builder: (context, tournamentProvider, _) {
                // A pending match invite is the urgent signal — it keeps the
                // plain dot. Otherwise the bubble counts tournaments open for
                // registration.
                final openCount = tournamentProvider.openRegistrationCount;
                if (tournamentProvider.hasPendingInvite) return const DsDot();
                if (openCount == 0) return const SizedBox.shrink();
                return DsBadge(count: openCount);
              },
            ),
          ),
          DsBottomBarItem(
            icon: Icons.people_outline_rounded,
            label: l10n.friends,
            badge: Consumer<FriendsProvider>(
              builder: (context, friendsProvider, _) {
                final count = friendsProvider.pendingRequestsCount;
                if (count == 0) return const SizedBox.shrink();
                return DsBadge(count: count);
              },
            ),
          ),
          DsBottomBarItem(icon: Icons.trending_up_rounded, label: l10n.rankings),
        ],
      ),
    );
  }
}
