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
import '../../utils/round_labels.dart';
import '../../utils/tournament_registration_gate.dart';
import '../../utils/tournament_status.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/design_system.dart';
import '../../widgets/trophy_image.dart';
import 'community_tournament_form_screen.dart';
import 'stats/stats_widgets.dart' show StatsChip;
import 'tournament_detail_screen.dart';
import 'tournament_history_screen.dart';
import '../tournament/tournament_camera_setup_screen.dart';

/// Tournament tab as a single chronological agenda (UX option 5): every
/// tournament that matters — open for registration, registered, live — is one
/// dated row grouped by day. No tabs, no auto-redirect; a registered
/// tournament is the same row with a green hairline and an unregister action.
/// Pending match invites pin above the agenda, out of chronology.
///
/// Visual system D: the tab draws its own [DsScreenHeader], rows are flat
/// [DsCard]s whose border colour is the only state signal, and the row's
/// single trailing action is a pill (register / unregister / status).
///
/// Community tournaments (organised by a player, 2026-10) share the agenda
/// with the official ones: the left of every row says who organises it (the
/// shield = Dart Rivals, initials = a player), chips filter the two kinds and
/// the + of the header creates one.
class TournamentScreen extends StatefulWidget {
  const TournamentScreen({super.key});

  @override
  State<TournamentScreen> createState() => _TournamentScreenState();
}

enum _AgendaFilter { all, official, community }

class _TournamentScreenState extends State<TournamentScreen> {
  _AgendaFilter _filter = _AgendaFilter.all;

  Future<void> _createTournament() async {
    final allowed = await TournamentRegistrationGate.runForOrganizer(context);
    if (!allowed || !mounted) return;
    AppNavigator.toScreen(context, const CommunityTournamentFormScreen());
  }

  bool _passesFilter(Tournament t) => switch (_filter) {
        _AgendaFilter.all => true,
        _AgendaFilter.official => t.isOfficial,
        _AgendaFilter.community => t.isCommunity,
      };

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
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: DsScreenHeader(
            title: l10n.tournaments,
            actions: [
              DsIconButton(
                icon: Icons.add_rounded,
                iconColor: AppTheme.primaryLight,
                tooltip: l10n.createTournamentTooltip,
                onTap: _createTournament,
              ),
              DsIconButton(
                icon: Icons.history_rounded,
                tooltip: l10n.history,
                onTap: () => AppNavigator.toScreen(
                  context,
                  const TournamentHistoryScreen(),
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
                for (final t in provider.organizedTournaments) t.id: t,
                for (final t in provider.registeredTournaments) t.id: t,
                for (final t in provider.activeTournaments) t.id: t,
              };
              final allTournaments = byId.values.toList();
              final agenda = allTournaments.where(_passesFilter).toList()
                ..sort((a, b) => a.scheduledDate.compareTo(b.scheduledDate));

              if (provider.isLoading &&
                  allTournaments.isEmpty &&
                  pendingMatches.isEmpty) {
                return const Center(
                  child: CircularProgressIndicator(color: AppTheme.primary),
                );
              }

              if (allTournaments.isEmpty && pendingMatches.isEmpty) {
                return RefreshIndicator(
                  onRefresh: _loadData,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                    children: [
                      DsCard(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          children: [
                            const Icon(
                              Icons.event_busy_outlined,
                              size: 32,
                              color: AppTheme.textTertiary,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              l10n.noUpcomingTournaments,
                              textAlign: TextAlign.center,
                              style: AppTheme.rowTitle,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }

              final children = <Widget>[];

              // Pinned invitations, out of chronology.
              for (var i = 0; i < pendingMatches.length; i++) {
                if (i > 0) children.add(const SizedBox(height: 10));
                children.add(_MatchInviteCard(match: pendingMatches[i]));
              }

              // Filter chips, right above the agenda they filter.
              if (children.isNotEmpty) children.add(const SizedBox(height: 18));
              children.add(_FilterChips(
                filter: _filter,
                onChanged: (f) => setState(() => _filter = f),
              ));
              if (agenda.isEmpty) {
                children.add(const SizedBox(height: 14));
                children.add(DsCard(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    l10n.agendaFilterEmpty,
                    textAlign: TextAlign.center,
                    style: AppTheme.rowTitle,
                  ),
                ));
              }

              DateTime? currentDay;
              for (final tournament in agenda) {
                final local = tournament.scheduledDate.toLocal();
                final day = DateTime(local.year, local.month, local.day);
                if (day != currentDay) {
                  currentDay = day;
                  // 22 px above a group; the list padding already gives 14
                  // under the header, so the first group only adds 8.
                  children.add(
                    _DayHeader(day: day, topGap: children.isEmpty ? 8 : 22),
                  );
                } else {
                  children.add(const SizedBox(height: 8));
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
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
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

/// Tous · Officiels · Communauté.
class _FilterChips extends StatelessWidget {
  final _AgendaFilter filter;
  final ValueChanged<_AgendaFilter> onChanged;

  const _FilterChips({required this.filter, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final labels = {
      _AgendaFilter.all: l10n.agendaFilterAll,
      _AgendaFilter.official: l10n.agendaFilterOfficial,
      _AgendaFilter.community: l10n.agendaFilterCommunity,
    };
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final entry in labels.entries)
          StatsChip(
            label: entry.value,
            selected: filter == entry.key,
            onTap: () => onChanged(entry.key),
          ),
      ],
    );
  }
}

/// "AUJOURD'HUI" / "DEMAIN · VEN. 24/7" / "VEN. 26/7" above the day's rows:
/// an 11 / 700 group label and a hairline.
class _DayHeader extends StatelessWidget {
  final DateTime day;
  final double topGap;

  const _DayHeader({required this.day, required this.topGap});

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
      padding: EdgeInsets.only(top: topGap, bottom: 10),
      child: Row(
        children: [
          Text(label.toUpperCase(), style: AppTheme.labelSmall),
          const SizedBox(width: 12),
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

/// One tournament as a 72 px agenda row. The state lives on the row: the
/// border colour (green = registered, sky = live) and ONE trailing action
/// (register / unregister pill, or a status pill). Tapping the row opens the
/// detail screen.
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
    final isMine = tournament.isOrganizedBy(
      context.read<AuthProvider>().currentUser?.id,
    );
    final timeLabel =
        DateFormat('HH:mm').format(tournament.scheduledDate.toLocal());

    // A physical trophy gets the gold cup next to the name and its render
    // before the action — gold is dressing, never a border.
    final showTrophy = tournament.hasTrophyImage;
    final borderColor = isLive
        ? AppTheme.primaryLight.withValues(alpha: 0.45)
        : widget.isRegistered
            ? AppTheme.success.withValues(alpha: 0.35)
            : AppTheme.border;

    return SizedBox(
      height: 72,
      child: DsCard(
        radius: AppTheme.radiusRow,
        padding: const EdgeInsets.fromLTRB(12, 0, 14, 0),
        side: BorderSide(color: borderColor),
        onTap: () => AppNavigator.toScreen(
          context,
          TournamentDetailScreen(tournamentId: tournament.id),
        ),
        child: Row(
          children: [
            // Who organises it: the shield for Dart Rivals, initials for a
            // player.
            if (tournament.isCommunity)
              _OrganizerAvatar(username: tournament.organizerUsername)
            else
              Image.asset(
                'assets/logo/logo-without-letters.png',
                width: 32,
                height: 32,
                fit: BoxFit.contain,
              ),
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
                          tournament.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ),
                      if (showTrophy) ...[
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.emoji_events_outlined,
                          size: 14,
                          color: AppTheme.accent,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text.rich(
                    TextSpan(
                      style: AppTheme.caption,
                      children: [
                        TextSpan(
                          text: timeLabel,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFCBD5E1),
                          ),
                        ),
                        TextSpan(text: ' · ${_metaLine(l10n, isMine: isMine)}'),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (showTrophy) ...[
              const SizedBox(width: 12),
              TrophyImage(url: tournament.trophyThumbUrl, size: 40),
            ],
            const SizedBox(width: 12),
            _trailing(
              l10n,
              isMine: isMine,
              isLive: isLive,
              isFull: isFull,
              canJoin: canJoin,
              canLeave: canLeave,
            ),
          ],
        ),
      ),
    );
  }

  String _metaLine(AppLocalizations l10n, {required bool isMine}) {
    final tournament = widget.tournament;
    if (tournament.isCommunity) {
      // Free, open to all, no ELO: who organises it, the fill and the format.
      return [
        isMine
            ? l10n.organizedByYou
            : l10n.organizedBy(tournament.organizerUsername ?? '?'),
        '${tournament.currentParticipants}/${tournament.maxParticipants}',
        'BO${tournament.bestOf}',
      ].join(' · ');
    }
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
      if (tournament.hasRankRequirement)
        localizedRankRequirement(l10n, tournament),
    ];
    return parts.join(' · ');
  }

  Widget _trailing(
    AppLocalizations l10n, {
    required bool isMine,
    required bool isLive,
    required bool isFull,
    required bool canJoin,
    required bool canLeave,
  }) {
    if (_isLoading) {
      return const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: AppTheme.primary,
        ),
      );
    }
    // The organiser manages their tournament from its screen, not from here.
    if (isMine && !isLive) {
      return DsPill(label: l10n.organizerLabel, color: AppTheme.primaryLight);
    }
    if (canJoin) {
      return _PillButton(
        label: dsSentence(l10n.registerNow),
        filled: true,
        onTap: _register,
      );
    }
    if (canLeave) {
      return _PillButton(
        label: dsSentence(l10n.unregister),
        filled: false,
        onTap: _unregister,
      );
    }
    if (isLive) {
      return DsPill(
        label: l10n.tournamentStatusInProgress,
        color: AppTheme.primaryLight,
        dot: true,
      );
    }
    if (widget.isRegistered) {
      return DsPill(
        label: l10n.agendaRegisteredChip,
        color: AppTheme.success,
      );
    }
    if (isFull && widget.tournament.isRegistrationOpen) {
      return DsPill(
        label: l10n.agendaFullChip,
        color: AppTheme.textSecondary,
      );
    }
    final status = widget.tournament.status;
    return DsPill(
      label: localizedTournamentStatus(l10n, status),
      color: _statusPillColor(status),
    );
  }

  /// Quiet status colours of the system: only "done" and "cancelled" leave
  /// the secondary grey (no gold for "upcoming").
  static Color _statusPillColor(String status) {
    switch (status) {
      case 'in_progress':
        return AppTheme.primaryLight;
      case 'completed':
        return AppTheme.textTertiary;
      case 'cancelled':
        return AppTheme.error;
      default:
        return AppTheme.textSecondary;
    }
  }
}

/// 32 px initials disc of the player organising a community tournament.
class _OrganizerAvatar extends StatelessWidget {
  final String? username;

  const _OrganizerAvatar({required this.username});

  @override
  Widget build(BuildContext context) {
    final name = (username ?? '').trim();
    final initials = name.isEmpty
        ? '?'
        : (name.length >= 2 ? name.substring(0, 2) : name).toUpperCase();
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: AppTheme.surfaceLight,
        shape: BoxShape.circle,
      ),
      child: Text(
        initials,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Color(0xFFE2E8F0),
          height: 1,
        ),
      ),
    );
  }
}

/// 32 px pill action of a row: filled primary gradient ("S'inscrire") or a
/// green outline ("Se désinscrire").
class _PillButton extends StatelessWidget {
  final String label;
  final bool filled;
  final VoidCallback onTap;

  const _PillButton({
    required this.label,
    required this.filled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: filled ? AppTheme.primaryGradient : null,
            border: filled
                ? null
                : Border.all(color: AppTheme.success.withValues(alpha: 0.5)),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: filled ? Colors.white : AppTheme.success,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}

/// Pinned "your match is ready" card: title + one caption line, the
/// countdown on the right, and the accept button (or the waiting pill) below.
class _MatchInviteCard extends StatelessWidget {
  final TournamentMatch match;

  const _MatchInviteCard({required this.match});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final authProvider = context.read<AuthProvider>();
    final currentUserId = authProvider.currentUser?.id;

    final isPlayer1 = currentUserId == match.player1Id;
    final opponentName =
        (isPlayer1 ? match.player2Username : match.player1Username) ?? '';
    final isReady = isPlayer1 ? match.player1Ready : match.player2Ready;

    final caption = [
      match.tournamentName ?? l10n.tournament,
      localizedRoundLabel(l10n, match),
      '${l10n.vs} $opponentName',
      '${l10n.bestOf} ${match.bestOf}',
    ].join(' · ');

    return DsCard(
      side: BorderSide(color: AppTheme.primaryLight.withValues(alpha: 0.45)),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dsSentence(l10n.tournamentInvitePromptTitle),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      caption,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.caption,
                    ),
                  ],
                ),
              ),
              if (match.inviteSentAt != null) ...[
                const SizedBox(width: 12),
                _CountdownTimer(inviteSentAt: match.inviteSentAt!),
              ],
            ],
          ),
          const SizedBox(height: 14),
          if (isReady)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                DsPill(
                  label: l10n.waitingForOpponent,
                  color: AppTheme.success,
                  dot: true,
                ),
              ],
            )
          else
            _AcceptMatchButton(matchId: match.id, matchData: match),
        ],
      ),
    );
  }
}

/// mm:ss left in the 7-minute join window; red under two minutes.
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
    final deadline = widget.inviteSentAt.add(const Duration(minutes: 7));
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
    final minutes = _remaining.inMinutes;
    final seconds = _remaining.inSeconds % 60;
    final isUrgent = _remaining.inMinutes < 2;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.schedule_outlined,
          size: 16,
          color: AppTheme.textSecondary,
        ),
        const SizedBox(width: 6),
        Text(
          '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: isUrgent ? AppTheme.error : AppTheme.textPrimary,
            fontFeatures: const [FontFeature.tabularFigures()],
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

    // The one filled block of the tab, styled by the theme (primary, r14).
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _acceptMatch,
        child: _isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(dsSentence(l10n.acceptAndJoin)),
      ),
    );
  }
}
