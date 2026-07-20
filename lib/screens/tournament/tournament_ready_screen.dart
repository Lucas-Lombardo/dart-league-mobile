import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../utils/app_navigator.dart';
import '../../utils/app_theme.dart';
import '../../utils/haptic_service.dart';
import '../../utils/orientation_utils.dart';
import '../../utils/tournament_round.dart';
import '../../models/tournament.dart';
import '../../services/tournament_service.dart';
import '../../providers/tournament_game_provider.dart';
import '../../providers/tournament_provider.dart';
import '../../providers/auth_provider.dart';
import '../../l10n/app_localizations.dart';
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

  // 5-minute join window (mirrors the backend MATCH_INVITE_TIMEOUT_MS).
  static const Duration _joinWindow = Duration(minutes: 5);
  Timer? _windowTimer;
  Duration _remaining = Duration.zero;
  bool _expired = false;

  // After expiry the backend sweep (runs every minute) settles the match;
  // poll the bracket until we can tell the player what actually happened.
  Timer? _outcomePoll;
  int _outcomePollTries = 0;

  // Socket-independent safety net. matchReadyUpdate/tournamentMatchStart are
  // fire-and-forget emits with no server-side replay: if this device's socket
  // wasn't registered at that instant, the event is lost and both players sit
  // here until the invite sweep forfeits them. Poll the ready-state endpoint
  // and navigate from it when the emit was missed.
  Timer? _statePoll;

  @override
  void initState() {
    super.initState();
    OrientationUtils.allowAll();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

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
        _navigateToGame(
          gameMatchId,
          agoraAppId: data['agoraAppId'] as String?,
          agoraToken: data['agoraToken'] as String?,
          agoraTokenStrict: data['agoraTokenStrict'] as String?,
          agoraChannelName: data['agoraChannelName'] as String?,
          agoraUid: (data['agoraUid'] as num?)?.toInt(),
          opponentAgoraUid: (data['opponentAgoraUid'] as num?)?.toInt(),
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
            _navigateToGame(
              gameMatchId,
              agoraAppId: start['agoraAppId'] as String?,
              agoraToken: start['agoraToken'] as String?,
              agoraTokenStrict: start['agoraTokenStrict'] as String?,
              agoraChannelName: start['agoraChannelName'] as String?,
              agoraUid: (start['agoraUid'] as num?)?.toInt(),
              opponentAgoraUid: (start['opponentAgoraUid'] as num?)?.toInt(),
            );
          }
        }
      } catch (_) {
        // Transient (or old backend without the endpoint) — the socket path
        // still does the job; next tick retries.
      }
    });
  }

  // The backend sweep runs every minute after the 5-minute deadline. Poll the
  // bracket a few times to tell the player how it ended instead of leaving
  // them staring at "expired" forever.
  void _startOutcomePolling() {
    _outcomePoll?.cancel();
    _outcomePollTries = 0;
    _outcomePoll = Timer.periodic(const Duration(seconds: 10), (_) async {
      if (!mounted || _navigating) {
        _outcomePoll?.cancel();
        return;
      }
      _outcomePollTries++;
      if (_outcomePollTries > 18) {
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
              if (mounted) Navigator.of(context).pop();
            },
            child: Text(l10n.ok),
          ),
        ],
      ),
    );
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

  Future<void> _navigateToGame(String gameMatchId, {String? agoraAppId, String? agoraToken, String? agoraTokenStrict, String? agoraChannelName, int? agoraUid, int? opponentAgoraUid}) async {
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
      agoraAppId: agoraAppId,
      agoraToken: agoraToken,
      agoraTokenStrict: agoraTokenStrict,
      agoraChannelName: agoraChannelName,
      agoraUid: agoraUid,
      opponentAgoraUid: opponentAgoraUid,
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
            const SizedBox(height: 40),
            // Tournament info
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
              ),
              child: Column(
                children: [
                  Text(
                    widget.tournamentName,
                    style: const TextStyle(
                      color: AppTheme.primary,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${localizedRoundName(widget.roundName, l10n).toUpperCase()} • ${l10n.bestOf} ${widget.bestOf}',
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),

            const Spacer(),

            // Player cards
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Row(
                children: [
                  Expanded(child: _buildPlayerCard(myUsername, _myReady, true)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      l10n.vs.toUpperCase(),
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                  Expanded(child: _buildPlayerCard(widget.opponentUsername, _opponentReady, false)),
                ],
              ),
            ),

            const SizedBox(height: 48),

            // Waiting indicator / expired state
            if (_expired)
              Column(
                children: [
                  const Icon(Icons.timer_off_outlined, size: 44, color: AppTheme.error),
                  const SizedBox(height: 12),
                  Text(
                    l10n.matchWindowExpiredTitle,
                    style: const TextStyle(
                      color: AppTheme.error,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      l10n.matchWindowExpiredHint,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
                    ),
                  ),
                ],
              )
            else
              Column(
                children: [
                  AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, child) {
                      return Opacity(
                        opacity: 0.5 + (_pulseController.value * 0.5),
                        child: child,
                      );
                    },
                    child: Column(
                      children: [
                        const SizedBox(
                          width: 32,
                          height: 32,
                          child: CircularProgressIndicator(
                            color: AppTheme.primary,
                            strokeWidth: 3,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _opponentReady ? l10n.startingMatch : l10n.waitingForOpponent,
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (widget.inviteSentAt != null && !_opponentReady) ...[
                    const SizedBox(height: 16),
                    _buildCountdownPill(),
                  ],
                ],
              ),

            const Spacer(),

            // Back button — withdraws the ready state server-side so the
            // opponent readying later doesn't start a game with nobody here.
            Padding(
              padding: const EdgeInsets.all(24),
              child: TextButton(
                onPressed: _cancelling ? null : _onCancelPressed,
                child: Text(
                  AppLocalizations.of(context).cancelButton,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCountdownPill() {
    final low = _remaining.inSeconds <= 60;
    final color = low ? AppTheme.error : AppTheme.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.timer_outlined, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            _formatRemaining(_remaining),
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.bold,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayerCard(String username, bool isReady, bool isMe) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isReady ? AppTheme.success : AppTheme.surfaceLight,
          width: isReady ? 2 : 1,
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: isReady
                  ? AppTheme.success.withValues(alpha: 0.2)
                  : AppTheme.surfaceLight,
              shape: BoxShape.circle,
            ),
            child: Icon(
              isReady ? Icons.check : Icons.hourglass_empty,
              color: isReady ? AppTheme.success : AppTheme.textSecondary,
              size: 28,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            isMe ? AppLocalizations.of(context).you : username,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            isReady ? AppLocalizations.of(context).ready : AppLocalizations.of(context).waiting2,
            style: TextStyle(
              color: isReady ? AppTheme.success : AppTheme.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}
