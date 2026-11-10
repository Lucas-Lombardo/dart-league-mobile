import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/progression.dart';
import '../../models/season.dart';
import '../../providers/progression_provider.dart';
import '../../providers/season_provider.dart';
import '../../utils/app_theme.dart';
import '../../widgets/progression/metal.dart';
import '../../widgets/progression/player_showcase_card.dart' show PremiumCrown;
import '../../widgets/progression/progression_widgets.dart';
import '../achievements/achievement_format.dart';
import '../achievements/achievement_models.dart';
import '../achievements/achievements_service.dart';
import '../league/league_models.dart';
import '../league/league_store.dart';
import '../onboarding/onboarding_models.dart';
import '../onboarding/onboarding_provider.dart';

// « Comment l'obtenir » (mockups docs/progression/ecrans/CasA2 and
// CasObtenir, generator `unlock_box` / `CASES` in svg/gen_casier.py): the
// short condition under a locked item of the locker, and the sheet that opens
// when it is tapped — one sentence, where I stand, a bar when it can be
// measured, and a button to the right screen. A missing piece of data (no
// network, unknown achievement) drops the line or the bar, never errors.

/// The short condition under a locked tile: « Niv. 27 », « Premium »…
/// [premium] paints it gold with the crown.
({String text, bool premium}) lockerCondition(BuildContext context, ItemDef item) {
  final l10n = AppLocalizations.of(context);
  final s = item.source;
  return switch (s.kind) {
    'level' when s.level != null => (text: l10n.xpLevelShort(s.level!), premium: false),
    'premium_level' => (text: l10n.lockerSCondPremium, premium: true),
    'achievement' => (text: l10n.lockerSCondAchievement, premium: false),
    'league' => (text: l10n.lockerSCondLeague, premium: false),
    'season' => (
      text: int.tryParse(s.ref ?? '') != null ? l10n.lockerSCondSeason(int.parse(s.ref!)) : _capitalized(s.label.resolve(context)),
      premium: false,
    ),
    'event' => (text: l10n.lockerSCondEvent, premium: false),
    'onboarding' => (text: l10n.lockerSCondOnboarding, premium: false),
    _ => (text: _capitalized(s.label.resolve(context)), premium: item.premium),
  };
}

String _capitalized(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// The tier of an achievement that gives an item (content `defs.achievement`).
class LockerAchievementReward {
  final Map<String, dynamic> def;
  final String tier; // bronze | silver | gold | unique
  final double threshold;
  const LockerAchievementReward({required this.def, required this.tier, required this.threshold});

  String get id => def['id'] as String;
  LocalizedText get name => LocalizedText.fromJson(def['name']);
  LocalizedText get description => LocalizedText.fromJson(def['description']);

  /// What the collection would know of it: lets « Voir le succès » open the
  /// detail screen (which refreshes itself) even without the network.
  Achievement get asAchievement {
    final tiers = def['tiers'];
    final unique = def['unique'];
    List<String> ids(dynamic v) => v is List ? v.whereType<String>().toList() : const [];
    double n(dynamic v) => v is num ? v.toDouble() : 0;
    return Achievement(
      id: id,
      family: def['family'] is String ? def['family'] as String : 'other',
      name: name,
      description: description,
      badgeId: def['badgeId'] is String ? def['badgeId'] as String : 'badge.$id',
      aiOnly: def['aiOnly'] == true,
      format: def['format'] is String ? def['format'] as String : 'int',
      unique: tiers is! List,
      steps: [
        if (tiers is List)
          for (final t in tiers.whereType<Map>())
            if (kAchievementTiers.contains(t['tier']))
              AchievementStep(tier: t['tier'] as String, threshold: n(t['threshold']), xp: n(t['xp']).round(), itemIds: ids(t['itemIds'])),
        if (tiers is! List && unique is Map)
          AchievementStep(tier: 'unique', threshold: n(unique['threshold']), xp: n(unique['xp']).round(), itemIds: ids(unique['itemIds'])),
      ],
    );
  }

  /// The tier whose `itemIds` holds [itemId]; else the item's own
  /// `source.ref` / `source.tier`. Null when the content does not know it.
  static LockerAchievementReward? find(ProgressionContent? content, ItemDef item) {
    final defs = content?.raw['defs'];
    final list = defs is Map ? defs['achievement'] : null;
    if (list is! List) return null;
    double n(dynamic v) => v is num ? v.toDouble() : 0;
    bool gives(dynamic v) => v is List && v.contains(item.id);
    final all = list.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).where((m) => m['id'] is String).toList();
    for (final def in all) {
      final tiers = def['tiers'];
      if (tiers is List) {
        for (final t in tiers.whereType<Map>()) {
          if (gives(t['itemIds']) && t['tier'] is String) {
            return LockerAchievementReward(def: def, tier: t['tier'] as String, threshold: n(t['threshold']));
          }
        }
      }
      final unique = def['unique'];
      if (unique is Map && gives(unique['itemIds'])) {
        return LockerAchievementReward(def: def, tier: 'unique', threshold: n(unique['threshold']));
      }
    }
    final ref = item.source.ref;
    final def = all.where((d) => d['id'] == ref).firstOrNull;
    if (def == null) return null;
    final tiers = def['tiers'];
    if (tiers is List) {
      final t = tiers.whereType<Map>().where((t) => t['tier'] == (item.source.tier ?? 'gold')).firstOrNull;
      if (t == null) return null;
      return LockerAchievementReward(def: def, tier: t['tier'] as String, threshold: n(t['threshold']));
    }
    final unique = def['unique'];
    return LockerAchievementReward(def: def, tier: 'unique', threshold: unique is Map ? n(unique['threshold']) : 0);
  }
}

/// Where a « how to get it » button leads.
enum LockerHowAction { levels, premium, achievement, league, quests, journey }

enum LockerHowIcon { level, premium, achievement, league, season, event, onboarding, other }

/// One « Comment l'obtenir » block.
class LockerHow {
  final LockerHowIcon icon;
  final String title;
  final String? subtitle;

  /// 0..1; null = not measurable (no bar).
  final double? progress;
  final String? progressFrom;
  final String? progressTo;
  final LockerHowAction? action;
  final String? actionLabel;
  final String? note;

  const LockerHow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.progress,
    this.progressFrom,
    this.progressTo,
    this.action,
    this.actionLabel,
    this.note,
  });

  /// « Passer Premium » is the one gold-outlined button.
  bool get goldAction => action == LockerHowAction.premium;
}

/// What the app knows about me when the sheet opens; every field may be
/// missing.
class LockerHowData {
  final int? level;
  final int? xpTotal;
  final bool isPremium;
  final XpCurve curve;
  final LockerAchievementReward? reward;
  final Achievement? achievement;

  /// League id → name, from the content (`defs.league`, `type: tier`).
  final Map<String, LocalizedText> leagueNames;
  final LocalizedText? currentLeague;

  /// The season the item belongs to, and the running season's number.
  final Season? season;
  final int? currentSeasonNumber;

  /// The item's event in the content (`events`).
  final Map<String, dynamic>? event;
  final OnboardingStatus? onboarding;
  final DateTime now;

  LockerHowData({
    this.level,
    this.xpTotal,
    this.isPremium = false,
    this.curve = const XpCurve(),
    this.reward,
    this.achievement,
    this.leagueNames = const {},
    this.currentLeague,
    this.season,
    this.currentSeasonNumber,
    this.event,
    this.onboarding,
    DateTime? now,
  }) : now = now ?? DateTime.now();
}

/// League id → name, from the content.
Map<String, LocalizedText> lockerLeagueNames(ProgressionContent? content) {
  final defs = content?.raw['defs'];
  final list = defs is Map ? defs['league'] : null;
  if (list is! List) return const {};
  return {
    for (final m in list.whereType<Map>())
      if (m['type'] == 'tier' && m['id'] is String) m['id'] as String: LocalizedText.fromJson(m['name']),
  };
}

/// The content's event [id] (startsAt / endsAt / name), or null.
Map<String, dynamic>? lockerEvent(ProgressionContent? content, String? id) {
  final list = content?.raw['events'];
  if (id == null || list is! List) return null;
  for (final m in list.whereType<Map>()) {
    if (m['id'] == id) return Map<String, dynamic>.from(m);
  }
  return null;
}

/// The 7 cases of CasObtenir, plus a plain fallback for a source the app
/// does not know (the server's label, no button).
LockerHow resolveLockerHow(BuildContext context, ItemDef item, LockerHowData d) {
  final l10n = AppLocalizations.of(context);
  final locale = Localizations.localeOf(context).toString();
  final s = item.source;
  final fallback = LockerHow(icon: LockerHowIcon.other, title: _capitalized(s.label.resolve(context)));

  // The bar runs from the start of my current level to the target level:
  // (xpTotal − xpForLevel(cur)) / (xpForLevel(n) − xpForLevel(cur)).
  double? levelProgress(int n) {
    final cur = d.level;
    final xp = d.xpTotal;
    if (cur == null || xp == null) return null;
    if (cur >= n) return 1.0;
    final from = d.curve.xpForLevel(cur);
    final span = d.curve.xpForLevel(n) - from;
    return span <= 0 ? 1.0 : ((xp - from) / span).clamp(0.0, 1.0);
  }

  LockerHow levelHow(int n, {LockerHowIcon icon = LockerHowIcon.level}) {
    final cur = d.level;
    return LockerHow(
      icon: icon,
      title: l10n.lockerSHowLevelTitle(n),
      subtitle: cur == null ? null : (cur >= n ? l10n.lockerSHowLevelReached(cur) : l10n.lockerSHowLevelSub(cur, n - cur)),
      progress: levelProgress(n),
      progressFrom: cur == null ? null : l10n.xpLevelShort(cur),
      progressTo: l10n.xpLevelShort(n),
      action: LockerHowAction.levels,
      actionLabel: l10n.lockerSSeeLevels,
    );
  }

  switch (s.kind) {
    case 'level':
      return s.level == null ? fallback : levelHow(s.level!);

    case 'premium_level':
      final n = s.level;
      if (n == null) return fallback;
      if (d.isPremium) return levelHow(n);
      final cur = d.level;
      return LockerHow(
        icon: LockerHowIcon.premium,
        title: l10n.lockerSHowPremiumTitle(n),
        subtitle: cur == null ? null : (cur >= n ? l10n.lockerSHowPremiumNow : l10n.lockerSHowPremiumSub(cur)),
        action: LockerHowAction.premium,
        actionLabel: l10n.lockerSGoPremium,
      );

    case 'achievement':
      final r = d.reward;
      if (r == null) return fallback;
      final name = r.name.resolve(context);
      final a = d.achievement;
      final step = a?.steps.where((x) => x.tier == r.tier).firstOrNull;
      final threshold = step?.threshold ?? r.threshold;
      final measurable = a != null && r.tier != 'unique' && a.format != 'ordinal' && !a.lowerIsBetter && threshold > 0;
      final value = a == null ? 0.0 : (a.aggregate == 'streak' ? math.max(a.value, a.best ?? 0) : a.value);
      final description = r.description.resolve(context);
      return LockerHow(
        icon: LockerHowIcon.achievement,
        title: r.tier == 'unique' ? name : l10n.lockerSHowAchievementTier(name, achievementTierName(l10n, r.tier)),
        subtitle: description.isEmpty ? null : description,
        progress: measurable ? (value / threshold).clamp(0.0, 1.0) : null,
        progressFrom: measurable ? formatAchievementValue(context, value, a.format) : null,
        progressTo: measurable ? formatAchievementValue(context, threshold, a.format) : null,
        action: LockerHowAction.achievement,
        actionLabel: l10n.lockerSSeeAchievement,
      );

    case 'league':
      final target = d.leagueNames[s.ref];
      final current = d.currentLeague;
      return LockerHow(
        icon: LockerHowIcon.league,
        title: target != null
            ? l10n.lockerSHowLeagueTitle(target.resolve(context))
            : (s.ref == 'first-promotion' ? l10n.lockerSHowLeagueFirstPromotion : fallback.title),
        subtitle: current == null ? null : l10n.lockerSHowLeagueSub(current.resolve(context)),
        action: LockerHowAction.league,
        actionLabel: l10n.lockerSSeeLeague,
      );

    case 'season':
      final n = int.tryParse(s.ref ?? '');
      if (n == null) return fallback;
      final season = d.season;
      final over = (season?.isClosed ?? false) || (d.currentSeasonNumber != null && d.currentSeasonNumber! > n);
      final end = season != null && season.isActive ? season.endAt : null;
      return LockerHow(
        icon: LockerHowIcon.season,
        title: l10n.lockerSHowSeasonTitle(n),
        subtitle: over
            ? l10n.lockerSHowSeasonOver
            : (end != null ? l10n.lockerSHowSeasonSubDate(DateFormat('d MMM', locale).format(end.toLocal())) : l10n.lockerSHowSeasonSub),
      );

    case 'event':
      final ev = d.event;
      final start = ev == null ? null : DateTime.tryParse('${ev['startsAt']}')?.toLocal();
      final end = ev == null ? null : DateTime.tryParse('${ev['endsAt']}')?.toLocal();
      if (start == null || end == null) return fallback;
      // endsAt is the first instant after the event: the last day is the one before.
      final lastDay = end.subtract(const Duration(minutes: 1));
      final day = DateFormat('d MMM', locale);
      final running = !d.now.isBefore(start) && d.now.isBefore(end);
      final month = DateFormat('MMMM', locale).format(start);
      return LockerHow(
        icon: LockerHowIcon.event,
        title: l10n.lockerSHowEventTitle(locale.startsWith('fr') ? month : _capitalized(month)),
        subtitle: l10n.lockerSHowEventDates(day.format(start), day.format(lastDay)),
        action: running ? LockerHowAction.quests : null,
        actionLabel: running ? l10n.lockerSSeeQuest : null,
        note: running ? null : (d.now.isBefore(start) ? l10n.lockerSEventNotStarted : l10n.lockerSEventOver),
      );

    case 'onboarding':
      final status = d.onboarding;
      final journey = status != null && status.status == 'active';
      return LockerHow(
        icon: LockerHowIcon.onboarding,
        title: l10n.lockerSHowOnboardingTitle,
        subtitle: status == null
            ? null
            : (journey
                  ? l10n.lockerSHowOnboardingDay(status.day.clamp(1, status.journeyDays), status.journeyDays)
                  : l10n.lockerSHowOnboardingClosed),
        action: journey ? LockerHowAction.journey : null,
        actionLabel: journey ? l10n.lockerSSeeJourney : null,
      );

    default:
      return fallback;
  }
}

/// What the sheet asks the locker to do once closed.
class LockerSheetOutcome {
  final bool tryOn;
  final LockerHowAction? action;
  final Achievement? achievement;
  const LockerSheetOutcome.tryOn() : tryOn = true, action = null, achievement = null;
  const LockerSheetOutcome.go(this.action, {this.achievement}) : tryOn = false;
}

/// The sheet of a locked item (CasA2): its visual in colour, its name, the
/// « {Type} à débloquer » pill, « Comment l'obtenir », and « Essayer sur ma
/// carte » when the item shows on the card.
class LockerUnlockSheet extends StatefulWidget {
  final ItemDef item;
  final String monogram;
  final bool isPremium;
  final bool canTry;

  /// Test seam: my progress on an achievement (default: GET /achievements/:id).
  @visibleForTesting
  static Future<Achievement?> Function(String id)? debugAchievementLoader;

  const LockerUnlockSheet({super.key, required this.item, required this.monogram, required this.isPremium, required this.canTry});

  static Future<LockerSheetOutcome?> show(
    BuildContext context, {
    required ItemDef item,
    required String monogram,
    required bool isPremium,
    required bool canTry,
  }) => showModalBottomSheet<LockerSheetOutcome>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppTheme.surface,
    barrierColor: const Color(0x9E020617),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
    builder: (_) => LockerUnlockSheet(item: item, monogram: monogram, isPremium: isPremium, canTry: canTry),
  );

  @override
  State<LockerUnlockSheet> createState() => _LockerUnlockSheetState();
}

class _LockerUnlockSheetState extends State<LockerUnlockSheet> {
  Achievement? _achievement;

  @override
  void initState() {
    super.initState();
    final kind = widget.item.source.kind;
    if (kind == 'achievement') {
      final reward = LockerAchievementReward.find(readProgressionContent(context), widget.item);
      final id = reward?.id ?? widget.item.source.ref;
      if (id != null) unawaited(_loadAchievement(id));
    } else if (kind == 'league' && LeagueStore.instance.visible == null) {
      unawaited(LeagueStore.instance.refresh());
    } else if (kind == 'onboarding') {
      final onboarding = maybeReadOnboarding(context);
      if (onboarding != null && onboarding.status == null) unawaited(onboarding.refresh());
    }
  }

  Future<void> _loadAchievement(String id) async {
    try {
      final loader = LockerUnlockSheet.debugAchievementLoader;
      final a = loader != null ? await loader(id) : (await AchievementsService.detail(id))?.achievement;
      if (mounted && a != null) setState(() => _achievement = a);
    } catch (e) {
      // Offline: the sentence without the bar.
      debugPrint('LockerUnlockSheet: $e');
    }
  }

  SeasonProvider? _seasons(BuildContext context) {
    try {
      return context.watch<SeasonProvider>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  LockerHowData _data(BuildContext context, LeagueSnapshot? league) {
    final p = maybeWatchProgression(context);
    final content = p?.content;
    final summary = p?.summary;
    final item = widget.item;
    Season? season;
    int? currentNumber;
    if (item.source.kind == 'season') {
      final provider = _seasons(context);
      final n = int.tryParse(item.source.ref ?? '');
      final current = provider?.current;
      currentNumber = current?.season.number;
      season = [?current?.season, ?current?.next, ...?provider?.seasons].where((x) => x.number == n).firstOrNull;
    }
    final onboarding = item.source.kind == 'onboarding' ? maybeWatchOnboarding(context)?.status : null;
    return LockerHowData(
      level: summary?.level,
      xpTotal: summary?.xpTotal,
      isPremium: widget.isPremium,
      curve: content?.curve ?? const XpCurve(),
      reward: LockerAchievementReward.find(content, item),
      achievement: _achievement,
      leagueNames: lockerLeagueNames(content),
      currentLeague: league?.league?.name,
      season: season,
      currentSeasonNumber: currentNumber,
      event: lockerEvent(content, item.source.ref),
      onboarding: onboarding,
    );
  }

  String _lockedPill(AppLocalizations l10n) => switch (widget.item.type) {
    ItemType.frame => l10n.lockerSLockedFrame,
    ItemType.background => l10n.lockerSLockedBackground,
    ItemType.title => l10n.lockerSLockedTitle,
    ItemType.flight => l10n.lockerSLockedFlight,
    _ => l10n.lockerSLockedAvatar,
  };

  void _go(LockerHow how, LockerHowData data) {
    final action = how.action;
    if (action == null) return;
    Navigator.of(context).pop(
      LockerSheetOutcome.go(
        action,
        achievement: action == LockerHowAction.achievement ? (data.achievement ?? data.reward?.asAchievement) : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final item = widget.item;
    return ListenableBuilder(
      listenable: LeagueStore.instance,
      builder: (context, _) {
        final data = _data(context, LeagueStore.instance.visible);
        final how = resolveLockerHow(context, item, data);
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 10, 20, lockerSheetBottomPadding(context)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: const Color(0xFF475569), borderRadius: BorderRadius.circular(4)),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  ProgressionItemVisual(item: item, monogramText: widget.monogram, size: 92),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.name.resolve(context),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 23,
                            height: 1.1,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.46,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          height: 24,
                          padding: const EdgeInsets.symmetric(horizontal: 9),
                          decoration: BoxDecoration(color: AppTheme.background, borderRadius: BorderRadius.circular(999)),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.lock_outline_rounded, size: 12, color: AppTheme.textSecondary),
                              const SizedBox(width: 5),
                              Flexible(
                                child: Text(
                                  _lockedPill(l10n),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppTheme.textSecondary),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              LockerHowBox(how: how),
              if (how.action != null) ...[
                const SizedBox(height: 12),
                LockerSheetButton(label: how.actionLabel ?? '', gold: how.goldAction, onTap: () => _go(how, data)),
              ],
              if (widget.canTry) ...[
                const SizedBox(height: 16),
                LockerSheetButton(
                  label: l10n.lockerSTryOnCard,
                  icon: Icons.visibility_outlined,
                  outlined: true,
                  onTap: () => Navigator.of(context).pop(const LockerSheetOutcome.tryOn()),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// 30 pt under a sheet's last button (the mockups), more above a home bar.
double lockerSheetBottomPadding(BuildContext context) => math.max(30, MediaQuery.paddingOf(context).bottom + 8);

/// The « Comment l'obtenir » block: icon, sentence, where I stand, the bar.
class LockerHowBox extends StatelessWidget {
  final LockerHow how;
  const LockerHowBox({super.key, required this.how});

  Widget _icon() {
    const c = AppTheme.playerBlueBright;
    return switch (how.icon) {
      LockerHowIcon.level => const Icon(Icons.hexagon_outlined, size: 20, color: c),
      LockerHowIcon.premium => const PremiumCrown(size: 20),
      LockerHowIcon.achievement => const Icon(Icons.track_changes_rounded, size: 20, color: c),
      LockerHowIcon.league => const Icon(Icons.leaderboard_outlined, size: 20, color: c),
      LockerHowIcon.season => const Icon(Icons.calendar_today_outlined, size: 19, color: c),
      LockerHowIcon.event => const Icon(Icons.ac_unit_rounded, size: 20, color: c),
      LockerHowIcon.onboarding => const Icon(Icons.auto_awesome_outlined, size: 20, color: c),
      LockerHowIcon.other => const Icon(Icons.lock_outline_rounded, size: 20, color: c),
    };
  }

  @override
  Widget build(BuildContext context) {
    final progress = how.progress;
    const label = TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppTheme.textSecondary);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppTheme.background, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(12)),
                child: _icon(),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      how.title,
                      style: const TextStyle(fontSize: 16, height: 1.25, fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
                    ),
                    if (how.subtitle != null) ...[
                      const SizedBox(height: 1),
                      Text(how.subtitle!, style: const TextStyle(fontSize: 13, height: 1.3, color: AppTheme.textSecondary)),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (progress != null) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: SizedBox(
                height: 8,
                child: Stack(
                  children: [
                    const Positioned.fill(child: ColoredBox(color: AppTheme.surfaceLight)),
                    FractionallySizedBox(
                      widthFactor: progress,
                      child: const ColoredBox(color: AppTheme.primaryLight, child: SizedBox.expand()),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 5),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(how.progressFrom ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: label),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(how.progressTo ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: label),
                ),
              ],
            ),
          ],
          if (how.note != null) ...[
            const SizedBox(height: 8),
            Text(how.note!, style: const TextStyle(fontSize: 12, color: AppTheme.textTertiary)),
          ],
        ],
      ),
    );
  }
}

/// The sheet's buttons: filled blue (50 pt), gold outline (« Passer
/// Premium »), or the slate outline of « Essayer sur ma carte » (46 pt).
class LockerSheetButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool gold;
  final bool outlined;
  final IconData? icon;
  const LockerSheetButton({super.key, required this.label, this.onTap, this.gold = false, this.outlined = false, this.icon});

  @override
  Widget build(BuildContext context) {
    final Color fg = gold ? const Color(0xFFFDE68A) : (outlined ? AppTheme.textPrimary : AppTheme.background);
    final side = gold
        ? const BorderSide(color: AppTheme.accent, width: 1.5)
        : (outlined ? const BorderSide(color: AppTheme.surfaceLight, width: 1.5) : BorderSide.none);
    return Material(
      color: gold || outlined ? Colors.transparent : AppTheme.primaryLight,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: side),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: outlined ? 46 : 50,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[Icon(icon, size: 17, color: fg), const SizedBox(width: 8)],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: outlined ? 15 : 16, fontWeight: outlined ? FontWeight.w700 : FontWeight.w800, color: fg),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
