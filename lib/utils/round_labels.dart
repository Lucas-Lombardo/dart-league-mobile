import '../l10n/app_localizations.dart';
import '../models/tournament.dart';

/// Round label for chips, headers and banners ("Demi-finales", "Finale", …).
/// The model's [TournamentMatch.roundNameDisplay] is English-only; screens
/// must go through this instead.
String localizedRoundLabel(AppLocalizations l10n, TournamentMatch match) {
  switch (match.roundName) {
    case 'final':
      return l10n.roundFinalLabel;
    case 'semi_final':
      return l10n.roundSemiFinals;
    case 'quarter_final':
      return l10n.roundQuarterFinals;
    case 'round_of_16':
      return l10n.roundOf16Label;
    case 'round_of_32':
      return l10n.roundOf32Label;
    case 'round_of_64':
      return l10n.roundOf64Label;
    default:
      return l10n.roundNLabel(match.roundNumber);
  }
}
