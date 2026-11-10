import '../../models/progression.dart';
import 'logic/challenge_engine.dart';

// Daily challenge API models (docs/progression/CONTRACT.md §14.2). Every
// fromJson is defensive: a missing or mistyped field gives a default, so a
// newer backend never crashes this screen.

Map<String, dynamic> _map(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
List<dynamic> _list(dynamic v) => v is List ? v : const [];
int _int(dynamic v, [int fallback = 0]) =>
    v is num ? v.toInt() : (v is String ? int.tryParse(v) ?? fallback : fallback);
int? _intOrNull(dynamic v) => v is num ? v.toInt() : null;
String? _str(dynamic v) => v is String ? v : null;
bool _bool(dynamic v) => v == true;
DateTime? _date(dynamic v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;
List<String> _strings(dynamic v) => _list(v).whereType<String>().toList();

enum ChallengeRing { single, double, treble }

/// One selector of [ChallengeBoardSpec]: `numbers` null = the 20 numbers,
/// `rings` null = every ring.
class ChallengeBoardSelector {
  final List<int>? numbers;
  final List<ChallengeRing>? rings;
  const ChallengeBoardSelector({this.numbers, this.rings});

  bool covers(int number, ChallengeRing ring) =>
      (numbers == null || numbers!.contains(number)) && (rings == null || rings!.contains(ring));
}

/// The zones that count, lit on the format's small board (CONTRACT §14.10):
/// `{ "all": true }` or `{ "segments": [{ numbers?, rings? }], "bull": bool }`.
/// Absent or malformed = the whole board.
class ChallengeBoardSpec {
  final bool all;
  final List<ChallengeBoardSelector> segments;
  final bool bull;

  const ChallengeBoardSpec({this.all = false, this.segments = const [], this.bull = false});

  static const allLit = ChallengeBoardSpec(all: true);

  /// A zone is lit when a selector covers it.
  bool lit(int number, ChallengeRing ring) => all || segments.any((s) => s.covers(number, ring));

  bool get bullLit => all || bull;

  /// Lit somewhere on [number] (its label is then drawn bright).
  bool numberLit(int number) => ChallengeRing.values.any((r) => lit(number, r));

  static ChallengeBoardSpec? fromJson(dynamic json) {
    if (json is! Map) return null;
    if (json['all'] == true) return allLit;
    final raw = json['segments'];
    if (raw is! List) return null;
    final segments = <ChallengeBoardSelector>[];
    for (final s in raw) {
      if (s is! Map) continue;
      final n = s['numbers'];
      final r = s['rings'];
      if ((n != null && n is! List) || (r != null && r is! List)) continue;
      segments.add(ChallengeBoardSelector(
        numbers: n is List ? n.whereType<int>().where((x) => x >= 1 && x <= 20).toList() : null,
        rings: r is List
            ? [
                for (final x in r)
                  if (x == 'single') ChallengeRing.single else if (x == 'double') ChallengeRing.double else if (x == 'treble') ChallengeRing.treble,
              ]
            : null,
      ));
    }
    return ChallengeBoardSpec(segments: segments, bull: json['bull'] == true);
  }
}

/// One format (`defs.challenge_format` of the content, or the day's snapshot).
class ChallengeFormat {
  final String id;
  final LocalizedText name;
  final LocalizedText short;
  final LocalizedText rule;

  /// The rule in one line (« 15 à 20 et bull · triple = 3 »); null on a
  /// server older than §14.10 — the screen then shows [short].
  final LocalizedText? brief;

  /// The zones lit on the small board; the whole board when the server sent none.
  final ChallengeBoardSpec board;
  final LocalizedText? tag;
  final String mode;
  final String? trainingType;
  final Map<String, dynamic> params;

  /// What the day drew for everyone (the finishes of a checkout format).
  final Map<String, dynamic> dayParams;

  /// 'desc' = higher is better, 'asc' = lower (darts to finish).
  final String scoreOrder;
  final LocalizedText? unit;
  final int? max;
  final String tieOrder;
  final LocalizedText? tieLabel;
  final int? durationMin;

  const ChallengeFormat({
    required this.id,
    required this.name,
    required this.short,
    required this.rule,
    this.brief,
    this.board = ChallengeBoardSpec.allLit,
    this.tag,
    required this.mode,
    this.trainingType,
    this.params = const {},
    this.dayParams = const {},
    this.scoreOrder = 'desc',
    this.unit,
    this.max,
    this.tieOrder = 'desc',
    this.tieLabel,
    this.durationMin,
  });

  /// This app version knows how to play it.
  bool get playable => kChallengeModes.contains(mode);
  bool get lowerIsBetter => scoreOrder == 'asc';

  /// The cap of "fewest darts" formats: an unfinished session scores cap + 1.
  int? get cap => mode == 'atc' || mode == 'x01' ? _intOrNull(params['cap']) : null;

  static ChallengeFormat? fromJson(dynamic json) {
    final m = _map(json);
    final id = _str(m['id']);
    final mode = _str(m['mode']);
    if (id == null || mode == null) return null;
    final score = _map(m['score']);
    final tie = _map(m['tiebreak']);
    final name = LocalizedText.fromJson(m['name']);
    return ChallengeFormat(
      id: id,
      name: name,
      short: m['short'] is Map ? LocalizedText.fromJson(m['short']) : name,
      rule: LocalizedText.fromJson(m['rule']),
      brief: m['brief'] is Map ? LocalizedText.fromJson(m['brief']) : null,
      board: ChallengeBoardSpec.fromJson(m['board']) ?? ChallengeBoardSpec.allLit,
      tag: m['tag'] is Map ? LocalizedText.fromJson(m['tag']) : null,
      mode: mode,
      trainingType: _str(m['trainingType']),
      params: _map(m['params']),
      dayParams: _map(m['dayParams']),
      scoreOrder: _str(score['order']) == 'asc' ? 'asc' : 'desc',
      unit: score['unit'] is Map ? LocalizedText.fromJson(score['unit']) : null,
      max: _intOrNull(score['max']),
      tieOrder: _str(tie['order']) == 'asc' ? 'asc' : 'desc',
      tieLabel: tie['label'] is Map ? LocalizedText.fromJson(tie['label']) : null,
      durationMin: _intOrNull(m['durationMin']),
    );
  }
}

/// The rank board a player plays in today (own rank, or merged).
class ChallengeBoard {
  final String rank;
  final List<String> ranks;
  final bool open;
  final int players;
  final int eloBonus;

  const ChallengeBoard({
    this.rank = 'bronze',
    this.ranks = const [],
    this.open = false,
    this.players = 0,
    this.eloBonus = 0,
  });

  factory ChallengeBoard.fromJson(dynamic json) {
    final m = _map(json);
    final rank = _str(m['rank']) ?? 'bronze';
    final ranks = _strings(m['ranks']);
    return ChallengeBoard(
      rank: rank,
      ranks: ranks.isEmpty ? [rank] : ranks,
      open: _bool(m['open']),
      players: _int(m['players']),
      eloBonus: _int(m['eloBonus']),
    );
  }

  /// Merged with the ranks above (e.g. Gold + Platinum).
  bool get merged => ranks.length > 1;
}

class ChallengeRanked {
  final String id;
  final String status;
  final String? excludedReason;
  final int? score;
  final int? tiebreak;
  final bool finished;
  final int? position;
  final int? total;
  final int? rankPct;
  final bool proofRequired;
  final String proofStatus;

  const ChallengeRanked({
    required this.id,
    this.status = 'started',
    this.excludedReason,
    this.score,
    this.tiebreak,
    this.finished = false,
    this.position,
    this.total,
    this.rankPct,
    this.proofRequired = false,
    this.proofStatus = 'none',
  });

  static ChallengeRanked? fromJson(dynamic json) {
    final m = _map(json);
    final id = _str(m['id']);
    if (id == null) return null;
    return ChallengeRanked(
      id: id,
      status: _str(m['status']) ?? 'started',
      excludedReason: _str(m['excludedReason']),
      score: _intOrNull(m['score']),
      tiebreak: _intOrNull(m['tiebreak']),
      finished: _bool(m['finished']),
      position: _intOrNull(m['position']),
      total: _intOrNull(m['total']),
      rankPct: _intOrNull(m['rankPct']),
      proofRequired: _bool(m['proofRequired']),
      proofStatus: _str(m['proofStatus']) ?? 'none',
    );
  }

  bool get submitted => status == 'submitted';

  /// Started and never sent: the ranked attempt is spent.
  bool get abandoned => status == 'started';
  bool get excluded => status == 'excluded';
}

class ChallengeStreakDay {
  final String date;
  final bool played;
  final bool today;
  const ChallengeStreakDay({required this.date, this.played = false, this.today = false});
}

class ChallengeStreak {
  final int current;
  final int best;
  final bool freezeAvailable;
  final List<ChallengeStreakDay> days;

  const ChallengeStreak({
    this.current = 0,
    this.best = 0,
    this.freezeAvailable = false,
    this.days = const [],
  });

  factory ChallengeStreak.fromJson(dynamic json) {
    final m = _map(json);
    return ChallengeStreak(
      current: _int(m['current']),
      best: _int(m['best']),
      freezeAvailable: _bool(m['freezeAvailable']),
      days: [
        for (final d in _list(m['days']))
          if (_str(_map(d)['date']) != null)
            ChallengeStreakDay(
              date: _str(_map(d)['date'])!,
              played: _bool(_map(d)['played']),
              today: _bool(_map(d)['today']),
            ),
      ],
    );
  }
}

/// Yesterday's n°1 of my board (the public session entry point).
class ChallengeCrownRef {
  final String date;
  final String crownId;
  final String board;
  final String userId;
  final String username;
  final int score;
  final bool verified;

  const ChallengeCrownRef({
    required this.date,
    required this.crownId,
    required this.board,
    required this.userId,
    required this.username,
    required this.score,
    required this.verified,
  });

  static ChallengeCrownRef? fromJson(dynamic json) {
    final m = _map(json);
    final crownId = _str(m['crownId']);
    if (crownId == null) return null;
    return ChallengeCrownRef(
      date: _str(m['date']) ?? '',
      crownId: crownId,
      board: _str(m['board']) ?? 'bronze',
      userId: _str(m['userId']) ?? '',
      username: _str(m['username']) ?? '',
      score: _int(m['score']),
      verified: _bool(m['verified']),
    );
  }
}

class ChallengeProofRequest {
  final String attemptId;
  final String date;
  const ChallengeProofRequest(this.attemptId, this.date);
}

List<ChallengeProofRequest> _proofRequests(dynamic v) => [
      for (final r in _list(v))
        if (_str(_map(r)['attemptId']) != null)
          ChallengeProofRequest(_str(_map(r)['attemptId'])!, _str(_map(r)['date']) ?? ''),
    ];

/// GET /challenge/today.
class ChallengeToday {
  final String date;
  final DateTime? endsAt;
  final ChallengeFormat format;
  final ChallengeBoard board;
  final int players;
  final ChallengeRanked? ranked;
  final int practiceCount;
  final ChallengeStreak streak;
  final bool remind;
  final ChallengeCrownRef? yesterday;
  final List<ChallengeProofRequest> proofPending;

  const ChallengeToday({
    required this.date,
    this.endsAt,
    required this.format,
    this.board = const ChallengeBoard(),
    this.players = 0,
    this.ranked,
    this.practiceCount = 0,
    this.streak = const ChallengeStreak(),
    this.remind = true,
    this.yesterday,
    this.proofPending = const [],
  });

  static ChallengeToday? fromJson(dynamic json) {
    final m = _map(json);
    final format = ChallengeFormat.fromJson(m['format']);
    final date = _str(m['date']);
    if (format == null || date == null) return null;
    return ChallengeToday(
      date: date,
      endsAt: _date(m['endsAt']),
      format: format,
      board: ChallengeBoard.fromJson(m['board']),
      players: _int(m['players']),
      ranked: ChallengeRanked.fromJson(m['ranked']),
      practiceCount: _int(m['practiceCount']),
      streak: ChallengeStreak.fromJson(m['streak']),
      remind: m['remind'] != false,
      yesterday: ChallengeCrownRef.fromJson(m['yesterday']),
      proofPending: _proofRequests(m['proofPending']),
    );
  }

  /// The ranked attempt is still to play.
  bool get rankedAvailable => ranked == null;

  /// The day is over: this snapshot is never shown nor played (a failed
  /// reload once kept yesterday's « Jouer » on screen).
  bool get expired => endsAt != null && !DateTime.now().isBefore(endsAt!);

  ChallengeToday copyWith({bool? remind}) => ChallengeToday(
        date: date,
        endsAt: endsAt,
        format: format,
        board: board,
        players: players,
        ranked: ranked,
        practiceCount: practiceCount,
        streak: streak,
        remind: remind ?? this.remind,
        yesterday: yesterday,
        proofPending: proofPending,
      );
}

/// POST /challenge/attempts.
class ChallengeStart {
  final String attemptId;
  final bool ranked;
  final String date;
  final DateTime? endsAt;
  final ChallengeFormat format;

  const ChallengeStart({
    required this.attemptId,
    required this.ranked,
    required this.date,
    this.endsAt,
    required this.format,
  });

  static ChallengeStart? fromJson(dynamic json) {
    final m = _map(json);
    final id = _str(m['attemptId']);
    final format = ChallengeFormat.fromJson(m['format']);
    if (id == null || format == null) return null;
    return ChallengeStart(
      attemptId: id,
      ranked: _bool(m['ranked']),
      date: _str(m['date']) ?? '',
      endsAt: _date(m['endsAt']),
      format: format,
    );
  }
}

class ChallengeRow {
  final int position;
  final String userId;
  final String username;
  final String rank;
  final int score;
  final int tiebreak;
  final bool finished;
  final bool me;
  final bool crown;
  final PublicCosmetics? cosmetics;

  const ChallengeRow({
    required this.position,
    required this.userId,
    required this.username,
    this.rank = 'bronze',
    required this.score,
    this.tiebreak = 0,
    this.finished = true,
    this.me = false,
    this.crown = false,
    this.cosmetics,
  });

  static ChallengeRow? fromJson(dynamic json) {
    final m = _map(json);
    final userId = _str(m['userId']);
    if (userId == null) return null;
    return ChallengeRow(
      position: _int(m['position']),
      userId: userId,
      username: _str(m['username']) ?? '',
      rank: _str(m['rank']) ?? 'bronze',
      score: _int(m['score']),
      tiebreak: _int(m['tiebreak']),
      finished: m['finished'] != false,
      me: _bool(m['me']),
      crown: _bool(m['crown']),
      cosmetics: PublicCosmetics.fromJson(m['cosmetics']),
    );
  }
}

enum ChallengeView { rank, all, friends }

extension ChallengeViewApi on ChallengeView {
  String get api => switch (this) {
        ChallengeView.rank => 'rank',
        ChallengeView.all => 'all',
        ChallengeView.friends => 'friends',
      };
}

/// GET /challenge/leaderboard.
class ChallengeLeaderboard {
  final String date;
  final ChallengeView view;
  final bool closed;
  final ChallengeBoard board;
  final int countRank;
  final int countAll;
  final int countFriends;
  final List<ChallengeRow> rows;

  const ChallengeLeaderboard({
    required this.date,
    this.view = ChallengeView.rank,
    this.closed = false,
    this.board = const ChallengeBoard(),
    this.countRank = 0,
    this.countAll = 0,
    this.countFriends = 0,
    this.rows = const [],
  });

  factory ChallengeLeaderboard.fromJson(dynamic json) {
    final m = _map(json);
    final counts = _map(m['counts']);
    final view = switch (_str(m['view'])) {
      'all' => ChallengeView.all,
      'friends' => ChallengeView.friends,
      _ => ChallengeView.rank,
    };
    return ChallengeLeaderboard(
      date: _str(m['date']) ?? '',
      view: view,
      closed: _bool(m['closed']),
      board: ChallengeBoard.fromJson(m['board']),
      countRank: _int(counts['rank']),
      countAll: _int(counts['all']),
      countFriends: _int(counts['friends']),
      rows: _list(m['rows']).map(ChallengeRow.fromJson).whereType<ChallengeRow>().toList(),
    );
  }
}

class ChallengeStanding {
  final String board;
  final List<String> ranks;
  final bool open;
  final int position;
  final int total;
  final int rankPct;
  final bool top10;
  final int allPosition;
  final int allTotal;
  final int eloBonus;

  const ChallengeStanding({
    required this.board,
    this.ranks = const [],
    this.open = false,
    required this.position,
    required this.total,
    this.rankPct = 100,
    this.top10 = false,
    this.allPosition = 0,
    this.allTotal = 0,
    this.eloBonus = 0,
  });

  static ChallengeStanding? fromJson(dynamic json) {
    final m = _map(json);
    final board = _str(m['board']);
    if (board == null) return null;
    return ChallengeStanding(
      board: board,
      ranks: _strings(m['ranks']),
      open: _bool(m['open']),
      position: _int(m['position']),
      total: _int(m['total']),
      rankPct: _int(m['rankPct'], 100),
      top10: _bool(m['top10']),
      allPosition: _int(m['allPosition']),
      allTotal: _int(m['allTotal']),
      eloBonus: _int(m['eloBonus']),
    );
  }
}

class ChallengeNamedScore {
  final String username;
  final int score;
  const ChallengeNamedScore(this.username, this.score);

  static ChallengeNamedScore? fromJson(dynamic json) {
    final m = _map(json);
    final name = _str(m['username']);
    if (name == null) return null;
    return ChallengeNamedScore(name, _int(m['score']));
  }
}

/// The result of an attempt (answer of submit, and GET /challenge/attempts/:id).
class ChallengeResult {
  final String date;
  final DateTime? endsAt;
  final bool closed;
  final ChallengeFormat format;
  final String attemptId;
  final bool ranked;
  final String status;
  final int score;
  final int tiebreak;
  final bool finished;
  final int darts;
  final List<int> perVisit;
  final Map<String, dynamic> details;
  final ChallengeStanding? standing;
  final List<ChallengeNamedScore> passed;
  final ChallengeNamedScore? leader;
  final int streak;
  final int bestStreak;
  final int xp;
  final bool proofRequired;
  final String proofStatus;

  const ChallengeResult({
    required this.date,
    this.endsAt,
    this.closed = false,
    required this.format,
    required this.attemptId,
    required this.ranked,
    this.status = 'submitted',
    required this.score,
    this.tiebreak = 0,
    this.finished = true,
    this.darts = 0,
    this.perVisit = const [],
    this.details = const {},
    this.standing,
    this.passed = const [],
    this.leader,
    this.streak = 0,
    this.bestStreak = 0,
    this.xp = 0,
    this.proofRequired = false,
    this.proofStatus = 'none',
  });

  static ChallengeResult? fromJson(dynamic json) {
    final m = _map(json);
    final format = ChallengeFormat.fromJson(m['format']);
    final a = _map(m['attempt']);
    final id = _str(a['id']);
    if (format == null || id == null) return null;
    final streak = _map(m['streak']);
    final proof = _map(m['proof']);
    return ChallengeResult(
      date: _str(m['date']) ?? '',
      endsAt: _date(m['endsAt']),
      closed: _bool(m['closed']),
      format: format,
      attemptId: id,
      ranked: _bool(a['ranked']),
      status: _str(a['status']) ?? 'submitted',
      score: _int(a['score']),
      tiebreak: _int(a['tiebreak']),
      finished: _bool(a['finished']),
      darts: _int(a['darts']),
      perVisit: _list(a['perVisit']).whereType<num>().map((e) => e.toInt()).toList(),
      details: _map(a['details']),
      standing: ChallengeStanding.fromJson(m['standing']),
      passed: _list(m['passed']).map(ChallengeNamedScore.fromJson).whereType<ChallengeNamedScore>().toList(),
      leader: ChallengeNamedScore.fromJson(m['leader']),
      streak: _int(streak['current']),
      bestStreak: _int(streak['best']),
      xp: _list(m['xp']).fold<int>(0, (s, e) => s + _int(_map(e)['amount'])),
      proofRequired: _bool(proof['required']),
      proofStatus: _str(proof['status']) ?? 'none',
    );
  }

  /// Best visit of a score max, for the "best visit: 140" line.
  int? get bestVisit => format.mode == 'high_score' && perVisit.isNotEmpty
      ? perVisit.reduce((a, b) => a > b ? a : b)
      : null;
}

class ChallengePodiumCrown {
  final String crownId;
  final String userId;
  final String? username;
  final int? score;
  final String status;
  final bool verified;
  final int aiDarts;
  final int correctedDarts;
  final int darts;

  const ChallengePodiumCrown({
    required this.crownId,
    required this.userId,
    this.username,
    this.score,
    this.status = 'auto_ok',
    this.verified = false,
    this.aiDarts = 0,
    this.correctedDarts = 0,
    this.darts = 0,
  });

  static ChallengePodiumCrown? fromJson(dynamic json) {
    final m = _map(json);
    final id = _str(m['crownId']);
    if (id == null) return null;
    return ChallengePodiumCrown(
      crownId: id,
      userId: _str(m['userId']) ?? '',
      username: _str(m['username']),
      score: _intOrNull(m['score']),
      status: _str(m['status']) ?? 'auto_ok',
      verified: _bool(m['verified']),
      aiDarts: _int(m['aiDarts']),
      correctedDarts: _int(m['correctedDarts']),
      darts: _int(m['darts']),
    );
  }
}

class ChallengePodiumMe {
  final String status;
  final int? score;
  final int? position;
  final int? total;
  final bool top10;
  final int xp;
  final bool crowned;
  final bool crownPaid;
  final int eloBonus;
  final int badgeCount;

  const ChallengePodiumMe({
    this.status = 'submitted',
    this.score,
    this.position,
    this.total,
    this.top10 = false,
    this.xp = 0,
    this.crowned = false,
    this.crownPaid = false,
    this.eloBonus = 0,
    this.badgeCount = 0,
  });

  static ChallengePodiumMe? fromJson(dynamic json) {
    if (json is! Map) return null;
    final m = _map(json);
    final crown = m['crown'] is Map ? _map(m['crown']) : null;
    return ChallengePodiumMe(
      status: _str(m['status']) ?? 'submitted',
      score: _intOrNull(m['score']),
      position: _intOrNull(m['position']),
      total: _intOrNull(m['total']),
      top10: _bool(m['top10']),
      xp: _int(m['xp']),
      crowned: crown != null,
      crownPaid: crown != null && _bool(crown['paid']),
      eloBonus: crown == null ? 0 : _int(crown['eloPaid'] ?? crown['eloBonus']),
      badgeCount: crown == null ? 0 : _int(crown['badgeCount']),
    );
  }
}

/// GET /challenge/podium: yesterday's final result of my board.
class ChallengePodium {
  final String date;
  final bool available;
  final bool closed;
  final ChallengeFormat? format;
  final ChallengeBoard board;
  final int eloBonus;
  final ChallengePodiumCrown? crown;
  final List<ChallengeRow> top;
  final ChallengePodiumMe? me;

  const ChallengePodium({
    required this.date,
    this.available = false,
    this.closed = false,
    this.format,
    this.board = const ChallengeBoard(),
    this.eloBonus = 0,
    this.crown,
    this.top = const [],
    this.me,
  });

  factory ChallengePodium.fromJson(dynamic json) {
    final m = _map(json);
    return ChallengePodium(
      date: _str(m['date']) ?? '',
      available: _bool(m['available']),
      closed: _bool(m['closed']),
      format: ChallengeFormat.fromJson(m['format']),
      board: ChallengeBoard.fromJson(m['board']),
      eloBonus: _int(m['eloBonus']),
      crown: ChallengePodiumCrown.fromJson(m['crown']),
      top: _list(m['top']).map(ChallengeRow.fromJson).whereType<ChallengeRow>().toList(),
      me: ChallengePodiumMe.fromJson(m['me']),
    );
  }
}

class ChallengeSessionDart {
  final String notation;
  final bool ai;
  final bool fixed;
  const ChallengeSessionDart(this.notation, {this.ai = false, this.fixed = false});
}

class ChallengeSessionVisit {
  /// Phone wall clock (ms) when the visit was confirmed.
  final int? t;
  final List<ChallengeSessionDart> darts;
  final int? value;
  const ChallengeSessionVisit({this.t, this.darts = const [], this.value});

  bool get corrected => darts.any((d) => d.fixed);
}

class ChallengeClip {
  final String url;
  final int? startWallMs;
  final int? durationMs;
  const ChallengeClip(this.url, {this.startWallMs, this.durationMs});
}

/// GET /challenge/sessions/:crownId — the public session of a n°1.
class ChallengeSession {
  final String crownId;
  final String date;
  final String board;
  final ChallengeFormat? format;
  final String userId;
  final String username;
  final String rank;
  final PublicCosmetics? cosmetics;
  final int score;
  final bool finished;
  final int darts;
  final int aiDarts;
  final int correctedDarts;
  final bool verified;
  final List<ChallengeSessionVisit> visits;
  final List<ChallengeClip> clips;
  final bool reportable;
  final bool reported;

  const ChallengeSession({
    required this.crownId,
    required this.date,
    required this.board,
    this.format,
    required this.userId,
    required this.username,
    this.rank = 'bronze',
    this.cosmetics,
    required this.score,
    this.finished = true,
    this.darts = 0,
    this.aiDarts = 0,
    this.correctedDarts = 0,
    this.verified = false,
    this.visits = const [],
    this.clips = const [],
    this.reportable = false,
    this.reported = false,
  });

  static ChallengeSession? fromJson(dynamic json) {
    final m = _map(json);
    final crownId = _str(m['crownId']);
    if (crownId == null) return null;
    final player = _map(m['player']);
    return ChallengeSession(
      crownId: crownId,
      date: _str(m['date']) ?? '',
      board: _str(m['board']) ?? 'bronze',
      format: ChallengeFormat.fromJson(m['format']),
      userId: _str(player['userId']) ?? '',
      username: _str(player['username']) ?? '',
      rank: _str(player['rank']) ?? 'bronze',
      cosmetics: PublicCosmetics.fromJson(player['cosmetics']),
      score: _int(m['score']),
      finished: m['finished'] != false,
      darts: _int(m['darts']),
      aiDarts: _int(m['aiDarts']),
      correctedDarts: _int(m['correctedDarts']),
      verified: _bool(m['verified']),
      visits: [
        for (final v in _list(m['visits']))
          ChallengeSessionVisit(
            t: _intOrNull(_map(v)['t']),
            value: _intOrNull(_map(v)['value']),
            darts: [
              for (final d in _list(_map(v)['darts']))
                if (_str(_map(d)['n']) != null)
                  ChallengeSessionDart(
                    _str(_map(d)['n'])!,
                    ai: _bool(_map(d)['ai']),
                    fixed: _bool(_map(d)['fix']),
                  ),
            ],
          ),
      ],
      clips: [
        for (final c in _list(m['clips']))
          if (_str(_map(c)['url']) != null)
            ChallengeClip(
              _str(_map(c)['url'])!,
              startWallMs: _intOrNull(_map(c)['startWallMs']),
              durationMs: _intOrNull(_map(c)['durationMs']),
            ),
      ],
      reportable: _bool(m['reportable']),
      reported: _bool(m['reported']),
    );
  }
}

/// One dart of the attempt being played, as sent to the server.
class ChallengeThrow {
  final ChallengeDart dart;

  /// Read by the AI camera.
  final bool ai;

  /// Set or changed by hand (edit sheet).
  final bool fixed;

  const ChallengeThrow(this.dart, {this.ai = false, this.fixed = false});

  Map<String, dynamic> toJson() => {
        'n': dart.notation,
        'ai': ai,
        if (fixed) 'fix': true,
      };
}

class ChallengeVisitRecord {
  /// Wall clock (ms) when the visit was confirmed.
  final int t;
  final List<ChallengeThrow> darts;
  const ChallengeVisitRecord(this.t, this.darts);

  Map<String, dynamic> toJson() => {
        't': t,
        'darts': darts.map((d) => d.toJson()).toList(),
      };
}
