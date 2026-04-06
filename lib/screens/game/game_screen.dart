import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/game_provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/match_service.dart';
import '../../utils/haptic_service.dart';
import '../../utils/app_theme.dart';
import '../../utils/score_converter.dart';
import '../../services/auto_scoring_service.dart';
import '../../widgets/auto_score_display.dart';
import '../../widgets/tv_scoreboard.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/app_navigator.dart';
import '../../widgets/rank_change_overlay.dart';
import '../../widgets/elo_change_overlay.dart';
import 'base_game_screen_state.dart';

class GameScreen extends StatefulWidget {
  final String matchId;
  final String opponentId;
  final String opponentUsername;
  final String? agoraAppId;
  final String? agoraToken;
  final String? agoraChannelName;

  const GameScreen({
    super.key,
    required this.matchId,
    required this.opponentId,
    required this.opponentUsername,
    this.agoraAppId,
    this.agoraToken,
    this.agoraChannelName,
  });

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends BaseGameScreenState<GameScreen> {
  String? _storedMatchId;
  final bool _didForfeit = false; // not final: set in disposeScreenSpecific via leaveMatch check

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

  @override
  Widget? buildExtraHeader(dynamic game, AuthProvider auth) => null;

  @override
  Widget buildAppBarTitle() => Row(children: [
    Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppTheme.error, shape: BoxShape.circle)),
    const SizedBox(width: 8),
    Text(AppLocalizations.of(context).liveMatch, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 2, color: Colors.white)),
  ]);

  @override
  void onScreenSpecificStateChange(dynamic game) {}

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
      agoraChannelName: widget.agoraChannelName,
    );
    gameStarted = game.gameStarted;
    gameEnded = game.gameEnded;
    if (widget.agoraAppId != null && widget.agoraAppId!.isNotEmpty) {
      updateLoadingMessage('Starting camera...');
      await initializeAgora(
        appId: widget.agoraAppId!,
        token: widget.agoraToken ?? '',
        channelName: widget.agoraChannelName ?? '',
      );
    }
    game.addListener(handleSharedStateChange);
    updateLoadingMessage('Loading AI model...');
    await loadAutoScoringPref();
    // Rejoin scenario: Agora credentials arrive later via game_state_sync.
    // Show loading spinner instead of the manual dartboard until the model loads.
    if (autoScoringEnabled && agoraEngine == null && !kIsWeb && AutoScoringService.isSupported) {
      setState(() => autoScoringLoading = true);
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
    if (!_didForfeit) leaveMatch();
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
    final forfeitData = game.pendingData;
    final winnerId = forfeitData?['winnerId'] as String?;
    final eloChange = forfeitData?['winnerEloChange'] as int? ?? 0;
    final isWinner = winnerId == auth.currentUser?.id;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: isWinner ? AppTheme.success : AppTheme.error,
            width: 2,
          ),
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
              isWinner ? AppLocalizations.of(context).victory.toUpperCase() : AppLocalizations.of(context).gameOver.toUpperCase(),
              style: AppTheme.titleLarge.copyWith(
                color: isWinner ? AppTheme.success : AppTheme.error,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isWinner
                  ? AppLocalizations.of(context).opponentLeftForfeit
                  : AppLocalizations.of(context).youLeftForfeited,
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
                  '${AppLocalizations.of(context).eloChange}: ${eloChange >= 0 ? '+' : ''}$eloChange',
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
        actions: [
          ElevatedButton(
            onPressed: () async {
              forfeitDialogShowing = false;
              final oldRank = auth.currentUser?.rank ?? 'unranked';
              final oldElo = auth.currentUser?.elo ?? 1200;
              Navigator.of(dialogCtx).pop();
              await auth.checkAuthStatus();
              if (!context.mounted) return;
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
            style: ElevatedButton.styleFrom(
              backgroundColor: isWinner ? AppTheme.success : AppTheme.primary,
            ),
            child: Text(AppLocalizations.of(context).continuePlaying),
          ),
        ],
      ),
    ).then((_) => forfeitDialogShowing = false);
  }

  @override
  Widget buildEndScreen(dynamic game, AuthProvider auth) {
    final didWin = game.winnerId == auth.currentUser?.id;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.surfaceGradient),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const Spacer(flex: 2),
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
                Text(
                  didWin ? AppLocalizations.of(context).victory.toUpperCase() : AppLocalizations.of(context).defeat.toUpperCase(),
                  style: AppTheme.displayLarge.copyWith(color: didWin ? AppTheme.success : AppTheme.error, fontSize: 48),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  didWin ? AppLocalizations.of(context).provenLegend : AppLocalizations.of(context).trainingPath,
                  style: AppTheme.bodyLarge,
                  textAlign: TextAlign.center,
                ),
                const Spacer(flex: 1),
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppTheme.surfaceLight.withValues(alpha: 0.5))),
                  child: Column(children: [
                    Text(AppLocalizations.of(context).matchResult, style: AppTheme.titleLarge.copyWith(color: AppTheme.primary, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(AppLocalizations.of(context).pleaseConfirmResult, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
                    const SizedBox(height: 24),
                    SizedBox(width: double.infinity, height: 56, child: ElevatedButton.icon(
                      onPressed: () { HapticService.mediumImpact(); _acceptMatchResult(game, auth); },
                      style: ElevatedButton.styleFrom(backgroundColor: AppTheme.success, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                      icon: const Icon(Icons.check_circle_outline),
                      label: Text(AppLocalizations.of(context).acceptResult, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1)),
                    )),
                    const SizedBox(height: 12),
                    SizedBox(width: double.infinity, height: 56, child: OutlinedButton.icon(
                      onPressed: () {
                        HapticService.lightImpact();
                        showReportDialog(
                          onSubmit: (reason) async {
                            if (game.matchId == null || auth.currentUser?.id == null) return;
                            final result = await MatchService.disputeMatchResult(game.matchId!, auth.currentUser!.id, reason);
                            final msg = result['message'] as String? ?? 'Dispute submitted';
                            if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: AppTheme.error, duration: const Duration(seconds: 2)));
                            Future.delayed(const Duration(seconds: 2), () { if (mounted) Navigator.of(context).pop(); });
                          },
                          onComplete: () {},
                        );
                      },
                      style: OutlinedButton.styleFrom(foregroundColor: AppTheme.error, side: BorderSide(color: AppTheme.error.withValues(alpha: 0.5), width: 2), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                      icon: const Icon(Icons.flag_outlined),
                      label: Text(AppLocalizations.of(context).reportPlayer, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1)),
                    )),
                  ]),
                ),
                const Spacer(flex: 2),
              ],
            ),
          ),
        ),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    if (isLoading) return buildLoadingScreen();

    try {
      final game = context.watch<GameProvider>();
      final auth = context.watch<AuthProvider>();
      
      if (game.matchId == null || !game.gameStarted) {
        return PopScope(canPop: false, onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          if (await onWillPop() && context.mounted) Navigator.of(context).pop();
        }, child: Scaffold(
          backgroundColor: AppTheme.background,
          appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0, iconTheme: const IconThemeData(color: Colors.white)),
          body: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const CircularProgressIndicator(color: AppTheme.primary),
            const SizedBox(height: 16),
            Text(AppLocalizations.of(context).initializingMatch, style: const TextStyle(color: AppTheme.textSecondary, letterSpacing: 2, fontWeight: FontWeight.bold)),
          ])),
        ));
      }
      if (game.gameEnded && game.pendingType != 'forfeit') return buildEndScreen(game, auth);

      final dartsThrown = game.dartsThrown;

      final safeTop = MediaQuery.of(context).padding.top;

      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop) return;
          final shouldPop = await onWillPop();
          if (shouldPop && context.mounted) {
            Navigator.of(context).pop();
          }
        },
        child: Scaffold(
          backgroundColor: AppTheme.background,
          body: Stack(
            children: [
              // Main content
              autoScoringLoading && (game.isMyTurn || game.pendingConfirmation)
                ? Container(
                    color: AppTheme.background,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(color: AppTheme.primary),
                          const SizedBox(height: 16),
                          Text(AppLocalizations.of(context).loadingAutoScoring, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
                        ],
                      ),
                    ),
                  )
                : (game.isMyTurn || game.pendingConfirmation)
                  ? AutoScoreGameView(
                      scoringService: autoScoringService!,
                      onConfirm: () => submitAutoScoredDarts(game),
                      onEndRoundEarly: () => submitAutoScoredDarts(game),
                      pendingConfirmation: game.pendingConfirmation,
                      myScore: game.myScore,
                      opponentScore: game.opponentScore,
                      opponentName: widget.opponentUsername,
                      myName: auth.currentUser?.username ?? 'You',
                      dartsThrown: dartsThrown,
                      agoraEngine: agoraEngine,
                      localCameraPreview: cameraFrameService?.controller != null && cameraFrameService!.controller!.value.isInitialized
                          ? CameraPreview(cameraFrameService!.controller!)
                          : null,
                      remoteUid: game.remoteUid,
                      isAudioMuted: isAudioMuted,
                      onToggleAudio: toggleAudio,
                      onSwitchCamera: switchCamera,
                      onZoomIn: zoomIn,
                      onZoomOut: zoomOut,
                      currentZoom: cameraZoom,
                      minZoom: cameraMinZoom,
                      maxZoom: cameraMaxZoom,
                      onEditDart: (index, dartScore) {
                        final (base, mul) = dartScoreToBackend(dartScore);
                        game.editDartThrow(index, base, mul);
                      },
                      onRemoveDart: (index) { autoScoringService?.removeDart(index); game.undoLastDart(); },
                      onToggleAi: autoScoringService!.modelLoaded ? toggleAiScoring : null,
                      aiEnabled: !aiManuallyDisabled,
                    )
                  // Opponent's turn
                  : Container(
                      color: AppTheme.background,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(height: safeTop),
                          if (game.opponentDisconnected)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              color: AppTheme.accent.withValues(alpha: 0.15),
                              child: Row(
                                children: [
                                  const Icon(Icons.wifi_off, color: AppTheme.accent, size: 18),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      '${AppLocalizations.of(context).opponentDisconnected} — ${AppLocalizations.of(context).timeLeftToReconnect.replaceAll('{time}', formatSeconds(game.disconnectGraceSeconds))}',
                                      style: const TextStyle(color: AppTheme.accent, fontSize: 13, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                            child: TvScoreboard(
                              myScore: game.myScore,
                              opponentScore: game.opponentScore,
                              myName: auth.currentUser?.username ?? 'You',
                              opponentName: widget.opponentUsername,
                              isMyTurn: false,
                              myAverage: game.myAveragePerRound,
                              opponentAverage: game.opponentAveragePerRound,
                            ),
                          ),
                          Expanded(
                            flex: 55,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                              child: buildOpponentTurnVideoLayout(game, channelId: widget.agoraChannelName ?? ''),
                            ),
                          ),
                          Expanded(
                            flex: 38,
                            child: Container(
                              decoration: const BoxDecoration(
                                color: AppTheme.surface,
                                borderRadius: BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24)),
                                boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, -4))],
                              ),
                              child: buildOpponentWaitingPanel(game),
                            ),
                          ),
                        ],
                      ),
                    ),

              // Floating back button
              Positioned(
                top: safeTop + 8,
                left: 12,
                child: GestureDetector(
                  onTap: () async {
                    final shouldLeave = await onWillPop();
                    if (shouldLeave && context.mounted) {
                      Navigator.of(context).pop();
                    }
                  },
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.arrow_back_ios_new, size: 16, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    } catch (e, stackTrace) {
      return Scaffold(
        appBar: AppBar(title: const Text('Error')),
        body: Center(
          child: Text('Error: $e\n$stackTrace'),
        ),
      );
    }
  }





}
