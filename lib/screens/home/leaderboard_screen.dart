import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/season_provider.dart';
import '../../models/season.dart';
import '../../services/user_service.dart';
import '../../services/friends_service.dart';
import '../../services/seasons_service.dart';
import '../../utils/app_navigator.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/rank_badge.dart';
import '../../widgets/premium_badge.dart';
import '../../widgets/season_card.dart';
import '../../widgets/season_chips.dart';
import '../../utils/app_theme.dart';
import '../../utils/haptic_service.dart';
import '../../utils/rank_translation.dart';
import '../profile/player_stats_screen.dart';
import 'seasons_screen.dart';

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  bool _isLoading = true;
  List<LeaderboardEntry> _entries = [];
  String? _errorMessage;
  bool _showFriendsOnly = false;

  /// Global ladder rank of the signed-in user (null while unranked/unknown).
  /// Only used on the legacy (no-season) path.
  int? _myGlobalPosition;

  /// Season whose ladder is shown; null = the active one. Set by the chips,
  /// by the seasons screen ("Standings ›") and by the home ring's
  /// "Final standings ›" through SeasonProvider.standingsRequest.
  int? _selectedSeason;

  /// My line in the displayed season (live for the active one, frozen for an
  /// archived one); null while unranked or not ranked in that season.
  SeasonStanding? _myStanding;

  @override
  void initState() {
    super.initState();
    final requested = context.read<SeasonProvider>().consumeStandingsRequest();
    if (requested != null) _selectedSeason = requested;
    _loadLeaderboard();
  }

  SeasonProvider get _seasonProvider => context.read<SeasonProvider>();

  /// The season the list is bound to, or null when the backend has no
  /// seasons yet (older deploy) — the screen then behaves as before.
  Season? _displayedSeason(SeasonProvider provider) {
    final active = provider.activeSeason;
    if (active == null) return null;
    final n = _selectedSeason;
    if (n == null || n == active.number) return active;
    for (final s in provider.seasons) {
      if (s.number == n) return s;
    }
    return active;
  }

  Future<void> _loadLeaderboard() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      if (_showFriendsOnly) {
        final friends = await FriendsService.getFriendsLeaderboard();
        final entries = friends.asMap().entries.map((entry) {
          final index = entry.key;
          final user = entry.value;
          return LeaderboardEntry(
            user: user,
            rank: index + 1,
            wins: user.wins,
            losses: user.losses,
          );
        }).toList();
        if (!mounted) return;
        setState(() {
          _entries = entries;
          _isLoading = false;
        });
      } else {
        final provider = _seasonProvider;
        // First load, or a requested season the provider has not listed yet
        // (the home ring can ask for a closed season before any refresh).
        final requested = _selectedSeason;
        if (provider.activeSeason == null ||
            (requested != null &&
                !provider.seasons.any((s) => s.number == requested))) {
          await provider.refresh();
        }
        if (!mounted) return;
        final season = _displayedSeason(provider);
        if (season != null) {
          // Season-aware ladder: W/L are the season's, positions come from
          // the backend (elo, season wins, username).
          final results = await Future.wait([
            SeasonsService.getStandings(season.number),
            SeasonsService.getMyStanding(season.number),
          ]);
          if (!mounted) return;
          setState(() {
            _entries = results[0] as List<LeaderboardEntry>;
            _myStanding = results[1] as SeasonStanding?;
            _isLoading = false;
          });
        } else {
          final entries = await UserService.getLeaderboard();
          final myPosition = await UserService.getMyLeaderboardPosition();
          if (!mounted) return;
          setState(() {
            _entries = entries;
            _myGlobalPosition = myPosition;
            _myStanding = null;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  void _openPlayer(LeaderboardEntry entry) {
    AppNavigator.toScreen(
      context,
      PlayerStatsScreen(
        userId: entry.user.id,
        username: entry.user.username,
      ),
    );
  }

  /// Pinned-row position: the season standing, the global rank from the
  /// backend (legacy path), or the index in the friends list.
  int? _myPosition(String? currentUserId) {
    if (_showFriendsOnly) {
      final index = _entries.indexWhere((e) => e.user.id == currentUserId);
      return index >= 0 ? index + 1 : null;
    }
    return _myStanding?.position ?? _myGlobalPosition;
  }

  void _selectSeason(int number) {
    final active = _seasonProvider.activeSeason;
    setState(() {
      _showFriendsOnly = false;
      _selectedSeason = active != null && number == active.number ? null : number;
    });
    _loadLeaderboard();
  }

  Future<void> _openSeasons(Season displayed) async {
    HapticService.lightImpact();
    final picked = await AppNavigator.toScreen<int>(
      context,
      SeasonsScreen(initialNumber: displayed.number),
    );
    if (!mounted || picked == null) return;
    _selectSeason(picked);
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = context.watch<AuthProvider>().currentUser;
    final l10n = AppLocalizations.of(context);
    final seasonProvider = context.watch<SeasonProvider>();
    final season = _displayedSeason(seasonProvider);
    final isArchived = season != null && season.isClosed && !_showFriendsOnly;

    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primary),
      );
    }

    if (_errorMessage != null) {
      return RefreshIndicator(
        onRefresh: _loadLeaderboard,
        color: AppTheme.primary,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: AppTheme.error, size: 64),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                style: const TextStyle(color: AppTheme.error),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadLeaderboard,
                child: Text(l10n.retry),
              ),
            ],
          ),
        ),
      );
    }

    final podium = _entries.take(3).toList();
    final rest = _entries.length > 3 ? _entries.sublist(3) : <LeaderboardEntry>[];
    final myPosition = _myPosition(currentUser?.id);

    final myStanding = _showFriendsOnly ? null : _myStanding;
    final list = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 12),
      children: [
        if (myStanding != null && currentUser != null)
          _MyCard(
            username: currentUser.username,
            standing: myStanding,
          ),
        if (isArchived) _FinalStandingsBanner(label: l10n.seasonFinalStandings),
        if (podium.length >= 3)
          _Podium(entries: podium, onTap: _openPlayer)
        else
          ...podium.asMap().entries.map(
                (e) => _LeaderboardRow(
                  entry: e.value,
                  isCurrentUser: e.value.user.id == currentUser?.id,
                  onTap: () => _openPlayer(e.value),
                ),
              ),
        ...rest.map(
          (entry) => _LeaderboardRow(
            entry: entry,
            isCurrentUser: entry.user.id == currentUser?.id,
            onTap: () => _openPlayer(entry),
          ),
        ),
      ],
    );

    return Column(
      children: [
        if (season != null) ...[
          // The season card replaces the title: what is being played and
          // when it ends. Tap → the posters.
          if (seasonProvider.activeSeason != null)
            SeasonCard(
              season: seasonProvider.activeSeason!,
              timeLeft: seasonProvider.timeLeft,
              onTap: () => _openSeasons(season),
            ),
          SeasonChips(
            seasons: seasonProvider.seasons.isNotEmpty
                ? seasonProvider.seasons
                : [seasonProvider.activeSeason!],
            selectedNumber: season.number,
            friendsOnly: _showFriendsOnly,
            onSeasonSelected: (number) {
              HapticService.lightImpact();
              _selectSeason(number);
            },
            onFriendsSelected: () {
              HapticService.lightImpact();
              setState(() => _showFriendsOnly = true);
              _loadLeaderboard();
            },
          ),
        ] else
          _ScopeToggle(
            showFriendsOnly: _showFriendsOnly,
            onChanged: (friendsOnly) {
              HapticService.lightImpact();
              setState(() => _showFriendsOnly = friendsOnly);
              _loadLeaderboard();
            },
          ),
        Expanded(
          child: _entries.isEmpty
              ? _EmptyState(showFriendsOnly: _showFriendsOnly, l10n: l10n)
              : Column(
                  children: [
                    Expanded(
                      // A frozen ladder never changes: no pull-to-refresh.
                      child: isArchived
                          ? list
                          : RefreshIndicator(
                              onRefresh: _loadLeaderboard,
                              color: AppTheme.primary,
                              child: list,
                            ),
                    ),
                    if (myPosition != null && currentUser != null)
                      _PinnedPositionRow(
                        position: myPosition,
                        username: currentUser.username,
                        rank: myStanding?.rank ?? currentUser.rank,
                        elo: myStanding?.elo ?? currentUser.elo,
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// "Your card" under the chips: rank badge, name · rank, season W/L, your
/// position and ELO in the displayed season.
class _MyCard extends StatelessWidget {
  final String username;
  final SeasonStanding standing;

  const _MyCard({required this.username, required this.standing});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.surfaceLight.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          RankBadge(rank: standing.rank, size: 40, showLabel: false),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    text: username,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                    children: [
                      TextSpan(
                        text: ' · ${RankTranslation.translate(l10n, standing.rank)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w500,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 1),
                Text(
                  l10n.seasonWinsLosses(standing.wins, standing.losses),
                  style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
          Text(
            '#${standing.position}',
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: AppTheme.primary,
            ),
          ),
          Container(
            width: 1,
            height: 34,
            margin: const EdgeInsets.symmetric(horizontal: 12),
            color: AppTheme.surfaceLight.withValues(alpha: 0.8),
          ),
          Text(
            '${standing.elo}',
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Thin banner above an archived ladder.
class _FinalStandingsBanner extends StatelessWidget {
  final String label;

  const _FinalStandingsBanner({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          const Icon(Icons.lock_outline, size: 13, color: AppTheme.textSecondary),
          const SizedBox(width: 6),
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.5,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact Mondial | Amis segmented control — replaces the old title card.
class _ScopeToggle extends StatelessWidget {
  final bool showFriendsOnly;
  final ValueChanged<bool> onChanged;

  const _ScopeToggle({required this.showFriendsOnly, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    Widget segment(String label, IconData icon, bool selected, VoidCallback onTap) {
      return Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: selected ? AppTheme.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: AppTheme.primary.withValues(alpha: 0.4),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: selected ? Colors.white : AppTheme.textSecondary,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: selected ? Colors.white : AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: AppTheme.surfaceLight.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          segment(l10n.global, Icons.public, !showFriendsOnly,
              () => onChanged(false)),
          segment(l10n.friends, Icons.people, showFriendsOnly,
              () => onChanged(true)),
        ],
      ),
    );
  }
}

/// Top 3 staged on gold/silver/bronze pedestals, winner raised in the middle.
class _Podium extends StatelessWidget {
  final List<LeaderboardEntry> entries;
  final void Function(LeaderboardEntry) onTap;

  const _Podium({required this.entries, required this.onTap});

  static const _gold = Color(0xFFFFD700);
  static const _silver = Color(0xFFC0C0C0);
  static const _bronze = Color(0xFFCD7F32);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: _PodiumSpot(
              entry: entries[1],
              place: 2,
              color: _silver,
              badgeSize: 44,
              baseHeight: 34,
              onTap: () => onTap(entries[1]),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _PodiumSpot(
              entry: entries[0],
              place: 1,
              color: _gold,
              badgeSize: 60,
              baseHeight: 50,
              crowned: true,
              onTap: () => onTap(entries[0]),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _PodiumSpot(
              entry: entries[2],
              place: 3,
              color: _bronze,
              badgeSize: 40,
              baseHeight: 26,
              onTap: () => onTap(entries[2]),
            ),
          ),
        ],
      ),
    );
  }
}

class _PodiumSpot extends StatelessWidget {
  final LeaderboardEntry entry;
  final int place;
  final Color color;
  final double badgeSize;
  final double baseHeight;
  final bool crowned;
  final VoidCallback onTap;

  const _PodiumSpot({
    required this.entry,
    required this.place,
    required this.color,
    required this.badgeSize,
    required this.baseHeight,
    this.crowned = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (crowned)
            const Padding(
              padding: EdgeInsets.only(bottom: 2),
              child: Text('👑', style: TextStyle(fontSize: 14)),
            ),
          Container(
            decoration: crowned
                ? BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.45),
                        blurRadius: 18,
                        spreadRadius: 1,
                      ),
                    ],
                  )
                : null,
            child: RankBadge(rank: entry.user.rank, size: badgeSize, showLabel: false),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  entry.user.username,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              PremiumBadge(isPremium: entry.user.isPremiumActive, size: 11),
            ],
          ),
          Text(
            '${entry.user.elo}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: place == 1 ? color : AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 5),
          Container(
            height: baseHeight,
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(9)),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  color.withValues(alpha: 0.35),
                  color.withValues(alpha: 0.07),
                ],
              ),
            ),
            child: Center(
              child: Text(
                '$place',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Dense list row from 4th place on.
class _LeaderboardRow extends StatelessWidget {
  final LeaderboardEntry entry;
  final bool isCurrentUser;
  final VoidCallback onTap;

  const _LeaderboardRow({
    required this.entry,
    required this.isCurrentUser,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isCurrentUser ? AppTheme.primary.withValues(alpha: 0.1) : null,
          border: Border(
            left: BorderSide(
              color: isCurrentUser ? AppTheme.primary : Colors.transparent,
              width: 3,
            ),
            bottom: BorderSide(
              color: AppTheme.surfaceLight.withValues(alpha: 0.35),
            ),
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 30,
              // scaleDown keeps 3+ digit ranks ("100") on a single line.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '${entry.rank}',
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: isCurrentUser ? AppTheme.primary : AppTheme.textSecondary,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            RankBadge(rank: entry.user.rank, size: 24, showLabel: false),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          entry.user.username,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: isCurrentUser ? AppTheme.primary : Colors.white,
                          ),
                        ),
                      ),
                      PremiumBadge(
                          isPremium: entry.user.isPremiumActive, size: 12),
                    ],
                  ),
                  Text(
                    '${entry.wins}${l10n.formWinLetter} - ${entry.losses}${l10n.formLossLetter}',
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '${entry.user.elo}',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: isCurrentUser ? AppTheme.primary : AppTheme.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Always-visible "your position" row docked under the list.
class _PinnedPositionRow extends StatelessWidget {
  final int position;
  final String username;
  final String rank;
  final int elo;

  const _PinnedPositionRow({
    required this.position,
    required this.username,
    required this.rank,
    required this.elo,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFF12233B),
        border: Border(
          top: BorderSide(color: AppTheme.primary.withValues(alpha: 0.4)),
        ),
      ),
      child: Row(
        children: [
          Text(
            l10n.positionOrdinal(position),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(width: 10),
          RankBadge(rank: rank, size: 24, showLabel: false),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$username — ${l10n.yourPosition}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
          Text(
            '$elo',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppTheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool showFriendsOnly;
  final AppLocalizations l10n;

  const _EmptyState({required this.showFriendsOnly, required this.l10n});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            showFriendsOnly ? Icons.people_outline : Icons.leaderboard_outlined,
            size: 64,
            color: AppTheme.textSecondary.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            showFriendsOnly ? 'No friends yet' : 'No leaderboard data available',
            style: AppTheme.titleLarge.copyWith(color: AppTheme.textSecondary),
          ),
          if (showFriendsOnly) ...[
            const SizedBox(height: 8),
            const Text(
              'Add friends to see their rankings!',
              style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}
