import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../utils/app_navigator.dart';
import '../../utils/app_theme.dart';
import '../../utils/haptic_service.dart';
import '../../utils/orientation_utils.dart';
import '../../utils/tournament_round.dart';
import '../../models/rtc_v2_config.dart';
import '../../services/turn_report_service.dart';
import '../../models/tournament.dart';
import '../../services/socket_service.dart';
import '../../services/tournament_service.dart';
import '../../providers/tournament_game_provider.dart';
import '../../providers/tournament_provider.dart';
import '../../providers/auth_provider.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/design_system.dart';
import 'tournament_camera_setup_screen.dart';
import 'tournament_game_screen.dart';

class TournamentReadyScreen extends StatefulWidget {
  final String matchId;
  final String tournamentId;
  final String tournamentName;
  final String roundName;
  final String opponentUsername;
  final String opponentId;
  final String player1Id;
  final String player2Id;
  final int bestOf;
  final DateTime? inviteSentAt;

  const TournamentReadyScreen({
    super.key,
    required this.matchId,
    required this.tournamentId,
    required this.tournamentName,
    required this.roundName,
    required this.opponentUsername,
    required this.opponentId,
    required this.player1Id,
    required this.player2Id,
    required this.bestOf,
    this.inviteSentAt,
  });

  @override
  State<TournamentReadyScreen> createState() => _TournamentReadyScreenState();
}

class _TournamentReadyScreenState extends State<TournamentReadyScreen>
    with SingleTickerProviderStateMixin {
  bool _myReady = false;
  bool _opponentReady = false;
  bool _navigating = false;
  bool _cancelling = false;
  late AnimationController _pulseController;

  // Socket events arrive through TournamentProvider's rebroadcast streams —
  // the provider is the single owner of the SocketService handler slots, so a
  // reconnect can no longer displace this screen's navigation handler (and
  // leaving this screen no longer kills the provider's listeners).
  StreamSubscription<Map<String, dynamic>>? _readySub;
  StreamSubscription<Map<String, dynamic>>? _startSub;
  StreamSubscription<Map<String, dynamic>>? _resultSub;

  // Join window — mirrors the backend MATCH_INVITE_TIMEOUT_MS. Past it the
  // sweep decides the match without the absentees (the stronger ELO advances
  // when neither showed), so this countdown must not run short of the server's.
  static const Duration _joinWindow = Duration(minutes: 7);
  Timer? _windowTimer;
  Duration _remaining = Duration.zero;
  bool _expired = false;

  // After expiry the backend sweep (runs every 10 seconds) settles the match;
  // poll the bracket until we can tell the player what actually happened.
  Timer? _outcomePoll;
  int _outcomePollTries = 0;

  // Socket-independent safety net. matchReadyUpdate/tournamentMatchStart are
  // fire-and-forget emits with no server-side replay: if this device's socket
  // wasn't registered at that instant, the event is lost and both players sit
  // here until the invite sweep forfeits them. Poll the ready-state endpoint
  // and navigate from it when the emit was missed.
  Timer? _statePoll;

  // Held for dispose(): context.read() is not allowed there.
  TournamentProvider? _tournamentProvider;

  @override
  void initState() {
    super.initState();
    OrientationUtils.allowAll();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    // Tell the global invite gate a lobby is open: while it is, the gate
    // holds its prompt and this screen owns what happens next (see
    // _showOutcomeDialogAndLeave, which chains into the following match).
    _tournamentProvider = context.read<TournamentProvider>()
      ..markInviteHandled(widget.matchId)
      ..setMatchScreenOpen(widget.matchId);

    _startWindowCountdown();
    _setupListeners();
    _startStatePolling();
  }

  void _startWindowCountdown() {
    final sentAt = widget.inviteSentAt;
    if (sentAt == null) return;
    final deadline = sentAt.add(_joinWindow);

    void tick() {
      final remaining = deadline.difference(DateTime.now());
      if (!mounted) return;
      setState(() {
        if (remaining <= Duration.zero) {
          _remaining = Duration.zero;
          _expired = true;
          _windowTimer?.cancel();
          _startOutcomePolling();
        } else {
          _remaining = remaining;
        }
      });
    }

    tick();
    _windowTimer = Timer.periodic(const Duration(seconds: 1), (_) => tick());
  }

  String _formatRemaining(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _setupListeners() async {
    // The lobby's own events (matchReadyUpdate / tournamentMatchStart) travel
    // over the socket; the poll below is only a safety net. If the socket
    // isn't ours, get one before readying rather than running the whole match
    // on HTTP alone.
    if (!SocketService.belongsToSession) {
      try {
        await SocketService.ensureAuthenticated();
      } catch (_) {}
      if (!mounted) return;
    }

    final tournamentProvider = context.read<TournamentProvider>();

    _readySub = tournamentProvider.readyUpdates.listen((data) {
      if (!mounted || data['matchId'] != widget.matchId) return;
      final p1Ready = data['player1Ready'] as bool? ?? false;
      final p2Ready = data['player2Ready'] as bool? ?? false;

      setState(() {
        final user = context.read<AuthProvider>().currentUser;
        final iAmPlayer1 = user?.id == widget.player1Id;
        // Sticky for MY card (like the poll): an update snapshotted before our
        // own POST landed must not un-set the optimistic local "prêt". The
        // opponent's card follows the server truth (they can unready).
        _myReady = _myReady || (iAmPlayer1 ? p1Ready : p2Ready);
        _opponentReady = iAmPlayer1 ? p2Ready : p1Ready;
      });
    });

    // Match start (both ready, backend created the game)
    _startSub = tournamentProvider.matchStarts.listen((data) {
      if (!mounted || data['matchId'] != widget.matchId) return;
      final gameMatchId = data['gameMatchId'] as String?;
      if (gameMatchId != null) {
        // Same payload as the P2P block, same reason: this is where a
        // tournament leg's capability verdict arrives.
        TurnReportService.resetForMatch();
        TurnReportService.applyMatchPayload(data);
        _navigateToGame(
          gameMatchId,
          rtcV2Config: RtcV2Config.tryParse(data['rtcV2']),
        );
      }
    });

    // Outcome events while waiting: opponent timed out (we advance) or the
    // match got postponed by a dispute rollback in the previous round.
    _resultSub = tournamentProvider.matchResults.listen((data) {
      if (!mounted || data['tournamentMatchId'] != widget.matchId) return;
      final reason = data['reason'] as String?;
      final user = context.read<AuthProvider>().currentUser;
      if (reason == 'opponent_timeout' && data['winnerId'] == user?.id) {
        _showOutcomeDialogAndLeave(advance: true);
      } else if (reason == 'match_postponed') {
        _showPostponedDialogAndLeave();
      }
    });

    // NOW send the ready call, after listeners are in place. Paint MY card
    // green immediately: the player already pressed "Prêt" on the camera
    // screen, and waiting for the POST round-trip made the checkmark lag
    // several seconds. If the POST is lost, the poll re-sends it (below).
    if (mounted) setState(() => _myReady = true);
    try {
      await TournamentService.setMatchReady(widget.matchId);
    } catch (e) {
      debugPrint('Error setting match ready: $e');
    }
  }

  void _startStatePolling() {
    _statePoll = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (!mounted || _navigating) {
        _statePoll?.cancel();
        return;
      }
      try {
        final state =
            await TournamentService.getMatchReadyState(widget.matchId);
        if (!mounted || _navigating) return;

        final p1Ready = state['player1Ready'] as bool? ?? false;
        final p2Ready = state['player2Ready'] as bool? ?? false;
        final user = context.read<AuthProvider>().currentUser;
        final iAmPlayer1 = user?.id == widget.player1Id;
        final myServerReady = iAmPlayer1 ? p1Ready : p2Ready;

        setState(() {
          _myReady = myServerReady || _myReady;
          _opponentReady = iAmPlayer1 ? p2Ready : p1Ready;
        });

        // My initial /ready never landed (failed or lost POST): the screen
        // shows "PRÊT" optimistically while the server disagrees, and the
        // sweep would forfeit me. Re-send rather than lying.
        if (!myServerReady && !_cancelling && !_expired) {
          try {
            await TournamentService.setMatchReady(widget.matchId);
          } catch (_) {}
        }

        final start = state['start'];
        if (start is Map<String, dynamic>) {
          final gameMatchId = start['gameMatchId'] as String?;
          if (gameMatchId != null) {
            _statePoll?.cancel();
            // The polling fallback carries the same block as the socket event.
            TurnReportService.resetForMatch();
            TurnReportService.applyMatchPayload(start);
            _navigateToGame(
              gameMatchId,
              rtcV2Config: RtcV2Config.tryParse(start['rtcV2']),
            );
          }
        }
      } catch (_) {
        // Transient (or old backend without the endpoint) — the socket path
        // still does the job; next tick retries.
      }
    });
  }

  // The backend sweep settles the match within ~10s of the deadline. Poll the
  // bracket to tell the player how it ended instead of leaving them staring
  // at "expired" forever (the socket result event usually beats this poll).
  void _startOutcomePolling() {
    _outcomePoll?.cancel();
    _outcomePollTries = 0;
    _outcomePoll = Timer.periodic(const Duration(seconds: 4), (_) async {
      if (!mounted || _navigating) {
        _outcomePoll?.cancel();
        return;
      }
      _outcomePollTries++;
      if (_outcomePollTries > 45) {
        // ~3 minutes with no verdict — stop polling, leave the manual exit.
        _outcomePoll?.cancel();
        return;
      }
      try {
        final bracket = await TournamentService.getBracket(widget.tournamentId);
        TournamentMatch? match;
        for (final m in bracket) {
          if (m.id == widget.matchId) {
            match = m;
            break;
          }
        }
        if (match == null || !mounted) return;
        final myId = context.read<AuthProvider>().currentUser?.id;

        if (match.status == 'in_progress') {
          // Both readied at the buzzer — the start event should carry us; if
          // it was missed, the resume flow on the Play screen picks it up.
          return;
        }
        if (match.isCompleted) {
          _outcomePoll?.cancel();
          if (match.winnerId != null && match.winnerId == myId) {
            _showOutcomeDialogAndLeave(advance: true);
          } else {
            _showOutcomeDialogAndLeave(advance: false);
          }
        } else if (match.status == 'pending') {
          // Rolled back to un-invited (dispute in the previous round).
          _outcomePoll?.cancel();
          _showPostponedDialogAndLeave();
        }
      } catch (_) {
        // Transient — next tick retries.
      }
    });
  }

  void _showOutcomeDialogAndLeave({required bool advance}) {
    if (!mounted || _navigating) return;
    _navigating = true;
    final l10n = AppLocalizations.of(context);
    HapticService.heavyImpact();
    // Refresh now so the next round's invite — if it exists — is known by
    // the time the player taps OK (see _chainIntoNextMatch). Matters on the
    // poll-driven path, where nothing else refreshes for up to 30 s.
    if (advance) _tournamentProvider?.loadPendingMatches();
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text(
          advance ? l10n.youAdvanceTitle : l10n.eliminatedTitle,
          style: TextStyle(color: advance ? AppTheme.success : AppTheme.error),
        ),
        content: Text(
          advance ? l10n.youAdvanceOpponentNoShow : l10n.eliminatedNoShowBody,
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              if (!mounted) return;
              if (advance && _chainIntoNextMatch()) return;
              Navigator.of(context).pop();
            },
            child: Text(l10n.ok),
          ),
        ],
      ),
    );
  }

  /// After "you advance": when the next round's invite is already waiting
  /// (a walkover decides both the result AND the next pairing in the same
  /// tick — Tournoi #4: jordinateur's R2 invite landed the same second as
  /// his R1 walkover, and he never saw it), go straight to its camera setup
  /// instead of dropping the player back on the tournament screen.
  /// Returns false when there is nothing to chain into (normal pop).
  bool _chainIntoNextMatch() {
    final tournaments = _tournamentProvider;
    final myId = context.read<AuthProvider>().currentUser?.id;
    if (tournaments == null || myId == null) return false;
    final next = tournaments.nextUnhandledInvite(excludeMatchId: widget.matchId);
    if (next == null) return false;
    tournaments.markInviteHandled(next.id);

    final isPlayer1 = next.player1Id == myId;
    final opponentId = (isPlayer1 ? next.player2Id : next.player1Id) ?? '';
    final opponentUsername =
        (isPlayer1 ? next.player2Username : next.player1Username) ?? '';

    HapticService.mediumImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context)
            .tournamentInvitePromptNextMatchHint),
        backgroundColor: const Color(0xFF7C3AED),
        duration: const Duration(seconds: 3),
      ),
    );
    AppNavigator.replaceWith(
      context,
      TournamentCameraSetupScreen(
        matchId: next.id,
        tournamentId: next.tournamentId,
        tournamentName: next.tournamentName ?? widget.tournamentName,
        roundName: next.roundName,
        opponentUsername: opponentUsername,
        opponentId: opponentId,
        player1Id: next.player1Id ?? '',
        player2Id: next.player2Id ?? '',
        bestOf: next.bestOf,
        inviteSentAt: next.inviteSentAt,
      ),
    );
    return true;
  }

  void _showPostponedDialogAndLeave() {
    if (!mounted || _navigating) return;
    _navigating = true;
    final l10n = AppLocalizations.of(context);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text(l10n.matchPostponedTitle, style: const TextStyle(color: Colors.white)),
        content: Text(
          l10n.matchPostponedBody,
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              if (mounted) Navigator.of(context).pop();
            },
            child: Text(l10n.ok),
          ),
        ],
      ),
    );
  }

  Future<void> _navigateToGame(String gameMatchId, {RtcV2Config? rtcV2Config}) async {
    if (!mounted || _navigating) return;
    _navigating = true;

    HapticService.heavyImpact();

    final user = context.read<AuthProvider>().currentUser;
    if (user == null) return;

    // The backend emits the final matchReadyUpdate and the start event in the
    // same tick, so navigating right away pre-empted the frame where the
    // opponent's card turns green — the lobby seemed to skip straight into
    // the match. Paint both cards "prêt" and hold a beat instead. Kept well
    // under the ~2s the backend waits before emitting game_started, so the
    // game screen's listeners are still armed in time.
    setState(() {
      _myReady = true;
      _opponentReady = true;
    });
    await Future.delayed(const Duration(milliseconds: 1100));
    if (!mounted) return;

    // Initialize the tournament game provider
    final tournamentGame = context.read<TournamentGameProvider>();
    tournamentGame.ensureListenersSetup();
    tournamentGame.initTournamentGame(
      tournamentMatchId: widget.matchId,
      gameMatchId: gameMatchId,
      tournamentId: widget.tournamentId,
      myUserId: user.id,
      opponentUserId: widget.opponentId,
      bestOf: widget.bestOf,
      roundName: widget.roundName,
      rtcV2Config: rtcV2Config,
    );

    AppNavigator.replaceWith(
      context,
      TournamentGameScreen(
        tournamentMatchId: widget.matchId,
        gameMatchId: gameMatchId,
        tournamentId: widget.tournamentId,
        tournamentName: widget.tournamentName,
        roundName: widget.roundName,
        opponentUsername: widget.opponentUsername,
        opponentId: widget.opponentId,
        bestOf: widget.bestOf,
      ),
    );
  }

  Future<void> _onCancelPressed() async {
    if (_cancelling) return;
    HapticService.lightImpact();
    setState(() => _cancelling = true);
    try {
      await TournamentService.setMatchUnready(widget.matchId);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      if (e.toString().contains('already started')) {
        // Both readied at the same moment — the start event is about to
        // navigate us into the game. Stay put.
        setState(() => _cancelling = false);
      } else {
        // Old backend (no unready endpoint) or transient error: leave anyway
        // rather than trapping the user on this screen.
        Navigator.of(context).pop();
      }
    }
  }

  @override
  void dispose() {
    _windowTimer?.cancel();
    _outcomePoll?.cancel();
    _statePoll?.cancel();
    _readySub?.cancel();
    _startSub?.cancel();
    _resultSub?.cancel();
    _pulseController.dispose();
    _tournamentProvider?.setMatchScreenClosed(widget.matchId);
    OrientationUtils.portraitOnly();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final user = context.read<AuthProvider>().currentUser;
    final myUsername = user?.username ?? l10n.you;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: DsScreenHeader(
                title: widget.tournamentName,
                showBack: true,
                onBack: _onCancelPressed,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
              child: Row(
                children: [
                  DsPill(label: localizedRoundName(widget.roundName, l10n)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${l10n.bestOf} ${widget.bestOf}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.caption,
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),

            // The two lobby seats: 56 px state disc, the name, and the ready
            // pill. The border turns green the moment a player is ready.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              // IntrinsicHeight so both seats share the taller card's height:
              // a bare `stretch` would ask for an infinite height inside this
              // unbounded Column.
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _buildPlayerCard(myUsername, _myReady, true)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Center(
                        child: Text(
                          l10n.vs,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.textTertiary,
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: _buildPlayerCard(widget.opponentUsername, _opponentReady, false),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 28),

            // Waiting indicator / expired state. Everyone on this screen has
            // already readied, so when the window closes with the opponent
            // still absent the verdict is "they no-showed, you advance" — the
            // red "YOU didn't join" copy would read as a loss. Reserve it for
            // the odd case where the opponent did ready (lost start event).
            if (_expired && _myReady && !_opponentReady)
              _buildStatusBlock(
                icon: Icons.hourglass_bottom_rounded,
                color: AppTheme.primaryLight,
                title: l10n.opponentNoShowTitle,
                hint: l10n.opponentNoShowHint,
                spinner: true,
              )
            else if (_expired)
              _buildStatusBlock(
                icon: Icons.timer_off_outlined,
                color: AppTheme.error,
                title: l10n.matchWindowExpiredTitle,
                hint: l10n.matchWindowExpiredHint,
              )
            else
              Column(
                children: [
                  AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, child) {
                      return Opacity(opacity: 0.5 + (_pulseController.value * 0.5), child: child);
                    },
                    child: Column(
                      children: [
                        const SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(
                            color: AppTheme.primary,
                            strokeWidth: 2.5,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          dsSentence(_opponentReady ? l10n.startingMatch : l10n.waitingForOpponent),
                          textAlign: TextAlign.center,
                          style: AppTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                  if (widget.inviteSentAt != null && !_opponentReady) ...[
                    const SizedBox(height: 14),
                    _buildCountdown(),
                  ],
                ],
              ),

            const Spacer(),

            // Back button — withdraws the ready state server-side so the
            // opponent readying later doesn't start a game with nobody here.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: TextButton(
                onPressed: _cancelling ? null : _onCancelPressed,
                child: Text(dsSentence(l10n.cancelButton)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Expired / no-show block: a quiet 20 px glyph, the verdict and its hint.
  Widget _buildStatusBlock({
    required IconData icon,
    required Color color,
    required String title,
    required String hint,
    bool spinner = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          Icon(icon, size: 26, color: color),
          const SizedBox(height: 12),
          Text(
            dsSentence(title),
            textAlign: TextAlign.center,
            style: AppTheme.titleLarge.copyWith(color: color),
          ),
          const SizedBox(height: 6),
          Text(hint, textAlign: TextAlign.center, style: AppTheme.caption),
          if (spinner) ...[
            const SizedBox(height: 16),
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(color: AppTheme.textSecondary, strokeWidth: 2),
            ),
          ],
        ],
      ),
    );
  }

  /// mm:ss left in the join window, 14 / 700 tabular; red under a minute.
  Widget _buildCountdown() {
    final low = _remaining.inSeconds <= 60;
    final color = low ? AppTheme.error : AppTheme.textPrimary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.schedule_outlined, size: 16, color: AppTheme.textSecondary),
        const SizedBox(width: 6),
        Text(
          _formatRemaining(_remaining),
          style: TextStyle(
            color: color,
            fontSize: 14,
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }

  /// One lobby seat: 56 px state disc, the name, the ready pill. The card's
  /// hairline turns green when that player is in.
  Widget _buildPlayerCard(String username, bool isReady, bool isMe) {
    final l10n = AppLocalizations.of(context);
    return DsCard(
      radius: AppTheme.radiusRow,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
      side: BorderSide(color: isReady ? AppTheme.success.withValues(alpha: 0.45) : AppTheme.border),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isReady ? AppTheme.success.withValues(alpha: 0.14) : AppTheme.surfaceLight,
            ),
            child: Icon(
              isReady ? Icons.check_rounded : Icons.hourglass_empty_rounded,
              color: isReady ? AppTheme.success : AppTheme.textSecondary,
              size: 26,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            isMe ? l10n.you : username,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: AppTheme.rowTitle,
          ),
          const SizedBox(height: 8),
          DsPill(
            label: dsSentence(isReady ? l10n.ready : l10n.waiting2),
            color: isReady ? AppTheme.success : AppTheme.textSecondary,
            dot: !isReady,
          ),
        ],
      ),
    );
  }
}
