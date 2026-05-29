import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../providers/matchmaking_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/subscription_provider.dart';
import '../../services/socket_service.dart';
import '../settings/subscription_screen.dart';
import '../training/training_select_screen.dart';
import '../../utils/app_theme.dart';
import '../../utils/haptic_service.dart';
import '../../utils/orientation_utils.dart';
import '../../l10n/app_localizations.dart';

class MatchmakingScreen extends StatefulWidget {
  const MatchmakingScreen({super.key});

  @override
  State<MatchmakingScreen> createState() => _MatchmakingScreenState();
}

class _MatchmakingScreenState extends State<MatchmakingScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late AnimationController _rotationController;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  MatchmakingProvider? _matchmakingProvider;
  String? _userId;

  /// True when another screen (a training launched via "Train while you wait")
  /// is on top of this one. While that's the case we must NOT leave the queue or
  /// pop on lifecycle/back events — the player is still queued, just elsewhere.
  bool get _isCurrent => ModalRoute.of(context)?.isCurrent ?? true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Keep the screen awake while in queue — without this the phone goes
    // to sleep if the user doesn't touch the screen and they miss the match.
    WakelockPlus.enable();
    OrientationUtils.allowAll();

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

    _userId ??= context.read<AuthProvider>().currentUser?.id;
    _matchmakingProvider ??= context.read<MatchmakingProvider>();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Only react while this screen is on top. If a "Train while you wait"
    // screen is above us, leaving the queue / popping here would wrongly cancel
    // the search and pop the training screen.
    if (state == AppLifecycleState.paused && _isCurrent) {
      final userId = _userId;
      if (userId != null) {
        _matchmakingProvider?.leaveQueue(userId);
      }
      if (mounted) Navigator.of(context).pop();
    }
  }

  /// Opens the training menu without leaving the queue. Match-found navigation
  /// is owned globally by [MatchmakingNavigationGate], so when an opponent is
  /// found the player is pulled out of the training and into the match
  /// automatically — regardless of which training screen they're on.
  void _openTrainingWhileWaiting() {
    HapticService.mediumImpact();
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const TrainingSelectScreen()),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _rotationController.dispose();
    _pulseController.dispose();
    // Releasing the wakelock here is safe: when match-found navigation pushes
    // GameScreen (which enables its own wakelock), the gate re-asserts the
    // wakelock post-frame, so this disable can't leave the match able to sleep.
    WakelockPlus.disable();
    OrientationUtils.portraitOnly();
    super.dispose();
  }

  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(1, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  Widget _buildDailyLimitErrorCard(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFC107), Color(0xFFEAB308)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFEAB308).withValues(alpha: 0.4),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          const Icon(Icons.workspace_premium, size: 36, color: Colors.white),
          const SizedBox(height: 8),
          Text(
            l10n.dailyLimitReachedShort,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${l10n.goPremiumUnlimited}.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 13,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () async {
                HapticService.mediumImpact();
                final user = context.read<AuthProvider>().currentUser;
                if (user?.id != null) {
                  await context.read<MatchmakingProvider>().leaveQueue(user!.id);
                }
                if (!context.mounted) return;
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const SubscriptionScreen()),
                ).then((_) {
                  if (context.mounted) {
                    context.read<SubscriptionProvider>().refresh();
                  }
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFFEAB308),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(
                l10n.upgradeToPremium,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, letterSpacing: 0.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final matchmaking = context.watch<MatchmakingProvider>();
    final user = context.watch<AuthProvider>().currentUser;
    final dailyLimitReached =
        matchmaking.errorMessage?.contains('DAILY_MATCH_LIMIT_REACHED') ?? false;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop && mounted && user?.id != null) {
          await matchmaking.leaveQueue(user!.id);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(AppLocalizations.of(context).findingMatch),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () async {
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
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: dailyLimitReached
                  ? Center(child: _buildDailyLimitErrorCard(context))
                  : Column(
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
                              ? AppLocalizations.of(context).connected
                              : AppLocalizations.of(context).disconnected,
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
                  const SizedBox(height: 12),
                  Expanded(
                    child: Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: AnimatedBuilder(
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
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  Text(
                    AppLocalizations.of(context).searchingForOpponentUpper,
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
                      fontSize: 44,
                      fontWeight: FontWeight.w900,
                      fontFamily: 'monospace', // Monospaced font for timer
                    ),
                  ),
                  const SizedBox(height: 16),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _openTrainingWhileWaiting,
                      borderRadius: BorderRadius.circular(18),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFF59E0B), Color(0xFFEAB308)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFEAB308).withValues(alpha: 0.4),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.22),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.sports_esports,
                                  color: Colors.white, size: 26),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    AppLocalizations.of(context).trainWhileWaiting,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    AppLocalizations.of(context)
                                        .trainWhileWaitingSubtitle,
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.92),
                                      fontSize: 12.5,
                                      height: 1.25,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right, color: Colors.white),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
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
                                  AppLocalizations.of(context).yourElo,
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
                                  AppLocalizations.of(context).eloRange,
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
                                const SizedBox(height: 4),
                                Text(
                                  AppLocalizations.of(context).eloRangeExpandingHint,
                                  style: const TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 10,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: () async {
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
                      child: Text(
                        AppLocalizations.of(context).cancelSearch,
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
