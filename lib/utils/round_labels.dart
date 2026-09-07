import '../l10n/app_localizations.dart';
import '../models/tournament.dart';

/// Round label for chips, headers and banners ("Demi-finales", "Finale", …).
/// The model's [TournamentMatch.roundNameDisplay] is English-only; screens
/// must go through this instead.
String localizedRoundLabel(AppLocalizations l10n, TournamentMatch match) {
  return localizedRoundLabelRaw(l10n, match.roundName, match.roundNumber);
}

/// Same labels from raw fields, for data that isn't a [TournamentMatch]
/// (e.g. the spectate live feed).
String localizedRoundLabelRaw(
  AppLocalizations l10n,
  String roundName,
  int roundNumber,
) {
  switch (roundName) {
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
      return l10n.roundNLabel(roundNumber);
  }
}

/// Column header label ("QUARTS", "DEMIS", "FINALE") — short enough for a
/// collapsed column.
String shortRoundLabel(
  AppLocalizations l10n,
  String roundName,
  int roundNumber,
) {
  switch (roundName) {
    case 'final':
      return l10n.roundShortFinal;
    case 'semi_final':
      return l10n.roundShortSemi;
    case 'quarter_final':
      return l10n.roundShortQuarter;
    case 'round_of_16':
      return l10n.roundShortOf16;
    case 'round_of_32':
      return l10n.roundShortOf32;
    case 'round_of_64':
      return l10n.roundShortOf64;
    default:
      return l10n.roundShortN(roundNumber);
  }
}

/// Lower-case, one-word round name used inside sentences ("Gagnant demi 2").
String tinyRoundLabel(
  AppLocalizations l10n,
  String roundName,
  int roundNumber,
) {
  switch (roundName) {
    case 'final':
      return l10n.roundTinyFinal;
    case 'semi_final':
      return l10n.roundTinySemi;
    case 'quarter_final':
      return l10n.roundTinyQuarter;
    case 'round_of_16':
      return l10n.roundTinyOf16;
    case 'round_of_32':
      return l10n.roundTinyOf32;
    case 'round_of_64':
      return l10n.roundTinyOf64;
    default:
      return l10n.roundTinyN(roundNumber);
  }
}
