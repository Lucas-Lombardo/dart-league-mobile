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

  // Register Screen
  String get confirmPassword;
  String get usernameRequired;
  String get usernameTooShort;
  String get usernameInvalid;
  String get emailRequired;
  String get emailInvalid;
  String get passwordRequired;
  String get passwordTooShort;
  String get confirmPasswordRequired;
  String get passwordMismatch;
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
  String get count180s;
  String get streak;
  String get viewFullMatchHistory;

  // Tournament Screen
  String get tournament;
  String get tournaments;
  String get tournamentPlaying;
  String get tournamentRegister;
  String get noActiveTournaments;
  String get registerForTournamentHint;
  String get noUpcomingTournaments;
  String get matchInvites;
  String get activeTournaments;
  String get registeredTournaments;
  String get registerNow;
  String get unregister;
  String get matchInvite;
  String get timeRemaining;
  String get waitingForOpponent;
  String get acceptAndJoin;
  String get tournamentDetails;
  String get tournamentNotFound;
  String get bracket;
  String get participants;
  String get scheduledDate;
  String get winnerReward;
  String get currentRound;
  String get winner;
  String get bracketNotGenerated;
  String get participantsRegistered;
  String get noParticipantsYet;

  // Email & Password Reset
  String get forgotPassword;
  String get forgotPasswordTitle;
  String get forgotPasswordDescription;
  String get sendResetLink;
  String get resetLinkSent;
  String get resetLinkSentDescription;
  String get backToLogin;
  String get checkYourEmail;
  String get checkYourEmailDescription;
  String get resendVerificationEmail;
  String get verificationEmailSent;

  // Placement
  String get placementMatches;
  String get placementDescription;
  String get completePlacementToUnlock;
  String get matchesCompleted;
  String get startMatch;
  String get unranked;

  // Matchmaking Screen
  String get findingMatch;
  String get matchFoundExclamation;
  String get opponent;
  String get startingGame;
  String get searchingForOpponentUpper;
  String get yourElo;
  String get eloRange;
  String get cancelSearch;

  // Camera Check / Camera Setup
  String get cameraSetupTitle;
  String get placementBadge;
  String get positionPhoneInstruction;
  String get initializingCamera;
  String get cameraRequiredError;
  String get cameraPermissionRequired;
  String get cameraAndMicPermissionRequired;
  String get micPermissionRequired;
  String get noCamerasFound;
  String get failedToInitializeCamera;
  String get unknownError;
  String get tryAgainButton;
  String get cameraReady;
  String get positionDeviceInstruction;
  String get dartboardNotDetected;
  String get boardNotFullyVisible;
  String get zoomInBoardTooFar;
  String get zoomOutBoardTooClose;
  String get dartboardDetectedGoodPosition;
  String get scanningForDartboard;
  String get cameraRequiredButton;
  String get scanningButton;
  String get cameraOnDuringMatchInfo;
  String get aiWillScoreDartsInfo;
  String get makeSureDartboardVisibleInfo;
  String get cameraCheck;
  String get cameraSetup;
  String get checkingPermissions;
  String get cameraRequired;
  String get cannotJoinWithoutCamera;
  String get enablePermissionsInSettings;
  String get tryAgain;
  String get permissionsGranted;
  String get readyToJoinQueue;
  String get cameraOnDuringMatch;
  String get micOffByDefault;
  String get makeSureDartboardVisible;
  String get joinQueue;
  String get permissionsRequired;
  String get positionDartboard;

  // Placement Game Screen
  String get botTurn;
  String get placementMatch;
  String get yourScore;
  String get bustConfirm;
  String get confirmWin;
  String get confirmAndEndTurn;
  String get endTurnEarly;
  String get botIsThrowing;
  String get bust;
  String get checkout;
  String get you;
  String get bot;
  String get savingResult;
  String get leaveMatch;
  String get leaveMatchWarning;
  String get stay;
  String get leave;
  String get retry;
  String get next;
  String get avgPerRound;

  // Placement Result Screen
  String get placementComplete;
  String get youWonOutOf;
  String get yourRank;
  String get startingElo;
  String get startPlayingRanked;

  // Placement hub
  String get winSingular;
  String get winsPlural;

  // Tournament Ready Screen
  String get bestOf;
  String get startingMatch;
  String get ready;
  String get waiting2;
  String get cancelButton;

  // Tournament Leg Result Screen
  String get legWon;
  String get legLost;
  String get legComplete;
  String get firstToLegsWins;
  String get nextLeg;

  // Tournament Match Result Screen
  String get youAdvance;
  String get eliminated;
  String get congratsWonSeries;
  String get betterLuckNextTime;
  String get finalScore;
  String get continueButton;
  String get returnHome;

  // Match Detail Screen
  String get matchDetails;
  String get eloChange;
  String get matchStatistics;
  String get totalRounds;
  String get avgScoreRound;
  String get highestRound;
  String get perfect180s;
  String get roundHistory;
  String get matchNotFound;
  String get accountInfoDefaultUsername;
  String get accountInfoDefaultEmail;

  // Haptic & Auto-scoring settings
  String get hapticFeedbackTitle;
  String get hapticFeedbackSubtitle;
  String get autoScoringTitle;
  String get autoScoringSubtitle;

  // Login
  String get welcomeBackLegend;

  // Home
  String get eloLabel;
  String get settingsTooltip;

  // Play screen
  String get userNotFound;
  String get joinMatch;
  // Note: 'play' already defined at line 53
  String get rankedLocked;
  String get activeTournament;
  String get rejoinVs;

  // Friends screen
  String get searchByUsernameHint;
  String get searchForUsersByUsername;
  String get noUsersFound;
  String get friendsStatus;
  String get pendingStatus;
  String get acceptButton;
  String get removeFriendTitle;
  String get removeFriendMessage;
  String get removeButton;
  String get incomingRequests;
  String get sentRequests;
  String get noFriendRequests;
  String get noFriendsYet;
  String get addFriendsHint;
  String get addFriendsButton;
  String get friendRequestSent;
  String get friendRequestAccepted;
  String get friendRequestDeclined;
  String get friendRemoved;

  // Leaderboard
  String get noFriendsYetHint;
  String get addFriendsToSeeRankings;
  String get noLeaderboardData;

  // Stats
  String get noStatisticsAvailable;

  // Splash screen
  String get competeRankWin;

  // Match Detail
  String get errorWithMessage;
  String get victoryEmoji;
  String get defeatEmoji;
  String get roundLabel;

  // Match History
  String get matchHistoryTitle;
  String get playGameToSeeHistory;
  String get youLabel;
  String get opponentLabel;
  String get addFriendButton;
  String get searchFailed;

  // Tournament
  String get entryFee;
  String get registrationOpensSoon;
  String get tbd;
  String get youIndicator;
  String get unknown;
  String get eloReward;

  // Tournament Game
  String get forfeitTournamentWarning;
  String get tournamentAppBarTitle;
  String get unableToAcceptResult;
  // Note: 'youAdvance' and 'eliminated' already defined
  String get opponentLeftForfeitAdvance;
  String get youLeftEliminated;
  String get returnToHome;
  String get wellPlayedConfirmResult;
  String get betterLuckNextLeg;
  String get pleaseConfirmMatchResult;
  String get acceptResult;
  String get reportPlayer;
  String get initializingMatch;
  String get initializingMatchError;
  String get legWonShort;
  String get legLostShort;

  // Tournament Ready
  String get vsUppercase;

  // Matchmaking
  String get unknownPlayer;
  String get eloValue;

  // Game Screen
  String get forfeitMatchWarning;
  String get liveMatch;
  String get acceptingMatchResult;
  String get matchResultAccepted;
  String get error;
  // Note: 'victory', 'gameOver', 'eloChange', 'defeat' already defined
  String get opponentLeftForfeit;
  String get youLeftForfeited;
  String get continuePlaying;
  String get provenLegend;
  String get trainingPath;
  String get matchResult;
  String get pleaseConfirmResult;
  String get loadingAutoScoring;
  String get opponentDisconnected;
  String get timeLeftToReconnect;
  String get yourScoreLabel;
  String get missButton;
  String get scoreLabel;
  String get dartCounter;
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
