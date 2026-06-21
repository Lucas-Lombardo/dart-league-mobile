import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/user.dart';
import '../../providers/match_invite_provider.dart';
import '../../utils/app_theme.dart';
import '../../utils/haptic_service.dart';
import '../../widgets/premium_badge.dart';
import '../../widgets/rank_badge.dart';

/// Full-screen "waiting room" shown to the inviter after they send a friendly
/// match invite. Reuses the app's matchmaking radar/pulse language but centred
/// on the invited friend. Resolves to declined / expired states; the global
/// FriendMatchGate navigates into the game when the friend accepts (which pops
/// this screen via pushAndRemoveUntil).
class FriendMatchWaitingScreen extends StatefulWidget {
  final User opponent;

  const FriendMatchWaitingScreen({super.key, required this.opponent});

  @override
  State<FriendMatchWaitingScreen> createState() =>
      _FriendMatchWaitingScreenState();
}

class _FriendMatchWaitingScreenState extends State<FriendMatchWaitingScreen>
    with TickerProviderStateMixin {
  late final AnimationController _pulse;
  late final AnimationController _ripple;
  Timer? _timeout;
  bool _expired = false;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _ripple = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();

    // Backend invites expire after ~150s (FRIEND_INVITE_TTL_MS) — long enough
    // for an offline friend to open the app from the push and accept. Keep the
    // local timeout just past that so we only show "expired" once the
    // server-side invite is truly gone, then release it.
    _timeout = Timer(const Duration(seconds: 155), () {
      if (!mounted) return;
      final p = context.read<MatchInviteProvider>();
      if (p.outgoingResolved == null && !_expired) {
        p.cancelOutgoing();
        setState(() => _expired = true);
      }
    });
  }

  @override
  void dispose() {
    _timeout?.cancel();
    _pulse.dispose();
    _ripple.dispose();
    super.dispose();
  }

  void _cancelAndLeave() {
    if (_leaving) return;
    _leaving = true;
    HapticService.lightImpact();
    final p = context.read<MatchInviteProvider>();
    p.cancelOutgoing();
    Navigator.of(context).maybePop();
  }

  void _back() {
    if (_leaving) return;
    _leaving = true;
    HapticService.lightImpact();
    context.read<MatchInviteProvider>().clearOutgoing();
    Navigator.of(context).maybePop();
  }

  String _statusText(AppLocalizations l10n, MatchInviteProvider p) {
    if (_expired) return l10n.inviteCancelledMsg;
    if (p.outgoingResolved == 'declined') return l10n.inviteDeclinedMsg;
    if (p.lastError != null) {
      switch (p.lastError) {
        case 'friend_not_premium':
          return l10n.friendNeedsPremium;
        case 'inviter_not_premium':
        case 'premium_required':
          return l10n.friendlyMatchPremiumRequired;
        case 'player_busy':
        case 'you_busy':
          return l10n.playerBusyMsg;
        default:
          return l10n.inviteFailedMsg;
      }
    }
    return l10n.waitingForFriend
        .replaceAll('{username}', widget.opponent.username);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final p = context.watch<MatchInviteProvider>();
    final resolved =
        _expired || p.outgoingResolved == 'declined' || p.lastError != null;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && !_leaving && !resolved) {
          context.read<MatchInviteProvider>().cancelOutgoing();
        }
      },
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(gradient: AppTheme.surfaceGradient),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      l10n.friendlyMatchLabel.toUpperCase(),
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                        letterSpacing: 2,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildAvatarWithRings(resolved),
                          const SizedBox(height: 32),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  widget.opponent.username,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              PremiumBadge(
                                isPremium: widget.opponent.isPremiumActive,
                                size: 16,
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _statusText(l10n, p),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: resolved
                                  ? AppTheme.textSecondary
                                  : Colors.white,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: resolved
                        ? ElevatedButton(
                            onPressed: _back,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primary,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16)),
                            ),
                            child: Text(
                              l10n.close,
                              style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1),
                            ),
                          )
                        : OutlinedButton(
                            onPressed: _cancelAndLeave,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.error,
                              side: BorderSide(
                                  color:
                                      AppTheme.error.withValues(alpha: 0.5),
                                  width: 2),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16)),
                            ),
                            child: Text(
                              l10n.cancel,
                              style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAvatarWithRings(bool resolved) {
    final accent = resolved ? AppTheme.textSecondary : AppTheme.primary;
    return SizedBox(
      width: 240,
      height: 240,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Expanding ripples (only while actively waiting).
          if (!resolved)
            AnimatedBuilder(
              animation: _ripple,
              builder: (context, _) {
                return Stack(
                  alignment: Alignment.center,
                  children: List.generate(3, (i) {
                    final phase = (_ripple.value + i / 3) % 1.0;
                    final size = 120 + phase * 120;
                    return Opacity(
                      opacity: (1 - phase) * 0.5,
                      child: Container(
                        width: size,
                        height: size,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: AppTheme.primary.withValues(alpha: 0.6),
                              width: 2),
                        ),
                      ),
                    );
                  }),
                );
              },
            ),
          // Steady glowing ring behind the avatar.
          ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1.06).animate(
              CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
            ),
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    accent.withValues(alpha: 0.18),
                    accent.withValues(alpha: 0.04),
                    Colors.transparent,
                  ],
                ),
                border: Border.all(color: accent, width: 2),
                boxShadow: resolved
                    ? null
                    : [
                        BoxShadow(
                          color: accent.withValues(alpha: 0.3),
                          blurRadius: 24,
                          spreadRadius: 2,
                        ),
                      ],
              ),
            ),
          ),
          // Opponent avatar (rank badge).
          RankBadge(rank: widget.opponent.rank, size: 96, showLabel: false),
        ],
      ),
    );
  }
}
