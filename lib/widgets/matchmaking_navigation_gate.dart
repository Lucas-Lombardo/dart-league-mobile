import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../l10n/app_localizations.dart';
import '../providers/matchmaking_provider.dart';
import '../screens/game/game_screen.dart';
import '../utils/app_theme.dart';

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
}

class _MatchmakingNavigationGateState extends State<MatchmakingNavigationGate> {
  MatchmakingProvider? _matchmaking;
  bool _navigating = false;

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
      _waitForAgoraCredentialsAndNavigate(matchmaking);
    } else {
      // New search started (or queue left) — allow the next match to navigate.
      _navigating = false;
    }
  }

  NavigatorState? get _navigator => widget.navigatorKey.currentState;
  BuildContext? get _navContext => widget.navigatorKey.currentContext;

  void _showMatchFoundDialog(MatchmakingProvider matchmaking) {
    final ctx = _navContext;
    if (ctx == null) return;

    showDialog(
      context: ctx,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppTheme.primary, width: 2),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle, color: AppTheme.primary, size: 80),
              const SizedBox(height: 16),
              Text(
                AppLocalizations.of(context).matchFoundExclamation,
                style: TextStyle(
                  color: AppTheme.primary,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 24),
              if (matchmaking.opponentId != null)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.background,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppTheme.surfaceLight.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        AppLocalizations.of(context).opponent,
                        style: AppTheme.labelLarge
                            .copyWith(color: AppTheme.textSecondary),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        matchmaking.opponentUsername ??
                            AppLocalizations.of(context).unknownPlayer,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        AppLocalizations.of(context).eloValue.replaceAll(
                            '{value}', '${matchmaking.opponentElo ?? '???'}'),
                        style: const TextStyle(
                          color: AppTheme.primary,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 24),
              Text(
                AppLocalizations.of(context).startingGame,
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 14,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Polls up to ~5s for Agora credentials, then jumps into the match. Navigating
  /// with `(route) => route.isFirst` removes every screen on top of HomeScreen —
  /// the MatchmakingScreen and any training/placement screen the player was on —
  /// so their `dispose()` runs and the camera is released for the match.
  void _waitForAgoraCredentialsAndNavigate(MatchmakingProvider matchmaking) {
    int attempts = 0;
    const maxAttempts = 50; // 5 seconds at 100ms

    void go() {
      final navigator = _navigator;
      if (navigator == null || matchmaking.matchId == null ||
          matchmaking.opponentId == null) {
        return;
      }
      navigator.pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => GameScreen(
            matchId: matchmaking.matchId!,
            opponentId: matchmaking.opponentId!,
            opponentUsername: matchmaking.opponentUsername ?? 'Opponent',
            agoraAppId: matchmaking.agoraAppId,
            agoraToken: matchmaking.agoraToken,
            agoraTokenStrict: matchmaking.agoraTokenStrict,
            agoraChannelName: matchmaking.agoraChannelName,
            agoraUid: matchmaking.agoraUid,
            opponentAgoraUid: matchmaking.opponentAgoraUid,
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

    void check() {
      if (!mounted) return;
      attempts++;
      final ready = matchmaking.agoraAppId != null &&
          matchmaking.agoraToken != null &&
          matchmaking.agoraChannelName != null;
      if (ready || attempts >= maxAttempts) {
        go();
        return;
      }
      Future.delayed(const Duration(milliseconds: 100), check);
    }

    Future.delayed(const Duration(milliseconds: 500), check);
  }

  @override
  void dispose() {
    _matchmaking?.removeListener(_onMatchmakingUpdate);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
