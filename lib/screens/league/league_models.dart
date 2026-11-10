import 'package:flutter/material.dart';

import '../../models/progression.dart';

/// Weekly league (docs/progression/CONTRACT.md §14.4). Every `fromJson` is
/// defensive: a missing or mistyped field gives a default, an unknown league
/// or outcome never throws.

int _int(dynamic v, [int fallback = 0]) => v is int ? v : (v is num ? v.toInt() : fallback);
String? _str(dynamic v) => v is String ? v : null;
Map<String, dynamic> _map(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : const {};
List<dynamic> _list(dynamic v) => v is List ? v : const [];
DateTime? _date(dynamic v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;

Color _hex(String? raw, Color fallback) {
  if (raw == null) return fallback;
  final s = raw.replaceFirst('#', '');
  if (s.length != 6) return fallback;
  final v = int.tryParse(s, radix: 16);
  return v == null ? fallback : Color(0xFF000000 | v);
}

/// One league of the ladder (Bois → Diamant), as the server defines it.
class LeagueTier {
  final String id;
  final int order;
  final LocalizedText name;
  final Color color;
  final List<Color> colors;

  const LeagueTier({
    required this.id,
    required this.order,
    required this.name,
    this.color = const Color(0xFFCBD5E1),
    this.colors = const [Color(0xFFE2E8F0), Color(0xFF7B8798), Color(0xFFCBD5E1)],
  });

  static LeagueTier? fromJson(dynamic json) {
    final m = _map(json);
    final id = _str(m['id']);
    if (id == null) return null;
    final colors = _list(m['colors']).map((c) => _hex(_str(c), const Color(0xFF7B8798))).toList();
    return LeagueTier(
      id: id,
      order: _int(m['order']),
      name: LocalizedText.fromJson(m['name']),
      color: _hex(_str(m['color']), const Color(0xFFCBD5E1)),
      colors: colors.length == 3 ? colors : const [Color(0xFFE2E8F0), Color(0xFF7B8798), Color(0xFFCBD5E1)],
    );
  }

  LinearGradient get gradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: colors,
        stops: const [0, 0.45, 1],
      );
}

/// One line of the "Everything counts" card.
class LeaguePointRule {
  final String id;
  final int points;
  final int winBonus;
  final LocalizedText? label;

  const LeaguePointRule({required this.id, required this.points, this.winBonus = 0, this.label});

  static LeaguePointRule? fromJson(dynamic json) {
    final m = _map(json);
    final id = _str(m['id']);
    if (id == null) return null;
    return LeaguePointRule(
      id: id,
      points: _int(m['points']),
      winBonus: _int(m['winBonus']),
      label: m['label'] is Map ? LocalizedText.fromJson(m['label']) : null,
    );
  }
}

class LeagueStanding {
  final int position;
  final String userId;
  final String username;
  final int elo;
  final String rank;
  final String league;
  final int points;
  final bool isMe;
  final PublicCosmetics? cosmetics;

  const LeagueStanding({
    required this.position,
    required this.userId,
    required this.username,
    this.elo = 0,
    this.rank = 'unranked',
    this.league = '',
    this.points = 0,
    this.isMe = false,
    this.cosmetics,
  });

  static LeagueStanding? fromJson(dynamic json) {
    final m = _map(json);
    final userId = _str(m['userId']);
    if (userId == null) return null;
    return LeagueStanding(
      position: _int(m['position']),
      userId: userId,
      username: _str(m['username']) ?? '',
      elo: _int(m['elo']),
      rank: _str(m['rank']) ?? 'unranked',
      league: _str(m['league']) ?? '',
      points: _int(m['points']),
      isMe: m['isMe'] == true,
      cosmetics: PublicCosmetics.fromJson(m['cosmetics']),
    );
  }
}

class LeagueGroup {
  final String id;
  final int size;
  final int promoteCount;
  final int relegateCount;
  /// Null at the top league (nobody goes up) / the bottom one (nobody goes down).
  final LeagueTier? promoteTo;
  final LeagueTier? relegateTo;
  final List<LeagueStanding> standings;

  const LeagueGroup({
    required this.id,
    this.size = 0,
    this.promoteCount = 0,
    this.relegateCount = 0,
    this.promoteTo,
    this.relegateTo,
    this.standings = const [],
  });

  static LeagueGroup? fromJson(dynamic json) {
    final m = _map(json);
    final id = _str(m['id']);
    if (id == null) return null;
    final standings = _list(m['standings']).map(LeagueStanding.fromJson).whereType<LeagueStanding>().toList();
    return LeagueGroup(
      id: id,
      size: _int(m['size'], standings.length),
      promoteCount: _int(m['promoteCount']),
      relegateCount: _int(m['relegateCount']),
      promoteTo: LeagueTier.fromJson(m['promoteTo']),
      relegateTo: LeagueTier.fromJson(m['relegateTo']),
      standings: standings,
    );
  }

  /// First position of the relegation zone (16 in a group of 20).
  int get relegateFrom => size - relegateCount + 1;
}

enum LeagueWeekState { open, closed, none }

/// GET /league/me
class LeagueSnapshot {
  final bool enabled;
  final String weekKey;
  final int weekNumber;
  final DateTime? endsAt;
  final DateTime? nextStartsAt;
  final LeagueWeekState state;
  final bool firstWeek;
  final LeagueTier? league;
  final List<LeagueTier> ladder;
  final List<LeaguePointRule> pointRules;
  final bool hasResult;
  final LeagueGroup? group;
  final int? myPosition;
  final int myPoints;

  const LeagueSnapshot({
    this.enabled = true,
    this.weekKey = '',
    this.weekNumber = 0,
    this.endsAt,
    this.nextStartsAt,
    this.state = LeagueWeekState.none,
    this.firstWeek = false,
    this.league,
    this.ladder = const [],
    this.pointRules = const [],
    this.hasResult = false,
    this.group,
    this.myPosition,
    this.myPoints = 0,
  });

  factory LeagueSnapshot.fromJson(dynamic json) {
    final m = _map(json);
    final me = _map(m['me']);
    return LeagueSnapshot(
      enabled: m['enabled'] != false,
      weekKey: _str(m['weekKey']) ?? '',
      weekNumber: _int(m['weekNumber']),
      endsAt: _date(m['endsAt']),
      nextStartsAt: _date(m['nextStartsAt']),
      state: switch (_str(m['state'])) {
        'open' => LeagueWeekState.open,
        'closed' => LeagueWeekState.closed,
        _ => LeagueWeekState.none,
      },
      firstWeek: m['firstWeek'] == true,
      league: LeagueTier.fromJson(m['league']),
      ladder: _list(m['ladder']).map(LeagueTier.fromJson).whereType<LeagueTier>().toList()
        ..sort((a, b) => a.order.compareTo(b.order)),
      pointRules: _list(m['pointRules']).map(LeaguePointRule.fromJson).whereType<LeaguePointRule>().toList(),
      hasResult: m['hasResult'] == true,
      group: LeagueGroup.fromJson(m['group']),
      myPosition: me['position'] is num ? _int(me['position']) : null,
      myPoints: _int(me['points']),
    );
  }

  bool get inGroup => group != null && state != LeagueWeekState.none;
}

enum LeagueOutcome { promoted, relegated, stayed }

LeagueOutcome _outcome(dynamic raw) => switch (raw) {
      'promoted' => LeagueOutcome.promoted,
      'relegated' => LeagueOutcome.relegated,
      _ => LeagueOutcome.stayed,
    };

/// GET /league/result → `result` (the Monday screen).
class LeagueResult {
  final String weekKey;
  final int weekNumber;
  final LeagueTier? league;
  final LeagueTier? leagueAfter;
  final LeagueOutcome outcome;
  final int position;
  final int groupSize;
  final int points;
  final int xp;
  final List<String> itemIds;
  final PublicBadge? badge;
  final List<String> promotedWith;
  final int? nextGroupSize;
  final DateTime? nextEndsAt;
  final List<LeagueTier> ladder;

  const LeagueResult({
    required this.weekKey,
    this.weekNumber = 0,
    this.league,
    this.leagueAfter,
    this.outcome = LeagueOutcome.stayed,
    this.position = 0,
    this.groupSize = 0,
    this.points = 0,
    this.xp = 0,
    this.itemIds = const [],
    this.badge,
    this.promotedWith = const [],
    this.nextGroupSize,
    this.nextEndsAt,
    this.ladder = const [],
  });

  static LeagueResult? fromJson(dynamic json) {
    final m = _map(json);
    final weekKey = _str(m['weekKey']);
    if (weekKey == null) return null;
    final badge = _map(m['badge']);
    final badgeId = _str(badge['badgeId']);
    final next = _map(m['next']);
    return LeagueResult(
      weekKey: weekKey,
      weekNumber: _int(m['weekNumber']),
      league: LeagueTier.fromJson(m['league']),
      leagueAfter: LeagueTier.fromJson(m['leagueAfter']),
      outcome: _outcome(m['outcome']),
      position: _int(m['position']),
      groupSize: _int(m['groupSize']),
      points: _int(m['points']),
      xp: _int(m['xp']),
      itemIds: _list(m['itemIds']).whereType<String>().toList(),
      badge: badgeId == null
          ? null
          : PublicBadge(id: 'league-$weekKey', badgeId: badgeId, tier: _str(badge['tier']), date: weekKey),
      promotedWith: _list(m['promotedWith']).whereType<String>().toList(),
      nextGroupSize: next.isEmpty ? null : _int(next['groupSize']),
      nextEndsAt: _date(next['endsAt']),
      ladder: _list(m['ladder']).map(LeagueTier.fromJson).whereType<LeagueTier>().toList()
        ..sort((a, b) => a.order.compareTo(b.order)),
    );
  }
}

class LeagueHistoryWeek {
  final String weekKey;
  final int weekNumber;
  final LeagueTier? league;
  final LeagueTier? leagueAfter;
  final LeagueOutcome outcome;
  final int position;
  final int groupSize;
  final int points;
  final int xp;

  const LeagueHistoryWeek({
    required this.weekKey,
    this.weekNumber = 0,
    this.league,
    this.leagueAfter,
    this.outcome = LeagueOutcome.stayed,
    this.position = 0,
    this.groupSize = 0,
    this.points = 0,
    this.xp = 0,
  });

  static LeagueHistoryWeek? fromJson(dynamic json) {
    final m = _map(json);
    final weekKey = _str(m['weekKey']);
    if (weekKey == null) return null;
    return LeagueHistoryWeek(
      weekKey: weekKey,
      weekNumber: _int(m['weekNumber']),
      league: LeagueTier.fromJson(m['league']),
      leagueAfter: LeagueTier.fromJson(m['leagueAfter']),
      outcome: _outcome(m['outcome']),
      position: _int(m['position']),
      groupSize: _int(m['groupSize']),
      points: _int(m['points']),
      xp: _int(m['xp']),
    );
  }
}

/// GET /league/history
class LeagueHistory {
  final LeagueTier? league;
  final LeagueTier? best;
  final int weeksPlayed;
  final int promotions;
  final List<LeagueHistoryWeek> weeks;

  const LeagueHistory({this.league, this.best, this.weeksPlayed = 0, this.promotions = 0, this.weeks = const []});

  factory LeagueHistory.fromJson(dynamic json) {
    final m = _map(json);
    return LeagueHistory(
      league: LeagueTier.fromJson(m['league']),
      best: LeagueTier.fromJson(m['best']),
      weeksPlayed: _int(m['weeksPlayed']),
      promotions: _int(m['promotions']),
      weeks: _list(m['weeks']).map(LeagueHistoryWeek.fromJson).whereType<LeagueHistoryWeek>().toList(),
    );
  }
}

/// GET /league/match-delta → `delta`: the league line of an end-of-match
/// screen (mockup FinDeMatchXP): points earned since the match started, and
/// my place in my group before and after them. Null when there is nothing to
/// say (no group this week, no point, older server).
class LeagueMatchDelta {
  final LeagueTier league;
  final int points;
  final int positionBefore;
  final int positionAfter;
  final int size;

  const LeagueMatchDelta({
    required this.league,
    required this.points,
    required this.positionBefore,
    required this.positionAfter,
    this.size = 0,
  });

  bool get moved => positionBefore != positionAfter;

  static LeagueMatchDelta? fromJson(dynamic json) {
    final m = _map(json);
    final league = LeagueTier.fromJson(m['league']);
    final points = _int(m['points']);
    final before = _int(m['positionBefore']);
    final after = _int(m['positionAfter']);
    if (league == null || points <= 0 || before <= 0 || after <= 0) return null;
    return LeagueMatchDelta(
      league: league,
      points: points,
      positionBefore: before,
      positionAfter: after,
      size: _int(m['size']),
    );
  }
}
