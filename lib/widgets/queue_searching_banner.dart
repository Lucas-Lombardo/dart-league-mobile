import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../providers/matchmaking_provider.dart';
import '../utils/app_theme.dart';

/// Surface pill shown in training screens while the player is still queued
/// for a ranked match: a pulsing primary dot, "Recherche de match 0:42" and
/// a chevron. The near-opaque surface keeps it readable over the live camera
/// feed. When an opponent is found, [MatchmakingNavigationGate] pulls the
/// player into the match automatically. Renders nothing when not searching.
class QueueSearchingBanner extends StatefulWidget {
  const QueueSearchingBanner({super.key});

  @override
  State<QueueSearchingBanner> createState() => _QueueSearchingBannerState();
}

class _QueueSearchingBannerState extends State<QueueSearchingBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  String _formatTime(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final searching = context.select<MatchmakingProvider, bool>(
      (m) => m.isSearching,
    );
    if (!searching) return const SizedBox.shrink();
    final searchTime = context.select<MatchmakingProvider, int>(
      (m) => m.searchTime,
    );
    final l10n = AppLocalizations.of(context);

    return Container(
      height: 36,
      padding: const EdgeInsets.fromLTRB(12, 0, 6, 0),
      decoration: BoxDecoration(
        color: AppTheme.surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.primaryLight.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FadeTransition(
            opacity: Tween<double>(begin: 0.35, end: 1.0).animate(_pulse),
            child: Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: AppTheme.primary,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            l10n.findingMatch,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              height: 1,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            _formatTime(searchTime),
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              height: 1,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 2),
          const Icon(
            Icons.chevron_right_rounded,
            size: 18,
            color: AppTheme.textTertiary,
          ),
        ],
      ),
    );
  }
}
