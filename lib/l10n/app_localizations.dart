import 'package:flutter/material.dart';
import 'app_localizations_en.dart';
import 'app_localizations_fr.dart';

abstract class AppLocalizations {
  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

  static const List<Locale> supportedLocales = [
    Locale('en'),
    Locale('fr'),
  ];

  String get appName;
  String get login;
  String get register;
  String get email;
  String get password;
  String get username;
  String get loginButton;
  String get registerButton;
  String get dontHaveAccount;
  String get alreadyHaveAccount;
  String get logout;
  String get profile;
  String get home;
  String get leaderboard;
  String get friends;
  String get settings;
  String get play;
  String get findMatch;
  String get searching;
  String get cancel;
  String get matchFound;
  String get waiting;
  String get wins;
  String get losses;
  String get rank;
  String get elo;
  String get recentMatches;
  String get noMatchesYet;
  String get victory;
  String get defeat;
  String get draw;
  String get vs;
  String get yourTurn;
  String get opponentTurn;
  String get gameOver;
  String get youWon;
  String get youLost;
  String get playAgain;
  String get backToHome;
  String get score;
  String get deleteAccount;
  String get deleteAccountConfirm;
  String get deleteAccountWarning;
  String get yes;
  String get no;
  String get accountDeleted;
  String get errorOccurred;
  String get connectionError;
  String get invalidCredentials;
  String get emailAlreadyExists;
  String get loading;
  String get searchingForOpponent;
  String get matchmaking;
  String get acceptMatch;
  String get declineMatch;
  String get playerLeft;
  String get reconnecting;
  String get connected;
  String get disconnected;
  String get language;
  String get changeLanguage;

  // Bottom Navigation
  String get stats;
  String get rankings;

  // Play Screen
  String get dartRivals;
  String get rankedCompetitive;
  String get refresh;
  String get loss;
  String get win;

  // Rank Names
  String get bronze;
  String get silver;
  String get gold;
  String get platinum;
  String get diamond;
  String get master;
  String get grandmaster;
  String get legend;

  // Leaderboard
  String get globalLeaderboard;
  String get global;
  String get player;

  // About Section
  String get about;
  String get appVersion;
  String get developer;
  String get preferences;

  // Friends Screen
  String get add;
  String get requests;
  String get friendsCount;

  // Stats Screen
  String get performanceOverview;
  String get winRate;
  String get totalMatches;
  String get avgScore;
  String get highestScore;
  String get streak;
  String get viewFullMatchHistory;
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) {
    return ['en', 'fr'].contains(locale.languageCode);
  }

  @override
  Future<AppLocalizations> load(Locale locale) async {
    switch (locale.languageCode) {
      case 'fr':
        return AppLocalizationsFr();
      case 'en':
      default:
        return AppLocalizationsEn();
    }
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
