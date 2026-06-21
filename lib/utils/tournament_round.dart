import '../l10n/app_localizations.dart';

/// Localized display name for a tournament round key (e.g. 'quarter_final').
/// Falls back to a humanized version of the raw key for unknown rounds.
String localizedRoundName(String roundName, AppLocalizations l10n) {
  switch (roundName) {
    case 'final':
      return l10n.roundFinal;
    case 'semi_final':
      return l10n.roundSemiFinal;
    case 'quarter_final':
      return l10n.roundQuarterFinal;
    case 'round_of_16':
      return l10n.roundOf16;
    case 'round_of_32':
      return l10n.roundOf32;
    case 'round_of_64':
      return l10n.roundOf64;
    default:
      return roundName.replaceAll('_', ' ');
  }
}
