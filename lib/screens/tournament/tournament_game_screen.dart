import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
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
import '../../utils/dart_sound_service.dart';
import '../../utils/app_theme.dart';
import '../../utils/score_converter.dart';
import '../../utils/storage_service.dart';
import '../../services/auto_scoring_service.dart';
import '../../widgets/interactive_dartboard.dart';
import '../../widgets/auto_score_display.dart';
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

  // Camera zoom
  double _cameraZoom = 1.0;
  double _cameraMinZoom = 1.0;
  double _cameraMaxZoom = 1.0;

  // Initial loading screen
  bool _isLoading = true;
  Timer? _loadingTimer;

  // Auto-scoring
  AutoScoringService? _autoScoringService;
  bool _autoScoringEnabled = false;
  bool _autoScoringLoading = false;

  // Track current player to distinguish new-turn vs same-turn capture restart
  String? _lastKnownCurrentPlayer;

  // Dialog dedup flags
  bool _winDialogShowing = false;
  bool _bustDialogShowing = false;
  bool _forfeitDialogShowing = false;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();

    _loadingTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _isLoading = false);
    });

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

          if (game.agoraAppId != null && game.agoraAppId!.isNotEmpty) {
            _initializeAgora();
          }

          game.addListener(_handleStateChange);

          // Load auto-scoring preference
          _loadAutoScoringPref();

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

      // ── Auto-scoring capture management ──
      if (_autoScoringService != null && _autoScoringEnabled) {
        final justBecameMyTurn =
            game.isMyTurn && game.currentPlayerId != _lastKnownCurrentPlayer;

        if (game.isMyTurn && game.pendingConfirmation && _autoScoringService!.isCapturing) {
          // Pending dialog just appeared — stop to prevent spurious throw_dart events
          _autoScoringService!.stopCapture();
        } else if (game.isMyTurn && !game.pendingConfirmation && !_autoScoringService!.isCapturing) {
          if (justBecameMyTurn) {
            _autoScoringService!.resetTurn();
          } else {
            // Restarting within same turn (after undo) — sync slot state
            _autoScoringService!.syncEmittedCount(game.currentRoundThrows.length);
          }
          _autoScoringService!.startCapture();
        } else if (!game.isMyTurn && _autoScoringService!.isCapturing) {
          _autoScoringService!.stopCapture();
        }
      }
      _lastKnownCurrentPlayer = game.currentPlayerId;

      // Reset flags when a new leg starts
      if (game.tournamentState == TournamentGameState.playing && !game.gameEnded) {
        _resultAccepted = false;
        _navigatingToResult = false;
      }

      // ── Pending win/bust dialogs (dedup guard) ──
      if (game.pendingConfirmation && game.pendingType != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !context.mounted) return;
          if (game.pendingType == 'win' && !_winDialogShowing) {
            _showPendingWinDialog();
          } else if (game.pendingType == 'bust' && !_bustDialogShowing) {
            _showPendingBustDialog();
          }
        });
      }

      // ── Agora reconnection ──
      if (game.needsAgoraReconnect) {
        game.clearAgoraReconnectFlag();
        _reconnectAgora(game);
      }

      // ── Forfeit dialog (dedup guard) ──
      if (game.gameEnded && game.pendingType == 'forfeit') {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && context.mounted && !_forfeitDialogShowing) {
            _showForfeitDialog();
          }
        });
      }

      // ── Tournament state transitions ──
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
          myLegsWon: game.myLegsWon,
          opponentLegsWon: game.opponentLegsWon,
          bestOf: widget.bestOf,
        ),
      ),
    );
  }

  Future<void> _loadAutoScoringPref() async {
    if (kIsWeb || !AutoScoringService.isSupported) {
      _autoScoringEnabled = false;
      return;
    }
    final enabled = await StorageService.getAutoScoring();
    if (mounted) {
      setState(() => _autoScoringEnabled = enabled);
    }
  }

  Future<void> _initAutoScoring() async {
    if (_agoraEngine == null) return;
    if (kIsWeb || !AutoScoringService.isSupported) return;
    final enabled = await StorageService.getAutoScoring();
    if (!mounted) return;
    setState(() => _autoScoringEnabled = enabled);
    if (!_autoScoringEnabled) return;

    setState(() => _autoScoringLoading = true);
    final engine = _agoraEngine!;
    _autoScoringService = AutoScoringService();
    await _autoScoringService!.init(
      captureFrame: () => AgoraService.takeLocalSnapshot(engine),
      onDartDetected: (slotIndex, dartScore) {
        if (!mounted) return;
        final game = context.read<TournamentGameProvider>();
        if (!game.isMyTurn) return;
        final (baseScore, multiplier) = dartScoreToBackend(dartScore);
        HapticService.mediumImpact();
        DartSoundService.playDartHit(baseScore, multiplier);
        game.throwDart(baseScore: baseScore, multiplier: multiplier);
      },
    );
    if (mounted) {
      setState(() => _autoScoringLoading = false);
      if (_autoScoringService!.modelLoaded) {
        _autoScoringService!.startCapture();
      }
    }
  }

  void _submitAutoScoredDarts(TournamentGameProvider game) {
    if (_autoScoringService == null) return;
    _autoScoringService!.stopCapture();
    game.confirmRound();
  }

  Future<void> _initializeAgora() async {
    final game = context.read<TournamentGameProvider>();
    
    debugPrint('TOURNAMENT AGORA: Initializing...');
    debugPrint('TOURNAMENT AGORA: appId=${game.agoraAppId}, token=${game.agoraToken != null ? "present" : "null"}, channel=${game.agoraChannelName}');
    
    // Validate credentials before proceeding
    if (game.agoraAppId == null || game.agoraAppId!.isEmpty ||
        game.agoraToken == null || game.agoraToken!.isEmpty ||
        game.agoraChannelName == null || game.agoraChannelName!.isEmpty) {
      debugPrint('TOURNAMENT AGORA: Missing credentials, skipping initialization');
      return;
    }
    
    _permissionsGranted = await AgoraService.requestPermissions();
    if (!_permissionsGranted) {
      debugPrint('TOURNAMENT AGORA: Permissions not granted');
      return;
    }

    try {
      _agoraEngine = await AgoraService.initializeEngine(game.agoraAppId!);
      await AgoraService.setBackCamera(_agoraEngine!);

      _agoraEngine!.registerEventHandler(
        RtcEngineEventHandler(
          onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
            debugPrint('TOURNAMENT AGORA: Joined channel successfully');
            if (!mounted) return;
            context.read<TournamentGameProvider>().setLocalUserJoined(true);
          },
          onUserJoined: (RtcConnection connection, int remoteUid, int elapsed) {
            debugPrint('TOURNAMENT AGORA: Remote user joined: $remoteUid');
            if (!mounted) return;
            context.read<TournamentGameProvider>().setRemoteUser(remoteUid);
          },
          onUserOffline: (RtcConnection connection, int remoteUid, UserOfflineReasonType reason) {
            debugPrint('TOURNAMENT AGORA: Remote user offline: $remoteUid');
            if (!mounted) return;
            context.read<TournamentGameProvider>().setRemoteUser(null);
          },
          onLocalVideoStateChanged: (VideoSourceType source, LocalVideoStreamState state, LocalVideoStreamReason error) {
            if (state == LocalVideoStreamState.localVideoStreamStateCapturing ||
                state == LocalVideoStreamState.localVideoStreamStateEncoding) {
              _initCameraZoom();
            }
          },
        ),
      );

      debugPrint('TOURNAMENT AGORA: Joining channel ${game.agoraChannelName}');
      await AgoraService.joinChannel(
        engine: _agoraEngine!,
        token: game.agoraToken!,
        channelName: game.agoraChannelName!,
        uid: 0,
      );

      debugPrint('TOURNAMENT AGORA: Initialization complete');

      // Initialize auto-scoring if enabled
      await _initAutoScoring();
    } catch (e) {
      debugPrint('TOURNAMENT AGORA: Error during initialization: $e');
    }
  }

  Future<void> _reconnectAgora(TournamentGameProvider game) async {
    final appId = game.agoraAppId;
    final token = game.agoraToken;
    final channelName = game.agoraChannelName;
    
    debugPrint('TOURNAMENT AGORA: Reconnecting...');
    debugPrint('TOURNAMENT AGORA: appId=$appId, token=${token != null ? "present" : "null"}, channel=$channelName');
    
    if (appId == null || appId.isEmpty || 
        token == null || token.isEmpty || 
        channelName == null || channelName.isEmpty) {
      debugPrint('TOURNAMENT AGORA: Missing credentials for reconnect');
      return;
    }

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
            debugPrint('TOURNAMENT AGORA: Reconnected to channel successfully');
            if (!mounted) return;
            context.read<TournamentGameProvider>().setLocalUserJoined(true);
          },
          onUserJoined: (RtcConnection connection, int remoteUid, int elapsed) {
            debugPrint('TOURNAMENT AGORA: Remote user joined after reconnect: $remoteUid');
            if (!mounted) return;
            context.read<TournamentGameProvider>().setRemoteUser(remoteUid);
          },
          onUserOffline: (RtcConnection connection, int remoteUid, UserOfflineReasonType reason) {
            debugPrint('TOURNAMENT AGORA: Remote user offline after reconnect: $remoteUid');
            if (!mounted) return;
            context.read<TournamentGameProvider>().setRemoteUser(null);
          },
          onLocalVideoStateChanged: (VideoSourceType source, LocalVideoStreamState state, LocalVideoStreamReason error) {
            if (state == LocalVideoStreamState.localVideoStreamStateCapturing ||
                state == LocalVideoStreamState.localVideoStreamStateEncoding) {
              _initCameraZoom();
            }
          },
        ),
      );
      await AgoraService.joinChannel(
        engine: _agoraEngine!,
        token: token,
        channelName: channelName,
        uid: 0,
      );
      _isAudioMuted = true;
      debugPrint('TOURNAMENT AGORA: Reconnection complete');

      // Re-initialize auto-scoring with the fresh engine
      if (_autoScoringService != null) {
        _autoScoringService!.stopCapture();
        _autoScoringService!.dispose();
        _autoScoringService = null;
      }
      await _initAutoScoring();
    } catch (e) {
      debugPrint('TOURNAMENT AGORA: Reconnection error: $e');
    }
  }

  Future<void> _toggleAudio() async {
    if (_agoraEngine == null) return;
    setState(() => _isAudioMuted = !_isAudioMuted);
    await _agoraEngine!.updateChannelMediaOptions(
      ChannelMediaOptions(publishMicrophoneTrack: !_isAudioMuted),
    );
    await _agoraEngine!.muteLocalAudioStream(_isAudioMuted);
  }

  Future<void> _switchCamera() async {
    if (_agoraEngine == null) return;
    await AgoraService.switchCamera(_agoraEngine!);
  }

  bool _cameraZoomInitialized = false;

  Future<void> _initCameraZoom({int attempt = 0}) async {
    if (_agoraEngine == null || !mounted || _cameraZoomInitialized) return;
    try {
      final maxZoom = await _agoraEngine!.getCameraMaxZoomFactor();
      if (mounted && maxZoom > 1.0) {
        _cameraZoomInitialized = true;
        setState(() {
          _cameraMinZoom = 1.0;
          _cameraMaxZoom = maxZoom.clamp(1.0, 10.0);
          _cameraZoom = 1.0;
        });
        debugPrint('ZOOM DEBUG: tournament zoom initialized max=$_cameraMaxZoom');
      }
    } catch (e) {
      if (attempt < 5 && mounted) {
        final delay = Duration(milliseconds: 500 * (attempt + 1));
        debugPrint('ZOOM DEBUG: tournament _initCameraZoom failed (attempt $attempt), retrying in ${delay.inMilliseconds}ms: $e');
        Future.delayed(delay, () => _initCameraZoom(attempt: attempt + 1));
      }
    }
  }

  Future<void> _zoomIn() async {
    if (_agoraEngine == null) return;
    final next = (_cameraZoom + 0.5).clamp(_cameraMinZoom, _cameraMaxZoom);
    await _agoraEngine!.setCameraZoomFactor(next);
    if (mounted) setState(() => _cameraZoom = next);
  }

  Future<void> _zoomOut() async {
    if (_agoraEngine == null) return;
    final next = (_cameraZoom - 0.5).clamp(_cameraMinZoom, _cameraMaxZoom);
    await _agoraEngine!.setCameraZoomFactor(next);
    if (mounted) setState(() => _cameraZoom = next);
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
    _winDialogShowing = true;
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
              _winDialogShowing = false;
              Navigator.pop(context);
              game.undoLastDart();
            },
            child: const Text('Edit Darts'),
          ),
          ElevatedButton(
            onPressed: () {
              _winDialogShowing = false;
              Navigator.pop(context);
              game.confirmWin();
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.success),
            child: const Text('Confirm Win'),
          ),
        ],
      ),
    ).then((_) => _winDialogShowing = false);
  }

  void _showPendingBustDialog() {
    final game = context.read<TournamentGameProvider>();
    final reason = game.pendingReason ?? 'unknown';
    _bustDialogShowing = true;
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
            onPressed: () {
              _bustDialogShowing = false;
              Navigator.pop(context);
              game.undoLastDart();
            },
            child: const Text('Edit Darts'),
          ),
          ElevatedButton(
            onPressed: () {
              _bustDialogShowing = false;
              Navigator.pop(context);
              game.confirmBust();
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            child: const Text('Confirm Bust'),
          ),
        ],
      ),
    ).then((_) => _bustDialogShowing = false);
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
    _forfeitDialogShowing = true;
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
              _forfeitDialogShowing = false;
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
    ).then((_) => _forfeitDialogShowing = false);
  }

  String _formatSeconds(int totalSeconds) {
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _loadingTimer?.cancel();
    _scoreAnimationController.dispose();
    WakelockPlus.disable();
    _leaveMatch();
    try {
      final game = context.read<TournamentGameProvider>();
      game.removeListener(_handleStateChange);
    } catch (_) {}
    _autoScoringService?.dispose();
    _autoScoringService = null;
    if (_agoraEngine != null) {
      AgoraService.leaveChannel(_agoraEngine!);
      AgoraService.dispose();
    }
    super.dispose();
  }

  Widget _buildLoadingScreen() {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldPop = await _onWillPop();
        if (shouldPop && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset('assets/logo/logo.png', width: 90, height: 90),
                const SizedBox(height: 32),
                const CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 2),
                const SizedBox(height: 24),
                Text(
                  'PREPARING MATCH',
                  style: AppTheme.titleLarge.copyWith(
                    color: AppTheme.textSecondary,
                    letterSpacing: 3,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Setting up camera & AI scoring...',
                  style: AppTheme.bodyLarge.copyWith(color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return _buildLoadingScreen();

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
              body: _autoScoringEnabled && _autoScoringLoading
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
                : _autoScoringEnabled && _autoScoringService != null && _autoScoringService!.modelLoaded && game.isMyTurn
                ? AutoScoreGameView(
                    scoringService: _autoScoringService!,
                    onConfirm: () => _submitAutoScoredDarts(game),
                    pendingConfirmation: game.pendingConfirmation,
                    myScore: game.myScore,
                    opponentScore: game.opponentScore,
                    opponentName: widget.opponentUsername,
                    myName: auth.currentUser?.username ?? 'You',
                    dartsThrown: game.dartsThrown,
                    agoraEngine: _agoraEngine,
                    remoteUid: game.remoteUid,
                    isAudioMuted: _isAudioMuted,
                    onToggleAudio: _toggleAudio,
                    onSwitchCamera: _switchCamera,
                    onZoomIn: _zoomIn,
                    onZoomOut: _zoomOut,
                    currentZoom: _cameraZoom,
                    minZoom: _cameraMinZoom,
                    maxZoom: _cameraMaxZoom,
                  )
                : Container(
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
                  connection: RtcConnection(channelId: game.agoraChannelName ?? ''),
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
      final opponentThrows = game.opponentRoundThrows;

      return SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text("OPPONENT'S DARTS", style: TextStyle(color: AppTheme.textSecondary, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(3, (i) {
                  final hasThrow = i < opponentThrows.length;
                  final notation = hasThrow ? opponentThrows[i] : null;
                  return Container(
                    width: 76,
                    margin: const EdgeInsets.symmetric(horizontal: 5),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: hasThrow ? AppTheme.surface : AppTheme.background,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: hasThrow ? AppTheme.primary.withValues(alpha: 0.4) : AppTheme.surfaceLight.withValues(alpha: 0.2)),
                    ),
                    child: Text(hasThrow ? notation! : '—', textAlign: TextAlign.center, style: TextStyle(color: hasThrow ? Colors.white : Colors.white24, fontSize: 18, fontWeight: FontWeight.bold)),
                  );
                }),
              ),
              const SizedBox(height: 16),
              const SizedBox(width: 36, height: 36, child: CircularProgressIndicator(color: AppTheme.error, strokeWidth: 2.5)),
              const SizedBox(height: 12),
              Text("OPPONENT'S TURN", style: TextStyle(color: AppTheme.error.withValues(alpha: 0.8), fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 2)),
              const SizedBox(height: 4),
              const Text("Please wait...", style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                margin: const EdgeInsets.symmetric(horizontal: 40),
                decoration: BoxDecoration(
                  color: AppTheme.error.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.error.withValues(alpha: 0.5)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.warning_rounded, color: AppTheme.error, size: 18),
                    SizedBox(width: 8),
                    Flexible(child: Text("Do not play during opponent's turn", style: TextStyle(color: AppTheme.error, fontSize: 12, fontWeight: FontWeight.w600))),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Manual interactive dartboard
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
