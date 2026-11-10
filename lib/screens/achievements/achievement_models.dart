// Achievements models — docs/progression/CONTRACT.md §14.3.
//
// Every fromJson is defensive: a missing or mistyped field falls back to a
// default and an unknown element is dropped (an old app hides new content,
// it never crashes).
import '../../models/progression.dart';

int _int(dynamic v, [int fallback = 0]) =>
    v is int ? v : (v is num ? v.toInt() : (int.tryParse('$v') ?? fallback));

double _num(dynamic v, [double fallback = 0]) =>
    v is num ? v.toDouble() : (double.tryParse('$v') ?? fallback);

double? _numOrNull(dynamic v) => v is num ? v.toDouble() : null;

String? _str(dynamic v) => v is String ? v : null;

DateTime? _date(dynamic v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;

List<String> _strings(dynamic v) => v is List ? v.whereType<String>().toList() : const <String>[];

Map<String, dynamic> _map(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : const <String, dynamic>{};

List<T> _list<T>(dynamic v, T? Function(dynamic) parse) =>
    v is List ? v.map(parse).whereType<T>().toList() : <T>[];

LocalizedText? _text(dynamic v) => v is Map ? LocalizedText.fromJson(v) : null;

/// 'bronze' | 'silver' | 'gold' | 'unique'.
const kAchievementTiers = ['bronze', 'silver', 'gold', 'unique'];

int achievementTierRank(String? tier) => switch (tier) {
      'bronze' => 1,
      'silver' => 2,
      'gold' || 'unique' => 3,
      _ => 0,
    };

class AchievementFamily {
  final String id;
  final LocalizedText name;
  const AchievementFamily({required this.id, required this.name});

  static AchievementFamily? fromJson(dynamic json) {
    final m = _map(json);
    final id = _str(m['id']);
    if (id == null) return null;
    return AchievementFamily(id: id, name: LocalizedText.fromJson(m['name']));
  }
}

class AchievementStep {
  final String tier;
  final double threshold;
  final int xp;
  final List<String> itemIds;

  /// Ordinal tiers (a league, a rank): the name shown instead of the number.
  final LocalizedText? label;
  final DateTime? unlockedAt;
  final double? rarity;

  /// Tour 5: reached, but held for an admin review (« En vérification »).
  final bool pending;

  const AchievementStep({
    required this.tier,
    required this.threshold,
    this.xp = 0,
    this.itemIds = const [],
    this.label,
    this.unlockedAt,
    this.rarity,
    this.pending = false,
  });

  bool get done => unlockedAt != null;

  static AchievementStep? fromJson(dynamic json) {
    final m = _map(json);
    final tier = _str(m['tier']);
    if (tier == null || !kAchievementTiers.contains(tier)) return null;
    return AchievementStep(
      tier: tier,
      threshold: _num(m['threshold']),
      xp: _int(m['xp']),
      itemIds: _strings(m['itemIds']),
      label: _text(m['label']),
      unlockedAt: _date(m['unlockedAt']),
      rarity: _numOrNull(m['rarity']),
      pending: m['pending'] == true,
    );
  }
}

class AchievementNext {
  final String tier;
  final double threshold;
  final double ratio;
  final LocalizedText? label;
  const AchievementNext({required this.tier, required this.threshold, this.ratio = 0, this.label});

  static AchievementNext? fromJson(dynamic json) {
    if (json is! Map) return null;
    final m = _map(json);
    final tier = _str(m['tier']);
    if (tier == null) return null;
    return AchievementNext(
      tier: tier,
      threshold: _num(m['threshold']),
      ratio: _num(m['ratio']).clamp(0, 1).toDouble(),
      label: _text(m['label']),
    );
  }
}

/// One achievement with my progress (GET /achievements, /achievements/:id).
class Achievement {
  final String id;
  final String family;
  final int sortOrder;
  final LocalizedText name;
  final LocalizedText description;
  final String badgeId;
  final bool aiOnly;

  /// 'int' | 'decimal' | 'percent' | 'ordinal'.
  final String format;

  /// 'count' | 'sum' | 'max' | 'min' | 'distinct' | 'streak'.
  final String aggregate;
  final bool unique;
  final String? tier;
  final double value;
  final double? best;
  final AchievementNext? next;
  final List<AchievementStep> steps;
  final double? rarity;
  final DateTime? unlockedAt;
  final int? accountAgeDays;

  /// Tour 5: some tier is held for an admin review.
  final bool pendingReview;

  const Achievement({
    required this.id,
    required this.family,
    required this.name,
    required this.badgeId,
    this.sortOrder = 0,
    this.description = LocalizedText.empty,
    this.aiOnly = false,
    this.format = 'int',
    this.aggregate = 'count',
    this.unique = false,
    this.tier,
    this.value = 0,
    this.best,
    this.next,
    this.steps = const [],
    this.rarity,
    this.unlockedAt,
    this.accountAgeDays,
    this.pendingReview = false,
  });

  bool get unlocked => tier != null;
  bool get complete => unlocked && next == null;

  /// Lower is better (a leg in 12 darts beats one in 18).
  bool get lowerIsBetter => aggregate == 'min';

  /// The share of players holding the tier I reached ([rarity] is the first
  /// tier's, the one a locked achievement shows).
  double? get tierRarity {
    final reached = tier;
    if (reached != null) {
      for (final s in steps) {
        if (s.tier == reached && s.rarity != null) return s.rarity;
      }
    }
    return rarity;
  }

  /// The badge as the medal widget expects it (no user badge id needed).
  PublicBadge get badge => PublicBadge(id: id, badgeId: badgeId, tier: tier == 'unique' ? null : tier);

  static Achievement? fromJson(dynamic json) {
    final m = _map(json);
    final id = _str(m['id']);
    final badgeId = _str(m['badgeId']);
    if (id == null || badgeId == null) return null;
    final tier = _str(m['tier']);
    return Achievement(
      id: id,
      family: _str(m['family']) ?? 'other',
      sortOrder: _int(m['sortOrder']),
      name: LocalizedText.fromJson(m['name']),
      description: LocalizedText.fromJson(m['description']),
      badgeId: badgeId,
      aiOnly: m['aiOnly'] == true,
      format: _str(m['format']) ?? 'int',
      aggregate: _str(m['aggregate']) ?? 'count',
      unique: m['unique'] == true,
      tier: kAchievementTiers.contains(tier) ? tier : null,
      value: _num(m['value']),
      best: _numOrNull(m['best']),
      next: AchievementNext.fromJson(m['next']),
      steps: _list(m['steps'], AchievementStep.fromJson),
      rarity: _numOrNull(m['rarity']),
      unlockedAt: _date(m['unlockedAt']),
      accountAgeDays: m['requires'] is Map ? (_map(m['requires'])['accountAgeDays'] as num?)?.toInt() : null,
      pendingReview: m['pendingReview'] == true,
    );
  }
}

class AchievementsSnapshot {
  final List<AchievementFamily> families;
  final List<Achievement> achievements;
  final int unlocked;
  final int total;
  final String? closestId;

  const AchievementsSnapshot({
    this.families = const [],
    this.achievements = const [],
    this.unlocked = 0,
    this.total = 0,
    this.closestId,
  });

  Achievement? get closest {
    final id = closestId;
    if (id == null) return null;
    for (final a in achievements) {
      if (a.id == id) return a;
    }
    return null;
  }

  factory AchievementsSnapshot.fromJson(dynamic json) {
    final m = _map(json);
    final list = _list(m['achievements'], Achievement.fromJson)..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return AchievementsSnapshot(
      families: _list(m['families'], AchievementFamily.fromJson),
      achievements: list,
      unlocked: _int(m['unlocked'], list.where((a) => a.unlocked).length),
      total: _int(m['total'], list.length),
      closestId: _str(m['closestId']),
    );
  }
}

/// A sample that moved the achievement (« Tes derniers 180 »).
class AchievementOccurrence {
  final DateTime? at;
  final double? value;
  final String? mode;
  final String? matchId;
  final String? opponentId;
  final String? opponentName;
  final int? legNumber;
  final bool hasCloudReplay;

  const AchievementOccurrence({
    this.at,
    this.value,
    this.mode,
    this.matchId,
    this.opponentId,
    this.opponentName,
    this.legNumber,
    this.hasCloudReplay = false,
  });

  static AchievementOccurrence? fromJson(dynamic json) {
    if (json is! Map) return null;
    final m = _map(json);
    final opp = _map(m['opponent']);
    return AchievementOccurrence(
      at: _date(m['at']),
      value: _numOrNull(m['value']),
      mode: _str(m['mode']),
      matchId: _str(m['matchId']),
      opponentId: _str(opp['id']),
      opponentName: _str(opp['username']),
      legNumber: m['legNumber'] is num ? (m['legNumber'] as num).toInt() : null,
      hasCloudReplay: m['hasCloudReplay'] == true,
    );
  }
}

class AchievementDetail {
  final Achievement achievement;
  final List<AchievementOccurrence> recent;
  const AchievementDetail({required this.achievement, this.recent = const []});

  static AchievementDetail? fromJson(dynamic json) {
    final a = Achievement.fromJson(json);
    if (a == null) return null;
    return AchievementDetail(achievement: a, recent: _list(_map(json)['recent'], AchievementOccurrence.fromJson));
  }
}

/// One tier reached (end of match, home screen).
class AchievementUnlock {
  final String id;
  final String achievementId;
  final String tier;
  final DateTime? unlockedAt;
  final bool retro;
  final int xp;
  final List<String> itemIds;
  final String? matchId;
  final double? contextValue;
  final LocalizedText name;
  final String badgeId;
  final double threshold;
  final LocalizedText? label;
  final String format;
  final double? rarity;
  final AchievementNext? next;
  final List<String> nextItemIds;
  final String? userBadgeId;

  const AchievementUnlock({
    required this.id,
    required this.achievementId,
    required this.tier,
    required this.name,
    required this.badgeId,
    this.unlockedAt,
    this.retro = false,
    this.xp = 0,
    this.itemIds = const [],
    this.matchId,
    this.contextValue,
    this.threshold = 0,
    this.label,
    this.format = 'int',
    this.rarity,
    this.next,
    this.nextItemIds = const [],
    this.userBadgeId,
  });

  PublicBadge get badge =>
      PublicBadge(id: userBadgeId ?? id, badgeId: badgeId, tier: tier == 'unique' ? null : tier);

  static AchievementUnlock? fromJson(dynamic json) {
    final m = _map(json);
    final id = _str(m['id']);
    final achievementId = _str(m['achievementId']);
    final tier = _str(m['tier']);
    final badgeId = _str(m['badgeId']);
    if (id == null || achievementId == null || tier == null || badgeId == null) return null;
    if (!kAchievementTiers.contains(tier)) return null;
    final ctx = _map(m['context']);
    final next = _map(m['next']);
    return AchievementUnlock(
      id: id,
      achievementId: achievementId,
      tier: tier,
      name: LocalizedText.fromJson(m['name']),
      badgeId: badgeId,
      unlockedAt: _date(m['unlockedAt']),
      retro: m['retro'] == true,
      xp: _int(m['xp']),
      itemIds: _strings(m['itemIds']),
      matchId: _str(ctx['matchId']),
      contextValue: _numOrNull(ctx['value']),
      threshold: _num(m['threshold']),
      label: _text(m['label']),
      format: _str(m['format']) ?? 'int',
      rarity: _numOrNull(m['rarity']),
      next: AchievementNext.fromJson(m['next']),
      nextItemIds: _strings(next['itemIds']),
      userBadgeId: _str(m['userBadgeId']),
    );
  }

  static List<AchievementUnlock> listFromJson(dynamic json) => _list(_map(json)['unlocks'], AchievementUnlock.fromJson);
}

class AchievementsSummary {
  final int unlocked;
  final int total;
  const AchievementsSummary({this.unlocked = 0, this.total = 0});

  factory AchievementsSummary.fromJson(dynamic json) {
    final m = _map(json);
    return AchievementsSummary(unlocked: _int(m['unlocked']), total: _int(m['total']));
  }
}
