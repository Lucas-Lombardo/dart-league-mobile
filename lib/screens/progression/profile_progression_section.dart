import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/progression.dart';
import '../../utils/app_theme.dart';
import '../../widgets/design_system.dart';
import '../../widgets/progression/progression_widgets.dart';
import '../achievements/achievements_profile_tile.dart';
import 'locker_screen.dart';
import 'progression_format.dart';
import 'progression_screen.dart';

/// Profile block (mockup ecrans/Profil.dc.html): the pinned badges seen by
/// opponents, and — on my own profile — the level / items tiles leading to
/// the progression screen and the locker. Agent 3 adds the achievements tile.
class ProfileProgressionSection extends StatelessWidget {
  final PublicCosmetics? cosmetics;
  final ProgressionSummary? mine;

  const ProfileProgressionSection({super.key, this.cosmetics, this.mine});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final badges = cosmetics?.badges ?? const <PublicBadge>[];
    final me = mine;
    if (badges.isEmpty && me == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (badges.isNotEmpty) ...[
          const SizedBox(height: 14),
          DsCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.progressionShowcase, style: AppTheme.caption),
                const SizedBox(height: 10),
                Row(
                  children: [
                    for (final b in badges) ...[BadgeMedal(badge: b, size: 44), const SizedBox(width: 12)],
                  ],
                ),
              ],
            ),
          ),
        ],
        if (me != null) ...[
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: DsCard(
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProgressionScreen())),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.xpLevel(me.level), style: AppTheme.rowTitle.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      XpProgressBar(xpIntoLevel: me.xpIntoLevel, xpToNext: me.xpToNext, height: 4),
                      const SizedBox(height: 6),
                      Text(
                        l10n.xpProgressValue(formatXp(me.xpIntoLevel), formatXp(me.xpToNext)),
                        style: AppTheme.caption,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DsCard(
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LockerScreen())),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.progressionItems, style: AppTheme.rowTitle.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      Text('${me.itemsOwned} / ${me.itemsTotal}', style: AppTheme.titleLarge),
                      const SizedBox(height: 2),
                      Text(l10n.progressionCustomize, style: AppTheme.caption.copyWith(color: AppTheme.primaryLight)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          // Agent 3: "Achievements 18 / 60" → the collection.
          const SizedBox(height: 10),
          const AchievementsProfileTile(),
        ],
      ],
    );
  }
}
