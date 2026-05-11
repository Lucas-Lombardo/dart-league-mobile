import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';

/// Small icon shown next to a username to indicate Premium membership.
/// Renders nothing for non-premium users so callers can place it
/// unconditionally.
class PremiumBadge extends StatelessWidget {
  final bool isPremium;
  final double size;
  final Color? color;

  const PremiumBadge({
    super.key,
    required this.isPremium,
    this.size = 16,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    if (!isPremium) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Icon(
        Icons.workspace_premium,
        size: size,
        color: color ?? const Color(0xFFFFC107),
        semanticLabel: AppLocalizations.of(context).premiumBadgeLabel,
      ),
    );
  }
}
