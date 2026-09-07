import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/tournament_game_provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/match_service.dart';
import '../../utils/app_navigator.dart';
import '../../utils/haptic_service.dart';
import '../../utils/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/design_system.dart';
import '../../widgets/game_turn_ui.dart';
import '../game/base_game_screen_state.dart';
import '../game/leg_end_view.dart';
import '../../services/turn_report_service.dart';
import '../game/match_end_view.dart';
import '../game/turn_reports_view.dart';
import 'tournament_match_result_screen.dart';

class TournamentGameScreen extends StatefulWidget {
  final String tournamentMatchId;
  final String gameMatchId;
  final String tournamentId;
  final String tournamentName;
  final String roundName;
  final String opponentUsername;
  final String opponentId;
  final int bestOf;

  const TournamentGameScreen({
    super.key,
    required this.tournamentMatchId,
    required this.gameMatchId,
    required this.tournamentId,
    required this.tournamentName,
    required this.roundName,
    required this.opponentUsername,
    required this.opponentId,
    required this.bestOf,
  });

  @override
  State<TournamentGameScreen> createState() => _TournamentGameScreenState();
}

class _TournamentGameScreenState extends BaseGameScreenState<TournamentGameScreen> {
  bool _navigatingToResult = false;
  bool _resultAccepted = false;
  String? _storedMatchId;

  // ─── Abstract overrides ───────────────────────────────────────────────────────
  @override
  dynamic readGame() => context.read<TournamentGameProvider>();

  @override
  String get aiTelemetryContext => 'tournament';

  @override
  String get opponentUsername => widget.opponentUsername;

  @override
  String? get matchIdForLeave => _storedMatchId;

  @override
  String get leaveWarningText =>
      AppLocalizations.of(context).forfeitTournamentWarning;

  @override
  Widget buildAppBarTitle() => Row(children: [
    Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppTheme.secondary, shape: BoxShape.circle)),
    const SizedBox(width: 8),
    Text(dsSentence(AppLocalizations.of(context).tournamentAppBarTitle), style: AppTheme.sectionTitle),
  ]);

  @override
  void onScreenSpecificStateChange(dynamic game) {
    final tGame = game as TournamentGameProvider;
    _storedMatchId = tGame.currentGameMatchId;
    if (tGame.tournamentState == TournamentGameState.playing && !tGame.gameEnded) {
      _resultAccepted = false;
      _navigatingToResult = false;
    }
    // legEnded needs no navigation: build renders the shared LegEndView
    // inline (same as ranked BO3) and the next leg's game_started swaps the
    // board back in.
    if (_resultAccepted) {
      if (tGame.tournamentState == TournamentGameState.seriesEnded && !_navigatingToResult) {
        _navigatingToResult = true;
        WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _navigateToMatchResult(tGame); });
      }
    }
  }

  @override
  Future<void> initScreenSpecific() async {
    final game = context.read<TournamentGameProvider>();
    final auth = context.read<AuthProvider>();
    if (auth.currentUser == null) return;
    storedPlayerId = auth.currentUser!.id;
    _storedMatchId = game.currentGameMatchId;
    gameStarted = game.gameStarted;
    gameEnded = game.gameEnded;
    updateLoadingMessage('Joining match...');
    await startMatchVideo(
      game: game,
      matchId: game.currentGameMatchId,
      opponentId: widget.opponentId,
    );
  }

  @override
  void disposeScreenSpecific() {
    leaveMatch();
    try { context.read<TournamentGameProvider>().removeListener(handleSharedStateChange); } catch (e) { debugPrint('[TournamentGame] Error removing listener: $e'); }
  }



  void _navigateToMatchResult(TournamentGameProvider game) {
    AppNavigator.replaceWith(
      context,
      TournamentMatchResultScreen(
        tournamentMatchId: widget.tournamentMatchId,
        tournamentId: widget.tournamentId,
        tournamentName: widget.tournamentName,
        roundName: widget.roundName,
        opponentUsername: widget.opponentUsername,
        seriesWinnerId: game.seriesWinnerId,
        myLegsWon: game.myLegsWon,
        opponentLegsWon: game.opponentLegsWon,
        bestOf: widget.bestOf,
      ),
    );
  }





  // ─── Tournament-specific accept result ────────────────────────────────────────
  void _acceptTournamentResult() async {
    final game = context.read<TournamentGameProvider>();
    final auth = context.read<AuthProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);

    if (game.currentGameMatchId == null || auth.currentUser?.id == null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).unableToAcceptResult),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }

    try {
      await MatchService.acceptMatchResult(
        game.currentGameMatchId!,
        auth.currentUser!.id,
      );
    } catch (e) {
      debugPrint('Error accepting tournament match result: $e');
      // Surface it, but continue: the result is already applied server-side;
      // acceptance is a confirmation, not a gate.
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.unableToAcceptResult),
          backgroundColor: AppTheme.error,
        ),
      );
    }

    if (!mounted) return;

    setState(() {
      _resultAccepted = true;
    });

    handleSharedStateChange();
  }

  // Shown after the player contests a result: the match is frozen server-side
  // until an admin picks the winner — leave the game flow entirely.
  void _showResultUnderReviewAndExit() {
    final l10n = AppLocalizations.of(context);
    showGameDialog<void>(
      context,
      accent: AppTheme.primary,
      icon: Icons.gavel_rounded,
      title: l10n.resultUnderReviewTitle,
      content: Text(l10n.resultUnderReviewBody, style: AppTheme.bodyMedium),
      actionsBuilder: (ctx) => [
        ElevatedButton(
          onPressed: () {
            Navigator.of(ctx).pop();
            if (!mounted) return;
            final provider = context.read<TournamentGameProvider>();
            AppNavigator.toHomeClearing(context);
            try {
              provider.reset();
            } catch (_) {}
          },
          child: Text(dsSentence(l10n.ok)),
        ),
      ],
    );
  }


  // ─── Overridden dialogs / end-screen ──────────────────────────────────────────
  @override
  void showForfeitDialog(dynamic game) {
    forfeitDialogShowing = true;
    final auth = context.read<AuthProvider>();
    final tGame = game as TournamentGameProvider;
    final winnerId = tGame.pendingData?['winnerId'] as String?;
    final isWinner = winnerId == auth.currentUser?.id;
    final parentNav = Navigator.of(context);
    // The screen can unmount while this dialog is still up (leaving the match
    // pops the route, but the dialog lives on the root overlay), and
    // actionsBuilder re-runs on every dialog rebuild — so nothing below may
    // touch the State's `context` after this point. Capture l10n now.
    final l10n = AppLocalizations.of(context);

    showGameDialog(
      context,
      accent: isWinner ? AppTheme.success : AppTheme.opponentPink,
      icon: isWinner ? Icons.emoji_events_outlined : Icons.logout_rounded,
      title: isWinner ? l10n.youAdvance : l10n.eliminated,
      content: Text(
        isWinner ? l10n.opponentLeftForfeitAdvance : l10n.youLeftEliminated,
        style: AppTheme.bodyMedium.copyWith(color: AppTheme.textPrimary),
      ),
      actionsBuilder: (dialogCtx) => [
        ElevatedButton(
          onPressed: () {
            forfeitDialogShowing = false;
            Navigator.of(dialogCtx).pop();
            game.reset();
            parentNav.pushNamedAndRemoveUntil('/home', (route) => false);
          },
          style: gameFilledButtonStyle(isWinner ? AppTheme.success : AppTheme.playerBlue),
          child: Text(dsSentence(l10n.returnToHome)),
        ),
      ],
    ).then((_) => forfeitDialogShowing = false);
  }

  @override
  String? get replayFormatLabel => widget.tournamentName.isNotEmpty
      ? widget.tournamentName.toUpperCase()
      : 'TOURNAMENT';

  @override
  Widget buildEndScreen(dynamic game, AuthProvider auth) {
    if (_resultAccepted) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final tGame = game as TournamentGameProvider;
    final didWin = tGame.winnerId == auth.currentUser?.id;
    final isSeriesOver = tGame.tournamentState == TournamentGameState.seriesEnded;

    // Step 1 of 2, same order as a ranked match: the visits flagged during
    // play get their reason first, the result is confirmed after. Only at the
    // END of the series — between legs the reports keep accumulating.
    if (isSeriesOver &&
        !turnReportsSettled &&
        TurnReportService.pending.isNotEmpty) {
      return TurnReportsView(
        onEdit: (report) => editTurnReport(report),
        onContinue: () =>
            finishTurnReports(matchId: tGame.currentGameMatchId),
      );
    }

    // One filled block (accept) over a quiet outlined refusal — the hero and
    // the tournament pill above already frame the result, so no card here.
    final panel = Column(mainAxisSize: MainAxisSize.min, children: [
      Text(
        dsSentence(isSeriesOver ? l10n.matchResult : l10n.legResultSubtitle(tGame.currentLeg)),
        style: AppTheme.sectionTitle,
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 6),
      Text(
        isSeriesOver ? l10n.pleaseConfirmMatchResult : l10n.confirmNextLeg,
        style: AppTheme.caption,
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 16),
      SizedBox(width: double.infinity, height: 52, child: ElevatedButton(
        onPressed: () { HapticService.mediumImpact(); _acceptTournamentResult(); },
        child: Text(dsSentence(l10n.acceptResult)),
      )),
      const SizedBox(height: 10),
      // Tournament matches get "refuse the result" (a dispute with a reason,
      // reviewed by an admin), not the ranked "report player" wording.
      SizedBox(width: double.infinity, height: 48, child: OutlinedButton.icon(
        onPressed: () {
          HapticService.lightImpact();
          showReportDialog(
            title: l10n.refuseResult,
            subtitle: l10n.refuseResultReasonPrompt,
            submitLabel: l10n.submitRefusal,
            icon: Icons.cancel_outlined,
            reasons: [
              l10n.reportReasonIncorrectScore,
              l10n.reportReasonCheating,
              l10n.reportReasonConnectionIssues,
              l10n.reportReasonOther,
            ],
            onSubmit: (reason, comment) async {
              if (tGame.currentGameMatchId == null || auth.currentUser?.id == null) return;
              await MatchService.disputeMatchResult(tGame.currentGameMatchId!, auth.currentUser!.id, reason, comment: comment);
              // The tournament match is now frozen server-side pending admin
              // review — do NOT continue as if the result stood (this used
              // to show the ADVANCE/ELIMINATED ceremony right after
              // contesting it).
              if (mounted) _showResultUnderReviewAndExit();
            },
            onComplete: () {},
          );
        },
        style: OutlinedButton.styleFrom(foregroundColor: AppTheme.error, textStyle: gameButtonTextStyle.copyWith(fontSize: 14)),
        icon: const Icon(Icons.cancel_outlined, size: 16),
        label: Text(dsSentence(l10n.refuseResult)),
      )),
    ]);

    return MatchEndView(
      didWin: didWin,
      title: isSeriesOver
          ? (didWin ? l10n.matchWonTitle : l10n.matchLostTitle)
          : (didWin ? l10n.legWonTitle(tGame.currentLeg) : l10n.legLostTitle(tGame.currentLeg)),
      subtitle: didWin ? l10n.wellPlayedConfirmResult : (isSeriesOver ? l10n.betterLuckNextTime : l10n.betterLuckNextLeg),
      scoreLine: '${tGame.myLegsWon} – ${tGame.opponentLegsWon}',
      scoreCaption: l10n.bestOfN(widget.bestOf),
      badgeText: widget.tournamentName,
      panel: panel,
      replayClips: matchReplayClips,
      // Tournament legs land on this same screen rather than a LegEndView, so
      // it carries the winning-visit offer for every leg, not just the last.
      preCard: buildWinningVisitBanner(tGame, didWin: didWin),
      // Asks the server for the figures it already replayed — and for a leg of
      // a series it answers for the whole series, which is the match played.
      statsMatchId: tGame.currentGameMatchId,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) return buildLoadingScreen();

    try {
      final game = context.watch<TournamentGameProvider>();
      final auth = context.watch<AuthProvider>();

      // Between-legs, result accepted: the shared LegEndView, exactly like
      // ranked BO3 — no button, tournament_next_leg + game_started flip the
      // provider back to a live leg and this build returns the board. Checked
      // BEFORE the gameStarted gate: the inter-leg window has gameStarted
      // false and would otherwise flash "initializing match".
      if (_resultAccepted &&
          game.tournamentState == TournamentGameState.legEnded) {
        return LegEndView(
          // No legWinnerId==null fallback here (unlike ranked): the state
          // only reaches legEnded via tournament_leg_won, which carries it.
          wonLeg: game.legWinnerId == auth.currentUser?.id,
          myLegsWon: game.myLegsWon,
          opponentLegsWon: game.opponentLegsWon,
          legsNeeded: game.legsNeeded,
          onAttemptPop: onWillPop,
        );
      }

      if (!game.gameStarted) return buildInitializingScreen();
      if (game.gameEnded && !_resultAccepted && game.pendingType != 'forfeit') return buildEndScreen(game, auth);

      return buildLiveMatchBody(game, auth);
    } catch (e, stackTrace) {
      return Scaffold(
        appBar: AppBar(title: Text(AppLocalizations.of(context).error)),
        body: Center(child: Text('${AppLocalizations.of(context).error}: $e\n$stackTrace')),
      );
    }
  }


}
