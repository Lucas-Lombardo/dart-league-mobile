/// One captured replay clip, local-first: [path] points at the MP4 in the
/// app cache. Upload to R2 / backend registration ride on top later (R1c) —
/// sharing never waits for them.
class ReplayClip {
  ReplayClip({
    required this.path,
    required this.createdAt,
    this.matchId,
    this.turnTotal,
  });

  final String path;
  final DateTime createdAt;
  final String? matchId;
  final int? turnTotal;
}

/// In-memory session store of the clips captured since app launch — feeds
/// the MatchEndView "moments" row and the library page. The files
/// themselves persist in cache; a follow-up lists the directory to rebuild
/// history across launches.
class ReplayClipsStore {
  static final List<ReplayClip> clips = [];

  static void add(ReplayClip clip) => clips.insert(0, clip);

  static List<ReplayClip> forMatch(String matchId) =>
      clips.where((c) => c.matchId == matchId).toList();
}
