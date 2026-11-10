import 'package:flutter/foundation.dart';

import '../../services/api_service.dart';
import 'challenge_models.dart';

/// Daily challenge API (backend src/challenge, CONTRACT.md §14.2).
class ChallengeApi {
  static Future<ChallengeToday> today() async {
    final t = ChallengeToday.fromJson(await ApiService.get('/challenge/today'));
    if (t == null) throw Exception('Unexpected challenge response');
    return t;
  }

  /// Tests replace the leaderboard call.
  @visibleForTesting
  static Future<ChallengeLeaderboard> Function(ChallengeView view)? debugLeaderboard;

  static Future<ChallengeLeaderboard> leaderboard(ChallengeView view, {String? date}) async {
    final fake = debugLeaderboard;
    if (fake != null && date == null) return fake(view);
    final q = 'view=${view.api}${date == null ? '' : '&date=$date'}';
    return ChallengeLeaderboard.fromJson(await ApiService.get('/challenge/leaderboard?$q'));
  }

  static Future<ChallengePodium> podium({String? date}) async =>
      ChallengePodium.fromJson(await ApiService.get('/challenge/podium${date == null ? '' : '?date=$date'}'));

  /// The first attempt of the day is the ranked one. [attemptId] is chosen
  /// here so a retried call never opens a second attempt.
  static Future<ChallengeStart> start(String attemptId) async {
    final s = ChallengeStart.fromJson(
      await ApiService.post('/challenge/attempts', {'attemptId': attemptId}),
    );
    if (s == null) throw Exception('Unexpected challenge response');
    return s;
  }

  static Future<ChallengeResult> submit(
    String attemptId, {
    required List<ChallengeVisitRecord> visits,
    required int clientScore,
    required int durationSec,
  }) async {
    final r = ChallengeResult.fromJson(await ApiService.post('/challenge/attempts/$attemptId/submit', {
      'visits': visits.map((v) => v.toJson()).toList(),
      'clientScore': clientScore,
      'durationSec': durationSec,
    }));
    if (r == null) throw Exception('Unexpected challenge response');
    return r;
  }

  static Future<ChallengeResult> attempt(String attemptId) async {
    final r = ChallengeResult.fromJson(await ApiService.get('/challenge/attempts/$attemptId'));
    if (r == null) throw Exception('Unexpected challenge response');
    return r;
  }

  static Future<ChallengeSession> session(String crownId) async {
    final s = ChallengeSession.fromJson(await ApiService.get('/challenge/sessions/$crownId'));
    if (s == null) throw Exception('Unexpected challenge response');
    return s;
  }

  static Future<void> report(String crownId, String reason, {String? comment}) async {
    await ApiService.post('/challenge/sessions/$crownId/report', {
      'reason': reason,
      if (comment != null && comment.trim().isNotEmpty) 'comment': comment.trim(),
    });
  }

  static Future<bool> setRemind(bool remind) async {
    final res = await ApiService.patch('/challenge/settings', {'remind': remind});
    return res is Map ? res['remind'] != false : remind;
  }

  static Future<List<ChallengeProofRequest>> pendingProofs() async {
    final res = await ApiService.get('/challenge/proof/pending');
    if (res is! List) return const [];
    return [
      for (final r in res)
        if (r is Map && r['attemptId'] is String)
          ChallengeProofRequest(r['attemptId'] as String, (r['date'] as String?) ?? ''),
    ];
  }
}

/// Today's challenge for the home row and the challenge screen. One fetch,
/// shared; refreshed when stale (date changed, or older than 2 minutes) and
/// right after a play.
class ChallengeStore extends ChangeNotifier {
  ChallengeStore._();
  static final ChallengeStore instance = ChallengeStore._();

  ChallengeToday? _today;
  String? _userId;
  DateTime? _fetchedAt;
  Future<void>? _inFlight;

  /// Tests replace the network call.
  @visibleForTesting
  Future<ChallengeToday> Function()? debugLoader;

  /// The snapshot, or null once its day is over (never shown nor played).
  ChallengeToday? get today => _live(_today);

  /// The account the snapshot belongs to.
  String? get userId => _userId;

  /// The snapshot of [userId], or null (another account, nothing yet, or a
  /// day that is over).
  ChallengeToday? todayFor(String? userId) =>
      userId != null && userId == _userId ? _live(_today) : null;

  static ChallengeToday? _live(ChallengeToday? t) => t == null || t.expired ? null : t;

  Future<void> refresh({String? userId}) {
    if (userId != null && userId != _userId) {
      _userId = userId;
      _today = null;
    }
    return _inFlight ??= _load().whenComplete(() => _inFlight = null);
  }

  /// Safe to call from a build: notifies only once the fetch is done.
  void refreshIfStale(String? userId) {
    if (userId == null) return;
    final fetched = _fetchedAt;
    final stale = userId != _userId ||
        fetched == null ||
        DateTime.now().difference(fetched) > const Duration(minutes: 2) ||
        (_today?.endsAt != null && DateTime.now().isAfter(_today!.endsAt!));
    if (stale && _inFlight == null) {
      Future.microtask(() => refresh(userId: userId));
    }
  }

  Future<void> _load() async {
    try {
      _today = await (debugLoader ?? ChallengeApi.today)();
    } catch (e) {
      debugPrint('ChallengeStore.refresh: $e');
      // Keep the last snapshot through a network blip, never past its day.
      if (_today?.expired ?? false) _today = null;
    } finally {
      _fetchedAt = DateTime.now();
      notifyListeners();
    }
  }

  /// Local change (reminder toggle) without a round trip.
  void patch(ChallengeToday today) {
    _today = today;
    notifyListeners();
  }

  void reset() {
    _today = null;
    _userId = null;
    _fetchedAt = null;
    notifyListeners();
  }

  @visibleForTesting
  void debugSeed(ChallengeToday? today, {String userId = 'me'}) {
    _today = today;
    _userId = userId;
    _fetchedAt = DateTime.now();
    notifyListeners();
  }
}
