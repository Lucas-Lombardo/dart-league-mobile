import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/tournament_game_provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/match_service.dart';
import '../../utils/haptic_service.dart';
import '../../utils/app_theme.dart';
import '../game/base_game_screen_state.dart';
import 'tournament_leg_result_screen.dart';
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
  String get opponentUsername => widget.opponentUsername;

  @override
  String? get matchIdForLeave => _storedMatchId;

  @override
  String get leaveWarningText =>
      'If you leave now, you will forfeit the tournament match and be eliminated.';

  @override
  Widget buildAppBarTitle() => Row(children: [
    Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppTheme.error, shape: BoxShape.circle)),
    const SizedBox(width: 8),
    const Text('TOURNAMENT', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 2, color: Colors.white)),
  ]);

  @override
  Widget? buildExtraHeader(dynamic game, AuthProvider auth) =>
      _buildSeriesScoreboard(game as TournamentGameProvider, auth);

  @override
  void onScreenSpecificStateChange(dynamic game) {
    final tGame = game as TournamentGameProvider;
    _storedMatchId = tGame.currentGameMatchId;
    if (tGame.tournamentState == TournamentGameState.playing && !tGame.gameEnded) {
      _resultAccepted = false;
      _navigatingToResult = false;
    }
    if (_resultAccepted) {
      if (tGame.tournamentState == TournamentGameState.legEnded && !_navigatingToResult) {
        _navigatingToResult = true;
        WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _navigateToLegResult(tGame); });
      }
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
    if (game.agoraAppId != null && game.agoraAppId!.isNotEmpty) {
      await initializeAgora(
        appId: game.agoraAppId!,
        token: game.agoraToken ?? '',
        channelName: game.agoraChannelName ?? '',
      );
    }
    game.addListener(handleSharedStateChange);
    await loadAutoScoringPref();
  }

  @override
  void disposeScreenSpecific() {
    leaveMatch();
    try { context.read<TournamentGameProvider>().removeListener(handleSharedStateChange); } catch (_) {}
  }



  void _navigateToLegResult(TournamentGameProvider game) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => TournamentLegResultScreen(
          tournamentMatchId: widget.tournamentMatchId,
          tournamentName: widget.tournamentName,
          roundName: widget.roundName,
          opponentUsername: widget.opponentUsername,
          legWinnerId: game.legWinnerId,
          myLegsWon: game.myLegsWon,
          opponentLegsWon: game.opponentLegsWon,
          legsNeeded: game.legsNeeded,
          bestOf: widget.bestOf,
          currentLeg: game.currentLeg,
        ),
      ),
    ).then((_) {
      // When leg result screen is dismissed, reset navigation flag
      _navigatingToResult = false;
    });
  }

  void _navigateToMatchResult(TournamentGameProvider game) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => TournamentMatchResultScreen(
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
      ),
    );
  }





  // ─── Tournament-specific accept result ────────────────────────────────────────
  void _acceptTournamentResult() async {
    final game = context.read<TournamentGameProvider>();
    final auth = context.read<AuthProvider>();
    final messenger = ScaffoldMessenger.of(context);

    if (game.currentGameMatchId == null || auth.currentUser?.id == null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Unable to accept result: Missing data'),
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
    }

    if (!mounted) return;

    setState(() {
      _resultAccepted = true;
    });

    handleSharedStateChange();
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

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: isWinner ? AppTheme.success : AppTheme.error, width: 2),
        ),
        title: Row(
          children: [
            Icon(
              isWinner ? Icons.emoji_events : Icons.exit_to_app,
              color: isWinner ? AppTheme.success : AppTheme.error,
              size: 32,
            ),
            const SizedBox(width: 12),
            Text(
              isWinner ? 'YOU ADVANCE!' : 'ELIMINATED',
              style: AppTheme.titleLarge.copyWith(
                color: isWinner ? AppTheme.success : AppTheme.error,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Text(
          isWinner
              ? 'Your opponent has left. You win by forfeit and advance!'
              : 'You have left the game. You are eliminated from the tournament.',
          style: AppTheme.bodyLarge.copyWith(fontSize: 16),
          textAlign: TextAlign.center,
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              forfeitDialogShowing = false;
              Navigator.of(dialogCtx).pop();
              game.reset();
              parentNav.pushNamedAndRemoveUntil('/home', (route) => false);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: isWinner ? AppTheme.success : AppTheme.primary,
            ),
            child: const Text('Return to Home'),
          ),
        ],
      ),
    ).then((_) => forfeitDialogShowing = false);
  }

  @override
  Widget buildEndScreen(dynamic game, AuthProvider auth) {
    if (_resultAccepted) return const SizedBox.shrink();
    final tGame = game as TournamentGameProvider;
    final didWin = tGame.winnerId == auth.currentUser?.id;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.surfaceGradient),
        child: SafeArea(child: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: didWin ? AppTheme.success.withValues(alpha: 0.1) : AppTheme.error.withValues(alpha: 0.1),
              shape: BoxShape.circle,
              border: Border.all(color: didWin ? AppTheme.success : AppTheme.error, width: 4),
              boxShadow: [BoxShadow(color: (didWin ? AppTheme.success : AppTheme.error).withValues(alpha: 0.4), blurRadius: 40, spreadRadius: 10)],
            ),
            child: Icon(didWin ? Icons.emoji_events : Icons.sentiment_dissatisfied, color: didWin ? AppTheme.success : AppTheme.error, size: 80),
          ),
          const SizedBox(height: 32),
          Text(didWin ? 'LEG WON!' : 'LEG LOST', style: AppTheme.displayLarge.copyWith(color: didWin ? AppTheme.success : AppTheme.error, fontSize: 48)),
          const SizedBox(height: 16),
          Text(didWin ? 'Well played! Confirm the result to continue.' : 'Better luck next leg. Confirm the result to continue.', style: AppTheme.bodyLarge, textAlign: TextAlign.center),
          const SizedBox(height: 48),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppTheme.surfaceLight.withValues(alpha: 0.5))),
            child: Column(children: [
              Text('Match Result', style: AppTheme.titleLarge.copyWith(color: AppTheme.primary, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('Please confirm the match result', style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
              const SizedBox(height: 24),
              SizedBox(width: double.infinity, height: 56, child: ElevatedButton.icon(
                onPressed: () { HapticService.mediumImpact(); _acceptTournamentResult(); },
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.success, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('ACCEPT RESULT', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1)),
              )),
              const SizedBox(height: 12),
              SizedBox(width: double.infinity, height: 56, child: OutlinedButton.icon(
                onPressed: () {
                  HapticService.lightImpact();
                  showReportDialog(
                    onSubmit: (reason) async {
                      if (tGame.currentGameMatchId == null || auth.currentUser?.id == null) return;
                      await MatchService.disputeMatchResult(tGame.currentGameMatchId!, auth.currentUser!.id, reason);
                      if (mounted) { setState(() => _resultAccepted = true); handleSharedStateChange(); }
                    },
                    onComplete: () {},
                  );
                },
                style: OutlinedButton.styleFrom(foregroundColor: AppTheme.error, side: BorderSide(color: AppTheme.error.withValues(alpha: 0.5), width: 2), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                icon: const Icon(Icons.flag_outlined),
                label: const Text('REPORT PLAYER', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1)),
              )),
            ]),
          ),
        ]))),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) return buildLoadingScreen();

    try {
      final game = context.watch<TournamentGameProvider>();
      final auth = context.watch<AuthProvider>();

      if (!game.gameStarted) {
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) async {
            if (didPop) return;
            final shouldPop = await onWillPop();
            if (shouldPop && context.mounted) Navigator.of(context).pop();
          },
          child: Scaffold(
            backgroundColor: AppTheme.background,
            appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0, iconTheme: const IconThemeData(color: Colors.white)),
            body: const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: AppTheme.primary),
                  SizedBox(height: 16),
                  Text('INITIALIZING MATCH...', style: TextStyle(color: AppTheme.textSecondary, letterSpacing: 2, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
        );
      }

      if (game.gameEnded && !_resultAccepted && game.pendingType != 'forfeit') return buildEndScreen(game, auth);

      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          if (await onWillPop() && context.mounted) Navigator.of(context).pop();
        },
        child: Container(
          color: AppTheme.surface,
          child: SafeArea(
            top: false,
            child: Scaffold(
              backgroundColor: AppTheme.background,
              appBar: AppBar(
                backgroundColor: AppTheme.surface,
                title: buildAppBarTitle(),
                centerTitle: true,
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                  onPressed: () async {
                    if (await onWillPop() && context.mounted) Navigator.of(context).pop();
                  },
                ),
                actions: [
                  Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: Row(
                      children: [
                        const Icon(Icons.sports_esports_outlined, size: 16, color: AppTheme.textSecondary),
                        const SizedBox(width: 4),
                        Text('Dart ${game.dartsThrown + 1}/3', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.primary)),
                      ],
                    ),
                  ),
                ],
              ),
              body: buildGameBody(game, auth),
            ),
          ),
        ),
      );
    } catch (e, stackTrace) {
      return Scaffold(
        appBar: AppBar(title: const Text('Error')),
        body: Center(child: Text('Error: $e\n$stackTrace')),
      );
    }
  }


  Widget _buildSeriesScoreboard(TournamentGameProvider game, AuthProvider auth) {
    final myUsername = auth.currentUser?.username ?? 'You';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border(
          bottom: BorderSide(color: AppTheme.primary.withValues(alpha: 0.3)),
        ),
      ),
      child: Row(
        children: [
          // My legs
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(myUsername.toUpperCase(), style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5), overflow: TextOverflow.ellipsis),
                Text('${game.myLegsWon}', style: const TextStyle(color: AppTheme.primary, fontSize: 24, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          // Center: round info + leg indicator
          Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  widget.roundName.replaceAll('_', ' ').toUpperCase(),
                  style: const TextStyle(color: AppTheme.primary, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                ),
              ),
              const SizedBox(height: 2),
              Text('Leg ${game.currentLeg}', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
              Text('Best of ${widget.bestOf}', style: TextStyle(color: AppTheme.textSecondary.withValues(alpha: 0.6), fontSize: 9)),
            ],
          ),
          // Opponent legs
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(widget.opponentUsername.toUpperCase(), style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5), overflow: TextOverflow.ellipsis),
                Text('${game.opponentLegsWon}', style: const TextStyle(color: AppTheme.error, fontSize: 24, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
