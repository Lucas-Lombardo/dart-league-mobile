import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/subscription_provider.dart';
import '../../utils/app_theme.dart';
import '../../utils/haptic_service.dart';

/// The ways a player can start a match from the home "Jouer" button.
enum PlayMode { competitive, friend, local }

/// Presents the play-mode selector as a modal bottom sheet and resolves to the
/// chosen [PlayMode], or `null` if the user dismisses it.
Future<PlayMode?> showPlayModeSheet(BuildContext context) {
  return showModalBottomSheet<PlayMode>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => const _PlayModeSheet(),
  );
}

class _PlayModeSheet extends StatelessWidget {
  const _PlayModeSheet();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Friend matches are premium-gated — except during Free Play, when the
    // "PREMIUM" pill would be misleading, so it's hidden.
    final freePlayActive = context.watch<SubscriptionProvider>().freePlayActive;
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceLight,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(l10n.chooseGameMode, style: AppTheme.titleLarge),
              const SizedBox(height: 20),
              _ModeOption(
                icon: Icons.leaderboard_rounded,
                accent: AppTheme.primary,
                title: l10n.competitiveModeTitle,
                subtitle: l10n.competitiveModeSubtitle,
                onTap: () => Navigator.of(context).pop(PlayMode.competitive),
              ),
              const SizedBox(height: 12),
              _ModeOption(
                icon: Icons.people_alt_rounded,
                accent: AppTheme.secondary,
                title: l10n.friendModeTitle,
                subtitle: l10n.friendModeSubtitle,
                badge: freePlayActive ? null : l10n.premium,
                onTap: () => Navigator.of(context).pop(PlayMode.friend),
              ),
              const SizedBox(height: 12),
              _ModeOption(
                icon: Icons.smartphone_rounded,
                accent: AppTheme.success,
                title: l10n.localModeTitle,
                subtitle: l10n.localModeSubtitle,
                onTap: () => Navigator.of(context).pop(PlayMode.local),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModeOption extends StatelessWidget {
  final IconData icon;
  final Color accent;
  final String title;
  final String subtitle;
  final String? badge;
  final VoidCallback onTap;

  const _ModeOption({
    required this.icon,
    required this.accent,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.background,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          HapticService.lightImpact();
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: accent.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: accent, size: 26),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (badge != null) ...[
                          const SizedBox(width: 8),
                          _PremiumPill(label: badge!),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 13,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right_rounded,
                  color: AppTheme.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

class _PremiumPill extends StatelessWidget {
  final String label;
  const _PremiumPill({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.workspace_premium, color: AppTheme.accent, size: 12),
          const SizedBox(width: 4),
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: AppTheme.accent,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
