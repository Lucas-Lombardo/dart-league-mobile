import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/progression.dart';
import '../../models/user.dart';
import '../../providers/auth_provider.dart';
import '../../providers/progression_provider.dart';
import '../../providers/subscription_provider.dart';
import '../../utils/app_theme.dart';
import '../../widgets/design_system.dart';
import '../../widgets/fit_text.dart';
import '../../widgets/progression/player_showcase_card.dart';
import '../../widgets/progression/progression_widgets.dart';
import '../achievements/achievement_detail_screen.dart';
import '../achievements/badge_picker.dart';
import '../league/league_screen.dart';
import '../onboarding/onboarding_journey_screen.dart';
import '../settings/subscription_screen.dart';
import 'levels_path_screen.dart';
import 'locker_letters_sheet.dart';
import 'locker_unlock.dart';
import 'progression_screen.dart';

/// The locker, piste A « Deux rayons » (mockups docs/progression/ecrans/
/// CasA1, CasA2, CasObtenir; CONTRACT §14.11): my S1 card as a live preview,
/// one tab per item type, and in each tab two shelves — « À toi » (in colour,
/// tap to equip) and « À débloquer » (silhouettes in a dashed outline, the
/// short condition instead of the name; tap for « Comment l'obtenir »).
/// « Essayer sur ma carte » shows a locked item on the card, locally only.
/// The letters of a monogram avatar are edited from the pencil of the
/// equipped one.
class LockerScreen extends StatefulWidget {
  final ItemType initialTab;
  const LockerScreen({super.key, this.initialTab = ItemType.avatar});

  @override
  State<LockerScreen> createState() => _LockerScreenState();
}

// Agent 3: the Badges tab (pin up to 3 to the showcase) is BadgePicker.
const _tabs = [ItemType.avatar, ItemType.frame, ItemType.background, ItemType.title, ItemType.flight, ItemType.badge];

/// My cosmetics with [item] in its slot: what « Essayer sur ma carte » shows.
PublicCosmetics lockerTryOn(PublicCosmetics c, ItemDef item) => PublicCosmetics(
  level: c.level,
  avatar: item.type == ItemType.avatar ? item.id : c.avatar,
  monogram: c.monogram,
  frame: item.type == ItemType.frame ? item.id : c.frame,
  background: item.type == ItemType.background ? item.id : c.background,
  title: item.type == ItemType.title ? item.id : c.title,
  flight: item.type == ItemType.flight ? item.id : c.flight,
  badges: c.badges,
);

class _LockerScreenState extends State<LockerScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  /// The locked item shown on the card (« Aperçu »); never sent.
  ItemDef? _trying;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: _tabs.length,
      vsync: this,
      initialIndex: _tabs.indexOf(widget.initialTab).clamp(0, _tabs.length - 1),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final p = context.read<ProgressionProvider>();
      await Future.wait([p.refreshInventory(), p.refreshSummary(), p.refreshContent()]);
      if (!mounted) return;
      setState(() => _loaded = true);
      final fresh = p.inventory?.items.where((i) => i.isNew).map((i) => i.itemId).toList() ?? const [];
      if (fresh.isNotEmpty) p.markItemsSeen(fresh);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _tabLabel(AppLocalizations l10n, ItemType t) => switch (t) {
    ItemType.avatar => l10n.lockerTabAvatars,
    ItemType.frame => l10n.lockerTabFrames,
    ItemType.background => l10n.lockerTabBackgrounds,
    ItemType.title => l10n.lockerTabTitles,
    ItemType.badge => l10n.achievementBadgesTab,
    _ => l10n.lockerTabFlights,
  };

  User? _me(BuildContext context) {
    try {
      return context.watch<AuthProvider>().currentUser;
    } on ProviderNotFoundException {
      return null;
    }
  }

  /// Premium per the subscription or the server's progression (either one).
  bool _isPremium(BuildContext context, ProgressionSummary? summary) {
    var subscribed = false;
    try {
      subscribed = context.watch<SubscriptionProvider>().isPremiumActive;
    } on ProviderNotFoundException {
      subscribed = false;
    }
    return subscribed || (summary?.isPremium ?? false);
  }

  void _stopTrying() {
    if (_trying != null) setState(() => _trying = null);
  }

  Future<void> _equip(ItemType type, String? itemId) async {
    _stopTrying();
    final l10n = AppLocalizations.of(context);
    final ok = await context.read<ProgressionProvider>().equip(EquipRequest.slot(type, itemId));
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.lockerEquipFailed)));
    }
  }

  Future<void> _editLetters(ItemDef item, String current, MonogramChoice? choice, String username) async {
    _stopTrying();
    final result = await LockerLettersSheet.show(context, item: item, current: current, choice: choice, username: username);
    if (result == null || !mounted) return;
    final ok = await context.read<ProgressionProvider>().equip(EquipRequest(monogram: result.choice));
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).lockerEquipFailed)));
    }
  }

  Future<void> _openLocked(ItemDef item, String monogram, bool isPremium) async {
    _stopTrying();
    final outcome = await LockerUnlockSheet.show(
      context,
      item: item,
      monogram: monogram,
      isPremium: isPremium,
      // A flight never shows on the card: nothing to try there.
      canTry: item.type != ItemType.flight,
    );
    if (outcome == null || !mounted) return;
    if (outcome.tryOn) {
      setState(() => _trying = item);
      return;
    }
    final Widget? screen = switch (outcome.action) {
      LockerHowAction.levels => const LevelsPathScreen(),
      LockerHowAction.premium => const SubscriptionScreen(),
      LockerHowAction.achievement => outcome.achievement == null ? null : AchievementDetailScreen(achievement: outcome.achievement!),
      LockerHowAction.league => const LeagueScreen(),
      // An event item's quest: the journal's « Événement » tab.
      LockerHowAction.quests => const ProgressionScreen(initialTab: QuestTab.event),
      LockerHowAction.journey => const OnboardingJourneyScreen(),
      null => null,
    };
    if (screen == null) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    if (!mounted) return;
    // Back from the levels, the paywall or a match: the item may be mine now.
    final p = context.read<ProgressionProvider>();
    if (outcome.action == LockerHowAction.premium) {
      try {
        await context.read<SubscriptionProvider>().refresh();
      } on ProviderNotFoundException {
        // Tests: no subscription provider.
      } catch (e) {
        debugPrint('LockerScreen: subscription refresh failed: $e');
      }
    }
    await Future.wait([p.refreshSummary(), p.refreshInventory()]);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final p = context.watch<ProgressionProvider>();
    final user = _me(context);
    final summary = p.summary;
    final cosmetics = summary?.cosmetics ?? user?.cosmetics ?? const PublicCosmetics();
    final equipment = p.inventory?.equipment ?? summary?.equipment ?? const Equipment();
    final owned = {for (final i in p.inventory?.items ?? const <InventoryItem>[]) i.itemId: i};
    final rank = user?.rank ?? 'unranked';
    final isPremium = _isPremium(context, summary);
    final trying = _trying;
    final waiting = !_loaded && p.inventory == null;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
              child: DsScreenHeader(title: l10n.lockerTitle, showBack: true),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 12),
              child: Stack(
                children: [
                  PlayerShowcaseCard(
                    username: user?.username ?? '',
                    rank: user?.rank,
                    cosmetics: trying == null ? cosmetics : lockerTryOn(cosmetics, trying),
                    isPremium: isPremium,
                    level: summary?.level ?? cosmetics.level,
                  ),
                  if (trying != null) Positioned(right: 14, bottom: 12, child: _PreviewTag(onTap: _stopTrying)),
                ],
              ),
            ),
            TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelColor: AppTheme.textPrimary,
              unselectedLabelColor: AppTheme.textSecondary,
              indicatorColor: AppTheme.primaryLight,
              dividerColor: AppTheme.border,
              tabs: [for (final t in _tabs) Tab(text: _tabLabel(l10n, t))],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  for (final t in _tabs)
                    if (t == ItemType.badge)
                      const BadgePicker()
                    else if (waiting)
                      const Center(child: CircularProgressIndicator(color: AppTheme.primaryLight))
                    else
                      _Shelves(
                        type: t,
                        items: p.content?.itemsOfType(t) ?? const [],
                        owned: owned,
                        equipped: equipment.slot(t),
                        monogram: cosmetics.monogram,
                        rank: rank,
                        busy: p.isBusy,
                        onEquip: (id) => _equip(t, id),
                        onLocked: (item) => _openLocked(item, cosmetics.monogram, isPremium),
                        onEditLetters: (item) => _editLetters(item, cosmetics.monogram, equipment.monogram, user?.username ?? ''),
                        onEquippedTap: _stopTrying,
                      ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// « Aperçu » on the card while a locked item is tried on; a tap cancels.
class _PreviewTag extends StatelessWidget {
  final VoidCallback onTap;
  const _PreviewTag({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      button: true,
      label: l10n.lockerSPreviewCancel,
      excludeSemantics: true,
      child: Material(
        key: const Key('locker-preview-tag'),
        color: const Color(0xCC0A0E18),
        shape: const StadiumBorder(side: BorderSide(color: AppTheme.playerBlueBright)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 26,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.visibility_outlined, size: 13, color: AppTheme.playerBlueBright),
                  const SizedBox(width: 5),
                  Text(
                    l10n.lockerSPreview,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppTheme.playerBlueBright),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One tab: « À toi » then « À débloquer », 4 tiles of 92 pt per row.
class _Shelves extends StatelessWidget {
  final ItemType type;
  final List<ItemDef> items;
  final Map<String, InventoryItem> owned;
  final String? equipped;
  final String monogram;
  final String rank;
  final bool busy;
  final ValueChanged<String?> onEquip;
  final ValueChanged<ItemDef> onLocked;
  final ValueChanged<ItemDef> onEditLetters;
  final VoidCallback onEquippedTap;

  const _Shelves({
    required this.type,
    required this.items,
    required this.owned,
    required this.equipped,
    required this.monogram,
    required this.rank,
    required this.busy,
    required this.onEquip,
    required this.onLocked,
    required this.onEditLetters,
    required this.onEquippedTap,
  });

  static const _grid = SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: 4,
    mainAxisSpacing: 8,
    crossAxisSpacing: 8,
    mainAxisExtent: 92,
  );

  Widget _header(String title, int count) => Row(
    crossAxisAlignment: CrossAxisAlignment.baseline,
    textBaseline: TextBaseline.alphabetic,
    children: [
      Text(
        title,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
      ),
      const SizedBox(width: 8),
      Text(
        '$count',
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppTheme.textTertiary),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Catalog order inside each shelf.
    final mine = items.where((i) => owned.containsKey(i.id)).toList();
    final locked = items.where((i) => !owned.containsKey(i.id)).toList();
    final defaultTile = _OwnedTile(
      key: const Key('locker-owned-default'),
      visual: type == ItemType.avatar
          ? PlayerAvatar(rank: rank, size: 46)
          : const Icon(Icons.block_rounded, color: AppTheme.textTertiary, size: 26),
      name: type == ItemType.avatar ? l10n.lockerDefaultAvatar : l10n.lockerNone,
      equipped: equipped == null,
      onTap: equipped == null ? onEquippedTap : (busy ? null : () => onEquip(null)),
    );
    return CustomScrollView(
      key: PageStorageKey('locker-${type.name}'),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          sliver: SliverToBoxAdapter(child: _header(l10n.lockerSOwned, mine.length + 1)),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverGrid(
            gridDelegate: _grid,
            delegate: SliverChildListDelegate([
              defaultTile,
              for (final item in mine)
                _OwnedTile(
                  key: Key('locker-owned-${item.id}'),
                  visual: ProgressionItemVisual(item: item, monogramText: monogram, size: 46),
                  name: item.name.resolve(context),
                  equipped: equipped == item.id,
                  isNew: owned[item.id]?.isNew ?? false,
                  letters: item.isMonogram && equipped == item.id,
                  onTap: equipped == item.id
                      ? (item.isMonogram ? () => onEditLetters(item) : onEquippedTap)
                      : (busy ? null : () => onEquip(item.id)),
                ),
            ]),
          ),
        ),
        if (locked.isNotEmpty) ...[
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 10),
            sliver: SliverToBoxAdapter(child: _header(l10n.lockerSToUnlock, locked.length)),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverGrid(
              gridDelegate: _grid,
              delegate: SliverChildListDelegate([
                for (final item in locked)
                  _LockedTile(
                    key: Key('locker-locked-${item.id}'),
                    item: item,
                    // A title is its own visual: its text, readable without a tap.
                    visual: item.type == ItemType.title
                        ? _LockedTitlePlate(title: item.name.resolve(context))
                        : ProgressionItemVisual(item: item, monogramText: monogram, size: 46),
                    onTap: () => onLocked(item),
                  ),
              ]),
            ),
          ),
        ],
        const SliverPadding(padding: EdgeInsets.only(bottom: 16)),
      ],
    );
  }
}

const _tileRadius = 16.0;

/// An item of mine: in colour on the surface, its name only. Equipped =
/// blue outline + check; new = blue dot; the equipped monogram avatar
/// carries a pencil (its letters).
class _OwnedTile extends StatelessWidget {
  final Widget visual;
  final String name;
  final bool equipped;
  final bool isNew;
  final bool letters;
  final VoidCallback? onTap;

  const _OwnedTile({
    super.key,
    required this.visual,
    required this.name,
    required this.equipped,
    this.isNew = false,
    this.letters = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      button: onTap != null,
      selected: equipped,
      label: [name, if (equipped) l10n.lockerEquipped, if (letters) l10n.lockerSLettersEdit].join(', '),
      excludeSemantics: true,
      child: Material(
        color: AppTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_tileRadius),
          side: BorderSide(color: equipped ? AppTheme.primaryLight : Colors.transparent, width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            children: [
              // Top-aligned, not centred: every visual of a row sits on the
              // same line whether its name takes one line or two.
              Positioned.fill(
                child: Column(
                  children: [
                    const SizedBox(height: 11),
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        SizedBox.square(dimension: 46, child: Center(child: visual)),
                        if (letters)
                          const Positioned(
                            right: -6,
                            bottom: -4,
                            child: _Chip(
                              key: Key('locker-letters-pencil'),
                              icon: Icons.edit_rounded,
                              border: AppTheme.primaryLight,
                              color: AppTheme.playerBlueBright,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // Two lines between words (« Monogramme / Acier »); a
                    // word too wide for the tile shrinks, never cut in two.
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: FitText(
                        name,
                        maxLines: 2,
                        minFontSize: 9,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 11,
                          height: 1.15,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (equipped)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    key: const Key('locker-equipped-check'),
                    width: 18,
                    height: 18,
                    decoration: const BoxDecoration(color: AppTheme.primaryLight, shape: BoxShape.circle),
                    child: const Icon(Icons.check_rounded, size: 12, color: AppTheme.background),
                  ),
                ),
              if (isNew)
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(color: AppTheme.primaryLight, shape: BoxShape.circle),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Grey, darker and half transparent (CSS grayscale(1) brightness(.55),
/// opacity .5 of the mockup).
const _silhouette = ColorFilter.matrix(<double>[
  0.2126 * 0.55, 0.7152 * 0.55, 0.0722 * 0.55, 0, 0, //
  0.2126 * 0.55, 0.7152 * 0.55, 0.0722 * 0.55, 0, 0, //
  0.2126 * 0.55, 0.7152 * 0.55, 0.0722 * 0.55, 0, 0, //
  0, 0, 0, 0.5, 0,
]);

/// An item to unlock: no fill, a dashed outline, the visual in silhouette
/// with a lock, and the short condition instead of the name (a title shows
/// its text on a grey plate, then the condition).
class _LockedTile extends StatelessWidget {
  final ItemDef item;
  final Widget visual;
  final VoidCallback onTap;
  const _LockedTile({super.key, required this.item, required this.visual, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cond = lockerCondition(context, item);
    final color = cond.premium ? AppTheme.accent : AppTheme.textSecondary;
    return Semantics(
      button: true,
      label: '${item.name.resolve(context)}, ${cond.text}',
      excludeSemantics: true,
      child: CustomPaint(
        foregroundPainter: const LockerDashedBorderPainter(),
        child: Material(
          color: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_tileRadius)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    if (item.type == ItemType.title)
                      SizedBox(width: _titlePlateWidth, height: 46, child: visual)
                    else
                      SizedBox.square(
                        dimension: 46,
                        child: ColorFiltered(
                          colorFilter: _silhouette,
                          child: Center(child: visual),
                        ),
                      ),
                    const Positioned(
                      right: -6,
                      bottom: -4,
                      child: _Chip(icon: Icons.lock_outline_rounded, border: Color(0xFF475569), color: Color(0xFFCBD5E1)),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (cond.premium) ...[const PremiumCrown(size: 11), const SizedBox(width: 3)],
                    Flexible(
                      child: Text(
                        cond.text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: color),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

const _titlePlateWidth = 70.0;

/// A locked title: its text on a grey plate (the silhouette of the card's
/// metal plate), up to two lines.
class _LockedTitlePlate extends StatelessWidget {
  final String title;
  const _LockedTitlePlate({required this.title});

  static const _style = TextStyle(fontSize: 11, height: 1.15, fontWeight: FontWeight.w800, color: Color(0xFFCBD5E1));

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('locker-title-plate'),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF3B4658), Color(0xFF283243)],
        ),
      ),
      // One word is never cut in two: it shrinks to fit the plate instead.
      child: title.trim().contains(' ')
          ? Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: _style)
          : FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(title, maxLines: 1, style: _style),
            ),
    );
  }
}

/// The 20 pt round chip on a tile's visual (lock, pencil).
class _Chip extends StatelessWidget {
  final IconData icon;
  final Color border;
  final Color color;
  const _Chip({super.key, required this.icon, required this.border, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: AppTheme.background,
        shape: BoxShape.circle,
        border: Border.all(color: border, width: 1.5),
      ),
      child: Icon(icon, size: 11, color: color),
    );
  }
}

/// The dashed 1.5 pt outline (#334155) of an item to unlock.
class LockerDashedBorderPainter extends CustomPainter {
  final Color color;
  final double width;
  final double radius;
  final double dash;
  final double gap;
  const LockerDashedBorderPainter({
    this.color = AppTheme.surfaceLight,
    this.width = 1.5,
    this.radius = _tileRadius,
    this.dash = 4.5,
    this.gap = 3.5,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(width / 2);
    final path = Path()..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius - width / 2)));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + dash), paint);
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant LockerDashedBorderPainter old) =>
      old.color != color || old.width != width || old.radius != radius || old.dash != dash || old.gap != gap;
}
