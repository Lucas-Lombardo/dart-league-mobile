import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:provider/provider.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import '../../providers/tournament_game_provider.dart';
import '../../providers/game_provider.dart' show ScoreMultiplier;
import '../../providers/auth_provider.dart';
import '../../services/agora_service.dart';
import '../../services/socket_service.dart';
import '../../services/match_service.dart';
import '../../utils/haptic_service.dart';
import '../../utils/app_theme.dart';
import '../../widgets/interactive_dartboard.dart';
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

class _TournamentGameScreenState extends State<TournamentGameScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _scoreAnimationController;
  int? _editingDartIndex;

  String? _storedPlayerId;
  bool _gameStarted = false;
  bool _gameEnded = false;
  bool _navigatingToResult = false;
  bool _resultAccepted = false;

  // Agora video
  RtcEngine? _agoraEngine;
  bool _isAudioMuted = true;
  bool _permissionsGranted = false;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();

    _scoreAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        final game = context.read<TournamentGameProvider>();
        final auth = context.read<AuthProvider>();

        if (auth.currentUser != null) {
          _storedPlayerId = auth.currentUser!.id;

          if (game.agoraAppId != null) {
            _initializeAgora();
          }

          game.addListener(_handleStateChange);

          // Sync initial state — game_started may have already fired
          if (game.gameStarted != _gameStarted || game.gameEnded != _gameEnded) {
            setState(() {
              _gameStarted = game.gameStarted;
              _gameEnded = game.gameEnded;
            });
          }
        }
      } catch (_) {}
    });
  }

  void _handleStateChange() {
    if (!mounted) return;

    try {
      final game = context.read<TournamentGameProvider>();
      _gameStarted = game.gameStarted;
      _gameEnded = game.gameEnded;

      // Handle pending win/bust dialogs
      if (game.pendingConfirmation && game.pendingType != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && context.mounted) {
            if (game.pendingType == 'win') {
              _showPendingWinDialog();
            } else if (game.pendingType == 'bust') {
              _showPendingBustDialog();
            }
          }
        });
      }

      // Reset flags when a new leg starts
      if (game.tournamentState == TournamentGameState.playing && !game.gameEnded) {
        _resultAccepted = false;
        _navigatingToResult = false;
      }

      // Handle Agora reconnection
      if (game.needsAgoraReconnect) {
        game.clearAgoraReconnectFlag();
        _reconnectAgora(game);
      }

      // Handle forfeit
      if (game.gameEnded && game.pendingType == 'forfeit') {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && context.mounted) {
            _showForfeitDialog();
          }
        });
      }

      // Handle tournament state transitions — only after user accepts result
      if (_resultAccepted) {
        if (game.tournamentState == TournamentGameState.legEnded && !_navigatingToResult) {
          _navigatingToResult = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _navigateToLegResult(game);
          });
        }

        if (game.tournamentState == TournamentGameState.seriesEnded && !_navigatingToResult) {
          _navigatingToResult = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _navigateToMatchResult(game);
          });
        }
      }
    } catch (_) {}
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
          player1LegsWon: game.player1LegsWon,
          player2LegsWon: game.player2LegsWon,
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
    // Clean up agora before navigating
    if (_agoraEngine != null) {
      AgoraService.leaveChannel(_agoraEngine!);
      AgoraService.dispose();
      _agoraEngine = null;
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => TournamentMatchResultScreen(
          tournamentMatchId: widget.tournamentMatchId,
          tournamentId: widget.tournamentId,
          tournamentName: widget.tournamentName,
          roundName: widget.roundName,
          opponentUsername: widget.opponentUsername,
          seriesWinnerId: game.seriesWinnerId,
          player1LegsWon: game.player1LegsWon,
          player2LegsWon: game.player2LegsWon,
          bestOf: widget.bestOf,
        ),
      ),
    );
  }

  Future<void> _initializeAgora() async {
    final game = context.read<TournamentGameProvider>();
    _permissionsGranted = await AgoraService.requestPermissions();
    if (!_permissionsGranted) return;

    try {
      _agoraEngine = await AgoraService.initializeEngine(game.agoraAppId!);
      await AgoraService.setBackCamera(_agoraEngine!);

      _agoraEngine!.registerEventHandler(
        RtcEngineEventHandler(
          onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
            if (!mounted) return;
            context.read<TournamentGameProvider>().setLocalUserJoined(true);
          },
          onUserJoined: (RtcConnection connection, int remoteUid, int elapsed) {
            if (!mounted) return;
            context.read<TournamentGameProvider>().setRemoteUser(remoteUid);
          },
          onUserOffline: (RtcConnection connection, int remoteUid, UserOfflineReasonType reason) {
            if (!mounted) return;
            context.read<TournamentGameProvider>().setRemoteUser(null);
          },
        ),
      );

      if (game.agoraToken != null && game.agoraChannelName != null) {
        await AgoraService.joinChannel(
          engine: _agoraEngine!,
          token: game.agoraToken!,
          channelName: game.agoraChannelName!,
          uid: 0,
        );
      }

      await _agoraEngine!.muteLocalAudioStream(true);
    } catch (_) {}
  }

  Future<void> _reconnectAgora(TournamentGameProvider game) async {
    final appId = game.agoraAppId;
    final token = game.agoraToken;
    final channelName = game.agoraChannelName;
    if (appId == null || token == null || channelName == null) return;

    try {
      if (_agoraEngine != null) {
        _agoraEngine = null;
        await AgoraService.dispose();
      }
      if (!_permissionsGranted) {
        _permissionsGranted = await AgoraService.requestPermissions();
        if (!_permissionsGranted) return;
      }
      _agoraEngine = await AgoraService.initializeEngine(appId);
      await AgoraService.setBackCamera(_agoraEngine!);
      _agoraEngine!.registerEventHandler(
        RtcEngineEventHandler(
          onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
            if (!mounted) return;
            context.read<TournamentGameProvider>().setLocalUserJoined(true);
          },
          onUserJoined: (RtcConnection connection, int remoteUid, int elapsed) {
            if (!mounted) return;
            context.read<TournamentGameProvider>().setRemoteUser(remoteUid);
          },
          onUserOffline: (RtcConnection connection, int remoteUid, UserOfflineReasonType reason) {
            if (!mounted) return;
            context.read<TournamentGameProvider>().setRemoteUser(null);
          },
        ),
      );
      await AgoraService.joinChannel(
        engine: _agoraEngine!,
        token: token,
        channelName: channelName,
        uid: 0,
      );
      await _agoraEngine!.muteLocalAudioStream(true);
      _isAudioMuted = true;
    } catch (_) {}
  }

  Future<void> _toggleAudio() async {
    if (_agoraEngine == null) return;
    setState(() => _isAudioMuted = !_isAudioMuted);
    await _agoraEngine!.muteLocalAudioStream(_isAudioMuted);
  }

  Future<void> _switchCamera() async {
    if (_agoraEngine == null) return;
    await AgoraService.switchCamera(_agoraEngine!);
  }

  void _leaveMatch() {
    try {
      final game = context.read<TournamentGameProvider>();
      final matchId = game.currentGameMatchId;
      if (matchId != null && _storedPlayerId != null && _gameStarted && !_gameEnded) {
        SocketService.emit('leave_match', {
          'matchId': matchId,
          'playerId': _storedPlayerId,
        });
      }
    } catch (_) {}
  }

  Future<bool> _onWillPop() async {
    final game = Provider.of<TournamentGameProvider>(context, listen: false);
    if (!game.gameStarted || game.gameEnded) return true;

    final shouldLeave = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppTheme.error, width: 2),
        ),
        title: Row(
          children: [
            const Icon(Icons.warning, color: AppTheme.error, size: 32),
            const SizedBox(width: 12),
            Text(
              'Leave Match?',
              style: AppTheme.titleLarge.copyWith(
                color: AppTheme.error,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Text(
          'If you leave now, you will forfeit the tournament match and be eliminated.',
          style: AppTheme.bodyLarge.copyWith(fontSize: 16),
          textAlign: TextAlign.center,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Stay in Match'),
          ),
          ElevatedButton(
            onPressed: () {
              _leaveMatch();
              Navigator.pop(dialogContext, true);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            child: const Text('Leave & Forfeit'),
          ),
        ],
      ),
    );
    return shouldLeave ?? false;
  }

  void _showPendingWinDialog() {
    final game = context.read<TournamentGameProvider>();
    final pendingData = game.pendingData;
    final finalDart = pendingData?['finalDart'];
    final notation = finalDart?['notation'] ?? 'Unknown';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppTheme.success, width: 2),
        ),
        title: Row(
          children: [
            const Icon(Icons.emoji_events, color: AppTheme.success, size: 32),
            const SizedBox(width: 12),
            Text(
              'CHECKOUT!',
              style: AppTheme.titleLarge.copyWith(
                color: AppTheme.success,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'You hit $notation to finish!',
              style: AppTheme.bodyLarge.copyWith(fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Is this correct?',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              game.undoLastDart();
            },
            child: const Text('Edit Darts'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              game.confirmWin();
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.success),
            child: const Text('Confirm Win'),
          ),
        ],
      ),
    );
  }

  void _showPendingBustDialog() {
    final game = context.read<TournamentGameProvider>();
    final reason = game.pendingReason ?? 'unknown';
    String reasonText;
    switch (reason) {
      case 'score_below_zero':
        reasonText = 'Score went below zero';
        break;
      case 'must_finish_double':
        reasonText = 'Must finish on a double';
        break;
      case 'score_one_remaining':
        reasonText = 'Cannot finish from 1';
        break;
      default:
        reasonText = 'Invalid throw';
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppTheme.error, width: 2),
        ),
        title: Row(
          children: [
            const Icon(Icons.warning, color: AppTheme.error, size: 32),
            const SizedBox(width: 12),
            Text(
              'BUST!',
              style: AppTheme.titleLarge.copyWith(
                color: AppTheme.error,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(reasonText, style: AppTheme.bodyLarge.copyWith(fontSize: 16), textAlign: TextAlign.center),
            const SizedBox(height: 8),
            const Text('Confirm to pass turn or edit if incorrect', style: TextStyle(color: AppTheme.textSecondary), textAlign: TextAlign.center),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () { Navigator.pop(context); game.undoLastDart(); },
            child: const Text('Edit Darts'),
          ),
          ElevatedButton(
            onPressed: () { Navigator.pop(context); game.confirmBust(); },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            child: const Text('Confirm Bust'),
          ),
        ],
      ),
    );
  }

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

    // Trigger state change handler to process any pending tournament navigation
    _handleStateChange();
  }

  void _showTournamentReportDialog() {
    String? selectedReason;
    final reasons = [
      'Cheating',
      'Unsportsmanlike conduct',
      'Incorrect score',
      'Connection issues',
      'Other',
    ];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: AppTheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: AppTheme.error, width: 2),
          ),
          title: Row(
            children: [
              const Icon(Icons.flag, color: AppTheme.error),
              const SizedBox(width: 12),
              Text(
                'Report Player',
                style: AppTheme.titleLarge.copyWith(
                  color: AppTheme.error,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Select a reason for reporting:',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
              ),
              const SizedBox(height: 16),
              ...reasons.map((reason) => InkWell(
                onTap: () {
                  setState(() {
                    selectedReason = reason;
                  });
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Icon(
                        selectedReason == reason
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        color: selectedReason == reason
                            ? AppTheme.error
                            : AppTheme.textSecondary,
                      ),
                      const SizedBox(width: 12),
                      Text(reason, style: const TextStyle(color: Colors.white)),
                    ],
                  ),
                ),
              )),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('CANCEL', style: TextStyle(color: AppTheme.textSecondary)),
            ),
            ElevatedButton(
              onPressed: selectedReason == null
                  ? null
                  : () {
                      HapticService.mediumImpact();
                      Navigator.of(context).pop();
                      _submitTournamentReport(selectedReason!);
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.error,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('SUBMIT REPORT', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  void _submitTournamentReport(String reason) async {
    final game = context.read<TournamentGameProvider>();
    final auth = context.read<AuthProvider>();
    final messenger = ScaffoldMessenger.of(context);

    if (game.currentGameMatchId == null || auth.currentUser?.id == null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Unable to submit report: Missing data'),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }

    try {
      final result = await MatchService.disputeMatchResult(
        game.currentGameMatchId!,
        auth.currentUser!.id,
        reason,
      );

      if (!mounted) return;

      final message = result['message'] as String? ?? 'Dispute submitted successfully';
      messenger.showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: AppTheme.error,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Error submitting dispute: $e'),
          backgroundColor: AppTheme.error,
          duration: const Duration(seconds: 3),
        ),
      );
    }

    // After reporting, still accept and proceed with tournament flow
    if (mounted) {
      setState(() {
        _resultAccepted = true;
      });
      _handleStateChange();
    }
  }

  void _showForfeitDialog() {
    final game = context.read<TournamentGameProvider>();
    final auth = context.read<AuthProvider>();
    final winnerId = game.pendingData?['winnerId'] as String?;
    final isWinner = winnerId == auth.currentUser?.id;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
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
              Navigator.pop(context);
              game.reset();
              Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: isWinner ? AppTheme.success : AppTheme.primary,
            ),
            child: const Text('Return to Home'),
          ),
        ],
      ),
    );
  }

  String _formatSeconds(int totalSeconds) {
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _scoreAnimationController.dispose();
    WakelockPlus.disable();
    _leaveMatch();
    try {
      final game = context.read<TournamentGameProvider>();
      game.removeListener(_handleStateChange);
    } catch (_) {}
    if (_agoraEngine != null) {
      AgoraService.leaveChannel(_agoraEngine!);
      AgoraService.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    try {
      final game = context.watch<TournamentGameProvider>();
      final auth = context.watch<AuthProvider>();

      if (!game.gameStarted) {
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) async {
            if (didPop) return;
            final shouldPop = await _onWillPop();
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

      // Show accept/report screen when leg ends (before tournament navigation)
      if (game.gameEnded && !_resultAccepted && game.pendingType != 'forfeit') {
        final winnerId = game.winnerId;
        final currentUserId = auth.currentUser?.id;
        final didWin = winnerId == currentUserId;

        return Scaffold(
          body: Container(
            decoration: const BoxDecoration(
              gradient: AppTheme.surfaceGradient,
            ),
            child: SafeArea(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        color: didWin
                            ? AppTheme.success.withValues(alpha: 0.1)
                            : AppTheme.error.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: didWin ? AppTheme.success : AppTheme.error,
                          width: 4,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: (didWin ? AppTheme.success : AppTheme.error).withValues(alpha: 0.4),
                            blurRadius: 40,
                            spreadRadius: 10,
                          ),
                        ],
                      ),
                      child: Icon(
                        didWin ? Icons.emoji_events : Icons.sentiment_dissatisfied,
                        color: didWin ? AppTheme.success : AppTheme.error,
                        size: 80,
                      ),
                    ),
                    const SizedBox(height: 32),
                    Text(
                      didWin ? 'LEG WON!' : 'LEG LOST',
                      style: AppTheme.displayLarge.copyWith(
                        color: didWin ? AppTheme.success : AppTheme.error,
                        fontSize: 48,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      didWin
                          ? 'Well played! Confirm the result to continue.'
                          : 'Better luck next leg. Confirm the result to continue.',
                      style: AppTheme.bodyLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 48),

                    // Match Result Survey
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 24),
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppTheme.surfaceLight.withValues(alpha: 0.5)),
                      ),
                      child: Column(
                        children: [
                          Text(
                            'Match Result',
                            style: AppTheme.titleLarge.copyWith(
                              color: AppTheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Please confirm the match result',
                            style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
                          ),
                          const SizedBox(height: 24),

                          // Accept Result Button
                          SizedBox(
                            width: double.infinity,
                            height: 56,
                            child: ElevatedButton.icon(
                              onPressed: () {
                                HapticService.mediumImpact();
                                _acceptTournamentResult();
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.success,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                              icon: const Icon(Icons.check_circle_outline),
                              label: const Text(
                                'ACCEPT RESULT',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1),
                              ),
                            ),
                          ),

                          const SizedBox(height: 12),

                          // Report Player Button
                          SizedBox(
                            width: double.infinity,
                            height: 56,
                            child: OutlinedButton.icon(
                              onPressed: () {
                                HapticService.lightImpact();
                                _showTournamentReportDialog();
                              },
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppTheme.error,
                                side: BorderSide(color: AppTheme.error.withValues(alpha: 0.5), width: 2),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                              icon: const Icon(Icons.flag_outlined),
                              label: const Text(
                                'REPORT PLAYER',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1),
                              ),
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
        );
      }

      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop) return;
          final shouldPop = await _onWillPop();
          if (shouldPop && context.mounted) Navigator.of(context).pop();
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
                    Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppTheme.error, shape: BoxShape.circle)),
                    const SizedBox(width: 8),
                    const Text('TOURNAMENT', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 2, color: Colors.white)),
                  ],
                ),
                centerTitle: true,
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                  onPressed: () async {
                    final shouldLeave = await _onWillPop();
                    if (shouldLeave && context.mounted) Navigator.of(context).pop();
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
              body: Container(
                color: AppTheme.background,
                child: Stack(
                  children: [
                    Column(
                      children: [
                        // Series scoreboard
                        _buildSeriesScoreboard(game, auth),

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
                                    'Opponent disconnected — ${_formatSeconds(game.disconnectGraceSeconds)} left',
                                    style: const TextStyle(color: AppTheme.accent, fontSize: 13, fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ),
                          ),

                        // Video area during opponent's turn
                        if (!game.isMyTurn)
                          Container(
                            height: 240,
                            padding: const EdgeInsets.all(12),
                            child: _buildOpponentTurnVideoLayout(game),
                          ),

                        // Mic/Camera controls during opponent turn
                        if (_agoraEngine != null && !game.isMyTurn)
                          _buildMediaControls(),

                        // Controls area
                        Expanded(
                          flex: 6,
                          child: Container(
                            decoration: const BoxDecoration(
                              color: AppTheme.surface,
                              borderRadius: BorderRadius.only(
                                topLeft: Radius.circular(24),
                                topRight: Radius.circular(24),
                              ),
                              boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, -4))],
                            ),
                            child: _buildScoreInput(game),
                          ),
                        ),
                      ],
                    ),

                    // Top bar with score + camera during my turn
                    if (game.isMyTurn)
                      Positioned(
                        top: 8,
                        left: 12,
                        right: 12,
                        child: _buildMyTurnOverlay(game),
                      ),

                    // Edit mode indicator
                    if (_editingDartIndex != null && game.isMyTurn)
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
                                      Text('Editing Dart ${(_editingDartIndex ?? 0) + 1}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                                    ],
                                  ),
                                  TextButton(
                                    onPressed: () => setState(() => _editingDartIndex = null),
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      backgroundColor: Colors.white.withValues(alpha: 0.2),
                                    ),
                                    child: const Text('CANCEL', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
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

  Widget _buildMyTurnOverlay(TournamentGameProvider game) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // My score + dart indicators
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
                Row(
                  children: [
                    const Text('YOUR SCORE: ', style: TextStyle(color: AppTheme.textSecondary, fontSize: 10, fontWeight: FontWeight.bold)),
                    Text('${game.myScore}', style: TextStyle(color: game.myScore <= 170 ? AppTheme.success : AppTheme.primary, fontSize: 22, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    ...List.generate(3, (index) {
                      final throws = game.currentRoundThrows;
                      final hasThrow = index < throws.length;
                      final isNext = index == throws.length;
                      final isEditing = _editingDartIndex == index;

                      return GestureDetector(
                        onTap: hasThrow ? () {
                          HapticService.lightImpact();
                          setState(() => _editingDartIndex = isEditing ? null : index);
                        } : null,
                        child: Container(
                          width: 36, height: 36,
                          margin: const EdgeInsets.only(right: 6),
                          decoration: BoxDecoration(
                            color: isEditing ? AppTheme.error.withValues(alpha: 0.3) : hasThrow ? AppTheme.primary.withValues(alpha: 0.2) : AppTheme.background,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isEditing ? AppTheme.error : hasThrow ? AppTheme.primary : isNext ? Colors.white24 : Colors.transparent,
                              width: isEditing ? 3 : (hasThrow || isNext ? 2 : 1),
                            ),
                          ),
                          child: Center(
                            child: hasThrow
                                ? Text(throws[index], style: TextStyle(color: isEditing ? AppTheme.error : AppTheme.primary, fontSize: 12, fontWeight: FontWeight.bold))
                                : Icon(Icons.adjust, color: isNext ? Colors.white54 : Colors.white10, size: 14),
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
                          if (_editingDartIndex != null && _editingDartIndex! < game.currentRoundThrows.length) {
                            game.editDartThrow(_editingDartIndex!, 0, ScoreMultiplier.single);
                            setState(() => _editingDartIndex = null);
                          } else {
                            game.throwDart(baseScore: 0, multiplier: ScoreMultiplier.single);
                          }
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          width: 44, height: 36,
                          decoration: BoxDecoration(
                            color: AppTheme.background,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppTheme.surfaceLight, width: 2),
                          ),
                          child: const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.close, color: Colors.white70, size: 14),
                              Text('MISS', style: TextStyle(color: Colors.white70, fontSize: 7, fontWeight: FontWeight.bold)),
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
        const SizedBox(width: 10),
        // Opponent score card
        Container(
          width: 90,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: AppTheme.surfaceLight.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.surfaceLight, width: 2),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 2))],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(widget.opponentUsername.toUpperCase(), style: const TextStyle(color: AppTheme.textSecondary, fontSize: 9, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis, maxLines: 1),
              const SizedBox(height: 2),
              Text('${game.opponentScore}', style: const TextStyle(color: AppTheme.primary, fontSize: 22, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOpponentTurnVideoLayout(TournamentGameProvider game) {
    return Stack(
      children: [
        if (_agoraEngine != null && game.remoteUid != null)
          Container(
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.error, width: 3),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: AgoraVideoView(
                controller: VideoViewController.remote(
                  rtcEngine: _agoraEngine!,
                  canvas: VideoCanvas(uid: game.remoteUid!),
                  connection: const RtcConnection(channelId: ''),
                ),
              ),
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.surfaceLight, width: 2),
            ),
            child: const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.videocam_off, size: 48, color: AppTheme.textSecondary),
                  SizedBox(height: 8),
                  Text('WAITING...', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
        Positioned(
          top: 12,
          left: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.error, width: 2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.opponentUsername.toUpperCase(), style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontWeight: FontWeight.bold)),
                Text('${game.opponentScore}', style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMediaControls() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildControlButton(
            icon: _isAudioMuted ? Icons.mic_off : Icons.mic,
            color: _isAudioMuted ? AppTheme.error : AppTheme.primary,
            onTap: _toggleAudio,
          ),
          const SizedBox(width: 16),
          _buildControlButton(
            icon: Icons.cameraswitch,
            color: AppTheme.primary,
            onTap: _switchCamera,
          ),
        ],
      ),
    );
  }

  Widget _buildControlButton({required IconData icon, required Color color, required VoidCallback onTap}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color, width: 2),
          ),
          child: Icon(icon, color: color, size: 24),
        ),
      ),
    );
  }

  Widget _buildScoreInput(TournamentGameProvider game) {
    if (!game.isMyTurn) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(width: 48, height: 48, child: CircularProgressIndicator(color: AppTheme.error, strokeWidth: 3)),
            const SizedBox(height: 24),
            Text("OPPONENT'S TURN", style: TextStyle(color: AppTheme.error.withValues(alpha: 0.8), fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 2)),
            const SizedBox(height: 8),
            const Text("Please wait...", style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.symmetric(horizontal: 40),
              decoration: BoxDecoration(
                color: AppTheme.error.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.error, width: 2),
              ),
              child: const Column(
                children: [
                  Icon(Icons.warning_rounded, color: AppTheme.error, size: 32),
                  SizedBox(height: 8),
                  Text("DO NOT PLAY!", textAlign: TextAlign.center, style: TextStyle(color: AppTheme.error, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1)),
                  SizedBox(height: 8),
                  Text("Playing during opponent's turn may result in match forfeiture", textAlign: TextAlign.center, style: TextStyle(color: AppTheme.error, fontSize: 12, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: Column(
            children: [
              const Spacer(flex: 1),
              Expanded(
                flex: 3,
                child: Container(
                  color: AppTheme.surface,
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  child: InteractiveDartboard(
                    onDartThrow: (score, multiplier) {
                      if (_editingDartIndex != null && _editingDartIndex! < game.currentRoundThrows.length) {
                        game.editDartThrow(_editingDartIndex!, score, multiplier);
                        setState(() => _editingDartIndex = null);
                      } else {
                        game.throwDart(baseScore: score, multiplier: multiplier);
                      }
                    },
                  ),
                ),
              ),
              if (game.isMyTurn)
                Container(
                  padding: const EdgeInsets.all(16),
                  color: AppTheme.surface,
                  child: SizedBox(
                    width: double.infinity,
                    height: 64,
                    child: ElevatedButton(
                      onPressed: () {
                        HapticService.heavyImpact();
                        game.confirmRound();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: game.pendingConfirmation ? AppTheme.primary : AppTheme.primary.withValues(alpha: 0.5),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(game.pendingConfirmation ? 'CONFIRM & END TURN' : 'END TURN EARLY', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1)),
                          const SizedBox(width: 8),
                          const Icon(Icons.check_circle_outline),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
