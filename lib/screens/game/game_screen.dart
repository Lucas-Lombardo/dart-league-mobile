import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/cricket.dart';
import '../../providers/game_provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/match_service.dart';
import '../../utils/haptic_service.dart';
import '../../utils/app_theme.dart';
import '../../widgets/design_system.dart';
import '../../widgets/game_turn_ui.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/app_navigator.dart';
import '../../widgets/rank_change_overlay.dart';
import '../../widgets/elo_change_overlay.dart';
import '../../services/turn_report_service.dart';
import 'base_game_screen_state.dart';
import 'leg_end_view.dart';
import 'match_end_view.dart';
import 'turn_reports_view.dart';

class GameScreen extends StatefulWidget {
  final String matchId;
  final String opponentId;
  final String opponentUsername;

  const GameScreen({
    super.key,
    required this.matchId,
    required this.opponentId,
    required this.opponentUsername,
  });

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends BaseGameScreenState<GameScreen> {
  String? _storedMatchId;

  @override
  dynamic readGame() => context.read<GameProvider>();

  @override
  String get aiTelemetryContext =>
      readGame().isFriendly == true ? 'friendly' : 'ranked';

  @override
  String get opponentUsername => widget.opponentUsername;

  @override
  String? get matchIdForLeave => _storedMatchId;

  @override
  @override
  String get leaveWarningText =>
      AppLocalizations.of(context).forfeitMatchWarning;

  @override
  Widget buildAppBarTitle() => Row(children: [
    Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppTheme.secondary, shape: BoxShape.circle)),
    const SizedBox(width: 8),
    Text(dsSentence(AppLocalizations.of(context).liveMatch), style: AppTheme.sectionTitle),
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
    );
    gameStarted = game.gameStarted;
    gameEnded = game.gameEnded;
    await startMatchVideo(
      game: game,
      matchId: widget.matchId,
      opponentId: widget.opponentId,
    );
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
      accent: isWinner ? AppTheme.success : AppTheme.error,
      icon: isWinner ? Icons.emoji_events_outlined : Icons.logout_rounded,
      title: isWinner ? l10n.victory : l10n.gameOver,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isWinner ? l10n.opponentLeftForfeit : l10n.youLeftForfeited,
            style: AppTheme.bodyMedium,
          ),
          if (isWinner) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Text(l10n.eloChange, style: AppTheme.caption),
                const SizedBox(width: 10),
                Container(
                  height: 28,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppTheme.success.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${eloChange >= 0 ? '+' : ''}$eloChange',
                    style: const TextStyle(
                      color: AppTheme.success,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      height: 1,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
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

    // Step 1 of 2: the visits flagged during the match need a reason before
    // anything else. Only shown to a player who actually flagged something —
    // for everyone else this is the screen they have always seen.
    if (!turnReportsSettled && TurnReportService.pending.isNotEmpty) {
      return TurnReportsView(
        onEdit: (report) => editTurnReport(report),
        onContinue: () => finishTurnReports(
          matchId: game.matchId as String?,
          seriesId: game.seriesId as String?,
        ),
      );
    }

    // The ONE filled block of the screen (accept) over a quiet outlined
    // report action — no card around them, the hero above already frames the
    // result.
    final resultPanel = Column(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(width: double.infinity, height: 52, child: ElevatedButton(
        onPressed: () { HapticService.mediumImpact(); _acceptMatchResult(game, auth); },
        child: Text(dsSentence(l10n.acceptResult)),
      )),
      const SizedBox(height: 10),
      SizedBox(width: double.infinity, height: 48, child: OutlinedButton.icon(
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
        style: OutlinedButton.styleFrom(foregroundColor: AppTheme.textSecondary, textStyle: gameButtonTextStyle.copyWith(fontSize: 14)),
        icon: const Icon(Icons.flag_outlined, size: 16),
        label: Text(dsSentence(l10n.reportPlayer)),
      )),
    ]);

    // Cricket friendly: the meaningful final score is points (score mode) or
    // closed targets (no-score) — the X01 columns never moved.
    final cricket = cricketStateOf(game);
    final cricketScoreLine = cricket == null
        ? null
        : cricket.scoreMode == CricketScoreMode.noScore
            ? '${cricket.myClosedCount}/${kCricketTargets.length} – ${cricket.oppClosedCount}/${kCricketTargets.length}'
            : '${cricket.myPoints} – ${cricket.oppPoints}';
    final cricketCaption = cricket == null
        ? null
        : '${l10n.cricketLabel} · ${cricket.scoreMode == CricketScoreMode.noScore ? l10n.cricketNoScoreLabel : l10n.cricketScoreLabel}';

    return MatchEndView(
      didWin: didWin,
      title: didWin ? l10n.victory : l10n.defeat,
      subtitle: didWin ? l10n.provenLegend : l10n.trainingPath,
      scoreLine: game.isRankedSeries == true ? '${game.myLegsWon} – ${game.opponentLegsWon}' : cricketScoreLine,
      scoreCaption: game.isRankedSeries == true ? l10n.bestOfN(game.bestOf as int) : cricketCaption,
      // Friendly matches don't affect ELO — swap the accept/report panel for a
      // "play again?" rematch panel.
      panel: game.isFriendly ? _buildFriendlyEndPanel(game) : resultPanel,
      replayClips: matchReplayClips,
      // The loser's only chance at the winning visit: they were sent straight
      // here by game_won, with no confirmation step of their own to hang it on.
      preCard: buildWinningVisitBanner(game, didWin: didWin),
      // The server already replayed these darts; the card asks it for them
      // rather than re-deriving anything client-side.
      statsMatchId: game.matchId as String?,
    );
  }


  /// Between-legs screen for ranked BO3 — the shared [LegEndView]. No buttons:
  /// ranked_next_leg drives the transition (gameEnded flips back to false and
  /// the board returns), but never before the screen has had its minimum time
  /// on screen (see [armLegEndDwell]).
  Widget _buildLegEndScreen(GameProvider game, AuthProvider auth) {
    armLegEndDwell();
    // Snapshotted, not re-read: the next leg's game_started can land while
    // this screen is still held open, and it clears legWinnerId.
    final wonLeg = legEndWonLeg(game.legWinnerId == auth.currentUser?.id ||
        (game.legWinnerId == null && game.winnerId == auth.currentUser?.id));
    return LegEndView(
      secondsLeft: legEndSecondsLeft,
      wonLeg: wonLeg,
      myLegsWon: game.myLegsWon,
      opponentLegsWon: game.opponentLegsWon,
      legsNeeded: game.legsNeeded,
      onAttemptPop: onWillPop,
      // Same offer as on the end-of-match screen, one leg earlier: this is
      // where the loser of legs 1 and 2 lands. The report joins the list and
      // gets its reason with the others when the series ends.
      banner: legEndWinningVisitBanner(game, didWin: wonLeg),
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
        const Icon(Icons.sentiment_dissatisfied_outlined,
            color: AppTheme.textSecondary, size: 32),
        const SizedBox(height: 10),
        Text(
          l10n.opponentDeclinedRematch,
          textAlign: TextAlign.center,
          style: AppTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: () {
              HapticService.lightImpact();
              AppNavigator.toHomeClearing(context);
            },
            child: Text(dsSentence(l10n.continueButton)),
          ),
        ),
      ]);
    } else if (game.rematchWaiting) {
      content = Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 2),
        ),
        const SizedBox(height: 14),
        Text(
          l10n.waitingForOpponent,
          textAlign: TextAlign.center,
          style: AppTheme.bodyMedium.copyWith(color: AppTheme.textPrimary),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => _leaveFriendlyToHome(game),
          style: TextButton.styleFrom(foregroundColor: AppTheme.textSecondary),
          child: Text(l10n.cancel),
        ),
      ]);
    } else {
      content = Column(mainAxisSize: MainAxisSize.min, children: [
        Text(l10n.playAgainQuestion, style: AppTheme.sectionTitle),
        if (game.opponentWantsRematch) ...[
          const SizedBox(height: 6),
          Text(
            l10n.opponentWantsToPlayAgain
                .replaceAll('{username}', widget.opponentUsername),
            textAlign: TextAlign.center,
            style: AppTheme.caption.copyWith(
                color: AppTheme.success, fontWeight: FontWeight.w600),
          ),
        ],
        SizedBox(height: isLandscape ? 12 : 16),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton.icon(
            onPressed: () {
              HapticService.mediumImpact();
              game.requestRematch();
            },
            icon: const Icon(Icons.replay_rounded, size: 20),
            label: Text(l10n.playAgain),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton(
            onPressed: () => _leaveFriendlyToHome(game),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.textSecondary,
              textStyle: gameButtonTextStyle.copyWith(fontSize: 14),
            ),
            child: Text(l10n.no),
          ),
        ),
      ]);
    }

    // No card chrome here: the end screen lays its actions flat on the
    // background, under a group label.
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(l10n.friendlyMatchLabel.toUpperCase(), style: AppTheme.labelSmall),
      SizedBox(height: isLandscape ? 10 : 14),
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

      // The next leg can arrive within a second of the checkout; the loser's
      // window to report the winning visit lives on the screen it replaces,
      // so the board waits out the dwell (a series ending still wins — the
      // final screen carries the same offer).
      if (game.isRankedSeries && !game.seriesEnded && legEndHoldActive) {
        return _buildLegEndScreen(game, auth);
      }

      if (game.matchId == null || !game.gameStarted) return buildInitializingScreen();
      if (game.gameEnded && game.pendingType != 'forfeit') return buildEndScreen(game, auth);

      clearLegEndDwell();
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
