import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../widgets/rank_badge.dart';
import '../l10n/app_localizations.dart';
import '../utils/haptic_service.dart';
import '../utils/app_theme.dart';
import '../providers/friends_provider.dart';
import 'home/play_screen.dart';
import 'home/stats_screen.dart';
import 'home/leaderboard_screen.dart';
import 'home/friends_screen.dart';
import 'home/tournament_screen.dart';
import 'settings/settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 2; // Start at Play (now index 2)

  final List<Widget> _screens = const [
    StatsScreen(),
    TournamentScreen(),
    PlayScreen(),
    FriendsScreen(),
    LeaderboardScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final user = authProvider.currentUser;
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Container(
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                height: 80,
                child: Image.asset(
                  'assets/logo/logo-without-letters.png',
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                l10n.dartRivals,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                  fontSize: 20,
                ),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () {
              HapticService.lightImpact();
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const SettingsScreen(),
                ),
              );
            },
            tooltip: l10n.settingsTooltip,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          if (user != null)
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: AppTheme.surfaceGradient,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
                border: Border.all(
                  color: AppTheme.surfaceLight.withValues(alpha: 0.5),
                ),
              ),
              child: Row(
                children: [
                  RankBadge(
                    rank: user.rank,
                    size: 80,
                    showLabel: false,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      user.username,
                      style: AppTheme.titleLarge,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.background,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppTheme.primary.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          l10n.eloLabel,
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppTheme.textSecondary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${user.elo}',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                color: AppTheme.background,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
                child: _screens[_currentIndex],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppTheme.surface,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 20,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Container(
              decoration: BoxDecoration(
                color: AppTheme.surfaceLight.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildNavItem(0, Icons.bar_chart, Icons.bar_chart_rounded, l10n.stats),
                  _buildNavItem(1, Icons.emoji_events_outlined, Icons.emoji_events, l10n.tournament),
                  _buildNavItem(2, Icons.play_circle_outline, Icons.play_circle_filled, l10n.play),
                  _buildNavItem(3, Icons.people_outline, Icons.people, l10n.friends),
                  _buildNavItem(4, Icons.leaderboard_outlined, Icons.leaderboard, l10n.rankings),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, IconData activeIcon, String label) {
    final isSelected = _currentIndex == index;
    final isPlayTab = index == 2; // Play is middle tab
    final showCircle = isSelected && isPlayTab;
    final isFriendsTab = index == 3;
    
    return GestureDetector(
      onTap: () {
        HapticService.lightImpact();
        setState(() {
          _currentIndex = index;
        });
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: showCircle
                      ? BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.primary.withValues(alpha: 0.3),
                              blurRadius: 12,
                              spreadRadius: 2,
                            ),
                          ],
                        )
                      : null,
                  child: Center(
                    child: Icon(
                      isSelected ? activeIcon : icon,
                      color: isSelected ? AppTheme.primary : AppTheme.textSecondary,
                      size: 24,
                    ),
                  ),
                ),
                if (isFriendsTab)
                  Consumer<FriendsProvider>(
                    builder: (context, friendsProvider, _) {
                      final count = friendsProvider.pendingRequestsCount;
                      if (count == 0) return const SizedBox.shrink();
                      
                      return Positioned(
                        right: -2,
                        top: -2,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: AppTheme.error,
                            shape: BoxShape.circle,
                            border: Border.all(color: AppTheme.background, width: 2),
                          ),
                          constraints: const BoxConstraints(
                            minWidth: 20,
                            minHeight: 20,
                          ),
                          child: Center(
                            child: Text(
                              count > 9 ? '9+' : count.toString(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isSelected ? AppTheme.primary : AppTheme.textSecondary,
                fontSize: 9,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
