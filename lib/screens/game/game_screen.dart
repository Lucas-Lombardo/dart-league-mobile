import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import '../../providers/game_provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/match_service.dart';
import '../../utils/haptic_service.dart';
import '../../utils/app_theme.dart';
import '../../widgets/auto_score_display.dart';
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
    const Text('LIVE MATCH', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 2, color: Colors.white)),
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
      await initializeAgora(
        appId: widget.agoraAppId!,
        token: widget.agoraToken ?? '',
        channelName: widget.agoraChannelName ?? '',
      );
    }
    game.addListener(handleSharedStateChange);
    await loadAutoScoringPref();
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
      if (mounted) Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
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
    final parentNav = Navigator.of(context);
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
              isWinner ? 'VICTORY!' : 'GAME OVER',
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
          Text(didWin ? 'VICTORY!' : 'DEFEAT', style: AppTheme.displayLarge.copyWith(color: didWin ? AppTheme.success : AppTheme.error, fontSize: 48)),
          const SizedBox(height: 16),
          Text(didWin ? 'You have proven yourself a legend.' : 'Training is the path to greatness.', style: AppTheme.bodyLarge, textAlign: TextAlign.center),
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
                onPressed: () { HapticService.mediumImpact(); _acceptMatchResult(game, auth); },
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
                      if (game.matchId == null || auth.currentUser?.id == null) return;
                      final result = await MatchService.disputeMatchResult(game.matchId!, auth.currentUser!.id, reason);
                      final msg = result['message'] as String? ?? 'Dispute submitted';
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: AppTheme.error, duration: const Duration(seconds: 2)));
                      Future.delayed(const Duration(seconds: 2), () { if (mounted) Navigator.pushNamedAndRemoveUntil(context, '/home', (r) => false); });
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
      final game = context.watch<GameProvider>();
      final auth = context.watch<AuthProvider>();
      
      if (game.matchId == null || !game.gameStarted) {
        return PopScope(canPop: false, onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          if (await onWillPop() && context.mounted) Navigator.of(context).pop();
        }, child: Scaffold(
          backgroundColor: AppTheme.background,
          appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0, iconTheme: const IconThemeData(color: Colors.white)),
          body: const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            CircularProgressIndicator(color: AppTheme.primary),
            SizedBox(height: 16),
            Text('INITIALIZING MATCH...', style: TextStyle(color: AppTheme.textSecondary, letterSpacing: 2, fontWeight: FontWeight.bold)),
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
              const Text(
                'LIVE MATCH',
                style: TextStyle(
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
              child: Row(
                children: [
                  const Icon(Icons.sports_esports_outlined, size: 16, color: AppTheme.textSecondary),
                  const SizedBox(width: 4),
                  Text(
                    'Dart ${dartsThrown + 1}/3',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        body: autoScoringEnabled && autoScoringLoading
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: AppTheme.primary),
                  SizedBox(height: 16),
                  Text('Loading auto-scoring...', style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
                ],
              ),
            )
          : autoScoringEnabled && autoScoringService != null && autoScoringService!.modelLoaded && game.isMyTurn
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
            )
          : Container(
          color: AppTheme.background,
          child: Stack(
            children: [
              Column(
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
                    Container(
                      height: 280,
                      padding: const EdgeInsets.all(12),
                      child: buildOpponentTurnVideoLayout(game),
                    ),
            
            // Mic and Camera controls
            if (agoraEngine != null && !game.isMyTurn)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Mic toggle
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: toggleAudio,
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTheme.surface,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isAudioMuted ? AppTheme.error : AppTheme.primary,
                              width: 2,
                            ),
                          ),
                          child: Icon(
                            isAudioMuted ? Icons.mic_off : Icons.mic,
                            color: isAudioMuted ? AppTheme.error : AppTheme.primary,
                            size: 24,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Camera switch
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: switchCamera,
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTheme.surface,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: AppTheme.primary,
                              width: 2,
                            ),
                          ),
                          child: const Icon(
                            Icons.cameraswitch,
                            color: AppTheme.primary,
                            size: 24,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Controls Area
            Expanded(
              flex: 6,
              child: Container(
                decoration: const BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 10,
                      offset: Offset(0, -4),
                    ),
                  ],
                ),
                child: buildScoreInputPanel(game),
              ),
            ),
              ],
            ),
            
            // Top bar with YOUR SCORE and Camera (only during user's turn)
            if (game.isMyTurn)
              Positioned(
                top: 16,
                left: 16,
                right: 16,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final screenWidth = MediaQuery.of(context).size.width;
                    final showCamera = screenWidth >= 375 && agoraEngine != null && game.remoteUid != null;
                    
                    return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Left: YOUR SCORE with global score, dart indicators, and MISS button
                    Flexible(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceLight.withValues(alpha: 0.95),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppTheme.surfaceLight,
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // YOUR SCORE with global score
                          Row(
                            children: [
                              const Text(
                                'YOUR SCORE: ',
                                style: TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              Text(
                                '${game.myScore}',
                                style: TextStyle(
                                  color: game.myScore <= 170 ? AppTheme.success : AppTheme.primary,
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          // Dart indicators and MISS button
                          Row(
                            children: [
                              ...List.generate(3, (index) {
                                final throws = game.currentRoundThrows;
                                final hasThrow = index < throws.length;
                                final isNext = index == throws.length;
                                final isEditing = editingDartIndex == index;
                                
                                return GestureDetector(
                                  onTap: hasThrow ? () {
                                    HapticService.lightImpact();
                                    setState(() {
                                      editingDartIndex = isEditing ? null : index;
                                    });
                                  } : null,
                                  child: Container(
                                    width: 40,
                                    height: 40,
                                    margin: const EdgeInsets.only(right: 8),
                                    decoration: BoxDecoration(
                                      color: isEditing
                                          ? AppTheme.error.withValues(alpha: 0.3)
                                          : hasThrow 
                                              ? AppTheme.primary.withValues(alpha: 0.2)
                                              : AppTheme.background,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: isEditing
                                            ? AppTheme.error
                                            : hasThrow 
                                                ? AppTheme.primary 
                                                : isNext 
                                                    ? Colors.white24 
                                                    : Colors.transparent,
                                        width: isEditing ? 3 : (hasThrow || isNext ? 2 : 1),
                                      ),
                                    ),
                                    child: Center(
                                      child: hasThrow 
                                          ? Text(
                                              throws[index],
                                              style: TextStyle(
                                                color: isEditing ? AppTheme.error : AppTheme.primary,
                                                fontSize: 14,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            )
                                          : Icon(
                                              Icons.adjust,
                                              color: isNext ? Colors.white54 : Colors.white10,
                                              size: 16,
                                            ),
                                    ),
                                  ),
                                );
                              }),
                              // MISS button
                              Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () {
                                    HapticService.mediumImpact();
                                    final game = context.read<GameProvider>();
                                    if (editingDartIndex != null && editingDartIndex! < game.currentRoundThrows.length) {
                                      game.editDartThrow(editingDartIndex!, 0, ScoreMultiplier.single);
                                      setState(() {
                                        editingDartIndex = null;
                                      });
                                    } else {
                                      game.throwDart(baseScore: 0, multiplier: ScoreMultiplier.single);
                                    }
                                  },
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    width: 50,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: AppTheme.background,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: AppTheme.surfaceLight,
                                        width: 2,
                                      ),
                                    ),
                                    child: const Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.close, color: Colors.white70, size: 16),
                                        Text(
                                          'MISS',
                                          style: TextStyle(
                                            color: Colors.white70,
                                            fontSize: 7,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    ),
                    
                    const SizedBox(width: 8),
                    // Right: Camera widget (if screen is large enough) or simple score card (if screen is small)
                    if (showCamera)
                      ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxHeight: 200,
                          maxWidth: 120,
                        ),
                        child: Container(
                          width: 120,
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceLight.withValues(alpha: 0.95),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppTheme.surfaceLight,
                              width: 2,
                            ),
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
                            // Opponent name
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              child: Text(
                                widget.opponentUsername.toUpperCase(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            // Camera video feed
                            Container(
                              width: double.infinity,
                              height: 80,
                              decoration: const BoxDecoration(
                                color: AppTheme.surface,
                              ),
                              child: AgoraVideoView(
                                controller: VideoViewController.remote(
                                  rtcEngine: agoraEngine!,
                                  canvas: VideoCanvas(uid: game.remoteUid!),
                                  connection: RtcConnection(channelId: ''),
                                ),
                              ),
                            ),
                            // Score at bottom
                            Padding(
                              padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'SCORE',
                                    style: TextStyle(
                                      color: AppTheme.textSecondary,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  Text(
                                    '${game.opponentScore}',
                                    style: const TextStyle(
                                      color: AppTheme.primary,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      )
                    else
                      // Show simple opponent score card on small screens
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceLight.withValues(alpha: 0.95),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppTheme.surfaceLight,
                            width: 2,
                          ),
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
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.opponentUsername.toUpperCase(),
                              style: const TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Text(
                                  'SCORE: ',
                                  style: TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 8,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  '${game.opponentScore}',
                                  style: const TextStyle(
                                    color: AppTheme.primary,
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                  ],
                );
                  },
                ),
              ),
            
            // Edit mode indicator (render on top of everything)
            if (editingDartIndex != null && game.isMyTurn)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Material(
                  elevation: 100,
                  color: AppTheme.error,
                  child: SafeArea(
                    bottom: false,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.edit, color: Colors.white, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                'Editing Dart ${(editingDartIndex ?? 0) + 1}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                          TextButton(
                            onPressed: () {
                              setState(() {
                                editingDartIndex = null;
                              });
                            },
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              minimumSize: const Size(60, 32),
                              backgroundColor: Colors.white.withValues(alpha: 0.2),
                            ),
                            child: const Text(
                              'CANCEL',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
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
