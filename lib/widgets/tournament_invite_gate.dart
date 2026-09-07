import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/tournament.dart';
import '../providers/auth_provider.dart';
import '../providers/game_provider.dart';
import '../providers/tournament_provider.dart';
import '../screens/tournament/tournament_camera_setup_screen.dart';
import '../utils/app_theme.dart';
import '../utils/dart_sound_service.dart';
import '../utils/haptic_service.dart';
import '../utils/round_labels.dart';
import 'design_system.dart';

/// Global, screen-independent "your tournament match is ready" prompt.
///
/// Companion to [FriendMatchGate] / [MatchmakingNavigationGate]: wrapped
/// around the whole app via MaterialApp.builder so the prompt reaches the
/// player whatever screen they are on — spectating, chatting, in settings.
///
/// Why: a tournament invite opens a 7-minute join window and a no-show is a
/// forfeit. Until now the only in-app signals were the home Play button
/// recolouring and a dot on the Tournament tab, and Android shows no push
/// while the app is foregrounded. Tournoi #4 (2026-08-22): 7 of 11 forfeits
/// were players with the app open and the invite delivered to their socket.
///
/// The prompt is raised once per invite (the provider remembers which ids
/// were handled), is held back while a tournament lobby is open (the lobby
/// chains into the next match itself) or while a ranked/friendly game is
/// live (it is re-evaluated as soon as that game ends), and closes itself if
/// the invite stops being joinable.
class TournamentInviteGate extends StatefulWidget {
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  const TournamentInviteGate({
    super.key,
    required this.navigatorKey,
    required this.child,
  });

  @override
  State<TournamentInviteGate> createState() => _TournamentInviteGateState();
}

class _TournamentInviteGateState extends State<TournamentInviteGate> {
  TournamentProvider? _tournaments;
  GameProvider? _game;
  AuthProvider? _auth;

  bool _prompting = false;
  String? _promptedMatchId;
  bool _evaluationScheduled = false;
  StreamSubscription<Map<String, dynamic>>? _reminderSub;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final auth = context.read<AuthProvider>();
    if (!identical(auth, _auth)) {
      _auth?.removeListener(_onChange);
      _auth = auth..addListener(_onChange);
    }
    final tournaments = context.read<TournamentProvider>();
    if (!identical(tournaments, _tournaments)) {
      _tournaments?.removeListener(_onChange);
      _tournaments = tournaments..addListener(_onChange);
      _reminderSub?.cancel();
      _reminderSub = tournaments.inviteReminders.listen(_onReminder);
    }
    final game = context.read<GameProvider>();
    if (!identical(game, _game)) {
      _game?.removeListener(_onChange);
      _game = game..addListener(_onChange);
    }
  }

  // Providers notify from async completions and socket callbacks, never from
  // inside a build — but pushing a route straight out of a listener is still
  // fragile (a notify can land mid-transition). Coalesce and defer.
  void _onChange() {
    if (_evaluationScheduled) return;
    _evaluationScheduled = true;
    Future.microtask(() {
      _evaluationScheduled = false;
      if (mounted) _evaluate();
    });
  }

  // Half-window nudge from the backend: prompt again for this invite, unless
  // it is on screen right now or the player is already in its lobby /
  // camera setup. The provider refreshes pendingMatches right after, which
  // runs _evaluate with the mark cleared.
  void _onReminder(Map<String, dynamic> data) {
    final matchId = data['matchId']?.toString();
    final tournaments = _tournaments;
    if (matchId == null || tournaments == null) return;
    if (_prompting && _promptedMatchId == matchId) return;
    if (tournaments.openMatchScreenId == matchId) return;
    tournaments.unmarkInviteHandled(matchId);
    _onChange();
  }

  bool get _inLiveGame {
    final g = _game;
    if (g == null) return false;
    return g.matchId != null && g.gameStarted && !g.matchOver;
  }

  void _evaluate() {
    final tournaments = _tournaments;
    final myUserId = tournaments?.myUserId ?? _auth?.currentUser?.id;
    if (tournaments == null || myUserId == null) return;
    if (_prompting) return;
    // A lobby / camera-setup is open: it owns the flow (and the "you
    // advance" dialog chains into the next invite itself).
    if (tournaments.openMatchScreenId != null) return;
    // Mid-game the prompt would sit on top of the board. The game provider
    // notifies when the match ends, which re-runs this.
    if (_inLiveGame) return;

    final invite = tournaments.nextUnhandledInvite();
    if (invite == null) return;
    final navigator = widget.navigatorKey.currentState;
    if (navigator == null) return;

    tournaments.markInviteHandled(invite.id);
    _prompting = true;
    _promptedMatchId = invite.id;

    DartSoundService.playMatchFound();
    HapticService.heavyImpact();
    Future.delayed(const Duration(milliseconds: 350), HapticService.vibrate);

    navigator
        .push(_InvitePromptRoute(match: invite, myUserId: myUserId))
        .whenComplete(() {
          _prompting = false;
          _promptedMatchId = null;
          // Another invite may have queued up behind this one.
          _onChange();
        });
  }

  @override
  void dispose() {
    _reminderSub?.cancel();
    _tournaments?.removeListener(_onChange);
    _game?.removeListener(_onChange);
    _auth?.removeListener(_onChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Dimmed, non-dismissible overlay route (the buttons are the only way out).
class _InvitePromptRoute extends PageRouteBuilder<void> {
  _InvitePromptRoute({required TournamentMatch match, required String myUserId})
    : super(
        opaque: false,
        barrierDismissible: false,
        // The app background at 92 %: the screen underneath is still
        // legible as a hint of where the player was, the card is not.
        barrierColor: AppTheme.background.withValues(alpha: 0.92),
        transitionDuration: const Duration(milliseconds: 260),
        reverseTransitionDuration: const Duration(milliseconds: 180),
        pageBuilder: (_, _, _) =>
            _TournamentInvitePrompt(match: match, myUserId: myUserId),
        transitionsBuilder: (_, animation, _, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutBack,
          );
          return FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.88, end: 1).animate(curved),
              child: child,
            ),
          );
        },
      );
}

class _TournamentInvitePrompt extends StatefulWidget {
  final TournamentMatch match;
  final String myUserId;

  const _TournamentInvitePrompt({required this.match, required this.myUserId});

  @override
  State<_TournamentInvitePrompt> createState() =>
      _TournamentInvitePromptState();
}

class _TournamentInvitePromptState extends State<_TournamentInvitePrompt> {
  Timer? _ticker;
  Duration? _remaining;
  TournamentProvider? _tournaments;
  bool _leaving = false;

  TournamentMatch get match => widget.match;

  bool get _isPlayer1 => match.player1Id == widget.myUserId;
  String get _opponentId =>
      (_isPlayer1 ? match.player2Id : match.player1Id) ?? '';
  String get _opponentUsername =>
      (_isPlayer1 ? match.player2Username : match.player1Username) ?? '';

  @override
  void initState() {
    super.initState();
    // First value without the expiry check: the gate only raises the prompt
    // for an open window, and _dismiss() needs a mounted route anyway.
    _remaining = _timeLeft();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tournaments = context.read<TournamentProvider>();
    if (!identical(tournaments, _tournaments)) {
      _tournaments?.removeListener(_onTournamentsChanged);
      _tournaments = tournaments..addListener(_onTournamentsChanged);
    }
  }

  // The invite stopped being joinable under us (sweep forfeited it, the
  // player readied from another path, the match got postponed): close rather
  // than offer a button that leads to an error.
  void _onTournamentsChanged() {
    final tournaments = _tournaments;
    if (tournaments == null || !mounted) return;
    final stillPending = tournaments.pendingMatches.any(
      (m) => m.id == match.id,
    );
    if (!stillPending) _dismiss();
  }

  Duration? _timeLeft() {
    final sentAt = match.inviteSentAt;
    if (sentAt == null) return null;
    return sentAt.add(TournamentProvider.joinWindow).difference(DateTime.now());
  }

  // Seconds spent past the deadline, to throttle the refresh below.
  int _expiredTicks = 0;

  void _tick() {
    final remaining = _timeLeft();
    if (remaining == null || !mounted) return;
    if (remaining <= Duration.zero) {
      // Window gone by this phone's clock. The server decides (its sweep
      // forfeits within ~10 s): show 00:00 and poll until the invite drops
      // out of the pending list, which closes the prompt.
      setState(() => _remaining = Duration.zero);
      if (_expiredTicks++ % 5 == 0) _tournaments?.loadPendingMatches();
      return;
    }
    setState(() => _remaining = remaining);
  }

  void _dismiss() {
    if (_leaving || !mounted) return;
    _leaving = true;
    final route = ModalRoute.of(context);
    if (route != null && route.isCurrent) {
      Navigator.of(context).pop();
    } else if (route != null) {
      Navigator.of(context).removeRoute(route);
    }
  }

  void _join() {
    if (_leaving) return;
    _leaving = true;
    HapticService.mediumImpact();
    // Same stack reset as the friendly-match gate: whatever the player was
    // doing (spectating, chatting) is abandoned — the camera is needed now —
    // and the tournament flow sits directly above home.
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => TournamentCameraSetupScreen(
          matchId: match.id,
          tournamentId: match.tournamentId,
          tournamentName: match.tournamentName ?? 'Tournament',
          roundName: match.roundName,
          opponentUsername: _opponentUsername,
          opponentId: _opponentId,
          player1Id: match.player1Id ?? '',
          player2Id: match.player2Id ?? '',
          bestOf: match.bestOf,
          inviteSentAt: match.inviteSentAt,
        ),
      ),
      (route) => route.isFirst,
    );
  }

  String _format(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _tournaments?.removeListener(_onTournamentsChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final remaining = _remaining;
    final urgent = remaining != null && remaining < const Duration(minutes: 2);

    // Same card as the pinned invitation on the Tournament tab
    // (tournament_screen.dart: _MatchInviteCard), promoted to a modal: a flat
    // surface with the sky hairline, a 24 / 800 title, caption lines, the one
    // filled button, and "Plus tard" as a text link.
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: DsCard(
                  side: BorderSide(
                    color: AppTheme.primaryLight.withValues(alpha: 0.45),
                  ),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Why this is on top of whatever the player was doing.
                      Text(
                        dsSentence(l10n.tournamentInvitePromptTitle),
                        style: AppTheme.displayMedium,
                      ),
                      const SizedBox(height: 8),
                      // Tournament · round.
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              match.tournamentName ?? l10n.tournament,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTheme.caption,
                            ),
                          ),
                          const Text(' · ', style: AppTheme.caption),
                          Text(
                            localizedRoundLabel(l10n, match),
                            style: AppTheme.caption,
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      // Opponent + format.
                      Row(
                        children: [
                          const Icon(
                            Icons.person_outline_rounded,
                            size: 16,
                            color: AppTheme.textSecondary,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '${l10n.vs} $_opponentUsername',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTheme.caption.copyWith(
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${l10n.bestOf} ${match.bestOf}',
                            style: AppTheme.caption,
                          ),
                        ],
                      ),
                      if (remaining != null) ...[
                        const SizedBox(height: 8),
                        // Countdown: red under two minutes, never gold.
                        Row(
                          children: [
                            const Icon(
                              Icons.schedule_outlined,
                              size: 16,
                              color: AppTheme.textSecondary,
                            ),
                            const SizedBox(width: 6),
                            Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: '${l10n.timeRemaining}: ',
                                    style: AppTheme.caption,
                                  ),
                                  TextSpan(
                                    text: _format(remaining),
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: urgent
                                          ? AppTheme.error
                                          : AppTheme.textPrimary,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 16),
                      // The one filled block: themed primary button.
                      ElevatedButton(
                        onPressed: _join,
                        child: Text(
                          dsSentence(l10n.acceptAndJoin),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        l10n.tournamentInvitePromptForfeitWarning,
                        style: AppTheme.caption,
                      ),
                      const SizedBox(height: 4),
                      Center(
                        child: TextButton(
                          onPressed: _dismiss,
                          child: Text(l10n.tournamentInvitePromptLater),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
