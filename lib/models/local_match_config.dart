/// Configuration for a local (hot-seat) 1v1 match.
///
/// Pure value object — the local match is entirely client-side: nothing here is
/// ever sent to the backend, persisted, or counted in stats.
class LocalMatchConfig {
  /// X01 starting score (301 / 501 / 701).
  final int startingScore;

  /// Match length in legs (1 / 3 / 5). "Best of" — first to [legsToWin] wins.
  final int bestOf;

  /// When true, a leg must be finished on a double (and leaving 1 busts).
  final bool doubleOut;

  final String player1Name;
  final String player2Name;

  const LocalMatchConfig({
    this.startingScore = 501,
    this.bestOf = 3,
    this.doubleOut = true,
    required this.player1Name,
    required this.player2Name,
  });

  /// Legs needed to win the match (e.g. best of 3 → 2).
  int get legsToWin => (bestOf ~/ 2) + 1;

  String nameOf(int player) => player == 0 ? player1Name : player2Name;
}
