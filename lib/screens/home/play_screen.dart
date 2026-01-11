import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/matchmaking_provider.dart';
import '../../providers/game_provider.dart';
import '../../widgets/recent_matches_widget.dart';
import '../../services/user_service.dart';
import '../../models/match.dart';
import '../../utils/haptic_service.dart';
import '../../utils/app_theme.dart';
import '../matchmaking/matchmaking_screen.dart';

class PlayScreen extends StatefulWidget {
  const PlayScreen({super.key});

  @override
  State<PlayScreen> createState() => _PlayScreenState();
}

class _PlayScreenState extends State<PlayScreen> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  List<Match> _recentMatches = [];
  bool _loadingMatches = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeInOut,
      ),
    );
    
    _loadRecentMatches();
  }

  Future<void> _loadRecentMatches() async {
    setState(() => _loadingMatches = true);
    try {
      final auth = context.read<AuthProvider>();
      if (auth.currentUser?.id != null) {
        final matches = await UserService.getUserMatches(auth.currentUser!.id, limit: 3);
        if (mounted) {
          setState(() {
            _recentMatches = matches;
            _loadingMatches = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingMatches = false);
      }
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  String _getNextRank(String currentRank) {
    switch (currentRank.toLowerCase()) {
      case 'bronze':
        return 'Silver';
      case 'silver':
        return 'Gold';
      case 'gold':
        return 'Platinum';
      case 'platinum':
        return 'Diamond';
      case 'diamond':
        return 'Master';
      case 'master':
        return 'Master';
      default:
        return 'Bronze';
    }
  }

  int _getEloNeededForNextRank(String currentRank, int currentElo) {
    final Map<String, int> rankThresholds = {
      'bronze': 1400,
      'silver': 1600,
      'gold': 1800,
      'platinum': 2000,
      'diamond': 2200,
      'master': 2400,
    };

    final nextRank = _getNextRank(currentRank).toLowerCase();
    final threshold = rankThresholds[nextRank] ?? 1400;
    return threshold - currentElo;
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;

    if (user == null) {
      return const Center(
        child: Text('User not found'),
      );
    }

    final eloNeeded = _getEloNeededForNextRank(user.rank, user.elo);
    final nextRank = _getNextRank(user.rank);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: AppTheme.surfaceGradient,
              borderRadius: BorderRadius.circular(24),
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
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'NEXT RANK',
                          style: AppTheme.labelLarge.copyWith(color: AppTheme.textSecondary),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          nextRank.toUpperCase(),
                          style: AppTheme.titleLarge.copyWith(color: AppTheme.primary),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        eloNeeded > 0 ? '$eloNeeded ELO to go' : 'Max Rank!',
                        style: TextStyle(
                          color: AppTheme.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: eloNeeded > 0 ? (200 - eloNeeded) / 200 : 1.0, // Simplified progress
                    backgroundColor: AppTheme.surface,
                    valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primary),
                    minHeight: 8,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          ScaleTransition(
            scale: _pulseAnimation,
            child: GestureDetector(
              onTap: () async {
                HapticService.mediumImpact();
                
                final matchmaking = context.read<MatchmakingProvider>();
                final game = context.read<GameProvider>();
                final user = context.read<AuthProvider>().currentUser;
                
                if (user?.id != null) {
                  matchmaking.setGameProvider(game);
                  await matchmaking.joinQueue(user!.id);
                  
                  if (context.mounted) {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const MatchmakingScreen(),
                      ),
                    );
                  }
                }
              },
              child: Container(
                height: 180,
                decoration: BoxDecoration(
                  gradient: AppTheme.primaryGradient,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primary.withValues(alpha: 0.4),
                      blurRadius: 20,
                      spreadRadius: 2,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    Positioned(
                      right: -20,
                      top: -20,
                      child: Icon(
                        Icons.sports_esports,
                        size: 150,
                        color: Colors.white.withValues(alpha: 0.1),
                      ),
                    ),
                    Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.play_arrow_rounded,
                              size: 48,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'FIND MATCH',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 2,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Ranked Competitive',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.8),
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
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
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Recent Matches',
                style: AppTheme.titleLarge,
              ),
              if (!_loadingMatches)
                TextButton(
                  onPressed: () {
                    // Navigate to history tab via parent controller if possible, or just refresh
                    _loadRecentMatches();
                  },
                  child: const Text('Refresh'),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (_loadingMatches)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32.0),
                child: CircularProgressIndicator(color: AppTheme.primary),
              ),
            )
          else if (_recentMatches.isNotEmpty)
            RecentMatchesWidget(
              matches: _recentMatches,
              userId: user.id,
            )
          else
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.surfaceLight),
              ),
              child: Column(
                children: [
                  const Icon(Icons.history, size: 48, color: AppTheme.textSecondary),
                  const SizedBox(height: 16),
                  Text(
                    'No matches yet',
                    style: AppTheme.bodyLarge.copyWith(color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Play your first game to see history',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppTheme.surfaceLight.withValues(alpha: 0.5),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.tips_and_updates_outlined, color: AppTheme.primary),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Pro Tip',
                        style: TextStyle(
                          color: AppTheme.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Practice your doubles! They are crucial for closing out games.',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
