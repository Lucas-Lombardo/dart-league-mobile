import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/recent_matches_widget.dart';
import '../../services/user_service.dart';
import '../../services/match_service.dart';
import '../../services/tournament_service.dart';
import '../../models/match.dart';
import '../../models/tournament.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/haptic_service.dart';
import '../../utils/app_theme.dart';
import '../../utils/rank_utils.dart';
import '../matchmaking/camera_setup_screen.dart';
import '../placement/placement_hub_screen.dart';
import '../tournament/tournament_camera_setup_screen.dart';

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
  Map<String, dynamic>? _activeMatch;
  TournamentMatch? _pendingTournamentMatch;
  bool _inActiveTournament = false;
  String? _activeTournamentName;

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
    _checkActiveMatch();
    _checkPendingTournamentMatch();
    _checkActiveTournamentStatus();
  }

  Future<void> _checkActiveMatch() async {
    try {
      final auth = context.read<AuthProvider>();
      if (auth.currentUser?.id != null) {
        final result = await MatchService.getActiveMatch(auth.currentUser!.id);
        if (mounted) {
          setState(() {
            _activeMatch = (result['active'] == true) ? result : null;
          });
        }
      }
    } catch (e) {
      // Failed to check for active match
    }
  }

  Future<void> _checkPendingTournamentMatch() async {
    try {
      final matches = await TournamentService.getPendingMatches();
      if (mounted) {
        setState(() {
          _pendingTournamentMatch = matches.isNotEmpty ? matches.first : null;
        });
      }
    } catch (e) {
      // Failed to check for pending tournament match
    }
  }

  Future<void> _checkActiveTournamentStatus() async {
    try {
      final status = await TournamentService.getActiveTournamentStatus();
      if (mounted) {
        setState(() {
          _inActiveTournament = status['inActiveTournament'] as bool? ?? false;
          _activeTournamentName = status['tournamentName'] as String?;
        });
      }
    } catch (e) {
      // Failed to check tournament status
    }
  }

  Future<void> _rejoinMatch() async {
    if (_activeMatch == null) return;

    HapticService.mediumImpact();

    final matchId = _activeMatch!['matchId'] as String?;
    final opponentId = _activeMatch!['opponentId'] as String?;
    final opponentUsername = _activeMatch!['opponentUsername'] as String?;

    if (matchId == null) return;

    if (mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => CameraSetupScreen(
            rejoinMatchId: matchId,
            rejoinOpponentId: opponentId,
            rejoinOpponentUsername: opponentUsername,
          ),
        ),
      );
    }
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

  String _getPreviousRank(String currentRank) {
    switch (currentRank.toLowerCase()) {
      case 'silver':
        return 'Bronze';
      case 'gold':
        return 'Silver';
      case 'platinum':
        return 'Gold';
      case 'diamond':
        return 'Platinum';
      case 'master':
        return 'Diamond';
      case 'bronze':
      default:
        return 'Bronze';
    }
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

  Map<String, int> get _rankThresholds => {
    'bronze': 0,
    'silver': 1000,
    'gold': 1500,
    'platinum': 2000,
    'diamond': 2500,
    'master': 3000,
  };

  int _getEloNeededForNextRank(String currentRank, int currentElo) {
    final nextRank = _getNextRank(currentRank).toLowerCase();
    final threshold = _rankThresholds[nextRank] ?? 1400;
    return threshold - currentElo;
  }

  int _getEloBelowPreviousRank(String currentRank, int currentElo) {
    final currentThreshold = _rankThresholds[currentRank.toLowerCase()] ?? 0;
    return currentThreshold - currentElo;
  }

  double _getRankProgress(String currentRank, int currentElo) {
    final currentThreshold = _rankThresholds[currentRank.toLowerCase()] ?? 1200;
    final nextRank = _getNextRank(currentRank).toLowerCase();
    final nextThreshold = _rankThresholds[nextRank] ?? 1400;
    
    if (currentRank.toLowerCase() == 'master' && currentElo >= nextThreshold) {
      return 1.0;
    }
    
    final rangeSize = nextThreshold - currentThreshold;
    final progress = (currentElo - currentThreshold) / rangeSize;
    return progress.clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;
    final l10n = AppLocalizations.of(context);

    if (user == null) {
      return const Center(
        child: Text('User not found'),
      );
    }

    final eloNeeded = _getEloNeededForNextRank(user.rank, user.elo);
    final previousRank = _getPreviousRank(user.rank);
    final currentRank = user.rank;
    final nextRank = _getNextRank(user.rank);
    final progress = _getRankProgress(user.rank, user.elo);

    final isUnranked = user.rank.toLowerCase() == 'unranked';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isUnranked)
            // Unranked: Placement prompt
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: AppTheme.surfaceGradient,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: AppTheme.accent.withValues(alpha: 0.5),
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
                  const Icon(Icons.emoji_events, size: 48, color: AppTheme.accent),
                  const SizedBox(height: 12),
                  Text(l10n.placementMatches, style: AppTheme.displayMedium),
                  const SizedBox(height: 8),
                  Text(
                    l10n.completePlacementToUnlock,
                    textAlign: TextAlign.center,
                    style: AppTheme.bodyLarge,
                  ),
                ],
              ),
            )
          else
            // Ranked: Normal rank progression
            Container(
            padding: const EdgeInsets.all(16),
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
                // Rank Progression
                Column(
                  children: [
                    // Rank badges row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        // Previous Rank
                        Opacity(
                          opacity: 0.5,
                          child: Column(
                            children: [
                              SizedBox(
                                width: 70,
                                height: 70,
                                child: RankUtils.getRankBadge(
                                  previousRank,
                                  size: 70,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '-${_getEloBelowPreviousRank(currentRank, user.elo).abs()}',
                                style: const TextStyle(
                                  color: Color(0xFFEF4444),
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        
                        // Current Rank
                        Column(
                          children: [
                            SizedBox(
                              width: 100,
                              height: 100,
                              child: RankUtils.getRankBadge(
                                currentRank,
                                size: 100,
                              ),
                            ),
                            const SizedBox(height: 4),
                          ],
                        ),
                        
                        // Next Rank
                        Opacity(
                          opacity: 0.3,
                          child: Column(
                            children: [
                              SizedBox(
                                width: 75,
                                height: 75,
                                child: RankUtils.getRankBadge(
                                  nextRank,
                                  size: 75,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '+${eloNeeded > 0 ? eloNeeded : 0}',
                                style: TextStyle(
                                  color: AppTheme.primary.withValues(alpha: 0.8),
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 8),
                    
                    // Progress bar
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Stack(
                        children: [
                          // Background bar
                          Container(
                            height: 12,
                            decoration: BoxDecoration(
                              color: AppTheme.surface,
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          // Progress bar
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: FractionallySizedBox(
                              widthFactor: progress,
                              child: Container(
                                height: 12,
                                decoration: BoxDecoration(
                                  gradient: AppTheme.primaryGradient,
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppTheme.primary.withValues(alpha: 0.4),
                                      blurRadius: 8,
                                      spreadRadius: 1,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          if (isUnranked)
            // Placement Matches button
            ScaleTransition(
              scale: _pulseAnimation,
              child: GestureDetector(
                onTap: () {
                  HapticService.mediumImpact();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const PlacementHubScreen(),
                    ),
                  ).then((_) {
                    // Reload matches and user data after returning
                    _loadRecentMatches();
                    context.read<AuthProvider>().checkAuthStatus();
                  });
                },
                child: Container(
                  height: 180,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFEAB308), Color(0xFFF59E0B)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFEAB308).withValues(alpha: 0.4),
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
                          Icons.emoji_events,
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
                            Text(
                              l10n.placementMatches.toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 2,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              l10n.completePlacementToUnlock,
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
            )
          else if (_pendingTournamentMatch != null)
            // Join Tournament Match button (highest priority after placement)
            ScaleTransition(
              scale: _pulseAnimation,
              child: GestureDetector(
                onTap: () {
                  HapticService.mediumImpact();
                  final match = _pendingTournamentMatch!;
                  final auth = context.read<AuthProvider>();
                  final currentUserId = auth.currentUser?.id;
                  final isPlayer1 = currentUserId == match.player1Id;
                  final opponentUsername = isPlayer1 ? (match.player2Username ?? 'Opponent') : (match.player1Username ?? 'Opponent');
                  final opponentId = isPlayer1 ? (match.player2Id ?? '') : (match.player1Id ?? '');

                  if (context.mounted) {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => TournamentCameraSetupScreen(
                          matchId: match.id,
                          tournamentId: match.tournamentId,
                          tournamentName: match.tournamentName ?? 'Tournament',
                          roundName: match.roundName,
                          opponentUsername: opponentUsername,
                          opponentId: opponentId,
                          player1Id: match.player1Id ?? '',
                          player2Id: match.player2Id ?? '',
                          bestOf: match.bestOf,
                          inviteSentAt: match.inviteSentAt,
                        ),
                      ),
                    );
                  }
                },
                child: Container(
                  height: 180,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF7C3AED), Color(0xFF9333EA)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF7C3AED).withValues(alpha: 0.4),
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
                          Icons.emoji_events,
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
                              'JOIN MATCH',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 2,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${_pendingTournamentMatch!.tournamentName ?? 'Tournament'} — ${_pendingTournamentMatch!.roundNameDisplay}',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.8),
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else if (_activeMatch != null)
            // Rejoin active ranked match
            ScaleTransition(
              scale: _pulseAnimation,
              child: GestureDetector(
                onTap: _rejoinMatch,
                child: Container(
                  height: 180,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFF6B00), Color(0xFFFF9500)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFF6B00).withValues(alpha: 0.4),
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
                          Icons.refresh,
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
                                Icons.arrow_forward_rounded,
                                size: 48,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'PLAY',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 2,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Rejoin vs ${_activeMatch!['opponentUsername']}',
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
            )
          else if (_inActiveTournament)
            // Blocked: In active tournament
            Container(
              height: 180,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppTheme.surfaceLight.withValues(alpha: 0.8),
                    AppTheme.surface,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppTheme.surfaceLight),
              ),
              child: Stack(
                children: [
                  Positioned(
                    right: -20,
                    top: -20,
                    child: Icon(
                      Icons.block,
                      size: 150,
                      color: Colors.white.withValues(alpha: 0.05),
                    ),
                  ),
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppTheme.accent.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.emoji_events,
                            size: 40,
                            color: AppTheme.accent,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'RANKED LOCKED',
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Active tournament: ${_activeTournamentName ?? 'In Progress'}',
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 13,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )
          else
            // Find Match button
            ScaleTransition(
              scale: _pulseAnimation,
              child: GestureDetector(
                onTap: () async {
                  HapticService.mediumImpact();
                  
                  if (context.mounted) {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const CameraSetupScreen(),
                      ),
                    );
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
                              'PLAY',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 2,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              l10n.rankedCompetitive,
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
                l10n.recentMatches,
                style: AppTheme.titleLarge,
              ),
              if (!_loadingMatches)
                TextButton(
                  onPressed: () {
                    // Navigate to history tab via parent controller if possible, or just refresh
                    _loadRecentMatches();
                  },
                  child: Text(l10n.refresh),
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
                    l10n.noMatchesYet,
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
