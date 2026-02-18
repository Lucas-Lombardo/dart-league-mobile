import '../providers/game_provider.dart' show ScoreMultiplier;
import '../services/dart_scoring_service.dart';

/// Convert a DartScore from the AI detection system to the backend's
/// notation format (baseScore + ScoreMultiplier).
///
/// Examples:
///   double_bull → (25, double) → D25 → 50 pts
///   single_bull → (25, single) → S25 → 25 pts
///   triple 20   → (20, triple) → T20 → 60 pts
///   double 16   → (16, double) → D16 → 32 pts
///   inner/outer single 5 → (5, single) → S5 → 5 pts
///   miss        → (0, single) → S0 → 0 pts
(int baseScore, ScoreMultiplier multiplier) dartScoreToBackend(DartScore score) {
  switch (score.ring) {
    case 'double_bull':
      return (25, ScoreMultiplier.double);
    case 'single_bull':
      return (25, ScoreMultiplier.single);
    case 'triple':
      return (score.segment, ScoreMultiplier.triple);
    case 'double':
      return (score.segment, ScoreMultiplier.double);
    case 'inner_single':
    case 'outer_single':
      return (score.segment, ScoreMultiplier.single);
    case 'miss':
    default:
      return (0, ScoreMultiplier.single);
  }
}

/// Convert a DartScore to the string notation used in the UI (e.g. "T20", "D16", "S5")
String dartScoreToNotation(DartScore score) {
  switch (score.ring) {
    case 'double_bull':
      return 'D25';
    case 'single_bull':
      return 'S25';
    case 'triple':
      return 'T${score.segment}';
    case 'double':
      return 'D${score.segment}';
    case 'inner_single':
    case 'outer_single':
      return 'S${score.segment}';
    case 'miss':
    default:
      return 'S0';
  }
}
