import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/game_provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/match_service.dart';
import '../../utils/haptic_service.dart';
import '../../utils/app_theme.dart';
import '../../services/auto_scoring_service.dart';
import '../../widgets/game_turn_ui.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/app_navigator.dart';
import '../../widgets/rank_change_overlay.dart';
import '../../widgets/elo_change_overlay.dart';
import 'base_game_screen_state.dart';
import 'match_end_view.dart';

class GameScreen extends StatefulWidget {
  final String matchId;
  final String opponentId;
  final String opponentUsername;
  final String? agoraAppId;
  final String? agoraToken;
  final String? agoraTokenStrict;
  final String? agoraChannelName;
  final int? agoraUid;
  final int? opponentAgoraUid;

  const GameScreen({
    super.key,
    required this.matchId,
    required this.opponentId,
    required this.opponentUsername,
    this.agoraAppId,
    this.agoraToken,
    this.agoraTokenStrict,
    this.agoraChannelName,
    this.agoraUid,
    this.opponentAgoraUid,
  });

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends BaseGameScreenState<GameScreen> {
  String? _storedMatchId;

  @override
  dynamic readGame() => context.read<GameProvider>();

  @override
  String get opponentUsername => widget.opponentUsername;

  @override
  String? get matchIdForLeave => _storedMatchId;

  @override
  @override
  String get leaveWarningText =>
      AppLocalizations.of(context).forfeitMatchWarning;

  // The screen was opened with the match's Agora channel; the provider only
  // learns it from later payloads.
  @override
  String? get fallbackAgoraChannelId => widget.agoraChannelName;

  @override
  Widget buildAppBarTitle() => Row(children: [
    Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppTheme.error, shape: BoxShape.circle)),
    const SizedBox(width: 8),
    Text(AppLocalizations.of(context).liveMatch, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 2, color: Colors.white)),
  ]);

  // The series this screen instance was opened for. _storedMatchId may only
  // follow the provider across legs of THIS series — see below.
  String? _screenSeriesId;

  @override
  void onScreenSpecificStateChange(dynamic game) {
    // In a BO3 series the live matchId moves to each new leg; the safety-net
    // forfeit on leave must target the CURRENT leg, not leg 1. But mirror
    // ONLY across legs of this screen's own series: unconditionally following
    // the provider defeated the stale-screen guard in leaveMatch() — a
    // deferred-disposed old screen adopted the SUCCESSOR match's id and
    // forfeited it (every friendly rematch died instantly at 501-501).
    final g = game as GameProvider;
    if (_screenSeriesId == null &&
        g.seriesId != null &&
        g.matchId == _storedMatchId) {
      _screenSeriesId = g.seriesId;
    }
    if (g.matchId != null &&
        _screenSeriesId != null &&
        g.seriesId == _screenSeriesId) {
      _storedMatchId = g.matchId;
    }
  }

  @override
  Future<void> initScreenSpecific() async {
    final game = context.read<GameProvider>();
    final auth = context.read<AuthProvider>();
    if (auth.currentUser == null) return;
    _storedMatchId = widget.matchId;
    storedPlayerId = auth.currentUser!.id;
    updateLoadingMessage('Joining match...');
    game.initGame(
      widget.matchId,
      auth.currentUser!.id,
      widget.opponentId,
      agoraAppId: widget.agoraAppId,
      agoraToken: widget.agoraToken,
      agoraTokenStrict: widget.agoraTokenStrict,
      agoraChannelName: widget.agoraChannelName,
      agoraUid: widget.agoraUid,
      opponentAgoraUid: widget.opponentAgoraUid,
    );
    gameStarted = game.gameStarted;
    gameEnded = game.gameEnded;
    if (widget.agoraAppId != null && widget.agoraAppId!.isNotEmpty) {
      updateLoadingMessage('Starting camera...');
      // Prefer the strict token (bound to a deterministic UID) when the
      // backend provides it. Fall back to the legacy token + uid=0 so we
      // remain compatible with backends that haven't been updated yet.
      final useStrict = widget.agoraTokenStrict != null &&
          widget.agoraTokenStrict!.isNotEmpty &&
          widget.agoraUid != null &&
          widget.agoraUid != 0;
      await initializeAgora(
        appId: widget.agoraAppId!,
        token: useStrict
            ? widget.agoraTokenStrict!
            : (widget.agoraToken ?? ''),
        channelName: widget.agoraChannelName ?? '',
        uid: useStrict ? widget.agoraUid : 0,
      );
    }
    game.addListener(handleSharedStateChange);
    updateLoadingMessage('Loading AI model...');
    await loadAutoScoringPref();
    // Rejoin scenario: Agora credentials arrive later via game_state_sync.
    // Show loading spinner instead of the manual dartboard until the model loads.
    if (autoScoringEnabled && agoraEngine == null && !kIsWeb && AutoScoringService.isSupported) {
      setState(() => autoScoringLoading = true);
      // If game_state_sync never arrives (or the reconnect wedges), the
      // watchdog drops the blocking overlay instead of spinning forever.
      armAutoScoringLoadingWatchdog();
      // game_state_sync may have already fired before the listener was attached.
      // If so, process the pending reconnect now instead of waiting for next notification.
      if (game.needsAgoraReconnect) {
        game.clearAgoraReconnectFlag();
        reconnectAgora(game); // fire-and-forget; will reset autoScoringLoading when done
      }
    }
  }

  @override
  void disposeScreenSpecific() {
    // Safety-net forfeit for the swipe-back / app-kill paths. leaveMatch() only
    // emits when the game is still live (gameStarted && !gameEnded), so a screen
    // popped after the match already ended — including a ghost match the server
    // already voided — never triggers a spurious forfeit.
    leaveMatch();
    try {
      context.read<GameProvider>().removeListener(handleSharedStateChange);
    } catch (e) {
      debugPrint('[GameScreen] Error removing listener: $e');
    }
  }
  





  void _showRankChangeAndNavigateHome(String oldRank, String newRank, GameProvider game) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: true,
        pageBuilder: (context, _, __) => RankChangeOverlay(
          oldRank: oldRank,
          newRank: newRank,
          onDismiss: () {
            game.reset();
            AppNavigator.toHomeClearing(context);
          },
        ),
        transitionsBuilder: (context, animation, _, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  void _showEloChangeOverlay({
    required int oldElo,
    required int newElo,
    required bool isWin,
    required GameProvider game,
    String? oldRank,
    String? newRank,
  }) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: true,
        pageBuilder: (context, _, __) => EloChangeOverlay(
          oldElo: oldElo,
          newElo: newElo,
          isWin: isWin,
          onDismiss: () {
            Navigator.of(context).pop(); // pop the elo overlay
            if (oldRank != null && newRank != null && oldRank != newRank) {
              _showRankChangeAndNavigateHome(oldRank, newRank, game);
            } else {
              game.reset();
              AppNavigator.toHomeClearing(context);
            }
          },
        ),
        transitionsBuilder: (context, animation, _, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  void _acceptMatchResult(GameProvider game, AuthProvider auth) async {
    if (game.matchId == null || auth.currentUser?.id == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final l10n = AppLocalizations.of(context);
      final oldRank = auth.currentUser!.rank;
      final oldElo = auth.currentUser!.elo;
      final didWin = game.winnerId == auth.currentUser!.id;
      messenger.showSnackBar(SnackBar(content: Text(l10n.acceptingMatchResult), duration: const Duration(seconds: 1)));
      await MatchService.acceptMatchResult(game.matchId!, auth.currentUser!.id);
      if (!mounted) return;
      await auth.checkAuthStatus();
      if (!mounted) return;
      final newRank = auth.currentUser?.rank ?? oldRank;
      final newElo = auth.currentUser?.elo ?? oldElo;
      _showEloChangeOverlay(
        oldElo: oldElo,
        newElo: newElo,
        isWin: didWin,
        game: game,
        oldRank: oldRank,
        newRank: newRank,
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('${AppLocalizations.of(context).error}: $e'), backgroundColor: AppTheme.error, duration: const Duration(seconds: 3)));
    }
  }



  @override
  void showForfeitDialog(dynamic game) {
    forfeitDialogShowing = true;
    final auth = context.read<AuthProvider>();
    // The screen can unmount while this dialog is still up (leaving the match
    // pops the route, but the dialog lives on the root overlay), and
    // actionsBuilder re-runs on every dialog rebuild — so nothing below may
    // touch the State's `context` after this point. Capture l10n now.
    final l10n = AppLocalizations.of(context);
    final forfeitData = game.pendingData;
    final winnerId = forfeitData?['winnerId'] as String?;
    final eloChange = forfeitData?['winnerEloChange'] as int? ?? 0;
    final isWinner = winnerId == auth.currentUser?.id;
    showGameDialog(
      context,
      accent: isWinner ? AppTheme.success : AppTheme.opponentPink,
      icon: isWinner ? Icons.emoji_events : Icons.exit_to_app,
      title: isWinner ? l10n.victory : l10n.gameOver,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            isWinner ? l10n.opponentLeftForfeit : l10n.youLeftForfeited,
            style: AppTheme.bodyLarge.copyWith(fontSize: 16),
            textAlign: TextAlign.center,
          ),
          if (isWinner) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.success.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${l10n.eloChange}: ${eloChange >= 0 ? '+' : ''}$eloChange',
                style: const TextStyle(
                  color: AppTheme.success,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ],
      ),
      actionsBuilder: (dialogCtx) => [
        ElevatedButton(
          onPressed: () async {
            forfeitDialogShowing = false;
            final oldRank = auth.currentUser?.rank ?? 'unranked';
            final oldElo = auth.currentUser?.elo ?? 1200;
            Navigator.of(dialogCtx).pop();
            await auth.checkAuthStatus();
            // State.mounted, not context.mounted: reading a defunct State's
            // `context` getter itself throws once the screen has unmounted.
            if (!mounted) return;
            final newRank = auth.currentUser?.rank ?? oldRank;
            final newElo = auth.currentUser?.elo ?? oldElo;
            _showEloChangeOverlay(
              oldElo: oldElo,
              newElo: newElo,
              isWin: isWinner,
              game: game,
              oldRank: oldRank,
              newRank: newRank,
            );
          },
          style: gameFilledButtonStyle(isWinner ? AppTheme.success : AppTheme.playerBlue),
          child: Text(l10n.continuePlaying),
        ),
      ],
    ).then((_) => forfeitDialogShowing = false);
  }

  @override
  Widget buildEndScreen(dynamic game, AuthProvider auth) {
    // BO3: a leg just ended but the series continues — show the leg result
    // while the server prepares the next leg (ranked_next_leg resets
    // gameEnded and brings the board back automatically).
    if (game.isRankedSeries == true && game.seriesEnded != true) {
      return _buildLegEndScreen(game as GameProvider, auth);
    }
    final l10n = AppLocalizations.of(context);
    final didWin = game.winnerId == auth.currentUser?.id;

    final resultPanel = Column(mainAxisSize: MainAxisSize.min, children: [
      Text(l10n.matchResult, style: AppTheme.titleLarge.copyWith(color: AppTheme.primary, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
      const SizedBox(height: 8),
      Text(l10n.pleaseConfirmResult, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14), textAlign: TextAlign.center),
      const SizedBox(height: 20),
      SizedBox(width: double.infinity, height: 56, child: ElevatedButton.icon(
        onPressed: () { HapticService.mediumImpact(); _acceptMatchResult(game, auth); },
        style: ElevatedButton.styleFrom(backgroundColor: AppTheme.success, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
        icon: const Icon(Icons.check_circle_outline),
        label: Text(l10n.acceptResult, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
      )),
      const SizedBox(height: 12),
      SizedBox(width: double.infinity, height: 56, child: OutlinedButton.icon(
        onPressed: () {
          HapticService.lightImpact();
          showReportDialog(
            onSubmit: (reason, comment) async {
              if (game.matchId == null || auth.currentUser?.id == null) return;
              final result = await MatchService.disputeMatchResult(game.matchId!, auth.currentUser!.id, reason, comment: comment);
              final msg = result['message'] as String? ?? 'Dispute submitted';
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: AppTheme.error, duration: const Duration(seconds: 2)));
              Future.delayed(const Duration(seconds: 2), () { if (mounted) Navigator.of(context).pop(); });
            },
            onComplete: () {},
          );
        },
        style: OutlinedButton.styleFrom(foregroundColor: AppTheme.error, side: BorderSide(color: AppTheme.error.withValues(alpha: 0.5), width: 2), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
        icon: const Icon(Icons.flag_outlined),
        label: Text(l10n.reportPlayer, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
      )),
    ]);

    return MatchEndView(
      didWin: didWin,
      title: didWin ? l10n.victory : l10n.defeat,
      subtitle: didWin ? l10n.provenLegend : l10n.trainingPath,
      scoreLine: game.isRankedSeries == true ? '${game.myLegsWon} – ${game.opponentLegsWon}' : null,
      scoreCaption: game.isRankedSeries == true ? l10n.bestOfN(game.bestOf as int) : null,
      // Friendly matches don't affect ELO — swap the accept/report panel for a
      // "play again?" rematch panel.
      panel: game.isFriendly ? _buildFriendlyEndPanel(game) : resultPanel,
    );
  }


  /// Between-legs screen for ranked BO3: leg result + series score + a
  /// "next leg" spinner. No buttons — ranked_next_leg drives the transition
  /// (gameEnded flips back to false and the board returns), and leaving here
  /// would forfeit the series, exactly like leaving mid-leg.
  Widget _buildLegEndScreen(GameProvider game, AuthProvider auth) {
    final l10n = AppLocalizations.of(context);
    final wonLeg = game.legWinnerId == auth.currentUser?.id ||
        (game.legWinnerId == null && game.winnerId == auth.currentUser?.id);
    final accent = wonLeg ? AppTheme.success : AppTheme.error;
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    // PopScope: the series is still live here — a bare back press silently
    // abandoned it (no dialog, no leave_match). Route through onWillPop like
    // the live board does.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        // `mounted`, not `context.mounted`: no build param here, so `context`
        // is the State getter, which throws once the screen has unmounted.
        if (await onWillPop() && mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.surfaceGradient),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: EdgeInsets.all(isLandscape ? 16 : 24),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                      border: Border.all(color: accent, width: 3),
                    ),
                    child: Icon(
                      wonLeg ? Icons.check_circle_outline : Icons.close,
                      color: accent,
                      size: isLandscape ? 40 : 56,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    wonLeg ? l10n.legWon.toUpperCase() : l10n.legLost.toUpperCase(),
                    style: AppTheme.displayLarge.copyWith(color: accent, fontSize: isLandscape ? 28 : 36),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '${game.myLegsWon} – ${game.opponentLegsWon}',
                    style: AppTheme.displayLarge.copyWith(color: Colors.white, fontSize: isLandscape ? 32 : 44),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.firstToNLegs(game.legsNeeded),
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  const CircularProgressIndicator(color: AppTheme.primary),
                  const SizedBox(height: 12),
                  Text(
                    l10n.nextLeg,
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14, letterSpacing: 1),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      ),
    );
  }

  void _leaveFriendlyToHome(GameProvider game) {
    HapticService.lightImpact();
    game.declineRematch();
    AppNavigator.toHomeClearing(context);
  }

  /// End-of-match panel for friendly (non-ranked) matches: a "play again?"
  /// rematch flow instead of the ranked accept-result / report panel.
  Widget _buildFriendlyEndPanel(GameProvider game) {
    final l10n = AppLocalizations.of(context);
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    Widget content;
    if (game.rematchDeclined) {
      content = Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.sentiment_dissatisfied,
            color: AppTheme.textSecondary, size: 40),
        const SizedBox(height: 12),
        Text(
          l10n.opponentDeclinedRematch,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: () {
              HapticService.lightImpact();
              AppNavigator.toHomeClearing(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
            child: Text(l10n.continueButton,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1)),
          ),
        ),
      ]);
    } else if (game.rematchWaiting) {
      content = Column(mainAxisSize: MainAxisSize.min, children: [
        const CircularProgressIndicator(color: AppTheme.primary),
        const SizedBox(height: 16),
        Text(
          l10n.waitingForOpponent,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => _leaveFriendlyToHome(game),
          child: Text(l10n.cancel,
              style: const TextStyle(color: AppTheme.textSecondary)),
        ),
      ]);
    } else {
      content = Column(mainAxisSize: MainAxisSize.min, children: [
        Text(
          l10n.playAgainQuestion,
          style: AppTheme.titleLarge
              .copyWith(color: AppTheme.primary, fontWeight: FontWeight.bold),
        ),
        if (game.opponentWantsRematch) ...[
          const SizedBox(height: 8),
          Text(
            l10n.opponentWantsToPlayAgain
                .replaceAll('{username}', widget.opponentUsername),
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.success, fontSize: 13),
          ),
        ],
        SizedBox(height: isLandscape ? 16 : 24),
        SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton.icon(
            onPressed: () {
              HapticService.mediumImpact();
              game.requestRematch();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.success,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
            icon: const Icon(Icons.replay),
            label: Text(l10n.playAgain,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1)),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 56,
          child: OutlinedButton(
            onPressed: () => _leaveFriendlyToHome(game),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.textSecondary,
              side: BorderSide(
                  color: AppTheme.surfaceLight.withValues(alpha: 0.5), width: 2),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
            child: Text(l10n.no,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1)),
          ),
        ),
      ]);
    }

    // No card chrome here: MatchEndView wraps the panel in the shared card.
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(
        l10n.friendlyMatchLabel.toUpperCase(),
        style: const TextStyle(
            color: AppTheme.textSecondary, fontSize: 12, letterSpacing: 1.5),
      ),
      SizedBox(height: isLandscape ? 12 : 16),
      content,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) return buildLoadingScreen();

    try {
      final game = context.watch<GameProvider>();
      final auth = context.watch<AuthProvider>();

      // BO3 between-legs: after ranked_next_leg (_gameStarted=false, next leg
      // not started yet) keep the leg result + series score on screen instead
      // of the generic "INITIALIZING MATCH" spinner — the ~2s transition made
      // every leg change look like a crash and hid the series score. And if
      // the series ENDS in that window (opponent forfeits), go straight to
      // the final end screen, which the init branch below would have masked.
      if (game.isRankedSeries && !game.gameStarted && game.currentLeg > 1) {
        if (game.seriesEnded) return buildEndScreen(game, auth);
        return _buildLegEndScreen(game, auth);
      }

      if (game.matchId == null || !game.gameStarted) return buildInitializingScreen();
      if (game.gameEnded && game.pendingType != 'forfeit') return buildEndScreen(game, auth);

      return buildLiveMatchBody(game, auth);
    } catch (e, stackTrace) {
      return Scaffold(
        appBar: AppBar(title: Text(AppLocalizations.of(context).error)),
        body: Center(
          child: Text('${AppLocalizations.of(context).error}: $e\n$stackTrace'),
        ),
      );
    }
  }





}
