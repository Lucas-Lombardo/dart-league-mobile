import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/user.dart';
import '../providers/match_invite_provider.dart';
import '../providers/subscription_provider.dart';
import '../screens/matchmaking/camera_setup_screen.dart';
import '../screens/matchmaking/friend_match_waiting_screen.dart';
import '../screens/settings/subscription_screen.dart';
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

    final inviteProvider = context.read<MatchInviteProvider>();
    // Pass the same camera/permission gate as ranked, then send the invite and
    // drop into the waiting room.
    final ready = await AppNavigator.toScreen<bool>(
      context,
      CameraSetupScreen(actionLabel: l10n.inviteToPlay, confirmAndPop: true),
    );
    if (ready != true || !context.mounted) return;
    inviteProvider.invite(friend.id, friendUsername: friend.username);
    if (context.mounted) {
      AppNavigator.toScreen(
        context,
        FriendMatchWaitingScreen(opponent: friend),
      );
    }
  }

  static void _showPremiumRequiredDialog(
      BuildContext context, AppLocalizations l10n) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text(l10n.premium, style: const TextStyle(color: Colors.white)),
        content: Text(l10n.friendlyMatchPremiumRequired,
            style: const TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.cancel,
                style: const TextStyle(color: AppTheme.textSecondary)),
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
        content: Text(message,
            style: const TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.close,
                style: const TextStyle(color: AppTheme.primary)),
          ),
        ],
      ),
    );
  }
}
