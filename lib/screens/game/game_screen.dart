import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import '../../providers/game_provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/match_service.dart';
import '../../utils/haptic_service.dart';
import '../../utils/app_theme.dart';
import '../../utils/score_converter.dart';
import '../../services/auto_scoring_service.dart';
import '../../widgets/auto_score_display.dart';
import '../../l10n/app_localizations.dart';
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
  String get leaveWarningText =>
      'If you leave now, you will forfeit the match and lose ELO points.';

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
    } catch (_) {}
  }
  





  void _acceptMatchResult(GameProvider game, AuthProvider auth) async {
    if (game.matchId == null || auth.currentUser?.id == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      messenger.showSnackBar(const SnackBar(content: Text('Accepting match result...'), duration: Duration(seconds: 1)));
      final result = await MatchService.acceptMatchResult(game.matchId!, auth.currentUser!.id);
      if (!mounted) return;
      await auth.checkAuthStatus();
      final message = result['message'] as String? ?? 'Match result accepted';
      messenger.showSnackBar(SnackBar(content: Text(message), backgroundColor: AppTheme.success, duration: const Duration(milliseconds: 500)));
      game.reset();
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.error, duration: const Duration(seconds: 3)));
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
                  ? 'Your opponent has left the game.\nYou win by forfeit!'
                  : 'You have left the game.\nMatch forfeited.',
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
                  'ELO: ${eloChange >= 0 ? '+' : ''}$eloChange',
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
              Navigator.of(dialogCtx).pop();
              await auth.checkAuthStatus();
              game.reset();
              if (context.mounted) Navigator.of(context).popUntil((route) => route.isFirst);
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
          Text(didWin ? AppLocalizations.of(context).victory.toUpperCase() : AppLocalizations.of(context).defeat.toUpperCase(), style: AppTheme.displayLarge.copyWith(color: didWin ? AppTheme.success : AppTheme.error, fontSize: 48)),
          const SizedBox(height: 16),
          Text(didWin ? AppLocalizations.of(context).provenLegend : AppLocalizations.of(context).trainingPath, style: AppTheme.bodyLarge, textAlign: TextAlign.center),
          const SizedBox(height: 48),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
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
        ]))),
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

      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop) return;
          final shouldPop = await onWillPop();
          if (shouldPop && context.mounted) {
            Navigator.of(context).pop();
          }
        },
        child: Container(
          color: AppTheme.surface,
          child: SafeArea(
            top: false,
            child: Scaffold(
              backgroundColor: AppTheme.background,
              appBar: AppBar(
                backgroundColor: AppTheme.surface,
            title: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: AppTheme.error,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                AppLocalizations.of(context).liveMatch,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 20),
            onPressed: () async {
              // Show warning dialog before leaving
              final shouldLeave = await onWillPop();
              if (shouldLeave && context.mounted) {
                Navigator.of(context).pop();
              }
            },
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: game.isMyTurn
                ? Row(
                    children: [
                      const Icon(Icons.sports_esports_outlined, size: 16, color: AppTheme.textSecondary),
                      const SizedBox(width: 4),
                      Text(
                        AppLocalizations.of(context).dartCounter.replaceAll('{current}', '${(dartsThrown + 1).clamp(1, 3)}'),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primary,
                        ),
                      ),
                    ],
                  )
                : Text(AppLocalizations.of(context).waiting, style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
            ),
          ],
        ),
        body: autoScoringEnabled && autoScoringLoading
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: AppTheme.primary),
                  const SizedBox(height: 16),
                  Text(AppLocalizations.of(context).loadingAutoScoring, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
                ],
              ),
            )
          : autoScoringEnabled && !aiManuallyDisabled && autoScoringService != null && autoScoringService!.modelLoaded && (game.isMyTurn || game.pendingConfirmation)
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
                // Undo all darts first to avoid negative scores on bust
                game.undoAllDarts();
                for (int i = 0; i < 3; i++) { autoScoringService?.clearDart(i); }
                // Re-throw only the edited dart
                game.editDartThrow(index, dartScore.segment == 0 && dartScore.ring != 'miss' ? 25 : dartScore.segment, dartScoreToMultiplier(dartScore));
              },
              onRemoveDart: (index) { autoScoringService?.removeDart(index); game.undoLastDart(); },
              onToggleAi: toggleAiScoring,
              aiEnabled: !aiManuallyDisabled,
            )
          : Container(
          color: AppTheme.background,
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Opponent disconnected banner
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
                              'Opponent disconnected — ${formatSeconds(game.disconnectGraceSeconds)} left to reconnect',
                              style: const TextStyle(
                                color: AppTheme.accent,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  // Video Area - Only show during opponent's turn
                  if (!game.isMyTurn)
                    Expanded(
                      flex: 62,
                      child: buildOpponentTurnVideoLayout(game, channelId: widget.agoraChannelName ?? '', showMyScore: false),
                    ),
                  // Score panel — inline during player's turn
                  if (game.isMyTurn)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final screenWidth = MediaQuery.of(context).size.width;
                          final showCamera = screenWidth >= 375 && agoraEngine != null && game.remoteUid != null;
                          return Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Flexible(
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: AppTheme.surfaceLight.withValues(alpha: 0.95),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: AppTheme.surfaceLight, width: 2),
                                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 2))],
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Row(children: [
                                        Text('${game.myScore}', style: TextStyle(color: game.myScore <= 170 ? AppTheme.success : AppTheme.primary, fontSize: 24, fontWeight: FontWeight.bold)),
                                        if (game.myScore <= 170 && game.myScore >= 2) ...[
                                          const SizedBox(width: 8),
                                          Text(checkoutHint(game.myScore) ?? '', style: const TextStyle(color: AppTheme.success, fontSize: 11, fontWeight: FontWeight.w500)),
                                        ],
                                      ]),
                                      const SizedBox(height: 8),
                                      Row(children: [
                                        ...List.generate(3, (index) {
                                          final throws = game.currentRoundThrows;
                                          final hasThrow = index < throws.length;
                                          final isNext = index == throws.length;
                                          final isEditing = editingDartIndex == index;
                                          return GestureDetector(
                                            onTap: hasThrow ? () { HapticService.lightImpact(); setState(() { editingDartIndex = isEditing ? null : index; }); } : null,
                                            child: Container(
                                              width: 44, height: 44, margin: const EdgeInsets.only(right: 8),
                                              decoration: BoxDecoration(
                                                color: isEditing ? AppTheme.error.withValues(alpha: 0.3) : hasThrow ? AppTheme.primary.withValues(alpha: 0.2) : AppTheme.background,
                                                borderRadius: BorderRadius.circular(8),
                                                border: Border.all(color: isEditing ? AppTheme.error : hasThrow ? AppTheme.primary : isNext ? Colors.white24 : Colors.transparent, width: isEditing ? 3 : (hasThrow || isNext ? 2 : 1)),
                                              ),
                                              child: Center(child: hasThrow
                                                ? Text(throws[index], style: TextStyle(color: isEditing ? AppTheme.error : AppTheme.primary, fontSize: 14, fontWeight: FontWeight.bold))
                                                : Icon(Icons.adjust, color: isNext ? Colors.white54 : Colors.white10, size: 16)),
                                            ),
                                          );
                                        }),
                                        Material(
                                          color: Colors.transparent,
                                          child: InkWell(
                                            onTap: () {
                                              HapticService.mediumImpact();
                                              final g = context.read<GameProvider>();
                                              if (editingDartIndex != null && editingDartIndex! < g.currentRoundThrows.length) {
                                                g.editDartThrow(editingDartIndex!, 0, ScoreMultiplier.single);
                                                setState(() { editingDartIndex = null; });
                                              } else {
                                                g.throwDart(baseScore: 0, multiplier: ScoreMultiplier.single);
                                              }
                                            },
                                            borderRadius: BorderRadius.circular(8),
                                            child: Container(
                                              width: 44, height: 44,
                                              decoration: BoxDecoration(color: AppTheme.background, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppTheme.surfaceLight, width: 2)),
                                              child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                                Icon(Icons.close, color: Colors.white70, size: 16),
                                                Text('MISS', style: TextStyle(color: Colors.white70, fontSize: 7, fontWeight: FontWeight.bold)),
                                              ]),
                                            ),
                                          ),
                                        ),
                                      ]),
                                      if (editingDartIndex != null) ...[
                                        const SizedBox(height: 4),
                                        Row(children: [
                                          const Icon(Icons.edit, color: AppTheme.error, size: 12),
                                          const SizedBox(width: 4),
                                          Text('Editing Dart ${(editingDartIndex ?? 0) + 1}', style: const TextStyle(color: AppTheme.error, fontSize: 11, fontWeight: FontWeight.w600)),
                                          const SizedBox(width: 8),
                                          GestureDetector(
                                            onTap: () => setState(() => editingDartIndex = null),
                                            child: const Text('cancel', style: TextStyle(color: AppTheme.textSecondary, fontSize: 11, decoration: TextDecoration.underline)),
                                          ),
                                        ]),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (showCamera)
                                ConstrainedBox(
                                  constraints: const BoxConstraints(maxHeight: 200, maxWidth: 120),
                                  child: Container(
                                    width: 120,
                                    decoration: BoxDecoration(
                                      color: AppTheme.surfaceLight.withValues(alpha: 0.95),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: AppTheme.surfaceLight, width: 2),
                                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 2))],
                                    ),
                                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                                      Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                        child: Text(widget.opponentUsername.toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5), overflow: TextOverflow.ellipsis),
                                      ),
                                      Container(
                                        width: double.infinity, height: 80,
                                        decoration: const BoxDecoration(color: AppTheme.surface),
                                        child: AgoraVideoView(controller: VideoViewController.remote(rtcEngine: agoraEngine!, canvas: VideoCanvas(uid: game.remoteUid!, renderMode: RenderModeType.renderModeHidden), connection: RtcConnection(channelId: widget.agoraChannelName ?? ''))),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                                        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                                          const Text('SCORE', style: TextStyle(color: AppTheme.textSecondary, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                                          Text('${game.opponentScore}', style: const TextStyle(color: AppTheme.primary, fontSize: 18, fontWeight: FontWeight.bold)),
                                        ]),
                                      ),
                                    ]),
                                  ),
                                )
                              else
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: AppTheme.surfaceLight.withValues(alpha: 0.95),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: AppTheme.surfaceLight, width: 2),
                                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 2))],
                                  ),
                                  child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(widget.opponentUsername.toUpperCase(), style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5), overflow: TextOverflow.ellipsis),
                                    const SizedBox(height: 4),
                                    Text('${game.opponentScore}', style: const TextStyle(color: AppTheme.primary, fontSize: 20, fontWeight: FontWeight.bold)),
                                  ]),
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                  // Controls Area
                  Expanded(
                    flex: game.isMyTurn ? 6 : 38,
                    child: Container(
                      decoration: const BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24)),
                        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, -4))],
                      ),
                      child: buildScoreInputPanel(game),
                    ),
                  ),
                ],
              ),

            // Local camera preview (during opponent's turn — same size/position as camera widget during my turn)
            if (!game.isMyTurn && agoraEngine != null)
              Positioned(
                top: 16,
                right: 16,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 200, maxWidth: 120),
                  child: Container(
                    width: 120,
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceLight.withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.surfaceLight, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('YOU', style: TextStyle(color: AppTheme.textSecondary, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                              Text('${game.myScore}', style: const TextStyle(color: AppTheme.success, fontSize: 16, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                        Container(
                          width: double.infinity,
                          height: 80,
                          decoration: const BoxDecoration(color: AppTheme.surface),
                          child: AgoraVideoView(
                            controller: VideoViewController(
                              rtcEngine: agoraEngine!,
                              canvas: const VideoCanvas(uid: 0),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              GestureDetector(
                                onTap: zoomOut,
                                child: Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.4),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                                  ),
                                  child: const Icon(Icons.remove, color: Colors.white, size: 16),
                                ),
                              ),
                              Text(
                                '${cameraZoom.toStringAsFixed(1)}x',
                                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                              GestureDetector(
                                onTap: zoomIn,
                                child: Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.4),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                                  ),
                                  child: const Icon(Icons.add, color: Colors.white, size: 16),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // AI toggle button (floating, during my turn)
            if (game.isMyTurn && autoScoringEnabled && autoScoringService != null && autoScoringService!.modelLoaded)
              Positioned(
                bottom: 80 + MediaQuery.of(context).viewPadding.bottom,
                right: 12,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: toggleAiScoring,
                    borderRadius: BorderRadius.circular(28),
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: aiManuallyDisabled ? AppTheme.surface : AppTheme.success.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: aiManuallyDisabled ? AppTheme.textSecondary : AppTheme.success,
                          width: 2,
                        ),
                      ),
                      child: Icon(
                        aiManuallyDisabled ? Icons.smart_toy_outlined : Icons.smart_toy,
                        color: aiManuallyDisabled ? AppTheme.textSecondary : AppTheme.success,
                        size: 22,
                      ),
                    ),
                  ),
                ),
              ),

            ],
          ),
          ),
        ),
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
