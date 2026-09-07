import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../l10n/app_localizations.dart';
import '../../models/cricket.dart';
import '../../models/local_match_config.dart';
import '../../providers/game_provider.dart' show ScoreMultiplier;
import '../../services/auto_scoring_service.dart';
import '../../services/dart_scoring_service.dart';
import '../../services/dataset_capture_service.dart';
import '../../utils/app_theme.dart';
import '../../utils/dart_sound_service.dart';
import '../../utils/haptic_service.dart';
import '../../utils/orientation_utils.dart';
import '../../utils/score_converter.dart';
import '../../widgets/auto_score_display.dart';
import '../../widgets/cricket_board.dart';
import '../../widgets/design_system.dart';
import '../../widgets/game_turn_ui.dart';
import '../../widgets/local_camera_preview.dart';
import '../placement/bot_camera_ai_mixin.dart';
import 'local_match_widgets.dart';

/// Local (hot-seat) cricket: the X01 local-match flow — two players, one
/// phone on its mount, hands-free turn switches, nothing persisted — on the
/// [CricketState] rules and the score table of the bot cricket screen.
///
/// The board is always oriented to the thrower: the "my" side of the state is
/// whoever is throwing (blue, left), the way the X01 local header puts the
/// thrower on the blue side. Every hand-over flips the state.
class LocalCricketMatchScreen extends StatefulWidget {
  final LocalMatchConfig config;

  const LocalCricketMatchScreen({super.key, required this.config});

  @override
  State<LocalCricketMatchScreen> createState() =>
      _LocalCricketMatchScreenState();
}

class _CricketDart {
  final int baseScore;
  final ScoreMultiplier multiplier;

  _CricketDart(this.baseScore, this.multiplier);
}

class _LocalCricketMatchScreenState extends State<LocalCricketMatchScreen>
    with WidgetsBindingObserver, BotCameraAiMixin {
  // ── Match state ──────────────────────────────────────────────────────────
  final List<int> _legsWon = [0, 0];
  int _activePlayer = 0; // who is throwing now
  int _legStarter = 0; // who threw first in the current leg (alternates)
  int _legNumber = 1;
  bool _gameEnded = false;
  int? _matchWinner;

  // Match-wide MPR numerator / denominator, per player.
  final List<int> _matchMarks = [0, 0];
  final List<int> _roundsPlayed = [0, 0];

  // Transient "it's X's turn" banner shown briefly when the turn auto-switches.
  String? _turnBannerName;
  Timer? _turnBannerTimer;

  // ── Current visit — the "my" side of _state is the active player ──
  late CricketState _state;
  late CricketState _visitStart;
  List<_CricketDart> _currentRoundThrows = [];
  List<CricketDartEffect> _effects = [];
  int _dartsThrown = 0;
  bool _isWin = false;
  bool _winDialogShowing = false;

  LocalMatchConfig get _config => widget.config;
  int get _opponent => 1 - _activePlayer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WakelockPlus.enable();
    OrientationUtils.allowAll();
    _state = CricketState(scoreMode: _config.cricketScoreMode);
    _visitStart = _state.clone();
    autoScoringService = AutoScoringService();
    autoScoringService!.telemetrySessionOf = () => ('local', null);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await initCameraAndAI();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _turnBannerTimer?.cancel();
    disposeCameraAndAI();
    // Same deferral contract as the online verdict flush — solo modes have
    // no verdict, the screen teardown is their "match over".
    DatasetCaptureService.flush();
    WakelockPlus.disable();
    OrientationUtils.portraitOnly();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      stopAiCapture();
      cameraService?.pause();
    } else if (state == AppLifecycleState.resumed) {
      cameraService?.resume();
      // Not under the win dialog either — the leg is waiting on a human.
      if (autoScoringEnabled &&
          !aiManuallyDisabled &&
          !_gameEnded &&
          !_isWin) {
        startAiCapture();
      }
    }
  }

  @override
  void onCameraAiReady() {
    if (autoScoringService?.modelLoaded == true) {
      _showTurnBanner(_config.nameOf(_activePlayer));
    }
  }

  double? _mprOf(int player) => _roundsPlayed[player] > 0
      ? _matchMarks[player] / _roundsPlayed[player]
      : null;

  // ── Visit ──────────────────────────────────────────────────────────────────

  @override
  void onAiAutoConfirm() => _confirmRound();

  @override
  void onAiDartDetected(int slotIndex, DartScore dartScore) {
    if (!mounted || _gameEnded) return;
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
    _promptIfWon();
  }

  /// Replays the visit on top of the visit-start snapshot, so dart edits and
  /// refined detections stay consistent (same pattern as the bot screen).
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

  /// A closing visit stops the AI and asks the thrower to confirm the leg.
  void _promptIfWon() {
    if (!_isWin) return;
    stopAiCapture();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _showWinDialog();
    });
  }

  /// Rolls the visit into the thrower's match-wide MPR counters.
  void _commitVisit() {
    _roundsPlayed[_activePlayer]++;
    for (final e in _effects) {
      _matchMarks[_activePlayer] += e.marksApplied;
    }
  }

  /// Finalise the active player's visit and pass to the opponent automatically.
  /// No interstitial — the phone stays mounted; the AI scores the next player.
  void _confirmRound() {
    if (_gameEnded) return;
    if (_isWin) {
      _showWinDialog();
      return;
    }
    stopAiCapture();
    _commitVisit();
    DartSoundService.playTurnFinished();
    _state = _state.flipped();
    _switchToPlayer(_opponent);
  }

  /// Hands the board to [next] and resumes auto-scoring for them — hands-free.
  /// [_state] must already be oriented to [next] (flipped, or a fresh leg).
  void _switchToPlayer(int next) {
    setState(() {
      _activePlayer = next;
      _visitStart = _state.clone();
      _currentRoundThrows = [];
      _effects = [];
      _dartsThrown = 0;
      _isWin = false;
      aiManuallyDisabled = false;
      aiPausedForEdit = false;
    });
    autoScoringService?.resetTurn();
    startAiCapture();
    DartSoundService.playYourTurn();
    _showTurnBanner(_config.nameOf(next));
  }

  void _showTurnBanner(String name) {
    _turnBannerTimer?.cancel();
    setState(() => _turnBannerName = name);
    _turnBannerTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _turnBannerName = null);
    });
  }

  // ── Legs & match end ───────────────────────────────────────────────────────

  void _handleLegWon() {
    final winner = _activePlayer;
    stopAiCapture();
    _commitVisit();
    DartSoundService.playWin();
    setState(() => _legsWon[winner]++);

    if (_legsWon[winner] >= _config.legsToWin) {
      setState(() {
        _gameEnded = true;
        _matchWinner = winner;
      });
    } else {
      _startNextLeg();
    }
  }

  void _startNextLeg() {
    // The player who didn't start the previous leg throws first.
    _legStarter = 1 - _legStarter;
    _legNumber++;
    _state = CricketState(scoreMode: _config.cricketScoreMode);
    _switchToPlayer(_legStarter);
  }

  void _rematch() {
    setState(() {
      _gameEnded = false;
      _matchWinner = null;
      _legsWon[0] = 0;
      _legsWon[1] = 0;
      _matchMarks[0] = 0;
      _matchMarks[1] = 0;
      _roundsPlayed[0] = 0;
      _roundsPlayed[1] = 0;
      _legNumber = 1;
      _legStarter = 0;
      _state = CricketState(scoreMode: _config.cricketScoreMode);
    });
    _switchToPlayer(0);
  }

  // ── Dialogs ────────────────────────────────────────────────────────────────

  void _showWinDialog() {
    if (_winDialogShowing || !mounted) return;
    _winDialogShowing = true;
    final l10n = AppLocalizations.of(context);
    showGameDialog<void>(
      context,
      accent: AppTheme.success,
      icon: Icons.emoji_events_outlined,
      title: l10n.cricketAllClosedTitle,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.localCricketAllClosedBody(_config.nameOf(_activePlayer)),
              style:
                  AppTheme.bodyMedium.copyWith(color: AppTheme.textPrimary)),
          const SizedBox(height: 6),
          Text(l10n.isThisCorrect, style: AppTheme.caption),
        ],
      ),
      actionsBuilder: (ctx) => [
        OutlinedButton(
          onPressed: () {
            _winDialogShowing = false;
            Navigator.pop(ctx);
            setState(() {
              aiPausedForEdit = true;
              _currentRoundThrows.clear();
            });
            _recalculate(); // empties the visit → clears _isWin
            autoScoringService?.stopCapture();
            for (int i = 0; i < 3; i++) {
              autoScoringService?.clearDart(i);
            }
          },
          child: Text(dsSentence(l10n.editDarts)),
        ),
        ElevatedButton(
          onPressed: () {
            _winDialogShowing = false;
            Navigator.pop(ctx);
            _handleLegWon();
          },
          style: gameFilledButtonStyle(AppTheme.success),
          child: Text(dsSentence(l10n.confirmWin)),
        ),
      ],
    ).then((_) => _winDialogShowing = false);
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_gameEnded) return _buildEndView();

    final safeTop = MediaQuery.of(context).padding.top;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldPop = await showLeaveLocalMatchDialog(context);
        if (shouldPop && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: Stack(
          children: [
            if (autoScoringLoading)
              const LocalMatchLoadingView()
            else
              _buildTurnView(),
            if (_turnBannerName != null)
              LocalTurnBanner(
                name: _turnBannerName!,
                safeTop: safeTop,
                player: _activePlayer,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTurnView() {
    final l10n = AppLocalizations.of(context);
    return AutoScoreGameView(
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
      // Thrower on the blue side (2026-08-19 unified header convention) —
      // the state is flipped on every hand-over so "my" is the active player.
      scorePanel: CricketScoreTable(
        state: _state,
        myName: _config.nameOf(_activePlayer),
        opponentName: _config.nameOf(_opponent),
        seriesTitle: _config.bestOf > 1
            ? 'BO${_config.bestOf} · ${l10n.legNumber(_legNumber)}'
            : null,
        myLegs: _legsWon[_activePlayer],
        opponentLegs: _legsWon[_opponent],
        myTurn: true,
        myMpr: _mprOf(_activePlayer),
        oppMpr: _mprOf(_opponent),
        rowHeight: 22,
      ),
      visitTotalText: cricketVisitTotalText(l10n, _effects),
      chipSubtitle: (i, _) => cricketChipSubtitle(
        l10n,
        i < _effects.length ? _effects[i] : null,
      ),
      localCameraPreview: !switchingCamera &&
              cameraService?.controller != null &&
              cameraService!.isInitialized
          ? LocalCameraPreview(controller: cameraService!.controller!)
          : null,
      onBack: () async {
        final shouldLeave = await showLeaveLocalMatchDialog(context);
        if (shouldLeave && mounted) Navigator.of(context).pop();
      },
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
            _currentRoundThrows.add(_CricketDart(0, ScoreMultiplier.single));
          }
          _currentRoundThrows.add(_CricketDart(base, mul));
        }
        _recalculate();
        if (_isWin) {
          _promptIfWon();
        } else {
          startAiCapture();
        }
      },
      // The edit modal stops capture so detections can't overwrite the manual
      // correction. Restart it even when the edit was cancelled (no onEditDart
      // then) — otherwise the AI stays dead for the rest of the visit.
      onEditModalClosed: () {
        if (!_isWin) startAiCapture();
      },
      onToggleAi: autoScoringService?.modelLoaded == true ? toggleAi : null,
      aiEnabled: !aiManuallyDisabled,
    );
  }

  Widget _buildEndView() {
    final l10n = AppLocalizations.of(context);
    return LocalMatchEndView(
      config: _config,
      winner: _matchWinner ?? 0,
      legsWon: _legsWon,
      stats: [
        // Player 1 blue, player 2 rose — the identity they carried all match.
        for (var p = 0; p < 2; p++)
          LocalMatchStatRow(
            label: _config.nameOf(p),
            value: _mprOf(p) == null
                ? '—'
                : l10n.mprShort(_mprOf(p)!.toStringAsFixed(2)),
            color: localPlayerTextColor(p),
            icon: Icons.timeline_rounded,
          ),
      ],
      onRematch: _rematch,
      onBack: () => Navigator.of(context).pop(),
    );
  }
}
