import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
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
    _knownIds.add(key);
    await _registerId(key, key);
  }

  /// Record another id (a later leg's matchId, the seriesId) under the active
  /// retention key. Runs on every state notify — the in-memory set makes the
  /// repeat calls free; storage is only touched on a NEW id (leg transition).
  static Future<void> noteId(String? id) async {
    final key = _activeKey;
    if (key == null || id == null || id.isEmpty) return;
    if (!_knownIds.add(id)) return;
    await _registerId(key, id);
  }

  /// Attach the global `capture_match` listener. Idempotent; stays attached
  /// for the app's lifetime — a dispute lands on the end screen or later,
  /// never scoped to one game screen.
  static void ensureListening() {
    if (_listening) return;
    _listening = true;
    SocketService.on('capture_match', _onCaptureMatch, owner: _owner);
  }

  static final Object _owner = Object();

  /// App-start sweep: disputes filed while this device was offline (or whose
  /// upload was cut short). One HTTP call; silent on any failure. Dedup is
  /// CLIENT-side: a fully uploaded key is forgotten from the registry, so
  /// resolving again returns only what still needs to go.
  static Future<void> checkPending() async {
    ensureListening();
    try {
      final res = await ApiService.get('/match-proof/pending');
      final requests = res['requests'];
      if (requests is! List) return;
      for (final request in requests) {
        if (request is! Map) continue;
        final matchId = request['matchId'] as String?;
        if (matchId == null) continue;
        for (final key
            in await _resolveKeys(matchId, request['seriesId'] as String?)) {
          await _upload(key, matchId);
        }
      }
    } catch (e) {
      debugPrint('[MatchProof] pending check failed: $e');
    }
  }

  static Future<void> _onCaptureMatch(dynamic data) async {
    if (data is! Map) return;
    final matchId = data['matchId'] as String?;
    if (matchId == null) return;
    final keys = await _resolveKeys(matchId, data['seriesId'] as String?);
    if (keys.isEmpty) {
      await _reportFailure(matchId, 'no_retained_match');
      return;
    }
    // A series' footage can span SEVERAL retention keys: a mid-series video
    // relaunch rebuilds the camera, and the new screen retains under the
    // current leg's matchId (device test 2026-08-31: legs 1-2 under the
    // first key, leg 3 — the disputed one — under a second that a
    // single-key resolve never uploaded). Upload them all.
    for (final key in keys) {
      await _upload(key, matchId);
    }
  }

  /// Cut the retained match into per-turn clips and upload them one by one.
  /// Sequential on purpose (same reasoning as the replay drain: the uplink is
  /// shared, resolving clips in order beats resolving them together late).
  static Future<void> _upload(String key, String matchId) async {
    if (_uploadsInFlight.contains(key)) return;
    _uploadsInFlight.add(key);
    try {
      final clips = await ReplayBufferService.cutRuns(
        key,
        rotationDegrees: CameraFrameService.calibratedUprightRotation,
      );
      if (clips.isEmpty) {
        await _reportFailure(matchId, 'no_retained_segments');
        return;
      }
      var delivered = 0;
      for (final clip in clips) {
        try {
          final file = File(clip.path);
          if (!await file.exists()) continue;
          final size = await file.length();
          final presign = await ApiService.post('/match-proof/presign', {
            'matchId': matchId,
            'sizeBytes': size,
            'startWallMs': clip.startWallMs,
            'durationMs': ?clip.durationMs,
          });
          final url = presign['url'] as String;
          final storageKey = presign['key'] as String;
          final put = await http
              .put(
                Uri.parse(url),
                headers: {'Content-Type': 'video/mp4'},
                body: await file.readAsBytes(),
              )
              .timeout(const Duration(minutes: 3));
          if (put.statusCode < 200 || put.statusCode >= 300) {
            throw Exception('R2 PUT failed: ${put.statusCode}');
          }
          await ApiService.post('/match-proof/confirm', {
            'matchId': matchId,
            'key': storageKey,
            'sizeBytes': size,
            'startWallMs': clip.startWallMs,
            'durationMs': ?clip.durationMs,
          });
          delivered++;
        } catch (e) {
          debugPrint('[MatchProof] clip upload failed: $e');
        } finally {
          // The run clip is a temp product of this upload alone; segments
          // stay until the retention purge.
          try {
            final file = File(clip.path);
            if (file.existsSync()) file.deleteSync();
          } catch (_) {}
        }
      }
      debugPrint('[MatchProof] $delivered/${clips.length} clips uploaded '
          'for $matchId');
      if (delivered == 0) {
        await _reportFailure(matchId, 'all_uploads_failed');
      } else if (delivered == clips.length) {
        // Everything landed server-side — the local copy has done its job.
        await ReplayBufferService.deleteRetention(key);
        await _forgetKey(key);
      }
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

  static Future<Map<String, dynamic>> _readRegistry() async {
    try {
      final raw = await StorageService.getMatchProofRegistry();
      if (raw == null || raw.isEmpty) return {};
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : {};
    } catch (_) {
      return {};
    }
  }

  static Future<void> _writeRegistry(Map<String, dynamic> registry) async {
    try {
      // Entries expire with the retained footage — prune what the native
      // 48h purge has certainly reclaimed.
      final cutoff =
          DateTime.now().subtract(const Duration(hours: 72)).millisecondsSinceEpoch;
      registry.removeWhere((_, entry) =>
          entry is! Map || ((entry['at'] as num?)?.toInt() ?? 0) < cutoff);
      await StorageService.saveMatchProofRegistry(jsonEncode(registry));
    } catch (e) {
      debugPrint('[MatchProof] registry write failed: $e');
    }
  }

  static Future<void> _registerId(String key, String id) async {
    final registry = await _readRegistry();
    final entry = registry[key];
    final ids = entry is Map ? List<String>.from(entry['ids'] as List? ?? []) : <String>[];
    if (ids.contains(id)) return;
    ids.add(id);
    registry[key] = {
      'ids': ids,
      'at': entry is Map
          ? ((entry['at'] as num?)?.toInt() ??
              DateTime.now().millisecondsSinceEpoch)
          : DateTime.now().millisecondsSinceEpoch,
    };
    await _writeRegistry(registry);
  }

  /// EVERY retention key holding footage for this dispute, oldest first — a
  /// mid-series relaunch splits one series across keys (see _onCaptureMatch).
  /// Fully uploaded keys were forgotten, so they never come back here.
  static Future<List<String>> _resolveKeys(
    String matchId,
    String? seriesId,
  ) async {
    final registry = await _readRegistry();
    final keys = <String>[];
    for (final entry in registry.entries) {
      final value = entry.value;
      if (value is! Map) continue;
      final ids = List<String>.from(value['ids'] as List? ?? []);
      if (ids.contains(matchId) ||
          (seriesId != null && ids.contains(seriesId))) {
        keys.add(entry.key);
      }
    }
    return keys;
  }

  static Future<void> _forgetKey(String key) async {
    final registry = await _readRegistry();
    if (registry.remove(key) != null) await _writeRegistry(registry);
  }
}
