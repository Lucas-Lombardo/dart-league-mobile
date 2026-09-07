import 'package:flutter/material.dart';

import '../utils/app_theme.dart';
import '../utils/rank_utils.dart';
import 'design_system.dart';
import 'premium_badge.dart';

/// Badge · name (+ premium crown) · subline · big number, a 3 px progress
/// hairline and a footer row (left text, right link).
class PlayerCard extends StatelessWidget {
  final String rank;
  final String username;
  final bool isPremium;
  final Widget subline;
  final String value;
  final String valueLabel;
  final double progress;
  final Widget? footerLeft;
  final Widget? footerRight;

  const PlayerCard({
    super.key,
    required this.rank,
    required this.username,
    required this.isPremium,
    required this.subline,
    required this.value,
    required this.valueLabel,
    required this.progress,
    this.footerLeft,
    this.footerRight,
  });

  @override
  Widget build(BuildContext context) {
    return DsCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              RankUtils.getRankBadge(rank, size: 72),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            username,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTheme.titleLarge.copyWith(height: 1.1),
                          ),
                        ),
                        PremiumBadge(isPremium: isPremium, size: 14, color: AppTheme.accent),
                      ],
                    ),
                    const SizedBox(height: 5),
                    subline,
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(value, style: AppTheme.displayLarge),
                  const SizedBox(height: 3),
                  Text(
                    valueLabel.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.3,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          DsProgressBar(value: progress),
          if (footerLeft != null || footerRight != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: footerLeft ?? const SizedBox.shrink()),
                ?footerRight,
              ],
            ),
          ],
        ],
      ),
    );
  }
}
