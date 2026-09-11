import 'local_match_config.dart';

enum RefereeInputMode { total, darts }

enum RefereeVisitKind { empty, score, bust, finish, invalid }

enum RefereeInputError { impossibleTotal, dartsAfterEnd }

/// A manually entered dart, with no fabricated camera coordinates or telemetry.
class RefereeDart {
  final int base;
  final int multiplier;

  RefereeDart(this.base, [this.multiplier = 1]) {
    if (multiplier < 1 ||
        multiplier > 3 ||
        !((base >= 1 && base <= 20) ||
            (base == 0 && multiplier == 1) ||
            (base == 25 && multiplier <= 2))) {
      throw ArgumentError('Invalid dart: $base × $multiplier');
    }
  }

  int get points => base * multiplier;
  bool get isDouble => multiplier == 2;
  String get notation => base == 0
      ? '0'
      : base == 25
      ? (isDouble ? '50' : '25')
      : '${['S', 'D', 'T'][multiplier - 1]}$base';
}

class RefereePreview {
  final RefereeVisitKind kind;
  final int points;
  final int remaining;
  final RefereeInputError? error;
  final List<int> finishDartCounts;

  const RefereePreview(
    this.kind,
    this.points,
    this.remaining, {
    this.error,
    this.finishDartCounts = const [],
  });

  bool get canValidate =>
      kind != RefereeVisitKind.empty && kind != RefereeVisitKind.invalid;
}

class RefereeVisit {
  final int player;
  final int leg;
  final int before;
  final int after;
  final int points;
  final bool bust;
  final bool checkout;
  final int? checkoutDarts;

  /// Null for a total: do not invent the individual darts behind it.
  final List<RefereeDart>? darts;

  RefereeVisit({
    required this.player,
    required this.leg,
    required this.before,
    required this.after,
    required this.points,
    required this.bust,
    required this.checkout,
    this.checkoutDarts,
    List<RefereeDart>? darts,
  }) : darts = darts == null ? null : List.unmodifiable(darts);
}

/// Local, synchronous scoring. Only [validateVisit] changes official scores.
/// Camera/AI, sockets, accounts and remote statistics are intentionally absent.
class RefereeMatch {
  final LocalMatchConfig config;
  final int firstPlayer;
  final List<int> _scores = [501, 501];
  final List<int> _legs = [0, 0];
  final List<RefereeVisit> _history = [];
  final List<_RefereeSnapshot> _undo = [];
  int _activePlayer;
  int? _winner;
  int? _legWinner;
  RefereeInputMode _inputMode = RefereeInputMode.total;
  String _totalInput = '';
  bool _replaceInput = false;
  final List<RefereeDart> _draftDarts = [];
  List<RefereeDart>? _carriedDarts;
  int? _editingDart;

  RefereeMatch({required this.config, this.firstPlayer = 0})
    : _activePlayer = firstPlayer {
    if (config.isCricket ||
        config.startingScore != 501 ||
        ![1, 3, 5].contains(config.bestOf) ||
        (firstPlayer != 0 && firstPlayer != 1)) {
      throw ArgumentError('Referee mode requires a local 501 and valid format');
    }
  }

  List<int> get scores => List.unmodifiable(_scores);
  List<int> get legs => List.unmodifiable(_legs);
  List<RefereeVisit> get history => List.unmodifiable(_history);
  List<RefereeDart> get draftDarts => List.unmodifiable(_draftDarts);
  int get activePlayer => _activePlayer;
  int? get winner => _winner;
  int? get legWinner => _legWinner;
  int get legNumber => _legs[0] + _legs[1] + (_legWinner == null ? 1 : 0);
  RefereeInputMode get inputMode => _inputMode;
  String get totalInput => _totalInput;
  int? get editingDart => _editingDart;
  bool get canUndo => _undo.isNotEmpty;
  bool get canEnter => _winner == null && _legWinner == null;

  /// Same convention as the existing local match: average credited visit score.
  /// Includes zero for busts, survives leg changes, excludes the draft.
  double? averageOf(int player) {
    final visits = _history.where((v) => v.player == player);
    if (visits.isEmpty) return null;
    return visits.fold<int>(0, (sum, v) => sum + v.points) / visits.length;
  }

  static final List<RefereeDart> _possibleDarts = [
    RefereeDart(0),
    RefereeDart(25),
    RefereeDart(25, 2),
    for (var n = 1; n <= 20; n++)
      for (var m = 1; m <= 3; m++) RefereeDart(n, m),
  ];
  static final List<Set<int>> _sums = _buildSums();
  static List<Set<int>> _buildSums() {
    final result = <Set<int>>[
      {0},
    ];
    for (var count = 1; count <= 3; count++) {
      result.add({
        for (final sum in result.last)
          for (final dart in _possibleDarts) sum + dart.points,
      });
    }
    return result;
  }

  static List<int> possibleFinishCounts(
    int points, {
    required bool doubleOut,
  }) => [
    for (var count = 1; count <= 3; count++)
      if (_possibleDarts.any(
        (d) =>
            d.points > 0 &&
            (!doubleOut || d.isDouble) &&
            _sums[count - 1].contains(points - d.points),
      ))
        count,
  ];

  RefereePreview get preview {
    final start = _scores[_activePlayer];
    final detailed = _inputMode == RefereeInputMode.darts
        ? _draftDarts
        : _carriedDarts;
    if (detailed != null && detailed.isNotEmpty) {
      var remaining = start;
      var points = 0;
      for (var i = 0; i < detailed.length; i++) {
        final dart = detailed[i];
        points += dart.points;
        remaining -= dart.points;
        final bust =
            remaining < 0 ||
            (config.doubleOut &&
                (remaining == 1 || (remaining == 0 && !dart.isDouble)));
        if (bust || remaining == 0) {
          if (i != detailed.length - 1) {
            return RefereePreview(
              RefereeVisitKind.invalid,
              points,
              remaining,
              error: RefereeInputError.dartsAfterEnd,
            );
          }
          return RefereePreview(
            bust ? RefereeVisitKind.bust : RefereeVisitKind.finish,
            points,
            bust ? start : 0,
            finishDartCounts: bust ? const [] : [i + 1],
          );
        }
      }
      return RefereePreview(RefereeVisitKind.score, points, remaining);
    }
    if (_inputMode == RefereeInputMode.darts || _totalInput.isEmpty) {
      return RefereePreview(RefereeVisitKind.empty, 0, start);
    }
    final points = int.tryParse(_totalInput);
    if (points == null || !_sums[3].contains(points)) {
      return RefereePreview(
        RefereeVisitKind.invalid,
        points ?? 0,
        start,
        error: RefereeInputError.impossibleTotal,
      );
    }
    final remaining = start - points;
    if (remaining < 0 || (config.doubleOut && remaining == 1)) {
      return RefereePreview(RefereeVisitKind.bust, points, start);
    }
    if (remaining == 0) {
      final counts = possibleFinishCounts(points, doubleOut: config.doubleOut);
      return RefereePreview(
        counts.isEmpty ? RefereeVisitKind.bust : RefereeVisitKind.finish,
        points,
        counts.isEmpty ? start : 0,
        finishDartCounts: counts,
      );
    }
    return RefereePreview(RefereeVisitKind.score, points, remaining);
  }

  void enterDigit(int digit) {
    if (!canEnter ||
        _inputMode != RefereeInputMode.total ||
        digit < 0 ||
        digit > 9) {
      return;
    }
    if (_replaceInput) {
      _totalInput = '';
      _replaceInput = false;
    }
    if (_totalInput.length >= 3) return;
    _carriedDarts = null;
    _totalInput = '${_totalInput == '0' ? '' : _totalInput}$digit';
  }

  void setTotal(int points) {
    if (!canEnter || _inputMode != RefereeInputMode.total) return;
    _totalInput = '$points';
    _replaceInput = true;
    _carriedDarts = null;
  }

  void backspace() {
    if (!canEnter || _inputMode != RefereeInputMode.total) return;
    if (_totalInput.isNotEmpty) {
      _totalInput = _totalInput.substring(0, _totalInput.length - 1);
    }
    _replaceInput = false;
    _carriedDarts = null;
  }

  void clearDraft() {
    _totalInput = '';
    _replaceInput = false;
    _draftDarts.clear();
    _carriedDarts = null;
    _editingDart = null;
  }

  /// Return false if changing the method would discard an unconverted total.
  bool useDarts({bool discardTotal = false}) {
    if (!canEnter) return false;
    if (_inputMode == RefereeInputMode.darts) return true;
    if (_carriedDarts == null && _totalInput.isNotEmpty && !discardTotal) {
      return false;
    }
    final carry = _carriedDarts;
    clearDraft();
    if (carry != null) _draftDarts.addAll(carry);
    _inputMode = RefereeInputMode.darts;
    return true;
  }

  void useTotal() {
    if (!canEnter || _inputMode == RefereeInputMode.total) return;
    _carriedDarts = _draftDarts.isEmpty ? null : List.of(_draftDarts);
    _totalInput = _draftDarts.isEmpty
        ? ''
        : '${_draftDarts.fold<int>(0, (n, d) => n + d.points)}';
    _replaceInput = true;
    _editingDart = null;
    _inputMode = RefereeInputMode.total;
  }

  void selectDart(int index) {
    if (!canEnter) return;
    _editingDart = index >= 0 && index < _draftDarts.length ? index : null;
  }

  bool enterDart(RefereeDart dart) {
    if (!canEnter || _inputMode != RefereeInputMode.darts) return false;
    if (_editingDart == null) {
      if (_draftDarts.length >= 3 ||
          ![
            RefereeVisitKind.empty,
            RefereeVisitKind.score,
          ].contains(preview.kind)) {
        return false;
      }
      _draftDarts.add(dart);
    } else {
      _draftDarts[_editingDart!] = dart;
    }
    _editingDart = null;
    return true;
  }

  void removeDart(int index) {
    if (!canEnter || index < 0 || index >= _draftDarts.length) return;
    _draftDarts.removeAt(index);
    _editingDart = null;
  }

  RefereeVisit validateVisit({bool bust = false, int? checkoutDarts}) {
    final draft = preview;
    if (!canEnter || (!bust && !draft.canValidate)) {
      throw StateError('No valid visit');
    }
    final isBust = bust || draft.kind == RefereeVisitKind.bust;
    final checkout = !isBust && draft.kind == RefereeVisitKind.finish;
    if (checkout && !draft.finishDartCounts.contains(checkoutDarts)) {
      throw StateError('Confirm the checkout and its dart count');
    }
    _undo.add(
      _RefereeSnapshot(
        List.of(_scores),
        List.of(_legs),
        _activePlayer,
        _winner,
        _legWinner,
      ),
    );
    final visit = RefereeVisit(
      player: _activePlayer,
      leg: legNumber,
      before: _scores[_activePlayer],
      after: isBust ? _scores[_activePlayer] : draft.remaining,
      points: isBust ? 0 : draft.points,
      bust: isBust,
      checkout: checkout,
      checkoutDarts: checkout ? checkoutDarts : null,
      darts: _inputMode == RefereeInputMode.darts ? _draftDarts : _carriedDarts,
    );
    _history.add(visit);
    _scores[_activePlayer] = visit.after;
    if (checkout) {
      _legs[_activePlayer]++;
      _legWinner = _activePlayer;
      if (_legs[_activePlayer] >= config.legsToWin) _winner = _activePlayer;
    } else {
      _activePlayer = 1 - _activePlayer;
    }
    clearDraft();
    return visit;
  }

  void startNextLeg() {
    if (_legWinner == null || _winner != null) return;
    _scores.setAll(0, [501, 501]);
    _activePlayer = (firstPlayer + _legs[0] + _legs[1]) % 2;
    _legWinner = null;
    clearDraft();
  }

  void undo() {
    if (_undo.isEmpty) return;
    final previous = _undo.removeLast();
    _history.removeLast();
    _scores.setAll(0, previous.scores);
    _legs.setAll(0, previous.legs);
    _activePlayer = previous.activePlayer;
    _winner = previous.winner;
    _legWinner = previous.legWinner;
    clearDraft();
  }

  void restart() {
    _scores.setAll(0, [501, 501]);
    _legs.setAll(0, [0, 0]);
    _history.clear();
    _undo.clear();
    _activePlayer = firstPlayer;
    _winner = _legWinner = null;
    _inputMode = RefereeInputMode.total;
    clearDraft();
  }
}

class _RefereeSnapshot {
  final List<int> scores;
  final List<int> legs;
  final int activePlayer;
  final int? winner;
  final int? legWinner;
  const _RefereeSnapshot(
    this.scores,
    this.legs,
    this.activePlayer,
    this.winner,
    this.legWinner,
  );
}
