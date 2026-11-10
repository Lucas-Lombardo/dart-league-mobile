import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/progression.dart';
import '../../providers/progression_provider.dart';
import '../../utils/app_theme.dart';
import '../../widgets/progression/metal.dart';
import '../../widgets/progression/progression_widgets.dart';
import '../progression/locker_screen.dart';
import '../progression/progression_format.dart';
import 'achievement_format.dart';
import 'achievement_models.dart';
import 'achievement_replay.dart';
import 'achievements_screen.dart';
import 'achievements_service.dart';

/// "Achievement unlocked" (mockup ecrans/HFDeblocage.dc.html), a bottom sheet
/// shown once the match is over — never during it — or back on the home
/// screen for what was not shown yet. The first launch after the update
/// groups the retroactive unlocks in one sheet.
class AchievementUnlockSheet extends StatelessWidget {
  /// Highest tier per achievement, most valuable first.
  final List<AchievementUnlock> unlocks;
  const AchievementUnlockSheet({super.key, required this.unlocks});

  static bool _showing = false;

  /// Unlocks shown during this session: the "seen" call may not have landed
  /// when the home screen asks again (the sheet's own pop triggers it).
  static final Set<String> _announced = {};

  /// End of a match: the tiers unlocked since it started. Achievements are
  /// counted just after the series is saved, so this asks twice.
  static Future<void> showForMatch(BuildContext context, DateTime since) async {
    for (final wait in const [Duration(milliseconds: 2500), Duration(seconds: 3)]) {
      await Future<void>.delayed(wait);
      if (!context.mounted) return;
      List<AchievementUnlock> found;
      try {
        found = await AchievementsService.unlockedSince(since);
      } catch (_) {
        return;
      }
      if (!context.mounted) return;
      final fresh = found.where((u) => !u.retro && !_announced.contains(u.id)).toList();
      if (fresh.isNotEmpty) {
        if (ModalRoute.of(context)?.isCurrent ?? true) await _show(context, fresh);
        return;
      }
    }
  }

  /// Home screen: whatever was never shown (the retroactive ones included).
  static Future<void> showIfPending(BuildContext context) async {
    if (_showing) return;
    List<AchievementUnlock> pending;
    try {
      pending = await AchievementsService.unseen();
    } catch (_) {
      return;
    }
    pending = pending.where((u) => !_announced.contains(u.id)).toList();
    if (pending.isEmpty || !context.mounted) return;
    await _show(context, pending);
  }

  static Future<void> _show(BuildContext context, List<AchievementUnlock> unlocks) async {
    if (_showing || unlocks.isEmpty) return;
    _showing = true;
    try {
      // Seen as soon as it is shown: a route popping back to the home screen
      // must not announce it again.
      _announced.addAll(unlocks.map((u) => u.id));
      unawaited(AchievementsService.markSeen(unlocks.map((u) => u.id).toList()));
      final sorted = [...unlocks]..sort((a, b) {
          final byTier = achievementTierRank(b.tier).compareTo(achievementTierRank(a.tier));
          return byTier != 0 ? byTier : b.xp.compareTo(a.xp);
        });
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: AppTheme.surface,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
        builder: (_) => AchievementUnlockSheet(unlocks: sorted),
      );
    } finally {
      _showing = false;
    }
  }

  bool get _isRetroBatch => unlocks.length > 2 && unlocks.every((u) => u.retro);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: const Color(0xFF475569), borderRadius: BorderRadius.circular(999)),
              ),
            ),
            const SizedBox(height: 24),
            if (_isRetroBatch) _RetroBody(unlocks: unlocks) else _SingleBody(unlocks: unlocks),
          ],
        ),
      ),
    );
  }
}

class _SingleBody extends StatelessWidget {
  final List<AchievementUnlock> unlocks;
  const _SingleBody({required this.unlocks});

  Future<void> _pin(BuildContext context, AchievementUnlock u) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final nav = Navigator.of(context);
    ProgressionProvider? p;
    try {
      p = context.read<ProgressionProvider>();
    } on ProviderNotFoundException {
      p = null;
    }
    final badgeId = u.userBadgeId;
    if (p == null || badgeId == null) {
      messenger?.showSnackBar(SnackBar(content: Text(l10n.achievementPinFailed)));
      return;
    }
    if (p.summary == null) await p.refreshSummary();
    final pinned = p.summary?.equipment.badges ?? const <String>[];
    if (pinned.contains(badgeId)) {
      messenger?.showSnackBar(SnackBar(content: Text(l10n.achievementAlreadyPinned)));
      return;
    }
    if (pinned.length >= 3) {
      // Full showcase: the locker's Badges tab picks the one to replace.
      nav.pop();
      await nav.push(MaterialPageRoute(builder: (_) => const LockerScreen(initialTab: ItemType.badge)));
      return;
    }
    final ok = await p.equip(EquipRequest(badges: [...pinned, badgeId]));
    messenger?.showSnackBar(SnackBar(content: Text(ok ? l10n.achievementPinned : l10n.achievementPinFailed)));
    if (ok && nav.canPop()) nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final content = readProgressionContent(context);
    final u = unlocks.first;
    final others = unlocks.length - 1;
    final metal = MetalPalette.of(content, MetalPalette.forTier(u.tier == 'unique' ? null : u.tier));
    final target = u.label?.resolve(context) ?? formatAchievementValue(context, u.threshold, u.format);
    final reward = _reward(context, u);
    final canReplay = AchievementReplay.hasLocal(u.matchId);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(child: BadgeMedal(badge: u.badge, size: 96)),
        const SizedBox(height: 18),
        Text(
          l10n.achievementUnlockedTitle,
          textAlign: TextAlign.center,
          style: AppTheme.rowTitle.copyWith(color: const Color(0xFF7DD3FC), fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          u.name.resolve(context),
          textAlign: TextAlign.center,
          style: AppTheme.displayMedium.copyWith(fontSize: 28),
        ),
        if (u.tier != 'unique') ...[
          const SizedBox(height: 4),
          Text(
            l10n.achievementTierLine(achievementTierName(l10n, u.tier), target),
            textAlign: TextAlign.center,
            style: AppTheme.rowTitle.copyWith(fontWeight: FontWeight.w700, color: metal.first),
          ),
        ],
        if (u.rarity != null) ...[
          const SizedBox(height: 4),
          Text(
            l10n.achievementPlayersHaveIt(formatRarity(context, u.rarity!)),
            textAlign: TextAlign.center,
            style: AppTheme.caption.copyWith(fontSize: 13),
          ),
        ],
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(child: _InfoCard(title: '+${formatXp(u.xp)} XP', subtitle: l10n.achievementXpAdded, accent: true)),
            if (reward != null) ...[
              const SizedBox(width: 8),
              Expanded(child: _InfoCard(title: reward.$1, subtitle: reward.$2)),
            ],
          ],
        ),
        const SizedBox(height: 20),
        ElevatedButton(
          style: AppTheme.primaryButtonStyle,
          onPressed: u.userBadgeId == null ? null : () => _pin(context, u),
          child: Text(l10n.achievementPin),
        ),
        if (canReplay) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            style: AppTheme.secondaryButtonStyle,
            icon: const Icon(Icons.play_arrow_rounded, size: 18),
            label: Text(l10n.achievementReplay),
            onPressed: () => AchievementReplay.open(context, matchId: u.matchId!, value: u.contextValue),
          ),
        ],
        if (others > 0) ...[
          const SizedBox(height: 6),
          TextButton(
            onPressed: () {
              final nav = Navigator.of(context);
              nav.pop();
              nav.push(AchievementsScreen.route());
            },
            child: Text('${l10n.achievementMore(others)} · ${l10n.achievementSeeAll}'),
          ),
        ],
      ],
    );
  }

  /// The item of this tier, else the one of the next tier.
  (String, String)? _reward(BuildContext context, AchievementUnlock u) {
    final l10n = AppLocalizations.of(context);
    final content = readProgressionContent(context);
    String? name(List<String> ids) {
      for (final id in ids) {
        final item = content?.item(id);
        if (item != null) return item.type == ItemType.title ? '« ${item.name.resolve(context)} »' : itemKindAndName(context, item);
      }
      return null;
    }

    final now = name(u.itemIds);
    if (now != null) return (now, l10n.achievementRewardNow);
    final next = u.next;
    final later = name(u.nextItemIds);
    if (next != null && later != null) {
      final target = next.label?.resolve(context) ?? formatAchievementValue(context, next.threshold, u.format);
      return (later, l10n.achievementRewardAt(achievementTierName(l10n, next.tier), target));
    }
    return null;
  }
}

class _RetroBody extends StatelessWidget {
  final List<AchievementUnlock> unlocks;
  const _RetroBody({required this.unlocks});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final xp = unlocks.fold<int>(0, (s, u) => s + u.xp);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 10,
          runSpacing: 10,
          children: [for (final u in unlocks.take(8)) BadgeMedal(badge: u.badge, size: 48)],
        ),
        const SizedBox(height: 18),
        Text(l10n.achievementRetroTitle, textAlign: TextAlign.center, style: AppTheme.displayMedium.copyWith(fontSize: 26)),
        const SizedBox(height: 6),
        Text(
          l10n.achievementRetroBody(unlocks.length),
          textAlign: TextAlign.center,
          style: AppTheme.caption.copyWith(fontSize: 14),
        ),
        const SizedBox(height: 16),
        _InfoCard(title: '+${formatXp(xp)} XP', subtitle: l10n.achievementXpAdded, accent: true),
        const SizedBox(height: 20),
        ElevatedButton(
          style: AppTheme.primaryButtonStyle,
          onPressed: () {
            final nav = Navigator.of(context);
            nav.pop();
            nav.push(AchievementsScreen.route());
          },
          child: Text(l10n.achievementSeeAll),
        ),
        const SizedBox(height: 6),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.achievementLater)),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool accent;
  const _InfoCard({required this.title, required this.subtitle, this.accent = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: AppTheme.background, borderRadius: BorderRadius.circular(AppTheme.radiusRow)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: accent
                ? AppTheme.titleLarge.copyWith(fontSize: 20, color: const Color(0xFF7DD3FC))
                : AppTheme.rowTitle.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 2),
          Text(subtitle, style: AppTheme.caption.copyWith(fontSize: 12)),
        ],
      ),
    );
  }
}

/// Invisible: once the match is over, announces the tiers it unlocked.
class AchievementUnlockWatcher extends StatefulWidget {
  final DateTime since;
  const AchievementUnlockWatcher({super.key, required this.since});

  @override
  State<AchievementUnlockWatcher> createState() => _AchievementUnlockWatcherState();
}

class _AchievementUnlockWatcherState extends State<AchievementUnlockWatcher> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) AchievementUnlockSheet.showForMatch(context, widget.since);
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
