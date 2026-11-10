import 'package:flutter/material.dart';

import '../models/progression.dart';
import '../utils/app_theme.dart';
import 'design_system.dart';
import 'premium_badge.dart';
import 'progression/progression_widgets.dart';

/// Badge · name (+ premium crown) · subline · big number, a 3 px progress
/// hairline and a footer row (left text, right link).
///
/// With [cosmetics] (progression) the card wears the player's frame and
/// background, shows their avatar instead of the rank badge, a "Lv. n" chip
/// and their title in front of the subline. Without, it looks as before.
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
  final PublicCosmetics? cosmetics;
  final VoidCallback? onAvatarTap;

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
    this.cosmetics,
    this.onAvatarTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = cosmetics;
    final titleName = TitleText.nameOf(context, c?.title);
    final card = DsCard(
      padding: const EdgeInsets.all(18),
      color: c?.background != null ? Colors.transparent : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: onAvatarTap,
                child: PlayerAvatar(rank: rank, cosmetics: c, size: 72),
              ),
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
                        if (c != null) ...[
                          const SizedBox(width: 6),
                          LevelChip(level: c.level),
                        ],
                      ],
                    ),
                    const SizedBox(height: 5),
                    if (titleName == null)
                      subline
                    else
                      Row(
                        children: [
                          Flexible(
                            flex: 0,
                            child: Text(
                              '$titleName · ',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTheme.caption.copyWith(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFFE2E8F0),
                              ),
                            ),
                          ),
                          Flexible(child: subline),
                        ],
                      ),
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
    if (c == null || (c.frame == null && c.background == null)) return card;
    return CardFrame(
      frameId: c.frame,
      level: c.level,
      width: 2,
      child: CardBackground(backgroundId: c.background, child: card),
    );
  }
}
