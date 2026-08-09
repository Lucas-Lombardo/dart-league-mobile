import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import 'dart_detection_types.dart';

/// TEMPORARY debug instrumentation — dumps EVERY analyzed frame of an AI
/// scoring session to local storage for offline model comparison:
///   `Documents/ai_debug/run_<epochMs>/f<seq>.jpg` — the exact pixels analyzed
///   `Documents/ai_debug/run_<epochMs>/frames.jsonl` — one line per frame:
///     timings, raw tips + control points, scorer gate state
///
/// The `<seq>` matches the `[AS f<seq>]` prefix of the verbose scoring log,
/// so log lines, JSONL lines and images all correlate.
///
/// iOS pixel paths only (BGRA/RGBA — what _fireCapture hands to inference);
/// the Android YUV path is not wired. Debug builds only, and inert unless
/// [enabled] is flipped on. Never touches the scoring path: pixels are copied
/// at call time, JPEG encoding runs in an isolate, failures are silent.
class DebugFrameDumpService {
  /// Master switch — keep false except during an analysis session.
  static const bool enabled = true;

  // Encode back-pressure: beyond this many JPEG encodes in flight the image
  // is skipped (its JSONL line still records everything else + the skip).
  static const int _maxInFlight = 3;

  static Directory? _dir;
  static RandomAccessFile? _jsonl;
  static bool _initStarted = false;
  static int _inFlight = 0;
  static int _skippedImages = 0;

  /// One dump directory per app process, created on first use.
  static Future<void> armSession() async {
    if (!enabled || !kDebugMode || _initStarted) return;
    _initStarted = true;
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory(
          '${docs.path}/ai_debug/run_${DateTime.now().millisecondsSinceEpoch}');
      await dir.create(recursive: true);
      _jsonl = await File('${dir.path}/frames.jsonl')
          .open(mode: FileMode.writeOnlyAppend);
      _dir = dir;
      debugPrint('[FrameDump] session dir: ${dir.path}');
    } catch (e) {
      debugPrint('[FrameDump] init failed, dump disabled: $e');
    }
  }

  /// Record one analyzed frame + its result. Called from _fireCapture right
  /// after inference, BEFORE any gate can early-return, so misses and gated
  /// frames are captured too.
  static void capture({
    required Uint8List pixels,
    required int width,
    required int height,
    required bool isBgra,
    required int seq,
    required ScoringResult result,
    int? totalMs,
    int? nativeMs,
    bool waitingForEmptyBoard = false,
    bool gateSawDarts = false,
  }) {
    if (!enabled || !kDebugMode) return;
    if (_dir == null) {
      unawaited(armSession());
      return;
    }

    final skipImage = _inFlight >= _maxInFlight;
    try {
      _jsonl?.writeStringSync('${jsonEncode({
            'seq': seq,
            'ts': DateTime.now().millisecondsSinceEpoch,
            'w': width,
            'h': height,
            'totalMs': totalMs,
            'nativeMs': nativeMs,
            'err': result.error,
            'wait': waitingForEmptyBoard ? 1 : 0,
            'sawDarts': gateSawDarts ? 1 : 0,
            'cps': [
              for (final c in result.calibrationPoints)
                {
                  'cls': c.className,
                  'x': c.x,
                  'y': c.y,
                  'conf': double.parse(c.confidence.toStringAsFixed(3)),
                },
            ],
            'tips': [
              for (int i = 0; i < result.dartTips.length; i++)
                {
                  'x': result.dartTips[i].x,
                  'y': result.dartTips[i].y,
                  'conf': double.parse(
                      result.dartTips[i].confidence.toStringAsFixed(3)),
                  'score': i < result.scores.length
                      ? result.scores[i].formatted
                      : null,
                },
            ],
            if (skipImage) 'imgSkipped': true,
          })}\n');
    } catch (_) {}

    if (skipImage) {
      _skippedImages++;
      if (_skippedImages % 10 == 1) {
        debugPrint('[FrameDump] $_skippedImages images skipped (encoder behind)');
      }
      return;
    }

    _inFlight++;
    final copy = Uint8List.fromList(pixels);
    unawaited(compute(
      _encodeJpeg,
      _EncodeJob(copy, width, height, isBgra),
    ).then((jpeg) async {
      if (jpeg == null) return;
      final path = '${_dir!.path}/f${seq.toString().padLeft(6, '0')}.jpg';
      await File(path).writeAsBytes(jpeg);
    }).catchError((Object e) {
      debugPrint('[FrameDump] frame $seq dropped: $e');
    }).whenComplete(() => _inFlight--));
  }
}

class _EncodeJob {
  final Uint8List pixels;
  final int width, height;
  final bool isBgra;
  _EncodeJob(this.pixels, this.width, this.height, this.isBgra);
}

Uint8List? _encodeJpeg(_EncodeJob job) {
  try {
    final image = img.Image.fromBytes(
      width: job.width,
      height: job.height,
      bytes: job.pixels.buffer,
      order: job.isBgra ? img.ChannelOrder.bgra : img.ChannelOrder.rgba,
    );
    return Uint8List.fromList(img.encodeJpg(image, quality: 90));
  } catch (_) {
    return null;
  }
}
