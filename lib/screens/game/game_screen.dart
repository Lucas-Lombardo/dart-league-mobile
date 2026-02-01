import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import '../../providers/game_provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/match_service.dart';
import '../../services/agora_service.dart';
import '../../services/socket_service.dart';
import '../../utils/haptic_service.dart';
import '../../utils/app_theme.dart';
import '../../widgets/interactive_dartboard.dart';

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

class _GameScreenState extends State<GameScreen> with SingleTickerProviderStateMixin {
  late AnimationController _scoreAnimationController;
  int? _editingDartIndex;
  
  // Store for leave_match event (needed in dispose)
  String? _storedMatchId;
  String? _storedPlayerId;
  bool _gameStarted = false;
  bool _gameEnded = false;
  
  // Agora video
  RtcEngine? _agoraEngine;
  bool _isVideoEnabled = true;
  bool _isAudioMuted = true;
  bool _permissionsGranted = false;

  @override
  void initState() {
    super.initState();
    
    
    _scoreAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        final game = context.read<GameProvider>();
        final auth = context.read<AuthProvider>();
        
        if (auth.currentUser != null) {
          // Store matchId and playerId for use in dispose
          _storedMatchId = widget.matchId;
          _storedPlayerId = auth.currentUser!.id;
          
          game.initGame(
            widget.matchId, 
            auth.currentUser!.id, 
            widget.opponentId,
            agoraAppId: widget.agoraAppId,
            agoraToken: widget.agoraToken,
            agoraChannelName: widget.agoraChannelName,
          );
          
          // Sync initial game state
          _gameStarted = game.gameStarted;
          _gameEnded = game.gameEnded;
          
          // Initialize Agora if credentials are available
          if (widget.agoraAppId != null) {
            _initializeAgora();
          }
          
          // Listen for pending confirmation state changes
          game.addListener(_handlePendingStateChange);
        }
      } catch (_) {
        // Initialization error
      }
    });
  }
  
  void _handlePendingStateChange() {
    // Early exit if widget is not mounted
    if (!mounted) return;
    
    try {
      final game = context.read<GameProvider>();
      
      // Track game state
      _gameStarted = game.gameStarted;
      _gameEnded = game.gameEnded;
      
      // Show dialog when entering pending state
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
      
      // Show forfeit dialog when opponent leaves
      if (game.gameEnded && game.pendingType == 'forfeit') {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && context.mounted) {
            _showForfeitDialog();
          }
        });
      }
    } catch (_) {
      // State change handling error
    }
  }

  Future<void> _initializeAgora() async {
    
    // Request permissions
    _permissionsGranted = await AgoraService.requestPermissions();
    if (!_permissionsGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Camera and microphone permissions are required for video calls'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
      return;
    }
    
    try {
      // Initialize engine
      _agoraEngine = await AgoraService.initializeEngine(widget.agoraAppId!);
      
      // Set back camera as default (same as camera setup)
      await AgoraService.setBackCamera(_agoraEngine!);
      
      // Set up event handlers
      _agoraEngine!.registerEventHandler(
        RtcEngineEventHandler(
          onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
            final game = context.read<GameProvider>();
            game.setLocalUserJoined(true);
          },
          onUserJoined: (RtcConnection connection, int remoteUid, int elapsed) {
            final game = context.read<GameProvider>();
            game.setRemoteUser(remoteUid);
          },
          onUserOffline: (RtcConnection connection, int remoteUid, UserOfflineReasonType reason) {
            final game = context.read<GameProvider>();
            game.setRemoteUser(null);
          },
        ),
      );
      
      // Disable audio completely before joining
      await _agoraEngine!.disableAudio();
      
      // Join channel
      if (widget.agoraToken != null && widget.agoraChannelName != null) {
        await AgoraService.joinChannel(
          engine: _agoraEngine!,
          token: widget.agoraToken!,
          channelName: widget.agoraChannelName!,
          uid: 0, // 0 means Agora will assign a uid
        );
      }
    } catch (_) {
      // Agora initialization error
    }
  }
  
  Future<void> _toggleVideo() async {
    if (_agoraEngine == null) return;
    
    setState(() {
      _isVideoEnabled = !_isVideoEnabled;
    });
    
    await AgoraService.toggleLocalVideo(_agoraEngine!, _isVideoEnabled);
  }
  
  Future<void> _toggleAudio() async {
    if (_agoraEngine == null) return;
    
    setState(() {
      _isAudioMuted = !_isAudioMuted;
    });
    
    if (_isAudioMuted) {
      // Disable audio completely
      await _agoraEngine!.disableAudio();
    } else {
      // Enable audio completely
      await _agoraEngine!.enableAudio();
    }
  }
  
  Future<void> _switchCamera() async {
    if (_agoraEngine == null) return;
    await AgoraService.switchCamera(_agoraEngine!);
  }

  // Build video layout when it's user's turn - show only small opponent camera
  Widget _buildMyTurnVideoLayout(GameProvider game) {
    return Align(
      alignment: Alignment.topLeft,
      child: Container(
        width: 120,
        height: 160,
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppTheme.surfaceLight,
            width: 2,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Stack(
            children: [
              if (_agoraEngine != null && game.remoteUid != null)
                AgoraVideoView(
                  controller: VideoViewController.remote(
                    rtcEngine: _agoraEngine!,
                    canvas: VideoCanvas(uid: game.remoteUid!),
                    connection: RtcConnection(channelId: ''),
                  ),
                )
              else
                Container(
                  color: AppTheme.surface,
                  child: const Center(
                    child: Icon(
                      Icons.videocam_off,
                      size: 32,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
              // Opponent label
              Positioned(
                bottom: 8,
                left: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.opponentUsername.toUpperCase(),
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${game.opponentScore}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Build video layout when it's opponent's turn - show large opponent with small user overlay
  Widget _buildOpponentTurnVideoLayout(GameProvider game) {
    return Stack(
      children: [
        // Large opponent camera (background)
        if (_agoraEngine != null && game.remoteUid != null)
          Container(
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppTheme.error,
                width: 3,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: AgoraVideoView(
                controller: VideoViewController.remote(
                  rtcEngine: _agoraEngine!,
                  canvas: VideoCanvas(uid: game.remoteUid!),
                  connection: RtcConnection(channelId: ''),
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
                  Text(
                    'WAITING...',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        // Opponent score overlay
        Positioned(
          top: 12,
          left: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: AppTheme.error,
                width: 2,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.opponentUsername.toUpperCase(),
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '${game.opponentScore}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
        // Small user camera overlay (top right)
        if (_agoraEngine != null && _permissionsGranted)
          Positioned(
            top: 12,
            right: 12,
            child: Container(
              width: 100,
              height: 130,
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppTheme.primary,
                  width: 2,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(
                  children: [
                    AgoraVideoView(
                      controller: VideoViewController(
                        rtcEngine: _agoraEngine!,
                        canvas: const VideoCanvas(uid: 0),
                      ),
                    ),
                    // User score overlay
                    Positioned(
                      bottom: 6,
                      left: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Builder(
                              builder: (context) {
                                final auth = context.read<AuthProvider>();
                                return Text(
                                  auth.currentUser?.username.toUpperCase() ?? 'YOU',
                                  style: const TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 8,
                                    fontWeight: FontWeight.bold,
                                  ),
                                );
                              }
                            ),
                            Text(
                              '${game.myScore}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _leaveMatch() {
    // Emit leave_match event to trigger forfeit on backend
    try {
      // Only emit if game actually started and hasn't ended
      if (_storedMatchId != null && _storedPlayerId != null && _gameStarted && !_gameEnded) {
        SocketService.emit('leave_match', {
          'matchId': _storedMatchId,
          'playerId': _storedPlayerId,
        });
      } else {
      }
    } catch (_) {
      // Leave match error
    }
  }

  @override
  void dispose() {
    _scoreAnimationController.dispose();
    
    // Emit leave_match before cleanup
    _leaveMatch();
    
    // Remove listener to prevent unmounted widget errors
    try {
      final game = context.read<GameProvider>();
      game.removeListener(_handlePendingStateChange);
    } catch (_) {
      // Provider access error during dispose
    }
    
    // Leave Agora channel and cleanup
    if (_agoraEngine != null) {
      AgoraService.leaveChannel(_agoraEngine!);
      AgoraService.dispose();
    }
    
    super.dispose();
  }

  void _acceptMatchResult(BuildContext context) async {
    final game = context.read<GameProvider>();
    final auth = context.read<AuthProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    
    if (game.matchId == null || auth.currentUser?.id == null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Unable to accept result: Missing data'),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }
    
    try {
      // Show loading
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Accepting match result...'),
          duration: Duration(seconds: 1),
        ),
      );
      
      final result = await MatchService.acceptMatchResult(
        game.matchId!,
        auth.currentUser!.id,
      );
      
      
      if (!mounted) return;
      
      // Fetch updated user profile from database
      await auth.checkAuthStatus();
      
      if (auth.currentUser != null) {
      } else {
      }
      
      // Reset game state to prevent duplicate dialogs
      game.reset();
      
      // Show success message
      final message = result['message'] as String? ?? 'Match result accepted';
      messenger.showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: AppTheme.success,
          duration: const Duration(milliseconds: 500),
        ),
      );
      
      // Navigate back to home and clear navigation stack
      await Future.delayed(const Duration(milliseconds: 300));
      
      if (mounted) {
        navigator.pushNamedAndRemoveUntil('/home', (route) => false);
      }
    } catch (e) {
      if (!mounted) return;
      
      messenger.showSnackBar(
        SnackBar(
          content: Text('Error accepting result: $e'),
          backgroundColor: AppTheme.error,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _showPendingWinDialog() {
    final game = context.read<GameProvider>();
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
            Text(
              'Is this correct?',
              style: AppTheme.labelLarge.copyWith(
                color: AppTheme.textSecondary,
              ),
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
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.success,
            ),
            child: const Text('Confirm Win'),
          ),
        ],
      ),
    );
  }

  void _showPendingBustDialog() {
    final game = context.read<GameProvider>();
    final reason = game.pendingReason ?? 'unknown';
    
    String reasonText = '';
    switch (reason) {
      case 'score_below_zero':
        reasonText = 'Score went below zero';
        break;
      case 'must_finish_double':
        reasonText = 'Must finish on a double';
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
            Text(
              reasonText,
              style: AppTheme.bodyLarge.copyWith(fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Confirm to pass turn or edit if incorrect',
              style: AppTheme.labelLarge.copyWith(
                color: AppTheme.textSecondary,
              ),
              textAlign: TextAlign.center,
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
              game.confirmBust();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.error,
            ),
            child: const Text('Confirm Bust'),
          ),
        ],
      ),
    );
  }

  void _showForfeitDialog() {
    final game = context.read<GameProvider>();
    final auth = context.read<AuthProvider>();
    final forfeitData = game.pendingData;
    final winnerId = forfeitData?['winnerId'] as String?;
    final eloChange = forfeitData?['winnerEloChange'] as int? ?? 0;
    final isWinner = winnerId == auth.currentUser?.id;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
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
              Navigator.pop(context);
              
              // Fetch updated user profile to get new ELO
              await auth.checkAuthStatus();
              
              if (auth.currentUser != null) {
              } else {
              }
              
              // Reset game state
              game.reset();
              
              // Navigate back to home
              if (context.mounted) {
                Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
              }
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

  void _showReportDialog(BuildContext context) {
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
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 14,
                ),
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
                      Text(
                        reason,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                ),
              )),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text(
                'CANCEL',
                style: TextStyle(color: AppTheme.textSecondary),
              ),
            ),
            ElevatedButton(
              onPressed: selectedReason == null
                  ? null
                  : () {
                      HapticService.mediumImpact();
                      Navigator.of(context).pop();
                      _submitReport(context, selectedReason!);
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.error,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'SUBMIT REPORT',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _submitReport(BuildContext context, String reason) async {
    final game = context.read<GameProvider>();
    final auth = context.read<AuthProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    
    if (game.matchId == null || auth.currentUser?.id == null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Unable to submit report: Missing data'),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }
    
    try {
      // Show loading
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Submitting dispute...'),
          duration: Duration(seconds: 1),
        ),
      );
      
      final result = await MatchService.disputeMatchResult(
        game.matchId!,
        auth.currentUser!.id,
        reason,
      );
      
      
      if (!mounted) return;
      
      // Show success message
      final message = result['message'] as String? ?? 'Dispute submitted successfully';
      messenger.showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: AppTheme.error,
          duration: const Duration(seconds: 2),
        ),
      );
      
      // Navigate back to home after delay
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          navigator.pushNamedAndRemoveUntil('/home', (route) => false);
        }
      });
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
  }

  Future<bool> _onWillPop() async {
    final game = Provider.of<GameProvider>(context, listen: false);
    
    // Allow leaving if game hasn't started (stuck on loading) or already ended
    if (!game.gameStarted || game.gameEnded) {
      return true;
    }
    
    // Show confirmation dialog
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
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'If you leave now, you will forfeit the match and lose ELO points.',
              style: AppTheme.bodyLarge.copyWith(fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Are you sure you want to leave?',
              style: AppTheme.labelLarge.copyWith(
                color: AppTheme.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Stay in Match'),
          ),
          ElevatedButton(
            onPressed: () {
              // Emit leave_match before leaving
              _leaveMatch();
              Navigator.pop(dialogContext, true);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.error,
            ),
            child: const Text('Leave & Forfeit'),
          ),
        ],
      ),
    );
    
    return shouldLeave ?? false;
  }

  @override
  Widget build(BuildContext context) {
    try {
      final game = context.watch<GameProvider>();
      final auth = context.watch<AuthProvider>();
      
      final matchId = game.matchId;
      final gameStarted = game.gameStarted;

      // Show loading if game not initialized or started
      if (matchId == null || !gameStarted) {
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) async {
            if (didPop) return;
            final shouldPop = await _onWillPop();
            if (shouldPop && context.mounted) {
              Navigator.of(context).pop();
            }
          },
          child: Scaffold(
            backgroundColor: AppTheme.background,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              iconTheme: const IconThemeData(color: Colors.white),
            ),
            body: const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(color: AppTheme.primary),
                SizedBox(height: 16),
                Text(
                  'INITIALIZING MATCH...',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    letterSpacing: 2,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
        );
      }

      final gameEnded = game.gameEnded;
      
      if (gameEnded) {
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
                      didWin ? 'VICTORY!' : 'DEFEAT',
                      style: AppTheme.displayLarge.copyWith(
                        color: didWin ? AppTheme.success : AppTheme.error,
                        fontSize: 48,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      didWin 
                          ? 'You have proven yourself a legend.' 
                          : 'Training is the path to greatness.',
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
                            style: TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 24),
                          
                          // Accept Result Button
                          SizedBox(
                            width: double.infinity,
                            height: 56,
                            child: ElevatedButton.icon(
                              onPressed: () {
                                HapticService.mediumImpact();
                                _acceptMatchResult(context);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.success,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              icon: const Icon(Icons.check_circle_outline),
                              label: const Text(
                                'ACCEPT RESULT',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1,
                                ),
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
                                _showReportDialog(context);
                              },
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppTheme.error,
                                side: BorderSide(color: AppTheme.error.withValues(alpha: 0.5), width: 2),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              icon: const Icon(Icons.flag_outlined),
                              label: const Text(
                                'REPORT PLAYER',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1,
                                ),
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

      final dartsThrown = game.dartsThrown;

      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop) return;
          final shouldPop = await _onWillPop();
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
              final shouldLeave = await _onWillPop();
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
        body: Container(
          color: AppTheme.background,
          child: Stack(
            children: [
              Column(
                children: [
                  // Video Area - Only show during opponent's turn
                  if (!game.isMyTurn)
                    Container(
                      height: 280,
                      padding: const EdgeInsets.all(12),
                      child: _buildOpponentTurnVideoLayout(game),
                    ),
            
            // Mic and Camera controls
            if (_agoraEngine != null && !game.isMyTurn)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Mic toggle
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _toggleAudio,
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTheme.surface,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _isAudioMuted ? AppTheme.error : AppTheme.primary,
                              width: 2,
                            ),
                          ),
                          child: Icon(
                            _isAudioMuted ? Icons.mic_off : Icons.mic,
                            color: _isAudioMuted ? AppTheme.error : AppTheme.primary,
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
                        onTap: _switchCamera,
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
                child: _buildScoreInput(game),
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
                    final showCamera = screenWidth >= 400 && _agoraEngine != null && game.remoteUid != null;
                    
                    return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Left: YOUR SCORE with global score, dart indicators, and MISS button
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
                                final isEditing = _editingDartIndex == index;
                                
                                return GestureDetector(
                                  onTap: hasThrow ? () {
                                    HapticService.lightImpact();
                                    setState(() {
                                      _editingDartIndex = isEditing ? null : index;
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
                                    if (_editingDartIndex != null && _editingDartIndex! < game.currentRoundThrows.length) {
                                      game.editDartThrow(_editingDartIndex!, 0, ScoreMultiplier.single);
                                      setState(() {
                                        _editingDartIndex = null;
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
                    
                    // Right: Camera widget (if screen is large enough) or simple score card (if screen is small)
                    if (showCamera)
                      ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxHeight: 220,
                          maxWidth: 160,
                        ),
                        child: Container(
                          width: 160,
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
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            // Camera video feed
                            Container(
                              width: double.infinity,
                              height: 105,
                              decoration: const BoxDecoration(
                                color: AppTheme.surface,
                              ),
                              child: AgoraVideoView(
                                controller: VideoViewController.remote(
                                  rtcEngine: _agoraEngine!,
                                  canvas: VideoCanvas(uid: game.remoteUid!),
                                  connection: RtcConnection(channelId: ''),
                                ),
                              ),
                            ),
                            // Score at bottom
                            Padding(
                              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
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
                                      fontSize: 22,
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
                              Text(
                                'Editing Dart ${(_editingDartIndex ?? 0) + 1}',
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
                                _editingDartIndex = null;
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

  Widget _buildCurrentRoundDisplay(GameProvider game) {
    final throws = game.currentRoundThrows;
    
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(3, (index) {
        final hasThrow = index < throws.length;
        final isNext = index == throws.length;
        final isEditing = _editingDartIndex == index;
        
        return GestureDetector(
          onTap: hasThrow && game.isMyTurn ? () {
            HapticService.lightImpact();
            setState(() {
              _editingDartIndex = isEditing ? null : index;
            });
          } : null,
          child: Container(
            width: 60,
            height: 60,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: hasThrow 
                  ? (isEditing ? AppTheme.error.withValues(alpha: 0.3) : AppTheme.primary.withValues(alpha: 0.2))
                  : AppTheme.background,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isEditing
                    ? AppTheme.error
                    : hasThrow 
                        ? AppTheme.primary 
                        : isNext && game.isMyTurn 
                            ? Colors.white24 
                            : Colors.transparent,
                width: hasThrow || (isNext && game.isMyTurn) || isEditing ? 2 : 1,
              ),
              boxShadow: hasThrow ? [
                BoxShadow(
                  color: (isEditing ? AppTheme.error : AppTheme.primary).withValues(alpha: 0.2),
                  blurRadius: 8,
                )
              ] : null,
            ),
            child: Stack(
              children: [
                Center(
                  child: hasThrow 
                    ? Text(
                        throws[index],
                        style: TextStyle(
                          color: isEditing ? AppTheme.error : AppTheme.primary,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      )
                    : Icon(
                        Icons.adjust,
                        color: isNext && game.isMyTurn ? Colors.white54 : Colors.white10,
                        size: 20,
                      ),
                ),
                if (hasThrow && game.isMyTurn)
                  Positioned(
                    top: 2,
                    right: 2,
                    child: Icon(
                      isEditing ? Icons.edit : Icons.edit_outlined,
                      size: 12,
                      color: isEditing ? AppTheme.error : AppTheme.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
        );
      }),
    );
  }

  Widget _buildScoreInput(GameProvider game) {
    // Waiting for Turn State
    if (!game.isMyTurn) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(
                color: AppTheme.error,
                strokeWidth: 3,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              "OPPONENT'S TURN",
              style: TextStyle(
                color: AppTheme.error.withValues(alpha: 0.8),
                fontSize: 20,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "Please wait...",
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.symmetric(horizontal: 40),
              decoration: BoxDecoration(
                color: AppTheme.error.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppTheme.error,
                  width: 2,
                ),
              ),
              child: const Column(
                children: [
                  Icon(
                    Icons.warning_rounded,
                    color: AppTheme.error,
                    size: 32,
                  ),
                  SizedBox(height: 8),
                  Text(
                    "DO NOT PLAY!",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppTheme.error,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    "Playing during opponent's turn may result in match forfeiture",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppTheme.error,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // Active Input State
    return Column(
      children: [
        
        // Interactive Dartboard and confirm button
        Expanded(
          child: Column(
            children: [
              // Add spacer to push dartboard down
              const Spacer(flex: 1),
              
              // Interactive Dartboard
              Expanded(
                flex: 3,
                child: Container(
                  color: AppTheme.surface,
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  child: InteractiveDartboard(
                    onDartThrow: (score, multiplier) {
                      if (_editingDartIndex != null && _editingDartIndex! < game.currentRoundThrows.length) {
                        game.editDartThrow(_editingDartIndex!, score, multiplier);
                        setState(() {
                          _editingDartIndex = null;
                        });
                      } else {
                        game.throwDart(baseScore: score, multiplier: multiplier);
                      }
                    },
                  ),
                ),
              ),
              
              // Confirm button (shown when pending confirmation or always available)
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
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            game.pendingConfirmation ? 'CONFIRM & END TURN' : 'END TURN EARLY',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1,
                            ),
                          ),
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

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: () {
        HapticService.mediumImpact();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScoreButton(int score, String label) {
    final game = context.read<GameProvider>();
    
    return GestureDetector(
      onTap: () {
        HapticService.mediumImpact();
        final multiplier = score == 50 ? ScoreMultiplier.double : ScoreMultiplier.single;
        final baseScore = score == 50 ? 25 : score;
        
        if (_editingDartIndex != null) {
          game.editDartThrow(_editingDartIndex!, baseScore, multiplier);
          setState(() {
            _editingDartIndex = null;
          });
        } else {
          game.throwDart(baseScore: baseScore, multiplier: multiplier);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.surfaceLight.withValues(alpha: 0.3)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNumberButton(int number, ScoreMultiplier multiplier) {
    final game = context.read<GameProvider>();
    
    // Determine color and dots based on multiplier
    Color backgroundColor;
    int dotCount;
    String label;
    
    if (multiplier == ScoreMultiplier.single) {
      backgroundColor = AppTheme.background;
      dotCount = 1;
      label = '$number';
    } else if (multiplier == ScoreMultiplier.double) {
      backgroundColor = const Color(0xFF1A3A1A); // Dark green tint
      dotCount = 2;
      label = '$number';
    } else {
      backgroundColor = const Color(0xFF3A1A1A); // Dark red tint
      dotCount = 3;
      label = '$number';
    }
    
    return GestureDetector(
      onTap: () {
        HapticService.lightImpact();
        
        if (_editingDartIndex != null) {
          game.editDartThrow(_editingDartIndex!, number, multiplier);
          setState(() {
            _editingDartIndex = null;
          });
        } else {
          game.throwDart(baseScore: number, multiplier: multiplier);
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppTheme.surfaceLight.withValues(alpha: 0.3)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
              overflow: TextOverflow.clip,
              maxLines: 1,
            ),
            const SizedBox(height: 1),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                dotCount,
                (index) => Container(
                  width: 2,
                  height: 2,
                  margin: const EdgeInsets.symmetric(horizontal: 0.5),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.6),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
