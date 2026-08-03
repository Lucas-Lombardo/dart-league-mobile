/// One clip of the cloud library, as `GET /replays/mine` returns it.
class ReplayEntry {
  ReplayEntry({
    required this.id,
    required this.url,
    required this.createdAt,
    this.name,
    this.turnTotal,
  });

  factory ReplayEntry.fromJson(Map<String, dynamic> json) => ReplayEntry(
        id: json['id'] as String,
        url: json['url'] as String,
        createdAt:
            DateTime.tryParse(json['createdAt'] as String? ?? '')?.toLocal() ??
                DateTime.now(),
        name: (json['name'] as String?)?.trim(),
        turnTotal: (json['turnTotal'] as num?)?.toInt(),
      );

  final String id;
  final String url;
  final DateTime createdAt;
  final String? name;
  final int? turnTotal;

  bool get hasName => name != null && name!.isNotEmpty;

  /// Whole days left before the backend's retention sweep removes this clip.
  /// Zero or less means the next sweep takes it.
  int daysLeft(int retentionDays) => createdAt
      .add(Duration(days: retentionDays))
      .difference(DateTime.now())
      .inDays;
}

/// Clips that belong to the same match as the player remembers it. A ranked
/// BO3 is ONE group, not one per leg — the backend collapses the legs onto
/// the series key, this just carries the result.
class ReplayGroup {
  ReplayGroup({
    required this.key,
    required this.clips,
    this.opponent,
    this.matchType,
    this.tournamentName,
    this.bestOf,
    this.myLegs,
    this.opponentLegs,
    this.outcome,
  });

  /// [orphanKey] when the clips have no match left to attach to.
  final String key;
  final List<ReplayEntry> clips;
  final String? opponent;
  final String? matchType;
  final String? tournamentName;
  final int? bestOf;
  final int? myLegs;
  final int? opponentLegs;

  /// 'won' | 'lost' | 'pending', or null when there is no match.
  final String? outcome;

  static const orphanKey = '_no_match';

  bool get isOrphan => key == orphanKey;

  /// The group sits in the list at its most recent clip — the API already
  /// returns clips newest first.
  DateTime get latestAt => clips.first.createdAt;

  /// Legs are only worth showing once both sides are known.
  bool get hasLegs => myLegs != null && opponentLegs != null;
}

/// Groups a page of `/replays/mine` while preserving its order: the first
/// clip of a match fixes where that match appears.
///
/// Clips whose match is unknown (captured outside a match, or whose match row
/// is gone) all land in a single [ReplayGroup.orphanKey] group, placed where
/// the most recent of them appeared.
List<ReplayGroup> groupReplayClips(List<Map<String, dynamic>> raw) {
  final order = <String>[];
  final entries = <String, List<ReplayEntry>>{};
  final contexts = <String, Map<String, dynamic>>{};

  for (final json in raw) {
    final match = json['match'] as Map<String, dynamic>?;
    final key = match?['key'] as String? ?? ReplayGroup.orphanKey;
    if (!entries.containsKey(key)) {
      order.add(key);
      entries[key] = [];
      if (match != null) contexts[key] = match;
    }
    entries[key]!.add(ReplayEntry.fromJson(json));
  }

  return [
    for (final key in order)
      ReplayGroup(
        key: key,
        clips: entries[key]!,
        opponent: contexts[key]?['opponent'] as String?,
        matchType: contexts[key]?['matchType'] as String?,
        tournamentName: contexts[key]?['tournamentName'] as String?,
        bestOf: (contexts[key]?['bestOf'] as num?)?.toInt(),
        myLegs: (contexts[key]?['myLegs'] as num?)?.toInt(),
        opponentLegs: (contexts[key]?['opponentLegs'] as num?)?.toInt(),
        outcome: contexts[key]?['outcome'] as String?,
      ),
  ];
}
