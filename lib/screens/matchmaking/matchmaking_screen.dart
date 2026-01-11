import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/matchmaking_provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/socket_service.dart';
import '../game/game_screen.dart';
import '../../utils/app_theme.dart';

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
  MatchmakingProvider? _matchmakingProvider;

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
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    
    if (_matchmakingProvider == null) {
      _matchmakingProvider = context.read<MatchmakingProvider>();
      _matchmakingProvider!.addListener(_onMatchmakingUpdate);
      
      // Check if match was already found (immediate match)
      if (_matchmakingProvider!.matchFound) {
        debugPrint('🎯 Immediate match detected');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _showMatchFoundDialog();
          }
        });
      }
    }
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
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppTheme.primary, width: 2),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.check_circle,
                color: AppTheme.primary,
                size: 80,
              ),
              const SizedBox(height: 16),
              const Text(
                'MATCH FOUND!',
                style: TextStyle(
                  color: AppTheme.primary,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 24),
              if (matchmaking.opponentId != null)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.background,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.surfaceLight.withValues(alpha: 0.5)),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'OPPONENT',
                        style: AppTheme.labelLarge.copyWith(color: AppTheme.textSecondary),
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
                          color: AppTheme.primary,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 24),
              const Text(
                'Starting game...',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 14,
                  fontStyle: FontStyle.italic,
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
        
        // Use Navigator to replace the entire stack with GameScreen
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (context) => GameScreen(
              matchId: matchmaking.matchId!,
              opponentId: matchmaking.opponentId!,
            ),
          ),
          (route) => route.isFirst, // Keep only the first route (home screen)
        );
        
        debugPrint('✅ Navigation to GameScreen complete');
      } catch (e, stackTrace) {
        debugPrint('❌ Error navigating to GameScreen: $e');
        debugPrint('Stack trace: $stackTrace');
      }
    });
  }

  @override
  void dispose() {
    debugPrint('🧹 MatchmakingScreen dispose called');
    _matchmakingProvider?.removeListener(_onMatchmakingUpdate);
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
            gradient: AppTheme.surfaceGradient,
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
                          ? AppTheme.success.withValues(alpha: 0.1)
                          : AppTheme.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: SocketService.isConnected 
                            ? AppTheme.success.withValues(alpha: 0.5)
                            : AppTheme.error.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          SocketService.isConnected ? Icons.wifi : Icons.wifi_off,
                          color: SocketService.isConnected 
                              ? AppTheme.success 
                              : AppTheme.error,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          SocketService.isConnected 
                              ? 'Connected'
                              : 'Not connected',
                          style: TextStyle(
                            color: SocketService.isConnected 
                                ? AppTheme.success 
                                : AppTheme.error,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),
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
                              AppTheme.primary.withValues(alpha: 0.2),
                              AppTheme.primary.withValues(alpha: 0.05),
                              Colors.transparent,
                            ],
                          ),
                          border: Border.all(
                            color: AppTheme.primary,
                            width: 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.primary.withValues(alpha: 0.2),
                              blurRadius: 20,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            ...List.generate(4, (index) {
                              final angle = (index * math.pi / 2);
                              return Transform.rotate(
                                angle: angle,
                                child: Container(
                                  width: 2,
                                  height: 200,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        Colors.transparent,
                                        AppTheme.primary.withValues(alpha: 0.5),
                                        Colors.transparent,
                                      ],
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                    ),
                                  ),
                                ),
                              );
                            }),
                            ...List.generate(2, (index) {
                              return Container(
                                width: 100 + (index * 60.0),
                                height: 100 + (index * 60.0),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: AppTheme.primary.withValues(alpha: 0.3),
                                    width: 1,
                                  ),
                                ),
                              );
                            }),
                            const Icon(
                              Icons.radar,
                              color: AppTheme.primary,
                              size: 48,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 48),
                  const Text(
                    'SEARCHING FOR OPPONENT',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _formatTime(matchmaking.searchTime),
                    style: const TextStyle(
                      color: AppTheme.primary,
                      fontSize: 48,
                      fontWeight: FontWeight.w900,
                      fontFamily: 'monospace', // Monospaced font for timer
                    ),
                  ),
                  const SizedBox(height: 32),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 20,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.background,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: AppTheme.surfaceLight.withValues(alpha: 0.5),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: IntrinsicHeight(
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              children: [
                                Text(
                                  'YOUR ELO',
                                  style: AppTheme.labelLarge.copyWith(color: AppTheme.textSecondary),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '${user?.elo ?? 0}',
                                  style: const TextStyle(
                                    color: AppTheme.primary,
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          VerticalDivider(color: AppTheme.surfaceLight.withValues(alpha: 0.5)),
                          Expanded(
                            child: Column(
                              children: [
                                Text(
                                  'RANGE',
                                  style: AppTheme.labelLarge.copyWith(color: AppTheme.textSecondary),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '±${matchmaking.eloRange}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
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
                        backgroundColor: AppTheme.error,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 4,
                      ),
                      child: const Text(
                        'CANCEL SEARCH',
                        style: TextStyle(
                          fontSize: 16,
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
                        color: AppTheme.error.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppTheme.error,
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.error_outline,
                            color: AppTheme.error,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              matchmaking.errorMessage!,
                              style: const TextStyle(
                                color: AppTheme.error,
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
