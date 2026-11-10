import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../l10n/app_localizations.dart';
import '../providers/matchmaking_provider.dart';
import '../screens/game/game_screen.dart';
import '../providers/auth_provider.dart';
import '../screens/progression/match_found_screen.dart';
import '../utils/rank_utils.dart';

/// Owns match-found navigation globally, independent of the current screen.
///
/// Why: a player can now run trainings while queued, so the "Match Found!" prompt
/// and the jump into [GameScreen] must work whether they're on [MatchmakingScreen],
/// a training screen, or anywhere else. The queue lives in the global
/// [MatchmakingProvider] and navigation uses the app's root [navigatorKey], both of
/// which outlive any single screen — so this gate, wrapped around the whole app via
/// MaterialApp.builder, is the single place that reacts to a match being found.
class MatchmakingNavigationGate extends StatefulWidget {
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  const MatchmakingNavigationGate({
    super.key,
    required this.navigatorKey,
    required this.child,
  });

  @override
  State<MatchmakingNavigationGate> createState() =>
      _MatchmakingNavigationGateState();

  /// Ghost match (Agent 5, CONTRACT.md §14.5). A ghost is "found" by the
  /// player's own tap rather than a socket event, but it goes through the
  /// same 6 s "Match found" screen ([matchFound], built with isGhost: true,
  /// left after its own `seconds`) and the same jump into the match as a
  /// ranked game: [destination]
  /// replaces every screen above the home screen. Returns false — and
  /// navigates nowhere — when no gate is mounted or a real match is already
  /// being opened: the real opponent always wins that race.
  static Future<bool> openGhostMatch({
    required MatchFoundScreen matchFound,
    required WidgetBuilder destination,
  }) async {
    final gate = _MatchmakingNavigationGateState._current;
    if (gate == null || !gate.mounted || gate._navigating) return false;
    return gate._openGhostMatch(matchFound, destination);
  }

  /// Test seam: what the ranked path opens instead of [GameScreen].
  @visibleForTesting
  static Widget Function(String matchId, String opponentId)? debugGameScreen;
}

class _MatchmakingNavigationGateState extends State<MatchmakingNavigationGate> {
  MatchmakingProvider? _matchmaking;
  bool _navigating = false;
  // Tracks whether the "Match Found!" dialog is currently on screen, so we can
  // force-dismiss it if the match is aborted (e.g. the player cancelled their
  // search and the server voided the ghost match) — otherwise the
  // barrierDismissible:false dialog would stay stuck forever.
  bool _dialogOpen = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final provider = context.read<MatchmakingProvider>();
    if (!identical(provider, _matchmaking)) {
      _matchmaking?.removeListener(_onMatchmakingUpdate);
      _matchmaking = provider;
      _matchmaking!.addListener(_onMatchmakingUpdate);
    }
  }

  void _onMatchmakingUpdate() {
    final matchmaking = _matchmaking;
    if (matchmaking == null) return;

    if (matchmaking.matchFound) {
      if (_navigating) return;
      _navigating = true;
      _showMatchFoundDialog(matchmaking);
      _navigateToGame(matchmaking);
    } else {
      // New search started, queue left, or the match was aborted — allow the
      // next match to navigate and tear down any stuck "Match Found!" dialog.
      _navigating = false;
      _dismissDialogIfOpen();
    }
  }

  NavigatorState? get _navigator => widget.navigatorKey.currentState;
  BuildContext? get _navContext => widget.navigatorKey.currentContext;

  /// Force-close the match-found dialog if it's showing. Safe to call when it
  /// isn't (guarded by [_dialogOpen]).
  void _dismissDialogIfOpen() {
    if (!_dialogOpen) return;
    _dialogOpen = false;
    final nav = _navigator;
    if (nav != null && nav.canPop()) nav.pop();
  }

  /// The 6-second "Match found" screen (piste B « Duel », CONTRACT §14.13:
  /// both S1 cards, ranks, ELO, what the series is worth, the 3-2-1 ring).
  /// A full-screen route rather than a dialog, but popped the same way by
  /// [_dismissDialogIfOpen] and removed by the pushAndRemoveUntil into
  /// GameScreen. The camera and the video call are not started during it.
  void _showMatchFoundDialog(MatchmakingProvider matchmaking) {
    final ctx = _navContext;
    final nav = _navigator;
    if (ctx == null || nav == null) return;
    final l10n = AppLocalizations.of(ctx);
    final me = ctx.read<AuthProvider>().currentUser;

    _dialogOpen = true;
    nav
        .push(
      MatchFoundScreen.route(
        MatchFoundScreen(
          subtitle: l10n.matchFoundRanked,
          seconds: _matchFoundSeconds,
          // Head-to-head line, fetched while the screen is up.
          opponentId: matchmaking.opponentId,
          me: MatchFoundPlayer(
            username: me?.username ?? '',
            rank: me?.rank ?? 'unranked',
            elo: matchmaking.playerElo ?? me?.elo,
            cosmetics: matchmaking.playerCosmetics ?? me?.cosmetics,
            isPremium: me?.isPremiumActive ?? false,
          ),
          opponent: MatchFoundPlayer(
            username: matchmaking.opponentUsername ?? l10n.unknownPlayer,
            rank: matchmaking.opponentElo == null ? 'unranked' : rankFromElo(matchmaking.opponentElo!),
            elo: matchmaking.opponentElo,
            cosmetics: matchmaking.opponentCosmetics,
            isPremium: matchmaking.opponentPremium,
          ),
          eloIfWin: matchmaking.eloIfWin,
          eloIfLoss: matchmaking.eloIfLoss,
        ),
      ),
    )
        .then((_) {
      // Cleared however the screen closes (our dismiss, or removal by the
      // pushAndRemoveUntil into GameScreen).
      _dialogOpen = false;
    });
  }

  /// Jumps into the match after a beat, so the "Match Found!" dialog is on
  /// screen long enough to be read. Navigating with `(route) => route.isFirst`
  /// removes every screen on top of HomeScreen — the MatchmakingScreen and any
  /// training/placement screen the player was on — so their `dispose()` runs
  /// and the camera is released for the match.
  ///
  /// Nothing is waited FOR: the match_found payload that got us here already
  /// carries everything the game screen needs, video block included.
  void _navigateToGame(MatchmakingProvider matchmaking) {
    void go() {
      final navigator = _navigator;
      if (navigator == null || matchmaking.matchId == null ||
          matchmaking.opponentId == null) {
        // The match was aborted (cancelled search / voided ghost match) before
        // we could navigate. Don't leave the dialog stuck and let a future
        // match navigate again.
        _navigating = false;
        _dismissDialogIfOpen();
        return;
      }
      final matchId = matchmaking.matchId!;
      final opponentId = matchmaking.opponentId!;
      navigator.pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) =>
              MatchmakingNavigationGate.debugGameScreen?.call(matchId, opponentId) ??
              GameScreen(
                matchId: matchId,
                opponentId: opponentId,
                opponentUsername: matchmaking.opponentUsername ?? 'Opponent',
              ),
        ),
        (route) => route.isFirst,
      );
      // Early re-assert: the disposing screens (training/matchmaking) call
      // WakelockPlus.disable() in their dispose(). NOTE this post-frame enable()
      // is NOT sufficient on its own — Flutter defers disposing the screen
      // beneath the still-animating GameScreen until the push transition
      // completes (~300ms later), so that disable() lands after this re-assert.
      // The authoritative re-assert lives in BaseGameScreenState, which keeps
      // re-firing enable() on a short periodic timer. This is just early cover.
      WidgetsBinding.instance.addPostFrameCallback((_) => WakelockPlus.enable());
    }

    Future.delayed(const Duration(seconds: _matchFoundSeconds), () {
      if (mounted) go();
    });
  }

  /// How long the "Match found" screen stays up (validated 9 nov. 2026:
  /// 6 s, the déroulé of MtDeroule; was 2 s, and a 500 ms dialog before
  /// that). The server starts nothing at match_found that 4 more seconds
  /// could cost a player (CONTRACT §14.13).
  static const int _matchFoundSeconds = MatchFoundScreen.defaultSeconds;

  /// The mounted gate, for [MatchmakingNavigationGate.openGhostMatch].
  static _MatchmakingNavigationGateState? _current;

  @override
  void initState() {
    super.initState();
    _current = this;
  }

  /// Ghost match: same screen, same timing, same navigation as a ranked
  /// match found by the queue. Holds [_navigating] for the duration so a
  /// late queue event cannot open a second match on top of it.
  Future<bool> _openGhostMatch(
    MatchFoundScreen matchFound,
    WidgetBuilder destination,
  ) async {
    final nav = _navigator;
    if (nav == null) return false;
    _navigating = true;
    try {
      unawaited(nav.push(MatchFoundScreen.route(matchFound)));
      // The screen's own length (MatchFoundScreen.defaultSeconds unless told
      // otherwise), so its 3-2-1 and the navigation always agree.
      await Future.delayed(Duration(seconds: matchFound.seconds));
      if (!mounted) return false;
      final navigator = _navigator;
      if (navigator == null) return false;
      unawaited(navigator.pushAndRemoveUntil(
        MaterialPageRoute(builder: destination),
        (route) => route.isFirst,
      ));
      WidgetsBinding.instance.addPostFrameCallback((_) => WakelockPlus.enable());
      return true;
    } finally {
      _navigating = false;
    }
  }

  @override
  void dispose() {
    if (identical(_current, this)) _current = null;
    _matchmaking?.removeListener(_onMatchmakingUpdate);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
