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
  bool _evaluationScheduled = false;

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

    DartSoundService.playMatchFound();
    HapticService.heavyImpact();
    Future.delayed(const Duration(milliseconds: 350), HapticService.vibrate);

    navigator
        .push(_InvitePromptRoute(match: invite, myUserId: myUserId))
        .whenComplete(() {
      _prompting = false;
      // Another invite may have queued up behind this one.
      _onChange();
    });
  }

  @override
  void dispose() {
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
          barrierColor: Colors.black.withValues(alpha: 0.82),
          transitionDuration: const Duration(milliseconds: 260),
          reverseTransitionDuration: const Duration(milliseconds: 180),
          pageBuilder: (_, _, _) =>
              _TournamentInvitePrompt(match: match, myUserId: myUserId),
          transitionsBuilder: (_, animation, _, child) {
            final curved =
                CurvedAnimation(parent: animation, curve: Curves.easeOutBack);
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

class _TournamentInvitePromptState extends State<_TournamentInvitePrompt>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
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
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
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
    final stillPending = tournaments.pendingMatches.any((m) => m.id == match.id);
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
    _pulse.dispose();
    _tournaments?.removeListener(_onTournamentsChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final remaining = _remaining;
    final urgent = remaining != null && remaining < const Duration(minutes: 2);
    const purple = Color(0xFF7C3AED);
    const purpleLight = Color(0xFF9333EA);

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 420),
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: purple.withValues(alpha: 0.6)),
                  boxShadow: [
                    BoxShadow(
                      color: purple.withValues(alpha: 0.35),
                      blurRadius: 40,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedBuilder(
                      animation: _pulse,
                      builder: (context, child) => Transform.scale(
                        scale: 1 + _pulse.value * 0.08,
                        child: child,
                      ),
                      child: Container(
                        width: 84,
                        height: 84,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            colors: [purple, purpleLight],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: purple.withValues(alpha: 0.5),
                              blurRadius: 24,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.emoji_events,
                          color: Colors.white,
                          size: 44,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      l10n.tournamentInvitePromptTitle,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${match.tournamentName ?? 'Tournament'} — ${localizedRoundLabel(l10n, match)}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (_opponentUsername.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        l10n.tournamentInvitePromptVersus(_opponentUsername),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    if (remaining != null) ...[
                      const SizedBox(height: 18),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: (urgent ? AppTheme.error : purple)
                              .withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.timer_outlined,
                              size: 18,
                              color: urgent ? AppTheme.error : purpleLight,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  l10n.tournamentInvitePromptCountdown(
                                      _format(remaining)),
                                  maxLines: 1,
                                  style: TextStyle(
                                    color:
                                        urgent ? AppTheme.error : purpleLight,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures()
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [purple, purpleLight],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: purple.withValues(alpha: 0.45),
                              blurRadius: 18,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: ElevatedButton.icon(
                          onPressed: _join,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          icon: const Icon(Icons.play_arrow_rounded, size: 26),
                          label: Text(
                            l10n.joinMatch,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      l10n.tournamentInvitePromptForfeitWarning,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextButton(
                      onPressed: _dismiss,
                      child: Text(
                        l10n.tournamentInvitePromptLater,
                        style: const TextStyle(color: AppTheme.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
