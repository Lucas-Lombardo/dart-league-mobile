import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/season.dart';
import '../services/seasons_service.dart';

/// Season state for the home hub: the active season (with my live standing),
/// the list of seasons for the picker, which season the home ring displays,
/// and a minute ticker for the countdown.
///
/// Refreshed from HomeScreen (initState + didPopNext) and when the
/// `season_ended` push is opened — there is no socket event for seasons.
class SeasonProvider extends ChangeNotifier {
  CurrentSeason? _current;
  List<Season> _seasons = [];
  int? _selectedNumber;
  SeasonStanding? _selectedStanding;
  bool _loadingSelected = false;
  SeasonRecap? _pendingRecap;
  Timer? _ticker;
  DateTime _now = DateTime.now();

  /// Injectable clock so the countdown can be tested with FakeAsync.
  DateTime Function() clock = DateTime.now;

  CurrentSeason? get current => _current;
  Season? get activeSeason => _current?.season;
  List<Season> get seasons => _seasons;
  SeasonRecap? get pendingRecap => _pendingRecap;

  /// The season the home ring displays. Defaults to the active one; a past
  /// season can be picked from the sheet — not persisted, the next launch is
  /// back on the active season.
  int? get selectedNumber => _selectedNumber ?? _current?.season.number;
  bool get isActiveSelected =>
      _current == null || selectedNumber == _current!.season.number;
  Season? get selectedSeason {
    final n = selectedNumber;
    if (n == null) return null;
    if (_current != null && n == _current!.season.number) {
      return _current!.season;
    }
    for (final s in _seasons) {
      if (s.number == n) return s;
    }
    return null;
  }

  /// My frozen line in the selected past season (null while loading or when
  /// I was not ranked in it).
  SeasonStanding? get selectedStanding =>
      isActiveSelected ? _current?.me : _selectedStanding;
  bool get loadingSelected => _loadingSelected;

  /// Time left in the active season, recomputed on every minute tick; null
  /// when no end is set.
  Duration? get timeLeft => _current?.season.timeLeft(_now);

  /// `true` once the backend answered at least once with a season.
  bool get hasSeason => _current != null;

  Future<void> refresh() async {
    final results = await Future.wait([
      SeasonsService.getCurrent(),
      SeasonsService.list(),
    ]);
    final current = results[0] as CurrentSeason?;
    final list = results[1] as List<Season>;
    if (current != null) _current = current;
    if (list.isNotEmpty) _seasons = list;
    _now = clock();
    _syncTicker();
    // A past selection that no longer exists (or never did) falls back to
    // the active season.
    if (_selectedNumber != null &&
        !_seasons.any((s) => s.number == _selectedNumber && s.isClosed)) {
      _selectedNumber = null;
      _selectedStanding = null;
    }
    notifyListeners();
  }

  /// Shows a past season on the home ring. Passing the active number (or
  /// null) goes back to the live view.
  Future<void> select(int? number) async {
    if (number == null || number == _current?.season.number) {
      _selectedNumber = null;
      _selectedStanding = null;
      notifyListeners();
      return;
    }
    _selectedNumber = number;
    _selectedStanding = null;
    _loadingSelected = true;
    notifyListeners();
    final standing = await SeasonsService.getMyStanding(number);
    // The user may have switched again while we were loading.
    if (_selectedNumber != number) return;
    _selectedStanding = standing;
    _loadingSelected = false;
    notifyListeners();
  }

  // ----------------------------------------------------------- navigation

  int? _standingsRequest;

  /// A cross-tab intent: "open the Rankings tab on season [number]". Set by
  /// the home ring ("Final standings ›") and the seasons screen; HomeScreen
  /// switches tabs, LeaderboardScreen consumes it when it mounts.
  int? get standingsRequest => _standingsRequest;

  void requestStandings(int number) {
    _standingsRequest = number;
    notifyListeners();
  }

  int? consumeStandingsRequest() {
    final n = _standingsRequest;
    _standingsRequest = null;
    return n;
  }

  /// The once-only recap gate: fetches and caches the pending recap so the
  /// caller can push the screens. Returns null when there is nothing to show.
  Future<SeasonRecap?> fetchRecap() async {
    final recap = await SeasonsService.getRecap();
    _pendingRecap = recap;
    notifyListeners();
    return recap;
  }

  /// Called at the end of the new-ELO screen. Clears the pending recap
  /// locally even if the call fails (it will come back at the next launch).
  Future<void> markRecapSeen(int number) async {
    _pendingRecap = null;
    notifyListeners();
    await SeasonsService.markRecapSeen(number);
  }

  void _syncTicker() {
    final needsTicker = _current?.season.endAt != null;
    if (!needsTicker) {
      _ticker?.cancel();
      _ticker = null;
      return;
    }
    _ticker ??= Timer.periodic(const Duration(minutes: 1), (_) => tick());
  }

  /// One countdown tick (public so tests can drive it without a timer).
  @visibleForTesting
  void tick() {
    _now = clock();
    notifyListeners();
  }

  /// Seeds the provider without the network (tests).
  @visibleForTesting
  void debugSetCurrent(CurrentSeason current, {List<Season> seasons = const []}) {
    _current = current;
    _seasons = seasons;
    _now = clock();
    _syncTicker();
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}
