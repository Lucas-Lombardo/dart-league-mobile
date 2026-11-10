import 'package:flutter/foundation.dart';

import '../../services/api_service.dart';
import 'league_models.dart';

/// Weekly league API (docs/progression/CONTRACT.md §14.4).
class LeagueApi {
  static Future<LeagueSnapshot> getMe() async => LeagueSnapshot.fromJson(await ApiService.get('/league/me'));

  /// Last week's result while not seen yet, else null.
  static Future<LeagueResult?> getResult() async {
    final response = await ApiService.get('/league/result');
    return LeagueResult.fromJson(response is Map ? response['result'] : null);
  }

  static Future<void> markResultSeen(String weekKey) async {
    await ApiService.post('/league/result/seen', {'weekKey': weekKey});
  }

  static Future<LeagueHistory> getHistory() async => LeagueHistory.fromJson(await ApiService.get('/league/history'));

  /// The league line of an end-of-match screen: points earned since [since]
  /// (the match start) and the place before / after. Null when there is
  /// nothing to say.
  static Future<LeagueMatchDelta?> getMatchDelta(DateTime since) async {
    final at = Uri.encodeQueryComponent(since.toUtc().toIso8601String());
    final response = await ApiService.get('/league/match-delta?since=$at');
    return LeagueMatchDelta.fromJson(response is Map ? response['delta'] : null);
  }
}

/// The league state the home row, the Progression card and the league screen
/// share. A plain singleton (no provider to register): widgets listen to it
/// with a ListenableBuilder. Never throws; on error it keeps the last value.
class LeagueStore extends ChangeNotifier {
  LeagueStore._();
  static final LeagueStore instance = LeagueStore._();

  LeagueSnapshot? _snapshot;
  bool _loading = false;
  bool _failed = false;
  Future<void>? _inFlight;

  /// Tests replace the network call (no HTTP in widget tests).
  @visibleForTesting
  Future<LeagueSnapshot> Function()? debugLoader;

  LeagueSnapshot? get snapshot => _snapshot;
  bool get isLoading => _loading;
  bool get failed => _failed;

  /// Null while unknown or when the server has no league (old backend).
  LeagueSnapshot? get visible => _snapshot != null && _snapshot!.enabled ? _snapshot : null;

  Future<void> refresh() {
    return _inFlight ??= _load().whenComplete(() => _inFlight = null);
  }

  Future<void> _load() async {
    _loading = true;
    notifyListeners();
    try {
      _snapshot = await (debugLoader ?? LeagueApi.getMe)();
      _failed = false;
    } catch (e) {
      debugPrint('LeagueStore.refresh: $e');
      _failed = true;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Results already shown in this session: a refresh racing the
  /// "seen" call must not bring the Monday screen back.
  final Set<String> _handled = {};
  bool isResultHandled(String weekKey) => _handled.contains(weekKey);

  /// After the Monday screen: nothing pending any more.
  void markResultHandled(String weekKey) {
    _handled.add(weekKey);
    final s = _snapshot;
    if (s == null || !s.hasResult) return;
    _snapshot = LeagueSnapshot(
      enabled: s.enabled,
      weekKey: s.weekKey,
      weekNumber: s.weekNumber,
      endsAt: s.endsAt,
      nextStartsAt: s.nextStartsAt,
      state: s.state,
      firstWeek: s.firstWeek,
      league: s.league,
      ladder: s.ladder,
      pointRules: s.pointRules,
      hasResult: false,
      group: s.group,
      myPosition: s.myPosition,
      myPoints: s.myPoints,
    );
    notifyListeners();
  }

  /// At login / account switch: never show the previous account's group.
  void reset() {
    _snapshot = null;
    _handled.clear();
    _failed = false;
    notifyListeners();
  }

  @visibleForTesting
  void debugSeed(LeagueSnapshot? snapshot) {
    _snapshot = snapshot;
    _failed = false;
    _loading = false;
    notifyListeners();
  }
}
