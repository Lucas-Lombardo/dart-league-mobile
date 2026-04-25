import '../../../models/training.dart';
import '../../../providers/game_provider.dart' show ScoreMultiplier;

/// Around the Clock ring mode — picked by the user before starting the run.
enum AtcMode { single, double, triple }

extension AtcModeX on AtcMode {
  TrainingType get trainingType {
    switch (this) {
      case AtcMode.single:
        return TrainingType.aroundTheClock;
      case AtcMode.double:
        return TrainingType.aroundTheClockDouble;
      case AtcMode.triple:
        return TrainingType.aroundTheClockTriple;
    }
  }

  ScoreMultiplier get requiredMultiplier {
    switch (this) {
      case AtcMode.single:
        return ScoreMultiplier.single;
      case AtcMode.double:
        return ScoreMultiplier.double;
      case AtcMode.triple:
        return ScoreMultiplier.triple;
    }
  }
}
