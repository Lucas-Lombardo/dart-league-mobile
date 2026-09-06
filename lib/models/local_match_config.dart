import 'cricket.dart';

/// Game family of a local match: X01 (301 / 501 / 701) or cricket.
enum LocalGameMode { x01, cricket }

/// Configuration for a local (hot-seat) 1v1 match.
///
/// Pure value object — the local match is entirely client-side: nothing here is
/// ever sent to the backend, persisted, or counted in stats.
class LocalMatchConfig {
  final LocalGameMode gameMode;

  /// Only meaningful when [gameMode] is cricket.
  final CricketScoreMode cricketScoreMode;

  /// X01 starting score (301 / 501 / 701). Ignored in cricket.
  final int startingScore;

  /// Match length in legs (1 / 3 / 5). "Best of" — first to [legsToWin] wins.
  final int bestOf;

  /// When true, a leg must be finished on a double (and leaving 1 busts).
  /// X01 only.
  final bool doubleOut;

  final String player1Name;
  final String player2Name;

  const LocalMatchConfig({
    this.gameMode = LocalGameMode.x01,
    this.cricketScoreMode = CricketScoreMode.score,
    this.startingScore = 501,
    this.bestOf = 3,
    this.doubleOut = true,
    required this.player1Name,
    required this.player2Name,
  });

  bool get isCricket => gameMode == LocalGameMode.cricket;

  /// Legs needed to win the match (e.g. best of 3 → 2).
  int get legsToWin => (bestOf ~/ 2) + 1;

  String nameOf(int player) => player == 0 ? player1Name : player2Name;
}
