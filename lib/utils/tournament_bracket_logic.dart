import '../models/tournament.dart';

/// Indexed, read-only view of a bracket: rounds in order, matches per round
/// sorted by match number, and the feeder links (which matches send their
/// winner into which slot). Pure Dart so the tree layout and the "where am I"
/// resolution can be unit-tested without widgets.
class BracketIndex {
  final List<int> rounds;
  final Map<int, List<TournamentMatch>> byRound;
  final Map<String, TournamentMatch> byId;
  final Map<String, List<TournamentMatch>> _feeders;

  BracketIndex._(this.rounds, this.byRound, this.byId, this._feeders);

  factory BracketIndex(List<TournamentMatch> bracket) {
    final byRound = <int, List<TournamentMatch>>{};
    final byId = <String, TournamentMatch>{};
    for (final m in bracket) {
      byRound.putIfAbsent(m.roundNumber, () => []).add(m);
      byId[m.id] = m;
    }
    for (final list in byRound.values) {
      list.sort((a, b) => a.matchNumber.compareTo(b.matchNumber));
    }
    final rounds = byRound.keys.toList()..sort();
    final feeders = <String, List<TournamentMatch>>{};
    for (final round in rounds) {
      for (final m in byRound[round]!) {
        final next = m.nextMatchId;
        if (next != null && byId.containsKey(next)) {
          feeders.putIfAbsent(next, () => []).add(m);
        }
      }
    }
    for (final list in feeders.values) {
      list.sort((a, b) => a.matchNumber.compareTo(b.matchNumber));
    }
    return BracketIndex._(rounds, byRound, byId, feeders);
  }

  bool get isEmpty => rounds.isEmpty;
  int get lastRound => rounds.last;

  /// Matches whose winner advances into [match], lowest match number first
  /// (that order is the slot order: first feeder → player 1, second → player 2).
  List<TournamentMatch> feedersOf(TournamentMatch match) =>
      _feeders[match.id] ?? const [];

  bool isRoundComplete(int round) =>
      byRound[round]!.every((m) => m.isCompleted);

  /// The round being played: the first one with an unfinished match, or the
  /// last round once everything is settled.
  int get activeRound => rounds.firstWhere(
    (r) => byRound[r]!.any((m) => !m.isCompleted),
    orElse: () => rounds.last,
  );

  /// The unfinished match that must end before [match]'s empty slot fills.
  /// Null when both slots are known or when the bracket carries no link.
  TournamentMatch? pendingFeederOf(TournamentMatch match) {
    final feeders = feedersOf(match);
    if (feeders.isEmpty) return null;
    if (match.player1Id != null && match.player2Id != null) return null;
    if (feeders.length == 1) {
      return feeders.first.isCompleted ? null : feeders.first;
    }
    final slot = match.player1Id == null ? 0 : 1;
    final feeder = feeders[slot];
    if (!feeder.isCompleted) return feeder;
    // The slot is empty although its feeder is over (e.g. a dispute rollback):
    // fall back to the other side if it is still open.
    final other = feeders[1 - slot];
    return other.isCompleted ? null : other;
  }

  /// The feeder for a given empty slot (0 = player 1, 1 = player 2), used to
  /// label the placeholder ("Gagnant demi 2"). Null when unknown.
  TournamentMatch? feederForSlot(TournamentMatch match, int slot) {
    final feeders = feedersOf(match);
    if (feeders.length == 2) return feeders[slot];
    if (feeders.length == 1) {
      // One feeder only: it fills whichever slot is still empty.
      final emptySlot = match.player1Id == null ? 0 : 1;
      return slot == emptySlot ? feeders.first : null;
    }
    return null;
  }

  bool isFinal(TournamentMatch match) =>
      match.roundName == 'final' ||
      (match.nextMatchId == null && match.roundNumber == lastRound);
}

/// What the signed-in player should be told about, in priority order.
enum TournamentFocusKind {
  /// Not in this bracket (spectator, or registration not drawn).
  none,

  /// Invited to a match that has not started: join now.
  ready,

  /// A live leg exists to reconnect to.
  resumable,

  /// Playing right now but no leg to resume (transient).
  inProgress,

  /// The result of the player's match is under admin review.
  disputed,

  /// Has a match ahead but cannot play yet (opponent unknown or not invited).
  waiting,

  /// Won the last match; the next one is not in the bracket yet (transient).
  qualified,

  /// Lost — the tournament goes on without them.
  eliminated,

  /// The player's match ended with no winner (double forfeit).
  notPlayed,

  /// Won the final.
  champion,
}

class TournamentFocus {
  final TournamentFocusKind kind;

  /// The match the focus card talks about (the open one, or the last one).
  final TournamentMatch? match;

  /// For [TournamentFocusKind.waiting]: the unfinished match whose winner
  /// becomes the player's opponent. Null when no link is known.
  final TournamentMatch? dependency;

  const TournamentFocus(this.kind, {this.match, this.dependency});

  static const none = TournamentFocus(TournamentFocusKind.none);

  bool get isNone => kind == TournamentFocusKind.none;
}

/// Where the player stands, from the bracket alone plus the two provider
/// lists that drive the CTA (pending invites, live leg).
TournamentFocus resolveTournamentFocus({
  required BracketIndex index,
  required String? userId,
  required List<TournamentMatch> pendingMatches,
  TournamentMatch? activeMatch,
}) {
  if (userId == null || index.isEmpty) return TournamentFocus.none;

  final mine = <TournamentMatch>[];
  for (final round in index.rounds) {
    for (final m in index.byRound[round]!) {
      if (m.player1Id == userId || m.player2Id == userId) mine.add(m);
    }
  }
  if (mine.isEmpty) return TournamentFocus.none;

  // At most one open match at a time; take the earliest round if the data
  // ever disagrees, since that is the one that blocks everything after it.
  TournamentMatch? open;
  for (final m in mine) {
    if (!m.isCompleted) {
      open = m;
      break;
    }
  }

  if (open != null) {
    if (open.isDisputed) {
      return TournamentFocus(TournamentFocusKind.disputed, match: open);
    }
    if (open.isInProgress) {
      final resumable =
          activeMatch != null &&
          activeMatch.id == open.id &&
          activeMatch.isInProgress &&
          activeMatch.lastGameId != null;
      return TournamentFocus(
        resumable
            ? TournamentFocusKind.resumable
            : TournamentFocusKind.inProgress,
        match: open,
      );
    }
    final bothKnown = open.player1Id != null && open.player2Id != null;
    final invited = pendingMatches.any((m) => m.id == open!.id);
    if (bothKnown && open.isWaitingForPlayers && invited) {
      return TournamentFocus(TournamentFocusKind.ready, match: open);
    }
    return TournamentFocus(
      TournamentFocusKind.waiting,
      match: open,
      dependency: bothKnown ? null : index.pendingFeederOf(open),
    );
  }

  final last = mine.last;
  if (last.winnerId == null) {
    return TournamentFocus(TournamentFocusKind.notPlayed, match: last);
  }
  if (last.winnerId == userId) {
    return TournamentFocus(
      index.isFinal(last)
          ? TournamentFocusKind.champion
          : TournamentFocusKind.qualified,
      match: last,
    );
  }
  return TournamentFocus(TournamentFocusKind.eliminated, match: last);
}

/// Ids of the matches [userId] won — the blue path through the tree.
Set<String> wonMatchIds(BracketIndex index, String? userId) {
  if (userId == null) return const {};
  final ids = <String>{};
  for (final m in index.byId.values) {
    if (m.winnerId == userId) ids.add(m.id);
  }
  return ids;
}

/// Geometry of one match tile inside the tree (logical pixels, origin at the
/// tree's top-left, headers excluded).
class BracketTileGeometry {
  final TournamentMatch match;
  final int round;
  final double x;
  final double y;
  final double width;
  final double height;
  final bool compact;

  const BracketTileGeometry({
    required this.match,
    required this.round,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.compact,
  });

  double get centerY => y + height / 2;
  double get right => x + width;
  double get bottom => y + height;
}

class BracketLayout {
  final List<BracketTileGeometry> tiles;
  final Map<String, BracketTileGeometry> byMatchId;
  final Map<int, double> columnX;
  final Map<int, double> columnWidth;
  final Set<int> compactRounds;
  final double width;
  final double height;
  final double gutter;

  const BracketLayout({
    required this.tiles,
    required this.byMatchId,
    required this.columnX,
    required this.columnWidth,
    required this.compactRounds,
    required this.width,
    required this.height,
    required this.gutter,
  });
}

/// Lays the bracket out as columns (one per round). Finished rounds other
/// than the last one collapse to narrow tiles so an 8-player bracket fits a
/// phone without scrolling; each later match sits at the midpoint of its two
/// feeders, like a paper bracket. [topInset] leaves room for the marker
/// pinned above a tile.
BracketLayout computeBracketLayout(
  BracketIndex index, {
  double tileWidth = 124,
  double tileHeight = 91,
  double compactWidth = 92,
  double compactHeight = 53,
  double gutter = 16,
  double gap = 24,
  double compactGap = 16,
  double topInset = 28,
}) {
  final tiles = <BracketTileGeometry>[];
  final byMatchId = <String, BracketTileGeometry>{};
  final columnX = <int, double>{};
  final columnWidth = <int, double>{};
  final compactRounds = <int>{};

  double x = 0;
  double maxBottom = topInset;
  for (final round in index.rounds) {
    final compact = round != index.lastRound && index.isRoundComplete(round);
    if (compact) compactRounds.add(round);
    final w = compact ? compactWidth : tileWidth;
    final h = compact ? compactHeight : tileHeight;
    final g = compact ? compactGap : gap;
    columnX[round] = x;
    columnWidth[round] = w;

    double? prevBottom;
    for (final match in index.byRound[round]!) {
      final feeders = index
          .feedersOf(match)
          .map((f) => byMatchId[f.id])
          .whereType<BracketTileGeometry>()
          .toList();
      double y;
      if (feeders.isNotEmpty) {
        final center =
            feeders.map((f) => f.centerY).reduce((a, b) => a + b) /
            feeders.length;
        y = center - h / 2;
      } else {
        y = prevBottom == null ? topInset : prevBottom + g;
      }
      if (prevBottom != null && y < prevBottom + g) y = prevBottom + g;
      if (y < topInset) y = topInset;
      final tile = BracketTileGeometry(
        match: match,
        round: round,
        x: x,
        y: y,
        width: w,
        height: h,
        compact: compact,
      );
      tiles.add(tile);
      byMatchId[match.id] = tile;
      prevBottom = tile.bottom;
      if (tile.bottom > maxBottom) maxBottom = tile.bottom;
    }
    x += w + gutter;
  }

  return BracketLayout(
    tiles: tiles,
    byMatchId: byMatchId,
    columnX: columnX,
    columnWidth: columnWidth,
    compactRounds: compactRounds,
    width: x - gutter,
    height: maxBottom,
    gutter: gutter,
  );
}
