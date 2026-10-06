import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../models/bot_rank.dart';
import '../../models/training.dart';
import '../../providers/placement_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/game_provider.dart';
import '../../services/auto_scoring_service.dart';
import '../../services/dataset_capture_service.dart';
import '../../services/dart_scoring_service.dart';
import '../../services/placement_debug_capture_service.dart';
import '../../services/training_service.dart';
import '../../utils/dart_caller_service.dart';
import '../../utils/dart_sound_service.dart';
import '../../utils/haptic_service.dart';
import '../../utils/app_theme.dart';
import '../../utils/game_system_ui.dart';
import '../../utils/orientation_utils.dart';
import '../../utils/score_converter.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/auto_score_display.dart';
import '../../widgets/design_system.dart';
import '../../widgets/game_turn_ui.dart';
import '../../widgets/local_camera_preview.dart';
import '../../widgets/queue_searching_banner.dart';
import '../game/leg_end_view.dart';
import '../game/match_end_view.dart';
import 'bot_camera_ai_mixin.dart';

class PlacementGameScreen extends StatefulWidget {
  const PlacementGameScreen({super.key});

  @override
  State<PlacementGameScreen> createState() => _PlacementGameScreenState();
}

class _PlacementGameScreenState extends State<PlacementGameScreen>
    with WidgetsBindingObserver, BotCameraAiMixin {
  bool _botTurnInProgress = false;
  bool _gameEnded = false;
  String? _winnerId;
  int? _editingDartIndex;

  // Local scoring state (no sockets)
  int _myScore = 501;
  int _dartsThrown = 0;
  int _totalDartsThrown = 0;
  List<_DartThrow> _currentRoundThrows = [];
  int _scoreBeforeRound = 501;
  bool _isBust = false;
  bool _isWin = false;
  bool _winDialogShowing = false;

  // Per-visit (3-dart) round scores for live & end-of-match averages.
  final List<int> _myRoundScores = [];
  final List<int> _botRoundScores = [];
  int _lastBotScore = 501;

  // Bot visits in the CURRENT leg only — the header's round number.
  // _botRoundScores keeps accumulating across legs for the match average, so
  // it can't drive the display in a series.
  int _botRoundsThisLeg = 0;

  // Bot-training series (BO3-BO11): between-legs screen state. Placement
  // matches stay single-leg and never enter this branch.
  bool _showingLegEnd = false;
  bool _lastLegWon = false;
  int _legEndSecondsLeft = 0;
  Timer? _legEndTimer;

  // Post-match stat screen state (bot-training only).
  bool _statsLoading = false;
  double? _overallBotAverage;
  bool _endIsBotTraining = false;
  int _endMyLegs = 0;
  int _endBotLegs = 0;
  int _endBestOf = 1;

  // Auto-scoring (local camera): fields and controls come from
  // BotCameraAiMixin, shared with the cricket bot screen.

  // Diagnostic capture of the first placement match (see
  // PlacementDebugCapture). Fires while the player's visit is still short of
  // three darts: a frame taken then is the only thing that can distinguish
  // "he never threw" from "he threw and the AI saw nothing".
  Timer? _debugCaptureTimer;
  static const Duration _debugCaptureInterval = Duration(seconds: 45);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WakelockPlus.enable();
    OrientationUtils.allowAll();
    GameSystemUi.enter();
    final provider = context.read<PlacementProvider>();
    _myScore = provider.player1Score;
    _scoreBeforeRound = _myScore;
    _lastBotScore = provider.player2Score;
    if (provider.mode == PlacementMode.placement) {
      PlacementDebugCapture.startMatch(
        matchId: provider.currentMatchId,
        botDifficulty: provider.currentBotDifficulty,
      );
    }
    autoScoringService = AutoScoringService();
    // This screen serves BOTH real placement matches and bot trainings, and
    // they differ on both axes. A bot training has no backend match record —
    // its `currentMatchId` is a locally minted 'training-<millis>' string —
    // so sending it would label the row with an id that joins to nothing.
    autoScoringService!.telemetrySessionOf = () {
      final placement = context.read<PlacementProvider>();
      final isBot = placement.mode == PlacementMode.botTraining;
      return (isBot ? 'bot' : 'placement', isBot ? null : placement.currentMatchId);
    };
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await initCameraAndAI();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _legEndTimer?.cancel();
    _debugCaptureTimer?.cancel();
    PlacementDebugCapture.endMatch();
    disposeCameraAndAI();
    // Same deferral contract as the online verdict flush — solo modes have
    // no verdict, the screen teardown is their "match over".
    DatasetCaptureService.flush();
    WakelockPlus.disable();
    OrientationUtils.portraitOnly();
    GameSystemUi.exit();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
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

  double? get _myAverage {
    if (_myRoundScores.isEmpty) return null;
    final total = _myRoundScores.fold<int>(0, (a, b) => a + b);
    return total / _myRoundScores.length;
  }

  double? get _botAverage {
    if (_botRoundScores.isEmpty) return null;
    final total = _botRoundScores.fold<int>(0, (a, b) => a + b);
    return total / _botRoundScores.length;
  }

  int _dartScore(int baseScore, ScoreMultiplier multiplier) {
    switch (multiplier) {
      case ScoreMultiplier.single:
        return baseScore;
      case ScoreMultiplier.double:
        return baseScore * 2;
      case ScoreMultiplier.triple:
        return baseScore * 3;
    }
  }

  // ─── Auto-scoring (BotCameraAiMixin hooks) ─────────────────────────────────

  @override
  void onCameraAiReady() => _startDebugCapture();

  /// No camera (or the AI init threw) means no frame to diagnose with — say
  /// so, or this match looks exactly like a player who simply never threw.
  @override
  void onCameraAiInitFailed(String stage) {
    unawaited(PlacementDebugCapture.note(stage, health: _debugHealth()));
  }

  @override
  void onAiAutoConfirm() => _confirmRound();

  /// Diagnostic dump of the first placement match: one frame as the board
  /// comes into view, then one every [_debugCaptureInterval] for as long as
  /// the current visit is still short of three darts. Deliberately keeps
  /// firing when the model failed to load — "AI dead, board fine" is exactly
  /// one of the answers we're after.
  void _startDebugCapture() {
    if (!PlacementDebugCapture.isActive) return;
    unawaited(PlacementDebugCapture.capture(cameraService,
        reason: 'open', health: _debugHealth()));
    _debugCaptureTimer?.cancel();
    _debugCaptureTimer = Timer.periodic(_debugCaptureInterval, (_) {
      if (!mounted || _gameEnded || _botTurnInProgress) return;
      if (_currentRoundThrows.length >= 3) return;
      unawaited(PlacementDebugCapture.capture(
        cameraService,
        reason: 'idle_d${_currentRoundThrows.length}',
        health: _debugHealth(),
      ));
    });
  }

  Map<String, dynamic> _debugHealth() {
    final ai = autoScoringService;
    return {
      'aiLoaded': ai?.modelLoaded ?? false,
      'aiLoading': ai?.isModelLoading ?? false,
      'aiError': ai?.initError,
      'aiOff': aiManuallyDisabled,
      'inferMs': ai?.lastInferenceMs,
      'framesAnalyzed': ai?.framesAnalyzed ?? 0,
      'lastTips': ai?.lastDartTipCount ?? 0,
      'lastCalibPts': ai?.lastCalibrationPointCount ?? 0,
      'camera': cameraService?.isInitialized ?? false,
      'zoom': cameraZoom,
    };
  }

  @override
  void onAiDartDetected(int slotIndex, DartScore dartScore) {
    if (!mounted || _botTurnInProgress || _gameEnded || _showingLegEnd) return;
    final (base, mul) = dartScoreToBackend(dartScore);
    HapticService.mediumImpact();
    DartSoundService.playDartHit(base, mul);

    // Score update for an already-tracked dart (model refined its prediction)
    if (slotIndex < _currentRoundThrows.length) {
      setState(() {
        _currentRoundThrows[slotIndex] = _DartThrow(base, mul, aiReading: dartScore);
      });
      _recalculateScore();
    } else {
      _throwDart(base, mul, aiReading: dartScore);
    }

    if (_isWin) {
      stopAiCapture();
      WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _showWinDialog(); });
    } else if (_isBust) {
      stopAiCapture();
      WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _showBustDialog(); });
    }
  }

  // ───────────────────────────────────────────────────────────────────────────

  void _throwDart(int baseScore, ScoreMultiplier multiplier, {DartScore? aiReading}) {
    if (_dartsThrown >= 3 || _botTurnInProgress || _gameEnded || _isBust || _isWin) return;

    // If editing an existing dart, replace it — keeping whatever the AI had
    // read for that slot, which is precisely what makes the correction a
    // labelled sample rather than just a fix.
    if (_editingDartIndex != null && _editingDartIndex! < _currentRoundThrows.length) {
      setState(() {
        _currentRoundThrows[_editingDartIndex!] = _DartThrow(
          baseScore,
          multiplier,
          aiReading: aiReading ?? _currentRoundThrows[_editingDartIndex!].aiReading,
        );
        _editingDartIndex = null;
      });
      _recalculateScore();
      return;
    }

    // Play dart hit sound
    DartSoundService.playDartHit(baseScore, multiplier);

    final score = _dartScore(baseScore, multiplier);
    final newScore = _myScore - score;

    // Bust: score goes below 0, equals 1, or hits 0 without a double
    if (newScore < 0 || newScore == 1 || (newScore == 0 && multiplier != ScoreMultiplier.double)) {
      setState(() {
        _isBust = true;
        _currentRoundThrows.add(
            _DartThrow(baseScore, multiplier, aiReading: aiReading));
        _dartsThrown++;
      });
      DartSoundService.playBust();
      return;
    }

    setState(() {
      _myScore = newScore;
      // aiReading must ride the ADD too, not just the edit branch above: a
      // dart the model detects arrives here the first time (its slot does not
      // exist yet), so dropping it here recorded EVERY placement dart as a
      // manual entry — 0 of 153 matches carried an AI reading between the
      // feature shipping on 2026-08-21 and this fix.
      _currentRoundThrows.add(
          _DartThrow(baseScore, multiplier, aiReading: aiReading));
      _dartsThrown++;
    });

    // Check win (checkout on double)
    if (newScore == 0 && multiplier == ScoreMultiplier.double) {
      setState(() => _isWin = true);
      return;
    }

    // Caller: announce the visit total right after the third dart lands.
    // Turns that end early (1–2 darts) are announced from _confirmRound instead.
    if (_dartsThrown == 3) {
      DartCallerService.callScore(_scoreBeforeRound - _myScore);
    }
  }

  void _recalculateScore() {
    int score = _scoreBeforeRound;
    bool bust = false;
    bool win = false;

    for (final dart in _currentRoundThrows) {
      final s = _dartScore(dart.baseScore, dart.multiplier);
      final newScore = score - s;
      if (newScore < 0 || newScore == 1 || (newScore == 0 && dart.multiplier != ScoreMultiplier.double)) {
        bust = true;
        break;
      }
      score = newScore;
      if (score == 0 && dart.multiplier == ScoreMultiplier.double) {
        win = true;
        break;
      }
    }

    setState(() {
      _myScore = bust ? _scoreBeforeRound : score;
      _dartsThrown = _currentRoundThrows.length;
      _isBust = bust;
      _isWin = win;
    });
  }

  void _confirmRound() {
    stopAiCapture();

    // Captured before the setState below clears it: the server needs to know
    // this visit busted, and _isBust is about to be reset.
    final bool busted = _isBust;
    final int roundScore;
    final List<String> roundThrows = _currentRoundThrows.map((t) => t.notation).toList();
    // The same visit, dart by dart, with what the AI read for each. Sent
    // alongside roundThrows rather than instead of it, so a server that only
    // knows the notations keeps working.
    final List<Map<String, dynamic>> roundDarts =
        _currentRoundThrows.map((t) => t.toJson()).toList();
    final int dartsThisRound = _currentRoundThrows.length;

    if (_isBust) {
      roundScore = 0;
      setState(() {
        _myScore = _scoreBeforeRound;
        _dartsThrown = 0;
        _totalDartsThrown += dartsThisRound;
        _currentRoundThrows = [];
        _isBust = false;
        _scoreBeforeRound = _myScore;
        _myRoundScores.add(0);
      });
    } else {
      roundScore = _scoreBeforeRound - _myScore;
      setState(() {
        _dartsThrown = 0;
        _totalDartsThrown += dartsThisRound;
        _currentRoundThrows = [];
        _scoreBeforeRound = _myScore;
        _myRoundScores.add(roundScore);
      });
      // Caller: a full 3-dart visit is already announced by _throwDart when the
      // third dart lands. Here we only cover turns ended early (1–2 darts) via
      // "finish turn" or removing darts.
      if (dartsThisRound >= 1 && dartsThisRound < 3) {
        DartCallerService.callScore(roundScore);
      }
    }

    DartSoundService.playTurnFinished();
    // A visit validated with fewer than three darts is the symptom we're
    // chasing — grab the board as it was when the player accepted it. (On an
    // auto-confirm the darts are already out, which is itself informative:
    // it says the player threw and pulled them.)
    if (dartsThisRound < 3) {
      unawaited(PlacementDebugCapture.capture(
        cameraService,
        reason: 'visit_r${_myRoundScores.length}_d$dartsThisRound',
        health: _debugHealth(),
      ));
    }
    _executeBotTurn(
      playerRoundScore: roundScore,
      playerRoundThrows: roundThrows,
      playerRoundDarts: roundDarts,
      dartsThisRound: dartsThisRound,
      playerBusted: busted,
    );
  }

  Future<void> _executeBotTurn({
    int? playerRoundScore,
    List<String>? playerRoundThrows,
    List<Map<String, dynamic>>? playerRoundDarts,
    int dartsThisRound = 0,
    bool playerBusted = false,
  }) async {
    if (_botTurnInProgress || _gameEnded) return;

    setState(() => _botTurnInProgress = true);

    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;

    final placement = context.read<PlacementProvider>();
    final success = await placement.triggerBotTurn(
      playerRoundScore: playerRoundScore,
      playerRoundThrows: playerRoundThrows,
      playerRoundDarts: playerRoundDarts,
      playerScoreAfterRound: _myScore,
      playerBusted: playerBusted,
    );

    // Logged whatever the server answered: a visit the backend refused (a
    // match already forfeited under the player's feet, a network drop) leaves
    // no trace anywhere else, and a leg played against a frozen bot is
    // precisely the kind of zombie match worth catching.
    if (playerRoundScore != null) {
      PlacementDebugCapture.recordVisit(
        roundIndex: _myRoundScores.length,
        dartsRegistered: dartsThisRound,
        roundScore: playerRoundScore,
        remaining: _myScore,
        sentToServer: success,
      );
    }

    if (success && mounted) {
      _botRoundsThisLeg++;
      // Bot just played a visit: record its 3-dart score (0 on bust).
      final botRoundScore =
          placement.botIsBust ? 0 : (_lastBotScore - placement.player2Score);
      if (botRoundScore >= 0) {
        setState(() {
          _botRoundScores.add(botRoundScore);
          _lastBotScore = placement.player2Score;
        });
        // Caller: announce the bot's visit like a human opponent's in a ranked
        // match. The total matches what the bot panel shows — 0 on a bust,
        // which the caller reads as "no score".
        DartCallerService.callScore(botRoundScore);
      } else {
        _lastBotScore = placement.player2Score;
      }

      await Future.delayed(const Duration(milliseconds: 1200));

      if (placement.botIsCheckout && placement.player2Score == 0) {
        _onBotCheckout();
        return;
      }
    }

    if (mounted) {
      setState(() { _botTurnInProgress = false; aiManuallyDisabled = false; aiPausedForEdit = false; });
      autoScoringService?.resetTurn();
      startAiCapture();
      DartSoundService.playYourTurn();
      // Caller: announce "you require N" when the player comes to the throw on a
      // finish (no-op otherwise), mirroring the online game screen.
      DartCallerService.callCheckout(_myScore);
    }
  }

  bool _bustDialogShowing = false;

  void _showBustDialog() {
    if (_bustDialogShowing || !mounted) return;
    _bustDialogShowing = true;
    final l10n = AppLocalizations.of(context);
    final visitTotal = visitPoints(_currentRoundThrows.map((dart) => dart.notation));
    showGameDialog(
      context,
      accent: AppTheme.error,
      icon: Icons.error_outline_rounded,
      title: l10n.bust,
      prominentActions: true,
      content: GameBustDialogContent(
        reason: l10n.scoreBusted,
        remaining: _scoreBeforeRound,
        visitTotal: visitTotal,
      ),
      actionsBuilder: (ctx) => [
        OutlinedButton(
          onPressed: () {
            _bustDialogShowing = false;
            Navigator.pop(ctx);
            setState(() {
              aiPausedForEdit = true;
              _isBust = false;
              _currentRoundThrows.clear();
              _dartsThrown = 0;
              _myScore = _scoreBeforeRound;
            });
            autoScoringService?.stopCapture();
            for (int i = 0; i < 3; i++) { autoScoringService?.clearDart(i); }
          },
          style: gameNeutralOutlineButtonStyle(),
          child: Text(dsSentence(l10n.editDarts)),
        ),
        ElevatedButton(
          onPressed: () {
            _bustDialogShowing = false;
            Navigator.pop(ctx);
            _confirmRound();
          },
          style: gameFilledButtonStyle(AppTheme.primary),
          child: Text(dsSentence(l10n.confirmBustButton)),
        ),
      ],
    ).then((_) => _bustDialogShowing = false);
  }

  void _showWinDialog() {
    if (_winDialogShowing || !mounted) return;
    final notation = _currentRoundThrows.isNotEmpty ? _currentRoundThrows.last.notation : '—';
    _winDialogShowing = true;
    final l10n = AppLocalizations.of(context);
    showGameDialog(
      context,
      accent: AppTheme.success,
      icon: Icons.emoji_events_outlined,
      title: l10n.checkout,
      prominentActions: true,
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(l10n.youHitToFinish(notation), style: gameDialogBodyStyle),
        const SizedBox(height: 6),
        Text(l10n.isThisCorrect, style: gameDialogHintStyle),
      ]),
      actionsBuilder: (ctx) => [
        OutlinedButton(
          onPressed: () {
            _winDialogShowing = false;
            Navigator.pop(ctx);
            setState(() {
              aiPausedForEdit = true;
              _isWin = false;
              _currentRoundThrows.clear();
              _dartsThrown = 0;
              _myScore = _scoreBeforeRound;
            });
            autoScoringService?.stopCapture();
            for (int i = 0; i < 3; i++) { autoScoringService?.clearDart(i); }
          },
          style: gameNeutralOutlineButtonStyle(),
          child: Text(dsSentence(l10n.editDarts)),
        ),
        ElevatedButton(
          onPressed: () {
            _winDialogShowing = false;
            Navigator.pop(ctx);
            DartSoundService.playWin();
            _onPlayerCheckout();
          },
          style: gameFilledButtonStyle(AppTheme.success),
          child: Text(dsSentence(l10n.confirmWin)),
        ),
      ],
    ).then((_) => _winDialogShowing = false);
  }

  /// Folds the in-flight (unconfirmed) visit into the round history — a
  /// checkout mid-visit bypasses _confirmRound, so without this the match
  /// average and dart count would miss the winning darts.
  void _foldCurrentRound() {
    if (_currentRoundThrows.isEmpty) return;
    final roundScore = _scoreBeforeRound - _myScore;
    _myRoundScores.add(!_isBust && roundScore >= 0 ? roundScore : 0);
    _totalDartsThrown += _currentRoundThrows.length;
    _currentRoundThrows = [];
    _dartsThrown = 0;
  }

  /// Player confirmed their checkout: single-leg flows end the match, a
  /// bot-training series records the leg and moves on.
  void _onPlayerCheckout() {
    final placement = context.read<PlacementProvider>();
    final auth = context.read<AuthProvider>();
    _foldCurrentRound();
    if (placement.mode != PlacementMode.botTraining || placement.bestOf <= 1) {
      _handleGameEnd(auth.currentUser?.id);
      return;
    }
    if (placement.recordBotLegResult(playerWon: true)) {
      _handleGameEnd(auth.currentUser?.id);
    } else {
      _showLegEnd(won: true);
    }
  }

  /// Bot reached zero: same split as [_onPlayerCheckout], other side.
  void _onBotCheckout() {
    final placement = context.read<PlacementProvider>();
    if (placement.mode != PlacementMode.botTraining || placement.bestOf <= 1) {
      _handleGameEnd(null);
      return;
    }
    if (placement.recordBotLegResult(playerWon: false)) {
      _handleGameEnd(null);
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
      _isBust = false;
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
      _myScore = placement.startingScore;
      _scoreBeforeRound = placement.startingScore;
      _dartsThrown = 0;
      _currentRoundThrows = [];
      _isBust = false;
      _isWin = false;
      _lastBotScore = placement.startingScore;
      _botRoundsThisLeg = 0;
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
      // Alternation: the bot opens this leg before the player's first visit.
      _executeBotTurn();
    }
  }

  void _handleGameEnd(String? winnerId) async {
    _foldCurrentRound();

    final placement = context.read<PlacementProvider>();
    final auth = context.read<AuthProvider>();
    final wasPlacement = placement.mode == PlacementMode.placement;
    final isBotTraining = placement.mode == PlacementMode.botTraining;
    // completeMatch clears the bot config — capture what the end screen and
    // the per-mode history filter still need.
    final modeWire = placement.botConfig?.modeWire;

    setState(() {
      _gameEnded = true;
      _winnerId = winnerId;
      _endIsBotTraining = isBotTraining;
      _statsLoading = isBotTraining;
      _endMyLegs = placement.myLegs;
      _endBotLegs = placement.botLegs;
      _endBestOf = placement.bestOf;
    });

    if (winnerId == null) {
      DartSoundService.playLose();
    }
    // _foldCurrentRound already rolled any in-flight darts into the total.
    final totalDarts = _totalDartsThrown;
    final matchAverage = _myAverage;
    final result = await placement.completeMatch(
      winnerId,
      player1Score: _myScore,
      currentUserId: auth.currentUser?.id,
      dartsThrown: totalDarts,
      matchPlayerAverage: matchAverage,
    );

    if (!mounted || result == null) return;

    if (wasPlacement) {
      await context.read<AuthProvider>().checkAuthStatus();
      if (mounted) Navigator.of(context).pop(result);
      return;
    }

    if (isBotTraining) {
      // Stay on the end screen and load the historical bot-training average
      // so the player can see both this match's stat and their overall trend.
      // Only sessions of the same game mode count — comparing a 301 average
      // to a 501 one (or an MPR) would be meaningless. Legacy sessions have
      // no details.mode; their bucket is their starting score.
      try {
        final sessions = await TrainingService.listSessions(
          type: TrainingType.botTraining,
          limit: 50,
        );
        bool sameMode(Map<String, dynamic> d) {
          if (modeWire == null) return true;
          final m = d['mode'];
          if (m is String) return m == modeWire;
          final ss = d['startingScore'];
          return ss is num && '${ss.toInt()}' == modeWire;
        }

        // completeMatch already POSTed this match, so listSessions returns it —
        // appending matchAverage here would count the last match twice.
        final averages = <double>[];
        for (final s in sessions) {
          final d = s.details;
          if (d == null || !sameMode(d)) continue;
          final a = d['playerAverage'];
          if (a is num && a > 0) averages.add(a.toDouble());
        }
        final overall = averages.isEmpty
            ? null
            : averages.reduce((a, b) => a + b) / averages.length;
        if (mounted) {
          setState(() {
            _overallBotAverage = overall;
            _statsLoading = false;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _statsLoading = false);
      }
      return;
    }

    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final placement = context.watch<PlacementProvider>();
    final auth = context.watch<AuthProvider>();

    if (_gameEnded) {
      final didWin = _winnerId == auth.currentUser?.id;
      return _buildGameEndScreen(didWin, isBotTraining: _endIsBotTraining);
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

    if (placement.currentMatchId == null) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        body: const Center(
          child: CircularProgressIndicator(color: AppTheme.primary),
        ),
      );
    }

    final safeTop = MediaQuery.of(context).padding.top;
    final botName = _botName(context, placement);

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
        body: Stack(
          children: [
            // Main content
            autoScoringLoading && !_botTurnInProgress
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
                          dsSentence(
                            AppLocalizations.of(context).loadingAutoScoring,
                          ),
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
                      if (_isWin) { _showWinDialog(); } else if (_isBust) { _showBustDialog(); } else { _confirmRound(); }
                    },
                    onEndRoundEarly: () { HapticService.heavyImpact(); _confirmRound(); },
                    pendingConfirmation: _isBust || _isWin,
                    // Same no-badges score header as the online X01 screens
                    // (2026-08-19 unified header).
                    header: TurnScoreHeader(
                      myName: auth.currentUser?.username ?? 'You',
                      opponentName: botName,
                      myScore: _myScore,
                      opponentScore: placement.player2Score,
                      myAverage: _myAverage,
                      opponentAverage: _botAverage,
                      seriesTitle: _seriesTitle(placement),
                      myLegs: placement.myLegs,
                      opponentLegs: placement.botLegs,
                      showBadges: false,
                      myTurn: true,
                    ),
                    localCameraPreview: !switchingCamera && cameraService?.controller != null && cameraService!.isInitialized
                        ? LocalCameraPreview(controller: cameraService!.controller!)
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
                        _currentRoundThrows[index] = _DartThrow(base, mul);
                      } else {
                        while (_currentRoundThrows.length < index) {
                          _currentRoundThrows.add(_DartThrow(0, ScoreMultiplier.single));
                        }
                        _currentRoundThrows.add(_DartThrow(base, mul));
                      }
                      _recalculateScore();
                      if (_isWin) {
                        stopAiCapture();
                        WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _showWinDialog(); });
                      } else if (_isBust) {
                        stopAiCapture();
                        WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _showBustDialog(); });
                      } else {
                        // Why: the dart edit modal stops capture so detections
                        // don't overwrite the manual correction. In ranked,
                        // capture restarts via the GameProvider listener; bot
                        // training has no such listener, so restart explicitly
                        // — otherwise removal detection can't auto-end the turn.
                        startAiCapture();
                      }
                    },
                    onToggleAi: autoScoringService!.modelLoaded ? toggleAi : null,
                    aiEnabled: !aiManuallyDisabled,
                    onBack: () async {
                      final shouldLeave = await _showLeaveDialog();
                      if (shouldLeave && context.mounted) Navigator.of(context).pop();
                    },
                  )
                // Bot's turn
                : _buildBotTurnScreen(placement, auth, botName, safeTop),

            // "Still searching" pill when this bot training was launched while
            // queued — the player is pulled into the match automatically when
            // an opponent is found (see MatchmakingNavigationGate). Sits a row
            // below the in-camera top controls so it never overlaps them, and
            // uses a high-contrast gold style to stay readable over the
            // camera feed.
            Positioned(
              top: safeTop + 52,
              left: 0,
              right: 0,
              child: const Center(child: QueueSearchingBanner()),
            ),
          ],
        ),
      ),
    );
  }

  /// "BO5 · Manche 2" for a bot-training series, null for single-leg flows —
  /// same string the ranked series shows, so the score bar center matches.
  String? _seriesTitle(PlacementProvider placement) {
    if (placement.mode != PlacementMode.botTraining || placement.bestOf <= 1) {
      return null;
    }
    return 'BO${placement.bestOf} · '
        '${AppLocalizations.of(context).legNumber(placement.currentLeg)}';
  }

  Widget _buildBotTurnScreen(
    PlacementProvider placement,
    AuthProvider auth,
    String botName,
    double safeTop,
  ) {
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    final safeBottom = MediaQuery.of(context).padding.bottom;
    final gutters = gameSideGutters(context);

    final header = TurnScoreHeader(
      myName: auth.currentUser?.username ?? 'You',
      opponentName: botName,
      myScore: _myScore,
      opponentScore: placement.player2Score,
      roundNumber: _botRoundsThisLeg + 1,
      myAverage: _myAverage,
      opponentAverage: _botAverage,
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

    final botPanel = _buildBotPanel(placement);
    final visitSection = _buildBotVisitSection(placement, botName);

    if (isLandscape) {
      return Container(
        color: AppTheme.gameBackground,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: safeTop),
            Expanded(
              child: Row(children: [
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(gutters.left, 8, 6, 8),
                    child: botPanel,
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(6, 8, gutters.right, 8),
                    child: Column(children: [
                      header,
                      const SizedBox(height: 8),
                      Expanded(child: SingleChildScrollView(child: visitSection)),
                      const SizedBox(height: 8),
                      const OpponentWarningBanner(),
                    ]),
                  ),
                ),
              ]),
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
              height: gameCameraHeight(context),
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

  /// Center panel for the bot's turn — the opponent camera panel without a
  /// feed: the same r20 frame and the same 1.5 px rose identity border, a
  /// "BOT" chip in the badge-row slot, then the robot + spinner while the bot
  /// "aims" and the visit total (with its bust / checkout verdict) once the
  /// throws land. No glow: the rose type carries the identity.
  Widget _buildBotPanel(PlacementProvider placement) {
    final l10n = AppLocalizations.of(context);
    final throws = placement.lastBotThrows;
    final hasThrown = throws.isNotEmpty;
    final visitTotal =
        throws.fold<int>(0, (sum, t) => sum + notationPoints(t.notation));
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(color: AppTheme.gamePanelEmpty),
          Center(
            child: hasThrown
                ? Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(
                      l10n.plusPts(placement.botIsBust ? 0 : visitTotal),
                      style: const TextStyle(
                        color: AppTheme.opponentPinkBright,
                        fontSize: 56,
                        fontWeight: FontWeight.w800,
                        height: 1,
                        letterSpacing: -1.5,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    if (placement.botIsBust || placement.botIsCheckout) ...[
                      const SizedBox(height: 12),
                      Text(
                        (placement.botIsBust ? l10n.bust : l10n.checkout)
                            .toUpperCase(),
                        style: AppTheme.labelSmall.copyWith(
                          color: placement.botIsBust
                              ? AppTheme.opponentPinkBright
                              : AppTheme.success,
                          height: 1,
                        ),
                      ),
                    ],
                  ])
                : Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(
                      Icons.smart_toy_outlined,
                      size: 44,
                      color: AppTheme.opponentPink,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      dsSentence(_botIsThrowingLabel(context, placement)),
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
                  ]),
          ),
          // ── Rose identity border: the same 1.5 px line as the live feed ──
          IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: AppTheme.opponentPink, width: 1.5),
                borderRadius: BorderRadius.circular(AppTheme.radiusCard),
              ),
            ),
          ),
          // "BOT" chip where the badge row sits on the opponent feed.
          Positioned(
            top: 10,
            left: 10,
            child: GameChip(text: l10n.bot, color: AppTheme.opponentPinkBright),
          ),
        ],
      ),
    );
  }

  /// "VOLÉE DE (bot) … TOTAL n" + the three visit chips, mirroring the
  /// opponent-turn visit section.
  Widget _buildBotVisitSection(PlacementProvider placement, String botName) {
    final l10n = AppLocalizations.of(context);
    final throws = placement.lastBotThrows;
    final total =
        throws.fold<int>(0, (sum, t) => sum + notationPoints(t.notation));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        VisitLabelRow(
          label: l10n.visitOf(botName),
          total: total,
          color: AppTheme.opponentPinkBright,
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 74,
          child: Row(
            children: List.generate(3, (i) {
              final notation = i < throws.length ? throws[i].notation : null;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(left: i == 0 ? 0 : 10),
                  child: DartVisitChip(
                    notation: notation,
                    accent: AppTheme.surfaceLight,
                    highlighted: notation != null && i == throws.length - 1,
                  ),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }

  /// End of a bot / placement match, on the shared [MatchEndView]: result
  /// disc, sentence-case title, the two-coloured legs tile, the stat rows and
  /// ONE primary action. A placement leg has no action — the result is being
  /// saved — so its "panel" is the spinner it always was.
  Widget _buildGameEndScreen(bool didWin, {bool isBotTraining = false}) {
    final l10n = AppLocalizations.of(context);
    final match = _myAverage;
    final isSeries = isBotTraining && _endBestOf > 1;

    final Widget panel = !isBotTraining
        ? Column(
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
              const SizedBox(height: 12),
              Text(
                dsSentence(l10n.savingResult),
                style: AppTheme.caption.copyWith(fontSize: 13),
              ),
            ],
          )
        : SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _statsLoading
                  ? null
                  : () => Navigator.of(context)
                      .pop({'botTraining': true, 'won': didWin}),
              child: Text(dsSentence(l10n.continueButton)),
            ),
          );

    final Widget? preCard = !isBotTraining
        ? null
        : Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _StatRow(
                  label: l10n.matchAverageLabel,
                  value: match != null && match > 0
                      ? l10n.matchAverageValue(match.toStringAsFixed(1))
                      : '—',
                  color: AppTheme.playerBlueBright,
                  icon: Icons.timeline_rounded,
                ),
                const SizedBox(height: 10),
                _StatRow(
                  label: l10n.overallBotAverageLabel,
                  value: _statsLoading
                      ? '…'
                      : (_overallBotAverage != null && _overallBotAverage! > 0
                          ? l10n.overallBotAverageValue(
                              _overallBotAverage!.toStringAsFixed(1))
                          : '—'),
                  color: AppTheme.textPrimary,
                  icon: Icons.equalizer_rounded,
                ),
              ],
            ),
          );

    return MatchEndView(
      didWin: didWin,
      title: didWin ? l10n.victory : l10n.defeat,
      subtitle: didWin ? l10n.youWon : l10n.youLost,
      badgeText: l10n.botPlayer,
      scoreLine: isSeries ? '$_endMyLegs – $_endBotLegs' : null,
      scoreCaption: isSeries ? l10n.bestOfN(_endBestOf) : null,
      preCard: preCard,
      panel: panel,
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

String _botName(BuildContext context, PlacementProvider placement) {
  final l10n = AppLocalizations.of(context);
  if (placement.mode == PlacementMode.botTraining && placement.botRank != null) {
    return l10n.botRankBotName(botRankDisplayLabel(l10n, placement.botRank!));
  }
  return l10n.botName(placement.currentBotDifficulty ?? 1);
}

String _botIsThrowingLabel(BuildContext context, PlacementProvider placement) {
  final l10n = AppLocalizations.of(context);
  if (placement.mode == PlacementMode.botTraining && placement.botRank != null) {
    return l10n.botRankIsThrowing(botRankDisplayLabel(l10n, placement.botRank!));
  }
  return l10n.botNameIsThrowing(placement.currentBotDifficulty ?? 1);
}

/// Localized rank name — shared with the cricket bot screen.
String botRankDisplayLabel(AppLocalizations l10n, BotRank rank) {
  switch (rank) {
    case BotRank.bronze:
      return l10n.rankBronze;
    case BotRank.silver:
      return l10n.rankSilver;
    case BotRank.gold:
      return l10n.rankGold;
    case BotRank.platinum:
      return l10n.rankPlatinum;
    case BotRank.diamond:
      return l10n.rankDiamond;
    case BotRank.pro:
      return l10n.rankPro;
    case BotRank.master:
      return l10n.rankMaster;
  }
}

class _DartThrow {
  final int baseScore;
  final ScoreMultiplier multiplier;

  /// What the model read for this dart, kept even if the player then corrects
  /// it: the pair (reading, correction) is a ground-truth training sample.
  /// Null for a dart typed in by hand.
  final DartScore? aiReading;

  _DartThrow(this.baseScore, this.multiplier, {this.aiReading});

  /// The per-dart record the backend stores on the visit. Only the fields the
  /// server knows how to read; a server that predates them ignores the lot and
  /// records the notation alone, exactly as before.
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{'notation': notation};
    final ai = aiReading;
    if (ai == null) {
      json['source'] = 'manual';
      return json;
    }
    json['source'] = 'ai';
    json['aiNotation'] = _notationOf(ai);
    // Only the finite ones — see finiteOrNull. This body is posted with
    // jsonEncode too, so an infinite radius would fail the whole bot turn.
    json.addAll(ai.telemetry);
    return json;
  }

  /// The model's own reading, before any correction by the player.
  static String _notationOf(DartScore score) {
    switch (score.ring) {
      case 'triple':
        return 'T${score.segment}';
      case 'double':
        return 'D${score.segment}';
      case 'double_bull':
        return 'D25';
      case 'single_bull':
        return 'S25';
      default:
        return 'S${score.segment}';
    }
  }

  String get notation {
    switch (multiplier) {
      case ScoreMultiplier.single:
        return 'S$baseScore';
      case ScoreMultiplier.double:
        return 'D$baseScore';
      case ScoreMultiplier.triple:
        return 'T$baseScore';
    }
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
