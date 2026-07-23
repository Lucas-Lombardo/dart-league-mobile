import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../providers/tournament_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/subscription_provider.dart';
import '../../models/tournament.dart';
import '../../utils/app_navigator.dart';
import '../../utils/app_theme.dart';
import '../../utils/haptic_service.dart';
import '../../utils/tournament_registration_gate.dart';
import '../../utils/tournament_status.dart';
import '../../l10n/app_localizations.dart';
import 'tournament_detail_screen.dart';
import 'tournament_history_screen.dart';
import '../tournament/tournament_camera_setup_screen.dart';

/// Tournament tab as a single chronological agenda (UX option 5): every
/// tournament that matters — open for registration, registered, live — is one
/// dated row grouped by day. No tabs, no auto-redirect; a registered
/// tournament is the same row with a checkmark and an unregister action.
/// Pending match invites pin above the agenda, out of chronology.
class TournamentScreen extends StatefulWidget {
  const TournamentScreen({super.key});

  @override
  State<TournamentScreen> createState() => _TournamentScreenState();
}

class _TournamentScreenState extends State<TournamentScreen> {
  @override
  void initState() {
    super.initState();
    _loadData();
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
          padding: const EdgeInsets.fromLTRB(20, 8, 16, 8),
          child: Row(
            children: [
              Text(
                l10n.tournaments,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textPrimary,
                  letterSpacing: -0.3,
                ),
              ),
              const Spacer(),
              Material(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: () {
                    HapticService.lightImpact();
                    AppNavigator.toScreen(context, const TournamentHistoryScreen());
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
                          l10n.history,
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
        Expanded(
          child: Consumer<TournamentProvider>(
            builder: (context, provider, _) {
              final pendingMatches = provider.pendingMatches;
              final registeredIds =
                  provider.registeredTournaments.map((t) => t.id).toSet();

              // One entry per tournament; the "my tournaments" copies win over
              // the public listing so the freshest status is displayed.
              final byId = <String, Tournament>{
                for (final t in provider.upcomingTournaments) t.id: t,
                for (final t in provider.registeredTournaments) t.id: t,
                for (final t in provider.activeTournaments) t.id: t,
              };
              final agenda = byId.values.toList()
                ..sort((a, b) => a.scheduledDate.compareTo(b.scheduledDate));

              if (provider.isLoading &&
                  agenda.isEmpty &&
                  pendingMatches.isEmpty) {
                return const Center(child: CircularProgressIndicator());
              }

              if (agenda.isEmpty && pendingMatches.isEmpty) {
                return RefreshIndicator(
                  onRefresh: _loadData,
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

              final children = <Widget>[];

              if (pendingMatches.isNotEmpty) {
                children.add(_SectionHeader(title: l10n.matchInvites));
                children.add(const SizedBox(height: 8));
                children.addAll(
                  pendingMatches.map((match) => _MatchInviteCard(match: match)),
                );
                children.add(const SizedBox(height: 8));
              }

              DateTime? currentDay;
              for (final tournament in agenda) {
                final local = tournament.scheduledDate.toLocal();
                final day = DateTime(local.year, local.month, local.day);
                if (day != currentDay) {
                  currentDay = day;
                  children.add(_DayHeader(day: day));
                }
                children.add(_AgendaRow(
                  key: ValueKey(tournament.id),
                  tournament: tournament,
                  isRegistered: registeredIds.contains(tournament.id),
                ));
              }

              return RefreshIndicator(
                onRefresh: _loadData,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  children: children,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// "Aujourd'hui" / "Demain · ven. 24/7" / "ven. 26/7" above the day's rows.
class _DayHeader extends StatelessWidget {
  final DateTime day;

  const _DayHeader({required this.day});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff = day.difference(today).inDays;
    final locale = Localizations.localeOf(context).toString();
    final formatted = DateFormat('EEE d/M', locale).format(day);
    final label = diff == 0
        ? l10n.agendaToday
        : diff == 1
            ? '${l10n.agendaTomorrow} · $formatted'
            : formatted;

    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 10, 2, 8),
      child: Row(
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              height: 1,
              color: AppTheme.surfaceLight.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}

/// One tournament as a compact agenda line. The state lives on the row:
/// border + trailing action (register / unregister / status chip), and a
/// green "registered" prefix in the meta line when an unregister button
/// occupies the trailing slot. Tapping the row opens the detail screen.
class _AgendaRow extends StatefulWidget {
  final Tournament tournament;
  final bool isRegistered;

  const _AgendaRow({
    super.key,
    required this.tournament,
    required this.isRegistered,
  });

  @override
  State<_AgendaRow> createState() => _AgendaRowState();
}

class _AgendaRowState extends State<_AgendaRow> {
  bool _isLoading = false;

  Future<void> _register() async {
    if (_isLoading) return;

    // Product spec: the tournament is visible to everyone; trying to join
    // while blocked (app outdated, email unverified, full, premium/rank)
    // explains why in a popup. Backend enforces everything again.
    final allowed =
        await TournamentRegistrationGate.run(context, widget.tournament);
    if (!allowed || !mounted) return;

    setState(() => _isLoading = true);
    HapticService.lightImpact();

    final provider = context.read<TournamentProvider>();
    final success = await provider.registerForTournament(
      widget.tournament.id,
      tournament: widget.tournament,
    );
    if (!mounted) return;
    setState(() => _isLoading = false);
    if (!success) {
      _showError(provider);
    }
  }

  Future<void> _unregister() async {
    if (_isLoading) return;

    setState(() => _isLoading = true);
    HapticService.lightImpact();

    final provider = context.read<TournamentProvider>();
    final success =
        await provider.unregisterFromTournament(widget.tournament.id);
    if (!mounted) return;
    setState(() => _isLoading = false);
    if (!success) {
      _showError(provider);
    }
  }

  void _showError(TournamentProvider provider) {
    final error = provider.error;
    if (error != null && mounted) {
      TournamentRegistrationGate.showRegistrationError(context, error);
      provider.clearError();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tournament = widget.tournament;
    final isLive = tournament.isInProgress;
    final isFull =
        tournament.currentParticipants >= tournament.maxParticipants;
    final canJoin =
        tournament.isRegistrationOpen && !widget.isRegistered && !isFull;
    final canLeave = widget.isRegistered && tournament.isRegistrationOpen;
    final timeLabel =
        DateFormat('HH:mm').format(tournament.scheduledDate.toLocal());

    final borderColor = isLive
        ? AppTheme.primary.withValues(alpha: 0.6)
        : widget.isRegistered
            ? AppTheme.success.withValues(alpha: 0.45)
            : AppTheme.surfaceLight.withValues(alpha: 0.5);

    return GestureDetector(
      onTap: () {
        HapticService.lightImpact();
        AppNavigator.toScreen(
          context,
          TournamentDetailScreen(tournamentId: tournament.id),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Flexible(
                        child: Text(
                          tournament.name,
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '· $timeLabel',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      if (canLeave)
                        Text(
                          '✓ ${l10n.agendaRegisteredChip} · ',
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.success,
                          ),
                        ),
                      Flexible(
                        child: Text(
                          _metaLine(l10n),
                          style: TextStyle(
                            fontSize: 11.5,
                            color: AppTheme.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            _trailing(l10n, isLive: isLive, isFull: isFull, canJoin: canJoin, canLeave: canLeave),
          ],
        ),
      ),
    );
  }

  String _metaLine(AppLocalizations l10n) {
    final tournament = widget.tournament;
    final isPremiumUser = context.select<SubscriptionProvider, bool>(
      (p) => p.isPremiumActive,
    );

    final parts = <String>[
      '${tournament.currentParticipants}/${tournament.maxParticipants}',
      '+${tournament.winnerEloReward} ELO',
      tournament.isFree
          ? l10n.freeLabel
          : tournament.hasPremiumDiscount(isPremium: isPremiumUser)
              ? tournament.formattedDiscountedPrice(isPremium: true)
              : tournament.formattedPrice,
      if (tournament.premiumRequired) 'Premium',
      if (tournament.hasRankRequirement) tournament.rankRequirementLabel,
      if (tournament.hasPrize) '🏆 ${tournament.formattedPrize}',
    ];
    return parts.join(' · ');
  }

  Widget _trailing(
    AppLocalizations l10n, {
    required bool isLive,
    required bool isFull,
    required bool canJoin,
    required bool canLeave,
  }) {
    if (_isLoading) {
      return const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (canJoin) {
      return _SmallActionButton(
        label: l10n.registerNow,
        filled: true,
        onTap: _register,
      );
    }
    if (canLeave) {
      return _SmallActionButton(
        label: l10n.unregister,
        filled: false,
        onTap: _unregister,
      );
    }
    if (isLive) {
      return _StatusChip(
        label: l10n.tournamentStatusInProgress,
        color: AppTheme.primary,
      );
    }
    if (widget.isRegistered) {
      return _StatusChip(
        label: '✓ ${l10n.agendaRegisteredChip}',
        color: AppTheme.success,
      );
    }
    if (isFull && widget.tournament.isRegistrationOpen) {
      return _StatusChip(
        label: l10n.agendaFullChip,
        color: AppTheme.textSecondary,
      );
    }
    return _StatusChip(
      label: localizedTournamentStatus(l10n, widget.tournament.status),
      color: tournamentStatusColor(widget.tournament.status),
    );
  }
}

class _SmallActionButton extends StatelessWidget {
  final String label;
  final bool filled;
  final VoidCallback onTap;

  const _SmallActionButton({
    required this.label,
    required this.filled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          gradient: filled
              ? const LinearGradient(
                  colors: [AppTheme.primary, AppTheme.primaryDark],
                )
              : null,
          border: filled
              ? null
              : Border.all(color: AppTheme.success.withValues(alpha: 0.5)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: filled ? Colors.white : AppTheme.success,
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
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
    // Keep in sync with MATCH_INVITE_TIMEOUT_MS (backend tournament.service.ts)
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
