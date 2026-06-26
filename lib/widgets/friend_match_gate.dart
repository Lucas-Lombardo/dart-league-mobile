import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../providers/auth_provider.dart';
import '../providers/game_provider.dart';
import '../providers/match_invite_provider.dart';
import '../screens/game/game_screen.dart';

/// Global, screen-independent handler for friend-invite ("friendly") matches.
///
/// Companion to [MatchmakingNavigationGate]: wrapped around the whole app via
/// MaterialApp.builder so the jump into [GameScreen] works no matter which
/// screen the user is on. The incoming-invite *prompt* is surfaced as the home
/// "Play" button turning into "Join the match" (see PlayScreen); this gate now
/// owns only: auth-driven start/stop of the invite provider, and the
/// match-start navigation once both players are in.
class FriendMatchGate extends StatefulWidget {
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  const FriendMatchGate({
    super.key,
    required this.navigatorKey,
    required this.child,
  });

  @override
  State<FriendMatchGate> createState() => _FriendMatchGateState();
}

class _FriendMatchGateState extends State<FriendMatchGate> {
  MatchInviteProvider? _provider;
  AuthProvider? _auth;
  bool _navigating = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final auth = context.read<AuthProvider>();
    if (!identical(auth, _auth)) {
      _auth?.removeListener(_onAuthUpdate);
      _auth = auth;
      _auth!.addListener(_onAuthUpdate);
    }

    final provider = context.read<MatchInviteProvider>();
    if (!identical(provider, _provider)) {
      _provider?.removeListener(_onInviteUpdate);
      _provider = provider;
      _provider!.addListener(_onInviteUpdate);
    }
    _provider!.setGameProvider(context.read<GameProvider>());
    _onAuthUpdate();
  }

  void _onAuthUpdate() {
    final userId = _auth?.currentUser?.id;
    if (userId != null) {
      _provider?.start(userId);
    } else {
      _provider?.stop();
    }
  }

  NavigatorState? get _navigator => widget.navigatorKey.currentState;

  void _onInviteUpdate() {
    final p = _provider;
    if (p == null) return;

    // Match starting — navigate in. The incoming-invite prompt itself lives on
    // the home Play button (PlayScreen accept/decline), so this gate only
    // reacts to the match actually starting.
    if (p.friendlyMatchFound && !_navigating) {
      _navigating = true;
      _navigateToGame(p);
    }
  }

  void _navigateToGame(MatchInviteProvider p) {
    int attempts = 0;
    const maxAttempts = 50; // ~5s at 100ms

    void go() {
      final navigator = _navigator;
      if (navigator == null || p.matchId == null || p.opponentId == null) {
        _navigating = false;
        return;
      }
      navigator.pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => GameScreen(
            matchId: p.matchId!,
            opponentId: p.opponentId!,
            opponentUsername: p.opponentUsername ?? 'Opponent',
            agoraAppId: p.agoraAppId,
            agoraToken: p.agoraToken,
            agoraTokenStrict: p.agoraTokenStrict,
            agoraChannelName: p.agoraChannelName,
            agoraUid: p.agoraUid,
            opponentAgoraUid: p.opponentAgoraUid,
          ),
        ),
        (route) => route.isFirst,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) => WakelockPlus.enable());
      p.consumeFriendlyMatch();
      _navigating = false;
    }

    void check() {
      if (!mounted) {
        _navigating = false;
        return;
      }
      attempts++;
      final ready = p.agoraAppId != null &&
          p.agoraToken != null &&
          p.agoraChannelName != null;
      if (ready || attempts >= maxAttempts) {
        go();
        return;
      }
      Future.delayed(const Duration(milliseconds: 100), check);
    }

    check();
  }

  @override
  void dispose() {
    _provider?.removeListener(_onInviteUpdate);
    _auth?.removeListener(_onAuthUpdate);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
