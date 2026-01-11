import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/matchmaking_provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/socket_service.dart';
import '../game/game_screen.dart';

class MatchmakingScreen extends StatefulWidget {
  const MatchmakingScreen({super.key});

  @override
  State<MatchmakingScreen> createState() => _MatchmakingScreenState();
}

class _MatchmakingScreenState extends State<MatchmakingScreen>
    with TickerProviderStateMixin {
  late AnimationController _rotationController;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();

    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeInOut,
      ),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final matchmaking = context.read<MatchmakingProvider>();
      matchmaking.addListener(_onMatchmakingUpdate);
      
      // Check if match was already found (immediate match)
      if (matchmaking.matchFound) {
        debugPrint('🎯 Immediate match detected in initState');
        _showMatchFoundDialog();
      }
    });
  }

  void _onMatchmakingUpdate() {
    final matchmaking = context.read<MatchmakingProvider>();
    if (matchmaking.matchFound && mounted) {
      _showMatchFoundDialog();
    }
  }

  void _showMatchFoundDialog() {
    final matchmaking = context.read<MatchmakingProvider>();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: const Color(0xFF0A0A0A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF00E5FF), width: 2),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.check_circle,
                color: Color(0xFF00E5FF),
                size: 80,
              ),
              const SizedBox(height: 16),
              const Text(
                'MATCH FOUND!',
                style: TextStyle(
                  color: Color(0xFF00E5FF),
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 24),
              if (matchmaking.opponentId != null)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1A),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'Opponent',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        matchmaking.opponentUsername ?? matchmaking.opponentId ?? 'Unknown',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'ELO: ${matchmaking.opponentElo ?? matchmaking.playerElo ?? 1200}',
                        style: const TextStyle(
                          color: Color(0xFF00E5FF),
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 24),
              const Text(
                'Starting game...',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    Future.delayed(const Duration(seconds: 3), () {
      if (!mounted) {
        debugPrint('⚠️ MatchmakingScreen not mounted, skipping navigation');
        return;
      }
      
      if (matchmaking.matchId == null || matchmaking.opponentId == null) {
        debugPrint('⚠️ Missing match data - matchId: ${matchmaking.matchId}, opponentId: ${matchmaking.opponentId}');
        return;
      }
      
      try {
        debugPrint('🎮 Navigating to GameScreen - matchId: ${matchmaking.matchId}, opponentId: ${matchmaking.opponentId}');
        
        Navigator.of(context).pop(); // Close dialog
        Navigator.of(context).pop(); // Go back from matchmaking screen
        
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => GameScreen(
              matchId: matchmaking.matchId!,
              opponentId: matchmaking.opponentId!,
            ),
          ),
        );
        
        debugPrint('✅ Navigation to GameScreen complete');
        
        // Don't reset match here - it will be reset when matchmaking screen disposes
      } catch (e, stackTrace) {
        debugPrint('❌ Error navigating to GameScreen: $e');
        debugPrint('Stack trace: $stackTrace');
      }
    });
  }

  @override
  void dispose() {
    debugPrint('🧹 MatchmakingScreen dispose called');
    try {
      if (mounted) {
        final matchmaking = context.read<MatchmakingProvider>();
        matchmaking.removeListener(_onMatchmakingUpdate);
      }
    } catch (e) {
      debugPrint('⚠️ Error in dispose: $e');
    }
    _rotationController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(1, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final matchmaking = context.watch<MatchmakingProvider>();
    final user = context.watch<AuthProvider>().currentUser;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop && mounted && user?.id != null) {
          debugPrint('🚪 PopScope: Leaving queue for user ${user!.id}');
          await matchmaking.leaveQueue(user.id);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Finding Match'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () async {
              debugPrint('⬅️ Back button pressed');
              if (mounted && user?.id != null) {
                await matchmaking.leaveQueue(user!.id);
              }
              if (mounted && context.mounted) {
                Navigator.of(context).pop();
              }
            },
          ),
        ),
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Color(0xFF0A0A0A),
                Color(0xFF1A1A1A),
                Color(0xFF0A0A0A),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                    decoration: BoxDecoration(
                      color: SocketService.isConnected 
                          ? const Color(0xFF4CAF50).withValues(alpha: 0.2)
                          : const Color(0xFFFF5252).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: SocketService.isConnected 
                            ? const Color(0xFF4CAF50)
                            : const Color(0xFFFF5252),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          SocketService.isConnected ? Icons.wifi : Icons.wifi_off,
                          color: SocketService.isConnected 
                              ? const Color(0xFF4CAF50) 
                              : const Color(0xFFFF5252),
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          SocketService.isConnected 
                              ? 'Connected'
                              : 'Not connected',
                          style: TextStyle(
                            color: SocketService.isConnected 
                                ? const Color(0xFF4CAF50) 
                                : const Color(0xFFFF5252),
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  AnimatedBuilder(
                    animation: _rotationController,
                    builder: (context, child) {
                      return Transform.rotate(
                        angle: _rotationController.value * 2 * math.pi,
                        child: child,
                      );
                    },
                    child: ScaleTransition(
                      scale: _pulseAnimation,
                      child: Container(
                        width: 200,
                        height: 200,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              const Color(0xFF00E5FF).withValues(alpha: 0.3),
                              const Color(0xFF00E5FF).withValues(alpha: 0.1),
                              Colors.transparent,
                            ],
                          ),
                          border: Border.all(
                            color: const Color(0xFF00E5FF),
                            width: 3,
                          ),
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            ...List.generate(8, (index) {
                              final angle = (index * math.pi / 4);
                              return Transform.rotate(
                                angle: angle,
                                child: Container(
                                  width: 3,
                                  height: 100,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        const Color(0xFF00E5FF),
                                        Colors.transparent,
                                      ],
                                      begin: Alignment.center,
                                      end: Alignment.topCenter,
                                    ),
                                  ),
                                ),
                              );
                            }),
                            const Icon(
                              Icons.gps_fixed,
                              color: Color(0xFF00E5FF),
                              size: 64,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 48),
                  const Text(
                    'Searching for opponent...',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _formatTime(matchmaking.searchTime),
                    style: const TextStyle(
                      color: Color(0xFF00E5FF),
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 32),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 16,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A1A),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFF00E5FF).withValues(alpha: 0.3),
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Your ELO',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              '${user?.elo ?? 0}',
                              style: const TextStyle(
                                color: Color(0xFF00E5FF),
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Search Range',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              '±${matchmaking.eloRange} ELO',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 48),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: () async {
                        debugPrint('❌ Cancel search pressed');
                        if (mounted && user?.id != null) {
                          await matchmaking.leaveQueue(user!.id);
                        }
                        if (mounted && context.mounted) {
                          Navigator.of(context).pop();
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF1744),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 8,
                      ),
                      child: const Text(
                        'CANCEL SEARCH',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  ),
                  if (matchmaking.errorMessage != null) ...[
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF1744).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFFFF1744),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.error_outline,
                            color: Color(0xFFFF1744),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              matchmaking.errorMessage!,
                              style: const TextStyle(
                                color: Color(0xFFFF1744),
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
