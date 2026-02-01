import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/tournament_provider.dart';
import '../../providers/auth_provider.dart';
import '../../models/tournament.dart';
import '../../services/tournament_service.dart';
import '../../utils/app_theme.dart';
import '../../utils/haptic_service.dart';
import '../../l10n/app_localizations.dart';

class TournamentDetailScreen extends StatefulWidget {
  final String tournamentId;

  const TournamentDetailScreen({super.key, required this.tournamentId});

  @override
  State<TournamentDetailScreen> createState() => _TournamentDetailScreenState();
}

class _TournamentDetailScreenState extends State<TournamentDetailScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool? _isRegistered;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final provider = context.read<TournamentProvider>();
    await provider.loadTournament(widget.tournamentId);
    _checkRegistration();
  }

  Future<void> _checkRegistration() async {
    final provider = context.read<TournamentProvider>();
    final isRegistered = await provider.isRegisteredForTournament(widget.tournamentId);
    if (mounted) {
      setState(() => _isRegistered = isRegistered);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(l10n.tournamentDetails),
        backgroundColor: AppTheme.surface,
      ),
      body: Consumer<TournamentProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading && provider.currentTournament == null) {
            return const Center(child: CircularProgressIndicator());
          }

          final tournament = provider.currentTournament;
          if (tournament == null) {
            return Center(
              child: Text(
                l10n.tournamentNotFound,
                style: const TextStyle(color: AppTheme.textSecondary),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _loadData,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                children: [
                  _TournamentHeader(
                    tournament: tournament,
                    isRegistered: _isRegistered,
                    onRegistrationChanged: _checkRegistration,
                  ),
                  const SizedBox(height: 16),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: AppTheme.surfaceLight.withValues(alpha: 0.5),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: TabBar(
                      controller: _tabController,
                      indicator: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppTheme.primary,
                            AppTheme.primary.withValues(alpha: 0.8),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primary.withValues(alpha: 0.4),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      indicatorSize: TabBarIndicatorSize.tab,
                      labelColor: Colors.white,
                      unselectedLabelColor: AppTheme.textSecondary,
                      labelStyle: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                      unselectedLabelStyle: const TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                      ),
                      dividerColor: Colors.transparent,
                      splashBorderRadius: BorderRadius.circular(12),
                      tabs: [
                        Tab(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.account_tree_outlined, size: 18),
                              const SizedBox(width: 8),
                              Text(l10n.bracket),
                            ],
                          ),
                        ),
                        Tab(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.people_outline, size: 18),
                              const SizedBox(width: 8),
                              Text(l10n.participants),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.5,
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _BracketTab(bracket: provider.currentBracket),
                        _ParticipantsTab(tournamentId: widget.tournamentId),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TournamentHeader extends StatelessWidget {
  final Tournament tournament;
  final bool? isRegistered;
  final VoidCallback onRegistrationChanged;

  const _TournamentHeader({
    required this.tournament,
    required this.isRegistered,
    required this.onRegistrationChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppTheme.surfaceGradient,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.emoji_events,
                  color: AppTheme.primary,
                  size: 32,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tournament.name,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: _getStatusColor(tournament.status).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        tournament.statusDisplay,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: _getStatusColor(tournament.status),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (tournament.description != null && tournament.description!.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              tournament.description!,
              style: const TextStyle(
                fontSize: 14,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: 20),
          _InfoRow(
            icon: Icons.calendar_today,
            label: l10n.scheduledDate,
            value: _formatDate(tournament.scheduledDate),
          ),
          const SizedBox(height: 8),
          _InfoRow(
            icon: Icons.people,
            label: l10n.participants,
            value: '${tournament.currentParticipants}/${tournament.maxParticipants}',
          ),
          const SizedBox(height: 8),
          _InfoRow(
            icon: Icons.star,
            label: l10n.winnerReward,
            value: '+${tournament.winnerEloReward} ELO',
            valueColor: AppTheme.accent,
          ),
          if (tournament.isInProgress) ...[
            const SizedBox(height: 8),
            _InfoRow(
              icon: Icons.sports_score,
              label: l10n.currentRound,
              value: '${tournament.currentRound}/${tournament.totalRounds}',
            ),
          ],
          if (tournament.winnerId != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.accent.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.emoji_events, color: AppTheme.accent),
                  const SizedBox(width: 12),
                  Text(
                    '${l10n.winner}: ${tournament.winnerUsername}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.accent,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if ((tournament.isRegistrationOpen || tournament.isUpcoming) && isRegistered != null) ...[
            const SizedBox(height: 20),
            _RegistrationButton(
              tournamentId: tournament.id,
              isRegistered: isRegistered!,
              canRegister: tournament.isRegistrationOpen,
              onChanged: onRegistrationChanged,
            ),
          ],
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'registration_open':
        return AppTheme.success;
      case 'in_progress':
        return AppTheme.primary;
      case 'completed':
        return AppTheme.textSecondary;
      case 'cancelled':
        return AppTheme.error;
      default:
        return AppTheme.accent;
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} at ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppTheme.textSecondary),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: const TextStyle(
            fontSize: 14,
            color: AppTheme.textSecondary,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: valueColor ?? AppTheme.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _RegistrationButton extends StatefulWidget {
  final String tournamentId;
  final bool isRegistered;
  final bool canRegister;
  final VoidCallback onChanged;

  const _RegistrationButton({
    required this.tournamentId,
    required this.isRegistered,
    this.canRegister = true,
    required this.onChanged,
  });

  @override
  State<_RegistrationButton> createState() => _RegistrationButtonState();
}

class _RegistrationButtonState extends State<_RegistrationButton> {
  bool _isLoading = false;

  Future<void> _toggleRegistration() async {
    if (_isLoading || !widget.canRegister) return;

    setState(() => _isLoading = true);
    HapticService.lightImpact();

    final provider = context.read<TournamentProvider>();
    bool success;

    if (widget.isRegistered) {
      success = await provider.unregisterFromTournament(widget.tournamentId);
    } else {
      success = await provider.registerForTournament(widget.tournamentId);
    }

    if (success) {
      widget.onChanged();
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    // If registration is not open yet, show info message
    if (!widget.canRegister) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: AppTheme.surfaceLight.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.textSecondary.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.schedule, size: 18, color: AppTheme.textSecondary.withValues(alpha: 0.8)),
            const SizedBox(width: 8),
            Text(
              'Registration opens soon',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppTheme.textSecondary.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: widget.isRegistered
            ? null
            : LinearGradient(
                colors: [AppTheme.primary, AppTheme.primary.withValues(alpha: 0.8)],
              ),
        color: widget.isRegistered ? AppTheme.success.withValues(alpha: 0.15) : null,
        borderRadius: BorderRadius.circular(14),
        border: widget.isRegistered
            ? Border.all(color: AppTheme.success.withValues(alpha: 0.5))
            : null,
        boxShadow: widget.isRegistered
            ? null
            : [
                BoxShadow(
                  color: AppTheme.primary.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _isLoading ? null : _toggleRegistration,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: _isLoading
                ? const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        widget.isRegistered ? Icons.check_circle : Icons.add_circle_outline,
                        size: 20,
                        color: widget.isRegistered ? AppTheme.success : Colors.white,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        widget.isRegistered ? l10n.unregister : l10n.registerNow,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: widget.isRegistered ? AppTheme.success : Colors.white,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _BracketTab extends StatelessWidget {
  final List<TournamentMatch> bracket;

  const _BracketTab({required this.bracket});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    if (bracket.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.account_tree_outlined,
              size: 48,
              color: AppTheme.textSecondary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.bracketNotGenerated,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    // Group matches by round
    final matchesByRound = <int, List<TournamentMatch>>{};
    for (final match in bracket) {
      matchesByRound.putIfAbsent(match.roundNumber, () => []).add(match);
    }

    final rounds = matchesByRound.keys.toList()..sort();

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: rounds.length,
      itemBuilder: (context, index) {
        final roundNumber = rounds[index];
        final matches = matchesByRound[roundNumber]!;
        final roundName = matches.first.roundNameDisplay;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                roundName,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primary,
                ),
              ),
            ),
            const SizedBox(height: 8),
            ...matches.map((match) => _BracketMatchCard(match: match)),
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }
}

class _BracketMatchCard extends StatelessWidget {
  final TournamentMatch match;

  const _BracketMatchCard({required this.match});

  @override
  Widget build(BuildContext context) {
    final authProvider = context.read<AuthProvider>();
    final currentUserId = authProvider.currentUser?.id;
    final isMyMatch = currentUserId == match.player1Id || currentUserId == match.player2Id;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isMyMatch
            ? AppTheme.primary.withValues(alpha: 0.1)
            : AppTheme.surfaceLight.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isMyMatch
              ? AppTheme.primary.withValues(alpha: 0.5)
              : AppTheme.surfaceLight.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              children: [
                _PlayerRow(
                  username: match.player1Username ?? 'TBD',
                  score: match.player1Score,
                  isWinner: match.winnerId == match.player1Id,
                  isCurrentUser: currentUserId == match.player1Id,
                ),
                const Divider(height: 16),
                _PlayerRow(
                  username: match.player2Username ?? 'TBD',
                  score: match.player2Score,
                  isWinner: match.winnerId == match.player2Id,
                  isCurrentUser: currentUserId == match.player2Id,
                ),
              ],
            ),
          ),
          if (match.isCompleted)
            Container(
              margin: const EdgeInsets.only(left: 8),
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: AppTheme.success.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check,
                color: AppTheme.success,
                size: 16,
              ),
            ),
        ],
      ),
    );
  }
}

class _PlayerRow extends StatelessWidget {
  final String username;
  final int score;
  final bool isWinner;
  final bool isCurrentUser;

  const _PlayerRow({
    required this.username,
    required this.score,
    required this.isWinner,
    required this.isCurrentUser,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (isWinner)
          const Padding(
            padding: EdgeInsets.only(right: 8),
            child: Icon(Icons.emoji_events, color: AppTheme.accent, size: 16),
          ),
        Expanded(
          child: Text(
            username,
            style: TextStyle(
              fontSize: 14,
              fontWeight: isWinner || isCurrentUser ? FontWeight.bold : FontWeight.normal,
              color: isCurrentUser ? AppTheme.primary : AppTheme.textPrimary,
            ),
          ),
        ),
        Text(
          score > 0 ? '$score' : '-',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: isWinner ? AppTheme.success : AppTheme.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _ParticipantsTab extends StatefulWidget {
  final String tournamentId;

  const _ParticipantsTab({required this.tournamentId});

  @override
  State<_ParticipantsTab> createState() => _ParticipantsTabState();
}

class _ParticipantsTabState extends State<_ParticipantsTab> {
  List<TournamentRegistration>? _registrations;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRegistrations();
  }

  Future<void> _loadRegistrations() async {
    try {
      final regs = await TournamentService.getRegistrations(widget.tournamentId);
      if (mounted) {
        setState(() {
          _registrations = regs;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading registrations: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Color _getRankColor(String? rank) {
    switch (rank) {
      case 'master':
        return const Color(0xFFFF4081);
      case 'diamond':
        return const Color(0xFF00BCD4);
      case 'platinum':
        return const Color(0xFF9C27B0);
      case 'gold':
        return const Color(0xFFFFD700);
      case 'silver':
        return const Color(0xFFC0C0C0);
      case 'bronze':
        return const Color(0xFFCD7F32);
      default:
        return AppTheme.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final authProvider = context.read<AuthProvider>();
    final currentUserId = authProvider.currentUser?.id;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_registrations == null || _registrations!.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.people_outline,
              size: 48,
              color: AppTheme.textSecondary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.noParticipantsYet,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _registrations!.length,
      itemBuilder: (context, index) {
        final reg = _registrations![index];
        final isCurrentUser = reg.userId == currentUserId;
        final rankColor = _getRankColor(reg.rank);

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppTheme.surface,
                AppTheme.surfaceLight.withValues(alpha: 0.3),
              ],
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isCurrentUser
                  ? AppTheme.primary.withValues(alpha: 0.5)
                  : AppTheme.surfaceLight.withValues(alpha: 0.3),
              width: isCurrentUser ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: rankColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: rankColor,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          reg.username ?? 'Unknown',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: isCurrentUser ? AppTheme.primary : AppTheme.textPrimary,
                          ),
                        ),
                        if (isCurrentUser) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'You',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: rankColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: rankColor.withValues(alpha: 0.3)),
                ),
                child: Text(
                  reg.rankDisplay,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: rankColor,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
