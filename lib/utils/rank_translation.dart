import '../l10n/app_localizations.dart';

class RankTranslation {
  static String translate(AppLocalizations l10n, String rank) {
    switch (rank.toLowerCase()) {
      case 'bronze':
        return l10n.bronze;
      case 'silver':
        return l10n.silver;
      case 'gold':
        return l10n.gold;
      case 'platinum':
        return l10n.platinum;
      case 'diamond':
        return l10n.diamond;
      case 'master':
        return l10n.master;
      case 'grandmaster':
        return l10n.grandmaster;
      case 'legend':
        return l10n.legend;
      default:
        return rank;
    }
  }
}
