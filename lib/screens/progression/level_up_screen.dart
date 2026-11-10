import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/progression.dart';
import '../../providers/progression_provider.dart';
import '../../utils/app_theme.dart';
import '../../widgets/design_system.dart';
import '../../widgets/progression/progression_widgets.dart';
import 'progression_format.dart';

/// "Level up" (mockup ecrans/NiveauGagne.dc.html): the new level, what it
/// unlocks, the next reward, "Equip now" / "Later". Shown outside matches only.
/// Past 50 (tour 5), levels 60, 70… announce their prestige star.
class LevelUpScreen extends StatelessWidget {
  final int level;
  final List<String> itemIds;

  const LevelUpScreen({super.key, required this.level, this.itemIds = const []});

  static Route<void> route({required int level, List<String> itemIds = const []}) => PageRouteBuilder<void>(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (_, _, _) => LevelUpScreen(level: level, itemIds: itemIds),
        transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
      );

  /// Shows the screen for the latest unseen level, once.
  static Future<void> showIfPending(BuildContext context) async {
    final p = context.read<ProgressionProvider>();
    final s = p.summary;
    if (s == null || s.level <= s.levelSeen) return;
    final reward = p.content?.levels[s.level];
    await Navigator.of(context).push(
      route(level: s.level, itemIds: [...?reward?.itemIds, if (s.isPremium) ...?reward?.premiumItemIds]),
    );
  }

  Future<void> _close(BuildContext context, {bool equip = false}) async {
    final p = context.read<ProgressionProvider>();
    final nav = Navigator.of(context);
    unawaited(p.markLevelSeen(level));
    if (equip) {
      final prestigeFrame = _prestigeFrameToEquip(p);
      final item = [...itemIds, ?prestigeFrame].map(p.item).whereType<ItemDef>().firstWhere(
            (i) => i.type != ItemType.badge,
            orElse: () => const ItemDef(
              id: '',
              type: ItemType.unknown,
              name: LocalizedText.empty,
              source: ItemSourceInfo(kind: '', label: LocalizedText.empty),
            ),
          );
      if (item.type != ItemType.unknown) await p.equip(EquipRequest.slot(item.type, item.id));
    }
    if (nav.mounted) nav.pop();
  }

  /// The star earned at this level (1 at 60, 2 at 70…), 0 otherwise.
  int _prestigeStar(ProgressionProvider p) {
    final prestige = p.content?.prestige;
    if (prestige == null || !prestige.isStarLevel(level)) return 0;
    return prestige.starsFor(level);
  }

  /// A star level for a player who owns the Légende frame but wears another:
  /// "Equip now" puts it on (the star only shows there).
  String? _prestigeFrameToEquip(ProgressionProvider p) {
    if (_prestigeStar(p) == 0) return null;
    final frameId = p.content?.prestige?.frameId;
    if (frameId == null || p.summary?.cosmetics.frame == frameId) return null;
    final owned = p.inventory?.items.any((i) => i.itemId == frameId);
    return owned == false ? null : frameId;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final p = context.watch<ProgressionProvider>();
    final summary = p.summary ?? ProgressionSummary(level: level, levelSeen: level);
    final items = itemIds.map(p.item).whereType<ItemDef>().toList();
    final next = p.content?.levels[level + 1];
    final nextItem = p.item(next?.itemIds.isEmpty ?? true ? null : next!.itemIds.first);
    final cosmetics = summary.cosmetics;
    final prestige = p.content?.prestige;
    final star = _prestigeStar(p);
    final prestigeMetal = p.item(prestige?.frameId)?.metal ?? 'legende';
    final wearsPrestigeFrame = prestige != null && cosmetics.frame == prestige.frameId;
    final nextStarLevel = prestige != null && level >= prestige.fromLevel ? prestige.nextStarLevel(level) : null;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close(context);
      },
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 36, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l10n.levelUpTitle, textAlign: TextAlign.center, style: AppTheme.sectionTitle),
                const SizedBox(height: 6),
                Text(
                  '$level',
                  textAlign: TextAlign.center,
                  style: AppTheme.displayLarge.copyWith(fontSize: 72, height: 1),
                ),
                const SizedBox(height: 14),
                XpProgressBar(xpIntoLevel: summary.xpIntoLevel, xpToNext: summary.xpToNext),
                const SizedBox(height: 8),
                Text(
                  l10n.levelUpProgress(formatXp(summary.xpIntoLevel), formatXp(summary.xpToNext), level + 1),
                  textAlign: TextAlign.center,
                  style: AppTheme.caption,
                ),
                const SizedBox(height: 28),
                if (star > 0) ...[
                  Text(l10n.levelUpUnlocks, style: AppTheme.sectionTitle),
                  const SizedBox(height: 10),
                  DsCard(
                    child: Row(
                      children: [
                        SizedBox(
                          width: 52,
                          height: 52,
                          child: Center(child: PrestigeStars(count: star, metal: prestigeMetal, size: 15, maxDrawn: 3)),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(l10n.prestigeStarName(star), style: AppTheme.rowTitle),
                              Text(
                                wearsPrestigeFrame ? l10n.levelUpPrestigeHint : l10n.levelUpPrestigeWear,
                                style: AppTheme.caption,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (items.isNotEmpty) const SizedBox(height: 14),
                ],
                if (items.isNotEmpty) ...[
                  if (star == 0) ...[
                    Text(l10n.levelUpUnlocks, style: AppTheme.sectionTitle),
                    const SizedBox(height: 10),
                  ],
                  DsCard(
                    child: Column(
                      children: [
                        for (final item in items)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: [
                                ProgressionItemVisual(item: item, monogramText: cosmetics.monogram, size: 52),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(item.name.resolve(context), style: AppTheme.rowTitle),
                                      Text(itemKindLabel(l10n, item.type), style: AppTheme.caption),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 6),
                        Text(l10n.levelUpVisible, style: AppTheme.caption, textAlign: TextAlign.center),
                      ],
                    ),
                  ),
                ],
                const Spacer(),
                if (nextItem != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Text(
                      l10n.progressionNextReward(level + 1, itemKindAndName(context, nextItem)),
                      textAlign: TextAlign.center,
                      style: AppTheme.caption.copyWith(color: const Color(0xFFCBD5E1)),
                    ),
                  )
                else if (nextStarLevel != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Text(
                      l10n.progressionNextStar(nextStarLevel),
                      textAlign: TextAlign.center,
                      style: AppTheme.caption.copyWith(color: const Color(0xFFCBD5E1)),
                    ),
                  ),
                if (items.any((i) => i.type != ItemType.badge) || _prestigeFrameToEquip(p) != null)
                  ElevatedButton(
                    onPressed: p.isBusy ? null : () => _close(context, equip: true),
                    child: Text(l10n.levelUpEquipNow),
                  ),
                TextButton(onPressed: () => _close(context), child: Text(l10n.levelUpLater)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

