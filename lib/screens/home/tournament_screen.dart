import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/tournament_provider.dart';
import '../../providers/auth_provider.dart';
import '../../models/tournament.dart';
import '../../utils/app_theme.dart';
import '../../utils/haptic_service.dart';
import '../../l10n/app_localizations.dart';
import 'tournament_detail_screen.dart';
import 'tournament_history_screen.dart';
import '../tournament/tournament_camera_setup_screen.dart';

class TournamentScreen extends StatefulWidget {
  const TournamentScreen({super.key});

  @override
  State<TournamentScreen> createState() => _TournamentScreenState();
}

class _TournamentScreenState extends State<TournamentScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
    _setInitialTab();
  }

  Future<void> _setInitialTab() async {
    await Future.delayed(const Duration(milliseconds: 100));
    if (!mounted) return;
    
    final provider = context.read<TournamentProvider>();
    final hasPlayingTournaments = provider.activeTournaments.isNotEmpty || 
                                   provider.pendingMatches.isNotEmpty || 
                                   provider.registeredTournaments.isNotEmpty;
    
    if (!hasPlayingTournaments && _tabController.index == 0) {
      _tabController.animateTo(1);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final provider = context.read<TournamentProvider>();
    await provider.loadMyTournaments();
    await provider.loadUpcomingTournaments();
    await provider.loadPendingMatches();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Material(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: () {
                    HapticService.lightImpact();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const TournamentHistoryScreen(),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: AppTheme.surfaceLight.withValues(alpha: 0.5),
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.history,
                          size: 18,
                          color: AppTheme.textSecondary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'History',
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
          padding: const EdgeInsets.all(4),
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
                    const Icon(Icons.sports_esports_outlined, size: 18),
                    const SizedBox(width: 8),
                    Text(l10n.tournamentPlaying),
                  ],
                ),
              ),
              Tab(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.how_to_reg_outlined, size: 18),
                    const SizedBox(width: 8),
                    Text(l10n.tournamentRegister),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _PlayingTournamentsTab(onRefresh: _loadData),
              _RegisterTournamentsTab(onRefresh: _loadData),
            ],
          ),
        ),
      ],
    );
  }
}

class _PlayingTournamentsTab extends StatelessWidget {
  final Future<void> Function() onRefresh;

  const _PlayingTournamentsTab({required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Consumer<TournamentProvider>(
      builder: (context, provider, _) {
        if (provider.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        final activeTournaments = provider.activeTournaments;
        final pendingMatches = provider.pendingMatches;
        final registeredTournaments = provider.registeredTournaments;

        if (activeTournaments.isEmpty && pendingMatches.isEmpty && registeredTournaments.isEmpty) {
          return RefreshIndicator(
            onRefresh: onRefresh,
            child: ListView(
              children: [
                SizedBox(height: MediaQuery.of(context).size.height * 0.2),
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.emoji_events_outlined,
                        size: 64,
                        color: AppTheme.textSecondary.withValues(alpha: 0.5),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        l10n.noActiveTournaments,
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l10n.registerForTournamentHint,
                        style: TextStyle(
                          color: AppTheme.textSecondary.withValues(alpha: 0.7),
                          fontSize: 14,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: onRefresh,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (pendingMatches.isNotEmpty) ...[
                _SectionHeader(title: l10n.matchInvites),
                const SizedBox(height: 8),
                ...pendingMatches.map((match) => _MatchInviteCard(match: match)),
                const SizedBox(height: 24),
              ],
              if (activeTournaments.isNotEmpty) ...[
                _SectionHeader(title: l10n.activeTournaments),
                const SizedBox(height: 8),
                ...activeTournaments.map((t) => _TournamentCard(tournament: t, showStatus: true)),
                const SizedBox(height: 24),
              ],
              if (registeredTournaments.isNotEmpty) ...[
                _SectionHeader(title: l10n.registeredTournaments),
                const SizedBox(height: 8),
                ...registeredTournaments.map((t) => _TournamentCard(tournament: t, showStatus: true)),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _RegisterTournamentsTab extends StatelessWidget {
  final Future<void> Function() onRefresh;

  const _RegisterTournamentsTab({required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Consumer<TournamentProvider>(
      builder: (context, provider, _) {
        if (provider.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        final tournaments = provider.upcomingTournaments;

        if (tournaments.isEmpty) {
          return RefreshIndicator(
            onRefresh: onRefresh,
            child: ListView(
              children: [
                SizedBox(height: MediaQuery.of(context).size.height * 0.2),
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.event_busy,
                        size: 64,
                        color: AppTheme.textSecondary.withValues(alpha: 0.5),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        l10n.noUpcomingTournaments,
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: onRefresh,
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: tournaments.length,
            itemBuilder: (context, index) {
              return _TournamentCard(
                tournament: tournaments[index],
              );
            },
          ),
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: AppTheme.textPrimary,
      ),
    );
  }
}

class _TournamentCard extends StatefulWidget {
  final Tournament tournament;
  final bool showStatus;

  const _TournamentCard({
    required this.tournament,
    this.showStatus = false,
  });

  @override
  State<_TournamentCard> createState() => _TournamentCardState();
}

class _TournamentCardState extends State<_TournamentCard> {
  bool _isLoading = false;
  bool? _isRegistered;

  @override
  void initState() {
    super.initState();
    if (widget.tournament.isRegistrationOpen) {
      _checkRegistration();
    }
  }

  Future<void> _checkRegistration() async {
    final provider = context.read<TournamentProvider>();
    final isRegistered = await provider.isRegisteredForTournament(widget.tournament.id);
    if (mounted) {
      setState(() => _isRegistered = isRegistered);
    }
  }

  Future<void> _toggleRegistration() async {
    if (_isLoading) return;

    final authProvider = context.read<AuthProvider>();
    if (_isRegistered != true && authProvider.currentUser?.isEmailVerified == false) {
      _showEmailVerificationDialog(context, authProvider);
      return;
    }

    setState(() => _isLoading = true);
    HapticService.lightImpact();

    final provider = context.read<TournamentProvider>();
    bool success;
    if (_isRegistered == true) {
      success = await provider.unregisterFromTournament(widget.tournament.id);
    } else {
      success = await provider.registerForTournament(widget.tournament.id, tournament: widget.tournament);
    }

    if (success && mounted) {
      setState(() {
        _isRegistered = !(_isRegistered ?? false);
        _isLoading = false;
      });
    } else if (mounted) {
      setState(() => _isLoading = false);
      // Show error if payment failed
      final error = provider.error;
      if (error != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error), backgroundColor: AppTheme.error),
        );
        provider.clearError();
      }
    }
  }

  void _showEmailVerificationDialog(BuildContext context, AuthProvider authProvider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.email_outlined, color: AppTheme.primary, size: 28),
            SizedBox(width: 12),
            Text(
              'Email Not Verified',
              style: TextStyle(color: AppTheme.textPrimary, fontSize: 20),
            ),
          ],
        ),
        content: const Text(
          'You must verify your email before joining a tournament. Check your inbox or resend the verification email.',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 15),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () async {
              await authProvider.resendVerification();
              if (context.mounted) {
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Verification email sent!'),
                    backgroundColor: AppTheme.success,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Resend Email'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tournament = widget.tournament;
    final canRegister = tournament.isRegistrationOpen;

    return GestureDetector(
      onTap: () {
        HapticService.lightImpact();
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => TournamentDetailScreen(tournamentId: tournament.id),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppTheme.surface,
              AppTheme.surfaceLight.withValues(alpha: 0.5),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: tournament.isInProgress
                ? AppTheme.primary.withValues(alpha: 0.6)
                : canRegister
                    ? AppTheme.success.withValues(alpha: 0.4)
                    : AppTheme.surfaceLight.withValues(alpha: 0.3),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              AppTheme.primary.withValues(alpha: 0.3),
                              AppTheme.primary.withValues(alpha: 0.1),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.emoji_events,
                          color: AppTheme.primary,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tournament.name,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(
                                  Icons.calendar_today,
                                  size: 12,
                                  color: AppTheme.textSecondary.withValues(alpha: 0.8),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _formatDate(tournament.scheduledDate),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.textSecondary.withValues(alpha: 0.8),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (widget.showStatus)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: _getStatusColor(tournament.status).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: _getStatusColor(tournament.status).withValues(alpha: 0.3),
                            ),
                          ),
                          child: Text(
                            tournament.statusDisplay,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: _getStatusColor(tournament.status),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _InfoChip(
                        icon: Icons.people,
                        label: '${tournament.currentParticipants}/${tournament.maxParticipants}',
                      ),
                      const SizedBox(width: 10),
                      _InfoChip(
                        icon: Icons.star,
                        label: '+${tournament.winnerEloReward} ELO',
                        color: AppTheme.accent,
                      ),
                      const SizedBox(width: 10),
                      _InfoChip(
                        icon: tournament.isFree ? Icons.card_giftcard : Icons.payment,
                        label: tournament.formattedPrice,
                        color: tournament.isFree ? AppTheme.success : AppTheme.primary,
                      ),
                      const Spacer(),
                      Icon(
                        Icons.arrow_forward_ios,
                        size: 14,
                        color: AppTheme.textSecondary.withValues(alpha: 0.5),
                      ),
                    ],
                  ),
                  if (tournament.hasPrize) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        tournament.hasCashPrize ? '💰 Winner Prize: ${tournament.formattedPrize}' : '🏆 Winner Prize: ${tournament.formattedPrize}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.amber,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (canRegister) ...[            
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: _isRegistered == true
                      ? AppTheme.success.withValues(alpha: 0.1)
                      : AppTheme.primary.withValues(alpha: 0.1),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(20),
                    bottomRight: Radius.circular(20),
                  ),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _isLoading ? null : _toggleRegistration,
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(20),
                      bottomRight: Radius.circular(20),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: _isLoading
                          ? const Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : _isRegistered == null
                              ? const Center(
                                  child: SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  ),
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      _isRegistered! ? Icons.check_circle : Icons.add_circle_outline,
                                      size: 18,
                                      color: _isRegistered! ? AppTheme.success : AppTheme.primary,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      _isRegistered! ? l10n.unregister : l10n.registerNow,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: _isRegistered! ? AppTheme.success : AppTheme.primary,
                                      ),
                                    ),
                                  ],
                                ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
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

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;

  const _InfoChip({
    required this.icon,
    required this.label,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final chipColor = color ?? AppTheme.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: chipColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: chipColor),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: chipColor,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _RegisterButton extends StatefulWidget {
  final Tournament tournament;

  const _RegisterButton({required this.tournament});

  @override
  State<_RegisterButton> createState() => _RegisterButtonState();
}

class _RegisterButtonState extends State<_RegisterButton> {
  bool _isLoading = false;
  bool? _isRegistered;

  @override
  void initState() {
    super.initState();
    _checkRegistration();
  }

  Future<void> _checkRegistration() async {
    final provider = context.read<TournamentProvider>();
    final isRegistered = await provider.isRegisteredForTournament(widget.tournament.id);
    if (mounted) {
      setState(() => _isRegistered = isRegistered);
    }
  }

  Future<void> _toggleRegistration() async {
    if (_isLoading) return;

    final authProvider = context.read<AuthProvider>();
    if (_isRegistered != true && authProvider.currentUser?.isEmailVerified == false) {
      _showEmailVerificationDialog(context, authProvider);
      return;
    }

    setState(() => _isLoading = true);
    HapticService.lightImpact();

    final provider = context.read<TournamentProvider>();
    bool success;

    if (_isRegistered == true) {
      success = await provider.unregisterFromTournament(widget.tournament.id);
    } else {
      success = await provider.registerForTournament(widget.tournament.id, tournament: widget.tournament);
    }

    if (success && mounted) {
      setState(() {
        _isRegistered = !(_isRegistered ?? false);
        _isLoading = false;
      });
    } else if (mounted) {
      setState(() => _isLoading = false);
      // Show error if payment failed
      final error = provider.error;
      if (error != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error), backgroundColor: AppTheme.error),
        );
        provider.clearError();
      }
    }
  }

  void _showEmailVerificationDialog(BuildContext context, AuthProvider authProvider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Email Not Verified'),
        content: const Text(
          'You must verify your email before joining a tournament. Check your inbox or resend the verification email.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          ElevatedButton(
            onPressed: () async {
              await authProvider.resendVerification();
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Verification email sent!'),
                  backgroundColor: AppTheme.success,
                ),
              );
            },
            child: const Text('Resend Email'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    if (_isRegistered == null) {
      return const SizedBox(
        height: 40,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _toggleRegistration,
        style: ElevatedButton.styleFrom(
          backgroundColor: _isRegistered! ? AppTheme.error : AppTheme.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: _isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(
                _isRegistered! ? l10n.unregister : l10n.registerNow,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
      ),
    );
  }
}

class _MatchInviteCard extends StatelessWidget {
  final TournamentMatch match;

  const _MatchInviteCard({required this.match});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final authProvider = context.read<AuthProvider>();
    final currentUserId = authProvider.currentUser?.id;
    
    final isPlayer1 = currentUserId == match.player1Id;
    final opponentName = isPlayer1 ? match.player2Username : match.player1Username;
    final isReady = isPlayer1 ? match.player1Ready : match.player2Ready;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primary.withValues(alpha: 0.2),
            AppTheme.surface,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.notifications_active,
                  color: AppTheme.accent,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.matchInvite,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    Text(
                      match.tournamentName ?? 'Tournament',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  match.roundNameDisplay,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Icon(Icons.person, size: 16, color: AppTheme.textSecondary),
              const SizedBox(width: 8),
              Text(
                '${l10n.vs} $opponentName',
                style: const TextStyle(
                  fontSize: 14,
                  color: AppTheme.textPrimary,
                ),
              ),
              const Spacer(),
              Text(
                'Best of ${match.bestOf}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
          if (match.inviteSentAt != null) ...[
            const SizedBox(height: 8),
            _CountdownTimer(inviteSentAt: match.inviteSentAt!),
          ],
          const SizedBox(height: 16),
          if (isReady)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.success.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.check_circle, color: AppTheme.success, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    l10n.waitingForOpponent,
                    style: const TextStyle(
                      color: AppTheme.success,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            )
          else
            _AcceptMatchButton(matchId: match.id, matchData: match),
        ],
      ),
    );
  }
}

class _CountdownTimer extends StatefulWidget {
  final DateTime inviteSentAt;

  const _CountdownTimer({required this.inviteSentAt});

  @override
  State<_CountdownTimer> createState() => _CountdownTimerState();
}

class _CountdownTimerState extends State<_CountdownTimer> {
  late Duration _remaining;

  @override
  void initState() {
    super.initState();
    _calculateRemaining();
    _startTimer();
  }

  void _calculateRemaining() {
    final deadline = widget.inviteSentAt.add(const Duration(minutes: 15));
    _remaining = deadline.difference(DateTime.now());
    if (_remaining.isNegative) {
      _remaining = Duration.zero;
    }
  }

  void _startTimer() {
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) {
        setState(() => _calculateRemaining());
        if (_remaining > Duration.zero) {
          _startTimer();
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final minutes = _remaining.inMinutes;
    final seconds = _remaining.inSeconds % 60;
    final isUrgent = _remaining.inMinutes < 2;

    return Row(
      children: [
        Icon(
          Icons.timer,
          size: 14,
          color: isUrgent ? AppTheme.error : AppTheme.accent,
        ),
        const SizedBox(width: 4),
        Text(
          '${l10n.timeRemaining}: ${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: isUrgent ? AppTheme.error : AppTheme.accent,
          ),
        ),
      ],
    );
  }
}

class _AcceptMatchButton extends StatefulWidget {
  final String matchId;
  final TournamentMatch? matchData;

  const _AcceptMatchButton({required this.matchId, this.matchData});

  @override
  State<_AcceptMatchButton> createState() => _AcceptMatchButtonState();
}

class _AcceptMatchButtonState extends State<_AcceptMatchButton> {
  bool _isLoading = false;

  Future<void> _acceptMatch() async {
    if (_isLoading) return;

    setState(() => _isLoading = true);
    HapticService.mediumImpact();

    final match = widget.matchData;
    if (match != null) {
      final auth = context.read<AuthProvider>();
      final currentUserId = auth.currentUser?.id;
      final isPlayer1 = currentUserId == match.player1Id;
      final opponentUsername = isPlayer1 ? (match.player2Username ?? 'Opponent') : (match.player1Username ?? 'Opponent');
      final opponentId = isPlayer1 ? (match.player2Id ?? '') : (match.player1Id ?? '');

      if (mounted) {
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
    } else {
      // Fallback: old behavior
      final provider = context.read<TournamentProvider>();
      await provider.setMatchReady(widget.matchId);
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _acceptMatch,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: _isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.check_circle_outline),
                  const SizedBox(width: 8),
                  Text(
                    l10n.acceptAndJoin,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
