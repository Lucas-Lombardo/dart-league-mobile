import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_service.dart';
import 'camera_frame_service.dart';
import 'replay_buffer_service.dart';
import 'socket_service.dart';

/// One visit's METADATA, kept in case someone flags it. No file: since the
/// ring retains the whole match (match-proof, 2026-08-31), the clip is cut
/// on demand when a `capture_turn` actually arrives — which removed the
/// 3-7.5 MB passthrough cut+write the app used to pay at EVERY visit end
/// (thermal round 5, finding n°3).
class _CachedVisit {
  _CachedVisit({
    required this.matchId,
    required this.turnIndex,
    required this.dartTimes,
    required this.windowStart,
    required this.windowEnd,
  });

  final String matchId;
  final int turnIndex;

  /// Wall-clock of each dart of the visit — the only device that has it is
  /// this one, and it is what turns the admin's player into a "jump to the
  /// contested dart" bar.
  final List<int> dartTimes;

  /// The wall-clock window the clip is cut from at capture time.
  final DateTime windowStart;
  final DateTime windowEnd;
}

/// A flag this device posted, waiting for its reason at the end of the match.
class PendingTurnReport {
  PendingTurnReport({
    required this.reportId,
    required this.matchId,
    this.legNumber,
    this.turnIndex,
    this.volleyScore,
    this.isWinningVolley = false,
  });

  final String reportId;
  final String matchId;
  final int? legNumber;
  final int? turnIndex;
  final int? volleyScore;
  final bool isWinningVolley;

  /// Filled on the end-of-match screen. Without a reason the flag is dropped.
  String? reason;
  String? comment;

  bool get isComplete => reason != null;
}

/// The device side of per-volley reports, both roles at once — in any match
/// you are the one who may flag and the one who may be flagged.
///
/// As the REPORTED player: the metadata of your last visit (and of the visit
/// that won each leg) is noted; the clip itself is cut from the ring/retained
/// segments ONLY when a `capture_turn` actually asks for it. Nothing is ever
/// sent otherwise, and nothing is ever shown — the reported player is not
/// told (product decision 2026-08-13).
///
/// As the REPORTER: the flags posted during the match are held here until the
/// end-of-match screen gives them a reason.
class TurnReportService {
  TurnReportService._();

  /// The visit that just ended, whatever it was. Overwritten every turn.
  static _CachedVisit? _lastVisit;

  /// Retention key of the match currently on screen (set next to
  /// beginRetention) — the fallback cut source once the live ring stopped.
  static String? activeRetentionKey;

  /// The visit that won a leg, kept per match id: it can still be flagged from
  /// the leg-end / match-end screen, minutes after the rolling one is gone.
  static final Map<String, _CachedVisit> _winningVisits = {};

  /// Flags posted by THIS device, newest last, across a whole series.
  static final List<PendingTurnReport> pending = [];

  static bool _listening = false;

  /// Whether the server AND the opponent can play their part. Set from the
  /// match payload's `turnReports` block (the server's both-sides verdict) —
  /// never from a local guess.
  static bool enabled = false;
  static int maxPerLeg = 2;

  /// Reads the `turnReports` block out of a match payload.
  ///
  /// Adopt-only, exactly like [RtcV2Config.adopt]: a payload WITHOUT the block
  /// leaves the current value alone. Not every event that reaches the provider
  /// carries the block (a leg transition, a plain state sync), and turning the
  /// feature off on those would make the bar blink out mid-series. The state is
  /// reset per match by [resetForMatch] instead.
  static void applyMatchPayload(dynamic data) {
    final block = data is Map ? data['turnReports'] : null;
    if (block is! Map || block['enabled'] != true) return;
    enabled = true;
    final max = block['maxPerLeg'];
    if (max is num) maxPerLeg = max.toInt();
    debugPrint('[TurnReport] enabled for this match (max $maxPerLeg/leg)');
  }

  /// Back to "off until a payload says otherwise" — called where a match is set
  /// up, right next to the line that clears the P2P config, so a match against
  /// an old client can never inherit the previous match's verdict.
  static void resetForMatch() {
    enabled = false;
    maxPerLeg = 2;
  }

  // ── Reported side ───────────────────────────────────────────────────────

  /// Called by the game screen when one of MY visits ends. Pure bookkeeping —
  /// no cut, no file I/O; the window is remembered and cut only on demand.
  static void noteVisit({
    required String matchId,
    required int turnIndex,
    required List<DateTime> dartTimes,
    required DateTime windowStart,
    required DateTime windowEnd,
  }) {
    _lastVisit = _CachedVisit(
      matchId: matchId,
      turnIndex: turnIndex,
      dartTimes: dartTimes.map((t) => t.millisecondsSinceEpoch).toList(),
      windowStart: windowStart,
      windowEnd: windowEnd,
    );
  }

  /// Promotes the noted visit to "this is the one that won the leg", so it
  /// survives until the series is over — the loser can still flag it from the
  /// end screen long after the rolling note moved on.
  static void keepAsWinningVisit(String matchId) {
    final visit = _lastVisit;
    if (visit == null) return;
    _winningVisits[matchId] = visit;
  }

  /// The server asks this device for one of its own visits. Silent: no UI, no
  /// notification, nothing the player can see or refuse. The clip is cut NOW:
  /// from the live ring while the match runs, from the retained match-proof
  /// segments once the ring stopped (end screens, relaunch).
  static Future<void> handleCaptureRequest(dynamic data) async {
    if (data is! Map) return;
    final reportId = data['reportId'] as String?;
    if (reportId == null) return;
    final matchId = data['matchId'] as String?;
    final isWinning = data['isWinningVolley'] == true;

    final visit = isWinning && matchId != null
        ? _winningVisits[matchId]
        : _lastVisit;
    if (visit == null) {
      await _reportFailure(reportId, 'no_cached_visit');
      return;
    }
    ReplayCapture? captured;
    try {
      final rotation = CameraFrameService.calibratedUprightRotation;
      if (ReplayBufferService.armed) {
        captured = await ReplayBufferService.captureRange(
          visit.windowStart,
          visit.windowEnd,
          rotationDegrees: rotation,
        );
      }
      final retentionKey = activeRetentionKey;
      if (captured == null && retentionKey != null) {
        captured = await ReplayBufferService.captureRetainedRange(
          retentionKey,
          visit.windowStart,
          visit.windowEnd,
          rotationDegrees: rotation,
        );
      }
    } catch (e) {
      debugPrint('[TurnReport] on-demand cut failed: $e');
    }
    if (captured == null) {
      await _reportFailure(reportId, 'cut_failed');
      return;
    }
    await _upload(reportId, visit, captured);
    // The cut is a temp file made for this upload alone.
    _deleteFile(captured.path);
  }

  static Future<void> _upload(
    String reportId,
    _CachedVisit visit,
    ReplayCapture captured,
  ) async {
    try {
      final file = File(captured.path);
      if (!await file.exists()) {
        await _reportFailure(reportId, 'clip_missing');
        return;
      }
      final size = await file.length();
      final presign = await ApiService.post('/turn-reports/evidence/presign', {
        'reportId': reportId,
        'sizeBytes': size,
      });
      final url = presign['url'] as String;
      final key = presign['key'] as String;

      final bytes = await file.readAsBytes();
      final put = await http
          .put(
            Uri.parse(url),
            headers: {'Content-Type': 'video/mp4'},
            body: bytes,
          )
          .timeout(const Duration(minutes: 3));
      if (put.statusCode < 200 || put.statusCode >= 300) {
        throw Exception('R2 PUT failed: ${put.statusCode}');
      }

      await ApiService.post('/turn-reports/evidence/confirm', {
        'reportId': reportId,
        'key': key,
        'durationMs': ?captured.durationMs,
        'sizeBytes': size,
        'dartTimestamps': visit.dartTimes,
      });
      debugPrint('[TurnReport] evidence uploaded for $reportId');
    } catch (e) {
      debugPrint('[TurnReport] upload failed: $e');
      await _reportFailure(reportId, e.toString());
    }
  }

  /// A failure is recorded, never swallowed: a device that never delivers is
  /// itself information for whoever reads the case.
  static Future<void> _reportFailure(String reportId, String reason) async {
    try {
      await ApiService.post('/turn-reports/evidence/failed', {
        'reportId': reportId,
        'reason': reason.length > 200 ? reason.substring(0, 200) : reason,
      });
    } catch (e) {
      debugPrint('[TurnReport] could not record failure: $e');
    }
  }

  // ── Reporter side ───────────────────────────────────────────────────────

  /// Flags posted in the current leg, whatever their state — what the in-game
  /// bar counts against [maxPerLeg].
  static int flagsInLeg(String matchId) =>
      pending.where((p) => p.matchId == matchId && !p.isWinningVolley).length;

  static bool alreadyFlagged(String matchId, int turnIndex) => pending.any(
        (p) =>
            p.matchId == matchId &&
            !p.isWinningVolley &&
            p.turnIndex == turnIndex,
      );

  static bool winningVolleyFlagged(String matchId) =>
      pending.any((p) => p.matchId == matchId && p.isWinningVolley);

  /// Flags emitted but not yet acknowledged, keyed by flagId. The socket can
  /// drop between the tap and the server, and a lost flag is a lost case —
  /// same reasoning as the per-dart delivery protocol, with the same
  /// server-side dedup on the id making the retry free.
  static final Map<String, Map<String, dynamic>> _unacked = {};
  static Timer? _retryTimer;

  /// Emits a flag and keeps retrying until the server acknowledges it.
  static void postFlag(Map<String, dynamic> payload) {
    final flagId = payload['flagId'] as String?;
    if (flagId == null) return;
    _unacked[flagId] = payload;
    _emit(payload);
    _retryTimer ??= Timer.periodic(const Duration(seconds: 3), (timer) {
      if (_unacked.isEmpty) {
        timer.cancel();
        _retryTimer = null;
        return;
      }
      for (final pending in _unacked.values) {
        _emit(pending);
      }
    });
  }

  static void _emit(Map<String, dynamic> payload) {
    try {
      SocketService.emit('flag_turn', payload);
    } catch (e) {
      debugPrint('[TurnReport] flag emit failed, will retry: $e');
    }
  }

  /// Records the server's acknowledgement of a flag we posted.
  static void onFlagAck(dynamic data) {
    if (data is! Map) return;
    final flagId = data['flagId'] as String?;
    // Refused (quota, unsupported opponent) is still an answer: stop retrying.
    if (flagId != null) _unacked.remove(flagId);
    if (data['ok'] != true) return;
    final reportId = data['reportId'] as String?;
    if (reportId == null) return;
    if (pending.any((p) => p.reportId == reportId)) return;
    pending.add(PendingTurnReport(
      reportId: reportId,
      matchId: data['matchId'] as String? ?? '',
      legNumber: (data['legNumber'] as num?)?.toInt(),
      turnIndex: (data['turnIndex'] as num?)?.toInt(),
      volleyScore: (data['volleyScore'] as num?)?.toInt(),
      isWinningVolley: data['isWinningVolley'] == true,
    ));
  }

  /// Sends the completed reports and drops whatever was left blank. One call,
  /// so "I skipped the screen" and "I only filled one in" both settle.
  static Future<void> submit({String? matchId, String? seriesId}) async {
    final items = pending
        .where((p) => p.isComplete)
        .map((p) => {
              'reportId': p.reportId,
              'reason': p.reason,
              if (p.comment != null && p.comment!.trim().isNotEmpty)
                'comment': p.comment!.trim(),
            })
        .toList();
    try {
      await ApiService.post('/turn-reports/submit', {
        'items': items,
        'matchId': ?matchId,
        'seriesId': ?seriesId,
      });
    } catch (e) {
      debugPrint('[TurnReport] submit failed: $e');
    }
    clearPending();
  }

  static void clearPending() {
    pending.clear();
  }

  // ── Wiring ──────────────────────────────────────────────────────────────

  /// Attaches the capture listener. Idempotent — the game screens call it on
  /// every entry, and the reported side must stay attached for the whole
  /// series, not just one leg.
  static void listen() {
    if (_listening) return;
    _listening = true;
    // NO resetForMatch() here: the verdict arrives with `match_found`, which
    // lands BEFORE the game screen exists. Resetting on screen init wiped it
    // and left the bar hidden for the whole first leg (device test
    // 2026-08-13). The reset belongs where the match is set up — next to the
    // one that clears the P2P config.

    SocketService.on('capture_turn', handleCaptureRequest, owner: _owner);
    SocketService.on('flag_ack', onFlagAck, owner: _owner);
  }

  static void stopListening() {
    if (!_listening) return;
    _listening = false;
    _retryTimer?.cancel();
    _retryTimer = null;
    _unacked.clear();
    enabled = false;
    // Metadata only since the on-demand-cut rework — nothing on disk to sweep
    // (the retained segments have their own TTL purge).
    _winningVisits.clear();
    _lastVisit = null;
    activeRetentionKey = null;
    SocketService.off('capture_turn', owner: _owner);
    SocketService.off('flag_ack', owner: _owner);
  }

  static final Object _owner = Object();

  /// End of a match/series: forget the visits noted for it. Called after the
  /// end-of-match screen is done, so the winning visit is still flaggable
  /// while that screen is up.
  static void disposeMatch(String matchId) {
    _winningVisits.remove(matchId);
    if (_lastVisit?.matchId == matchId) _lastVisit = null;
  }

  static void _deleteFile(String path) {
    try {
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
    } catch (e) {
      debugPrint('[TurnReport] could not delete $path: $e');
    }
  }
}
