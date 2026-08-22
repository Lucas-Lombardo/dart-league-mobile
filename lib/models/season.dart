import '../utils/api_config.dart';

/// Seasons: a ladder cycle. The backend keeps exactly one `active`, one
/// `scheduled` and N `closed` seasons; a closed season carries a frozen
/// ladder. Every `fromJson` here is defensive: the hub must never crash on a
/// partial payload, it simply shows less.

DateTime? _date(dynamic value) {
  if (value is! String || value.isEmpty) return null;
  try {
    return DateTime.parse(value);
  } on FormatException {
    return null;
  }
}

int? _int(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

Map<String, dynamic>? _map(dynamic value) =>
    value is Map<String, dynamic> ? value : null;

enum SeasonStatus { scheduled, active, closed }

SeasonStatus _status(dynamic value) {
  switch (value) {
    case 'active':
      return SeasonStatus.active;
    case 'closed':
      return SeasonStatus.closed;
    default:
      return SeasonStatus.scheduled;
  }
}

/// The #1 of a closed season (frozen), or the live leader of the active one.
class SeasonChampion {
  final String id;
  final String username;
  final int elo;
  final String rank;

  const SeasonChampion({
    required this.id,
    required this.username,
    required this.elo,
    required this.rank,
  });

  factory SeasonChampion.fromJson(Map<String, dynamic> json) {
    return SeasonChampion(
      id: json['id'] as String? ?? '',
      username: json['username'] as String? ?? '',
      elo: _int(json['elo']) ?? 0,
      rank: json['rank'] as String? ?? 'unranked',
    );
  }
}

/// One player's line in a season: frozen for a closed season, live for the
/// active one (`/seasons/:n/standings/me`, `myStanding`, `me`).
class SeasonStanding {
  final int position;
  final int elo;
  final String rank;
  final int wins;
  final int losses;

  const SeasonStanding({
    required this.position,
    required this.elo,
    required this.rank,
    required this.wins,
    required this.losses,
  });

  factory SeasonStanding.fromJson(Map<String, dynamic> json) {
    return SeasonStanding(
      position: _int(json['position']) ?? 0,
      elo: _int(json['elo']) ?? 0,
      rank: json['rank'] as String? ?? 'unranked',
      wins: _int(json['wins']) ?? 0,
      losses: _int(json['losses']) ?? 0,
    );
  }
}

class Season {
  final String id;
  final int number;
  final SeasonStatus status;
  /// Null for Season 0 ("since launch").
  final DateTime? startedAt;
  /// Null while the end is not decided yet — the season simply keeps running.
  final DateTime? endAt;
  final DateTime? closedAt;
  final String? trophyModel;
  /// Season 0 has no prize; every later season pays 50 € + a trophy.
  final bool hasReward;
  final SeasonChampion? champion;
  final int? playersCount;
  final SeasonStanding? myStanding;

  const Season({
    required this.id,
    required this.number,
    required this.status,
    this.startedAt,
    this.endAt,
    this.closedAt,
    this.trophyModel,
    required this.hasReward,
    this.champion,
    this.playersCount,
    this.myStanding,
  });

  factory Season.fromJson(Map<String, dynamic> json) {
    final number = _int(json['number']) ?? 0;
    final champion = _map(json['champion']);
    final mine = _map(json['myStanding']);
    return Season(
      id: json['id'] as String? ?? '',
      number: number,
      status: _status(json['status']),
      startedAt: _date(json['startedAt']),
      endAt: _date(json['endAt']),
      closedAt: _date(json['closedAt']),
      trophyModel: json['trophyModel'] as String?,
      hasReward: json['hasReward'] as bool? ?? number > 0,
      champion: champion == null ? null : SeasonChampion.fromJson(champion),
      playersCount: _int(json['playersCount']),
      myStanding: mine == null ? null : SeasonStanding.fromJson(mine),
    );
  }

  bool get isActive => status == SeasonStatus.active;
  bool get isClosed => status == SeasonStatus.closed;
  bool get isScheduled => status == SeasonStatus.scheduled;

  /// True when a physical trophy model was picked by the admin.
  bool get hasTrophyImage => trophyModel != null && trophyModel!.isNotEmpty;

  /// Full-size render (1024 px, transparent background).
  String get trophyImageUrl => '$baseUrl/trophies/$trophyModel.png';

  /// Small render (320 px) for list rows and cards.
  String get trophyThumbUrl => '$baseUrl/trophies/$trophyModel-thumb.png';

  /// Time left before the end, or null when no end is set. Never negative.
  Duration? timeLeft([DateTime? now]) {
    final end = endAt;
    if (end == null) return null;
    final left = end.difference(now ?? DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  /// 0..1 position of `now` between start and end, null when either is
  /// missing (Season 0 has no start; an open-ended season has no end).
  double? progress([DateTime? now]) {
    final start = startedAt;
    final end = endAt;
    if (start == null || end == null) return null;
    final total = end.difference(start).inSeconds;
    if (total <= 0) return 1;
    final elapsed = (now ?? DateTime.now()).difference(start).inSeconds;
    return (elapsed / total).clamp(0.0, 1.0);
  }
}

/// `GET /seasons/current`: the active season, the next one, the live leader
/// and the caller's live standing (null while unranked).
class CurrentSeason {
  final Season season;
  final Season? next;
  final SeasonChampion? leader;
  final SeasonStanding? me;

  const CurrentSeason({
    required this.season,
    this.next,
    this.leader,
    this.me,
  });

  static CurrentSeason? fromJson(Map<String, dynamic> json) {
    final season = _map(json['season']);
    if (season == null) return null;
    final next = _map(json['next']);
    final leader = _map(json['leader']);
    final me = _map(json['me']);
    return CurrentSeason(
      season: Season.fromJson(season),
      next: next == null ? null : Season.fromJson(next),
      leader: leader == null ? null : SeasonChampion.fromJson(leader),
      me: me == null ? null : SeasonStanding.fromJson(me),
    );
  }
}

/// `GET /seasons/recap`: the once-only end-of-season screens.
class SeasonRecap {
  final Season season;
  final SeasonStanding standing;
  final int eloBefore;
  final int eloAfter;
  final String rankBefore;
  final String rankAfter;
  /// Best rating reached during the season (the "record" tile).
  final int? peakElo;
  final SeasonChampion? champion;
  final Season? nextSeason;

  const SeasonRecap({
    required this.season,
    required this.standing,
    required this.eloBefore,
    required this.eloAfter,
    required this.rankBefore,
    required this.rankAfter,
    this.peakElo,
    this.champion,
    this.nextSeason,
  });

  static SeasonRecap? fromJson(Map<String, dynamic> json) {
    final season = _map(json['season']);
    final standing = _map(json['standing']);
    if (season == null || standing == null) return null;
    final champion = _map(json['champion']);
    final next = _map(json['nextSeason']);
    final line = SeasonStanding.fromJson(standing);
    return SeasonRecap(
      season: Season.fromJson(season),
      standing: line,
      eloBefore: _int(json['eloBefore']) ?? line.elo,
      eloAfter: _int(json['eloAfter']) ?? _int(standing['eloAfterReset']) ?? line.elo,
      rankBefore: json['rankBefore'] as String? ?? line.rank,
      rankAfter: json['rankAfter'] as String? ?? line.rank,
      peakElo: _int(standing['peakElo']),
      champion: champion == null ? null : SeasonChampion.fromJson(champion),
      nextSeason: next == null ? null : Season.fromJson(next),
    );
  }

  bool get rankChanged => rankBefore.toLowerCase() != rankAfter.toLowerCase();
}
