import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../utils/app_theme.dart';
import '../../widgets/design_system.dart';
import '../../widgets/fit_text.dart';
import '../../widgets/progression/metal.dart';
import '../../widgets/progression/progression_widgets.dart';
import 'achievement_detail_screen.dart';
import 'achievement_format.dart';
import 'achievement_models.dart';
import 'achievements_service.dart';

/// The color a tier's name is written in (the metal's light stop).
Color achievementTierColor(BuildContext context, String? tier) {
  if (tier == null) return AppTheme.textSecondary;
  final content = readProgressionContent(context);
  return MetalPalette.of(content, MetalPalette.forTier(tier == 'unique' ? null : tier)).first;
}

/// The achievements collection (mockup ecrans/HFCollection.dc.html): family
/// chips, the closest tier to reach, then every achievement as a badge.
class AchievementsScreen extends StatefulWidget {
  /// Opens on this family ('scoring', 'finishing'…), every family when null.
  final String? initialFamily;

  /// Test seam: the network call.
  final Future<AchievementsSnapshot> Function()? load;

  const AchievementsScreen({super.key, this.initialFamily, this.load});

  static Route<void> route({String? family}) =>
      MaterialPageRoute(builder: (_) => AchievementsScreen(initialFamily: family));

  @override
  State<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends State<AchievementsScreen> {
  late Future<AchievementsSnapshot> _future = _fetch();
  late String? _family = widget.initialFamily;

  Future<AchievementsSnapshot> _fetch() => (widget.load ?? AchievementsService.list)();

  Future<void> _reload() async {
    final f = _fetch();
    setState(() => _future = f);
    await f.catchError((_) => const AchievementsSnapshot());
  }

  Future<void> _open(Achievement a) async {
    await Navigator.of(context).push(AchievementDetailScreen.route(a));
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: FutureBuilder<AchievementsSnapshot>(
          future: _future,
          builder: (context, snap) {
            final data = snap.data;
            return Column(
              children: [
                DsScreenHeader(
                  title: l10n.achievementsTitle,
                  showBack: true,
                  actions: [
                    if (data != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Text(
                          '${data.unlocked} / ${data.total}',
                          style: AppTheme.rowTitle.copyWith(color: AppTheme.textSecondary, fontWeight: FontWeight.w700),
                        ),
                      ),
                  ],
                ),
                Expanded(
                  child: data == null
                      ? Center(
                          child: snap.hasError
                              ? Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(l10n.achievementLoadFailed, style: AppTheme.caption),
                                    const SizedBox(height: 8),
                                    TextButton(onPressed: _reload, child: Text(l10n.achievementRetry)),
                                  ],
                                )
                              : const CircularProgressIndicator(color: AppTheme.primary),
                        )
                      : RefreshIndicator(
                          color: AppTheme.primary,
                          onRefresh: _reload,
                          child: _body(context, data),
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _body(BuildContext context, AchievementsSnapshot data) {
    final l10n = AppLocalizations.of(context);
    final known = data.families.map((f) => f.id).toSet();
    final shown = data.achievements
        .where((a) => _family == null || a.family == _family || (_family == 'other' && !known.contains(a.family)))
        .toList();
    final closest = data.closest;
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: SizedBox(
            height: 50,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              children: [
                _Chip(label: l10n.achievementFamilyAll, selected: _family == null, onTap: () => setState(() => _family = null)),
                for (final f in data.families)
                  _Chip(
                    label: f.name.resolve(context),
                    selected: _family == f.id,
                    onTap: () => setState(() => _family = f.id),
                  ),
              ],
            ),
          ),
        ),
        if (closest != null && (_family == null || closest.family == _family))
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            sliver: SliverToBoxAdapter(child: _ClosestCard(achievement: closest, onTap: () => _open(closest))),
          ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              mainAxisExtent: 150,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, i) => AchievementTile(achievement: shown[i], onTap: () => _open(shown[i])),
              childCount: shown.length,
            ),
          ),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Chip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Material(
        color: selected ? AppTheme.surfaceLight : AppTheme.surface,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Center(
              child: Text(
                label,
                style: AppTheme.caption.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: selected ? AppTheme.textPrimary : AppTheme.textSecondary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ClosestCard extends StatelessWidget {
  final Achievement achievement;
  final VoidCallback onTap;
  const _ClosestCard({required this.achievement, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final a = achievement;
    final next = a.next!;
    return DsCard(
      onTap: onTap,
      side: const BorderSide(color: AppTheme.primaryLight, width: 1.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.achievementClosest, style: AppTheme.caption.copyWith(fontSize: 13)),
          const SizedBox(height: 8),
          Text(
            l10n.achievementClosestTier(a.name.resolve(context), achievementTierName(l10n, next.tier)),
            style: AppTheme.titleLarge.copyWith(fontSize: 17),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: DsProgressBar(value: next.ratio, color: AppTheme.primaryLight, height: 8)),
              const SizedBox(width: 12),
              Text(achievementProgress(context, a), style: AppTheme.rowTitle.copyWith(fontWeight: FontWeight.w800)),
            ],
          ),
        ],
      ),
    );
  }
}

/// One achievement of the collection: medal, name, tier, progress or rarity.
class AchievementTile extends StatelessWidget {
  final Achievement achievement;
  final VoidCallback? onTap;
  const AchievementTile({super.key, required this.achievement, this.onTap});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final a = achievement;
    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(AppTheme.radiusRow),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 10),
          child: Column(
            children: [
              BadgeMedal(badge: a.badge, size: 44, locked: !a.unlocked),
              const SizedBox(height: 7),
              // Names and notes wrap between words on two lines; a word too
              // wide for the tile shrinks, it is never cut in two.
              FitText(
                a.name.resolve(context),
                maxLines: 2,
                minFontSize: 10,
                textAlign: TextAlign.center,
                style: AppTheme.caption.copyWith(
                  fontSize: 13,
                  height: 1.25,
                  fontWeight: FontWeight.w700,
                  color: a.unlocked ? AppTheme.textPrimary : AppTheme.textSecondary,
                ),
              ),
              const Spacer(),
              Text(
                achievementTierName(l10n, a.tier),
                maxLines: 1,
                style: AppTheme.caption.copyWith(
                  fontSize: 11,
                  height: 1.2,
                  fontWeight: FontWeight.w700,
                  color: achievementTierColor(context, a.tier),
                ),
              ),
              // Room for two lines on every tile: the tier names of a row
              // stay on one line whether the note takes one or two.
              ConstrainedBox(
                constraints: BoxConstraints(minHeight: MediaQuery.textScalerOf(context).scale(11) * 1.2 * 2),
                child: FitText(
                  achievementTileNote(context, a),
                  maxLines: 2,
                  minFontSize: 9,
                  textAlign: TextAlign.center,
                  style: AppTheme.caption.copyWith(fontSize: 11, height: 1.2, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
