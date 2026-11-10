import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../services/api_service.dart';
import '../../services/camera_frame_service.dart';
import '../../services/replay_buffer_service.dart';
import 'ghost_service.dart';

/// The ghost match's video (regles.md §5). The match is filmed like a ranked
/// one — the replay ring retains every turn of the live player under the
/// ghost match id — and the footage leaves the phone ONLY when the server
/// asked for it at the end of the match (`proofRequired`): low trust factor,
/// or a score out of the player's usual range. Otherwise it is deleted.
class GhostProofUploader {
  GhostProofUploader._();

  static final Set<String> _inFlight = {};

  /// Start retaining the match's footage under [matchId].
  static Future<void> beginRetention(String matchId) => ReplayBufferService.beginRetention(matchId);

  /// Nothing to prove: free the disk.
  static Future<void> discard(String matchId) => ReplayBufferService.deleteRetention(matchId);

  /// Uploads every retained turn of [matchId]. True when all of it landed.
  /// [reportMissing]: tell the server when nothing was retained (in-session
  /// upload); the startup sweep stays silent instead.
  static Future<bool> upload(String matchId, {bool reportMissing = true}) async {
    if (!_inFlight.add(matchId)) return false;
    try {
      final batch = await ReplayBufferService.cutRuns(
        matchId,
        rotationDegrees: CameraFrameService.calibratedUprightRotation,
      );
      if (batch.clips.isEmpty) {
        if (reportMissing) await _fail(matchId, 'no_retained_segments');
        return false;
      }
      var delivered = 0;
      for (var i = 0; i < batch.clips.length; i++) {
        final clip = batch.clips[i];
        try {
          final file = File(clip.path);
          final size = await file.length();
          final presign = await ApiService.post('/ghost/matches/$matchId/proof/presign', {'sizeBytes': size});
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
          await ApiService.post('/ghost/matches/$matchId/proof/confirm', {
            'key': presign['key'] as String,
            'sizeBytes': size,
            'startWallMs': clip.startWallMs,
            'durationMs': ?clip.durationMs,
            'last': i == batch.clips.length - 1 && delivered == i,
          });
          delivered++;
        } catch (e) {
          debugPrint('[GhostProof] clip upload failed: $e');
        } finally {
          try {
            await File(clip.path).delete();
          } catch (_) {}
        }
      }
      final complete = batch.complete && delivered == batch.clips.length;
      if (complete) {
        await ReplayBufferService.deleteRetention(matchId);
      } else {
        await _fail(matchId, 'partial_upload:$delivered/${batch.clips.length}');
      }
      return complete;
    } catch (e) {
      debugPrint('[GhostProof] proof failed: $e');
      await _fail(matchId, 'proof_processing_failed');
      return false;
    } finally {
      _inFlight.remove(matchId);
    }
  }

  /// Startup sweep: matches still owing their video (the app was killed
  /// before the upload finished). Silent on any failure.
  static Future<void> uploadPending() async {
    try {
      for (final id in await GhostService.pendingProofs()) {
        await upload(id, reportMissing: false);
      }
    } catch (e) {
      debugPrint('[GhostProof] pending sweep failed: $e');
    }
  }

  static Future<void> _fail(String matchId, String reason) async {
    try {
      await ApiService.post('/ghost/matches/$matchId/proof/failed', {'reason': reason});
    } catch (e) {
      debugPrint('[GhostProof] could not record failure: $e');
    }
  }
}
