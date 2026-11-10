import 'package:flutter/material.dart';
import 'app_localizations_en.dart';
import 'app_localizations_fr.dart';

abstract class AppLocalizations {
  String get checkoutMicOn;
  String get checkoutMicOff;
  String get checkoutEnableMic;
  String get checkoutDisableMic;
  String get checkoutWaiting;
  String get checkoutCorrecting;
  String get checkoutOpponentHint;
  String get checkoutCorrectionHint;
  String get checkoutAuto;
  String get checkoutCallEnds;
  String get checkoutOwnAuto;
  String get checkoutOtherAuto;

  // Local 501 referee mode.
  String get refereeClear;
  String get refereeBackspace;
  String refereeDartCount(int count);
  String get refereeMode;
  String get localScoringChoice;
  String get localScoringChoiceHint;
  String get localSameBoard;
  String get localAutomaticScoring;
  String get localAutomaticDescription;
  String get localAutomaticFeatures;
  String get refereeDescription;
  String get refereeFeatures;
  String get localSharedPhone;
  String get refereePrepare;
  String get refereeSetupHint;
  String get refereeLegsToWin;
  String get refereeFormatQuick;
  String get refereeFormatClassic;
  String get refereeFormatLong;
  String get refereeOneLegHint;
  String get refereeFirstPlayer;
  String get refereeFirstPlayerHint;
  String get refereeStraightOut;
  String get refereeStraightOutHint;
  String get refereeStartHint;
  String get refereeTotalTab;
  String get refereeHelpTab;
  String get refereeTotalHint;
  String get refereeAnnounceRemaining;
  String get refereeWaitingDart;
  String get refereeValidateVisit;
  String get refereeClearDarts;
  String get refereeUndo;
  String get refereeUndoShort;
  String get refereeUndoDone;
  String get refereeImpossibleTotal;
  String get refereeDartsAfterEnd;
  String get refereeDartsFull;
  String get refereeRecalculate;
  String get refereeFinishTitle;
  String get refereeFinishDoubleTitle;
  String get refereeFinishQuestion;
  String get refereeFinishKnown;
  String get refereeNoDouble;
  String get refereeHistoryEmpty;
  String get refereeAverageHint;
  String get refereeMiss;
  String get refereeBackToSetup;
  String refereeFormatHint(int target, int maximum);
  String refereeLegStatus(int leg, int target);
  String refereeCalculation(int start, int points);
  String refereeDartPoints(int points);
  String refereeDeleteDart(int number);
  String refereeCorrectDart(int number);
  String refereeSwitchWarning(int points);
  String refereeBustExplanation(String name, int score);
  String refereeHistoryScore(int before, int points, int after);

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

  // Settings > friend-online push
  String get friendOnlineNotifTitle;
  String get friendOnlineNotifDescription;

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

  /// Home: subtitle of the Compétitif primary row ("Match classé").
  String get homeCompetitiveSubtitle;
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

  /// Les chiffres derrière un bust : « 130 restants, volée de 139 ».
  String bustFigures(int remaining, int visit);

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
  String get opponentNeedsUpdateFriendly;
  String get proposeFriendlyBo1;
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
  String get localCricketScoreHint;
  String localCricketAllClosedBody(String name);

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
  String get reportReceivedTitle;
  String get reportReceivedLateBody;
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

  /// Tag on the opponent-turn dart label when the score was typed by hand.
  String get manualDartTag;
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
  String get manualConfirmExplainer;
  String get manualConfirmButton;
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
  String get spectateCamera;
  String get spectateBoard;
  String spectateThrowing(String name);
  String spectateCameraUnavailable(String name);
  String get spectateMuteCaller;
  String get spectateUnmuteCaller;
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
  String get referralStatusTrialEnded;
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
  // ── Tournament detail: bracket tree, focus card, participants ──
  String get bracketYouAreHere;
  String get bracketEliminatedHere;
  String get bracketChampionMarker;
  String get bracketWaiting;
  String get bracketYourTurn;
  String bracketWinnerOf(String round, int n);
  String get roundShortFinal;
  String get roundShortSemi;
  String get roundShortQuarter;
  String get roundShortOf16;
  String get roundShortOf32;
  String get roundShortOf64;
  String roundShortN(int n);
  String get roundTinyFinal;
  String get roundTinySemi;
  String get roundTinyQuarter;
  String get roundTinyOf16;
  String get roundTinyOf32;
  String get roundTinyOf64;
  String roundTinyN(int n);
  String get nextMatchTag;
  String get bracketNotifyWhenReady;
  String get bracketWatchThisMatch;
  String bracketEliminatedIn(String round);
  String bracketLostScore(int mine, int theirs);
  String get bracketThanksFollowLive;
  String bracketDependsOn(String round, int n);
  String get bracketQualifiedWaiting;
  String bracketInRound(String round);
  String bracketEliminatedAt(String round);
  String bracketPlayersAlive(int total, int alive);
  String get seedLabel;
  String get bracketBye;
  String get bracketQualifiedShort;
  String bracketSpectators(int n);

  // Premium paywall / settings (system D restyle)
  String get premiumContinueYearly;
  String get premiumContinueMonthly;
  String get settingsEditShort;

  /// Friends tab: "HORS LIGNE" group label (the online one reuses [online]).
  String get friendsOffline;

  // Leaderboard (system D)
  /// "Toutes ›" — the link to the seasons screen at the end of the chips row.
  String get leaderboardAllSeasons;

  // Matchmaking queue + training hub (system D)
  /// Hour tick under the peak-hours chart ("0 h", "6 h", …).
  String queueAxisHour(int hour);
  /// One-line subtitle of the "bot" primary row on the training hub.
  String get trainingBotRowSubtitle;
  /// Suffix of the Calcul tile caption: the drills need no camera.
  String get trainingNoCameraShort;

  // Stats tab (system D restyle)
  String get statsLegendYou;
  String get statsLegendMedian;
  String statsWindowDays(int days);
  String historyPlacementOrdinal(int place);
  String placementHubPlayMatch(int n);
  String placementHubResumeMatch(String bot);
  String get placementHubToPlay;
  String placementHubBotAverage(int avg);
  String placementHubBotName(String rank);
  String placementResultStartsIn(String rank);
  String get spectateHubEmptyHint;


  /// Quiz stat tile: the number of questions answered.
  String get trainingQuizQuestionLabel;

  /// Quiz stat tile: the number of correct answers.
  String get trainingQuizCorrectLabel;

  /// Replay library empty state: the title of the card.
  String get replaysEmptyTitle;

  /// Replay library empty state: how to get a first clip.
  String get replaysEmptyHint;

  /// Per-double progress card: when the last block on this double was thrown
  /// ("dernière séance hier").
  String trainingProgressLastSession(String when);

  /// Per-double progress empty state: the title of the card.
  String get trainingProgressEmptyTitle;

  /// Agenda filter chip: every tournament.
  String get agendaFilterAll;

  /// Agenda filter chip: Dart Rivals tournaments.
  String get agendaFilterOfficial;

  /// Agenda filter chip: tournaments organised by players.
  String get agendaFilterCommunity;

  /// Agenda: the filter leaves nothing.
  String get agendaFilterEmpty;

  /// Meta line of a community tournament: who organises it.
  String organizedBy(String name);

  /// Meta line of a tournament the user organises.
  String get organizedByYou;

  /// Pill on a tournament the user organises / on the organiser row.
  String get organizerLabel;

  /// Tournaments tab: the sticky button at the bottom that creates a
  /// community tournament.
  String get organizeTournamentCta;

  /// Tournaments tab: subtitle of the sticky "organise" button.
  String get organizeTournamentCtaSubtitle;

  /// Community tournament form: title when creating.
  String get communityFormTitleNew;

  /// Community tournament form: title when editing.
  String get communityFormTitleEdit;

  /// Form label: tournament name.
  String get communityFormName;

  /// Form hint: tournament name.
  String get communityFormNameHint;

  /// Form label: the one start date + time.
  String get communityFormStart;

  /// Form: when registration closes (15 min before the start).
  String communityFormRegistrationCloses(String time);

  /// Form label: bracket size.
  String get communityFormPlayers;

  /// Form label: best-of of the matches.
  String get communityFormFormat;

  /// Form switch: the organiser plays too.
  String get communityFormIPlay;

  /// Form switch subtitle.
  String get communityFormIPlaySub;

  /// Form footnote: the rules of a community tournament.
  String get communityFormNote;

  /// Form button: create.
  String get communityFormCreate;

  /// Form error: name under 3 characters.
  String get communityFormNameTooShort;

  /// Form error: start under 48 hours away.
  String get communityFormStartTooSoon;

  /// Form error: start over 30 days away.
  String get communityFormStartTooLate;

  /// Form error: picked size smaller than the registrations.
  String communityFormSizeBelowRegistered(int count);

  /// Form (edit): cancel the tournament.
  String get communityCancelTournament;

  /// Cancel dialog: title.
  String get communityCancelConfirmTitle;

  /// Cancel dialog: body.
  String get communityCancelConfirmBody;

  /// Cancel dialog: keep the tournament.
  String get communityKeep;

  /// Snackbar once cancelled.
  String get communityCancelledToast;

  /// Detail screen: the organiser's card.
  String get organizerPanelTitle;

  /// Organiser card: start date and the 15-min close.
  String organizerPanelBody(String when);

  /// Organiser card button.
  String get organizerShare;

  /// Organiser card button.
  String get organizerInvite;

  /// Organiser card button.
  String get organizerEdit;

  /// Organiser card: start before the date.
  String get organizerStartNow;

  /// Organiser card: players still needed to start.
  String organizerPlayersMissing(int count);

  /// Start-now dialog: title.
  String get organizerStartConfirmTitle;

  /// Start-now dialog: body.
  String organizerStartConfirmBody(int count);

  /// Start-now dialog: confirm.
  String get organizerStartAction;

  /// Snackbar once started.
  String get organizerStartedToast;

  /// Share-sheet text of a community tournament.
  String organizerShareMessage(String name, String when);

  /// Remove-player dialog: title.
  String organizerRemoveConfirmTitle(String name);

  /// Remove-player dialog: body.
  String get organizerRemoveConfirmBody;

  /// Remove-player dialog: confirm, and the row button tooltip.
  String get organizerRemoveAction;

  /// Invite-friends sheet: title.
  String get inviteSheetTitle;

  /// Invite-friends sheet: no friends.
  String get inviteSheetEmpty;

  /// Invite-friends sheet: send button.
  String inviteSheetSend(int count);

  /// Snackbar after inviting.
  String inviteSheetSent(int count);

  /// Popup when a player without premium tries a tournament past the monthly quota: title.
  String tournamentMonthlyLimitTitle(int limit);

  /// Quota popup body, the tournament is this month.
  String tournamentMonthlyLimitBody(int limit);

  /// Quota popup body, the tournament is in a later month.
  String tournamentMonthlyLimitBodyOtherMonth(int limit, String month);

  /// Quota popup: dismiss.
  String get tournamentMonthlyLimitLater;

  /// Paywall benefit: no monthly tournament limit.
  String get benefitUnlimitedTournaments;

  /// Level card rows: the average over the first nine darts of a leg.
  String get levelFirst9;

  /// Level card rows: the average while more than 170 remains.
  String get levelScoring;

  /// Level card rows: the average from 170 down.
  String get levelFinishing;

  /// Level card rows: darts at a finishing double that checked out.
  String get levelDoubles;

  /// Level card headline caption, cohort = the player's rank.
  String levelBeatsRank(int percent, String rank);

  /// Level card headline caption, cohort = every player.
  String levelBeatsAll(int percent);

  /// Level card footnote, cohort = the player's rank.
  String levelFootnoteRank(int size, String rank, int days);

  /// Level card footnote, cohort = every player.
  String levelFootnoteAll(int size, int days);

  /// Level card footnote when no figure can be placed yet.
  String levelWindowOnly(int days);

  /// Impacts card label on the player's own stats.
  String get impactsYours;

  /// Impacts card label on another player's page.
  String get impactsTheirs;

  /// Impacts card: the board of darts thrown above 170.
  String get impactsScoring;

  /// Impacts card: the board of darts thrown at a finishing double.
  String get impactsDoubles;

  /// Impacts card caption under the scoring board.
  String impactsTrebles(int hits, int total);

  /// Impacts card caption under the doubles board.
  String impactsDoublesHit(int hits, int total);

  /// Impacts card caption under a board with no located dart.
  String get impactsNone;

  /// Screen-reader hint: tapping a board replays its darts.
  String get impactsReplay;

  /// Player page: the career record card.
  String get profileRecord;

  /// Player page: "88 – 18" row label.
  String get profileWinsLosses;


  // ---- Progression & rewards (docs/progression/CONTRACT.md) ----
  /// Level pill on player cards.
  String xpLevelShort(int level);

  /// Progression level, long form.
  String xpLevel(int level);

  /// XP inside the level.
  String xpProgressValue(String current, String total);

  /// Progression screen title.
  String get progressionTitle;

  /// Level path screen title / link.
  String get progressionPath;

  /// Next level reward.
  String progressionNextReward(int level, String reward);

  /// Profile pinned badges caption.
  String get progressionShowcase;

  /// Profile button to the locker.
  String get progressionCustomize;

  /// Profile tile: items owned.
  String get progressionItems;

  /// Daily quests section / home block.
  String get questsToday;

  /// Reroll error.
  String get questsRerollFailed;

  /// Home quests row title.
  String get questsRow;

  /// Home quests row subtitle.
  String questsRowSubtitle(int done, int total, int xp);

  /// All daily quests done.
  String get questsAllDone;

  /// XP reward.
  String questXp(int xp);

  /// Short days.
  String durationDaysShort(int days);

  /// Short hours.
  String durationHoursShort(int hours);

  /// Short minutes.
  String durationMinutesShort(int minutes);

  /// Item kind.
  String get itemKindAvatar;

  /// Item kind.
  String get itemKindFrame;

  /// Item kind.
  String get itemKindBackground;

  /// Item kind.
  String get itemKindTitle;

  /// Item kind.
  String get itemKindFlight;

  /// Item kind.
  String get itemKindBadge;

  /// Level 1 reward.
  String get levelsPathBase;

  /// Level up screen title.
  String get levelUpTitle;

  /// XP towards the next level.
  String levelUpProgress(String current, String total, int next);

  /// Level up: unlocked items.
  String get levelUpUnlocks;

  /// Where items show.
  String get levelUpVisible;

  /// Equip now button.
  String get levelUpEquipNow;

  /// Later button.
  String get levelUpLater;

  /// Locker screen title.
  String get lockerTitle;

  /// Locker tab.
  String get lockerTabAvatars;

  /// Locker tab.
  String get lockerTabFrames;

  /// Locker tab.
  String get lockerTabBackgrounds;

  /// Locker tab.
  String get lockerTabTitles;

  /// Locker tab.
  String get lockerTabFlights;

  /// Default avatar tile.
  String get lockerDefaultAvatar;

  /// No item tile.
  String get lockerNone;

  /// Equipped item note.
  String get lockerEquipped;

  /// Equip error.
  String get lockerEquipFailed;

  /// Initials field.
  String get lockerMonogramHint;

  /// Save button.
  String get lockerSave;

  /// Match found screen title.
  String get matchFoundTitle;

  /// Match found subtitle (ranked).
  String get matchFoundRanked;

  /// Match found subtitle (friendly).
  String get matchFoundFriendly;

  /// Me side.
  String get matchFoundYou;

  /// Opponent side.
  String get matchFoundOpponent;

  /// Ghost opponent side.
  String get matchFoundGhost;

  /// End of match XP block.
  String get xpEarnedTitle;

  /// XP not computed yet.
  String get xpPending;

  /// Level reached.
  String xpLevelReached(int level);

  /// Item unlocked.
  String xpItemUnlocked(String item);

  // --- progression (Agent 1) ---
  /// Match found: the two players never met.
  String get matchFoundFirstMeeting;
  // --- fin progression ---

  // --- league (Agent 4) ---
  /// Weekly league: section / screen title.
  String get leagueWeeklyTitle;

  /// Weekly league: "Steel League" / "Ligue Acier".
  String leagueName(String league);

  /// Weekly league: a place, "3rd" / "3ᵉ".
  String leaguePlace(int position);

  /// Weekly league: "914 pts".
  String leaguePoints(String points);

  /// Weekly league: time left in the week.
  String leagueTimeLeft(String duration);

  /// Weekly league: the week is over (Sunday night).
  String get leagueWeekOver;

  /// Weekly league: header when the week is over.
  String get leagueResultsMonday;

  /// Weekly league: line under the promotion zone.
  String leaguePromoteZone(String league);

  /// Weekly league: line above the relegation zone.
  String leagueRelegateZone(int from, int to, String league);

  /// Weekly league: points card title.
  String get leagueEverythingCounts;

  /// Weekly league: ranked win bonus.
  String leagueRuleWinBonus(int bonus);

  /// Weekly league: my row.
  String get leagueYou;

  /// Weekly league: never had a league.
  String get leagueFirstTitle;

  /// Weekly league: never had a league, explanation.
  String get leagueFirstBody;

  /// Weekly league: no group this week (did not play last week).
  String get leagueBackTitle;

  /// Weekly league: no group this week, explanation.
  String get leagueBackBody;

  /// Weekly league: time until Monday.
  String leagueStartsIn(String duration);

  /// Weekly league: final standings note.
  String get leagueClosedBody;

  /// Weekly league: weekday, short (1 = Monday).
  String leagueWeekdayShort(int weekday);

  /// Weekly league: weekday, long (1 = Monday).
  String leagueWeekdayLong(int weekday);

  /// Weekly league: an hour of the day.
  String leagueHour(int hour);

  /// Weekly league: "ends Sun. 10 pm".
  String leagueEndsOn(String day, String hour);

  /// Monday screen: "Week 45 finished".
  String leagueWeekFinished(int week);

  /// Monday screen: promoted headline.
  String get leagueResultUp;

  /// Monday screen: relegated headline.
  String get leagueResultDown;

  /// Monday screen: stayed headline.
  String get leagueResultStay;

  /// Monday screen: "of 20".
  String leagueOutOf(int size);

  /// Monday screen: points tile.
  String get leaguePointsLabel;

  /// Monday screen: XP tile.
  String get leagueXpLabel;

  /// Monday screen: a reward item, "Title “Climber”".
  String leagueRewardItem(String kind, String name);

  /// Monday screen: podium badge row.
  String get leaguePodiumBadge;

  /// Monday screen: podium badge subtitle.
  String leaguePodiumBadgeSub(String place);

  /// Monday screen: one player promoted with you.
  String leaguePromotedWithOne(String name);

  /// Monday screen: several players promoted with you.
  String leaguePromotedWithMany(String names);

  /// Monday screen: the new week.
  String leagueNewWeek(int size, String ends);

  /// Monday screen: button to the new league.
  String get leagueSeeNewLeague;

  /// Monday screen: button when there is no new group.
  String get leagueContinue;

  /// League history: title.
  String get leagueHistoryTitle;

  /// League history: tooltip.
  String get leagueHistoryTooltip;

  /// League history: empty.
  String get leagueHistoryEmpty;

  /// League history: "Week 45".
  String leagueHistoryWeek(int week);

  /// League history: best league reached.
  String leagueBest(String league);

  /// League history: promoted.
  String get leagueOutcomeUp;

  /// League history: relegated.
  String get leagueOutcomeDown;

  /// League history: stayed.
  String get leagueOutcomeStay;

  /// Weekly league: load error.
  String get leagueLoadFailed;

  /// Weekly league: retry button.
  String get leagueRetry;
  // --- fin league ---

  // --- onboarding (Agent 2b) ---
  /// Placement camera screen: POST /placement/start failed.
  String get onboardingPlacementStartFailed;

  /// Placement / bot match: the bot turn failed after the automatic retries.
  String get onboardingPlacementBotTurnFailedTitle;
  String get onboardingPlacementBotTurnFailedBody;

  /// Placement / bot match end: the result could not be saved.
  String get onboardingPlacementSaveFailedTitle;
  String get onboardingPlacementSaveFailedBody;

  /// Placement: the server refused the match (forfeited or cancelled).
  String get onboardingPlacementMatchGoneTitle;
  String get onboardingPlacementMatchGoneBody;

  /// Placement / bot match: label of the suggested-finish bar ("Finish T20 · D20").
  String get onboardingCheckoutHintLabel;

  /// First 7 days: the card and screen title.
  String get onboardingTitle;

  /// First 7 days card footer: the premium given at the end.
  String onboardingPremiumAtTheEnd(int days);

  /// First 7 days: "Day 3".
  String onboardingDayN(int day);

  /// First 7 days card: "Today · day 2".
  String onboardingTodayDay(int day);

  /// First 7 days card: "Tomorrow · day 3".
  String onboardingTomorrowDay(int day);

  /// First 7 days timeline: "Day 2 · today".
  String onboardingDayToday(int day);

  /// First 7 days timeline: "Day 3 · opens tomorrow".
  String onboardingDayOpensTomorrow(int day);

  /// First 7 days card: the day-7 summary is ready.
  String get onboardingBilanReadyTitle;

  /// First 7 days card: open the summary.
  String get onboardingSee;

  /// First 7 days timeline: open the summary.
  String get onboardingSeeBilan;

  /// First 7 days timeline: the open step's button.
  String get onboardingPlayNow;

  /// First 7 days: XP reward of a step.
  String onboardingXp(int xp);

  /// First 7 days: premium days reward.
  String onboardingPremiumDays(int days);

  /// First 7 days: an item reward, kind then name ("title “New Recruit”").
  String onboardingRewardItem(String kind, String name);

  /// Day-7 summary: "7 of 7 steps".
  String onboardingBilanSteps(int done, int total);

  /// Day-7 summary: title.
  String get onboardingBilanTitle;

  /// Day-7 summary tiles.
  String get onboardingBilanMatches;
  String get onboardingBilanBestVisit;
  String get onboardingBilanAverage;
  String get onboardingBilanSinceDay1;
  String get onboardingBilanYourRank;

  /// Day-7 summary: "You unlock" section.
  String get onboardingBilanUnlocks;

  /// Day-7 summary: premium end date and perks.
  String onboardingBilanPremiumUntil(String date);
  String get onboardingBilanPremiumPerks;

  /// Day-7 summary: the frame reward.
  String onboardingBilanFrame(String name);
  String get onboardingBilanEquipped;
  String get onboardingBilanInLocker;

  /// Day-7 summary: what comes next.
  String get onboardingBilanNext;

  /// Day-7 summary: share button and shared text.
  String get onboardingBilanShare;
  String onboardingBilanShareText(int matches, String best, String average);
  // --- fin onboarding ---

  // --- ghost (Agent 5) ---
  /// Ghost match: chip on the board / end screen.
  String get ghostBadge;

  /// Queue: the bottom link once the ghost card is folded, « Jouer contre
  /// un fantôme ».
  String get ghostPlayButton;

  /// Ghost match needs the AI camera.
  String get ghostCameraRequired;

  /// Ghost match could not start.
  String get ghostStartError;

  /// Free tier: daily match used.
  String get ghostDailyLimit;

  /// Unranked player.
  String get ghostPlacementRequired;

  /// The offer is gone.
  String get ghostOfferExpired;

  /// Match found subtitle.
  String ghostMatchFoundSubtitle(int bestOf);

  /// Match found: the replayed match.
  String ghostMatchFoundRecord(String date, String average);

  /// Board caption during the ghost's turn.
  String ghostPanelCaption(String date);

  /// Waiting for the ghost's answer.
  String get ghostThrowing;

  /// Visit not sent.
  String get ghostSendFailed;

  /// Retry.
  String get ghostRetry;

  /// In-match REC strip.
  String get ghostRecBanner;

  /// In-match REC strip, over the daily cap.
  String get ghostRecBannerNoElo;

  /// Leaving a counted ghost match.
  String get ghostLeaveWarning;

  /// Leaving a ghost match out of the ELO cap.
  String get ghostLeaveWarningNoElo;

  /// Leaving before the first visit.
  String get ghostLeaveFree;

  /// End screen subtitle.
  String ghostVs(String name);

  /// End screen: new rating.
  String ghostEloCaption(int elo);

  /// End screen: gain on hold.
  String get ghostEloHeldCaption;

  /// End screen: why the gain is on hold.
  String get ghostEloHeld;

  /// End screen: no ELO.
  String get ghostEloNoneCaption;

  /// End screen: over the daily cap.
  String get ghostEloNone;

  /// End screen: average tile.
  String get ghostAverageLabel;

  /// Proof upload in progress.
  String get ghostProofSending;

  /// Proof uploaded.
  String get ghostProofSent;

  /// Proof upload failed.
  String get ghostProofFailed;

  /// End screen: back home.
  String get ghostHome;

  /// Resume a running ghost match.
  String get ghostResume;

  /// Owner digest title.
  String ghostDigestTitle(int count);

  /// Owner digest row subtitle.
  String ghostDigestRowSubtitle(int wins, int xp);

  /// Owner digest kicker.
  String get ghostDigestWhileAway;

  /// Owner digest: the replayed match.
  String ghostDigestReplays(String date, String average);

  /// Owner digest XP tile.
  String ghostDigestWins(int count);

  /// Owner digest record tile.
  String get ghostDigestRecord;

  /// Owner digest: who beat the ghost.
  String ghostDigestBeaten(String name, int darts);

  /// Owner digest: challenge button.
  String ghostDigestChallenge(String name);

  /// Owner digest: row button.
  String get ghostDigestChallengeShort;

  /// Owner digest footer.
  String get ghostDigestFooter;

  /// Owner digest: ghost won (letter).
  String get ghostResultWin;

  /// Owner digest: ghost lost (letter).
  String get ghostResultLoss;

  /// Settings section.
  String get ghostSettingsSection;

  /// Settings: matches used as ghosts.
  String get ghostSettingsEnabled;

  /// Settings hint.
  String get ghostSettingsEnabledHint;

  /// Settings: grouped push.
  String get ghostSettingsNotify;

  /// Settings hint.
  String get ghostSettingsNotifyHint;
  // --- fin ghost ---

  // --- achievement (Agent 3) ---
  /// Achievements screen title, profile tile.
  String get achievementsTitle;

  /// Family chip: every family.
  String get achievementFamilyAll;

  /// "Closest" card of the collection.
  String get achievementClosest;

  /// "Bull Finish · Silver tier".
  String achievementClosestTier(String name, String tier);

  /// Tier names.
  String get achievementTierBronze;
  String get achievementTierSilver;
  String get achievementTierGold;

  /// A unique achievement, unlocked.
  String get achievementTierUnique;

  /// Not unlocked yet.
  String get achievementLocked;

  /// "9 % of players".
  String achievementRarity(String pct);

  /// "8 / 10 for Silver".
  String achievementForBronze(String progress);
  String achievementForSilver(String progress);
  String achievementForGold(String progress);

  /// "best 31".
  String achievementRecord(String value);

  /// Load error.
  String get achievementLoadFailed;

  /// Retry button.
  String get achievementRetry;

  /// Detail: the AI-only rule.
  String get achievementAiOnly;

  /// Detail: "unlocked on 4 October".
  String achievementUnlockedOn(String date);

  /// Detail: target of a tier, "target 100".
  String achievementTarget(String target);

  /// Detail: the last samples that moved the achievement.
  String get achievementRecent;

  /// "vs Mika_180".
  String achievementRecentVs(String opponent);

  /// "leg 2".
  String achievementRecentLeg(int leg);

  /// Replay of the dart / visit.
  String get achievementReplay;

  /// No replay for that match.
  String get achievementNoReplay;

  /// "Ancien": the account age condition.
  String get achievementRequiresAge;

  /// Unlock sheet: title.
  String get achievementUnlockedTitle;

  /// "Silver tier · 10".
  String achievementTierLine(String tier, String target);

  /// "4 % of players have it".
  String achievementPlayersHaveIt(String pct);

  /// Under "+250 XP".
  String get achievementXpAdded;

  /// The reward of a later tier: "at Gold (50)".
  String achievementRewardAt(String tier, String target);

  /// The reward of this tier.
  String get achievementRewardNow;

  /// Pin the badge.
  String get achievementPin;

  /// Pinned.
  String get achievementPinned;

  /// Already pinned.
  String get achievementAlreadyPinned;

  /// Pin failed.
  String get achievementPinFailed;

  /// Open the collection.
  String get achievementSeeAll;

  /// Close the sheet.
  String get achievementLater;

  /// "+ 3 more".
  String achievementMore(int count);

  /// First launch: the retroactive unlocks.
  String get achievementRetroTitle;

  /// "18 achievements unlocked from your past matches."
  String achievementRetroBody(int count);

  /// Locker tab.
  String get achievementBadgesTab;

  /// Locker tab hint.
  String get achievementBadgesHint;

  /// No badge yet.
  String get achievementBadgesEmpty;

  /// At most 3 pins.
  String get achievementBadgesFull;

  /// "2 / 3 pinned".
  String achievementBadgesPinned(int count);
  // --- fin achievement ---

  // --- challenge (Agent 2) ---
  String get challengeTitle;
  String challengeStreakDays(int days);
  String challengeRowDone(String format, String place, int total);
  String challengeRowPlayed(String format, String score);
  String challengePrizeRank(String rank);
  String challengePrizeReward(int elo);
  String challengeBoardNotOpen(int players);
  String challengeMergedWith(String ranks);
  String challengeEndsIn(String time);
  String challengeHoursMinutes(int hours, int minutes);
  String challengeMinutes(int minutes);
  String get challengePractice;
  String get challengePracticeNote;
  String get challengeAbandoned;
  String get challengeExcluded;
  String get challengeExcludedRejected;
  String get challengeUpdateApp;
  String get challengeYourStreak;
  String get challengeFreezeAvailable;
  String get challengeFreezeUsed;
  String get challengeLeaderboardTitle;
  String challengeTabRank(String rank, int count);
  String challengeTabAll(int count);
  String challengeTabFriends(int count);
  String get challengeEmptyBoard;
  String get challengeEmptyFriends;
  String get challengeWatchSession;
  String get challengeWatchMySession;
  String get challengeYesterdayResult;
  String get challengeRemind;
  String get challengeLoadFailed;
  String get challengeRetry;
  String get challengeUnfinished;
  String get challengeCrownLabel;
  String get challengePlayTotal;
  String get challengePlayTarget;
  String get challengePlayRemaining;
  String get challengePlayVisit;
  String get challengePlayDarts;
  String get challengePlayScore;
  String get challengePlayHits;
  String get challengePlayMarks;
  String get challengePlayPoints;
  String challengeVisitProgress(int index, int total);
  String challengeDartProgress(int index, int total);
  String challengeTargetProgress(int index, int total);
  String challengeCheckoutProgress(int index, int total, int used, int budget);
  String get challengeAnyDouble;
  String get challengeAnyTriple;
  String get challengeRankedBadge;
  String get challengePracticeBadge;
  String get challengeQuitRankedTitle;
  String get challengeQuitRankedBody;
  String get challengeSubmitting;
  String get challengeSubmitFailed;
  String get challengeStartFailed;
  String challengeResultTitle(String date);
  String challengeBestVisit(int value);
  String challengePlaceSub(String rank, String place, int total);
  String get challengeStreakPlus;
  String get challengePassedPrefix;
  String get challengeAnd;
  String challengeLeaderStays(String name, String score, String left);
  String challengeYouLead(String left);
  String get challengeProofSending;
  String get challengeProofSent;
  String get challengeProofWhy;
  String get challengeProofReceived;
  String get challengeProofFailed;
  String get challengeTop10Pending;
  String get challengePracticeResult;
  String get challengeShare;
  String get challengeShareFailed;
  String challengeShareText(String format, String score);
  String challengeStoryHeader(String date);
  String challengeStoryTop(int pct);
  String challengeStoryPlace(String place, String rank);
  String challengeStoryStreak(int days);
  String get challengeStoryLine;
  String get challengeStoryCta;
  String challengePodiumFirst(String rank);
  String get challengePodiumEmpty;
  String get challengePodiumNotClosed;
  String get challengeNoFirst;
  String get challengeEloLabel;
  String get challengeBadgeLabel;
  String get challengeSessionVerified;
  String challengeSessionVerifiedBody(int ai, int corrected);
  String get challengeSessionPending;
  String get challengeSessionPendingBody;
  String challengePodiumYourPlace(String place, int total, int xp);
  String get challengePinBadge;
  String get challengeCrownAvatar;
  String challengeWinsOf(int wins, int goal);
  String challengeSessionSubtitle(String rank, String format, String date);
  String get challengeSessionCorrected;
  String get challengeSessionNoVideo;
  String challengeVisitOverlay(int index, int value);
  String get challengePlayerCamera;
  String get challengePlay;
  String get challengePause;
  String get challengeReport;
  String get challengeReported;
  String get challengeReportFailed;
  String get challengeReportReasonScore;
  String get challengeReportReasonHidden;
  String get challengeReportReasonEdited;
  String get challengeReportReasonOther;
  String challengeCorrectedVisits(String name, int count);
  // --- fin challenge ---

  // --- finitions (Agent Finitions) ---
  /// End of match, under the XP: the league points of this match and the
  /// place before / after ("Ligue Acier : +50 pts, tu passes de 6ᵉ à 4ᵉ.").
  /// [league] is already "Steel League" / "Ligue Acier".
  String leagueMatchMoved(String league, int points, String from, String to);

  /// End of match, under the XP: the league points, same place.
  String leagueMatchStayed(String league, int points, String place);
  // --- fin finitions ---

  // --- tour 5 (Agent Tour 5) ---
  /// "Étoile de prestige 2": one star on the Légende frame every 10 levels past 50.
  String prestigeStarName(int n);
  /// What carries the star (levels path, level up): "Cadre Légende".
  String get prestigeStarKind;
  /// Level up at 60, 70…: under the star.
  String get levelUpPrestigeHint;
  /// Level up: the star only shows on the Légende frame.
  String get levelUpPrestigeWear;
  /// Level up past 50, when the next level gives no item.
  String progressionNextStar(int level);
  /// Ghost offer refused by the server (GHOST_PREMIUM_REQUIRED).
  String get ghostPremiumRequired;
  /// Achievement detail: a tier reached but held for an admin review.
  String get achievementPendingReview;
  String get achievementPendingReviewHint;
  // --- fin tour 5 ---
  // --- home final ---
  /// Player card (S1): the « Modifier » button of one's own card → locker.
  String get homeEditCard;
  String get homeEditCardLabel;
  /// Player card (S1): under the level number, in the hexagon.
  String get homeLevelHexLabel;
  /// « +40 XP »: the XP a way of playing or a quest pays.
  String homeXpGain(int xp);
  /// Home quest strip: the daily quest in progress, the weekly one once the daily are done.
  String homeQuestDaily(String quest);
  String homeQuestWeekly(String quest);
  String get homeQuestsAllDone;
  /// Screen reader: « 2/3 » on the quest strip.
  String homeQuestsDoneLabel(int done, int total);
  /// Compétitif: « 3 matchs classés en direct », and the quiet line with none.
  String homeLiveRanked(int count);
  String get homeLiveNone;
  /// Compétitif: « Platine dans 191 pts ».
  String homeNextRankIn(String rank, int points);
  /// Compétitif during placement: « Compétitif · Placement », « Ton rang dans 2 matchs ».
  String get homePlacementLabel;
  String homePlacementLeft(int count);
  /// Compétitif, event states: the button and their caption.
  String get homeResume;
  String get homeJoin;
  String homeMatchInProgress(String opponent);
  String get homeRankedLockedCaption;
  String get homeTournamentLiveCaption;
  String get homeTournamentReadyCaption;
  /// « Jouer autrement » and its tiles.
  String get homePlayOtherWays;
  String get homeNoXp;
  // --- fin home final ---
  // --- challenge simple ---
  /// Daily challenge screen B (docs/progression/ecrans/DefB1, DefB2).
  /// Header bell: the SnackBar after a tap.
  String get challengeSRemindOn;
  String get challengeSRemindOff;
  /// Screen reader: the streak pill of the header.
  String challengeSStreakLabel(int days);
  /// Format card: « 1 essai · caméra IA », then « · fin dans 14 h » (challengeEndsIn).
  String get challengeSMeta;
  /// « 14 h »: whole hours left.
  String challengeSHours(int hours);
  /// The ⓘ of the format card and the title of its sheet.
  String get challengeSRuleLabel;
  String get challengeSRuleOneTry;
  String get challengeSRuleCamera;
  String get challengeSRewardsTitle;
  String challengeSRewardPlay(int xp);
  String challengeSRewardTop10(int xp);
  /// Before the ranked try: the n°1 of my board, or nobody yet.
  String get challengeSToBeat;
  String get challengeSNobodyYet;
  String get challengeSBeFirst;
  String get challengeSPlay;
  /// Under the Play button: « N°1 : +24 ELO · top 10 % : +50 XP ».
  String challengeSPrizeLine(int elo, int xp);
  /// Under the Play button while the board has fewer than 5 players.
  String challengeSNotOpen(int players);
  /// After the ranked try: the duel with the n°1.
  String get challengeSYou;
  String challengeSPlace(String place, int total);
  String get challengeSVs;
  String get challengeSFirst;
  String get challengeSSecond;
  String challengeSXpEarned(int xp);
  String get challengeSReview;
  String get challengeSPractice;
  String get challengeSOffBoard;
  /// The top 5 of the page.
  String get challengeSLeaderboard;
  String get challengeSAll;
  String get challengeSFriends;
  String challengeSMeRow(String name);
  String challengeSPlayers(int count);
  String get challengeSYesterday;
  String get challengeSNoScores;
  // --- fin challenge simple ---
  // --- locker simple ---
  /// Locker A (docs/progression/ecrans/CasA1, CasA2, CasObtenir).
  /// The two shelves of each tab: « À toi », « À débloquer ».
  String get lockerSOwned;
  String get lockerSToUnlock;
  /// The short condition under a locked item (« Niv. 27 » is xpLevelShort).
  String get lockerSCondPremium;
  String get lockerSCondAchievement;
  String get lockerSCondLeague;
  String lockerSCondSeason(int number);
  String get lockerSCondEvent;
  String get lockerSCondOnboarding;
  /// The pill of the locked item's sheet: « Avatar à débloquer ».
  String get lockerSLockedAvatar;
  String get lockerSLockedFrame;
  String get lockerSLockedBackground;
  String get lockerSLockedTitle;
  String get lockerSLockedFlight;
  /// « Essayer sur ma carte » and the tag on the card while trying.
  String get lockerSTryOnCard;
  String get lockerSPreview;
  /// Screen reader: the tag on the card cancels the preview.
  String get lockerSPreviewCancel;
  /// How to get it: a level.
  String lockerSHowLevelTitle(int level);
  String lockerSHowLevelSub(int level, int left);
  String lockerSHowLevelReached(int level);
  String get lockerSSeeLevels;
  /// How to get it: the premium track.
  String lockerSHowPremiumTitle(int level);
  String lockerSHowPremiumSub(int level);
  String get lockerSHowPremiumNow;
  String get lockerSGoPremium;
  /// How to get it: an achievement tier (« Bulls, palier Or »).
  String lockerSHowAchievementTier(String name, String tier);
  String get lockerSSeeAchievement;
  /// How to get it: the weekly league.
  String lockerSHowLeagueTitle(String league);
  String get lockerSHowLeagueFirstPromotion;
  String lockerSHowLeagueSub(String league);
  String get lockerSSeeLeague;
  /// How to get it: a season.
  String lockerSHowSeasonTitle(int number);
  String get lockerSHowSeasonSub;
  String lockerSHowSeasonSubDate(String date);
  String get lockerSHowSeasonOver;
  /// How to get it: a dated event (« décembre », « Du 11 déc. au 3 janv. »).
  String lockerSHowEventTitle(String month);
  String lockerSHowEventDates(String from, String to);
  String get lockerSSeeQuest;
  String get lockerSEventNotStarted;
  String get lockerSEventOver;
  /// How to get it: the first 7 days.
  String get lockerSHowOnboardingTitle;
  String lockerSHowOnboardingDay(int day, int days);
  String get lockerSHowOnboardingClosed;
  String get lockerSSeeJourney;
  /// The letters of a monogram avatar (replaces « Texte du monogramme »).
  String get lockerSLettersTitle;
  String get lockerSLettersSub;
  String get lockerSLettersAuto;
  String get lockerSLettersDouble;
  String get lockerSLettersCustom;
  /// Screen reader: the pencil on the equipped monogram avatar.
  String get lockerSLettersEdit;
  // --- fin locker simple ---
  // --- fantôme secours (Agent Fantôme secours) ---
  /// Queue: the ghost card's title after [minutes] without an opponent.
  String ghostQueueNobody(int minutes);
  // --- fin fantôme secours ---
  // --- match found duel ---
  /// Match found: the label over what the series is worth.
  String get matchFoundStakes;

  /// Match found: head-to-head record, no pronoun ("Bilan 7 – 5").
  String matchFoundDuelRecord(int wins, int losses);

  /// Match found: under the 3-2-1 ring.
  String get matchFoundStarting;

  /// Match found: the versus disc.
  String get matchFoundVsShort;
  // --- fin match found duel ---
  // --- fantôme carte B ---
  /// Queue ghost card: the line under the ghost's card.
  String get ghostQueueReplayed;

  /// Queue ghost card: the blue button, before the XP.
  String get ghostQueuePlay;

  /// Queue ghost card: folds the card into the bottom link.
  String get ghostQueueWait;

  /// Queue ghost card, free player: the gold button to the subscription.
  String get ghostQueuePremium;

  /// Screen reader: the lock on a free player's blurred ghost card.
  String get ghostQueueLocked;
  // --- fin fantôme carte B ---
  // --- parcours et progression (Agent Parcours) ---
  /// Levels path: a tier of 10 levels, « Niveaux 21 – 30 ».
  String pathTierRange(int from, int to);

  /// Levels path: the last card, past level 50.
  String pathPrestige(int every);

  /// Levels path: two items of one level sharing a name, « Légende · cadre et titre ».
  String pathPairSame(String name, String kindA, String kindB);

  /// Levels path: short item kinds, for [pathPairSame].
  String get pathKindAvatar;
  String get pathKindFrame;
  String get pathKindBackground;
  String get pathKindTitle;
  String get pathKindFlight;

  /// Levels path: XP still needed for the next level, « 774 XP ».
  String pathXpLeft(String xp);

  /// Screen reader: a level reached / still locked.
  String get pathReached;
  String get pathLocked;

  /// Progression tabs.
  String get questsTabDay;
  String get questsTabWeek;
  String get questsTabDiscover;
  String get questsTabEvent;

  /// Progression, the line under the tabs.
  String questsNewQuestsIn(String time);
  String questsWeekLeft(String time);
  String get questsOnce;
  String questsEventUntil(String date);

  /// Daily quest changes left today (0 or 1).
  String questsChanges(int count);

  /// The folded line of the quests done: « 1 terminée · +40 XP gagnés ».
  String questsDoneSummary(int count, String xp);

  /// The swap icon on a quest that can be changed, and its confirmation.
  String get questsChangeLabel;
  String get questsChangeTitle;
  String get questsChangeBody;
  String get questsChangeConfirm;

  /// A tab without any quest.
  String get questsNothing;
  // --- fin parcours et progression ---
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
