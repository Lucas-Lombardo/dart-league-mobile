import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../l10n/app_localizations.dart';
import '../providers/auth_provider.dart';
import '../providers/game_provider.dart';
import '../providers/match_invite_provider.dart';
import '../screens/game/game_screen.dart';
import '../screens/matchmaking/camera_setup_screen.dart';
import '../utils/app_theme.dart';

/// Global, screen-independent handler for friend-invite ("friendly") matches.
///
/// Companion to [MatchmakingNavigationGate]: wrapped around the whole app via
/// MaterialApp.builder so an incoming invite popup and the jump into
/// [GameScreen] work no matter which screen the user is on. The inviter's
/// "waiting room" is a dedicated screen (FriendMatchWaitingScreen), so this gate
/// only owns: auth start/stop, the incoming invite popup, and match-start
/// navigation.
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
  bool _incomingShown = false;
  BuildContext? _incomingDialogCtx;

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
  BuildContext? get _navContext => widget.navigatorKey.currentContext;

  void _onInviteUpdate() {
    final p = _provider;
    if (p == null) return;

    // Match starting wins over everything — navigate in.
    if (p.friendlyMatchFound && !_navigating) {
      _navigating = true;
      _navigateToGame(p);
      return;
    }

    // Incoming invite popup (invitee).
    if (p.incoming != null && !_incomingShown) {
      _showIncomingDialog(p);
    } else if (p.incoming == null && _incomingShown) {
      _dismissIncoming();
    }
  }

  void _showIncomingDialog(MatchInviteProvider p) {
    final ctx = _navContext;
    final invite = p.incoming;
    if (ctx == null || invite == null) return;
    _incomingShown = true;
    showDialog<void>(
      context: ctx,
      barrierDismissible: false,
      builder: (dialogCtx) {
        _incomingDialogCtx = dialogCtx;
        final l10n = AppLocalizations.of(dialogCtx);
        return AlertDialog(
          backgroundColor: AppTheme.surface,
          title: Text(l10n.matchInviteTitle,
              style: const TextStyle(color: Colors.white)),
          content: Text(
            l10n.invitedYouToMatch
                .replaceAll('{username}', invite.inviterUsername),
            style: const TextStyle(color: AppTheme.textSecondary),
          ),
          actions: [
            TextButton(
              // Sets incoming=null → the gate dismisses this dialog reactively.
              onPressed: () => p.decline(invite.inviteId),
              child: Text(l10n.declineInvite,
                  style: const TextStyle(color: AppTheme.error)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                final id = invite.inviteId;
                final label = l10n.joinMatch;
                p.clearIncoming(); // dismisses this dialog reactively
                _goToCameraThenAccept(id, label);
              },
              child: Text(l10n.joinMatch),
            ),
          ],
        );
      },
    ).then((_) {
      _incomingShown = false;
      _incomingDialogCtx = null;
    });
  }

  void _dismissIncoming() {
    final c = _incomingDialogCtx;
    if (c != null && Navigator.canPop(c)) Navigator.of(c).pop();
    _incomingShown = false;
    _incomingDialogCtx = null;
  }

  /// Route the invitee through the same camera/permission gate as ranked, then
  /// accept once they confirm. The match-start navigation is handled below.
  Future<void> _goToCameraThenAccept(String inviteId, String label) async {
    final navigator = _navigator;
    final p = _provider;
    if (navigator == null || p == null) return;
    final ready = await navigator.push<bool>(
      MaterialPageRoute(
        builder: (_) => CameraSetupScreen(actionLabel: label, confirmAndPop: true),
      ),
    );
    if (ready == true) p.accept(inviteId);
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
      // pushAndRemoveUntil removed any open dialogs / the waiting screen too.
      _incomingShown = false;
      _incomingDialogCtx = null;
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
