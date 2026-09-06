import '../providers/game_provider.dart' show ScoreMultiplier;

/// Cricket targets in scoreboard order: 20 down to 15, then the bull.
/// The bull is keyed as 25 (its single value); a double bull counts 2 marks.
const List<int> kCricketTargets = [20, 19, 18, 17, 16, 15, 25];

/// - [score]: hits on a target you closed keep scoring its value while the
///   opponent has it open; win = all targets closed AND points >= opponent.
/// - [noScore]: pure race — first to close every target wins, no points.
enum CricketScoreMode { score, noScore }

/// What one dart did to the board — drives the visit-chip subtitle
/// ("1 marque", "+60 pts", "0 marque") and the board animation.
class CricketDartEffect {
  /// Target the marks/points landed on, or null for a dart outside 15-20/bull.
  final int? target;
  final int marksApplied;
  final int pointsScored;

  /// True when this dart put the [target] at exactly 3 marks.
  final bool closedTarget;

  const CricketDartEffect({
    this.target,
    this.marksApplied = 0,
    this.pointsScored = 0,
    this.closedTarget = false,
  });
}

/// Pure cricket rules state for one leg, playable by any pair of sides.
///
/// House rules (validated for Dart Rivals): marks are always S=1 / D=2 / T=3,
/// bull 25=1 / 50=2, no triple bull; a dart that closes a target mid-throw
/// scores its overflow marks as points (score mode, opponent still open).
///
/// The engine is transport-agnostic: the bot screen feeds it local AI
/// detections and bot throws; a future online mode can feed it server events.
class CricketState {
  final CricketScoreMode scoreMode;

  final Map<int, int> _myMarks = {for (final t in kCricketTargets) t: 0};
  final Map<int, int> _oppMarks = {for (final t in kCricketTargets) t: 0};
  int _myPoints = 0;
  int _oppPoints = 0;
  int _myMarksTotal = 0;
  int _oppMarksTotal = 0;

  CricketState({this.scoreMode = CricketScoreMode.score});

  /// Rebuilds a board from the server's wire maps (friendly online matches —
  /// the server is authoritative, this state is display-only there).
  factory CricketState.fromWire({
    required CricketScoreMode scoreMode,
    required Map<int, int> myMarks,
    required Map<int, int> oppMarks,
    required int myPoints,
    required int oppPoints,
  }) {
    final state = CricketState(scoreMode: scoreMode);
    for (final t in kCricketTargets) {
      state._myMarks[t] = (myMarks[t] ?? 0).clamp(0, 3);
      state._oppMarks[t] = (oppMarks[t] ?? 0).clamp(0, 3);
    }
    state._myPoints = myPoints;
    state._oppPoints = oppPoints;
    return state;
  }

  int myMarks(int target) => _myMarks[target] ?? 0;
  int oppMarks(int target) => _oppMarks[target] ?? 0;
  int get myPoints => _myPoints;
  int get oppPoints => _oppPoints;

  /// Every mark the player scored this leg — the MPR numerator. Only marks
  /// that counted: closing marks plus scoring overflow; darts on dead targets
  /// and wasted overflow are worth 0, the way real marks are tallied.
  int get myMarksTotal => _myMarksTotal;

  /// The opponent's counterpart of [myMarksTotal]. Only meaningful when both
  /// sides are humans on one phone (hot-seat), where each gets an MPR.
  int get oppMarksTotal => _oppMarksTotal;

  int get myClosedCount =>
      kCricketTargets.where((t) => myMarks(t) >= 3).length;
  int get oppClosedCount =>
      kCricketTargets.where((t) => oppMarks(t) >= 3).length;

  bool isClosedByMe(int target) => myMarks(target) >= 3;
  bool isClosedByOpp(int target) => oppMarks(target) >= 3;

  /// Closed on both sides — no more marks or points for anyone (score mode).
  bool isDead(int target) => isClosedByMe(target) && isClosedByOpp(target);

  /// I closed it, the opponent hasn't: every further hit scores points.
  bool isScoringForMe(int target) =>
      scoreMode == CricketScoreMode.score &&
      isClosedByMe(target) &&
      !isClosedByOpp(target);

  bool get iWon =>
      myClosedCount == kCricketTargets.length &&
      (scoreMode == CricketScoreMode.noScore || _myPoints >= _oppPoints);

  bool get oppWon =>
      oppClosedCount == kCricketTargets.length &&
      (scoreMode == CricketScoreMode.noScore || _oppPoints >= _myPoints);

  /// Marks one dart is worth on its target (0 for darts off the cricket
  /// numbers). The bull has no triple; T25 never occurs from detection.
  static int marksForDart(int baseScore, ScoreMultiplier multiplier) {
    if (!kCricketTargets.contains(baseScore)) return 0;
    switch (multiplier) {
      case ScoreMultiplier.single:
        return 1;
      case ScoreMultiplier.double:
        return 2;
      case ScoreMultiplier.triple:
        return baseScore == 25 ? 0 : 3;
    }
  }

  /// Applies one dart for the given side and returns what it did.
  CricketDartEffect applyDart(
    int baseScore,
    ScoreMultiplier multiplier, {
    required bool mine,
  }) {
    final marks = marksForDart(baseScore, multiplier);
    if (marks == 0) return const CricketDartEffect();

    final own = mine ? _myMarks : _oppMarks;
    final other = mine ? _oppMarks : _myMarks;
    final current = own[baseScore] ?? 0;
    final newMarks = (current + marks).clamp(0, 3);
    final applied = newMarks - current;
    final overflow = marks - applied;
    own[baseScore] = newMarks;

    int points = 0;
    if (scoreMode == CricketScoreMode.score &&
        overflow > 0 &&
        (other[baseScore] ?? 0) < 3) {
      points = overflow * baseScore;
      if (mine) {
        _myPoints += points;
      } else {
        _oppPoints += points;
      }
    }
    // Marks that actually counted: toward closing, plus scoring overflow. A
    // dart on a dead target (or wasted overflow) is worth 0 — counting the
    // raw marks would credit "3 marques" and inflate the MPR for a dart that
    // changed nothing on the board.
    final effectiveMarks = applied + (points > 0 ? overflow : 0);
    if (mine) {
      _myMarksTotal += effectiveMarks;
    } else {
      _oppMarksTotal += effectiveMarks;
    }

    return CricketDartEffect(
      target: baseScore,
      marksApplied: effectiveMarks,
      pointsScored: points,
      closedTarget: applied > 0 && newMarks == 3,
    );
  }

  /// Deep copy — the game screen snapshots the state at the start of a visit
  /// and replays the edited darts on top, exactly like the X01 recalculation.
  CricketState clone() {
    final copy = CricketState(scoreMode: scoreMode);
    copy._myMarks.addAll(_myMarks);
    copy._oppMarks.addAll(_oppMarks);
    copy._myPoints = _myPoints;
    copy._oppPoints = _oppPoints;
    copy._myMarksTotal = _myMarksTotal;
    copy._oppMarksTotal = _oppMarksTotal;
    return copy;
  }

  /// Mirror image: the opponent becomes "me". The hot-seat local match keeps
  /// the thrower on the "my" side (blue, left) like the X01 header does, so
  /// it flips the board every time the phone changes hands. Deep copy, like
  /// [clone].
  CricketState flipped() {
    final copy = CricketState(scoreMode: scoreMode);
    copy._myMarks.addAll(_oppMarks);
    copy._oppMarks.addAll(_myMarks);
    copy._myPoints = _oppPoints;
    copy._oppPoints = _myPoints;
    copy._myMarksTotal = _oppMarksTotal;
    copy._oppMarksTotal = _myMarksTotal;
    return copy;
  }

  /// Wire shape for the stateless bot-turn endpoint ({'20': 2, ..., '25': 0}).
  Map<String, int> marksToWire({required bool mine}) => {
        for (final t in kCricketTargets)
          '$t': (mine ? _myMarks : _oppMarks)[t] ?? 0,
      };
}
