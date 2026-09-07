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
import '../../widgets/design_system.dart';
import '../../widgets/rank_badge.dart';
import '../../widgets/premium_badge.dart';
import '../../widgets/season_card.dart';
import '../../widgets/season_chips.dart';
import '../../utils/app_theme.dart';
import '../../utils/haptic_service.dart';
import '../../utils/rank_translation.dart';
import '../profile/player_stats_screen.dart';
import 'seasons_screen.dart';

/// Every figure on this screen (positions, ELO, W/L) is tabular.
const _tabular = [FontFeature.tabularFigures()];

/// Slate 200 — the quiet white of list-row figures.
const _figure = Color(0xFFE2E8F0);

/// Hairline between two list rows.
const _rowHairline = Color(0x59334155);

/// "Ta position" → "ta position" after a "·" mid-line.
String _lowerFirst(String s) =>
    s.isEmpty ? s : s[0].toLowerCase() + s.substring(1);

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

  /// The header's people button: Friends ⇄ the selected season's ladder.
  void _setFriendsOnly(bool friendsOnly) {
    if (friendsOnly == _showFriendsOnly) return;
    setState(() => _showFriendsOnly = friendsOnly);
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
    final l10n = AppLocalizations.of(context);

    return Column(
      children: [
        // The shell draws no header for this tab; the people button is the
        // friends-scope toggle (lit while the friends ladder is shown).
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: DsScreenHeader(
            title: l10n.rankings,
            actions: [
              DsIconButton(
                icon: Icons.people_outline_rounded,
                tooltip: l10n.friends,
                iconColor: _showFriendsOnly ? AppTheme.primaryLight : null,
                onTap: _isLoading ? null : () => _setFriendsOnly(!_showFriendsOnly),
              ),
            ],
          ),
        ),
        Expanded(child: _buildBody(context, l10n)),
      ],
    );
  }

  Widget _buildBody(BuildContext context, AppLocalizations l10n) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primary),
      );
    }

    if (_errorMessage != null) {
      return _ErrorState(
        message: _errorMessage!,
        retryLabel: l10n.retry,
        onRetry: _loadLeaderboard,
      );
    }

    final currentUser = context.watch<AuthProvider>().currentUser;
    final seasonProvider = context.watch<SeasonProvider>();
    final season = _displayedSeason(seasonProvider);
    final isArchived = season != null && season.isClosed && !_showFriendsOnly;

    final podium = _entries.take(3).toList();
    final rest = _entries.length > 3 ? _entries.sublist(3) : <LeaderboardEntry>[];
    final myPosition = _myPosition(currentUser?.id);
    final myStanding = _showFriendsOnly ? null : _myStanding;

    final list = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      children: [
        if (myStanding != null && currentUser != null) ...[
          LeaderboardMyCard(username: currentUser.username, standing: myStanding),
          const SizedBox(height: 14),
        ],
        if (isArchived) ...[
          _FinalStandingsBanner(label: l10n.seasonFinalStandings),
          const SizedBox(height: 10),
        ],
        if (podium.length >= 3) ...[
          LeaderboardPodium(entries: podium, onTap: _openPlayer),
          const SizedBox(height: 6),
        ] else
          ...podium.map(
            (entry) => LeaderboardRow(
              entry: entry,
              isCurrentUser: entry.user.id == currentUser?.id,
              onTap: () => _openPlayer(entry),
            ),
          ),
        ...rest.map(
          (entry) => LeaderboardRow(
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: SeasonChips(
              seasons: seasonProvider.seasons.isNotEmpty
                  ? seasonProvider.seasons
                  : [seasonProvider.activeSeason!],
              selectedNumber: season.number,
              friendsOnly: _showFriendsOnly,
              onSeasonSelected: (number) {
                HapticService.lightImpact();
                _selectSeason(number);
              },
              onSeeAll: () => _openSeasons(season),
            ),
          ),
          // What is being played and when it ends. Tap → the posters.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: SeasonCard(
              season: seasonProvider.activeSeason!,
              timeLeft: seasonProvider.timeLeft,
              onTap: () => _openSeasons(season),
            ),
          ),
        ] else
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: _ScopeToggle(
              showFriendsOnly: _showFriendsOnly,
              onChanged: (friendsOnly) {
                HapticService.lightImpact();
                _setFriendsOnly(friendsOnly);
              },
            ),
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
                      LeaderboardPinnedRow(
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

/// "Your card" under the season card: badge, name · rank, season W/L, your
/// position and ELO in the displayed season. Public for the preview harness.
@visibleForTesting
class LeaderboardMyCard extends StatelessWidget {
  final String username;
  final SeasonStanding standing;

  const LeaderboardMyCard({
    super.key,
    required this.username,
    required this.standing,
  });

  static const _figureStyle = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w800,
    color: AppTheme.textPrimary,
    height: 1,
    fontFeatures: _tabular,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SizedBox(
      height: 60,
      child: DsCard(
        radius: AppTheme.radiusRow,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            RankBadge(rank: standing.rank, size: 36, showLabel: false),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(
                      text: username,
                      style: AppTheme.rowTitle,
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
                  const SizedBox(height: 2),
                  Text(
                    l10n.seasonWinsLosses(standing.wins, standing.losses),
                    style: AppTheme.caption,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '#${standing.position}',
              style: _figureStyle.copyWith(color: AppTheme.primaryLight),
            ),
            Container(
              width: 1,
              height: 28,
              margin: const EdgeInsets.symmetric(horizontal: 12),
              color: AppTheme.border,
            ),
            Text('${standing.elo}', style: _figureStyle),
          ],
        ),
      ),
    );
  }
}

/// Thin group label above an archived ladder.
class _FinalStandingsBanner extends StatelessWidget {
  final String label;

  const _FinalStandingsBanner({required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.lock_outline_rounded, size: 13, color: AppTheme.textSecondary),
        const SizedBox(width: 6),
        Text(label.toUpperCase(), style: AppTheme.labelSmall),
      ],
    );
  }
}

/// Legacy (no seasons backend) Global | Friends segmented control.
class _ScopeToggle extends StatelessWidget {
  final bool showFriendsOnly;
  final ValueChanged<bool> onChanged;

  const _ScopeToggle({required this.showFriendsOnly, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    Widget segment(String label, IconData icon, bool selected, VoidCallback onTap) {
      final color = selected ? AppTheme.textPrimary : AppTheme.textSecondary;
      return Expanded(
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            height: 32,
            decoration: BoxDecoration(
              color: selected ? AppTheme.surfaceLight : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          segment(l10n.global, Icons.public_rounded, !showFriendsOnly,
              () => onChanged(false)),
          segment(l10n.friends, Icons.people_outline_rounded, showFriendsOnly,
              () => onChanged(true)),
        ],
      ),
    );
  }
}

/// Top 3 staged on gold / silver / bronze pedestals, winner raised in the
/// middle. Public for the preview harness.
@visibleForTesting
class LeaderboardPodium extends StatelessWidget {
  /// The first three entries, in rank order.
  final List<LeaderboardEntry> entries;
  final void Function(LeaderboardEntry) onTap;

  const LeaderboardPodium({
    super.key,
    required this.entries,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: _PodiumSpot(
            entry: entries[1],
            place: 2,
            metal: AppTheme.silver,
            badgeSize: 44,
            baseHeight: 40,
            onTap: () => onTap(entries[1]),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _PodiumSpot(
            entry: entries[0],
            place: 1,
            metal: AppTheme.gold,
            badgeSize: 60,
            baseHeight: 58,
            onTap: () => onTap(entries[0]),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _PodiumSpot(
            entry: entries[2],
            place: 3,
            metal: AppTheme.bronze,
            badgeSize: 40,
            baseHeight: 30,
            onTap: () => onTap(entries[2]),
          ),
        ),
      ],
    );
  }
}

class _PodiumSpot extends StatelessWidget {
  final LeaderboardEntry entry;
  final int place;
  final Color metal;
  final double badgeSize;
  final double baseHeight;
  final VoidCallback onTap;

  const _PodiumSpot({
    required this.entry,
    required this.place,
    required this.metal,
    required this.badgeSize,
    required this.baseHeight,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          RankBadge(rank: entry.user.rank, size: badgeSize, showLabel: false),
          const SizedBox(height: 6),
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
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
              PremiumBadge(
                isPremium: entry.user.isPremiumActive,
                size: 11,
                color: AppTheme.accent,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${entry.user.elo}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: place == 1 ? AppTheme.gold : _figure,
              height: 1,
              fontFeatures: _tabular,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            height: baseHeight,
            width: double.infinity,
            alignment: Alignment.topCenter,
            padding: const EdgeInsets.only(top: 8),
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  metal.withValues(alpha: 0.19),
                  metal.withValues(alpha: 0.04),
                ],
              ),
            ),
            child: Text(
              '$place',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: metal,
                height: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Dense 46 px list row from 4th place on, hairline below. My own row is
/// tinted primary. Public for the preview harness.
@visibleForTesting
class LeaderboardRow extends StatelessWidget {
  final LeaderboardEntry entry;
  final bool isCurrentUser;
  final VoidCallback onTap;

  const LeaderboardRow({
    super.key,
    required this.entry,
    required this.isCurrentUser,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final nameColor = isCurrentUser ? AppTheme.primaryLight : AppTheme.textPrimary;
    final figureColor = isCurrentUser ? AppTheme.primaryLight : _figure;
    final positionColor = isCurrentUser ? AppTheme.primaryLight : AppTheme.textSecondary;
    final captionColor = isCurrentUser ? AppTheme.primaryLight : AppTheme.textTertiary;

    return Column(
      children: [
        Material(
          color: isCurrentUser
              ? AppTheme.primary.withValues(alpha: 0.10)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              height: 46,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 24,
                      // scaleDown keeps 3+ digit positions ("100") on one line.
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '${entry.rank}',
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: positionColor,
                            fontFeatures: _tabular,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    RankBadge(rank: entry.user.rank, size: 24, showLabel: false),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
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
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: nameColor,
                                    height: 1.1,
                                  ),
                                ),
                              ),
                              PremiumBadge(
                                isPremium: entry.user.isPremiumActive,
                                size: 11,
                                color: AppTheme.accent,
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            l10n.seasonWinsLosses(entry.wins, entry.losses),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: captionColor,
                              height: 1.1,
                              fontFeatures: _tabular,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${entry.user.elo}',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: figureColor,
                        fontFeatures: _tabular,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 1, width: double.infinity, child: ColoredBox(color: _rowHairline)),
      ],
    );
  }
}

/// Always-visible "your position" row docked under the list, above the
/// bottom bar. Public for the preview harness.
@visibleForTesting
class LeaderboardPinnedRow extends StatelessWidget {
  final int position;
  final String username;
  final String rank;
  final int elo;

  const LeaderboardPinnedRow({
    super.key,
    required this.position,
    required this.username,
    required this.rank,
    required this.elo,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF12233B),
        border: Border(
          top: BorderSide(color: AppTheme.primaryLight.withValues(alpha: 0.4)),
        ),
      ),
      child: Row(
        children: [
          Text(
            l10n.positionOrdinal(position),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppTheme.primaryLight,
              fontFeatures: _tabular,
            ),
          ),
          const SizedBox(width: 12),
          RankBadge(rank: rank, size: 26, showLabel: false),
          const SizedBox(width: 12),
          Expanded(
            child: Text.rich(
              TextSpan(
                text: username,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
                children: [
                  TextSpan(
                    text: ' · ${_lowerFirst(l10n.yourPosition)}',
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
          ),
          const SizedBox(width: 12),
          Text(
            '$elo',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppTheme.primaryLight,
              fontFeatures: _tabular,
            ),
          ),
        ],
      ),
    );
  }
}

/// Quiet card: icon, one line, optional hint.
class _EmptyState extends StatelessWidget {
  final bool showFriendsOnly;
  final AppLocalizations l10n;

  const _EmptyState({required this.showFriendsOnly, required this.l10n});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Align(
        alignment: Alignment.topCenter,
        child: DsCard(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                showFriendsOnly
                    ? Icons.people_outline_rounded
                    : Icons.leaderboard_outlined,
                size: 32,
                color: AppTheme.textTertiary,
              ),
              const SizedBox(height: 10),
              Text(
                showFriendsOnly ? l10n.noFriendsYetHint : l10n.noLeaderboardData,
                textAlign: TextAlign.center,
                style: AppTheme.rowTitle,
              ),
              if (showFriendsOnly) ...[
                const SizedBox(height: 4),
                Text(
                  l10n.addFriendsToSeeRankings,
                  textAlign: TextAlign.center,
                  style: AppTheme.caption,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Load failure: the message and a retry button; pull-to-refresh also works.
class _ErrorState extends StatelessWidget {
  final String message;
  final String retryLabel;
  final Future<void> Function() onRetry;

  const _ErrorState({
    required this.message,
    required this.retryLabel,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRetry,
      color: AppTheme.primary,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
        children: [
          DsCard(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline_rounded, size: 32, color: AppTheme.error),
                const SizedBox(height: 10),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: AppTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                ElevatedButton(onPressed: onRetry, child: Text(retryLabel)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
