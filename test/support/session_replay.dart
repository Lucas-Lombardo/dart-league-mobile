import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'package:mobile/services/auto_scoring_service.dart';
import 'package:mobile/services/dart_detection_types.dart';
import 'package:mobile/services/dart_scoring_service.dart';
import 'package:mobile/services/detection_parsing.dart';

/// Replays a session recorded by autoscoring_lab through the app's real
/// scorer, offline and deterministic: every recorded frame (calibration points
/// + tips, as the phone's model saw them) is rebuilt into a ScoringResult and
/// fed to [AutoScoringService.debugProcessResult] under the recorded clock,
/// with the player's recorded actions (visit starts, edits, removals) applied
/// between frames where they happened.
///
/// The model is not re-run: this measures everything AFTER the model —
/// calibration use, grouping, dedup, gates, slots — against what the player
/// kept at the end of each visit (the ground truth).
class SessionReplay {
  SessionReplay(this.frames, this.events);

  factory SessionReplay.load(String dir) {
    List<Map<String, dynamic>> read(String name) {
      final f = File('$dir/$name');
      if (!f.existsSync()) return [];
      return f
          .readAsLinesSync()
          .where((l) => l.trim().isNotEmpty)
          .map((l) => jsonDecode(l) as Map<String, dynamic>)
          .toList();
    }

    return SessionReplay(read('frames.jsonl'), read('events.jsonl'));
  }

  final List<Map<String, dynamic>> frames;
  final List<Map<String, dynamic>> events;

  static const Set<String> _inputEvents = {
    'visit_start',
    'turn_start',
    'capture_start',
    'edit',
    'remove',
    'clear',
    'sync',
  };

  /// [verbose] turns the scorer's per-frame trace on (it prints).
  Future<ReplayScorecard> run({bool verbose = false}) async {
    final card = ReplayScorecard();
    for (final e in events) {
      if (e['type'] == 'visit') {
        card.truth[e['visit'] as int] =
            (e['slots'] as List).whereType<String>().toList();
      }
      if (e['type'] == 'dart_emitted') {
        card.recordedEmits
            .add(ReplayEmit(e['visit'] as int, e['seq'] as int, _formatted(e['score'])));
      }
      if (e['type'] == 'auto_confirm') card.recordedAutoConfirms++;
    }

    final svc = AutoScoringService();
    final savedClock = AutoScoringService.clock;
    final savedVerbose = AutoScoringService.verboseScoringLog;
    final savedPrint = debugPrint;
    AutoScoringService.verboseScoringLog = verbose;
    // The scorer's per-frame debug summary would print ~2000 lines.
    debugPrint = (String? message, {int? wrapWidth}) {};
    final pending =
        events.where((e) => _inputEvents.contains(e['type'])).toList();
    // The recorded pipeline closed these visits itself (auto-confirm) and the
    // lab opened the next one on the spot. Replaying a different pipeline,
    // the next visit must open when THE REPLAY closes the visit — or, failing
    // that, when the player starts throwing again.
    final recordedCloses = <int, double>{};
    for (final e in events) {
      if (e['type'] == 'auto_confirm') {
        recordedCloses[e['seq'] as int] = (e['ts'] as num).toDouble() / 1000.0;
      }
    }
    var visit = 0;
    final deferred = <Map<String, dynamic>>[];
    double? deferredSince;
    var closedThisFrame = false;

    void apply(Map<String, dynamic> e) {
        switch (e['type']) {
          case 'visit_start':
          case 'turn_start':
            visit = (e['visit'] as int?) ?? visit + 1;
            svc.resetTurn();
            svc.waitForEmptyBoardOnce();
            break;
          case 'capture_start':
            svc.debugMarkCaptureStart();
            break;
          case 'edit':
            svc.overrideDart(
                e['index'] as int, _scoreFromJson(e['score'] as Map));
            break;
          case 'remove':
            svc.removeDart(e['index'] as int);
            break;
          case 'clear':
            svc.clearDart(e['index'] as int);
            break;
          case 'sync':
            svc.syncEmittedCount(e['count'] as int);
            break;
        }
    }

    void openDeferred() {
      for (final e in deferred) {
        apply(e);
      }
      deferred.clear();
      deferredSince = null;
    }

    void applyUpTo(int seq) {
      while (pending.isNotEmpty && (pending.first['seq'] as int) <= seq) {
        final e = pending.removeAt(0);
        final s = e['seq'] as int;
        final opensAfterAutoClose = recordedCloses.containsKey(s) &&
            (e['type'] == 'visit_start' ||
                (e['type'] == 'capture_start' && deferred.isNotEmpty));
        if (opensAfterAutoClose) {
          deferred.add(e);
          deferredSince ??= recordedCloses[s];
          continue;
        }
        apply(e);
      }
    }

    try {
      var lastSeq = 0;
      for (final f in frames) {
        final seq = (f['seq'] as num?)?.toInt() ?? lastSeq + 1;
        applyUpTo(seq - 1);
        final clockS = (f['clock'] as num?)?.toDouble() ??
            ((f['ts'] as num).toDouble() / 1000.0);
        AutoScoringService.clock = () => clockS;
        // The player is throwing again and the replay never closed the visit.
        final hasTips = (f['tips'] as List? ?? const []).isNotEmpty;
        if (deferred.isNotEmpty &&
            (hasTips || clockS - deferredSince! > 6.0)) {
          card.visitsNotClosed++;
          openDeferred();
        }
        final v = visit;
        closedThisFrame = false;
        await svc.debugProcessResult(
          scoringResultFromJson(f),
          seq: seq,
          inferenceMs: (f['ms'] as num?)?.toInt(),
          onDartDetected: (slot, score) =>
              card.replayEmits.add(ReplayEmit(v, seq, score.formatted)),
          onAutoConfirm: () {
            card.autoConfirmsByVisit[v] =
                (card.autoConfirmsByVisit[v] ?? 0) + 1;
            closedThisFrame = true;
          },
        );
        if (closedThisFrame && deferred.isNotEmpty) {
          card.closeDelays.add(clockS - deferredSince!);
          openDeferred();
        }
        lastSeq = seq;
      }
      applyUpTo(1 << 30);
      if (deferred.isNotEmpty) {
        card.visitsNotClosed++;
        openDeferred();
      }
    } finally {
      AutoScoringService.clock = savedClock;
      AutoScoringService.verboseScoringLog = savedVerbose;
      debugPrint = savedPrint;
      svc.dispose();
    }
    card.compute();
    return card;
  }
}

class ReplayEmit {
  ReplayEmit(this.visit, this.seq, this.score);
  final int visit;
  final int seq;
  final String score;
}

/// The six-line report card of one replay, against the darts the player kept
/// at the end of each visit.
class ReplayScorecard {
  final Map<int, List<String>> truth = {};
  final List<ReplayEmit> recordedEmits = [];
  final List<ReplayEmit> replayEmits = [];
  final Map<int, int> autoConfirmsByVisit = {};
  int recordedAutoConfirms = 0;

  int truthDarts = 0;
  int correct = 0;
  int wrongValue = 0;
  int missed = 0;
  int extra = 0;
  int prematureClosures = 0;
  int autoConfirms = 0;

  /// Visits the recorded pipeline closed on its own but the replay did not
  /// close before the player threw again (or within 6 s).
  int visitsNotClosed = 0;

  /// For visits both closed: replay close time − recorded close time, s.
  final List<double> closeDelays = [];

  /// Mean (replay emit frame − recorded emit frame) over darts both emitted
  /// with the same score in the same visit: + = the replay scores later.
  double meanEmitDelayFrames = 0;

  void compute() {
    final delays = <int>[];
    for (final entry in truth.entries) {
      final want = List<String>.of(entry.value);
      truthDarts += want.length;
      final got = replayEmits.where((e) => e.visit == entry.key).toList();
      final unmatched = <String>[];
      for (final g in got) {
        if (want.remove(g.score)) {
          correct++;
        } else {
          unmatched.add(g.score);
        }
      }
      final wrong = unmatched.length < want.length ? unmatched.length : want.length;
      wrongValue += wrong;
      missed += want.length - wrong;
      extra += unmatched.length - wrong;
      // A visit closed by the AI before all of its darts were scored.
      final closes = autoConfirmsByVisit[entry.key] ?? 0;
      autoConfirms += closes;
      if (closes > 0 && got.length < entry.value.length) prematureClosures++;

      final rec = recordedEmits.where((e) => e.visit == entry.key).toList();
      for (final g in got) {
        final i = rec.indexWhere((r) => r.score == g.score);
        if (i >= 0) {
          delays.add(g.seq - rec[i].seq);
          rec.removeAt(i);
        }
      }
    }
    if (delays.isNotEmpty) {
      meanEmitDelayFrames = delays.reduce((a, b) => a + b) / delays.length;
    }
  }

  String summary() => [
        'darts to score: $truthDarts (${truth.length} visits)',
        '  correct      : $correct',
        '  wrong value  : $wrongValue',
        '  missed       : $missed',
        '  extra (phantom/duplicate): $extra',
        'visits closed too early: $prematureClosures '
            '(auto-confirms $autoConfirms, recorded $recordedAutoConfirms)',
        'visits left open (recording closed them): $visitsNotClosed',
        'auto-close delay vs recording: '
            '${closeDelays.isEmpty ? '-' : (closeDelays.reduce((a, b) => a + b) / closeDelays.length).toStringAsFixed(2)} s mean, '
            '${closeDelays.isEmpty ? '-' : closeDelays.reduce(max).toStringAsFixed(2)} s max',
        'emit delay vs recording: ${meanEmitDelayFrames.toStringAsFixed(2)} frames',
      ].join('\n');
}

/// Rebuild the scorer's input for one recorded frame, scoring the tips from
/// the recorded calibration exactly like scoreParsedDetections does.
ScoringResult scoringResultFromJson(Map<String, dynamic> f) {
  final w = (f['w'] as num?)?.toInt() ?? 1;
  final h = (f['h'] as num?)?.toInt() ?? 1;
  final cps = <Detection>[];
  for (final c in (f['cps'] as List? ?? const [])) {
    final cls = c['cls'] as String;
    final id = kDetectionLabels.indexOf(cls);
    if (id < 0) continue;
    cps.add(Detection(
      classId: id,
      className: cls,
      x: (c['x'] as num).toDouble(),
      y: (c['y'] as num).toDouble(),
      width: (c['w'] as num?)?.toDouble() ?? 0.02,
      height: (c['h'] as num?)?.toDouble() ?? 0.02,
      confidence: (c['conf'] as num).toDouble(),
    ));
  }
  final tips = <Detection>[
    for (final t in (f['tips'] as List? ?? const []))
      Detection(
        classId: 8,
        className: 'tip',
        x: (t['x'] as num).toDouble(),
        y: (t['y'] as num).toDouble(),
        width: (t['w'] as num?)?.toDouble() ?? 0.01,
        height: (t['h'] as num?)?.toDouble() ?? 0.01,
        confidence: (t['conf'] as num).toDouble(),
      ),
  ];
  final fromCache = f['cache'] == 1 || f['cache'] == true;
  // Recordings older than the whole-ring gate carry no 'cpsRaw'; a frame that
  // had its 4 points then behaved like a full read.
  final rawCps = (f['cpsRaw'] as num?)?.toInt() ??
      (cps.length >= 4 ? kControlPointCount : cps.length);
  ScoringResult empty(String error) => ScoringResult(
        calibrationPoints: cps,
        dartTips: tips,
        scores: [],
        totalScore: 0,
        imageWidth: w,
        imageHeight: h,
        error: error,
        calibrationFromCache: fromCache,
        detectedControlPoints: rawCps,
      );
  if (cps.length < 4) return empty('Need 4 control points, found ${cps.length}');
  if (tips.isEmpty) return empty('No darts detected');
  try {
    final scorer = DartScoringService(
        cps.map((c) => [c.x, c.y, c.flag.toDouble()]).toList());
    final scores = tips.map((d) => scorer.score(d.x, d.y)).toList();
    return ScoringResult(
      calibrationPoints: cps,
      dartTips: tips,
      scores: scores,
      totalScore: scores.fold(0, (s, x) => s + x.score),
      imageWidth: w,
      imageHeight: h,
      calibrationFromCache: fromCache,
      detectedControlPoints: rawCps,
    );
  } catch (e) {
    return empty('Scoring error: $e');
  }
}

String _formatted(Object? s) =>
    s is Map ? (s['f'] as String? ?? '') : (s as String? ?? '');

DartScore _scoreFromJson(Map s) => DartScore(
      score: s['score'] as int,
      segment: s['segment'] as int,
      ring: s['ring'] as String,
      radius: (s['radius'] as num?)?.toDouble() ?? 0,
      angle: (s['angle'] as num?)?.toDouble() ?? 0,
      confidence: (s['conf'] as num?)?.toDouble(),
    );
