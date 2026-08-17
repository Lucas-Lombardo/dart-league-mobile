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

    // Game mode picker — only when the backend can run cricket. Against an
    // older server the sheet is skipped and the flow stays exactly as before
    // (X01, payload untouched). The flag only lands with the server's
    // `authenticated` handshake (reset to false on every disconnect), so wait
    // for it like the BO3 opt-in does — otherwise a tap right after a cold
    // start or a reconnect silently skips the sheet on a capable server. On
    // connection failure we fall through with the flag false: same degraded
    // X01 path as before, and the invite itself will surface the error.
    try {
      await SocketService.ensureAuthenticated();
    } catch (_) {}
    if (!context.mounted) return;
    String gameMode = 'x01';
    if (SocketService.supportsCricket) {
      final choice = await showModalBottomSheet<String>(
        context: context,
        backgroundColor: AppTheme.surface,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (_) => _FriendlyModeSheet(friendUsername: friend.username),
      );
      if (choice == null || !context.mounted) return;
      gameMode = choice;
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
      gameMode: gameMode,
    );
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

/// "Which game?" sheet shown between the premium gate and the camera setup.
/// Pops 'x01' | 'cricket_score' | 'cricket_noscore'; X01 first and one tap,
/// so the historical flow stays two taps for the player in a hurry.
class _FriendlyModeSheet extends StatefulWidget {
  final String friendUsername;

  const _FriendlyModeSheet({required this.friendUsername});

  @override
  State<_FriendlyModeSheet> createState() => _FriendlyModeSheetState();
}

class _FriendlyModeSheetState extends State<_FriendlyModeSheet> {
  bool _noScore = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      child: Padding(
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
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            _optionCard(
              label: '501',
              hint: l10n.friendlyX01Hint,
              color: AppTheme.primary,
              onTap: () {
                HapticService.mediumImpact();
                Navigator.of(context).pop('x01');
              },
            ),
            const SizedBox(height: 12),
            _optionCard(
              label: l10n.cricketLabel,
              hint: l10n.cricketSetupHint,
              color: AppTheme.success,
              onTap: () {
                HapticService.mediumImpact();
                Navigator.of(context)
                    .pop(_noScore ? 'cricket_noscore' : 'cricket_score');
              },
              extra: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(
                  children: [
                    _variantChip(l10n.cricketScoreLabel, !_noScore,
                        () => setState(() => _noScore = false)),
                    const SizedBox(width: 6),
                    _variantChip(l10n.cricketNoScoreLabel, _noScore,
                        () => setState(() => _noScore = true)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _optionCard({
    required String label,
    required String hint,
    required Color color,
    required VoidCallback onTap,
    Widget? extra,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color, width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: color,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Icon(Icons.play_arrow_rounded, color: color),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                hint,
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 13,
                ),
              ),
              if (extra != null) extra,
            ],
          ),
        ),
      ),
    );
  }

  Widget _variantChip(String label, bool selected, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticService.lightImpact();
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? AppTheme.success.withValues(alpha: 0.25)
                : AppTheme.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? AppTheme.success
                  : AppTheme.surfaceLight.withValues(alpha: 0.8),
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? Colors.white : AppTheme.textSecondary,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
