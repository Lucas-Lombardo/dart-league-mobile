import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import '../../providers/game_provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/match_service.dart';
import '../../services/agora_service.dart';
import '../../utils/haptic_service.dart';
import '../../utils/app_theme.dart';

class GameScreen extends StatefulWidget {
  final String matchId;
  final String opponentId;
  final String? agoraAppId;
  final String? agoraToken;
  final String? agoraChannelName;

  const GameScreen({
    super.key,
    required this.matchId,
    required this.opponentId,
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
  
  // Agora video
  RtcEngine? _agoraEngine;
  bool _isVideoEnabled = true;
  bool _isAudioMuted = false;
  bool _permissionsGranted = false;

  @override
  void initState() {
    super.initState();
    
    debugPrint('🎮 GameScreen initState - matchId: ${widget.matchId}, opponentId: ${widget.opponentId}');
    
    _scoreAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        final game = context.read<GameProvider>();
        final auth = context.read<AuthProvider>();
        
        if (auth.currentUser != null) {
          game.initGame(
            widget.matchId, 
            auth.currentUser!.id, 
            widget.opponentId,
            agoraAppId: widget.agoraAppId,
            agoraToken: widget.agoraToken,
            agoraChannelName: widget.agoraChannelName,
          );
          
          // Initialize Agora if credentials are available
          if (widget.agoraAppId != null) {
            _initializeAgora();
          }
        }
      } catch (e, stackTrace) {
        debugPrint('❌ GameScreen initState error: $e');
        debugPrint('Stack trace: $stackTrace');
      }
    });
  }

  Future<void> _initializeAgora() async {
    debugPrint('📹 Initializing Agora for video calling');
    
    // Request permissions
    _permissionsGranted = await AgoraService.requestPermissions();
    if (!_permissionsGranted) {
      debugPrint('❌ Camera/Mic permissions denied');
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
      
      // Set up event handlers
      _agoraEngine!.registerEventHandler(
        RtcEngineEventHandler(
          onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
            debugPrint('📹 Local user joined channel: ${connection.channelId}');
            final game = context.read<GameProvider>();
            game.setLocalUserJoined(true);
          },
          onUserJoined: (RtcConnection connection, int remoteUid, int elapsed) {
            debugPrint('📹 Remote user joined: $remoteUid');
            final game = context.read<GameProvider>();
            game.setRemoteUser(remoteUid);
          },
          onUserOffline: (RtcConnection connection, int remoteUid, UserOfflineReasonType reason) {
            debugPrint('📹 Remote user offline: $remoteUid, reason: $reason');
            final game = context.read<GameProvider>();
            game.setRemoteUser(null);
          },
        ),
      );
      
      // Join channel
      if (widget.agoraToken != null && widget.agoraChannelName != null) {
        await AgoraService.joinChannel(
          engine: _agoraEngine!,
          token: widget.agoraToken!,
          channelName: widget.agoraChannelName!,
          uid: 0, // 0 means Agora will assign a uid
        );
      }
    } catch (e) {
      debugPrint('❌ Error initializing Agora: $e');
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
    
    await AgoraService.toggleLocalAudio(_agoraEngine!, _isAudioMuted);
  }
  
  Future<void> _switchCamera() async {
    if (_agoraEngine == null) return;
    await AgoraService.switchCamera(_agoraEngine!);
  }

  @override
  void dispose() {
    _scoreAnimationController.dispose();
    
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
      
      debugPrint('✅ Match result accepted');
      
      if (!mounted) return;
      
      // Fetch updated user profile from database
      debugPrint('🔄 Fetching updated user profile from database...');
      await auth.checkAuthStatus();
      
      if (auth.currentUser != null) {
        debugPrint('✅ User profile updated: ELO=${auth.currentUser!.elo}, Rank=${auth.currentUser!.rank}');
      } else {
        debugPrint('⚠️ Failed to fetch updated profile - /auth/profile endpoint may not exist or returned null');
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
      
      debugPrint('📢 Report submitted: $reason');
      
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

  @override
  Widget build(BuildContext context) {
    try {
      final game = context.watch<GameProvider>();
      final auth = context.watch<AuthProvider>();
      
      final matchId = game.matchId;
      final gameStarted = game.gameStarted;

      // Show loading if game not initialized or started
      if (matchId == null || !gameStarted) {
        return Scaffold(
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

      return Scaffold(
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
            onPressed: () {
              // Confirm exit dialog could be added here
              Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
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
        body: Column(
          children: [
            // Video Area - Side by side cameras
            Container(
              height: 220,
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  // Opponent's camera (left side)
                  Expanded(
                    child: Stack(
                      children: [
                        if (_agoraEngine != null && game.remoteUid != null)
                          Container(
                            decoration: BoxDecoration(
                              color: AppTheme.surface,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: !game.isMyTurn ? AppTheme.error : AppTheme.surfaceLight,
                                width: !game.isMyTurn ? 3 : 2,
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
                        // Opponent label and score
                        Positioned(
                          top: 8,
                          left: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.7),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: !game.isMyTurn ? AppTheme.error : AppTheme.surfaceLight,
                                width: 2,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'OPPONENT',
                                  style: TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  '${game.opponentScore}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 32,
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
                  const SizedBox(width: 12),
                  // Your camera (right side)
                  Expanded(
                    child: Stack(
                      children: [
                        if (_agoraEngine != null && _permissionsGranted)
                          Container(
                            decoration: BoxDecoration(
                              color: AppTheme.surface,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: game.isMyTurn ? AppTheme.primary : AppTheme.surfaceLight,
                                width: game.isMyTurn ? 3 : 2,
                              ),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: AgoraVideoView(
                                controller: VideoViewController(
                                  rtcEngine: _agoraEngine!,
                                  canvas: const VideoCanvas(uid: 0),
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
                                    'NO CAMERA',
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
                        // Your label and score
                        Positioned(
                          top: 8,
                          left: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.7),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: game.isMyTurn ? AppTheme.primary : AppTheme.surfaceLight,
                                width: 2,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'YOU',
                                  style: TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  '${game.myScore}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 32,
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
                ],
              ),
            ),
            
            // Camera/Mic controls
            if (_agoraEngine != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Camera toggle
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _toggleVideo,
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTheme.surface,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _isVideoEnabled ? AppTheme.primary : AppTheme.error,
                              width: 2,
                            ),
                          ),
                          child: Icon(
                            _isVideoEnabled ? Icons.videocam : Icons.videocam_off,
                            color: _isVideoEnabled ? AppTheme.primary : AppTheme.error,
                            size: 24,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
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
            
            // Current Round Darts Display
            Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              color: AppTheme.surface.withValues(alpha: 0.5),
              child: _buildCurrentRoundDisplay(game),
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
          ],
        ),
      );
    }

    // Active Input State
    return Column(
      children: [
        // Edit mode indicator
        if (_editingDartIndex != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: AppTheme.error.withValues(alpha: 0.2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.edit, color: AppTheme.error, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'Editing Dart ${(_editingDartIndex ?? 0) + 1}',
                      style: const TextStyle(
                        color: AppTheme.error,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
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
                  style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(50, 30)),
                  child: const Text(
                    'CANCEL',
                    style: TextStyle(color: AppTheme.error, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        
        // Action buttons row (Delete, Miss, Bulls)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          color: AppTheme.surface,
          child: Row(
            children: [
              Expanded(
                child: _buildActionButton(
                  icon: Icons.delete_outline,
                  label: 'DELETE',
                  color: AppTheme.error,
                  onTap: () {
                    if (_editingDartIndex != null && _editingDartIndex! < game.currentRoundThrows.length) {
                      game.deleteDartThrow(_editingDartIndex!);
                      setState(() {
                        _editingDartIndex = null;
                      });
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildScoreButton(0, 'MISS'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildScoreButton(25, 'S-BULL'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildScoreButton(50, 'D-BULL'),
              ),
            ],
          ),
        ),
        
        // Number grid and confirm button
        Expanded(
          child: Column(
            children: [
              // Number grid
              Expanded(
                child: Container(
                  color: AppTheme.surface,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: GridView.builder(
                    padding: const EdgeInsets.only(bottom: 8),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 10,
                      crossAxisSpacing: 4,
                      mainAxisSpacing: 4,
                      childAspectRatio: 0.85,
                    ),
                    itemCount: 60,
                    itemBuilder: (context, index) {
                      final row = index ~/ 10; // 0-5
                      final col = index % 10;
                      
                      // Determine multiplier based on row groups
                      ScoreMultiplier multiplier;
                      if (row < 2) {
                        // Rows 0-1: Singles
                        multiplier = ScoreMultiplier.single;
                      } else if (row < 4) {
                        // Rows 2-3: Doubles
                        multiplier = ScoreMultiplier.double;
                      } else {
                        // Rows 4-5: Triples
                        multiplier = ScoreMultiplier.triple;
                      }
                      
                      // Determine number based on even/odd row within each group
                      int number;
                      if (row % 2 == 0) {
                        // Even rows: 20 down to 11
                        number = 20 - col;
                      } else {
                        // Odd rows: 10 down to 1
                        number = 10 - col;
                      }
                      
                      return _buildNumberButton(number, multiplier);
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
