import 'dart:async' show unawaited;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/subscription_provider.dart';
import '../widgets/rank_badge.dart';
import '../widgets/premium_badge.dart';
import '../widgets/update_banner.dart';
import '../l10n/app_localizations.dart';
import '../utils/app_navigator.dart';
import '../utils/haptic_service.dart';
import '../utils/app_theme.dart';
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
      tp.startRealtime(myUserId: context.read<AuthProvider>().currentUser?.id);

      // Referral: the "I have a code" entry points on the Premium screen and
      // the daily-limit card need eligibility resolved before they can decide
      // whether to render at all.
      context.read<ReferralProvider>().refreshEligibility();

      // Match proof: attach the capture_match listener for the app's
      // lifetime, and sweep for result disputes that were filed while this
      // device was offline (their footage is still retained locally).
      unawaited(MatchProofService.checkPending());

      // Seasons: the home ring pill + line and the Rankings tab read the
      // provider; no socket event, so it refreshes here and on didPopNext.
      // It also carries the "open the Rankings tab on season N" intent.
      final seasons = context.read<SeasonProvider>();
      _seasonProvider = seasons;
      seasons.addListener(_onSeasonStandingsRequest);
      seasons.refresh();
      // Once-only end-of-season screens: on launch, and when the
      // "season_ended" push is opened.
      _maybeShowSeasonRecap();
      PushNotificationService.addOpenedListener(_onSeasonPushOpened);

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
    // Tear down on logout (HomeScreen is removed from the tree).
    _tournamentProvider?.stopRealtime();
    _seasonProvider?.removeListener(_onSeasonStandingsRequest);
    PushNotificationService.removeOpenedListener(_onSeasonPushOpened);
    _refreshNotifier.dispose();
    super.dispose();
  }

  void _onSeasonPushOpened(Map<String, dynamic> data) {
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

  /// "Final standings ›" on the home ring / a poster's "Standings ›": switch
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
    final authProvider = context.watch<AuthProvider>();
    final user = authProvider.currentUser;
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Container(
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                height: 38,
                child: Image.asset(
                  'assets/logo/logo-without-letters.png',
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                l10n.dartRivals,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                  fontSize: 20,
                ),
              ),
            ],
          ),
        ),
        actions: [
          Consumer<ChatProvider>(
            builder: (context, chat, _) => IconButton(
              icon: Stack(
                clipBehavior: Clip.none,
                children: [
                  const Icon(Icons.chat_bubble_outline),
                  if (chat.unreadTotal > 0)
                    Positioned(
                      top: -4,
                      right: -6,
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 15),
                        height: 15,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.error,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          chat.unreadTotal > 99 ? '99+' : '${chat.unreadTotal}',
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              onPressed: () {
                HapticService.lightImpact();
                AppNavigator.toScreen(context, const ReceivedMessagesScreen());
              },
              tooltip: l10n.receivedMessagesTitle,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () {
              HapticService.lightImpact();
              AppNavigator.toScreen(context, const SettingsScreen());
            },
            tooltip: l10n.settingsTooltip,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          if (user != null)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppTheme.surfaceLight.withValues(alpha: 0.5),
                ),
              ),
              child: Row(
                children: [
                  RankBadge(
                    rank: user.rank,
                    size: 28,
                    showLabel: false,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            user.username,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: Colors.white,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                        Selector<SubscriptionProvider, bool>(
                          selector: (_, sub) => sub.isPremiumActive,
                          builder: (_, isPremium, __) =>
                              PremiumBadge(isPremium: isPremium, size: 16),
                        ),
                      ],
                    ),
                  ),
                  // "#14 |" before the ELO — only while the active season is
                  // the one displayed on the ring (a past season keeps the
                  // live ELO here without a position).
                  Consumer<SeasonProvider>(
                    builder: (context, seasons, _) {
                      final me = seasons.current?.me;
                      if (me == null || !seasons.isActiveSelected) {
                        return const SizedBox.shrink();
                      }
                      return Row(
                        children: [
                          Text(
                            '#${me.position}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                          Container(
                            width: 1,
                            height: 14,
                            margin: const EdgeInsets.symmetric(horizontal: 10),
                            color: AppTheme.surfaceLight.withValues(alpha: 0.9),
                          ),
                        ],
                      );
                    },
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        '${user.elo}',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primary,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        l10n.eloLabel,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          // "Update available" banner — self-gating (renders nothing unless an
          // update is available and not dismissed).
          const UpdateBanner(),
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                color: AppTheme.background,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
                child: _screens[_currentIndex],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppTheme.surface,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 20,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Container(
              decoration: BoxDecoration(
                color: AppTheme.surfaceLight.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  Expanded(child: _buildNavItem(0, '📊', l10n.stats)),
                  Expanded(child: _buildNavItem(1, '🏆', l10n.tournament)),
                  Expanded(child: _buildNavItem(2, '', l10n.play)),
                  Expanded(child: _buildNavItem(3, '👥', l10n.friends)),
                  Expanded(child: _buildNavItem(4, '📈', l10n.rankings)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, String emoji, String label) {
    final isSelected = _currentIndex == index;
    final isPlayTab = index == 2; // Play is middle tab
    // The Play tab keeps its circle permanently (B2): it reads as the central
    // action button of the bar; selection only brightens the glow.
    final showCircle = isPlayTab;
    final isFriendsTab = index == 3;
    final isTournamentTab = index == 1;
    
    return GestureDetector(
      onTap: () {
        HapticService.lightImpact();
        setState(() {
          _currentIndex = index;
        });
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: showCircle
                      ? BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: isSelected ? 0.2 : 0.1),
                          shape: BoxShape.circle,
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: AppTheme.primary.withValues(alpha: 0.3),
                                    blurRadius: 12,
                                    spreadRadius: 2,
                                  ),
                                ]
                              : null,
                        )
                      : null,
                  child: Center(
                    // The Play tab carries the brand (shield logo); the other
                    // tabs use rich color emoji like the validated mockup —
                    // selection reads through the label color and full opacity.
                    child: isPlayTab
                        ? Image.asset(
                            'assets/logo/logo-without-letters.png',
                            width: 36,
                            height: 36,
                            fit: BoxFit.contain,
                          )
                        : Opacity(
                            opacity: isSelected ? 1.0 : 0.72,
                            child: Text(
                              emoji,
                              style: const TextStyle(fontSize: 21),
                            ),
                          ),
                  ),
                ),
                if (isTournamentTab)
                  Consumer<TournamentProvider>(
                    builder: (context, tournamentProvider, _) {
                      // A pending match invite is the urgent signal — it keeps
                      // the plain dot. Otherwise the bubble counts tournaments
                      // open for registration.
                      final openCount = tournamentProvider.openRegistrationCount;
                      if (!tournamentProvider.hasPendingInvite && openCount == 0) {
                        return const SizedBox.shrink();
                      }
                      return Positioned(
                        right: -2,
                        top: -2,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: AppTheme.error,
                            shape: BoxShape.circle,
                            border: Border.all(color: AppTheme.background, width: 2),
                          ),
                          constraints: BoxConstraints(
                            minWidth: tournamentProvider.hasPendingInvite ? 14 : 20,
                            minHeight: tournamentProvider.hasPendingInvite ? 14 : 20,
                          ),
                          child: tournamentProvider.hasPendingInvite
                              ? null
                              : Center(
                                  child: Text(
                                    openCount > 9 ? '9+' : openCount.toString(),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                        ),
                      );
                    },
                  ),
                if (isFriendsTab)
                  Consumer<FriendsProvider>(
                    builder: (context, friendsProvider, _) {
                      final count = friendsProvider.pendingRequestsCount;
                      if (count == 0) return const SizedBox.shrink();

                      return Positioned(
                        right: -2,
                        top: -2,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: AppTheme.error,
                            shape: BoxShape.circle,
                            border: Border.all(color: AppTheme.background, width: 2),
                          ),
                          constraints: const BoxConstraints(
                            minWidth: 20,
                            minHeight: 20,
                          ),
                          child: Center(
                            child: Text(
                              count > 9 ? '9+' : count.toString(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isSelected ? AppTheme.primary : AppTheme.textSecondary,
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
