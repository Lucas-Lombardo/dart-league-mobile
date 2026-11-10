import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../utils/app_theme.dart';

/// Shared pieces of the ghost screens (mockups FantomeFile, FantomeMatch,
/// FantomeNuit), system D: Manrope, one blue accent, rose for the opponent.

/// The ghost glyph of the mockups (Lucide "ghost"), drawn as SVG.
class GhostIcon extends StatelessWidget {
  final double size;
  final Color color;
  final double strokeWidth;
  const GhostIcon({super.key, this.size = 22, this.color = AppTheme.playerBlueBright, this.strokeWidth = 2});

  @override
  Widget build(BuildContext context) {
    final svg = '<svg viewBox="0 0 24 24" fill="none" stroke="#FFFFFF" stroke-width="$strokeWidth" '
        'stroke-linecap="round" stroke-linejoin="round"><path d="M9 10h.01"/><path d="M15 10h.01"/>'
        '<path d="M12 2a8 8 0 0 0-8 8v12l3-3 2.5 2.5L12 19l2.5 2.5L17 19l3 3V10a8 8 0 0 0-8-8z"/></svg>';
    return SvgPicture.string(
      svg,
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );
  }
}

/// "28 oct." / "Oct 28" for the replayed match date.
String ghostShortDate(BuildContext context, DateTime? date) {
  if (date == null) return '—';
  final locale = Localizations.localeOf(context).toLanguageTag();
  try {
    return DateFormat.MMMd(locale).format(date);
  } catch (_) {
    return DateFormat.MMMd().format(date);
  }
}

/// "55,2" / "55.2".
String ghostAverage(BuildContext context, double value) {
  final locale = Localizations.localeOf(context).toLanguageTag();
  try {
    return NumberFormat('0.0', locale).format(value);
  } catch (_) {
    return value.toStringAsFixed(1);
  }
}

/// "+13" / "−12".
String ghostSignedElo(int delta) => delta >= 0 ? '+$delta' : '−${delta.abs()}';

/// The "REC" strip of the ghost match (FantomeMatch): the player's camera is
/// filming, and what the result counts for.
class GhostRecBanner extends StatelessWidget {
  final bool eloEligible;
  const GhostRecBanner({super.key, required this.eloEligible});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(AppTheme.radiusRow)),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(color: AppTheme.opponentPink, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            'REC',
            style: AppTheme.labelSmall.copyWith(color: AppTheme.opponentPinkBright, letterSpacing: 1),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              eloEligible ? l10n.ghostRecBanner : l10n.ghostRecBannerNoElo,
              style: AppTheme.caption.copyWith(color: const Color(0xFFCBD5E1), fontSize: 13, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

/// A friendly sentence for a failed ghost call, from the server's code.
String ghostErrorMessage(AppLocalizations l10n, Object error) {
  final s = error.toString();
  if (s.contains('GHOST_PREMIUM_REQUIRED')) return l10n.ghostPremiumRequired;
  if (s.contains('DAILY_MATCH_LIMIT_REACHED')) return l10n.ghostDailyLimit;
  if (s.contains('PLACEMENT_REQUIRED')) return l10n.ghostPlacementRequired;
  if (s.contains('OFFER_EXPIRED') ||
      s.contains('OFFER_NOT_FOUND') ||
      s.contains('GHOST_ALREADY_FACED') ||
      s.contains('GHOST_QUEUE_ONLY')) {
    return l10n.ghostOfferExpired;
  }
  return l10n.ghostStartError;
}
