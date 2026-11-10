import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../utils/app_theme.dart';
import '../training/logic/checkout_routes.dart';

/// The suggested finish for [remaining] with the [dartsLeft] darts of the
/// visit, as display labels ('T20', 'D16', 'Bull'), or null when there is no
/// finish this visit (over 170, a bogey number, or not enough darts left).
///
/// The "double wall" of the 2026-08-12 audit: 41 first-match abandons at 50
/// points or less, after ~15 visits, 27 of them on a 0 visit. New players do
/// not know which double their score leaves — the book route says it.
List<String>? suggestedCheckout(int remaining, int dartsLeft) {
  if (dartsLeft <= 0 || remaining < 2 || remaining > 170) return null;
  if (minDartsToCheckout(remaining) == 0 ||
      minDartsToCheckout(remaining) > dartsLeft) {
    return null;
  }
  final routes = recommendedCheckoutRoutes(remaining, dartsLeft);
  if (routes.isEmpty) return null;
  return routes.first.map((d) => _label(d.notation)).toList();
}

String _label(String notation) {
  switch (notation) {
    case 'DB':
      return 'Bull';
    case 'B':
      return '25';
  }
  return notation;
}

/// A thin bar docked to the bottom of the player's camera panel (the slot the
/// replay capture bar uses online): "Finish  T20 · T20 · D20". Nothing when
/// there is no finish this visit.
class CheckoutHintBar extends StatelessWidget {
  final int remaining;
  final int dartsLeft;

  const CheckoutHintBar({
    super.key,
    required this.remaining,
    required this.dartsLeft,
  });

  /// The bar, or null when there is nothing to suggest (so the camera panel
  /// keeps its zoom pill where it was).
  static Widget? maybe({required int remaining, required int dartsLeft}) {
    if (suggestedCheckout(remaining, dartsLeft) == null) return null;
    return CheckoutHintBar(remaining: remaining, dartsLeft: dartsLeft);
  }

  @override
  Widget build(BuildContext context) {
    final route = suggestedCheckout(remaining, dartsLeft);
    if (route == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        color: AppTheme.gameBackground.withValues(alpha: 0.86),
        child: Row(
          children: [
            Text(
              l10n.onboardingCheckoutHintLabel,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                route.join('  ·  '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppTheme.playerBlueBright,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
