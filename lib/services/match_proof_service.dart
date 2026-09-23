import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import 'api_service.dart';
import 'camera_frame_service.dart';
import 'replay_buffer_service.dart';
import 'socket_service.dart';
import '../utils/storage_service.dart';

/// Match proof (result disputes): the whole match's my-turn footage, kept on
/// the phone by the ring's retention mode, and uploaded ONLY when a result
/// dispute asks for it (`capture_match` push, or the startup pending check
/// for a dispute that arrived while this device was offline).
///
/// Storage-side this costs disk, never heat: the ring already encodes every
/// my-turn frame — retention just stops throwing the segments away. ~1.7% of
/// matches end in a dispute, so nothing is uploaded for the other 98%.
///
/// The registry maps a retention key (the matchId the screen started with) to
/// every matchId/seriesId seen during the session (BO3 legs each have their
/// own matchId), persisted so a dispute filed after an app relaunch still
/// finds its footage.
class MatchProofService {
  MatchProofService._();

  static bool _listening = false;
  static Future<void> _registryTail = Future.value();
  static Future<void>? _pendingCheck;
  static Timer? _retryTimer;
  static int _retryCount = 0;
  static final _lifecycle = _ProofLifecycle();
  static String? _activeKey;
  static final Set<String> _uploadsInFlight = {};

  /// Ids already registered under [_activeKey] — [noteId] runs on every game
  /// state notify, and only the first sighting of an id may touch storage.
  static final Set<String> _knownIds = {};

  /// Called by the game screen when the ring arms for an online match:
  /// starts retention under [key] and registers it for later resolution.
  static Future<void> startMatch({required String key}) async {
    _activeKey = key;
    _knownIds.clear();
    ensureListening();
    await ReplayBufferService.beginRetention(key);
    await noteId(key);
  }

  /// Record another id (a later leg's matchId, the seriesId) under the active
  /// retention key. Runs on every state notify — the in-memory set makes the
  /// repeat calls free; storage is only touched on a NEW id (leg transition).
  static Future<void> noteId(String? id) async {
    final key = _activeKey;
    if (key == null || id == null || id.isEmpty) return;
    if (!_knownIds.add(id)) return;
    try {
      await _registerId(key, id);
    } catch (e) {
      if (_activeKey == key) _knownIds.remove(id);
      debugPrint('[MatchProof] registry failed: $e');
    }
  }

  /// Attach the global `capture_match` listener. Idempotent; stays attached
  /// for the app's lifetime — a dispute lands on the end screen or later,
  /// never scoped to one game screen.
  static void ensureListening() {
    // Re-attach the owned socket handler after logout/login too.
    SocketService.on('capture_match', _captureRequested, owner: _owner);
    SocketService.addReconnectListener(_retryPending);
    if (_listening) return;
    _listening = true;
    WidgetsBinding.instance.addObserver(_lifecycle);
  }

  static final Object _owner = Object();

  /// App-start sweep: disputes filed while this device was offline (or whose
  /// upload was cut short). One HTTP call; silent on any failure. Dedup is
  /// CLIENT-side: a fully uploaded key is forgotten from the registry, so
  /// resolving again returns only what still needs to go.
  static Future<void> checkPending() {
    ensureListening();
    return _pendingCheck ??= _checkPending().whenComplete(() {
      _pendingCheck = null;
    });
  }

  static Future<void> _checkPending() async {
    try {
      final res = await ApiService.get('/match-proof/pending');
      final requests = res['requests'];
      if (requests is! List) return;
      for (final request in requests) {
        if (request is Map) await _onCaptureMatch(request);
      }
    } catch (e) {
      debugPrint('[MatchProof] pending check failed: $e');
      _scheduleRetry();
    }
  }

  static void _retryPending() {
    _retryCount = 0;
    _retryTimer?.cancel();
    _retryTimer = null;
    unawaited(checkPending());
  }

  static void _scheduleRetry() {
    if (_retryTimer != null || _retryCount >= 2) return;
    _retryCount++;
    _retryTimer = Timer(Duration(seconds: 30 * _retryCount), () {
      _retryTimer = null;
      unawaited(checkPending());
    });
  }

  static Future<void> _captureRequested(dynamic data) async {
    _retryCount = 0;
    await _onCaptureMatch(data, reportMissing: true);
  }

  static Future<void> _onCaptureMatch(
    dynamic data, {
    bool reportMissing = false,
  }) async {
    if (data is! Map) return;
    final matchId = data['matchId'] as String?;
    if (matchId == null) return;
    try {
      final keys = await _resolveKeys(matchId, data['seriesId'] as String?);
      // No registry entry can also mean this footage was already delivered.
      // The startup sweep must not manufacture a failure in that case.
      if (keys.isEmpty && reportMissing) {
        await _reportFailure(matchId, 'no_retained_match');
      }
      for (final key in keys) {
        await _upload(key, matchId);
      }
    } catch (e) {
      debugPrint('[MatchProof] capture failed: $e');
      _scheduleRetry();
    }
  }

  /// Keep a per-clip receipt across retries/app restarts. An acknowledged PUT
  /// retries the SAME confirmation key; confirmed clips never upload twice.
  static Future<void> _upload(String key, String matchId) async {
    if (!_uploadsInFlight.add(key)) return;
    try {
      // A dispute on an earlier leg can arrive while this key still records.
      // Cutting/deleting it then would lose the rest of the series.
      if (_activeKey == key && ReplayBufferService.armed) {
        _scheduleRetry();
        return;
      }
      final batch = await ReplayBufferService.cutRuns(
        key,
        rotationDegrees: CameraFrameService.calibratedUprightRotation,
      );
      var delivered = 0;
      for (final clip in batch.clips) {
        try {
          final file = File(clip.path);
          final size = await file.length();
          final id = '$matchId:${clip.startWallMs}:${clip.durationMs}:$size';
          final receipts = await _receipts(key);
          final receipt = receipts[id];
          if (receipt is Map && receipt['delivered'] == true) {
            delivered++;
            continue;
          }
          String? storageKey = receipt is Map
              ? receipt['key'] as String?
              : null;
          if (storageKey == null) {
            final presign = await ApiService.post('/match-proof/presign', {
              'matchId': matchId,
              'sizeBytes': size,
              'startWallMs': clip.startWallMs,
              'durationMs': ?clip.durationMs,
            });
            final put = await http
                .put(
                  Uri.parse(presign['url'] as String),
                  headers: {'Content-Type': 'video/mp4'},
                  body: await file.readAsBytes(),
                )
                .timeout(const Duration(minutes: 3));
            if (put.statusCode < 200 || put.statusCode >= 300) {
              throw Exception('R2 PUT failed: ${put.statusCode}');
            }
            storageKey = presign['key'] as String;
            await _saveReceipt(key, id, {'key': storageKey});
          }
          await ApiService.post('/match-proof/confirm', {
            'matchId': matchId,
            'key': storageKey,
            'sizeBytes': size,
            'startWallMs': clip.startWallMs,
            'durationMs': ?clip.durationMs,
          });
          await _saveReceipt(key, id, {'key': storageKey, 'delivered': true});
          delivered++;
        } catch (e) {
          debugPrint('[MatchProof] clip upload failed: $e');
        } finally {
          try {
            await File(clip.path).delete();
          } catch (_) {}
        }
      }
      final complete =
          batch.complete &&
          batch.clips.isNotEmpty &&
          delivered == batch.clips.length;
      if (complete && !(_activeKey == key && ReplayBufferService.armed)) {
        await ReplayBufferService.deleteRetention(key);
        await _forgetKey(key);
      } else {
        await _reportFailure(
          matchId,
          batch.clips.isEmpty
              ? 'no_retained_segments'
              : !batch.complete
              ? 'partial_export'
              : 'partial_upload:$delivered/${batch.clips.length}',
        );
        _scheduleRetry();
      }
    } catch (e) {
      debugPrint('[MatchProof] proof processing failed: $e');
      await _reportFailure(matchId, 'proof_processing_failed');
      _scheduleRetry();
    } finally {
      _uploadsInFlight.remove(key);
    }
  }

  /// A failure is recorded, never swallowed — same contract as turn reports:
  /// a device that never delivers is itself information for the case.
  static Future<void> _reportFailure(String matchId, String reason) async {
    try {
      await ApiService.post('/match-proof/failed', {
        'matchId': matchId,
        'reason': reason,
      });
    } catch (e) {
      debugPrint('[MatchProof] could not record failure: $e');
    }
  }

  // ── Registry (persisted key → ids map) ──────────────────────────────────

  // Secure-storage read/modify/write operations must be serialized: a leg ID,
  // series ID and upload receipt can arrive during the same state notification.
  static Future<T> _withRegistry<T>(Future<T> Function() operation) {
    final result = _registryTail.then((_) => operation());
    _registryTail = result.then<void>(
      (_) {},
      onError: (Object e, StackTrace st) {},
    );
    return result;
  }

  static Future<Map<String, dynamic>> _readRegistry() async {
    final raw = await StorageService.getMatchProofRegistry();
    if (raw == null || raw.isEmpty) return {};
    return Map<String, dynamic>.from(jsonDecode(raw) as Map);
  }

  static Future<void> _writeRegistry(Map<String, dynamic> registry) async {
    final cutoff = DateTime.now()
        .subtract(const Duration(hours: 72))
        .millisecondsSinceEpoch;
    registry.removeWhere(
      (_, entry) =>
          entry is! Map || ((entry['at'] as num?)?.toInt() ?? 0) < cutoff,
    );
    await StorageService.saveMatchProofRegistry(jsonEncode(registry));
  }

  static Future<void> _registerId(String key, String id) =>
      _withRegistry(() async {
        final registry = await _readRegistry();
        final entry = registry[key];
        final ids = entry is Map
            ? List<String>.from(entry['ids'] as List? ?? [])
            : <String>[];
        if (ids.contains(id)) return;
        ids.add(id);
        registry[key] = {
          if (entry is Map) ...Map<String, dynamic>.from(entry),
          'ids': ids,
          'at': entry is Map
              ? entry['at']
              : DateTime.now().millisecondsSinceEpoch,
        };
        await _writeRegistry(registry);
      });

  static Future<List<String>> _resolveKeys(String matchId, String? seriesId) =>
      _withRegistry(() async {
        final registry = await _readRegistry();
        return [
          for (final entry in registry.entries)
            if (entry.value is Map &&
                ((entry.value['ids'] as List? ?? []).contains(matchId) ||
                    (seriesId != null &&
                        (entry.value['ids'] as List? ?? []).contains(
                          seriesId,
                        ))))
              entry.key,
        ];
      });

  static Future<Map<String, dynamic>> _receipts(String key) =>
      _withRegistry(() async {
        final entry = (await _readRegistry())[key];
        return Map<String, dynamic>.from(
          entry is Map ? entry['receipts'] as Map? ?? {} : {},
        );
      });

  static Future<void> _saveReceipt(
    String key,
    String id,
    Map<String, dynamic> receipt,
  ) => _withRegistry(() async {
    final registry = await _readRegistry();
    final entry = registry[key];
    if (entry is! Map) throw StateError('Missing proof registry entry');
    final receipts = Map<String, dynamic>.from(entry['receipts'] as Map? ?? {});
    receipts[id] = receipt;
    entry['receipts'] = receipts;
    await _writeRegistry(registry);
  });

  static Future<void> _forgetKey(String key) => _withRegistry(() async {
    final registry = await _readRegistry();
    if (registry.remove(key) != null) await _writeRegistry(registry);
  });

  @visibleForTesting
  static void debugReset() {
    _retryTimer?.cancel();
    _retryTimer = null;
    _retryCount = 0;
    if (_listening) WidgetsBinding.instance.removeObserver(_lifecycle);
    SocketService.removeReconnectListener(_retryPending);
    _listening = false;
    _activeKey = null;
    _knownIds.clear();
  }
}

class _ProofLifecycle extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) MatchProofService._retryPending();
  }
}
