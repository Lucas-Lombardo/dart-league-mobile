import 'package:flutter/material.dart';
import 'app_localizations_en.dart';
import 'app_localizations_fr.dart';

abstract class AppLocalizations {
  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static const List<Locale> supportedLocales = [Locale('en'), Locale('fr')];

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
  String playersOnline(int count);
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
  String get voiceCaller;
  String get voiceCallerDescription;

  // Settings > Sounds & vibrations
  String get soundsSection;
  String get soundDartHit;
  String get soundDartHitDescription;
  String get soundTurn;
  String get soundTurnDescription;
  String get soundGameEffects;
  String get soundGameEffectsDescription;
  String get soundMatchFound;
  String get soundMatchFoundDescription;
  String get haptics;
  String get hapticsDescription;

  // Settings > AI dataset sharing
  String get datasetShareTitle;
  String get datasetShareDescription;

  // Settings > profile hero & account
  String get editProfile;
  String get accountSection;
  String get logoutConfirm;

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
  String get trainWhileWaiting;
  String get trainWhileWaitingSubtitle;
  String get peakHours;
  String get peakHoursNow;
  String peakHoursHint(int hour);
  String get peakHoursGrowing;

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
  String get cameraNeededForAiInfo;
  String get boardLocked;
  String get dartboardDetectedGoodPosition;
  String get scanningForDartboard;
  String get cameraRequiredButton;
  String get scanningButton;
  String get cameraOnDuringMatchInfo;
  String get aiWillScoreDartsInfo;
  String get makeSureDartboardVisibleInfo;
  String get removeDartsFromBoardHint;
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
  // Countdown wording while the between-legs screen is deliberately held open
  // (it is the loser's only window to report the winning visit).
  String nextLegIn(int seconds);
  // Short "legs" unit shown next to a BO3 series score (e.g. "2 - 1 legs").
  String get legsShort;

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

  // Profile edit
  String get editUsername;
  String get editEmail;
  String get save;
  String get profileUpdated;
  String get emailChangedVerifyHint;

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
  String get inactivityPenaltyTitle;
  String get inactivityPenaltyDescription;
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

  // Tournament participation conditions
  String get tournamentRequirements;
  String get tournamentPremiumRequired;
  String get tournamentRankRequired;
  String get tournamentNotEligiblePremium;
  String get tournamentNotEligibleRank;

  // Tournament history / states
  String get tournamentHistoryTitle;
  String get historyFilterAll;
  String get historyFilterMine;
  String get noTournamentHistory;
  String get noTournamentHistoryHint;
  String get noParticipatedTournaments;
  String get players;
  String get tournamentLoadError;
  String get matchWindowExpiredTitle;
  String get matchWindowExpiredHint;
  String get opponentNoShowTitle;
  String get opponentNoShowHint;

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
  String get refuseResult;
  String get refuseResultReasonPrompt;
  String get submitRefusal;
  String get initializingMatch;
  String get initializingMatchError;
  String get matchNotStartingTitle;
  String get matchNotStartingBody;
  String get matchNotStartingOffline;
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
  String get rankUp;
  String get rankDown;
  String get provenLegend;
  String get trainingPath;
  String get matchResult;
  String get pleaseConfirmResult;
  String get loadingAutoScoring;
  String get opponentDisconnected;
  String get timeLeftToReconnect;
  String get connectionLostReconnecting;
  String get matchNoLongerInProgress;
  String get yourScoreLabel;
  String get missButton;
  String get scoreLabel;
  String get dartCounter;

  // Play Screen - additional
  String get playFirstGameToSeeHistory;
  String get viewAll;

  // Play Screen - Pro Tips
  String get proTipLabel;
  List<String> get proTips;

  // Matchmaking - ELO range expansion hint
  String get eloRangeExpandingHint;

  // Matchmaking - queue timeout (no opponent found after 15 min)
  String get queueTimeoutTitle;
  String get queueTimeoutMessage;
  String get queueTimeoutBackButton;

  // Tournament Game - end screen titles (parameterized)
  String get matchWonTitle;
  String get matchLostTitle;
  String legWonTitle(int legNumber);
  String legLostTitle(int legNumber);
  String legResultSubtitle(int legNumber);
  String get confirmNextLeg;

  // Tournament end screen
  String get tournamentChampion;
  String get tournamentRunnerUp;
  String get tournamentSemiFinalist;
  String get tournamentQuarterFinalist;
  String get tournamentParticipant;
  String get tournamentFirstPlace;
  String get tournamentSecondPlace;
  String get tournamentThirdFourthPlace;
  String get tournamentTopEight;
  String get tournamentTopSixteen;
  String get yourTournamentJourney;

  // Trainings
  String get rankedStatsTab;
  String get trainingStatsTab;
  String get trainingStatsHeader;
  String get trainingStartNewSession;
  String get trainingNoSessionsYet;
  String get trainingCompleteSessionToTrack;
  String get trainingSelectTitle;
  String get trainingCategoriesLabel;
  String get trainingCategoryDoubles;
  String get trainingCategoryCheckouts;
  String get trainingCategoryScoring;
  String get trainingCategoryGames;
  String trainingCategoryGameCount(int count);
  String get trainingAroundTheClock;
  String get trainingAroundTheClockDescription;
  String get trainingAroundTheClockDoublesDescription;
  String get trainingAroundTheClockScoringDescription;
  String get trainingAroundTheClockDouble;
  String get trainingAroundTheClockTriple;
  String get trainingAtcPickModeTitle;
  String get trainingAtcSingle;
  String get trainingAtcDouble;
  String get trainingAtcTriple;
  String get trainingAtcSingleHint;
  String get trainingAtcDoubleHint;
  String get trainingAtcTripleHint;
  String get trainingBobs27;
  String get trainingBobs27Description;
  String get trainingHighScore;
  String get trainingHighScoreDescription;
  String get trainingJdcChallenge;
  String get trainingJdcChallengeDescription;
  String get trainingJdcPart1Caption;
  String get trainingJdcPart2Caption;
  String get trainingJdcPart3Caption;
  String get trainingRules;
  String get trainingRulesAroundTheClock;
  String get trainingRulesBobs27;
  String get trainingRulesHighScore;
  String get trainingRulesCheckout50;
  String get trainingRulesCheckout81_121;
  String get trainingRulesBotTraining;
  String get trainingRulesJdcChallenge;
  String get trainingCheckout50;
  String get trainingCheckout50Description;
  String get trainingCheckout81_121;
  String get trainingCheckout81_121Description;
  String get trainingCheckoutPickScore;
  String get trainingCheckout81Hint;
  String get trainingCheckout121Hint;
  String trainingCheckoutFromN(int startScore);
  String get trainingCheckouts;
  String trainingCheckoutsOutOf(int hits, int total);
  String trainingAttemptProgress(int current, int total);
  String trainingVisitProgress(int current, int total);
  String get trainingRemaining;
  String get trainingHighestReached;
  String get trainingBusted;
  String get trainingBustBelowZero;
  String get trainingBustNotDouble;
  String get trainingBustLeftOne;
  String get trainingBustOutOfDarts;
  String get trainingPlayCardTitle;
  String get trainingPlayCardSubtitle;
  String get trainingAiUnavailable;
  String get trainingCameraInfo;
  String get trainingStartButton;
  String get trainingConfirmVisit;
  String get trainingEndRoundEarly;
  String get trainingComplete;
  String get trainingIncomplete;
  String get trainingDartsThrown;
  String get trainingDartsToFinish;
  String get trainingFinalScore;
  String get trainingTotalScore;
  String get trainingScore;
  String get trainingRoundLabel;
  String trainingRoundProgress(int current, int total);
  String trainingHighestRound(int score);
  String get trainingNextTarget;
  String get trainingBullLabel;

  // Important Doubles drill.
  String get trainingImportantDoubles;
  String get trainingImportantDoublesDescription;
  String get trainingRulesImportantDoubles;
  String get trainingImportantDoublesPickTitle;
  String get trainingImportantDoublesPickHint;
  String get trainingImportantDoublesPickEmpty;
  String trainingImportantDoublesPickSummary(int darts);
  String get trainingTargetLabel;
  String get trainingHitRate;
  String get trainingHitRatePercent;
  String trainingBlockProgress(int current, int total);
  String trainingDartsProgress(int thrown, int total);
  String get trainingProgressTitle;
  String get trainingProgressEmpty;
  String trainingProgressSessionsDarts(int sessions, int darts);
  String get trainingViewProgress;

  // Calcul (quiz) drills: Quick Count + Checkout Vision.
  String get trainingCategoryCalcul;
  String get trainingQuickCount;
  String get trainingQuickCountDescription;
  String get trainingRulesQuickCount;
  String get trainingCheckoutVision;
  String get trainingCheckoutVisionDescription;
  String get trainingRulesCheckoutVision;
  String get trainingQuizYouAreOn;
  String get trainingQuickCountWatch;
  String get trainingQuizScorePrompt;
  String trainingQuizQuestionProgress(int current, int total);
  String get trainingQuizTimeUp;
  String trainingQuizItWas(int answer);
  String get trainingQuizAccuracyLabel;
  String get trainingQuizTimeAvgLabel;
  String get trainingQuizStreakLabel;
  String get trainingQuizNext;
  String trainingQuizDartsAllowed(int darts);
  String trainingCheckoutVisionPrompt(int darts);
  String get trainingCheckoutVisionFinishDouble;
  String get trainingCheckoutVisionOut;
  String get trainingCheckoutVisionMissedTitle;
  String get trainingCheckoutVisionShort;
  String get trainingCheckoutVisionBookRoute;
  String get trainingCheckoutVisionOtherRoutes;
  String get trainingCheckoutVisionRecommendedRoutes;
  String trainingCheckoutVisionBookCount(int count);

  String get trainingBustedOut;
  String get trainingResultSaved;
  String get trainingPlayAgain;
  String get trainingQuitTitle;
  String get trainingQuitMessage;
  String get trainingBest;
  String get trainingBestLow;
  String get trainingAverage;
  String get trainingLast;
  String get trainingAttempts;
  String get trainingGames;
  String get trainingNotYetPlayed;

  String get submit;

  // Premium / subscription
  String get premium;
  String get upgradeToPremium;
  String get upgrade;
  String get premiumRenewsOn;
  String get premiumFreeSubtitle;
  String get premiumActive;
  String get premiumActiveTitle;
  String get goPremiumTitle;
  String get unlockUnlimitedMatches;
  String get planYearly;
  String get planMonthly;
  String get yearlySubtitle;
  String get monthlySubtitle;
  String get bestValue;
  String get whatYouGet;
  String get benefitUnlimitedMatches;
  String get benefitPremiumBadge;
  String get benefitSupportDev;
  String get paywallFooter;
  String get statusLabel;
  String get nextRenewal;
  String get manageSubscription;
  String get manageFooter;
  String get autoRenewDisclosure;
  String get termsOfUse;
  String get privacyPolicy;
  String get restorePurchases;
  String get restoreSuccess;
  String get restoreFailed;
  String get restoreNothingToRestore;
  String get dailyLimitReached;
  String get dailyLimitReachedShort;
  String get goPremiumUnlimited;
  String get freeTierMatchAvailable;
  String get freeTierMatchUsed;
  String get tapToUpgradeForUnlimited;
  String get freePlayBannerTitle;
  String get freePlayBannerSubtitle;
  String get unrankedFreeTierHint;

  // --- Chat (friend/support messaging) ---
  String get receivedMessagesTitle;
  String get unreadSection;
  String get earlierSection;
  String get noReceivedMessages;
  String get writeViaFriendsHint;
  String get teamDartRivals;
  String get teamBadge;
  String get teamConversationSubtitle;
  String get teamReplyDelay;
  String get messageHint;
  String get chatRetentionNotice;
  String get chatEmpty;
  String get chatMessageAction;
  String get reportConversationAction;
  String get reportConversationSubtitle;
  String get reportSentConfirmation;
  String get blockAction;
  String get unblockAction;
  String get blockedBanner;
  String get todayLabel;
  String get yesterdayLabel;
  String get tapToLearnAboutPremium;

  // Tournament & verification
  String get history;
  String get emailNotVerifiedTitle;
  String get emailVerificationRequired;
  String get close;
  String get resendEmail;
  String get prizeLabel;
  String get prizeToWin;
  String get trophyLabel;
  String get trophyShippedToWinner;

  // Game dialogs
  String get stayInMatch;
  String get leaveAndForfeit;
  String youHitToFinish(String notation);
  String get isThisCorrect;
  String get editDarts;
  String get confirmPassOrEdit;
  String get confirmBustButton;
  String get scoreBusted;
  String get selectReasonReporting;
  String get disputeSubmitted;
  String get submitReport;
  String get preparingMatch;
  String get waitingUpper;
  String get opponentTurnUpper;
  String get pleaseWait;
  String get doNotPlayDuringOpponentTurn;

  // Report reasons
  String get reportReasonCheating;
  String get reportReasonUnsportsmanlike;
  String get reportReasonIncorrectScore;
  String get reportReasonConnectionIssues;
  String get reportReasonOther;

  // Report comment
  String get reportCommentLabel;
  String get reportCommentHint;

  // Bust reasons
  String get bustReasonBelowZero;
  String get bustReasonMustDouble;
  String get bustReasonOneRemaining;
  String get bustReasonInvalid;

  // Tournament Game
  String legNumber(int number);

  // Tournament End rounds
  String get roundFinal;
  String get roundSemiFinal;
  String get roundQuarterFinal;
  String get roundOf16;
  String get roundOf32;
  String get roundOf64;

  // Camera Check
  String failedToCheckPermissions(String error);

  // Placement Game
  String botName(int difficulty);
  String botNameIsThrowing(int difficulty);
  String botRankBotName(String rank);
  String botRankIsThrowing(String rank);
  String get rankBronze;
  String get rankSilver;
  String get rankGold;
  String get rankPlatinum;
  String get rankDiamond;
  String get rankPro;
  String get rankMaster;
  String get trainingBotTraining;
  String get trainingBotTrainingDescription;
  String get trainingBotPickRank;
  String trainingBotAvg(int avg);
  String get trainingBotPickGameType;
  String get trainingBotGameTypeHint501;
  String get trainingBotGameTypeHint301;
  String get trainingBotGameTypeHint201;
  String get botSetupTitle;
  String get botSetupModeSection;
  String get botSetupFormatSection;
  String get botSetupOpponentSection;
  String get starterAlternates;
  String get cricketLabel;
  String get cricketSetupHint;
  String get cricketScoreLabel;
  String get cricketNoScoreLabel;
  String get cricketScoreHint;
  String get cricketNoScoreHint;
  String botModeStatsSummary(int games, int winPct, String metric);
  String avgShort(String value);
  String mprShort(String value);
  String get mprLabel;
  String get statsFilterAll;
  String cricketMarks(int n);
  String cricketMarksShort(int n);
  String get pointsShortUpper;
  String get cricketMprCaption;
  String get visitUpper;
  String get cricketAllClosedTitle;
  String get cricketAllClosedBody;
  String get botVisitConnectionError;
  String challengeFriendTitle(String username);
  String get challengeChooseGame;
  String get friendlyX01Hint;
  String get opponentNeedsUpdateCricket;
  String get proposeX01Instead;
  String get matchAverageLabel;
  String get overallBotAverageLabel;
  String matchAverageValue(String value);
  String overallBotAverageValue(String value);
  String get loadingAi;

  // Training
  String dartNumber(int number);
  String get saving;

  // Widgets - score input
  String get endRoundEarlyUpper;
  String get endTurnUpper;
  String get turnLabel;
  String get editLabel;
  String editDartNumber(int number);
  String get singleUpper;
  String get doubleUpper;
  String get tripleUpper;
  String get singleShort;
  String get doubleShort;
  String get tripleShort;
  String get singleBull;
  String get doubleBull;
  String get bull50;
  String get bull25;

  // Widgets - error / status
  String get oops;
  String get tryAgainUpper;
  String get unableToConnectMessage;
  String get noRecentMatches;
  String botWithAvg(int avg);
  String get winUpper;
  String get lossUpper;
  String get placementUpper;
  String get placementCapitalized;
  String get vsLabel;
  String get youUpper;
  String get avgLabel;
  String get waitingForOpponentUpper;
  String get opponentUpper;
  String get premiumBadgeLabel;

  // Connecting / loading
  String get connecting;

  // Bot turn match opponent (game)
  String get botPlayer;

  // Checkout & finishing statistics
  String get checkoutAndFinishing;
  String get statLast30Days;
  String get statAllTime;
  String get bestCheckout;
  String get finishingDoubles;
  String get avgThreeDart;

  // Play-mode selector + friend selection
  String get chooseGameMode;
  String get competitiveModeTitle;
  String get competitiveModeSubtitle;
  String get friendModeTitle;
  String get friendModeSubtitle;
  String get selectFriendTitle;
  String get selectFriendSubtitle;

  // Local 1v1 (hot-seat) match
  String get localModeTitle;
  String get localModeSubtitle;
  String get localMatchBadge;
  String get localMatchSetupTitle;
  String get playersLabel;
  String get player1DefaultName;
  String get player2DefaultName;
  String get startingScoreLabel;
  String get matchLengthLabel;
  String bestOfN(int n);
  String get rulesLabel;
  String get doubleOutLabel;
  String get doubleOutHint;
  String get startMatchButton;
  String get pointsLabel;
  String legsUnit(int n);
  String firstToNLegs(int n);
  String turnOf(String name);
  String localMatchWinner(String name);
  String get rematchButton;

  // Friendly (friend-invite) matches + play-again
  String get inviteToPlay;
  String get friendlyMatchPremiumRequired;
  String get friendNeedsPremium;
  String get matchInviteTitle;
  String get invitedYouToMatch;
  String get waitingForFriend;
  String get inviteDeclinedMsg;
  String get inviteCancelledMsg;
  String get declineInvite;
  String get playAgainQuestion;
  String get opponentWantsToPlayAgain;
  String get opponentDeclinedRematch;
  String get friendlyMatchLabel;
  String get playerBusyMsg;
  String get inviteFailedMsg;
  String get online;

  // "Update your app" banner
  String get updateAvailableTitle;
  String get updateAvailableBody;
  String get updateNow;

  // Tournament registration gate + match-day dialogs
  String get ok;
  String get updateRequiredTitle;
  String get tournamentUpdateRequiredBody;
  String get tournamentFullTitle;
  String get tournamentFullBody;
  String get notEligibleTitle;
  String get requiredRank;
  String get profileUnavailable;
  String get verificationEmailFailed;
  String get registrationNotOpenError;
  String get paymentRefunded;
  String get resultUnderReviewTitle;
  String get resultUnderReviewBody;
  String get youAdvanceTitle;
  String get youAdvanceOpponentNoShow;
  // Unmissable "your match is ready" prompt (TournamentInviteGate)
  String get tournamentInvitePromptTitle;
  String get tournamentInvitePromptForfeitWarning;
  String get tournamentInvitePromptLater;
  String get tournamentInvitePromptNextMatchHint;
  String get eliminatedTitle;
  String get eliminatedNoShowBody;
  String get matchPostponedTitle;
  String get matchPostponedBody;
  String get resumeTournamentMatch;
  String get underReviewBadge;
  String get disputedMatchBanner;

  // In-match maquette UI (turn header, visit chips, camera overlays)
  String get liveBadge;
  String get playingBadge;
  String roundChip(int number);
  String get opponentAvgLabel;
  String get yourAvgLabel;
  String visitOf(String name);
  String get yourVisit;
  String get replayCapture;
  String get replaySaved;
  String get replayShare;
  String get replaySaveToGallery;
  String get replaySavedToGallery;
  String get replaySaveToGalleryFailed;
  String get replayGalleryPermissionDenied;
  String get replayShareFailed;
  String get replayNothingToCapture;
  String get replayMoments;
  String get myReplays;
  String get replaysEmpty;
  String get replayQuotaBanner;
  String get replayDeleteTitle;
  String get replayDelete;
  String get replayRename;
  String get replayNameHint;
  String get replayViewMine;
  String get replaysSection;
  String get myReplaysSubtitle;
  String replayClipsCount(int count);
  String replayFreeLeft(int left);
  String replayVs(String opponent);
  String replayClipNumber(int position);
  String replayRetentionNotice(int days);
  String replayExpiresIn(int days);
  String get replayExpiresToday;
  String get replayNoMatch;
  String get replayPreparing;
  String get replayOutcomeWon;
  String get replayOutcomeLost;
  String get replayOutcomePending;
  String get replayFormatFriendly;
  String get replayFormatRanked;
  String get replayFormatPlacement;
  String get totalLabel;
  String get upcomingDart;
  String get editShort;
  String dartOf(int number);
  String plusPts(int points);
  String ptsLabel(int points);
  String get doNotThrowTitle;
  String get opponentTurnWait;
  String get autoValidation;
  String get autoValidationHint;
  String get confirmUpper;

  // Tournament detail screen (round-focused bracket)
  String get roundFinalLabel;
  String get roundSemiFinals;
  String get roundQuarterFinals;
  String get roundOf16Label;
  String get roundOf32Label;
  String get roundOf64Label;
  String roundNLabel(int n);
  String roundProgress(int current, int total);
  String get yourMatchTag;
  String get joinTournamentMatch;
  String get otherMatchesLabel;
  String get matchStatusCompleted;
  String get matchStatusInProgress;
  String get matchStatusWaitingPlayers;
  String get matchStatusUpcoming;
  String get matchStatusNotPlayed;
  String get matchNotPlayedBody;
  String get startsAfterPreviousRound;
  String get tbdLabel;
  String get qualifiedLabel;
  String championCrowned(String name);
  String get freeLabel;
  String get tournamentStatusUpcoming;
  String get tournamentStatusRegistrationOpen;
  String get tournamentStatusRegistrationClosed;
  String get tournamentStatusInProgress;
  String get tournamentStatusCompleted;
  String get tournamentStatusCancelled;

  // Tournament agenda (chronological tournament tab)
  String get agendaToday;
  String get agendaTomorrow;
  String get agendaRegisteredChip;
  String get agendaFullChip;

  // Home (B2): ELO ring hero + form row
  String get nextRankConnector;
  String get maxRankReached;
  String get formLabel;
  String get formWinLetter;
  String get formLossLetter;
  String winStreak(int n);

  // Leaderboard (option A: podium + pinned position)
  String get yourPosition;
  String positionOrdinal(int n);

  // Friends (option A: single challenge CTA, swipe to remove)
  String get challengeFriend;

  // Activity pill (homescreen) + detail sheet
  String activityActiveLabel(int hours);
  String get activityPulseTitle;
  String activitySheetSubtitle(int hours);
  String activityMatchesLabel(int hours);
  String get activityPeakLabel;
  String activityPeakTip(String hour);
  String get activityQueueTip;
  String get activityNowAxisLabel;

  // ---- Stats, onglet Matchs (flow A) ----
  String get matchStatsTab;
  String get statsFilters;
  String get statsPeriod;
  String get statsMode;
  String get statsPeriod7;
  String get statsPeriod30;
  String get statsPeriod90;
  String get statsPeriodAll;
  String get statsModeRanked;
  String get statsModeFriendly;
  String get statsModeTournament;
  String get statsModeBot;
  String get statsBestVisit;
  String get statsCheckout;
  String get statsDoubleLadder;
  String get statsRecords;
  String get statsRecordBestCheckout;
  String get statsRecordBestLeg;
  String get statsRecordBestLegAverage;
  String get statsRecordLongestStreak;
  String get statsHowCalculated;
  String get statsAverageExplainer;
  String get statsNoDataForFilter;
  String get statsNoDataHint;
  String get statsNoRecordsYet;
  String get statsApply;
  String statsLastNLegs(int count);
  String statsPreviousBlock(String value);
  String statsVisitBreakdown(int count);
  String statsUnlockCurve(int count);
  String statsVersus(String name);

  // Comparison screen (where the player stands among other players).
  String get comparisonTitle;
  String get comparisonProfile;
  String get comparisonWhereYouStand;
  String get comparisonMedianMarker;
  String get comparisonStrength;
  String get comparisonWeakness;
  String get comparisonNotEnoughLegs;
  String get comparisonMetricScoring;
  String get comparisonMetricFinishing;
  String get comparisonMetricConsistency;
  String get comparisonMetricPower;
  String get comparisonMetricComposure;
  String get comparisonAxisScoring;
  String get comparisonAxisFinishing;
  String get comparisonAxisConsistency;
  String get comparisonAxisPower;
  String get comparisonAxisComposure;
  String comparisonTopPercent(int percent);
  String comparisonCohortRank(String rank, int size);
  String comparisonCohortAll(int size);
  String comparisonFootnote(int days, int minLegs);
  String comparisonBeatsPercent(int percent);
  String comparisonLegsToGo(int count);

  // Head-to-head screen.
  String get headToHeadTitle;
  String get headToHeadEncounters;
  String get headToHeadInTheirMatches;
  String get headToHeadRecentMeetings;
  String get headToHeadNoHistory;
  String get headToHeadTons;
  String get headToHeadLastResult;
  String headToHeadChallenge(String name);
  String headToHeadLegsBasis(int legs);

  // End-of-match stats card.
  String get matchStatsTitle;
  String get matchStatsDoubles;
  String matchStatsVsWindow(String average, int days);
  String statsDartsUnit(String value);

  // ── Per-volley reports (2026-08-13) ─────────────────────────────────────
  // The in-game bar shares the replay capture slot; the winning visit is
  // flagged from the end-of-leg / end-of-match screens instead.
  String get flagVisit;
  String flagVisitWithScore(int score);
  String flagVisitUndo(int seconds);
  String get flagVisitSent;
  String flagWinningVisit(int score);
  String get flagAction;
  String get flagDone;
  String get turnReportsTitle;
  String turnReportsIntro(int count);
  String turnReportLegTurn(int leg, int turn);
  String turnReportTurnOnly(int turn);
  String turnReportWinningLabel(int leg);
  String get turnReportWinningNoLeg;
  String turnReportVisitScore(int score);
  String get turnReportTodo;
  String get turnReportReady;
  String turnReportSubmit(int count);
  String get turnReportSkip;
  String turnReportDropWarning(int count);
  String get turnReportDialogTitle;
  String get turnReportRemove;
  String get turnReportSent;

  // Spectator mode
  String get spectateLiveTitle;
  String get spectateLiveNow;
  String get spectateRankedSection;
  String get spectateTournamentsSection;
  String get spectateWatch;
  String spectateMatchesLive(int count);
  String spectateMatchCountBadge(int count);
  String get spectateNoLiveMatches;
  String get spectateVirtualBoard;
  String spectateVisitOf(String name);
  String get spectateLastVisits;
  String get spectateLeave;
  String get spectateUnavailable;
  String get spectateMatchOver;
  String get spectateConnecting;
  String get spectateWaitingNextLeg;

  // --- Referral program ---
  String get referralTitle;
  String get referralSectionTitle;
  String get referralCreateCodeTitle;
  String get referralCreateCodeSubtitle;
  String get referralMyCodeTitle;
  String get referralHaveCodeTitle;
  String referralHaveCodeSubtitle(int days);
  String get referralYourCode;
  String get referralCodeCopied;
  String get referralShareCode;
  String referralShareMessage(String code, int days);
  String referralCodeExplainer(int days);
  String get referralEmailGateBody;
  String get referralEmailGateAction;
  String get referralEmailGateSent;
  String get referralRewardsTitle;
  String get referralMonthlyLabel;
  String get referralMonthlySubtitle;
  String get referralYearlyLabel;
  String get referralYearlySubtitle;
  String get referralRefereesTitle;
  String referralEarnedTotal(String amount);
  String referralPendingTotal(String amount);
  String get referralNoRefereesYet;
  String get referralStatusTrial;
  String referralStatusSubscribed(String amount);
  String referralStatusRewardDue(String amount);
  String referralStatusRewardPaid(String amount);
  String get referralStatusCancelled;
  String get referralAdminContactNote;
  String get referralRedeemTitle;
  String get referralRedeemHeadline;
  String referralRedeemBody(int days);
  String get referralRedeemHint;
  String referralRedeemAction(int days);
  String get referralRedeemFootnote;
  String referralRedeemSuccessTitle(int days);
  String referralRedeemSuccessBody(String username);
  String get referralRedeemSuccessAction;
  String referralReferredBy(String username);
  String get referralErrorInvalidCode;
  String get referralErrorSelfCode;
  String get referralErrorAlreadyReferred;
  String get referralErrorAlreadySubscribed;
  String get referralErrorAccountTooOld;
  String get referralErrorEmailNotVerified;
  String get referralErrorUnknown;
  String get referralOnboardingTitle;
  String referralOnboardingBody(int days);
  String get referralOnboardingAction;
  String get referralOnboardingSkip;
  String referralPaywallRow(int days);

  // Seasons
  String seasonN(int n);
  String seasonShort(int n);
  String get seasonsTitle;
  String get seasonAllSeasons;
  String get seasonInProgress;
  String get seasonInProgressCaps;
  String get seasonEnded;
  String get seasonUpcoming;
  String seasonEndsIn(String duration);
  String get seasonEndToBeAnnounced;
  String seasonDurationDaysHours(int d, int h);
  String seasonDurationHoursMinutes(int h, int m);
  String seasonDurationMinutes(int m);
  String get seasonPrize;
  String get seasonPrizeFor1st;
  String seasonPrizeFor1stOn(String date);
  String get seasonPrizeFor1stShort;
  String get seasonPrizeUpForGrabs;
  String get seasonNoReward;
  String get seasonBegin;
  String get seasonEnd;
  String seasonToday(String date);
  String get seasonChampion;
  String get seasonLeader;
  String get seasonYou;
  String get seasonStandings;
  String get seasonFinalStandings;
  String seasonYouAre(int position);
  String get seasonNotRanked;
  String get seasonFinalRank;
  String seasonFinalRankLine(String rank, int position, int total);
  String get seasonEndedLabel;
  String get seasonEloFinal;
  String seasonOf(int total);
  String seasonFromLaunchTo(String date);
  String seasonPeriod(String start, String end);
  String seasonAfterSeason(int n);
  String seasonWinsLosses(int wins, int losses);
  String get seasonRecapTitle;
  String seasonRecapEnded(int n);
  String seasonRecapFinalRankOf(String username);
  String get seasonRecapWinsLosses;
  String get seasonRecapRecord;
  String seasonRecapChampionOf(int n);
  String seasonRecapChampionWins(int elo);
  String seasonRecapChampionElo(int elo);
  String seasonRecapNextStarts(int n, String date);
  String seasonRecapNextStarted(int n);
  String get seasonRecapSeeNewElo;
  String get seasonRecapShare;
  String get seasonRecapShareFailed;
  String get seasonResetTitle;
  String get seasonResetBody;
  String seasonResetEndOf(int n);
  String seasonResetStartOf(int n);
  String get seasonResetBefore;
  String get seasonResetStart;
  String seasonResetYouStay(String rank);
  String seasonResetYouBecome(String rank);
  String get seasonResetNoMaster;
  String seasonResetPrizeOn(String date);
  String get seasonResetPrize;
  String seasonResetPlay(int n);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
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
