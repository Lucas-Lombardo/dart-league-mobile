import '../../models/progression.dart';

/// JSON models of the /ghost API (docs/progression/CONTRACT.md §14.5).
/// Every `fromJson` is defensive: a missing or mistyped field gives a safe
/// default, never a crash — the backend may grow fields an old app ignores.

int _int(dynamic v, [int fallback = 0]) =>
    v is num ? v.toInt() : (v is String ? int.tryParse(v) ?? fallback : fallback);

int? _intOrNull(dynamic v) => v is num ? v.toInt() : null;

double _double(dynamic v, [double fallback = 0]) =>
    v is num ? v.toDouble() : (v is String ? double.tryParse(v) ?? fallback : fallback);

double? _doubleOrNull(dynamic v) => v is num ? v.toDouble() : null;

String _string(dynamic v, [String fallback = '']) => v is String ? v : fallback;

bool _bool(dynamic v, [bool fallback = false]) => v is bool ? v : fallback;

DateTime? _date(dynamic v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;

List<Map<String, dynamic>> _maps(dynamic v) => v is List
    ? v.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList()
    : const [];

/// The ghost's player, as the screens show them.
class GhostOpponent {
  final String? ownerId;
  final String username;
  final int elo;
  final String rank;
  final PublicCosmetics? cosmetics;
  final DateTime? playedAt;
  final double average;

  const GhostOpponent({
    this.ownerId,
    required this.username,
    required this.elo,
    required this.rank,
    this.cosmetics,
    this.playedAt,
    this.average = 0,
  });

  factory GhostOpponent.fromJson(dynamic json) {
    final j = json is Map ? Map<String, dynamic>.from(json) : <String, dynamic>{};
    return GhostOpponent(
      ownerId: j['ownerId'] is String ? j['ownerId'] as String : null,
      username: _string(j['username'], '—'),
      elo: _int(j['elo']),
      rank: _string(j['rank'], 'unranked'),
      cosmetics: PublicCosmetics.fromJson(j['cosmetics']),
      playedAt: _date(j['playedAt']),
      average: _double(j['average']),
    );
  }
}

class GhostOffer {
  final String id;
  final DateTime? expiresAt;
  final GhostOpponent ghost;
  final int bestOf;
  final bool eloEligible;
  final int eloMatchesLeft;
  final int eloIfWin;
  final int eloIfLoss;

  const GhostOffer({
    required this.id,
    this.expiresAt,
    required this.ghost,
    this.bestOf = 3,
    this.eloEligible = true,
    this.eloMatchesLeft = 0,
    this.eloIfWin = 0,
    this.eloIfLoss = 0,
  });

  static GhostOffer? fromJson(dynamic json) {
    if (json is! Map) return null;
    final j = Map<String, dynamic>.from(json);
    final id = j['id'];
    if (id is! String || id.isEmpty) return null;
    return GhostOffer(
      id: id,
      expiresAt: _date(j['expiresAt']),
      ghost: GhostOpponent.fromJson(j['ghost']),
      bestOf: _int(j['bestOf'], 3),
      eloEligible: _bool(j['eloEligible'], true),
      eloMatchesLeft: _int(j['eloMatchesLeft']),
      eloIfWin: _int(j['eloIfWin']),
      eloIfLoss: _int(j['eloIfLoss']),
    );
  }
}

/// The ghost is offered after this long in the ranked queue (CONTRACT
/// §14.12): the fallback until the server says (defs.ghost, the offer).
const int kGhostQueueDelay = 300;

/// Why no ghost is proposed right now. [queueOnly]: not in the ranked queue
/// (the only place a ghost is offered, §14.12); [queueWait]: in it, not for
/// long enough yet (see [GhostOfferResponse.retryInSec]); [premium]: a free
/// player past the 5 minutes, who sees [GhostOfferResponse.preview] locked.
enum GhostUnavailable { placement, queueOnly, queueWait, active, dailyLimit, premium, none, unknown }

GhostUnavailable _reason(dynamic v) => switch (v) {
      'placement' => GhostUnavailable.placement,
      'queue_only' => GhostUnavailable.queueOnly,
      'queue_wait' => GhostUnavailable.queueWait,
      'active' => GhostUnavailable.active,
      'daily_limit' => GhostUnavailable.dailyLimit,
      'premium' => GhostUnavailable.premium,
      'none' => GhostUnavailable.none,
      _ => GhostUnavailable.unknown,
    };

/// The ghost a free player would face (`reason: 'premium'`, CONTRACT
/// §14.12): shown blurred behind a lock. Nothing to start it with — the
/// server keeps no offer behind it.
class GhostPreview {
  final String username;
  final int elo;
  final String rank;
  final PublicCosmetics? cosmetics;

  const GhostPreview({required this.username, required this.elo, required this.rank, this.cosmetics});

  /// null without a name: nothing worth a card.
  static GhostPreview? fromJson(dynamic json) {
    if (json is! Map) return null;
    final j = Map<String, dynamic>.from(json);
    final username = j['username'];
    if (username is! String || username.isEmpty) return null;
    return GhostPreview(
      username: username,
      elo: _int(j['elo']),
      rank: _string(j['rank'], 'unranked'),
      cosmetics: PublicCosmetics.fromJson(j['cosmetics']),
    );
  }
}

class GhostOfferResponse {
  final bool available;
  final GhostOffer? offer;
  final GhostUnavailable? reason;
  final String? activeMatchId;
  final int queueDelaySec;

  /// With [GhostUnavailable.queueWait]: seconds before asking again.
  final int? retryInSec;

  /// With [GhostUnavailable.premium]: the ghost, for the locked card.
  final GhostPreview? preview;

  const GhostOfferResponse({
    required this.available,
    this.offer,
    this.reason,
    this.activeMatchId,
    this.queueDelaySec = kGhostQueueDelay,
    this.retryInSec,
    this.preview,
  });

  factory GhostOfferResponse.fromJson(dynamic json) {
    final j = json is Map ? Map<String, dynamic>.from(json) : <String, dynamic>{};
    final offer = GhostOffer.fromJson(j['offer']);
    final delay = _int(j['queueDelaySec'], kGhostQueueDelay);
    final available = _bool(j['available']) && offer != null;
    final reason = j['available'] == true ? null : _reason(j['reason']);
    return GhostOfferResponse(
      available: available,
      offer: offer,
      reason: reason,
      activeMatchId: j['activeMatchId'] is String ? j['activeMatchId'] as String : null,
      queueDelaySec: delay > 0 ? delay : kGhostQueueDelay,
      retryInSec: _intOrNull(j['retryInSec']),
      preview: !available && reason == GhostUnavailable.premium ? GhostPreview.fromJson(j['preview']) : null,
    );
  }
}

/// One dart of the ghost, at its real place and rhythm.
class GhostDart {
  final String notation;

  /// Normalized distance from the bull (1 = outer edge of the double ring).
  final double? radius;

  /// Radians, atan2(dy, dx) with y pointing down (the scorer's convention).
  final double? angle;

  /// Wait before this dart lands, in ms.
  final int delayMs;
  final bool skipped;

  const GhostDart({
    required this.notation,
    this.radius,
    this.angle,
    this.delayMs = 1500,
    this.skipped = false,
  });

  factory GhostDart.fromJson(Map<String, dynamic> j) => GhostDart(
        notation: _string(j['notation'], 'S0'),
        radius: _doubleOrNull(j['radius']),
        angle: _doubleOrNull(j['angle']),
        delayMs: _int(j['delayMs'], 1500).clamp(0, 20000),
        skipped: _bool(j['skipped']),
      );
}

class GhostVisit {
  final int leg;
  final int index;
  final int score;
  final bool busted;
  final bool checkout;
  final int remaining;
  final List<GhostDart> darts;

  const GhostVisit({
    required this.leg,
    required this.index,
    required this.score,
    this.busted = false,
    this.checkout = false,
    required this.remaining,
    required this.darts,
  });

  factory GhostVisit.fromJson(Map<String, dynamic> j) => GhostVisit(
        leg: _int(j['leg']),
        index: _int(j['index']),
        score: _int(j['score']),
        busted: _bool(j['busted']),
        checkout: _bool(j['checkout']),
        remaining: _int(j['remaining'], 501),
        darts: _maps(j['darts']).map(GhostDart.fromJson).toList(),
      );
}

class GhostEnd {
  final bool won;
  final String? endReason;
  final int playerLegsWon;
  final int ghostLegsWon;

  /// applied | held | none | rejected | expired | pending
  final String eloStatus;
  final int? eloDelta;
  final bool proofRequired;
  final double average;

  const GhostEnd({
    required this.won,
    this.endReason,
    this.playerLegsWon = 0,
    this.ghostLegsWon = 0,
    this.eloStatus = 'none',
    this.eloDelta,
    this.proofRequired = false,
    this.average = 0,
  });

  bool get eloHeld => eloStatus == 'held';
  bool get eloApplied => eloStatus == 'applied';

  static GhostEnd? fromJson(dynamic json) {
    if (json is! Map) return null;
    final j = Map<String, dynamic>.from(json);
    return GhostEnd(
      won: _bool(j['won']),
      endReason: j['endReason'] is String ? j['endReason'] as String : null,
      playerLegsWon: _int(j['playerLegsWon']),
      ghostLegsWon: _int(j['ghostLegsWon']),
      eloStatus: _string(j['eloStatus'], 'none'),
      eloDelta: _intOrNull(j['eloDelta']),
      proofRequired: _bool(j['proofRequired']),
      average: _double(j['average']),
    );
  }
}

class GhostPlayerVisit {
  final List<String> notations;
  final int score;
  final bool busted;
  const GhostPlayerVisit({required this.notations, required this.score, this.busted = false});

  factory GhostPlayerVisit.fromJson(Map<String, dynamic> j) => GhostPlayerVisit(
        notations: (j['notations'] is List)
            ? (j['notations'] as List).whereType<String>().toList()
            : const [],
        score: _int(j['score']),
        busted: _bool(j['busted']),
      );
}

/// The match as the server holds it — the only truth about the score.
class GhostMatchState {
  final String id;
  final String status;
  final int bestOf;
  final int legsToWin;
  final int currentLeg;
  final int playerLegsWon;
  final int ghostLegsWon;
  final bool ghostStartsLeg;
  final bool isOver;
  final int nextVisitIndex;
  final int playerRemaining;
  final int ghostRemaining;
  final List<GhostPlayerVisit> playerVisits;
  final List<GhostVisit> ghostVisits;
  final double playerAverage;
  final double ghostAverageLive;
  final bool eloEligible;
  final int? eloIfWin;
  final int? eloIfLoss;
  final GhostOpponent ghost;
  final GhostEnd? end;

  const GhostMatchState({
    required this.id,
    required this.status,
    this.bestOf = 3,
    this.legsToWin = 2,
    this.currentLeg = 0,
    this.playerLegsWon = 0,
    this.ghostLegsWon = 0,
    this.ghostStartsLeg = false,
    this.isOver = false,
    this.nextVisitIndex = 0,
    this.playerRemaining = 501,
    this.ghostRemaining = 501,
    this.playerVisits = const [],
    this.ghostVisits = const [],
    this.playerAverage = 0,
    this.ghostAverageLive = 0,
    this.eloEligible = false,
    this.eloIfWin,
    this.eloIfLoss,
    required this.ghost,
    this.end,
  });

  static GhostMatchState? fromJson(dynamic json) {
    if (json is! Map) return null;
    final j = Map<String, dynamic>.from(json);
    final id = j['id'];
    if (id is! String || id.isEmpty) return null;
    return GhostMatchState(
      id: id,
      status: _string(j['status'], 'in_progress'),
      bestOf: _int(j['bestOf'], 3),
      legsToWin: _int(j['legsToWin'], 2),
      currentLeg: _int(j['currentLeg']),
      playerLegsWon: _int(j['playerLegsWon']),
      ghostLegsWon: _int(j['ghostLegsWon']),
      ghostStartsLeg: j['legStarter'] == 'ghost',
      isOver: j['turn'] == 'over' || (j['status'] is String && j['status'] != 'in_progress'),
      nextVisitIndex: _int(j['nextVisitIndex']),
      playerRemaining: _int(j['playerRemaining'], 501),
      ghostRemaining: _int(j['ghostRemaining'], 501),
      playerVisits: _maps(j['playerVisits']).map(GhostPlayerVisit.fromJson).toList(),
      ghostVisits: _maps(j['ghostVisits']).map(GhostVisit.fromJson).toList(),
      playerAverage: _double(j['playerAverage']),
      ghostAverageLive: _double(j['ghostAverageLive']),
      eloEligible: _bool(j['eloEligible']),
      eloIfWin: _intOrNull(j['eloIfWin']),
      eloIfLoss: _intOrNull(j['eloIfLoss']),
      ghost: GhostOpponent.fromJson(j['ghost']),
      end: GhostEnd.fromJson(j['end']),
    );
  }
}

/// Answer to a posted visit: the server's verdict and the ghost's reply.
class GhostVisitResult {
  final bool duplicate;
  final GhostMatchState match;
  final int? visitScore;
  final int? visitRemaining;
  final bool visitBusted;
  final bool visitCheckout;

  /// Ghost visits to replay, in order (the current leg's answer, then the
  /// opening visit of the next leg when the ghost starts it).
  final List<GhostVisit> ghostVisits;
  final int? legEndedIndex;
  final bool? legWonByPlayer;

  const GhostVisitResult({
    required this.duplicate,
    required this.match,
    this.visitScore,
    this.visitRemaining,
    this.visitBusted = false,
    this.visitCheckout = false,
    this.ghostVisits = const [],
    this.legEndedIndex,
    this.legWonByPlayer,
  });

  static GhostVisitResult? fromJson(dynamic json) {
    if (json is! Map) return null;
    final j = Map<String, dynamic>.from(json);
    final match = GhostMatchState.fromJson(j['match']);
    if (match == null) return null;
    final visit = j['visit'] is Map ? Map<String, dynamic>.from(j['visit'] as Map) : null;
    final legEnded = j['legEnded'] is Map ? Map<String, dynamic>.from(j['legEnded'] as Map) : null;
    return GhostVisitResult(
      duplicate: _bool(j['duplicate']),
      match: match,
      visitScore: visit == null ? null : _int(visit['score']),
      visitRemaining: visit == null ? null : _intOrNull(visit['remaining']),
      visitBusted: visit != null && _bool(visit['busted']),
      visitCheckout: visit != null && _bool(visit['checkout']),
      ghostVisits: _maps(j['ghostVisits']).map(GhostVisit.fromJson).toList(),
      legEndedIndex: legEnded == null ? null : _int(legEnded['leg']),
      legWonByPlayer: legEnded == null ? null : legEnded['winner'] == 'player',
    );
  }
}

class GhostDigestGame {
  final String id;
  final String opponentId;
  final String opponentUsername;
  final bool ghostWon;
  final int ghostLegs;
  final int opponentLegs;
  final DateTime? finishedAt;

  const GhostDigestGame({
    required this.id,
    required this.opponentId,
    required this.opponentUsername,
    required this.ghostWon,
    this.ghostLegs = 0,
    this.opponentLegs = 0,
    this.finishedAt,
  });

  factory GhostDigestGame.fromJson(Map<String, dynamic> j) => GhostDigestGame(
        id: _string(j['id']),
        opponentId: _string(j['opponentId']),
        opponentUsername: _string(j['opponentUsername'], '—'),
        ghostWon: _bool(j['ghostWon']),
        ghostLegs: _int(j['ghostLegs']),
        opponentLegs: _int(j['opponentLegs']),
        finishedAt: _date(j['finishedAt']),
      );
}

/// What the owner's ghost did while they were away (mockup FantomeNuit).
class GhostDigest {
  final int count;
  final int ghostWins;
  final int ghostLosses;
  final int xp;
  final DateTime? sourcePlayedAt;
  final double sourceAverage;
  final String? beatenByUsername;
  final String? beatenByUserId;
  final int beatenByDarts;
  final List<GhostDigestGame> games;

  const GhostDigest({
    this.count = 0,
    this.ghostWins = 0,
    this.ghostLosses = 0,
    this.xp = 0,
    this.sourcePlayedAt,
    this.sourceAverage = 0,
    this.beatenByUsername,
    this.beatenByUserId,
    this.beatenByDarts = 0,
    this.games = const [],
  });

  bool get isEmpty => count == 0 || games.isEmpty;

  factory GhostDigest.fromJson(dynamic json) {
    final j = json is Map ? Map<String, dynamic>.from(json) : <String, dynamic>{};
    final source = j['source'] is Map ? Map<String, dynamic>.from(j['source'] as Map) : null;
    final beaten = j['beatenBy'] is Map ? Map<String, dynamic>.from(j['beatenBy'] as Map) : null;
    final games = _maps(j['games']).map(GhostDigestGame.fromJson).toList();
    return GhostDigest(
      count: _int(j['count'], games.length),
      ghostWins: _int(j['ghostWins']),
      ghostLosses: _int(j['ghostLosses']),
      xp: _int(j['xp']),
      sourcePlayedAt: _date(source?['playedAt']),
      sourceAverage: _double(source?['average']),
      beatenByUsername: beaten?['username'] is String ? beaten!['username'] as String : null,
      beatenByUserId: beaten?['userId'] is String ? beaten!['userId'] as String : null,
      beatenByDarts: _int(beaten?['darts']),
      games: games,
    );
  }
}

class GhostSettings {
  /// My matches may be replayed as ghosts.
  final bool enabled;

  /// The grouped "your ghost played" push.
  final bool notify;

  const GhostSettings({this.enabled = true, this.notify = true});

  factory GhostSettings.fromJson(dynamic json) {
    final j = json is Map ? Map<String, dynamic>.from(json) : <String, dynamic>{};
    return GhostSettings(enabled: _bool(j['enabled'], true), notify: _bool(j['notify'], true));
  }
}

/// A dart of the live player's visit, as posted to the server.
class GhostPostedDart {
  final String notation;

  /// What the model read before any correction; null for a typed dart.
  final String? aiNotation;
  final Map<String, double> telemetry;

  /// Phone wall clock when the dart registered (epoch ms).
  final int? t;

  const GhostPostedDart({required this.notation, this.aiNotation, this.telemetry = const {}, this.t});

  Map<String, dynamic> toJson() => {
        'notation': notation,
        'source': aiNotation == null ? 'manual' : 'ai',
        if (aiNotation != null) 'aiNotation': aiNotation,
        if (aiNotation != null) ...telemetry,
        't': ?t,
      };
}
