import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../l10n/app_localizations.dart';
import '../../models/bot_rank.dart';
import '../../models/cricket.dart';
import '../../models/training.dart';
import '../../providers/auth_provider.dart';
import '../../providers/game_provider.dart';
import '../../providers/placement_provider.dart';
import '../../services/auto_scoring_service.dart';
import '../../services/bot_training_service.dart';
import '../../services/dart_scoring_service.dart';
import '../../services/dataset_capture_service.dart';
import '../../services/training_service.dart';
import '../../utils/app_theme.dart';
import '../../utils/dart_sound_service.dart';
import '../../utils/haptic_service.dart';
import '../../utils/game_system_ui.dart';
import '../../utils/orientation_utils.dart';
import '../../utils/score_converter.dart';
import '../../widgets/auto_score_display.dart';
import '../../widgets/cricket_board.dart';
import '../../widgets/design_system.dart';
import '../../widgets/game_turn_ui.dart';
import '../../widgets/local_camera_preview.dart';
import '../game/leg_end_view.dart';
import '../game/match_end_view.dart';
import 'bot_camera_ai_mixin.dart';
import 'placement_game_screen.dart' show botRankDisplayLabel;

/// Cricket against the bot. Same chrome and camera/AI plumbing as the X01
/// bot screen (AutoScoreGameView, bot-turn panel, LegEndView between legs) —
/// only the score panel and the rules engine change: [CricketState] holds the
/// marks, the CricketBoardStrip renders them, and the bot's visits come from
/// the stateless cricket bot-turn endpoint.
class CricketBotGameScreen extends StatefulWidget {
  const CricketBotGameScreen({super.key});

  @override
  State<CricketBotGameScreen> createState() => _CricketBotGameScreenState();
}

class _CricketDart {
  final int baseScore;
  final ScoreMultiplier multiplier;

  _CricketDart(this.baseScore, this.multiplier);
}

class _CricketBotGameScreenState extends State<CricketBotGameScreen>
    with WidgetsBindingObserver, BotCameraAiMixin {
  bool _botTurnInProgress = false;
  bool _gameEnded = false;
  bool _wonMatch = false;

  late CricketState _state;
  late CricketState _visitStart;
  List<_CricketDart> _currentRoundThrows = [];
  List<CricketDartEffect> _effects = [];
  int _dartsThrown = 0;
  bool _isWin = false;
  bool _winDialogShowing = false;

  // Bot visit display state.
  List<BotThrow> _botThrows = [];
  List<CricketDartEffect> _botEffects = [];

  // Match totals across legs — the MPR numerator/denominator.
  int _totalDartsThrown = 0;
  int _roundsPlayed = 0;
  int _matchMyMarks = 0;

  // Bot visits in the CURRENT leg only — the header's round number.
  int _botRounds = 0;

  // Series (BO3-BO11) between-legs state, same pattern as the X01 screen.
  bool _showingLegEnd = false;
  bool _lastLegWon = false;
  int _legEndSecondsLeft = 0;
  Timer? _legEndTimer;

  // Post-match stat screen state.
  bool _statsLoading = false;
  double? _overallMpr;
  int _endMyLegs = 0;
  int _endBotLegs = 0;
  int _endBestOf = 1;
  int _endMyPoints = 0;
  int _endBotPoints = 0;

  // Auto-scoring (local camera): fields and controls come from
  // BotCameraAiMixin, shared with the X01 bot screen.

  CricketScoreMode get _scoreMode =>
      context.read<PlacementProvider>().botConfig?.cricketScoreMode ??
      CricketScoreMode.score;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WakelockPlus.enable();
    OrientationUtils.allowAll();
    GameSystemUi.enter();
    _state = CricketState(scoreMode: _scoreMode);
    _visitStart = _state.clone();
    autoScoringService = AutoScoringService();
    autoScoringService!.telemetrySessionOf = () => ('bot', null);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await initCameraAndAI();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _legEndTimer?.cancel();
    disposeCameraAndAI();
    DatasetCaptureService.flush();
    WakelockPlus.disable();
    OrientationUtils.portraitOnly();
    GameSystemUi.exit();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      stopAiCapture();
      cameraService?.pause(
        releaseCamera: state == AppLifecycleState.inactive ? false : null,
      );
    } else if (state == AppLifecycleState.resumed) {
      final camera = cameraService;
      camera?.resume().then((_) {
        if (mounted && identical(cameraService, camera)) setState(() {});
      });
      if (autoScoringEnabled &&
          !aiManuallyDisabled &&
          !_gameEnded &&
          !_botTurnInProgress &&
          !_showingLegEnd) {
        startAiCapture();
      }
    }
  }

  double? get _myMpr =>
      _roundsPlayed > 0 ? _matchMyMarks / _roundsPlayed : null;

  // ─── Player visit ──────────────────────────────────────────────────────────

  @override
  void onAiAutoConfirm() => _confirmRound();

  @override
  void onAiDartDetected(int slotIndex, DartScore dartScore) {
    if (!mounted || _botTurnInProgress || _gameEnded || _showingLegEnd) return;
    final (base, mul) = dartScoreToBackend(dartScore);
    HapticService.mediumImpact();
    DartSoundService.playDartHit(base, mul);

    if (slotIndex < _currentRoundThrows.length) {
      _currentRoundThrows[slotIndex] = _CricketDart(base, mul);
    } else {
      if (_dartsThrown >= 3 || _isWin) return;
      _currentRoundThrows.add(_CricketDart(base, mul));
    }
    _recalculate();

    if (_isWin) {
      stopAiCapture();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showWinDialog();
      });
    }
  }

  /// Replays the visit on top of the visit-start snapshot — the cricket
  /// equivalent of the X01 screen's _recalculateScore, so dart edits and
  /// refined detections stay consistent.
  void _recalculate() {
    final replay = _visitStart.clone();
    final effects = <CricketDartEffect>[];
    for (final d in _currentRoundThrows) {
      effects.add(replay.applyDart(d.baseScore, d.multiplier, mine: true));
      if (replay.iWon) break;
    }
    setState(() {
      _state = replay;
      _effects = effects;
      _dartsThrown = _currentRoundThrows.length;
      _isWin = replay.iWon;
    });
  }

  /// Rolls the confirmed visit into the match totals and clears the slots.
  void _commitVisit() {
    _roundsPlayed++;
    _totalDartsThrown += _currentRoundThrows.length;
    for (final e in _effects) {
      _matchMyMarks += e.marksApplied;
    }
    _visitStart = _state.clone();
    _currentRoundThrows = [];
    _effects = [];
    _dartsThrown = 0;
  }

  void _confirmRound() {
    if (_isWin) {
      _showWinDialog();
      return;
    }
    stopAiCapture();
    _commitVisit();
    DartSoundService.playTurnFinished();
    setState(() {});
    _executeBotTurn();
  }

  void _showWinDialog() {
    if (_winDialogShowing || !mounted) return;
    _winDialogShowing = true;
    final l10n = AppLocalizations.of(context);
    showGameDialog(
      context,
      accent: AppTheme.success,
      icon: Icons.emoji_events_outlined,
      title: l10n.cricketAllClosedTitle,
      prominentActions: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.cricketAllClosedBody, style: gameDialogBodyStyle),
          const SizedBox(height: 6),
          Text(l10n.isThisCorrect, style: gameDialogHintStyle),
        ],
      ),
      actionsBuilder: (ctx) => [
        OutlinedButton(
          onPressed: () {
            _winDialogShowing = false;
            Navigator.pop(ctx);
            setState(() {
              aiPausedForEdit = true;
              _isWin = false;
              _currentRoundThrows.clear();
            });
            _recalculate();
            autoScoringService?.stopCapture();
            for (int i = 0; i < 3; i++) {
              autoScoringService?.clearDart(i);
            }
          },
          style: gameNeutralOutlineButtonStyle(),
          child: Text(dsSentence(l10n.editDarts)),
        ),
        ElevatedButton(
          onPressed: () {
            _winDialogShowing = false;
            Navigator.pop(ctx);
            DartSoundService.playWin();
            _onPlayerLegWon();
          },
          style: gameFilledButtonStyle(AppTheme.success),
          child: Text(dsSentence(l10n.confirmWin)),
        ),
      ],
    ).then((_) => _winDialogShowing = false);
  }

  // ─── Bot visit ─────────────────────────────────────────────────────────────

  Future<void> _executeBotTurn() async {
    if (_botTurnInProgress || _gameEnded) return;
    final placement = context.read<PlacementProvider>();
    final rank = placement.botRank;
    if (rank == null) return;

    setState(() {
      _botTurnInProgress = true;
      _botThrows = [];
      _botEffects = [];
    });

    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;

    // The endpoint is stateless, so a retry re-sends the same board — safe.
    // After the last attempt the visit is dropped for good (nothing replays
    // it later), so the failure must be VISIBLE, never a phantom 0-mark visit.
    List<BotThrow>? throws;
    for (var attempt = 0; attempt < 3 && throws == null; attempt++) {
      try {
        final response = await BotTrainingService.cricketBotTurn(
          rank: rank,
          scoreMode: _scoreMode == CricketScoreMode.noScore
              ? 'noScore'
              : 'score',
          botMarks: _state.marksToWire(mine: false),
          playerMarks: _state.marksToWire(mine: true),
          botPoints: _state.oppPoints,
          playerPoints: _state.myPoints,
        );
        throws = (response['botThrows'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(BotThrow.fromJson)
            .toList();
      } catch (_) {
        if (!mounted) return;
        if (attempt < 2) {
          await Future.delayed(const Duration(seconds: 1));
        }
      }
      if (!mounted) return;
    }

    if (throws == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).botVisitConnectionError),
        ),
      );
      _handBackToPlayer();
      return;
    }
    final botThrows = throws;

    final effects = <CricketDartEffect>[];
    for (final t in botThrows) {
      final mul = t.isTriple
          ? ScoreMultiplier.triple
          : t.isDouble
          ? ScoreMultiplier.double
          : ScoreMultiplier.single;
      final effect = _state.applyDart(t.baseScore, mul, mine: false);
      effects.add(effect);
      if (_state.oppWon) break;
    }
    _botRounds++;
    // The player's snapshot must include what the bot just did, or the next
    // recalculation would erase the bot's marks.
    _visitStart = _state.clone();
    setState(() {
      _botThrows = botThrows;
      _botEffects = effects;
    });

    await Future.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;

    if (_state.oppWon) {
      _onBotLegWon();
      return;
    }

    _handBackToPlayer();
  }

  void _handBackToPlayer() {
    setState(() {
      _botTurnInProgress = false;
      aiManuallyDisabled = false;
      aiPausedForEdit = false;
    });
    autoScoringService?.resetTurn();
    startAiCapture();
    DartSoundService.playYourTurn();
  }

  // ─── Legs & match end ──────────────────────────────────────────────────────

  void _onPlayerLegWon() {
    final placement = context.read<PlacementProvider>();
    _commitVisit();
    if (placement.recordBotLegResult(playerWon: true)) {
      _finishMatch(won: true);
    } else {
      _showLegEnd(won: true);
    }
  }

  void _onBotLegWon() {
    final placement = context.read<PlacementProvider>();
    if (placement.recordBotLegResult(playerWon: false)) {
      _finishMatch(won: false);
    } else {
      _showLegEnd(won: false);
    }
  }

  void _showLegEnd({required bool won}) {
    stopAiCapture();
    if (!won) DartSoundService.playLose();
    setState(() {
      _showingLegEnd = true;
      _lastLegWon = won;
      _legEndSecondsLeft = 5;
      _isWin = false;
      _botTurnInProgress = false;
    });
    _legEndTimer?.cancel();
    _legEndTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_legEndSecondsLeft <= 1) {
        t.cancel();
        _startNextLeg();
      } else {
        setState(() => _legEndSecondsLeft--);
      }
    });
  }

  void _startNextLeg() {
    if (!mounted) return;
    final placement = context.read<PlacementProvider>();
    placement.startNextBotLeg();
    setState(() {
      _showingLegEnd = false;
      _state = CricketState(scoreMode: _scoreMode);
      _visitStart = _state.clone();
      _currentRoundThrows = [];
      _effects = [];
      _dartsThrown = 0;
      _isWin = false;
      _botThrows = [];
      _botEffects = [];
      // Header round number is per-leg (unlike the match-wide MPR counters).
      _botRounds = 0;
      aiManuallyDisabled = false;
      aiPausedForEdit = false;
    });
    autoScoringService?.resetTurn();
    for (int i = 0; i < 3; i++) {
      autoScoringService?.clearDart(i);
    }
    if (placement.playerStartsLeg) {
      DartSoundService.playYourTurn();
      startAiCapture();
    } else {
      _executeBotTurn();
    }
  }

  Future<void> _finishMatch({required bool won}) async {
    final placement = context.read<PlacementProvider>();
    final auth = context.read<AuthProvider>();
    final mpr = _myMpr;
    final modeWire = placement.botConfig?.modeWire;

    setState(() {
      _gameEnded = true;
      _wonMatch = won;
      _statsLoading = true;
      _endMyLegs = placement.myLegs;
      _endBotLegs = placement.botLegs;
      _endBestOf = placement.bestOf;
      _endMyPoints = _state.myPoints;
      _endBotPoints = _state.oppPoints;
    });
    if (!won) DartSoundService.playLose();

    await placement.completeMatch(
      won ? auth.currentUser?.id : null,
      player1Score: 0,
      currentUserId: auth.currentUser?.id,
      dartsThrown: _totalDartsThrown,
      extraDetails: {
        if (mpr != null) 'mpr': double.parse(mpr.toStringAsFixed(2)),
        'marks': _matchMyMarks,
        'rounds': _roundsPlayed,
        'myPoints': _endMyPoints,
        'botPoints': _endBotPoints,
      },
    );
    if (!mounted) return;

    // Historical MPR over the same cricket variant, for the end screen.
    try {
      final sessions = await TrainingService.listSessions(
        type: TrainingType.botTraining,
        limit: 50,
      );
      final mprs = <double>[];
      for (final s in sessions) {
        final d = s.details;
        if (d == null || d['mode'] != modeWire) continue;
        final v = d['mpr'];
        if (v is num && v > 0) mprs.add(v.toDouble());
      }
      final overall = mprs.isEmpty
          ? null
          : mprs.reduce((a, b) => a + b) / mprs.length;
      if (mounted) {
        setState(() {
          _overallMpr = overall;
          _statsLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _statsLoading = false);
    }
  }

  // ─── UI ────────────────────────────────────────────────────────────────────

  String? _seriesTitle(PlacementProvider placement) {
    if (placement.bestOf <= 1) return null;
    return 'BO${placement.bestOf} · '
        '${AppLocalizations.of(context).legNumber(placement.currentLeg)}';
  }

  @override
  Widget build(BuildContext context) {
    final placement = context.watch<PlacementProvider>();
    final auth = context.watch<AuthProvider>();
    final l10n = AppLocalizations.of(context);

    if (_gameEnded) {
      return _buildGameEndScreen(l10n);
    }

    if (_showingLegEnd) {
      return LegEndView(
        wonLeg: _lastLegWon,
        myLegsWon: placement.myLegs,
        opponentLegsWon: placement.botLegs,
        legsNeeded: placement.legsToWin,
        secondsLeft: _legEndSecondsLeft,
        onAttemptPop: _showLeaveDialog,
      );
    }

    final safeTop = MediaQuery.of(context).padding.top;
    final botName = l10n.botRankBotName(
      botRankDisplayLabel(l10n, placement.botRank ?? BotRank.gold),
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldPop = await _showLeaveDialog();
        if (shouldPop && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: autoScoringLoading && !_botTurnInProgress
            ? Container(
                color: AppTheme.background,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          color: AppTheme.primary,
                          strokeWidth: 2,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        dsSentence(l10n.loadingAutoScoring),
                        style: AppTheme.caption.copyWith(fontSize: 13),
                      ),
                    ],
                  ),
                ),
              )
            : !_botTurnInProgress
            ? AutoScoreGameView(
                scoringService: autoScoringService!,
                onConfirm: () {
                  HapticService.heavyImpact();
                  _confirmRound();
                },
                onEndRoundEarly: () {
                  HapticService.heavyImpact();
                  _confirmRound();
                },
                pendingConfirmation: _isWin,
                confirmBesideChips: true,
                scorePanel: CricketScoreTable(
                  state: _state,
                  myName: auth.currentUser?.username ?? 'You',
                  opponentName: botName,
                  seriesTitle: _seriesTitle(placement),
                  myLegs: placement.myLegs,
                  opponentLegs: placement.botLegs,
                  myTurn: true,
                  myMpr: _myMpr,
                  rowHeight: 22,
                ),
                visitTotalText: cricketVisitTotalText(l10n, _effects),
                chipSubtitle: (i, _) => cricketChipSubtitle(
                  l10n,
                  i < _effects.length ? _effects[i] : null,
                ),
                localCameraPreview:
                    !switchingCamera &&
                        cameraService?.controller != null &&
                        cameraService!.isInitialized
                    ? LocalCameraPreview(
                        controller: cameraService!.controller!,
                      )
                    : null,
                onSwitchCamera: switchCamera,
                onZoomIn: zoomIn,
                onZoomOut: zoomOut,
                currentZoom: cameraZoom,
                minZoom: cameraMinZoom,
                maxZoom: cameraMaxZoom,
                onEditDart: (index, dartScore) {
                  final (base, mul) = dartScoreToBackend(dartScore);
                  if (index < _currentRoundThrows.length) {
                    _currentRoundThrows[index] = _CricketDart(base, mul);
                  } else {
                    while (_currentRoundThrows.length < index) {
                      _currentRoundThrows.add(
                        _CricketDart(0, ScoreMultiplier.single),
                      );
                    }
                    _currentRoundThrows.add(_CricketDart(base, mul));
                  }
                  _recalculate();
                  if (_isWin) {
                    stopAiCapture();
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) _showWinDialog();
                    });
                  } else {
                    startAiCapture();
                  }
                },
                onToggleAi: autoScoringService?.modelLoaded == true
                    ? toggleAi
                    : null,
                aiEnabled: !aiManuallyDisabled,
                onBack: () async {
                  final shouldLeave = await _showLeaveDialog();
                  if (shouldLeave && context.mounted) {
                    Navigator.of(context).pop();
                  }
                },
              )
            : _buildBotTurnScreen(placement, auth, botName, safeTop, l10n),
      ),
    );
  }

  Widget _buildBotTurnScreen(
    PlacementProvider placement,
    AuthProvider auth,
    String botName,
    double safeTop,
    AppLocalizations l10n,
  ) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final safeBottom = MediaQuery.of(context).padding.bottom;
    final gutters = gameSideGutters(context);
    final noScore = _scoreMode == CricketScoreMode.noScore;

    final header = TurnScoreHeader(
      myName: auth.currentUser?.username ?? 'You',
      opponentName: botName,
      myScore: noScore ? _state.myClosedCount : _state.myPoints,
      opponentScore: noScore ? _state.oppClosedCount : _state.oppPoints,
      roundNumber: _botRounds + 1,
      seriesTitle: _seriesTitle(placement),
      myLegs: placement.myLegs,
      opponentLegs: placement.botLegs,
      myTurn: false,
      leading: GameControlButton(
        icon: Icons.arrow_back_ios_new_rounded,
        onTap: () async {
          final shouldLeave = await _showLeaveDialog();
          if (shouldLeave && mounted) Navigator.of(context).pop();
        },
      ),
    );

    final botPanel = _buildBotPanel(placement, l10n);
    final visitSection = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        CricketBoardStrip(state: _state),
        const SizedBox(height: 12),
        _buildBotVisitSection(botName, l10n),
      ],
    );

    if (isLandscape) {
      return Container(
        color: AppTheme.gameBackground,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: safeTop),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(gutters.left, 8, 6, 8),
                      child: botPanel,
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(6, 8, gutters.right, 8),
                      child: Column(
                        children: [
                          header,
                          const SizedBox(height: 8),
                          Expanded(
                            child: SingleChildScrollView(child: visitSection),
                          ),
                          const SizedBox(height: 8),
                          const OpponentWarningBanner(),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: safeBottom),
          ],
        ),
      );
    }

    return Container(
      color: AppTheme.gameBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: safeTop),
          const SizedBox(height: 6),
          header,
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SizedBox(
              height: gameCameraHeight(context) * 0.8,
              child: botPanel,
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: visitSection,
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(12, 8, 12, safeBottom + 10),
            child: const OpponentWarningBanner(),
          ),
        ],
      ),
    );
  }

  /// The bot's "feed": the opponent camera panel without a camera — same r20
  /// frame, same 1.5 px rose identity border, a "BOT" chip in the badge-row
  /// slot, and the visit read in rose type rather than a glow.
  Widget _buildBotPanel(PlacementProvider placement, AppLocalizations l10n) {
    final hasThrown = _botThrows.isNotEmpty;
    var marks = 0;
    var points = 0;
    for (final e in _botEffects) {
      marks += e.marksApplied;
      points += e.pointsScored;
    }
    final headline = points > 0 ? l10n.plusPts(points) : '+$marks';
    final caption = l10n.cricketMarks(marks);

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(color: AppTheme.gamePanelEmpty),
          Center(
            child: hasThrown
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        headline,
                        style: const TextStyle(
                          color: AppTheme.opponentPinkBright,
                          fontSize: 56,
                          fontWeight: FontWeight.w800,
                          height: 1,
                          letterSpacing: -1.5,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        caption.toUpperCase(),
                        style: AppTheme.labelSmall.copyWith(height: 1),
                      ),
                    ],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.smart_toy_outlined,
                        size: 44,
                        color: AppTheme.opponentPink,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        dsSentence(
                          l10n.botRankIsThrowing(
                            botRankDisplayLabel(
                              l10n,
                              placement.botRank ?? BotRank.gold,
                            ),
                          ),
                        ),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppTheme.opponentPinkBright,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          color: AppTheme.opponentPink,
                          strokeWidth: 2,
                        ),
                      ),
                    ],
                  ),
          ),
          IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: AppTheme.opponentPink, width: 1.5),
                borderRadius: BorderRadius.circular(AppTheme.radiusCard),
              ),
            ),
          ),
          Positioned(
            top: 10,
            left: 10,
            child: GameChip(text: l10n.bot, color: AppTheme.opponentPinkBright),
          ),
        ],
      ),
    );
  }

  Widget _buildBotVisitSection(String botName, AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        VisitLabelRow(
          label: l10n.visitOf(botName),
          total: 0,
          color: AppTheme.opponentPinkBright,
          totalText: cricketVisitTotalText(l10n, _botEffects),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 74,
          child: Row(
            children: List.generate(3, (i) {
              final notation = i < _botThrows.length
                  ? _botThrows[i].notation
                  : null;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(left: i == 0 ? 0 : 10),
                  child: DartVisitChip(
                    notation: notation,
                    accent: AppTheme.surfaceLight,
                    subtitle: notation != null
                        ? cricketChipSubtitle(
                            l10n,
                            i < _botEffects.length ? _botEffects[i] : null,
                          )
                        : null,
                    highlighted:
                        notation != null && i == _botThrows.length - 1,
                  ),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }

  /// End of a cricket bot match, on the shared [MatchEndView]: result disc,
  /// sentence-case title, the two-coloured legs tile, the MPR rows and ONE
  /// primary action.
  Widget _buildGameEndScreen(AppLocalizations l10n) {
    final didWin = _wonMatch;
    final mpr = _myMpr;
    final isSeries = _endBestOf > 1;

    return MatchEndView(
      didWin: didWin,
      title: didWin ? l10n.victory : l10n.defeat,
      subtitle: '${l10n.cricketLabel} · ${l10n.botPlayer}',
      badgeText: l10n.botPlayer,
      scoreLine: isSeries ? '$_endMyLegs – $_endBotLegs' : null,
      scoreCaption: isSeries ? l10n.bestOfN(_endBestOf) : null,
      preCard: Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _StatRow(
              label: l10n.mprLabel,
              value: mpr != null ? mpr.toStringAsFixed(2) : '—',
              color: AppTheme.playerBlueBright,
              icon: Icons.timeline_rounded,
            ),
            const SizedBox(height: 10),
            _StatRow(
              label: l10n.overallBotAverageLabel,
              value: _statsLoading
                  ? '…'
                  : (_overallMpr != null
                      ? l10n.mprShort(_overallMpr!.toStringAsFixed(2))
                      : '—'),
              color: AppTheme.textPrimary,
              icon: Icons.equalizer_rounded,
            ),
          ],
        ),
      ),
      panel: SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton(
          onPressed: _statsLoading
              ? null
              : () => Navigator.of(context)
                  .pop({'botTraining': true, 'won': didWin}),
          child: Text(dsSentence(l10n.continueButton)),
        ),
      ),
    );
  }

  Future<bool> _showLeaveDialog() async {
    final l10n = AppLocalizations.of(context);
    final shouldLeave = await showGameDialog<bool>(
      context,
      accent: AppTheme.error,
      icon: Icons.logout_rounded,
      title: l10n.leaveMatch,
      content: Text(l10n.leaveMatchWarning, style: AppTheme.bodyMedium),
      actionsBuilder: (ctx) => [
        OutlinedButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(dsSentence(l10n.stay)),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: gameFilledButtonStyle(AppTheme.error),
          child: Text(dsSentence(l10n.leave)),
        ),
      ],
    );
    return shouldLeave ?? false;
  }
}

/// One end-of-match figure: a flat surface card with a hairline, an outlined
/// icon, the label and the value in [color].
class _StatRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  const _StatRow({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return DsCard(
      radius: AppTheme.radiusRow,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.textSecondary, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.rowTitle,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              height: 1,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
