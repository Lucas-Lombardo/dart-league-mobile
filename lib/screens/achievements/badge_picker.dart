import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/progression.dart';
import '../../providers/progression_provider.dart';
import '../../utils/app_theme.dart';
import '../../widgets/progression/progression_widgets.dart';
import 'achievement_format.dart';
import 'achievements_screen.dart' show achievementTierColor;

/// The locker's Badges tab: every badge I own, tap to pin it to my showcase
/// (3 at most, seen by opponents) or to unpin it. PUT /progression/equipment.
class BadgePicker extends StatelessWidget {
  const BadgePicker({super.key});

  Future<void> _toggle(BuildContext context, List<String> pinned, String userBadgeId) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final next = pinned.contains(userBadgeId)
        ? (List<String>.of(pinned)..remove(userBadgeId))
        : [...pinned, userBadgeId];
    if (next.length > 3) {
      messenger?.showSnackBar(SnackBar(content: Text(l10n.achievementBadgesFull)));
      return;
    }
    final ok = await context.read<ProgressionProvider>().equip(EquipRequest(badges: next));
    if (!ok) messenger?.showSnackBar(SnackBar(content: Text(l10n.achievementPinFailed)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final p = context.watch<ProgressionProvider>();
    final badges = p.inventory?.badges ?? const <OwnedBadge>[];
    final pinned = (p.inventory?.equipment ?? p.summary?.equipment ?? const Equipment()).badges;
    // Known badges only (an unknown one is hidden); pinned first, in order.
    final known = badges.where((b) => p.item(b.badgeId) != null).toList()
      ..sort((a, b) {
        final pa = pinned.indexOf(a.id), pb = pinned.indexOf(b.id);
        if (pa >= 0 || pb >= 0) return (pa < 0 ? 99 : pa).compareTo(pb < 0 ? 99 : pb);
        return (p.item(a.badgeId)?.sortOrder ?? 0).compareTo(p.item(b.badgeId)?.sortOrder ?? 0);
      });

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          sliver: SliverToBoxAdapter(
            child: Row(
              children: [
                Expanded(child: Text(l10n.achievementBadgesHint, style: AppTheme.caption)),
                const SizedBox(width: 8),
                Text(
                  l10n.achievementBadgesPinned(pinned.length),
                  style: AppTheme.caption.copyWith(fontWeight: FontWeight.w700, color: AppTheme.primaryLight),
                ),
              ],
            ),
          ),
        ),
        if (known.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(l10n.achievementBadgesEmpty, textAlign: TextAlign.center, style: AppTheme.caption),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 0.78,
              ),
              delegate: SliverChildBuilderDelegate((context, i) {
                final b = known[i];
                final slot = pinned.indexOf(b.id);
                final item = p.item(b.badgeId)!;
                final dated = b.date != null ? BadgeMedal.dateLabel(b.date, Localizations.localeOf(context)) : null;
                return Material(
                  key: ValueKey('badge-pick-${b.id}'),
                  color: AppTheme.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusRow),
                    side: BorderSide(
                      color: slot >= 0 ? AppTheme.primaryLight : AppTheme.border,
                      width: slot >= 0 ? 1.5 : 1,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: p.isBusy ? null : () => _toggle(context, pinned, b.id),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(6, 10, 6, 8),
                      child: Column(
                        children: [
                          Expanded(
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                BadgeMedal(badge: b.asPublic, size: 52),
                                if (slot >= 0)
                                  Positioned(
                                    top: 0,
                                    right: 4,
                                    child: Container(
                                      width: 18,
                                      height: 18,
                                      alignment: Alignment.center,
                                      decoration: const BoxDecoration(color: AppTheme.primaryLight, shape: BoxShape.circle),
                                      child: Text(
                                        '${slot + 1}',
                                        style: AppTheme.caption.copyWith(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                          color: AppTheme.background,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            item.name.resolve(context),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: AppTheme.caption.copyWith(fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                          ),
                          Text(
                            dated ?? achievementTierName(l10n, b.tier ?? 'unique'),
                            maxLines: 1,
                            textAlign: TextAlign.center,
                            style: AppTheme.caption.copyWith(fontSize: 11, color: achievementTierColor(context, b.tier ?? 'unique')),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }, childCount: known.length),
            ),
          ),
      ],
    );
  }
}
