import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../utils/app_navigator.dart';
import '../../utils/app_theme.dart';
import '../../widgets/design_system.dart';
import 'local_match_setup_screen.dart';
import 'referee_match_setup_screen.dart';

/// Choose the scoring method before entering either local-match setup flow.
class LocalMatchEntryScreen extends StatelessWidget {
  const LocalMatchEntryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(dsSentence(l10n.localModeTitle))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          children: [
            Text(l10n.localSameBoard, style: AppTheme.labelSmall),
            const SizedBox(height: 12),
            Text(l10n.localScoringChoice, style: AppTheme.displayMedium),
            const SizedBox(height: 12),
            Text(l10n.localScoringChoiceHint, style: AppTheme.bodyMedium),
            const SizedBox(height: 28),
            _ModeCard(
              key: const ValueKey('local-automatic'),
              icon: Icons.camera_alt_outlined,
              title: l10n.localAutomaticScoring,
              description: l10n.localAutomaticDescription,
              features: l10n.localAutomaticFeatures,
              onTap: () => AppNavigator.toScreen<void>(
                context,
                const LocalMatchSetupScreen(),
              ),
            ),
            const SizedBox(height: 14),
            _ModeCard(
              key: const ValueKey('local-referee'),
              icon: Icons.calculate_outlined,
              title: l10n.refereeMode,
              description: l10n.refereeDescription,
              features: l10n.refereeFeatures,
              highlighted: true,
              onTap: () => AppNavigator.toScreen<void>(
                context,
                const RefereeMatchSetupScreen(),
              ),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                const Icon(
                  Icons.adjust,
                  size: 22,
                  color: AppTheme.textTertiary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l10n.localSharedPhone,
                    style: AppTheme.caption.copyWith(height: 1.6),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final String features;
  final bool highlighted;
  final VoidCallback onTap;

  const _ModeCard({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.features,
    required this.onTap,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final accent = highlighted ? AppTheme.primaryLight : AppTheme.textPrimary;
    return Material(
      color: highlighted ? const Color(0xFF11283D) : AppTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        side: BorderSide(
          color: highlighted
              ? AppTheme.primaryLight.withValues(alpha: .45)
              : AppTheme.border,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: accent, size: 28),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: AppTheme.titleLarge.copyWith(color: accent),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.arrow_forward_rounded, size: 21, color: accent),
                ],
              ),
              const SizedBox(height: 8),
              Text(description, style: AppTheme.bodyMedium),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 13),
                child: Divider(),
              ),
              Text(features, style: AppTheme.caption),
            ],
          ),
        ),
      ),
    );
  }
}
