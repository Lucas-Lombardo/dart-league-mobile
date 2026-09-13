import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/user.dart';
import '../providers/match_invite_provider.dart';
import '../providers/subscription_provider.dart';
import '../screens/matchmaking/camera_setup_screen.dart';
import '../screens/matchmaking/friend_match_waiting_screen.dart';
import '../screens/settings/subscription_screen.dart';
import '../services/socket_service.dart';
import 'app_navigator.dart';
import 'app_theme.dart';
import 'haptic_service.dart';

/// Shared launcher for the "play against a friend" (friendly match) flow.
///
/// Premium-gated on both sides; the backend re-validates. Routes through the
/// shared camera setup (friendly matches use video like ranked) before the
/// invite is sent, then drops into the waiting room. Used by both the friends
/// list and the new play-mode friend selector so the behaviour stays identical.
class FriendlyMatchLauncher {
  FriendlyMatchLauncher._();

  static Future<void> invite(BuildContext context, User friend) async {
    final l10n = AppLocalizations.of(context);
    HapticService.lightImpact();

    final subscription = context.read<SubscriptionProvider>();
    // During Free Play (Sat 20:00–00:00 Europe/Paris) friend matches are open to
    // everyone; otherwise both players must be premium. The backend re-validates
    // this exact rule on invite/accept either way.
    if (!subscription.freePlayActive) {
      if (!subscription.isPremiumActive) {
        _showPremiumRequiredDialog(context, l10n);
        return;
      }
      if (!friend.isPremiumActive) {
        _showInfoDialog(context, l10n.friendNeedsPremium);
        return;
      }
    }

    // Capabilities arrive with authentication, including after reconnect.
    try {
      await SocketService.ensureAuthenticated();
    } catch (_) {}
    if (!context.mounted) return;
    var config = (gameMode: 'x01', bestOf: 1);
    if (SocketService.supportsCricket || SocketService.supportsFriendlySeries) {
      final choice =
          await showModalBottomSheet<({String gameMode, int bestOf})>(
            context: context,
            backgroundColor: AppTheme.surface,
            isScrollControlled: true,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            builder: (_) => FriendlyMatchSetupSheet(
              friendUsername: friend.username,
              supportsCricket: SocketService.supportsCricket,
              supportsSeries: SocketService.supportsFriendlySeries,
            ),
          );
      if (choice == null || !context.mounted) return;
      config = choice;
    }

    final inviteProvider = context.read<MatchInviteProvider>();
    // Pass the same camera/permission gate as ranked, then send the invite and
    // drop into the waiting room.
    final ready = await AppNavigator.toScreen<bool>(
      context,
      CameraSetupScreen(actionLabel: l10n.inviteToPlay, confirmAndPop: true),
    );
    if (ready != true || !context.mounted) return;
    inviteProvider.invite(
      friend.id,
      friendUsername: friend.username,
      gameMode: config.gameMode,
      bestOf: config.bestOf,
    );
    if (context.mounted) {
      AppNavigator.toScreen(
        context,
        FriendMatchWaitingScreen(opponent: friend),
      );
    }
  }

  static void _showPremiumRequiredDialog(
    BuildContext context,
    AppLocalizations l10n,
  ) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text(l10n.premium, style: const TextStyle(color: Colors.white)),
        content: Text(
          l10n.friendlyMatchPremiumRequired,
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              l10n.cancel,
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              AppNavigator.toScreen(context, const SubscriptionScreen());
            },
            child: Text(l10n.upgrade),
          ),
        ],
      ),
    );
  }

  static void _showInfoDialog(BuildContext context, String message) {
    final l10n = AppLocalizations.of(context);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        content: Text(
          message,
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              l10n.close,
              style: const TextStyle(color: AppTheme.primary),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shared invitation setup: game mode and best-of format before the camera gate.
class FriendlyMatchSetupSheet extends StatefulWidget {
  final String friendUsername;
  final bool supportsCricket;
  final bool supportsSeries;

  const FriendlyMatchSetupSheet({
    super.key,
    required this.friendUsername,
    required this.supportsCricket,
    required this.supportsSeries,
  });

  @override
  State<FriendlyMatchSetupSheet> createState() => _FriendlyModeSheetState();
}

class _FriendlyModeSheetState extends State<FriendlyMatchSetupSheet> {
  bool _noScore = false;
  bool _cricket = false;
  int _bestOf = 1;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.challengeFriendTitle(widget.friendUsername),
              style: AppTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              l10n.challengeChooseGame,
              style: const TextStyle(color: AppTheme.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _choice(
                  '501',
                  !_cricket,
                  () => setState(() => _cricket = false),
                ),
                if (widget.supportsCricket) ...[
                  const SizedBox(width: 8),
                  _choice(
                    l10n.cricketLabel,
                    _cricket,
                    () => setState(() => _cricket = true),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _cricket ? l10n.cricketSetupHint : l10n.friendlyX01Hint,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 13,
              ),
            ),
            if (_cricket) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  _choice(
                    l10n.cricketScoreLabel,
                    !_noScore,
                    () => setState(() => _noScore = false),
                  ),
                  const SizedBox(width: 8),
                  _choice(
                    l10n.cricketNoScoreLabel,
                    _noScore,
                    () => setState(() => _noScore = true),
                  ),
                ],
              ),
            ],
            if (widget.supportsSeries) ...[
              const SizedBox(height: 24),
              Row(
                children: [
                  for (final bestOf in const [1, 3, 5, 7]) ...[
                    if (bestOf != 1) const SizedBox(width: 8),
                    _choice(
                      'BO$bestOf',
                      _bestOf == bestOf,
                      () => setState(() => _bestOf = bestOf),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Text(
                l10n.firstToNLegs((_bestOf ~/ 2) + 1),
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 13,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 24),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed: () {
                HapticService.mediumImpact();
                Navigator.of(context).pop((
                  gameMode: _cricket
                      ? (_noScore ? 'cricket_noscore' : 'cricket_score')
                      : 'x01',
                  bestOf: _bestOf,
                ));
              },
              child: Text(l10n.continueButton),
            ),
          ],
        ),
      ),
    );
  }

  Widget _choice(String label, bool selected, VoidCallback onTap) {
    return Expanded(
      child: Semantics(
        selected: selected,
        button: true,
        child: Material(
          color: selected
              ? AppTheme.primary.withValues(alpha: 0.18)
              : AppTheme.surface,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: selected ? AppTheme.primary : AppTheme.surfaceLight,
                ),
              ),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: selected ? Colors.white : AppTheme.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
