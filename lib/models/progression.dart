// Progression & rewards models — docs/progression/CONTRACT.md §8, §9, §11.
//
// Every fromJson is defensive: a missing or mistyped field falls back to a
// default, and an element of an unknown type is dropped (an old app must hide
// new content cleanly, never crash).
import 'package:flutter/widgets.dart';

int _int(dynamic v, [int fallback = 0]) =>
    v is int ? v : (v is num ? v.toInt() : (int.tryParse('$v') ?? fallback));

String? _str(dynamic v) => v is String ? v : null;

DateTime? _date(dynamic v) => v is String ? DateTime.tryParse(v) : null;

List<String> _strings(dynamic v) =>
    v is List ? v.whereType<String>().toList() : const <String>[];

Map<String, dynamic> _map(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : const <String, dynamic>{};

/// `{fr, en}` text from the server.
class LocalizedText {
  final String fr;
  final String en;
  const LocalizedText({required this.fr, required this.en});

  static const empty = LocalizedText(fr: '', en: '');

  factory LocalizedText.fromJson(dynamic json) {
    final m = _map(json);
    final fr = _str(m['fr']) ?? _str(m['en']) ?? '';
    final en = _str(m['en']) ?? fr;
    return LocalizedText(fr: fr, en: en);
  }

  String of(Locale locale) => locale.languageCode == 'fr' ? fr : en;
  String resolve(BuildContext context) => of(Localizations.localeOf(context));
}

enum ItemType { avatar, frame, background, title, flight, badge, unknown }

ItemType itemTypeFrom(String? raw) => switch (raw) {
      'avatar' => ItemType.avatar,
      'frame' => ItemType.frame,
      'background' => ItemType.background,
      'title' => ItemType.title,
      'flight' => ItemType.flight,
      'badge' => ItemType.badge,
      _ => ItemType.unknown,
    };

class ItemAsset {
  final String url;
  final String format; // svg | png | webp
  final String hash;
  const ItemAsset({required this.url, required this.format, required this.hash});

  static ItemAsset? fromJson(dynamic json) {
    final m = _map(json);
    final url = _str(m['url']);
    final format = _str(m['format']);
    if (url == null || format == null) return null;
    if (!const {'svg', 'png', 'webp'}.contains(format)) return null;
    return ItemAsset(url: url, format: format, hash: _str(m['hash']) ?? '');
  }

  bool get isSvg => format == 'svg';
}

class ItemSourceInfo {
  final String kind;
  final int? level;
  final String? ref;
  final String? tier;
  final LocalizedText label;
  const ItemSourceInfo({required this.kind, this.level, this.ref, this.tier, required this.label});

  factory ItemSourceInfo.fromJson(dynamic json) {
    final m = _map(json);
    return ItemSourceInfo(
      kind: _str(m['kind']) ?? 'unknown',
      level: m['level'] is num ? _int(m['level']) : null,
      ref: _str(m['ref']),
      tier: _str(m['tier']),
      label: LocalizedText.fromJson(m['label']),
    );
  }
}

class ItemDef {
  final String id;
  final ItemType type;
  final LocalizedText name;
  final ItemSourceInfo source;
  final bool premium;
  final Map<String, dynamic> render;
  final ItemAsset? asset;
  final int sortOrder;

  const ItemDef({
    required this.id,
    required this.type,
    required this.name,
    required this.source,
    this.premium = false,
    this.render = const {},
    this.asset,
    this.sortOrder = 0,
  });

  /// Null for an unusable entry (no id, unknown type): the caller hides it.
  static ItemDef? fromJson(dynamic json) {
    final m = _map(json);
    final id = _str(m['id']);
    final type = itemTypeFrom(_str(m['type']));
    if (id == null || id.isEmpty || type == ItemType.unknown) return null;
    return ItemDef(
      id: id,
      type: type,
      name: LocalizedText.fromJson(m['name']),
      source: ItemSourceInfo.fromJson(m['source']),
      premium: m['premium'] == true,
      render: _map(m['render']),
      asset: ItemAsset.fromJson(m['asset']),
      sortOrder: _int(m['sortOrder']),
    );
  }

  String? get renderKind => _str(render['kind']);
  String? get metal => _str(render['metal']);
  bool get isMonogram => type == ItemType.avatar && renderKind == 'monogram';

  List<Color> get renderColors {
    final raw = render['colors'];
    if (raw is! List) return const [];
    return raw.whereType<String>().map(parseHexColor).whereType<Color>().toList();
  }
}

Color? parseHexColor(String hex) {
  final h = hex.replaceFirst('#', '');
  if (h.length != 6 && h.length != 8) return null;
  final v = int.tryParse(h.length == 6 ? 'FF$h' : h, radix: 16);
  return v == null ? null : Color(v);
}

class LevelRewardDef {
  final int level;
  final List<String> itemIds;
  final List<String> premiumItemIds;
  const LevelRewardDef({required this.level, this.itemIds = const [], this.premiumItemIds = const []});

  factory LevelRewardDef.fromJson(dynamic json) {
    final m = _map(json);
    return LevelRewardDef(
      level: _int(m['level'], 1),
      itemIds: _strings(m['itemIds']),
      premiumItemIds: _strings(m['premiumItemIds']),
    );
  }
}

class XpCurve {
  final int base;
  final int perLevel;

  /// Past this level every level costs base + perLevel × capLevel (3 200 XP
  /// after level 50); null = the cost keeps growing (a server without the key).
  final int? capLevel;
  const XpCurve({this.base = 200, this.perLevel = 60, this.capLevel = 50});

  factory XpCurve.fromJson(dynamic json) {
    final m = _map(json);
    if (m.isEmpty) return const XpCurve();
    final cap = m['capLevel'];
    return XpCurve(
      base: _int(m['base'], 200),
      perLevel: _int(m['perLevel'], 60),
      capLevel: cap is num && cap >= 1 ? cap.toInt() : null,
    );
  }

  /// XP to go from [level] to level + 1: base + perLevel × min(level, cap)
  /// (the same formula as the server's engine/xp-curve.ts).
  int xpToNext(int level) {
    var n = level < 1 ? 1 : level;
    final cap = capLevel;
    if (cap != null && n > cap) n = cap;
    return base + perLevel * n;
  }

  /// Total XP needed to reach [level] (level 1 = 0).
  int xpForLevel(int level) {
    final n = (level < 1 ? 1 : level) - 1;
    final cap = capLevel;
    if (cap == null || n <= cap) return base * n + (perLevel * n * (n + 1)) ~/ 2;
    return base * n + (perLevel * cap * (cap + 1)) ~/ 2 + perLevel * cap * (n - cap);
  }
}

/// Prestige (levels.json `prestige`, tour 5): past [fromLevel], one star on
/// the [frameId] frame (Légende) every [everyLevels] levels.
class PrestigeDef {
  final String frameId;
  final int fromLevel;
  final int everyLevels;
  const PrestigeDef({required this.frameId, this.fromLevel = 50, this.everyLevels = 10});

  /// Null when absent or malformed: no star anywhere (older servers).
  static PrestigeDef? fromJson(dynamic json) {
    final m = _map(json);
    final frameId = _str(m['frameId']);
    final from = _int(m['fromLevel']);
    final every = _int(m['everyLevels']);
    if (frameId == null || from < 1 || every < 1) return null;
    return PrestigeDef(frameId: frameId, fromLevel: from, everyLevels: every);
  }

  /// floor((level − fromLevel) / everyLevels), never below 0.
  int starsFor(int level) => level <= fromLevel ? 0 : (level - fromLevel) ~/ everyLevels;

  /// Stars on [frameId] worn at [level]: only the prestige frame carries them.
  int starsOn(String? frameId, int level) => frameId == this.frameId ? starsFor(level) : 0;

  /// The level a new star is earned at (60, 70…).
  bool isStarLevel(int level) => level > fromLevel && (level - fromLevel) % everyLevels == 0;

  /// The level star number [n] (1-based) is earned at.
  int levelOfStar(int n) => fromLevel + n * everyLevels;

  /// The next level that earns a star, after [level].
  int nextStarLevel(int level) => levelOfStar(starsFor(level) + 1);
}

/// The XP of each way of playing (GET /progression/content → `xp`, CONTRACT
/// §14.9): the server's own constants, printed by the home. Null on a server
/// without the block, and a missing key is null too: the label is then left
/// out, never guessed.
class XpRules {
  final int? ranked;
  final int? rankedWin;
  final int? friendly;
  final int? training;
  final int? ghost;
  final int? challenge;

  const XpRules({this.ranked, this.rankedWin, this.friendly, this.training, this.ghost, this.challenge});

  static XpRules? fromJson(dynamic json) {
    if (json is! Map) return null;
    int? v(dynamic x) => x is num && x >= 0 ? x.toInt() : null;
    return XpRules(
      ranked: v(json['ranked']),
      rankedWin: v(json['rankedWin']),
      friendly: v(json['friendly']),
      training: v(json['training']),
      ghost: v(json['ghost']),
      challenge: v(json['challenge']),
    );
  }
}

/// The content catalog (GET /progression/content), cached on disk.
class ProgressionContent {
  final String version;
  final XpCurve curve;

  /// Stars on the Légende frame past level 50 (null = none).
  final PrestigeDef? prestige;

  /// XP per way of playing (null on an older server).
  final XpRules? xp;
  final Map<String, List<Color>> metals;
  final Map<String, ItemDef> items;
  final Map<int, LevelRewardDef> levels;
  final Map<String, dynamic> raw;

  const ProgressionContent({
    required this.version,
    this.curve = const XpCurve(),
    this.prestige,
    this.xp,
    this.metals = const {},
    this.items = const {},
    this.levels = const {},
    this.raw = const {},
  });

  factory ProgressionContent.fromJson(Map<String, dynamic> json) {
    final metals = <String, List<Color>>{};
    _map(json['metals']).forEach((k, v) {
      final colors = (v is List ? v : const [])
          .whereType<String>()
          .map(parseHexColor)
          .whereType<Color>()
          .toList();
      if (colors.length == 3) metals[k] = colors;
    });
    final items = <String, ItemDef>{};
    for (final raw in (json['items'] is List ? json['items'] as List : const [])) {
      final item = ItemDef.fromJson(raw);
      if (item != null) items[item.id] = item;
    }
    final levels = <int, LevelRewardDef>{};
    for (final raw in (json['levels'] is List ? json['levels'] as List : const [])) {
      final l = LevelRewardDef.fromJson(raw);
      levels[l.level] = l;
    }
    return ProgressionContent(
      version: _str(json['version']) ?? '',
      curve: XpCurve.fromJson(json['curve']),
      prestige: PrestigeDef.fromJson(json['prestige']),
      xp: XpRules.fromJson(json['xp']),
      metals: metals,
      items: items,
      levels: levels,
      raw: json,
    );
  }

  ItemDef? item(String? id) => id == null ? null : items[id];

  /// Prestige stars of a player wearing [frameId] at [level] (0 when the
  /// frame is not the prestige one).
  int prestigeStars(String? frameId, int level) => prestige?.starsOn(frameId, level) ?? 0;

  /// The XP the weekly league pays for [position] (defs.league → settings →
  /// xpByPosition, the same bands as the server's xpForPosition); null when
  /// the content has no league settings.
  int? leagueXpFor(int position) {
    final defs = _map(raw['defs']);
    final league = defs['league'];
    if (league is! List) return null;
    final settings = league.map(_map).firstWhere((d) => d['type'] == 'settings', orElse: () => const {});
    final bands = settings['xpByPosition'];
    if (bands is! List) return null;
    final sorted = bands.map(_map).where((b) => _int(b['to']) > 0).toList()
      ..sort((a, b) => _int(a['to']).compareTo(_int(b['to'])));
    if (position < 1) return 0;
    for (final b in sorted) {
      if (position <= _int(b['to'])) return _int(b['xp']);
    }
    return 0;
  }

  List<ItemDef> itemsOfType(ItemType type) =>
      items.values.where((i) => i.type == type).toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
}

class PublicBadge {
  final String id;
  final String badgeId;
  final String? tier;
  final String? date;
  const PublicBadge({required this.id, required this.badgeId, this.tier, this.date});

  static PublicBadge? fromJson(dynamic json) {
    final m = _map(json);
    final id = _str(m['id']);
    final badgeId = _str(m['badgeId']);
    if (id == null || badgeId == null) return null;
    return PublicBadge(id: id, badgeId: badgeId, tier: _str(m['tier']), date: _str(m['date']));
  }
}

/// Compact cosmetics on every player DTO (CONTRACT.md §9). Null fields mean
/// "default look": rank badge, no frame, plain background, no title.
class PublicCosmetics {
  final int level;
  final String? avatar;
  final String monogram;
  final String? frame;
  final String? background;
  final String? title;
  final String? flight;
  final List<PublicBadge> badges;

  const PublicCosmetics({
    this.level = 1,
    this.avatar,
    this.monogram = '',
    this.frame,
    this.background,
    this.title,
    this.flight,
    this.badges = const [],
  });

  static PublicCosmetics? fromJson(dynamic json) {
    if (json is! Map) return null;
    final m = Map<String, dynamic>.from(json);
    return PublicCosmetics(
      level: _int(m['level'], 1).clamp(1, 1 << 30),
      avatar: _str(m['avatar']),
      monogram: _str(m['monogram']) ?? '',
      frame: _str(m['frame']),
      background: _str(m['background']),
      title: _str(m['title']),
      flight: _str(m['flight']),
      badges: (m['badges'] is List ? m['badges'] as List : const [])
          .map(PublicBadge.fromJson)
          .whereType<PublicBadge>()
          .toList(),
    );
  }
}

class MonogramChoice {
  final String kind; // initials | double
  final String value;
  const MonogramChoice({required this.kind, required this.value});

  static MonogramChoice? fromJson(dynamic json) {
    final m = _map(json);
    final kind = _str(m['kind']);
    final value = _str(m['value']);
    if (kind == null || value == null) return null;
    return MonogramChoice(kind: kind, value: value);
  }

  Map<String, dynamic> toJson() => {'kind': kind, 'value': value};
}

class Equipment {
  final String? avatar;
  final String? frame;
  final String? background;
  final String? title;
  final String? flight;
  final List<String> badges;
  final MonogramChoice? monogram;

  const Equipment({
    this.avatar,
    this.frame,
    this.background,
    this.title,
    this.flight,
    this.badges = const [],
    this.monogram,
  });

  factory Equipment.fromJson(dynamic json) {
    final m = _map(json);
    return Equipment(
      avatar: _str(m['avatar']),
      frame: _str(m['frame']),
      background: _str(m['background']),
      title: _str(m['title']),
      flight: _str(m['flight']),
      badges: _strings(m['badges']),
      monogram: MonogramChoice.fromJson(m['monogram']),
    );
  }

  String? slot(ItemType type) => switch (type) {
        ItemType.avatar => avatar,
        ItemType.frame => frame,
        ItemType.background => background,
        ItemType.title => title,
        ItemType.flight => flight,
        _ => null,
      };
}

class ProgressionSummary {
  final int level;
  final int xpTotal;
  final int xpIntoLevel;
  final int xpToNext;
  final int levelSeen;
  final bool isPremium;
  final LevelRewardDef nextRewards;
  final int itemsOwned;
  final int itemsTotal;
  final Equipment equipment;
  final PublicCosmetics cosmetics;

  const ProgressionSummary({
    this.level = 1,
    this.xpTotal = 0,
    this.xpIntoLevel = 0,
    this.xpToNext = 260,
    this.levelSeen = 1,
    this.isPremium = false,
    this.nextRewards = const LevelRewardDef(level: 2),
    this.itemsOwned = 0,
    this.itemsTotal = 0,
    this.equipment = const Equipment(),
    this.cosmetics = const PublicCosmetics(),
  });

  factory ProgressionSummary.fromJson(dynamic json) {
    final m = _map(json);
    return ProgressionSummary(
      level: _int(m['level'], 1),
      xpTotal: _int(m['xpTotal']),
      xpIntoLevel: _int(m['xpIntoLevel']),
      xpToNext: _int(m['xpToNext'], 260),
      levelSeen: _int(m['levelSeen'], 1),
      isPremium: m['isPremium'] == true,
      nextRewards: LevelRewardDef.fromJson(m['nextRewards']),
      itemsOwned: _int(m['itemsOwned']),
      itemsTotal: _int(m['itemsTotal']),
      equipment: Equipment.fromJson(m['equipment']),
      cosmetics: PublicCosmetics.fromJson(m['cosmetics']) ?? const PublicCosmetics(),
    );
  }

  double get progress => xpToNext <= 0 ? 0 : (xpIntoLevel / xpToNext).clamp(0.0, 1.0);
}

class UserQuest {
  final String id;
  final String questId;
  final String period;
  final String group;
  final LocalizedText text;
  final int progress;
  final int threshold;
  final int xp;
  final String status;
  final String? rewardItemId;

  const UserQuest({
    required this.id,
    required this.questId,
    required this.period,
    this.group = '',
    required this.text,
    this.progress = 0,
    this.threshold = 1,
    this.xp = 0,
    this.status = 'active',
    this.rewardItemId,
  });

  static UserQuest? fromJson(dynamic json) {
    final m = _map(json);
    final id = _str(m['id']);
    if (id == null) return null;
    return UserQuest(
      id: id,
      questId: _str(m['questId']) ?? '',
      period: _str(m['period']) ?? 'daily',
      group: _str(m['group']) ?? '',
      text: LocalizedText.fromJson(m['text']),
      progress: _int(m['progress']),
      threshold: _int(m['threshold'], 1),
      xp: _int(m['xp']),
      status: _str(m['status']) ?? 'active',
      rewardItemId: _str(m['rewardItemId']),
    );
  }

  bool get isDone => status == 'completed';
  double get fraction => threshold <= 0 ? 0 : (progress / threshold).clamp(0.0, 1.0);
}

List<UserQuest> _quests(dynamic v) =>
    (v is List ? v : const []).map(UserQuest.fromJson).whereType<UserQuest>().toList();

class QuestSection {
  final String periodKey;
  final DateTime? endsAt;
  final bool rerollAvailable;
  final List<UserQuest> quests;
  const QuestSection({this.periodKey = '', this.endsAt, this.rerollAvailable = false, this.quests = const []});

  factory QuestSection.fromJson(dynamic json) {
    final m = _map(json);
    return QuestSection(
      periodKey: _str(m['periodKey']) ?? '',
      endsAt: _date(m['endsAt']),
      rerollAvailable: m['rerollAvailable'] == true,
      quests: _quests(m['quests']),
    );
  }

  int get done => quests.where((q) => q.isDone).length;
  int get xpLeft => quests.where((q) => !q.isDone).fold(0, (s, q) => s + q.xp);
}

/// The quests of one running event (GET /progression/quests → `events`):
/// the server only sends the events on right now.
class EventQuests {
  final String eventId;
  final LocalizedText name;
  final DateTime? endsAt;
  final List<UserQuest> quests;
  const EventQuests({required this.eventId, this.name = LocalizedText.empty, this.endsAt, this.quests = const []});

  /// Null without an id (an entry the app cannot place).
  static EventQuests? fromJson(dynamic json) {
    final m = _map(json);
    final id = _str(m['eventId']);
    if (id == null) return null;
    return EventQuests(
      eventId: id,
      name: LocalizedText.fromJson(m['name']),
      endsAt: _date(m['endsAt']),
      quests: _quests(m['quests']),
    );
  }
}

class QuestsSnapshot {
  final QuestSection daily;
  final QuestSection weekly;
  final QuestSection discovery;

  /// Event quests, one entry per running event (empty on an older server).
  final List<EventQuests> events;
  const QuestsSnapshot({
    this.daily = const QuestSection(),
    this.weekly = const QuestSection(),
    this.discovery = const QuestSection(),
    this.events = const [],
  });

  factory QuestsSnapshot.fromJson(dynamic json) {
    final m = _map(json);
    return QuestsSnapshot(
      daily: QuestSection.fromJson(m['daily']),
      weekly: QuestSection.fromJson(m['weekly']),
      discovery: QuestSection.fromJson(m['discovery']),
      events: (m['events'] is List ? m['events'] as List : const [])
          .map(EventQuests.fromJson)
          .whereType<EventQuests>()
          .toList(),
    );
  }

  QuestsSnapshot withDaily(QuestSection daily) =>
      QuestsSnapshot(daily: daily, weekly: weekly, discovery: discovery, events: events);
}

class InventoryItem {
  final String itemId;
  final String source;
  final bool isNew;
  const InventoryItem({required this.itemId, this.source = '', this.isNew = false});

  static InventoryItem? fromJson(dynamic json) {
    final m = _map(json);
    final id = _str(m['itemId']);
    if (id == null) return null;
    return InventoryItem(itemId: id, source: _str(m['source']) ?? '', isNew: m['isNew'] == true);
  }
}

class OwnedBadge {
  final String id;
  final String badgeId;
  final String? tier;
  final String? date;
  const OwnedBadge({required this.id, required this.badgeId, this.tier, this.date});

  static OwnedBadge? fromJson(dynamic json) {
    final m = _map(json);
    final id = _str(m['id']);
    final badgeId = _str(m['badgeId']);
    if (id == null || badgeId == null) return null;
    return OwnedBadge(id: id, badgeId: badgeId, tier: _str(m['tier']), date: _str(m['date']));
  }

  PublicBadge get asPublic => PublicBadge(id: id, badgeId: badgeId, tier: tier, date: date);
}

class Inventory {
  final List<InventoryItem> items;
  final List<OwnedBadge> badges;
  final Equipment equipment;
  const Inventory({this.items = const [], this.badges = const [], this.equipment = const Equipment()});

  factory Inventory.fromJson(dynamic json) {
    final m = _map(json);
    return Inventory(
      items: (m['items'] is List ? m['items'] as List : const [])
          .map(InventoryItem.fromJson)
          .whereType<InventoryItem>()
          .toList(),
      badges: (m['badges'] is List ? m['badges'] as List : const [])
          .map(OwnedBadge.fromJson)
          .whereType<OwnedBadge>()
          .toList(),
      equipment: Equipment.fromJson(m['equipment']),
    );
  }

  bool owns(String itemId) => items.any((i) => i.itemId == itemId);
}

class XpEntry {
  final String source;
  final String refId;
  final int amount;
  final LocalizedText label;
  const XpEntry({required this.source, required this.refId, required this.amount, required this.label});

  static XpEntry? fromJson(dynamic json) {
    final m = _map(json);
    final source = _str(m['source']);
    if (source == null) return null;
    return XpEntry(
      source: source,
      refId: _str(m['refId']) ?? '',
      amount: _int(m['amount']),
      label: LocalizedText.fromJson(m['label']),
    );
  }
}

class XpFeed {
  final List<XpEntry> entries;
  final int totalAmount;
  final int levelBefore;
  final int levelAfter;
  final List<LevelRewardDef> levelUps;
  final ProgressionSummary progression;

  const XpFeed({
    this.entries = const [],
    this.totalAmount = 0,
    this.levelBefore = 1,
    this.levelAfter = 1,
    this.levelUps = const [],
    this.progression = const ProgressionSummary(),
  });

  factory XpFeed.fromJson(dynamic json) {
    final m = _map(json);
    return XpFeed(
      entries: (m['entries'] is List ? m['entries'] as List : const [])
          .map(XpEntry.fromJson)
          .whereType<XpEntry>()
          .toList(),
      totalAmount: _int(m['totalAmount']),
      levelBefore: _int(m['levelBefore'], 1),
      levelAfter: _int(m['levelAfter'], 1),
      levelUps: (m['levelUps'] is List ? m['levelUps'] as List : const [])
          .map(LevelRewardDef.fromJson)
          .toList(),
      progression: ProgressionSummary.fromJson(m['progression']),
    );
  }
}

/// PUT /progression/equipment body: only the set keys are sent.
class EquipRequest {
  final Map<String, dynamic> body;
  const EquipRequest._(this.body);

  factory EquipRequest({
    Object? avatar = _unset,
    Object? frame = _unset,
    Object? background = _unset,
    Object? title = _unset,
    Object? flight = _unset,
    List<String>? badges,
    Object? monogram = _unset,
  }) {
    final b = <String, dynamic>{};
    void put(String k, Object? v) {
      if (!identical(v, _unset)) b[k] = v is MonogramChoice ? v.toJson() : v;
    }

    put('avatar', avatar);
    put('frame', frame);
    put('background', background);
    put('title', title);
    put('flight', flight);
    if (badges != null) b['badges'] = badges;
    put('monogram', monogram);
    return EquipRequest._(b);
  }

  /// Equips [itemId] in the slot of its type (null unequips).
  factory EquipRequest.slot(ItemType type, String? itemId) => switch (type) {
        ItemType.avatar => EquipRequest(avatar: itemId),
        ItemType.frame => EquipRequest(frame: itemId),
        ItemType.background => EquipRequest(background: itemId),
        ItemType.title => EquipRequest(title: itemId),
        ItemType.flight => EquipRequest(flight: itemId),
        _ => EquipRequest(),
      };
}

const Object _unset = Object();
