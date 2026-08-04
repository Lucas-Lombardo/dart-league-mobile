import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_service.dart';
import 'replay_clips_store.dart';

/// Background upload of captured clips to the user's cloud library:
/// presign → PUT straight to R2 → confirm. Fire-and-forget by design — a
/// capture is ALWAYS usable locally (share sheet included) whether or not
/// the upload lands; the library screen simply shows what made it.
class ReplayUploadService {
  /// Set when the backend refused the upload for quota (5 free clips) —
  /// the library screen turns it into the premium upsell banner.
  static bool quotaReached = false;

  static Future<void> uploadClip(ReplayClip clip) async {
    try {
      final file = File(clip.path);
      if (!await file.exists()) return;
      final size = await file.length();

      final presign = await ApiService.post('/replays/presign', {
        'sizeBytes': size,
      });
      final url = presign['url'] as String;
      final key = presign['key'] as String;

      // The presigned PUT goes straight to R2 — no auth headers, and the
      // content type/length must match what was signed.
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

      await ApiService.post('/replays', {
        'key': key,
        'matchId': ?clip.matchId,
        // Every clip is a manual capture now; the backend still accepts the
        // old 'highlight' value for apps that have not updated.
        'type': 'manual',
        'turnTotal': ?clip.turnTotal,
        'durationMs': ?clip.durationMs,
        'sizeBytes': size,
      });
      quotaReached = false;
      // The library swaps the clip's "preparing" row for its cloud row on
      // this notify (it refetches /replays/mine, which now has the clip).
      clip.status = ReplayClipStatus.cloud;
      ReplayClipsStore.touch();
      debugPrint('[ReplayUpload] uploaded ${clip.path}');
    } catch (e) {
      if (e.toString().contains('quota')) quotaReached = true;
      // Local-only from here: the pending row disappears (the cloud library
      // will never list this clip) and the quota banner explains the why
      // when that is the cause.
      clip.status = ReplayClipStatus.failed;
      ReplayClipsStore.touch();
      debugPrint('[ReplayUpload] failed (kept local): $e');
    }
  }
}
