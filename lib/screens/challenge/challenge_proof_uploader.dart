import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../services/api_service.dart';
import '../../services/camera_frame_service.dart';
import '../../services/replay_buffer_service.dart';
import 'challenge_api.dart';

enum ChallengeProofState { sending, sent, failed }

/// The filmed session of a ranked attempt (anti-cheat): the same native ring
/// as the match proof of disputes keeps every segment of the session under
/// `challenge-<attemptId>`; the top 3 of a board upload it straight to R2
/// (presigned PUT, streamed from disk — a run can weigh 100+ MB).
class ChallengeProofUploader {
  ChallengeProofUploader._();

  static String retentionKey(String attemptId) => 'challenge-$attemptId';

  /// Per attempt, for the result screen's "session sent" line.
  static final ValueNotifier<Map<String, ChallengeProofState>> states = ValueNotifier(const {});

  static final Set<String> _inFlight = {};

  static void _set(String attemptId, ChallengeProofState s) {
    states.value = {...states.value, attemptId: s};
  }

  /// Starts retaining the ring's segments for this attempt (ranked only).
  static Future<void> beginRecording(String attemptId) =>
      ReplayBufferService.beginRetention(retentionKey(attemptId));

  /// Nobody will ask for this video (practice, or outside the top 3).
  /// The native side also purges it after 48 h.
  static Future<void> discard(String attemptId) =>
      ReplayBufferService.deleteRetention(retentionKey(attemptId));

  /// Uploads the session. True once the server has it. Never throws.
  static Future<bool> upload(String attemptId) async {
    if (!_inFlight.add(attemptId)) return false;
    _set(attemptId, ChallengeProofState.sending);
    final key = retentionKey(attemptId);
    try {
      final batch = await ReplayBufferService.cutRuns(
        key,
        rotationDegrees: CameraFrameService.calibratedUprightRotation,
      );
      if (batch.clips.isEmpty) {
        await _fail(attemptId, 'no_retained_segments');
        return false;
      }
      var sent = 0;
      for (final clip in batch.clips) {
        final file = File(clip.path);
        try {
          final size = await file.length();
          final presign = await ApiService.post('/challenge/proof/presign', {
            'attemptId': attemptId,
            'sizeBytes': size,
            'startWallMs': clip.startWallMs,
            'durationMs': ?clip.durationMs,
          });
          final request = http.StreamedRequest('PUT', Uri.parse(presign['url'] as String))
            ..headers['Content-Type'] = 'video/mp4'
            ..contentLength = size;
          final response = request.send();
          await request.sink.addStream(file.openRead());
          await request.sink.close();
          final put = await response.timeout(const Duration(minutes: 10));
          if (put.statusCode < 200 || put.statusCode >= 300) {
            throw Exception('R2 PUT failed: ${put.statusCode}');
          }
          await ApiService.post('/challenge/proof/confirm', {
            'attemptId': attemptId,
            'key': presign['key'],
            'sizeBytes': size,
            'startWallMs': clip.startWallMs,
            'durationMs': ?clip.durationMs,
          });
          sent++;
        } catch (e) {
          debugPrint('[ChallengeProof] run upload failed: $e');
        } finally {
          try {
            await file.delete();
          } catch (_) {}
        }
      }
      if (sent == 0) {
        await _fail(attemptId, 'upload_failed');
        return false;
      }
      final done = await ApiService.post('/challenge/proof/complete', {'attemptId': attemptId});
      final delivered = done is Map && done['proofStatus'] == 'delivered';
      if (delivered && sent == batch.clips.length && batch.complete) {
        await ReplayBufferService.deleteRetention(key);
      }
      _set(attemptId, delivered ? ChallengeProofState.sent : ChallengeProofState.failed);
      return delivered;
    } catch (e) {
      debugPrint('[ChallengeProof] upload failed: $e');
      await _fail(attemptId, 'proof_processing_failed');
      return false;
    } finally {
      _inFlight.remove(attemptId);
    }
  }

  /// A failure is recorded, never swallowed: the admin sees why it is missing.
  static Future<void> _fail(String attemptId, String reason) async {
    _set(attemptId, ChallengeProofState.failed);
    try {
      await ApiService.post('/challenge/proof/failed', {'attemptId': attemptId, 'reason': reason});
    } catch (e) {
      debugPrint('[ChallengeProof] could not record failure: $e');
    }
  }

  /// Videos the server still waits for (the app was killed during the
  /// upload, or the player climbed into the top 3 later). Never throws.
  static Future<void> sweepPending() async {
    try {
      final pending = await ChallengeApi.pendingProofs();
      for (final p in pending) {
        if (states.value[p.attemptId] == ChallengeProofState.sending) continue;
        unawaited(upload(p.attemptId));
      }
    } catch (e) {
      debugPrint('[ChallengeProof] pending sweep failed: $e');
    }
  }
}
