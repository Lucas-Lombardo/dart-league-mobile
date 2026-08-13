import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

import 'api_service.dart';
import 'camera_frame_service.dart';

/// Diagnostic capture of the FIRST placement match — the one half the players
/// abandon (2026-08-12 prod audit: 377 forfeits vs 385 finishes against bot
/// #1, 70% of them without a single recorded visit).
///
/// The rounds we store server-side only say what the app *counted*. They can
/// never answer the actual question: were three darts in the board when the
/// app counted one? A frame taken at the moment the visit is validated does.
///
/// Two rules shape everything here:
///
/// - **Upload NOW, never at the end.** The players this exists for close the
///   app and never come back (none of the four abandons of 2026-08-11/12
///   ever reopened it). Anything buffered for a post-match flush — the way
///   DatasetCaptureService defers, because it shares the device with a live
///   P2P call — would die with the process. A placement match has no call to
///   protect, so each ~100KB frame goes out on the spot.
/// - **Never get in the way.** One capture in flight at a time, everything
///   off the UI thread, every failure silent, a hard per-match cap, and a
///   backend refusal pauses the whole thing for the session.
///
/// The backend drops a match's frames as soon as it ends normally, and the
/// keys sit under R2's 7-day `ephemeral/` lifecycle rule — what survives is
/// only what was asked for: the matches that went wrong.
class PlacementDebugCapture {
  /// Remote kill-switch from /app/version-config (`placementDebugEnabled`).
  /// Fail-closed: stays off until the backend says otherwise, and drops back
  /// to off for the session when a presign is refused.
  static bool remoteEnabled = false;

  /// Hard ceiling per match — the backend enforces 30, we stay under it so a
  /// legitimate long leg never hits a 429.
  static const int _maxFrames = 24;

  /// Longest side of an uploaded frame. Enough to count darts in the board,
  /// small enough (~80-120KB) to send on mobile data without a second
  /// thought.
  static const int _maxEdge = 960;

  static String? _matchId;
  static int _seq = 0;
  static bool _busy = false;
  static DateTime? _startedAt;
  static final List<Map<String, dynamic>> _visits = [];
  static Map<String, dynamic> _health = {};

  static bool get isActive => remoteEnabled && _matchId != null;

  /// Called when the placement game screen opens. [botDifficulty] 1 is the
  /// first placement match — the only one captured.
  static void startMatch({required String? matchId, required int? botDifficulty}) {
    if (matchId == null || botDifficulty != 1) return;
    _matchId = matchId;
    _seq = 0;
    _startedAt = DateTime.now();
    _visits.clear();
    _health = {};
  }

  static void endMatch() {
    _matchId = null;
    _visits.clear();
  }

  /// One frame + the rolling meta object. [reason] must stay within the
  /// backend's `[a-z0-9_]{1,40}` slug — it IS the filename, and the point is
  /// to read a dump without opening every image.
  ///
  /// Fire-and-forget: callers never await this, and it never throws.
  static Future<void> capture(
    CameraFrameService? camera, {
    required String reason,
    Map<String, dynamic>? health,
  }) async {
    if (!isActive || _busy || camera == null) return;
    if (_seq >= _maxFrames) return;
    _busy = true;
    final matchId = _matchId!;
    final seq = _seq++;
    if (health != null) _health = health;

    String? path;
    try {
      path = await camera.captureFrame();
      if (path == null) {
        // No frame at all: the camera pipeline is dead, which is itself the
        // answer. The meta object still goes out to say so.
        await _putMeta(matchId, note: 'no_frame_$reason');
        return;
      }
      final raw = await File(path).readAsBytes();
      final small = await compute(_shrink, raw);
      if (small == null) return;
      await _put(matchId, seq, reason, small, 'jpg', 'image/jpeg');
      await _putMeta(matchId);
    } catch (e) {
      debugPrint('[PlacementDebug] capture dropped: $e');
    } finally {
      if (path != null) {
        try {
          await File(path).delete();
        } catch (_) {}
      }
      _busy = false;
    }
  }

  /// Meta-only report, for the paths where there is no frame to take: camera
  /// that never initialised, model that never loaded. "No camera at all" is
  /// one of the candidate explanations for a match with zero recorded visits,
  /// and it is invisible everywhere else.
  static Future<void> note(String note, {Map<String, dynamic>? health}) async {
    if (!isActive || _busy) return;
    _busy = true;
    try {
      if (health != null) _health = health;
      await _putMeta(_matchId!, note: note);
    } catch (e) {
      debugPrint('[PlacementDebug] note dropped: $e');
    } finally {
      _busy = false;
    }
  }

  /// Records a validated visit for the meta object. Kept even when the
  /// bot-turn call fails — a leg the server never saw is exactly the kind of
  /// zombie match this is meant to expose.
  static void recordVisit({
    required int roundIndex,
    required int dartsRegistered,
    required int roundScore,
    required int remaining,
    required bool sentToServer,
  }) {
    if (!isActive) return;
    _visits.add({
      'r': roundIndex,
      'darts': dartsRegistered,
      'score': roundScore,
      'left': remaining,
      if (!sentToServer) 'lost': true,
    });
  }

  static Future<void> _putMeta(String matchId, {String? note}) async {
    final meta = <String, dynamic>{
      'matchId': matchId,
      'startedAt': _startedAt?.toIso8601String(),
      'at': DateTime.now().toIso8601String(),
      'platform': Platform.isIOS ? 'ios' : 'android',
      'frames': _seq,
      'visits': _visits,
      ..._health,
      'note': ?note,
    };
    final bytes = utf8.encode(jsonEncode(meta));
    await _put(matchId, 0, 'meta', bytes, 'json', 'application/json');
  }

  static Future<void> _put(
    String matchId,
    int seq,
    String reason,
    List<int> body,
    String kind,
    String contentType,
  ) async {
    Map<String, dynamic> presign;
    try {
      final res = await ApiService.post('/placement-debug/presign', {
        'matchId': matchId,
        'seq': seq,
        'reason': reason,
        'kind': kind,
        'sizeBytes': body.length,
      });
      presign = res as Map<String, dynamic>;
    } catch (e) {
      // A refusal is the backend closing the tap (flag off, cap reached,
      // quota) — stop asking for the rest of the session. The flag re-arms
      // at the next version-config read.
      remoteEnabled = false;
      debugPrint('[PlacementDebug] presign refused, pausing: $e');
      return;
    }

    // The presigned PUT goes straight to R2 — no auth headers, and the
    // content type/length must match what was signed.
    final put = await http
        .put(
          Uri.parse(presign['url'] as String),
          headers: {'Content-Type': contentType},
          body: body,
        )
        .timeout(const Duration(seconds: 30));
    if (put.statusCode < 200 || put.statusCode >= 300) {
      debugPrint('[PlacementDebug] PUT ${put.statusCode} for $reason');
    }
  }
}

/// Runs in an isolate: decode the camera's JPEG, fit it in [_maxEdge] and
/// re-encode small. Returns null rather than throwing — a diagnostic frame is
/// always expendable.
Uint8List? _shrink(Uint8List jpeg) {
  try {
    final decoded = img.decodeJpg(jpeg);
    if (decoded == null) return null;
    final longest =
        decoded.width > decoded.height ? decoded.width : decoded.height;
    final resized = longest <= PlacementDebugCapture._maxEdge
        ? decoded
        : img.copyResize(
            decoded,
            width: decoded.width >= decoded.height
                ? PlacementDebugCapture._maxEdge
                : null,
            height: decoded.height > decoded.width
                ? PlacementDebugCapture._maxEdge
                : null,
            interpolation: img.Interpolation.average,
          );
    return Uint8List.fromList(img.encodeJpg(resized, quality: 78));
  } catch (_) {
    return null;
  }
}
