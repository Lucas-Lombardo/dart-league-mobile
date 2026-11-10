import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/progression.dart';
import '../../providers/progression_provider.dart';
import '../../providers/subscription_provider.dart';
import '../../utils/app_theme.dart';
import '../../widgets/design_system.dart';
import '../../widgets/fit_text.dart';
import '../../widgets/progression/metal.dart';
import '../../widgets/progression/player_showcase_card.dart' show PremiumCrown, metalGradient;
import '../../widgets/progression/progression_widgets.dart';
import 'locker_screen.dart' show LockerDashedBorderPainter;
import 'progression_format.dart';

/// The levels path by tiers of ten (piste C, mockup docs/progression/ecrans/
/// R5C, generator svg/gen_revue56.py `p5c`): the tiers done folded and ticked
/// with their ten rewards in small, the current tier open (reached levels in
/// colour with a tick, the next one outlined with its XP bar, the rest in
/// grey silhouette with a lock), the tiers to come folded behind dashes, then
/// the prestige card past 50 (one star on the Légende frame every 10 levels).
/// The premium column shows each level's premium item with a small crown, in
/// colour only when it is mine (premium and the level reached).
class LevelsPathScreen extends StatefulWidget {
  const LevelsPathScreen({super.key});

  /// Tiers of ten from level 1 up to the last level the data rewards (50
  /// today), rounded up to a ten.
  @visibleForTesting
  static List<PathTier> tiers(ProgressionContent? content) {
    final top = [50, ...?content?.levels.keys].reduce(math.max);
    final last = ((top + 9) ~/ 10) * 10;
    return [for (var from = 1; from <= last; from += 10) PathTier(from, from + 9)];
  }

  /// The levels of the prestige card: the star levels (60, 70…) past the
  /// tiers, up to two stars past the current one (three at least). Empty
  /// without prestige data.
  @visibleForTesting
  static List<int> prestigeLevels(ProgressionContent? content, int current) {
    final prestige = content?.prestige;
    if (prestige == null) return const [];
    final lastTier = tiers(content).last.to;
    final stars = math.max(prestige.starsFor(current) + 2, 3);
    return [
      for (var n = 1; n <= stars; n++)
        if (prestige.levelOfStar(n) > lastTier) prestige.levelOfStar(n),
    ];
  }

  @override
  State<LevelsPathScreen> createState() => _LevelsPathScreenState();
}

/// Levels [from] to [to] (both included).
@immutable
class PathTier {
  final int from;
  final int to;
  const PathTier(this.from, this.to);

  /// Levels of the tier I have reached.
  int reached(int current) => (current - from + 1).clamp(0, to - from + 1);
  int get size => to - from + 1;

  /// Done: every level reached. Current: holds my next level. Locked: after it.
  PathTierState stateFor(int current) {
    if (current >= to) return PathTierState.done;
    if (current + 1 >= from) return PathTierState.current;
    return PathTierState.locked;
  }

  @override
  bool operator ==(Object other) => other is PathTier && other.from == from && other.to == to;
  @override
  int get hashCode => Object.hash(from, to);
  @override
  String toString() => 'PathTier($from–$to)';
}

enum PathTierState { done, current, locked }

enum _RowState { reached, next, locked }

class _LevelsPathScreenState extends State<LevelsPathScreen> {
  final _scroll = ScrollController();
  final _currentKey = GlobalKey();
  final _nextKey = GlobalKey();

  /// Folded cards (done or to come) the player opened; the prestige card
  /// is keyed by 0.
  final _open = <int>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealCurrent());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// The current card on screen from the start, with no scroll from the
  /// player: the smallest jump that shows my next level's row (with a little
  /// room under it), never past the card's title. Nothing moves when it is
  /// already on screen, so the tiers done above keep their place.
  void _revealCurrent() {
    if (!mounted || !_scroll.hasClients) return;
    final card = _currentKey.currentContext?.findRenderObject();
    if (card is! RenderBox) return;
    final viewport = RenderAbstractViewport.maybeOf(card);
    if (viewport == null) return;
    final next = _nextKey.currentContext?.findRenderObject();
    final top = viewport.getOffsetToReveal(card, 0).offset;
    final bottom = next is RenderBox
        ? viewport.getOffsetToReveal(next, 1).offset + 16
        : viewport.getOffsetToReveal(card, 1).offset;
    final target = math.min(top, math.max(bottom, 0.0)).clamp(0.0, _scroll.position.maxScrollExtent);
    if (target > 0) _scroll.jumpTo(target);
  }

  void _toggle(int key) => setState(() => _open.contains(key) ? _open.remove(key) : _open.add(key));

  bool _isPremium(ProgressionSummary? summary) {
    var subscribed = false;
    try {
      subscribed = context.watch<SubscriptionProvider>().isPremiumActive;
    } on ProviderNotFoundException {
      subscribed = false;
    }
    return subscribed || (summary?.isPremium ?? false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final p = context.watch<ProgressionProvider>();
    final content = p.content;
    final summary = p.summary;
    final current = summary?.level ?? 1;
    final premium = _isPremium(summary);
    final tiers = LevelsPathScreen.tiers(content);
    final prestigeLevels = LevelsPathScreen.prestigeLevels(content, current);
    final data = _PathData(
      provider: p,
      current: current,
      premium: premium,
      monogram: summary?.cosmetics.monogram ?? '',
      summary: summary,
      nextKey: _nextKey,
    );

    final cards = <Widget>[
      for (final tier in tiers)
        switch (tier.stateFor(current)) {
          PathTierState.current => _CurrentTierCard(key: _currentKey, tier: tier, data: data),
          PathTierState.done => _DoneTierCard(
              key: Key('path-tier-${tier.from}'),
              tier: tier,
              data: data,
              open: _open.contains(tier.from),
              onTap: () => _toggle(tier.from),
            ),
          PathTierState.locked => _LockedCard(
              key: Key('path-tier-${tier.from}'),
              title: l10n.pathTierRange(tier.from, tier.to),
              count: '0 / ${tier.size}',
              open: _open.contains(tier.from),
              onTap: () => _toggle(tier.from),
              rows: [for (var l = tier.from; l <= tier.to; l++) _levelRow(context, data, l)],
            ),
        },
      if (prestigeLevels.isNotEmpty)
        _PrestigeCard(
          key: current >= tiers.last.to ? _currentKey : const Key('path-prestige'),
          levels: prestigeLevels,
          data: data,
          isCurrent: current >= tiers.last.to,
          open: _open.contains(0),
          onTap: () => _toggle(0),
        ),
    ];

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
              child: DsScreenHeader(
                title: l10n.progressionPath,
                showBack: true,
                actions: [_LevelPill(level: current)],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < cards.length; i++) ...[
                      if (i > 0) const SizedBox(height: 10),
                      cards[i],
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// What every row needs to know about me.
class _PathData {
  final ProgressionProvider provider;
  final int current;
  final bool premium;
  final String monogram;
  final ProgressionSummary? summary;

  /// Around my next level's row (the tier's or the next star's).
  final GlobalKey nextKey;
  const _PathData({
    required this.provider,
    required this.current,
    required this.premium,
    required this.monogram,
    required this.summary,
    required this.nextKey,
  });

  List<ItemDef> items(int level) =>
      (provider.content?.levels[level]?.itemIds ?? const <String>[]).map(provider.item).whereType<ItemDef>().toList();

  ItemDef? premiumItem(int level) {
    final ids = provider.content?.levels[level]?.premiumItemIds ?? const <String>[];
    return ids.map(provider.item).whereType<ItemDef>().firstOrNull;
  }

  _RowState state(int level) => level <= current
      ? _RowState.reached
      : (level == current + 1 ? _RowState.next : _RowState.locked);
}

/// « Monogramme Acier », « Légende · cadre et titre » (two items, one name),
/// « Avatar de rang, fond uni » at level 1.
String levelsPathName(BuildContext context, List<ItemDef> items, int level) {
  final l10n = AppLocalizations.of(context);
  if (items.isEmpty) return level == 1 ? l10n.levelsPathBase : '—';
  final names = [for (final i in items) i.name.resolve(context)];
  if (items.length > 1 && names.toSet().length == 1) {
    final kinds = [for (final i in items) _shortKind(l10n, i.type)];
    return l10n.pathPairSame(names.first, kinds.sublist(0, kinds.length - 1).join(', '), kinds.last);
  }
  return names.toSet().join('\u00a0· ');
}

String _shortKind(AppLocalizations l10n, ItemType type) => switch (type) {
      ItemType.avatar => l10n.pathKindAvatar,
      ItemType.frame => l10n.pathKindFrame,
      ItemType.background => l10n.pathKindBackground,
      ItemType.title => l10n.pathKindTitle,
      ItemType.flight => l10n.pathKindFlight,
      _ => itemKindLabel(l10n, type),
    };

Widget _levelRow(BuildContext context, _PathData d, int level) {
  final items = d.items(level);
  final state = d.state(level);
  final premiumItem = d.premiumItem(level);
  final s = d.summary;
  final row = _PathRow(
    key: Key('path-level-$level'),
    level: level,
    state: state,
    name: levelsPathName(context, items, level),
    visual: items.isEmpty
        ? const _RankDisc(size: 28)
        : _ItemThumb(item: items.first, monogram: d.monogram, size: 28),
    premium: premiumItem == null
        ? null
        : _PremiumCell(
            item: premiumItem,
            monogram: d.monogram,
            mine: d.premium && state == _RowState.reached,
          ),
    progress: state == _RowState.next && s != null ? s.progress : null,
    xpLeft: state == _RowState.next && s != null ? formatXp(math.max(0, s.xpToNext - s.xpIntoLevel)) : null,
  );
  return state == _RowState.next ? KeyedSubtree(key: d.nextKey, child: row) : row;
}

// ─── Cards ───────────────────────────────────────────────────────────────────

/// Card text styles (mockup: 15/800 title, 13/800 count).
const _cardTitle = TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppTheme.textPrimary);
const _cardCount = TextStyle(
  fontSize: 13,
  fontWeight: FontWeight.w800,
  color: AppTheme.playerBlueBright,
  fontFeatures: [FontFeature.tabularFigures()],
);
const _lockColor = Color(0xFF475569);
const _radius = 16.0;

/// A tier with every level reached: folded, ticked, its ten rewards in small
/// and in colour; touching it unfolds its ten rows.
class _DoneTierCard extends StatelessWidget {
  final PathTier tier;
  final _PathData data;
  final bool open;
  final VoidCallback onTap;
  const _DoneTierCard({super.key, required this.tier, required this.data, required this.open, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final title = l10n.pathTierRange(tier.from, tier.to);
    final count = '${tier.size} / ${tier.size}';
    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(_radius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: Padding(
            padding: open ? const EdgeInsets.fromLTRB(8, 12, 8, 8) : const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: open ? const EdgeInsets.fromLTRB(6, 0, 6, 6) : EdgeInsets.zero,
                  child: Semantics(
                    button: true,
                    expanded: open,
                    label: '$title, $count',
                    excludeSemantics: true,
                    child: Row(
                      children: [
                        const _Tick(size: 22),
                        const SizedBox(width: 8),
                        Expanded(child: FitText(title, minFontSize: 12, style: _cardTitle)),
                        const SizedBox(width: 8),
                        Text(count, style: _cardCount),
                        const SizedBox(width: 8),
                        _Chevron(open: open, color: AppTheme.textTertiary),
                      ],
                    ),
                  ),
                ),
                if (open)
                  ..._rows(context)
                else ...[
                  const SizedBox(height: 8),
                  Row(
                    key: Key('path-minis-${tier.from}'),
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      for (var l = tier.from; l <= tier.to; l++)
                        data.items(l).isEmpty
                            ? const _RankDisc(size: 22, plain: true)
                            : _ItemThumb(item: data.items(l).first, monogram: data.monogram, size: 22),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _rows(BuildContext context) => [
        for (var l = tier.from; l <= tier.to; l++) ...[
          if (l > tier.from) const SizedBox(height: 4),
          _levelRow(context, data, l),
        ],
      ];
}

/// The tier holding my next level: always open.
class _CurrentTierCard extends StatelessWidget {
  final PathTier tier;
  final _PathData data;
  const _CurrentTierCard({super.key, required this.tier, required this.data});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _OpenCard(
      title: l10n.pathTierRange(tier.from, tier.to),
      count: '${tier.reached(data.current)} / ${tier.size}',
      rows: [for (var l = tier.from; l <= tier.to; l++) _levelRow(context, data, l)],
    );
  }
}

/// The open card of the current tier (and of prestige past 50): surface,
/// hairline border, title and count, one row per level.
class _OpenCard extends StatelessWidget {
  final String title;
  final String? count;
  final Widget? trailing;
  final List<Widget> rows;
  const _OpenCard({required this.title, this.count, this.trailing, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(_radius),
        border: Border.all(color: AppTheme.surfaceLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
            child: Row(
              children: [
                Expanded(child: FitText(title, minFontSize: 12, style: _cardTitle)),
                if (count != null) ...[const SizedBox(width: 8), Text(count!, style: _cardCount)],
                if (trailing != null) ...[const SizedBox(width: 8), trailing!],
              ],
            ),
          ),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(height: 4),
            rows[i],
          ],
        ],
      ),
    );
  }
}

/// A card still to come: no fill, dashed outline, lock, grey count; touching
/// it unfolds its rows, all still locked.
class _LockedCard extends StatelessWidget {
  final String title;
  final String? count;
  final bool open;
  final VoidCallback onTap;
  final List<Widget> rows;
  const _LockedCard({
    super.key,
    required this.title,
    this.count,
    required this.open,
    required this.onTap,
    required this.rows,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: const LockerDashedBorderPainter(radius: _radius),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(_radius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: Padding(
              padding: open ? const EdgeInsets.fromLTRB(8, 14, 8, 8) : const EdgeInsets.symmetric(horizontal: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    button: true,
                    expanded: open,
                    label: [title, ?count, AppLocalizations.of(context).pathLocked].join(', '),
                    excludeSemantics: true,
                    child: SizedBox(
                      height: open ? 28 : 50,
                      child: Padding(
                        padding: open ? const EdgeInsets.symmetric(horizontal: 6) : EdgeInsets.zero,
                        child: Row(
                          children: [
                            const Icon(Icons.lock_outline_rounded, size: 16, color: _lockColor),
                            const SizedBox(width: 8),
                            Expanded(
                              child: FitText(
                                title,
                                minFontSize: 12,
                                style: _cardTitle.copyWith(color: AppTheme.textTertiary),
                              ),
                            ),
                            if (count != null) ...[
                              const SizedBox(width: 8),
                              Text(count!, style: _cardCount.copyWith(color: _lockColor)),
                            ],
                            const SizedBox(width: 8),
                            _Chevron(open: open, color: _lockColor),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (open) ...[
                    const SizedBox(height: 6),
                    for (var i = 0; i < rows.length; i++) ...[
                      if (i > 0) const SizedBox(height: 4),
                      rows[i],
                    ],
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Past the last tier: one star on the Légende frame every 10 levels. Open
/// once every tier is done; before that, folded behind dashes like a tier to
/// come. Every star level draws the same single star.
class _PrestigeCard extends StatelessWidget {
  final List<int> levels;
  final _PathData data;
  final bool isCurrent;
  final bool open;
  final VoidCallback onTap;
  const _PrestigeCard({
    super.key,
    required this.levels,
    required this.data,
    required this.isCurrent,
    required this.open,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final content = data.provider.content;
    final prestige = content?.prestige;
    if (prestige == null) return const SizedBox.shrink();
    final metal = content?.item(prestige.frameId)?.metal ?? 'legende';
    final s = data.summary;
    final curve = content?.curve ?? const XpCurve();
    // A star level is « next » only once every tier is done: before that, my
    // next level is in a tier and the whole card is still to come.
    final next = isCurrent ? levels.where((l) => l > data.current).firstOrNull : null;

    Widget row(int level) {
      final star = prestige.starsFor(level);
      final state = level <= data.current
          ? _RowState.reached
          : (level == next ? _RowState.next : _RowState.locked);
      double? progress;
      String? left;
      if (state == _RowState.next && s != null) {
        // From the previous star level (or the last tier) to this one.
        final from = curve.xpForLevel(math.max(level - prestige.everyLevels, prestige.fromLevel));
        final to = curve.xpForLevel(level);
        final xp = s.xpTotal > 0 ? s.xpTotal : curve.xpForLevel(s.level) + s.xpIntoLevel;
        progress = to <= from ? 0 : ((xp - from) / (to - from)).clamp(0.0, 1.0);
        left = formatXp(math.max(0, to - xp));
      }
      final pathRow = _PathRow(
        key: Key('path-level-$level'),
        level: level,
        state: state,
        // « 1 · » and « Cadre Légende » each stay on one line.
        name: '${l10n.prestigeStarName(star)}\u00a0· ${l10n.prestigeStarKind.replaceAll(' ', '\u00a0')}',
        visual: PrestigeStars(key: Key('path-star-$level'), count: 1, metal: metal, size: 20),
        progress: progress,
        xpLeft: left,
        premiumColumn: false,
      );
      return state == _RowState.next ? KeyedSubtree(key: data.nextKey, child: pathRow) : pathRow;
    }

    final title = l10n.pathPrestige(prestige.everyLevels);
    final rows = [for (final l in levels) row(l)];
    if (isCurrent) {
      final stars = prestige.starsFor(data.current);
      return _OpenCard(
        title: title,
        trailing: stars > 0 ? PrestigeStars(count: stars, metal: metal, size: 14, maxDrawn: 0) : null,
        rows: rows,
      );
    }
    return _LockedCard(title: title, open: open, onTap: onTap, rows: rows);
  }
}

// ─── Rows ────────────────────────────────────────────────────────────────────

/// One level (mockup `crow`): number, reward, name, then a tick (reached), a
/// lock (to come) or the XP bar (next level), and the premium column.
class _PathRow extends StatelessWidget {
  final int level;
  final _RowState state;
  final String name;
  final Widget visual;
  final Widget? premium;
  final double? progress;
  final String? xpLeft;

  /// The 52 pt premium column, kept empty when the level has no premium item
  /// so the ticks stay aligned (the prestige rows have none).
  final bool premiumColumn;

  const _PathRow({
    super.key,
    required this.level,
    required this.state,
    required this.name,
    required this.visual,
    this.premium,
    this.progress,
    this.xpLeft,
    this.premiumColumn = true,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final reached = state == _RowState.reached;
    final next = state == _RowState.next;
    final numberColor = reached ? AppTheme.textPrimary : (next ? AppTheme.playerBlueBright : AppTheme.textTertiary);
    final nameColor = reached || next ? AppTheme.textPrimary : AppTheme.textTertiary;
    // The next level's bar runs to the right edge when it has no premium item
    // (mockup `crow`); every other row keeps the column, so the ticks align.
    final premiumSlot = premium ?? (premiumColumn && !next ? const SizedBox(width: _PremiumCell.width) : null);
    return Semantics(
      label: [
        l10n.xpLevel(level),
        name,
        if (reached) l10n.pathReached,
        if (state == _RowState.locked) l10n.pathLocked,
        if (xpLeft != null) l10n.pathXpLeft(xpLeft!),
      ].join(', '),
      excludeSemantics: true,
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: next ? const Color(0x1A38BDF8) : null,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: next ? AppTheme.primaryLight : Colors.transparent, width: 1.5),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 26,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  '$level',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: numberColor,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 36,
              child: Center(child: state == _RowState.locked ? _Silhouette(child: visual) : visual),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FitText(
                name,
                maxLines: 2,
                minFontSize: 11,
                style: TextStyle(fontSize: 14, height: 1.2, fontWeight: FontWeight.w700, color: nameColor),
              ),
            ),
            const SizedBox(width: 10),
            if (next)
              _NextBar(progress: progress ?? 0, xpLeft: xpLeft, width: premium == null ? 90 : 64)
            else if (reached)
              const _Tick(size: 20)
            else
              const SizedBox(
                width: 20,
                child: Icon(Icons.lock_outline_rounded, size: 15, color: _lockColor),
              ),
            if (premiumSlot != null) ...[const SizedBox(width: 10), premiumSlot],
          ],
        ),
      ),
    );
  }
}

/// The next level's XP: a 5 pt bar and « 774 XP » under it, on the right.
class _NextBar extends StatelessWidget {
  final double progress;
  final String? xpLeft;
  final double width;
  const _NextBar({required this.progress, required this.xpLeft, required this.width});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SizedBox(
      width: width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Bar(value: progress, height: 5),
          if (xpLeft != null) ...[
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                l10n.pathXpLeft(xpLeft!),
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.playerBlueBright),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  final double value;
  final double height;
  const _Bar({required this.value, required this.height});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        height: height,
        child: ColoredBox(
          color: AppTheme.surfaceLight,
          child: Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: value.clamp(0.0, 1.0),
              heightFactor: 1,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  color: AppTheme.primaryLight,
                  borderRadius: BorderRadius.all(Radius.circular(999)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The premium item of a level, crowned: in colour when it is mine (premium
/// and the level reached), in silhouette otherwise.
class _PremiumCell extends StatelessWidget {
  static const width = 52.0;
  final ItemDef item;
  final String monogram;
  final bool mine;
  const _PremiumCell({required this.item, required this.monogram, required this.mine});

  @override
  Widget build(BuildContext context) {
    final thumb = _ItemThumb(item: item, monogram: monogram, size: 34);
    return SizedBox(
      width: width,
      height: 40,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.centerRight,
        children: [
          KeyedSubtree(
            key: Key(mine ? 'path-premium-mine' : 'path-premium-locked'),
            child: mine ? thumb : _Silhouette(child: thumb),
          ),
          const Positioned(top: -2, right: -4, child: PremiumCrown(size: 12)),
        ],
      ),
    );
  }
}

// ─── Small pieces ────────────────────────────────────────────────────────────

/// Grey, darker and see-through: CSS grayscale(1) brightness(.6), opacity .45
/// (the mockup's SIL).
const _silhouetteFilter = ColorFilter.matrix(<double>[
  0.2126 * 0.6, 0.7152 * 0.6, 0.0722 * 0.6, 0, 0, //
  0.2126 * 0.6, 0.7152 * 0.6, 0.0722 * 0.6, 0, 0, //
  0.2126 * 0.6, 0.7152 * 0.6, 0.0722 * 0.6, 0, 0, //
  0, 0, 0, 0.45, 0,
]);

class _Silhouette extends StatelessWidget {
  final Widget child;
  const _Silhouette({required this.child});

  @override
  Widget build(BuildContext context) => ColorFiltered(colorFilter: _silhouetteFilter, child: child);
}

/// An item's thumbnail. A title draws as a small brass plate (the plate of the
/// player card) so a reached one and a locked one differ like other items.
class _ItemThumb extends StatelessWidget {
  final ItemDef item;
  final String monogram;
  final double size;
  const _ItemThumb({required this.item, required this.monogram, required this.size});

  @override
  Widget build(BuildContext context) {
    if (item.type != ItemType.title) {
      return ProgressionItemVisual(item: item, monogramText: monogram, size: size);
    }
    final metal = MetalPalette.of(watchProgressionContent(context), 'laiton');
    return SizedBox.square(
      dimension: size,
      child: Center(
        child: Container(
          width: size,
          height: size * 0.62,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(size * 0.16),
            gradient: metalGradient(metal, begin: Alignment.topCenter, end: Alignment.bottomCenter),
          ),
          child: Text(
            'Aa',
            style: TextStyle(fontSize: size * 0.32, height: 1, fontWeight: FontWeight.w800, color: const Color(0xFF1A1406)),
          ),
        ),
      ),
    );
  }
}

/// Level 1 has no item: the rank avatar and a plain background. A slate disc
/// (with a person when there is room for it).
class _RankDisc extends StatelessWidget {
  final double size;
  final bool plain;
  const _RankDisc({required this.size, this.plain = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(color: AppTheme.surfaceLight, shape: BoxShape.circle),
      child: plain ? null : Icon(Icons.person_rounded, size: size * 0.6, color: AppTheme.textSecondary),
    );
  }
}

/// The blue disc with a dark tick.
class _Tick extends StatelessWidget {
  final double size;
  const _Tick({required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(color: AppTheme.primaryLight, shape: BoxShape.circle),
      child: Icon(Icons.check_rounded, size: size * 0.62, color: AppTheme.background),
    );
  }
}

class _Chevron extends StatelessWidget {
  final bool open;
  final Color color;
  const _Chevron({required this.open, required this.color});

  @override
  Widget build(BuildContext context) => AnimatedRotation(
        turns: open ? 0.5 : 0,
        duration: const Duration(milliseconds: 200),
        child: Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: color),
      );
}

/// « Niv. 23 » on the right of the header.
class _LevelPill extends StatelessWidget {
  final int level;
  const _LevelPill({required this.level});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.surfaceLight),
      ),
      child: Text(
        AppLocalizations.of(context).xpLevelShort(level),
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          color: AppTheme.textPrimary,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}
