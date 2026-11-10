/// Daily challenge scoring engine — the app's twin of
/// backend/src/challenge/engine/challenge-engine.ts.
///
/// The server replays the darts of every attempt and keeps ITS score; this
/// copy only drives the live display (target, remaining, total) and the end
/// of the session. Both sides are checked against the same vectors
/// (test/challenge_vectors.json, a copy of the backend's).
library;

class ChallengeDart {
  /// 0 = miss, 1–20, 25 = bull.
  final int segment;

  /// 0 miss, 1 single, 2 double, 3 triple. Bull: 1 = 25, 2 = 50.
  final int mult;
  final int points;

  const ChallengeDart(this.segment, this.mult, this.points);

  static const miss = ChallengeDart(0, 0, 0);

  /// Canonical notation sent to the server: M, S20, D20, T20, SB, DB.
  String get notation {
    if (mult == 0 || segment == 0) return 'M';
    if (segment == 25) return mult == 2 ? 'DB' : 'SB';
    return '${const ['', 'S', 'D', 'T'][mult]}$segment';
  }

  @override
  bool operator ==(Object other) =>
      other is ChallengeDart && other.segment == segment && other.mult == mult;

  @override
  int get hashCode => Object.hash(segment, mult);
}

/// Parses 'M' / 'S0' (miss), 'S20' 'D20' 'T20', 'B' / 'SB' / 'S25' (25),
/// 'DB' / 'D25' / 'BULL' / '50' (50). Null when it is not a dart.
ChallengeDart? parseChallengeDart(String? raw) {
  if (raw == null) return null;
  final n = raw.trim().toUpperCase();
  if (n == 'M' || n == 'MISS' || n == 'S0' || n == '0') return ChallengeDart.miss;
  if (n == 'B' || n == 'SB' || n == 'S25' || n == '25') return const ChallengeDart(25, 1, 25);
  if (n == 'DB' || n == 'D25' || n == 'BULL' || n == '50') return const ChallengeDart(25, 2, 50);
  final m = RegExp(r'^([SDT])(\d{1,2})$').firstMatch(n);
  if (m == null) return null;
  final segment = int.parse(m.group(2)!);
  if (segment < 1 || segment > 20) return null;
  final mult = m.group(1) == 'S' ? 1 : (m.group(1) == 'D' ? 2 : 3);
  return ChallengeDart(segment, mult, segment * mult);
}

/// The modes this app version can play. A format whose mode is not listed
/// is shown with an "update the app" message instead of the play button.
const kChallengeModes = {
  'high_score',
  'target_points',
  'bobs_27',
  'doubles_block',
  'atc',
  'checkout_set',
  'x01',
  'shanghai',
  'halve_it',
  'jdc',
  'cricket_marks',
};

class ChallengeEngineResult {
  final int score;
  final int tiebreak;
  final int darts;
  final int visits;
  final bool finished;
  final List<int> perVisit;

  /// Where the session stands, for the live display (app only): `target`
  /// (the current target value, 25 = bull), `targetIndex`, `targetCount`,
  /// `remaining`, `finishIndex`, `finishCount`, `budgetUsed`…
  final Map<String, Object?> cursor;

  const ChallengeEngineResult({
    required this.score,
    required this.tiebreak,
    required this.darts,
    required this.visits,
    required this.finished,
    required this.perVisit,
    this.cursor = const {},
  });
}

num _num(Object? v, num fallback) {
  if (v is num) return v;
  if (v is String) return num.tryParse(v) ?? fallback;
  return fallback;
}

List<int> _intList(Object? v, List<int> fallback) {
  if (v is List && v.every((x) => x is num)) {
    return v.map((x) => (x as num).toInt()).toList();
  }
  return fallback;
}

final List<int> _oneToTwenty = List.generate(20, (i) => i + 1);

/// Pads to 3 darts with misses — except a live, unfinished last visit.
List<ChallengeDart> _three(List<ChallengeDart> visit, {bool pad = true}) {
  final out = visit.take(3).toList();
  if (pad) {
    while (out.length < 3) {
      out.add(ChallengeDart.miss);
    }
  }
  return out;
}

class _X01Visit {
  final int remaining;
  final int scored;
  final int darts;
  final bool busted;
  final bool checkedOut;
  const _X01Visit(this.remaining, this.scored, this.darts, this.busted, this.checkedOut);
}

_X01Visit _x01Visit(int remaining, List<ChallengeDart> visit, {bool doubleOut = true}) {
  var rem = remaining;
  var darts = 0;
  for (final d in visit) {
    darts++;
    final next = rem - d.points;
    if (next < 0 || (doubleOut && next == 1) || (next == 0 && doubleOut && d.mult != 2)) {
      return _X01Visit(remaining, 0, darts, true, false);
    }
    rem = next;
    if (rem == 0) return _X01Visit(0, remaining, darts, false, true);
  }
  return _X01Visit(rem, remaining - rem, darts, false, false);
}

/// Runs the darts of a session through a mode. Null for an unknown mode.
/// [partialLast]: the last visit is still being thrown (live display) — it
/// is not padded with misses.
ChallengeEngineResult? runChallengeEngine(
  String mode,
  Map<String, dynamic> params,
  Map<String, dynamic> day,
  List<List<ChallengeDart>> visits, {
  bool partialLast = false,
}) {
  List<ChallengeDart> visitAt(int i) =>
      _three(visits[i], pad: !(partialLast && i == visits.length - 1));
  switch (mode) {
    case 'high_score':
      return _highScore(params, visits.length, visitAt);
    case 'target_points':
      return _targetPoints(params, visits.length, visitAt);
    case 'bobs_27':
      return _bobs27(params, visits.length, visitAt);
    case 'doubles_block':
      return _doublesBlock(params, visits.length, visitAt);
    case 'atc':
      return _atc(params, visits.length, visitAt);
    case 'checkout_set':
      return _checkoutSet(params, day, visits.length, visitAt);
    case 'x01':
      return _x01(params, visits.length, visitAt);
    case 'shanghai':
      return _shanghai(params, visits.length, visitAt);
    case 'halve_it':
      return _halveIt(params, visits.length, visitAt);
    case 'jdc':
      return _jdc(visits.length, visitAt);
    case 'cricket_marks':
      return _cricket(params, visits.length, visitAt);
  }
  return null;
}

typedef _VisitAt = List<ChallengeDart> Function(int i);

ChallengeEngineResult _highScore(Map<String, dynamic> p, int count, _VisitAt at) {
  final n = _num(p['visits'], 5).toInt().clamp(1, 1000);
  final perVisit = <int>[];
  for (var i = 0; i < count && i < n; i++) {
    perVisit.add(at(i).fold<int>(0, (s, d) => s + d.points));
  }
  final best = perVisit.isEmpty ? 0 : perVisit.reduce((a, b) => a > b ? a : b);
  return ChallengeEngineResult(
    score: perVisit.fold(0, (a, b) => a + b),
    tiebreak: best,
    darts: perVisit.length * 3,
    visits: perVisit.length,
    finished: perVisit.length >= n,
    perVisit: perVisit,
    cursor: {'visitIndex': perVisit.length, 'visitCount': n},
  );
}

ChallengeEngineResult _targetPoints(Map<String, dynamic> p, int count, _VisitAt at) {
  final total = _num(p['darts'], 21).toInt().clamp(1, 1000);
  final segment = _num(p['segment'], 20).toInt();
  var darts = 0, score = 0, tiebreak = 0;
  final perVisit = <int>[];
  for (var i = 0; i < count; i++) {
    if (darts >= total) break;
    var v = 0;
    for (final d in at(i)) {
      if (darts >= total) break;
      darts++;
      if (d.segment != segment) continue;
      v += d.points;
      if (segment == 25 ? d.mult == 2 : d.mult == 3) tiebreak++;
    }
    score += v;
    perVisit.add(v);
  }
  return ChallengeEngineResult(
    score: score,
    tiebreak: tiebreak,
    darts: darts,
    visits: perVisit.length,
    finished: darts >= total,
    perVisit: perVisit,
    cursor: {'target': segment, 'dartCount': total},
  );
}

ChallengeEngineResult _bobs27(Map<String, dynamic> p, int count, _VisitAt at) {
  final targets = _intList(p['targets'], [..._oneToTwenty, 25]);
  var score = _num(p['start'], 27).toInt();
  var hitsTotal = 0;
  var out = false;
  final perVisit = <int>[];
  for (var i = 0; i < count; i++) {
    if (perVisit.length >= targets.length || out) break;
    final target = targets[perVisit.length];
    final value = target == 25 ? 50 : target * 2;
    final hits = at(i).where((d) => d.segment == target && d.mult == 2).length;
    final delta = hits > 0 ? value * hits : -value;
    score += delta;
    hitsTotal += hits;
    perVisit.add(delta);
    if (score <= 0) out = true;
  }
  final idx = perVisit.length;
  return ChallengeEngineResult(
    score: score,
    tiebreak: hitsTotal,
    darts: perVisit.length * 3,
    visits: perVisit.length,
    finished: out || perVisit.length >= targets.length,
    perVisit: perVisit,
    cursor: {
      'targetIndex': idx,
      'targetCount': targets.length,
      'target': idx < targets.length ? targets[idx] : null,
      'ring': 'double',
    },
  );
}

ChallengeEngineResult _doublesBlock(Map<String, dynamic> p, int count, _VisitAt at) {
  final targets = _intList(p['targets'], [20, 16, 8]);
  final per = _num(p['dartsPer'], 10).toInt().clamp(1, 1000);
  final total = targets.length * per;
  var darts = 0, hits = 0, firstHit = 0;
  final perVisit = <int>[];
  for (var i = 0; i < count; i++) {
    if (darts >= total) break;
    var v = 0;
    for (final d in at(i)) {
      if (darts >= total) break;
      final target = targets[darts ~/ per];
      darts++;
      if (d.segment == target && d.mult == 2) {
        v++;
        hits++;
        if (firstHit == 0) firstHit = darts;
      }
    }
    perVisit.add(v);
  }
  return ChallengeEngineResult(
    score: hits,
    tiebreak: firstHit == 0 ? total + 1 : firstHit,
    darts: darts,
    visits: perVisit.length,
    finished: darts >= total,
    perVisit: perVisit,
    cursor: {
      'target': darts < total ? targets[darts ~/ per] : null,
      'ring': 'double',
      'dartCount': total,
    },
  );
}

ChallengeEngineResult _atc(Map<String, dynamic> p, int count, _VisitAt at) {
  final targets = _intList(p['targets'], [..._oneToTwenty, 25]);
  final ring = p['ring'] is String ? p['ring'] as String : 'any';
  final cap = _num(p['cap'], 99).toInt().clamp(1, 10000);
  bool hits(ChallengeDart d, int t) {
    if (d.segment != t || d.mult == 0) return false;
    if (ring == 'any') return true;
    if (t == 25) return d.mult == 2;
    return ring == 'double' ? d.mult == 2 : d.mult == 3;
  }

  var idx = 0, darts = 0;
  final perVisit = <int>[];
  for (var i = 0; i < count; i++) {
    if (idx >= targets.length || darts >= cap) break;
    var v = 0;
    for (final d in at(i)) {
      if (idx >= targets.length || darts >= cap) break;
      darts++;
      if (hits(d, targets[idx])) {
        idx++;
        v++;
      }
    }
    perVisit.add(v);
  }
  final completed = idx >= targets.length;
  return ChallengeEngineResult(
    score: completed ? darts : cap + 1,
    tiebreak: idx,
    darts: darts,
    visits: perVisit.length,
    finished: completed || darts >= cap,
    perVisit: perVisit,
    cursor: {
      'targetIndex': idx,
      'targetCount': targets.length,
      'target': idx < targets.length ? targets[idx] : null,
      'ring': ring,
      'cap': cap,
      'completed': completed,
    },
  );
}

ChallengeEngineResult _checkoutSet(
  Map<String, dynamic> p,
  Map<String, dynamic> day,
  int count,
  _VisitAt at,
) {
  final finishes = _intList(day['finishes'], const []);
  final budget = ((_num(p['darts'], 9) / 3).ceil() * 3).clamp(3, 300);
  final catch40 = p['scoring'] == 'catch40';
  var score = 0, tiebreak = 0, totalDarts = 0, i = 0, used = 0;
  var rem = finishes.isNotEmpty ? finishes[0] : 0;
  final perVisit = <int>[];
  void close(bool success) {
    if (success) {
      score += catch40 ? (used <= 2 ? 3 : (used == 3 ? 2 : 1)) : finishes[i];
      if (catch40) tiebreak += used;
    } else {
      tiebreak += catch40 ? used : rem;
    }
    i++;
    rem = i < finishes.length ? finishes[i] : 0;
    used = 0;
  }

  for (var k = 0; k < count; k++) {
    if (i >= finishes.length) break;
    final r = _x01Visit(rem, at(k));
    final thrown = r.checkedOut ? r.darts : 3;
    used += thrown;
    totalDarts += thrown;
    rem = r.remaining;
    perVisit.add(r.scored);
    if (r.checkedOut) {
      close(true);
    } else if (used >= budget) {
      close(false);
    }
  }
  return ChallengeEngineResult(
    score: score,
    tiebreak: tiebreak,
    darts: totalDarts,
    visits: perVisit.length,
    finished: finishes.isNotEmpty && i >= finishes.length,
    perVisit: perVisit,
    cursor: {
      'finishIndex': i,
      'finishCount': finishes.length,
      'remaining': rem,
      'budgetUsed': used,
      'budget': budget,
    },
  );
}

ChallengeEngineResult _x01(Map<String, dynamic> p, int count, _VisitAt at) {
  final start = _num(p['start'], 501).toInt().clamp(2, 100000);
  final cap = _num(p['cap'], 45).toInt().clamp(3, 10000);
  final doubleOut = p['doubleOut'] != false;
  var rem = start, darts = 0, first9 = 0;
  var checkedOut = false;
  final perVisit = <int>[];
  for (var i = 0; i < count; i++) {
    if (checkedOut || darts >= cap) break;
    final allowed = (cap - darts) < 3 ? cap - darts : 3;
    final visit = at(i).take(allowed).toList();
    final r = _x01Visit(rem, visit, doubleOut: doubleOut);
    final thrown = r.checkedOut ? r.darts : (visit.length < allowed ? visit.length : allowed);
    darts += thrown;
    if (perVisit.length < 3) first9 += r.scored;
    rem = r.remaining;
    checkedOut = r.checkedOut;
    perVisit.add(r.scored);
  }
  return ChallengeEngineResult(
    score: checkedOut ? darts : cap + 1,
    tiebreak: first9,
    darts: darts,
    visits: perVisit.length,
    finished: checkedOut || darts >= cap,
    perVisit: perVisit,
    cursor: {'remaining': rem, 'cap': cap, 'completed': checkedOut},
  );
}

ChallengeEngineResult _shanghai(Map<String, dynamic> p, int count, _VisitAt at) {
  final from = _num(p['from'], 10).toInt();
  final to = _num(p['to'], 20).toInt();
  final targets = [for (var t = from; t <= to; t++) t];
  var score = 0, triples = 0;
  final perVisit = <int>[];
  for (var i = 0; i < count; i++) {
    if (perVisit.length >= targets.length) break;
    final t = targets[perVisit.length];
    var v = 0;
    for (final d in at(i)) {
      if (d.segment != t) continue;
      v += d.points;
      if (d.mult == 3) triples++;
    }
    score += v;
    perVisit.add(v);
  }
  final idx = perVisit.length;
  return ChallengeEngineResult(
    score: score,
    tiebreak: triples,
    darts: perVisit.length * 3,
    visits: perVisit.length,
    finished: perVisit.length >= targets.length,
    perVisit: perVisit,
    cursor: {
      'targetIndex': idx,
      'targetCount': targets.length,
      'target': idx < targets.length ? targets[idx] : null,
      'ring': 'any',
    },
  );
}

const _defaultHalveTargets = [
  {'n': 20},
  {'n': 16},
  {'ring': 'double'},
  {'n': 17},
  {'ring': 'triple'},
  {'n': 18},
  {'n': 19},
  {'n': 25},
];

ChallengeEngineResult _halveIt(Map<String, dynamic> p, int count, _VisitAt at) {
  final raw = p['targets'];
  final targets = raw is List
      ? raw.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList()
      : _defaultHalveTargets.map((m) => Map<String, dynamic>.from(m)).toList();
  var score = _num(p['start'], 0).toInt();
  var hitTargets = 0;
  final perVisit = <int>[];
  bool hits(ChallengeDart d, Map<String, dynamic> t) {
    if (d.mult == 0) return false;
    if (t['ring'] == 'double') return d.mult == 2;
    if (t['ring'] == 'triple') return d.mult == 3;
    return d.segment == _num(t['n'], -1).toInt();
  }

  for (var i = 0; i < count; i++) {
    if (perVisit.length >= targets.length) break;
    final t = targets[perVisit.length];
    final scoring = at(i).where((d) => hits(d, t)).toList();
    if (scoring.isEmpty) {
      final halved = score ~/ 2;
      perVisit.add(halved - score);
      score = halved;
    } else {
      final v = scoring.fold<int>(0, (s, d) => s + d.points);
      score += v;
      hitTargets++;
      perVisit.add(v);
    }
  }
  final idx = perVisit.length;
  return ChallengeEngineResult(
    score: score,
    tiebreak: hitTargets,
    darts: perVisit.length * 3,
    visits: perVisit.length,
    finished: perVisit.length >= targets.length,
    perVisit: perVisit,
    cursor: {
      'targetIndex': idx,
      'targetCount': targets.length,
      'halveTarget': idx < targets.length ? targets[idx] : null,
    },
  );
}

const _jdcPart1 = [10, 11, 12, 13, 14, 15];
const _jdcPart3 = [15, 16, 17, 18, 19, 20];
final List<int> _jdcDoubles = [..._oneToTwenty, 25];

ChallengeEngineResult _jdc(int count, _VisitAt at) {
  const total = 19;
  var score = 0, doubles = 0;
  final perVisit = <int>[];
  for (var i = 0; i < count; i++) {
    final k = perVisit.length;
    if (k >= total) break;
    final darts = at(i);
    var v = 0;
    if (k < 6 || k >= 13) {
      final t = k < 6 ? _jdcPart1[k] : _jdcPart3[k - 13];
      final kinds = <int>{};
      for (final d in darts) {
        if (d.segment != t) continue;
        v += d.points;
        kinds.add(d.mult);
      }
      if (kinds.contains(1) && kinds.contains(2) && kinds.contains(3)) v += 100;
    } else {
      final start = (k - 6) * 3;
      for (var j = 0; j < darts.length; j++) {
        final t = _jdcDoubles[start + j];
        final d = darts[j];
        if (d.segment == t && d.mult == 2) {
          v += t == 25 ? 100 : 50;
          doubles++;
        }
      }
    }
    score += v;
    perVisit.add(v);
  }
  final k = perVisit.length;
  final List<int> targets;
  if (k >= total) {
    targets = const [];
  } else if (k < 6) {
    targets = [_jdcPart1[k]];
  } else if (k >= 13) {
    targets = [_jdcPart3[k - 13]];
  } else {
    targets = _jdcDoubles.sublist((k - 6) * 3, (k - 6) * 3 + 3);
  }
  return ChallengeEngineResult(
    score: score,
    tiebreak: doubles,
    darts: perVisit.length * 3,
    visits: perVisit.length,
    finished: perVisit.length >= total,
    perVisit: perVisit,
    cursor: {
      'targetIndex': k,
      'targetCount': total,
      'targets': targets,
      'ring': k >= 6 && k < 13 ? 'double' : 'any',
    },
  );
}

ChallengeEngineResult _cricket(Map<String, dynamic> p, int count, _VisitAt at) {
  final total = _num(p['darts'], 30).toInt().clamp(1, 1000);
  final numbers = _intList(p['numbers'], [15, 16, 17, 18, 19, 20, 25]);
  var darts = 0, marks = 0, bull = 0;
  final perVisit = <int>[];
  for (var i = 0; i < count; i++) {
    if (darts >= total) break;
    var v = 0;
    for (final d in at(i)) {
      if (darts >= total) break;
      darts++;
      if (!numbers.contains(d.segment) || d.mult == 0) continue;
      v += d.mult;
      if (d.segment == 25) bull += d.mult;
    }
    marks += v;
    perVisit.add(v);
  }
  return ChallengeEngineResult(
    score: marks,
    tiebreak: bull,
    darts: darts,
    visits: perVisit.length,
    finished: darts >= total,
    perVisit: perVisit,
    cursor: {'dartCount': total},
  );
}
