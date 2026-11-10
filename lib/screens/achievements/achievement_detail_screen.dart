import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/progression.dart';
import '../../utils/app_theme.dart';
import '../../widgets/design_system.dart';
import '../../widgets/progression/metal.dart';
import '../../widgets/progression/progression_widgets.dart';
import '../progression/progression_format.dart';
import 'achievement_format.dart';
import 'achievement_models.dart';
import 'achievement_replay.dart';
import 'achievements_screen.dart' show achievementTierColor;
import 'achievements_service.dart';

/// One achievement (mockup ecrans/HFPaliers.dc.html): the medal and the
/// value, each tier with its date or its progress and its rarity, then the
/// last times it moved, with the replay when there is one.
class AchievementDetailScreen extends StatefulWidget {
  /// What the collection already knows: shown at once, refreshed by the detail.
  final Achievement achievement;

  /// Test seam: the network call.
  final Future<AchievementDetail?> Function(String id)? load;

  const AchievementDetailScreen({super.key, required this.achievement, this.load});

  static Route<void> route(Achievement a) => MaterialPageRoute(builder: (_) => AchievementDetailScreen(achievement: a));

  @override
  State<AchievementDetailScreen> createState() => _AchievementDetailScreenState();
}

class _AchievementDetailScreenState extends State<AchievementDetailScreen> {
  late Achievement _a = widget.achievement;
  List<AchievementOccurrence> _recent = const [];

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      final d = await (widget.load ?? AchievementsService.detail)(widget.achievement.id);
      if (!mounted || d == null) return;
      setState(() {
        _a = d.achievement;
        _recent = d.recent;
      });
    } catch (e) {
      debugPrint('AchievementDetailScreen: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final a = _a;
    final current = a.next?.tier;
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            DsScreenHeader(title: a.name.resolve(context), showBack: true),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                children: [
                  Row(
                    children: [
                      BadgeMedal(badge: a.badge, size: 72, locked: !a.unlocked),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              a.format == 'ordinal'
                                  ? achievementProgress(context, a)
                                  : formatAchievementValue(context, a.value, a.format),
                              style: AppTheme.displayMedium.copyWith(fontSize: 34, height: 1),
                            ),
                            const SizedBox(height: 4),
                            Text(a.description.resolve(context), style: AppTheme.caption.copyWith(fontSize: 14)),
                            if (a.aggregate == 'streak' && a.best != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                l10n.achievementRecord(formatAchievementValue(context, a.best!, a.format)),
                                style: AppTheme.caption,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (a.aiOnly) ...[
                    const SizedBox(height: 12),
                    Text(l10n.achievementAiOnly, style: AppTheme.caption),
                  ],
                  if (a.accountAgeDays != null && !a.unlocked) ...[
                    const SizedBox(height: 6),
                    Text(l10n.achievementRequiresAge, style: AppTheme.caption),
                  ],
                  if (a.pendingReview) ...[
                    const SizedBox(height: 6),
                    Text(l10n.achievementPendingReviewHint, style: AppTheme.caption),
                  ],
                  const SizedBox(height: 18),
                  for (final step in a.steps) ...[
                    _StepRow(achievement: a, step: step, current: step.tier == current),
                    const SizedBox(height: 8),
                  ],
                  if (_recent.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(l10n.achievementRecent, style: AppTheme.sectionTitle),
                    const SizedBox(height: 8),
                    for (final r in _recent) ...[
                      _RecentRow(occurrence: r),
                      const SizedBox(height: 8),
                    ],
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  final Achievement achievement;
  final AchievementStep step;
  final bool current;
  const _StepRow({required this.achievement, required this.step, required this.current});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final content = readProgressionContent(context);
    final a = achievement;
    final done = step.done;
    final metal = MetalPalette.of(content, MetalPalette.forTier(step.tier == 'unique' ? null : step.tier));
    final rewards = step.itemIds.map((id) => content?.item(id)).whereType<ItemDef>().map((i) => itemKindAndName(context, i));
    final target = achievementStepTarget(context, step, a.format);
    final parts = <String>[
      a.unique ? target : (a.format == 'ordinal' ? target : l10n.achievementTarget(target)),
      if (done && step.unlockedAt != null) l10n.achievementUnlockedOn(formatAchievementDate(context, step.unlockedAt!)),
      if (!done && step.pending) l10n.achievementPendingReview,
      if (!done) ...rewards,
    ];
    final name = a.unique ? a.name.resolve(context) : achievementTierName(l10n, step.tier);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusRow),
        border: current ? Border.all(color: AppTheme.primaryLight, width: 1.5) : null,
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: done ? metal.first.withValues(alpha: 0.16) : AppTheme.background,
              border: Border.all(color: done ? metal.last : AppTheme.surfaceLight, width: 1.5),
            ),
            child: Icon(
              done ? Icons.check_rounded : Icons.military_tech_outlined,
              size: 16,
              color: done ? metal.first : AppTheme.textSecondary,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: AppTheme.rowTitle.copyWith(
                          fontWeight: FontWeight.w800,
                          color: done ? achievementTierColor(context, step.tier) : AppTheme.textPrimary,
                        ),
                      ),
                    ),
                    if (step.rarity != null)
                      Text(
                        l10n.achievementRarity(formatRarity(context, step.rarity!)),
                        style: AppTheme.caption.copyWith(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(parts.join(' · '), style: AppTheme.caption.copyWith(fontSize: 13, color: const Color(0xFFCBD5E1))),
                if (current && a.next != null) ...[
                  const SizedBox(height: 8),
                  DsProgressBar(value: a.next!.ratio, color: AppTheme.primaryLight, height: 6),
                  const SizedBox(height: 4),
                  Text(achievementProgress(context, a), style: AppTheme.caption.copyWith(fontSize: 12)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentRow extends StatelessWidget {
  final AchievementOccurrence occurrence;
  const _RecentRow({required this.occurrence});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final r = occurrence;
    final title = [
      if (r.opponentName != null) l10n.achievementRecentVs(r.opponentName!),
      if (r.legNumber != null) l10n.achievementRecentLeg(r.legNumber!),
      if (r.opponentName == null && r.value != null) formatXp(r.value!.round()),
    ].join(' · ');
    final canReplay = r.matchId != null && (r.hasCloudReplay || AchievementReplay.hasLocal(r.matchId));
    return Container(
      height: 56,
      padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
      decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(AppTheme.radiusRow)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title.isEmpty ? '—' : title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTheme.rowTitle),
                if (r.at != null) Text(formatAchievementWhen(context, r.at!), style: AppTheme.caption.copyWith(fontSize: 12)),
              ],
            ),
          ),
          if (canReplay)
            IconButton(
              tooltip: l10n.achievementReplay,
              icon: const Icon(Icons.play_arrow_rounded, color: AppTheme.textPrimary),
              onPressed: () => AchievementReplay.open(context, matchId: r.matchId!, value: r.value),
            ),
        ],
      ),
    );
  }
}
