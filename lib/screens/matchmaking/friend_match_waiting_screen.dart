import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/user.dart';
import '../../providers/match_invite_provider.dart';
import '../../utils/app_theme.dart';
import '../../utils/haptic_service.dart';
import '../../widgets/design_system.dart';
import '../../widgets/premium_badge.dart';
import '../../widgets/rank_badge.dart';

/// Full-screen "waiting room" shown to the inviter after they send a friendly
/// match invite, centred on the invited friend. Resolves to declined /
/// expired states; the global FriendMatchGate navigates into the game when
/// the friend accepts (which pops this screen via pushAndRemoveUntil).
class FriendMatchWaitingScreen extends StatefulWidget {
  final User opponent;

  const FriendMatchWaitingScreen({super.key, required this.opponent});

  @override
  State<FriendMatchWaitingScreen> createState() =>
      _FriendMatchWaitingScreenState();
}

class _FriendMatchWaitingScreenState extends State<FriendMatchWaitingScreen> {
  Timer? _timeout;
  bool _expired = false;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _armTimeout();
  }

  /// Backend invites expire after ~150s (FRIEND_INVITE_TTL_MS) — long enough
  /// for an offline friend to open the app from the push and accept. Keep the
  /// local timeout just past that so we only show "expired" once the
  /// server-side invite is truly gone, then release it. Re-armed when a
  /// refused cricket invite is re-sent as a 501.
  void _armTimeout() {
    _timeout?.cancel();
    _timeout = Timer(const Duration(seconds: 155), () {
      if (!mounted) return;
      final p = context.read<MatchInviteProvider>();
      if (p.outgoingResolved == null && !_expired) {
        p.cancelOutgoing();
        setState(() => _expired = true);
      }
    });
  }

  void _retryAsX01() {
    HapticService.mediumImpact();
    context.read<MatchInviteProvider>().retryAsX01();
    setState(() => _expired = false);
    _armTimeout();
  }

  @override
  void dispose() {
    _timeout?.cancel();
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

  /// The friend's app can't play cricket — surfaced by the server at send,
  /// replay or accept time. The one refusal with a recourse (offer a 501).
  bool _needsUpdate(MatchInviteProvider p) =>
      p.outgoingResolved == 'opponent_needs_update' ||
      p.lastError == 'opponent_needs_update';

  String _statusText(AppLocalizations l10n, MatchInviteProvider p) {
    if (_expired) return l10n.inviteCancelledMsg;
    if (_needsUpdate(p)) return l10n.opponentNeedsUpdateCricket;
    if (p.outgoingResolved != null) return l10n.inviteDeclinedMsg;
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
        _expired || p.outgoingResolved != null || p.lastError != null;
    final needsUpdate = _needsUpdate(p) && !_expired;
    final isCricket = p.outgoingGameMode.startsWith('cricket');

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && !_leaving && !resolved) {
          context.read<MatchInviteProvider>().cancelOutgoing();
        }
      },
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: DsScreenHeader(
                  title: l10n.friendlyMatchLabel,
                  showBack: true,
                  onBack: resolved ? _back : _cancelAndLeave,
                  actions: [
                    if (isCricket)
                      DsPill(
                        label:
                            '${l10n.cricketLabel} · ${p.outgoingGameMode == 'cricket_noscore' ? l10n.cricketNoScoreLabel : l10n.cricketScoreLabel}',
                        color: AppTheme.success,
                      ),
                  ],
                ),
              ),
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        RankBadge(
                          rank: widget.opponent.rank,
                          size: 80,
                          showLabel: false,
                        ),
                        const SizedBox(height: 18),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                widget.opponent.username,
                                style: AppTheme.titleLarge,
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
                        const SizedBox(height: 8),
                        Text(
                          _statusText(l10n, p),
                          textAlign: TextAlign.center,
                          style: AppTheme.bodyMedium,
                        ),
                        if (!resolved) ...[
                          const SizedBox(height: 22),
                          const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              color: AppTheme.primary,
                              strokeWidth: 2.5,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  children: [
                    if (resolved && needsUpdate) ...[
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _retryAsX01,
                          child: Text(dsSentence(l10n.proposeX01Instead)),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: resolved
                          ? (needsUpdate
                              ? OutlinedButton(
                                  onPressed: _back,
                                  child: Text(dsSentence(l10n.close)),
                                )
                              : ElevatedButton(
                                  onPressed: _back,
                                  child: Text(dsSentence(l10n.close)),
                                ))
                          : OutlinedButton(
                              onPressed: _cancelAndLeave,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppTheme.error,
                              ),
                              child: Text(dsSentence(l10n.cancel)),
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
