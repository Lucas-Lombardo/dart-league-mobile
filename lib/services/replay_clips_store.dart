import 'package:flutter/foundation.dart';

/// Where a clip stands on its way to the cloud library. Every capture starts
/// [preparing] (raw cut done, end-of-match overlay render + upload still
/// ahead); the upload flips it to [cloud] on confirm or [failed] when the
/// upload is refused (quota) or errors — the clip then stays local-only.
enum ReplayClipStatus { preparing, cloud, failed }

/// One captured replay clip, local-first: [path] points at the MP4 in the
/// app cache. Upload to R2 / backend registration ride on top later (R1c) —
/// sharing never waits for them.
class ReplayClip {
  ReplayClip({
    required this.path,
    required this.createdAt,
    this.matchId,
    this.opponent,
    this.turnTotal,
    this.durationMs,
  });

  /// Mutable on purpose: the capture stores the RAW cut, and the deferred
  /// end-of-match render swaps in the overlay-dressed file (the store and the
  /// match list hold this same object, so both see the upgrade).
  String path;
  final DateTime createdAt;
  final String? matchId;

  /// Opponent's username at capture time — what the library's pending row
  /// shows while the cloud group (which carries the real match context) does
  /// not exist yet.
  final String? opponent;
  final int? turnTotal;

  /// Clip length as the native cut reported it — uploaded with the clip so
  /// the library can show it.
  final int? durationMs;

  /// Updated by the end-of-match pipeline; bump [ReplayClipsStore.touch]
  /// after changing it so the library re-syncs.
  ReplayClipStatus status = ReplayClipStatus.preparing;
}

/// In-memory session store of the clips captured since app launch — feeds
/// the MatchEndView "moments" row and the library page. The files
/// themselves persist in cache; a follow-up lists the directory to rebuild
/// history across launches.
class ReplayClipsStore {
  static final List<ReplayClip> clips = [];

  /// Bumped on every add/status change. The library listens to it to show
  /// freshly captured clips as "preparing" rows and to refetch the cloud
  /// list the moment an upload lands.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static void touch() => revision.value++;

  static void add(ReplayClip clip) {
    clips.insert(0, clip);
    touch();
  }

  static List<ReplayClip> forMatch(String matchId) =>
      clips.where((c) => c.matchId == matchId).toList();

  /// Clips still on their way to the cloud, newest first (list order).
  static List<ReplayClip> preparing() => clips
      .where((c) => c.status == ReplayClipStatus.preparing)
      .toList(growable: false);
}
