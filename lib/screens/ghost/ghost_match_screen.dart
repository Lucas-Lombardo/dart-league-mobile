import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/auth_provider.dart';
import '../../providers/game_provider.dart' show ScoreMultiplier;
import '../../services/auto_scoring_service.dart';
import '../../services/camera_frame_service.dart';
import '../../services/dart_scoring_service.dart';
import '../../services/dataset_capture_service.dart';
import '../../services/replay_buffer_service.dart';
import '../../utils/app_theme.dart';
import '../../utils/dart_caller_service.dart';
import '../../utils/dart_sound_service.dart';
import '../../utils/game_system_ui.dart';
import '../../utils/haptic_service.dart';
import '../../utils/orientation_utils.dart';
import '../../utils/rank_utils.dart';
import '../../utils/score_converter.dart';
import '../../utils/storage_service.dart';
import '../../widgets/auto_score_display.dart';
import '../../widgets/design_system.dart';
import '../../widgets/game_turn_ui.dart';
import '../../widgets/local_camera_preview.dart';
import '../../widgets/progression/progression_widgets.dart';
import '../../widgets/virtual_dartboard.dart';
import '../game/leg_end_view.dart';
import '../game/match_end_view.dart';
import '../placement/bot_camera_ai_mixin.dart';
import '../progression/xp_summary_panel.dart';
import 'ghost_models.dart';
import 'ghost_proof_uploader.dart';
import 'ghost_replay.dart';
import 'ghost_service.dart';
import 'ghost_widgets.dart';

/// The ghost match (mockup FantomeMatch). The live player throws with the
/// camera and the AI, exactly like the bot screens; each visit goes to the
/// server, which scores it, plays the ghost's answer and decides the legs.
/// The ghost's real darts are then replayed at their real place and pace.
///
/// Nothing here decides a result: the screen only shows what the server
/// returned. The camera films the player's turns (replay ring, retained
/// under the match id); the video is sent only if the server asks for it.
class GhostMatchScreen extends StatefulWidget {
  final GhostMatchState initial;
  const GhostMatchScreen({super.key, required this.initial});

  @override
  State<GhostMatchScreen> createState() => _GhostMatchScreenState();
}

class _GhostMatchScreenState extends State<GhostMatchScreen>
    with WidgetsBindingObserver, BotCameraAiMixin {
  late GhostMatchState _match;
  late final DateTime _startedAt = DateTime.now();

  // The live player's visit in progress (scored locally for the dialogs; the
  // server re-scores it).
  final List<_Throw> _throws = [];
  int _scoreBeforeRound = 501;
  int _myScore = 501;
  bool _isBust = false;
  bool _isWin = false;
  bool _bustDialogShowing = false;
  bool _winDialogShowing = false;

  // Sending.
  bool _sending = false;
  bool _sendFailed = false;
  List<GhostPostedDart>? _pendingDarts;
  int _pendingLeg = 0;
  int _pendingIndex = 0;

  // Ghost turn (replay).
  bool _ghostTurn = false;
  GhostVisit? _ghostVisit;
  int _ghostDartsShown = 0;
  int _ghostScoreShown = 501;
  GhostReplayController? _replay;

  // Header figures (decoupled from _match while a replay catches up).
  int _shownLegsMe = 0;
  int _shownLegsGhost = 0;
  int _shownLeg = 0;

  // Leg end.
  bool _showingLegEnd = false;
  bool _lastLegWon = false;
  int _legEndSecondsLeft = 0;
  Timer? _legEndTimer;

  // End.
  GhostEnd? _end;
  bool _proofUploading = false;
  bool? _proofSent;
  bool _leaving = false;

  // Averages, from the visits seen on this screen.
  final List<int> _myVisitScores = [];
  final List<int> _ghostVisitScores = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WakelockPlus.enable();
    OrientationUtils.allowAll();
    GameSystemUi.enter();
    _applyServerState(widget.initial, resetLocal: true);
    if (widget.initial.end != null) {
      _end = widget.initial.end;
    }
    autoScoringService = AutoScoringService();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_end != null) return;
      await initCameraAndAI();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _replay?.cancel();
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
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      stopAiCapture();
      cameraService?.pause(releaseCamera: state == AppLifecycleState.inactive ? false : null);
    } else if (state == AppLifecycleState.resumed) {
      final camera = cameraService;
      camera?.resume().then((_) {
        if (mounted && identical(cameraService, camera)) setState(() {});
      });
      if (_isPlayerTurn) startAiCapture();
    }
  }

  bool get _isPlayerTurn =>
      _end == null && !_ghostTurn && !_showingLegEnd && !_sending && !_sendFailed && autoScoringEnabled;

  // ─── Camera: the bot screens' init, with the replay ring recording ──────

  /// Same as [BotCameraAiMixin.initCameraAndAI], plus the replay ring and
  /// match-proof retention: the ghost match is filmed like a ranked one.
  @override
  Future<void> initCameraAndAI() async {
    if (kIsWeb || !AutoScoringService.isSupported || !mounted) return;
    setState(() {
      autoScoringEnabled = true;
      autoScoringLoading = true;
    });
    try {
      final camera = CameraFrameService();
      await camera.initialize(replayRing: true);
      if (!mounted) {
        await camera.dispose();
        return;
      }
      if (!camera.isInitialized) {
        await camera.dispose();
        if (mounted) setState(() => autoScoringLoading = false);
        return;
      }
      cameraService = camera;
      autoScoringService?.onCaptureActiveChanged = camera.setAiActive;
      if (ReplayBufferService.armed) {
        await GhostProofUploader.beginRetention(_match.id);
        ReplayBufferService.setMyTurn(true);
      }
      try {
        final minZoom = await camera.getMinZoomLevel();
        final maxZoom = await camera.getMaxZoomLevel();
        final clamped = (await StorageService.getCameraZoom()).clamp(minZoom, maxZoom);
        await camera.setZoomLevel(clamped);
        if (mounted) {
          setState(() {
            cameraMinZoom = minZoom;
            cameraMaxZoom = maxZoom;
            cameraZoom = clamped;
          });
        }
      } catch (_) {}
      await autoScoringService!.loadModel();
      if (!mounted) return;
      setState(() => autoScoringLoading = false);
      if (autoScoringService!.modelLoaded && _isPlayerTurn) startAiCapture();
    } catch (_) {
      if (mounted) setState(() => autoScoringLoading = false);
    }
  }

  // ─── Server state ───────────────────────────────────────────────────────

  void _applyServerState(GhostMatchState m, {bool resetLocal = false}) {
    _match = m;
    _shownLegsMe = m.playerLegsWon;
    _shownLegsGhost = m.ghostLegsWon;
    _shownLeg = m.currentLeg;
    _ghostScoreShown = m.ghostRemaining;
    if (resetLocal) {
      _throws.clear();
      _scoreBeforeRound = m.playerRemaining;
      _myScore = m.playerRemaining;
      _isBust = false;
      _isWin = false;
    }
  }

  // ─── AI hooks ───────────────────────────────────────────────────────────

  @override
  void onAiAutoConfirm() => _confirmRound();

  @override
  void onAiDartDetected(int slotIndex, DartScore dartScore) {
    if (!mounted || !_isPlayerTurn) return;
    final (base, mul) = dartScoreToBackend(dartScore);
    HapticService.mediumImpact();
    DartSoundService.playDartHit(base, mul);
    if (slotIndex < _throws.length) {
      setState(() => _throws[slotIndex] = _Throw(base, mul, aiReading: dartScore, t: _throws[slotIndex].t));
      _recalculateScore();
    } else {
      _throwDart(base, mul, aiReading: dartScore);
    }
    _maybeAskVerdict();
  }

  void _maybeAskVerdict() {
    if (_isWin) {
      stopAiCapture();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showWinDialog();
      });
    } else if (_isBust) {
      stopAiCapture();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showBustDialog();
      });
    }
  }

  // ─── Local scoring of the visit in progress ─────────────────────────────

  static int _points(int base, ScoreMultiplier m) => switch (m) {
        ScoreMultiplier.single => base,
        ScoreMultiplier.double => base * 2,
        ScoreMultiplier.triple => base * 3,
      };

  void _throwDart(int base, ScoreMultiplier mul, {DartScore? aiReading}) {
    if (_throws.length >= 3 || _isBust || _isWin || !_isPlayerTurn) return;
    final next = _myScore - _points(base, mul);
    final t = _Throw(base, mul, aiReading: aiReading, t: DateTime.now().millisecondsSinceEpoch);
    if (next < 0 || next == 1 || (next == 0 && mul != ScoreMultiplier.double)) {
      setState(() {
        _isBust = true;
        _throws.add(t);
      });
      DartSoundService.playBust();
      return;
    }
    setState(() {
      _myScore = next;
      _throws.add(t);
      if (next == 0) _isWin = true;
    });
    if (_throws.length == 3 && !_isWin) DartCallerService.callScore(_scoreBeforeRound - _myScore);
  }

  void _recalculateScore() {
    var score = _scoreBeforeRound;
    var bust = false;
    var win = false;
    for (final d in _throws) {
      final next = score - _points(d.baseScore, d.multiplier);
      if (next < 0 || next == 1 || (next == 0 && d.multiplier != ScoreMultiplier.double)) {
        bust = true;
        break;
      }
      score = next;
      if (score == 0) {
        win = true;
        break;
      }
    }
    setState(() {
      _myScore = bust ? _scoreBeforeRound : score;
      _isBust = bust;
      _isWin = win;
    });
  }

  void _resetVisit() {
    setState(() {
      _throws.clear();
      _isBust = false;
      _isWin = false;
      _myScore = _scoreBeforeRound;
      aiPausedForEdit = true;
    });
    autoScoringService?.stopCapture();
    for (var i = 0; i < 3; i++) {
      autoScoringService?.clearDart(i);
    }
  }

  // ─── Sending the visit ──────────────────────────────────────────────────

  void _confirmRound() {
    if (!_isPlayerTurn) return;
    stopAiCapture();
    final darts = _throws.map((t) => t.toPosted()).toList();
    final roundScore = _isBust ? 0 : _scoreBeforeRound - _myScore;
    if (_throws.isNotEmpty && _throws.length < 3 && !_isBust && !_isWin) {
      DartCallerService.callScore(roundScore);
    }
    DartSoundService.playTurnFinished();
    _myVisitScores.add(roundScore);
    _pendingDarts = darts;
    _pendingLeg = _match.currentLeg;
    _pendingIndex = _match.nextVisitIndex;
    _sendVisit();
  }

  Future<void> _sendVisit() async {
    final darts = _pendingDarts;
    if (darts == null) return;
    setState(() {
      _sending = true;
      _sendFailed = false;
    });
    ReplayBufferService.setMyTurn(false);
    try {
      final result = await GhostService.postVisit(
        matchId: _match.id,
        leg: _pendingLeg,
        index: _pendingIndex,
        darts: darts,
      );
      if (!mounted) return;
      _pendingDarts = null;
      _onVisitResult(result);
    } catch (e) {
      if (!mounted) return;
      final s = e.toString();
      if (s.contains('OUT_OF_SYNC') || s.contains('GHOST_OVER') || s.contains('409')) {
        // The server knows better: take its state.
        try {
          final fresh = await GhostService.match(_match.id);
          if (!mounted) return;
          _pendingDarts = null;
          _resyncTo(fresh);
          return;
        } catch (_) {}
      }
      setState(() {
        _sending = false;
        _sendFailed = true;
      });
    }
  }

  void _resyncTo(GhostMatchState fresh) {
    setState(() {
      _sending = false;
      _sendFailed = false;
      _applyServerState(fresh, resetLocal: true);
    });
    if (fresh.end != null) {
      _finish(fresh.end!);
    } else {
      _startPlayerTurn();
    }
  }

  void _onVisitResult(GhostVisitResult r) {
    if (r.duplicate) {
      _resyncTo(r.match);
      return;
    }
    final previousLeg = _match.currentLeg;
    final previousGhostScore = _ghostScoreShown;
    final legEnded = r.legEndedIndex != null;
    final thisLeg = r.ghostVisits.where((v) => v.leg == previousLeg).toList();
    final nextLeg = r.ghostVisits.where((v) => v.leg != previousLeg).toList();
    setState(() {
      _sending = false;
      _match = r.match;
      // My visit is settled on the server's figure (the leg's, even when the
      // answer already carries the next leg).
      _scoreBeforeRound = legEnded ? (r.visitRemaining ?? 0) : r.match.playerRemaining;
      _myScore = _scoreBeforeRound;
      _throws.clear();
      _isBust = false;
      _isWin = false;
      _ghostScoreShown = previousGhostScore;
    });

    void afterLegEnd() {
      if (!mounted) return;
      if (r.match.end != null) {
        _finish(r.match.end!);
        return;
      }
      setState(() {
        _shownLeg = r.match.currentLeg;
        _scoreBeforeRound = r.match.playerRemaining;
        _myScore = r.match.playerRemaining;
        _ghostScoreShown = 501;
      });
      _playGhost(nextLeg, then: _startPlayerTurn);
    }

    void afterThisLeg() {
      if (!mounted) return;
      if (legEnded) {
        setState(() {
          _shownLegsMe = r.match.playerLegsWon;
          _shownLegsGhost = r.match.ghostLegsWon;
        });
        if (r.match.end != null) {
          _finish(r.match.end!);
        } else {
          _showLegEnd(won: r.legWonByPlayer ?? false, then: afterLegEnd);
        }
        return;
      }
      _startPlayerTurn();
    }

    _playGhost(thisLeg, then: afterThisLeg);
  }

  // ─── Ghost replay ───────────────────────────────────────────────────────

  void _playGhost(List<GhostVisit> visits, {required VoidCallback then}) {
    if (visits.isEmpty) {
      then();
      return;
    }
    _replay?.cancel();
    setState(() {
      _ghostTurn = true;
      _ghostVisit = visits.first;
      _ghostDartsShown = 0;
    });
    _replay = GhostReplayController(
      visits: visits,
      onDart: (vi, shown) {
        if (!mounted) return;
        final visit = visits[vi];
        final dart = visit.darts[shown - 1];
        setState(() {
          _ghostVisit = visit;
          _ghostDartsShown = shown;
        });
        if (!dart.skipped) {
          final (base, mul) = _parse(dart.notation);
          DartSoundService.playDartHit(base, mul);
        }
      },
      onVisitDone: (vi) {
        if (!mounted) return;
        final visit = visits[vi];
        _ghostVisitScores.add(visit.busted ? 0 : visit.score);
        DartCallerService.callScore(visit.busted ? 0 : visit.score);
        setState(() {
          _ghostScoreShown = visit.remaining;
          if (vi + 1 < visits.length) {
            _ghostVisit = visits[vi + 1];
            _ghostDartsShown = 0;
          }
        });
      },
      onFinished: () {
        if (!mounted) return;
        setState(() => _ghostTurn = false);
        then();
      },
    )..start();
  }

  static (int, ScoreMultiplier) _parse(String notation) {
    final base = int.tryParse(notation.length > 1 ? notation.substring(1) : '') ?? 0;
    final mul = switch (notation.isNotEmpty ? notation[0] : 'S') {
      'D' => ScoreMultiplier.double,
      'T' => ScoreMultiplier.triple,
      _ => ScoreMultiplier.single,
    };
    return (base, mul);
  }

  void _startPlayerTurn() {
    if (!mounted || _end != null) return;
    setState(() {
      _ghostTurn = false;
      _ghostVisit = null;
      _ghostDartsShown = 0;
      aiManuallyDisabled = false;
      aiPausedForEdit = false;
    });
    ReplayBufferService.setMyTurn(true);
    autoScoringService?.resetTurn();
    for (var i = 0; i < 3; i++) {
      autoScoringService?.clearDart(i);
    }
    startAiCapture();
    DartSoundService.playYourTurn();
    DartCallerService.callCheckout(_myScore);
  }

  // ─── Leg end / match end ────────────────────────────────────────────────

  void _showLegEnd({required bool won, required VoidCallback then}) {
    stopAiCapture();
    if (!won) DartSoundService.playLose();
    setState(() {
      _showingLegEnd = true;
      _lastLegWon = won;
      _legEndSecondsLeft = 4;
    });
    _legEndTimer?.cancel();
    _legEndTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_legEndSecondsLeft <= 1) {
        t.cancel();
        setState(() => _showingLegEnd = false);
        then();
      } else {
        setState(() => _legEndSecondsLeft--);
      }
    });
  }

  Future<void> _finish(GhostEnd end) async {
    stopAiCapture();
    _replay?.cancel();
    setState(() {
      _end = end;
      _ghostTurn = false;
      _sending = false;
      _showingLegEnd = false;
    });
    if (end.won) {
      DartSoundService.playWin();
    } else {
      DartSoundService.playLose();
    }
    // The rating moved on the server: refresh the profile.
    unawaited(context.read<AuthProvider>().checkAuthStatus());
    // Stop filming; the retained turns stay on disk for the proof.
    if (ReplayBufferService.armed) await ReplayBufferService.stop();
    if (end.proofRequired) {
      if (!mounted) return;
      setState(() => _proofUploading = true);
      final ok = await GhostProofUploader.upload(_match.id);
      if (mounted) {
        setState(() {
          _proofUploading = false;
          _proofSent = ok;
        });
      }
    } else {
      unawaited(GhostProofUploader.discard(_match.id));
    }
  }

  Future<bool> _confirmLeave() async {
    if (_end != null) return true;
    final l10n = AppLocalizations.of(context);
    final committed = _match.playerVisits.isNotEmpty || _match.currentLeg > 0 || _myVisitScores.isNotEmpty;
    final leave = await showGameDialog<bool>(
      context,
      accent: AppTheme.error,
      icon: Icons.logout_rounded,
      title: l10n.leaveMatch,
      content: Text(
        !committed
            ? l10n.ghostLeaveFree
            : _match.eloEligible
                ? l10n.ghostLeaveWarning
                : l10n.ghostLeaveWarningNoElo,
        style: AppTheme.bodyMedium,
      ),
      actionsBuilder: (ctx) => [
        OutlinedButton(onPressed: () => Navigator.pop(ctx, false), child: Text(dsSentence(l10n.stay))),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: gameFilledButtonStyle(AppTheme.error),
          child: Text(dsSentence(l10n.leave)),
        ),
      ],
    );
    if (leave != true || !mounted) return false;
    setState(() => _leaving = true);
    final result = await GhostService.abandon(_match.id);
    if (!mounted) return false;
    setState(() => _leaving = false);
    final end = result?.end;
    if (result != null && result.status == 'abandoned' && end != null) {
      _match = result;
      await _finish(end);
      return false;
    }
    if (ReplayBufferService.armed) await ReplayBufferService.stop();
    unawaited(GhostProofUploader.discard(_match.id));
    return true;
  }

  // ─── Dialogs ────────────────────────────────────────────────────────────

  void _showBustDialog() {
    if (_bustDialogShowing || !mounted) return;
    _bustDialogShowing = true;
    final l10n = AppLocalizations.of(context);
    showGameDialog(
      context,
      accent: AppTheme.error,
      icon: Icons.error_outline_rounded,
      title: l10n.bust,
      prominentActions: true,
      content: GameBustDialogContent(
        reason: l10n.scoreBusted,
        remaining: _scoreBeforeRound,
        visitTotal: visitPoints(_throws.map((d) => d.notation)),
      ),
      actionsBuilder: (ctx) => [
        OutlinedButton(
          onPressed: () {
            _bustDialogShowing = false;
            Navigator.pop(ctx);
            _resetVisit();
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
    _winDialogShowing = true;
    final l10n = AppLocalizations.of(context);
    final notation = _throws.isNotEmpty ? _throws.last.notation : '—';
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
            _resetVisit();
          },
          style: gameNeutralOutlineButtonStyle(),
          child: Text(dsSentence(l10n.editDarts)),
        ),
        ElevatedButton(
          onPressed: () {
            _winDialogShowing = false;
            Navigator.pop(ctx);
            _confirmRound();
          },
          style: gameFilledButtonStyle(AppTheme.success),
          child: Text(dsSentence(l10n.confirmWin)),
        ),
      ],
    ).then((_) => _winDialogShowing = false);
  }

  // ─── Build ──────────────────────────────────────────────────────────────

  double? _avg(List<int> scores) =>
      scores.isEmpty ? null : scores.fold<int>(0, (a, b) => a + b) / scores.length;

  String _seriesTitle(AppLocalizations l10n) =>
      'BO${_match.bestOf} · ${l10n.legNumber(_shownLeg + 1)}';

  Widget _header({required bool myTurn, Widget? leading}) {
    final auth = context.watch<AuthProvider>();
    final me = auth.currentUser;
    return TurnScoreHeader(
      myName: me?.username ?? 'You',
      opponentName: _match.ghost.username,
      myScore: _myScore,
      opponentScore: _ghostScoreShown,
      myAverage: _avg(_myVisitScores),
      opponentAverage: _avg(_ghostVisitScores),
      seriesTitle: _seriesTitle(AppLocalizations.of(context)),
      myLegs: _shownLegsMe,
      opponentLegs: _shownLegsGhost,
      myTurn: myTurn,
      showBadges: !myTurn,
      leading: leading,
      myAvatar: me == null ? null : FramedAvatar(rank: me.rank, cosmetics: me.cosmetics, size: 20),
      opponentAvatar: FramedAvatar(
        rank: rankFromElo(_match.ghost.elo),
        cosmetics: _match.ghost.cosmetics,
        size: 20,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final end = _end;
    if (end != null) return _buildEnd(end);

    if (_showingLegEnd) {
      return LegEndView(
        wonLeg: _lastLegWon,
        myLegsWon: _shownLegsMe,
        opponentLegsWon: _shownLegsGhost,
        legsNeeded: _match.legsToWin,
        secondsLeft: _legEndSecondsLeft,
        onAttemptPop: _confirmLeave,
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final pop = await _confirmLeave();
        if (pop && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: Stack(
          children: [
            if (autoScoringLoading && !_ghostTurn && !_sending)
              _buildLoading()
            else if (_isPlayerTurn && autoScoringService != null)
              _buildPlayerTurn()
            else
              _buildGhostTurn(),
            if (_leaving)
              const ColoredBox(
                color: Color(0x880F172A),
                child: Center(child: CircularProgressIndicator(color: AppTheme.primary)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return Container(
      color: AppTheme.background,
      alignment: Alignment.center,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 2),
        ),
        const SizedBox(height: 14),
        Text(
          dsSentence(AppLocalizations.of(context).loadingAutoScoring),
          style: AppTheme.caption.copyWith(fontSize: 13),
        ),
      ]),
    );
  }

  Widget _buildPlayerTurn() {
    final ai = autoScoringService!;
    return AutoScoreGameView(
      scoringService: ai,
      onConfirm: () {
        HapticService.heavyImpact();
        if (_isWin) {
          _showWinDialog();
        } else if (_isBust) {
          _showBustDialog();
        } else {
          _confirmRound();
        }
      },
      onEndRoundEarly: () {
        HapticService.heavyImpact();
        _confirmRound();
      },
      pendingConfirmation: _isBust || _isWin,
      header: _header(myTurn: true),
      localCameraPreview: !switchingCamera && cameraService?.controller != null && cameraService!.isInitialized
          ? LocalCameraPreview(controller: cameraService!.controller!)
          : null,
      onSwitchCamera: switchCamera,
      onZoomIn: zoomIn,
      onZoomOut: zoomOut,
      currentZoom: cameraZoom,
      minZoom: cameraMinZoom,
      maxZoom: cameraMaxZoom,
      captureButton: const _RecPill(),
      onEditDart: (index, dartScore) {
        final (base, mul) = dartScoreToBackend(dartScore);
        if (index < _throws.length) {
          // Keep what the AI read for that slot: the pair is the trust signal.
          _throws[index] = _Throw(base, mul, aiReading: _throws[index].aiReading, t: _throws[index].t);
        } else {
          while (_throws.length < index) {
            _throws.add(_Throw(0, ScoreMultiplier.single, t: DateTime.now().millisecondsSinceEpoch));
          }
          _throws.add(_Throw(base, mul, t: DateTime.now().millisecondsSinceEpoch));
        }
        _recalculateScore();
        if (_isWin || _isBust) {
          _maybeAskVerdict();
        } else {
          startAiCapture();
        }
      },
      onEditModalClosed: () {
        if (_isPlayerTurn && !_isWin && !_isBust) startAiCapture();
      },
      // Camera and AI are mandatory in a ghost match, like in ranked.
      onToggleAi: null,
      aiEnabled: true,
      onBack: () async {
        final pop = await _confirmLeave();
        if (pop && mounted) Navigator.of(context).pop();
      },
    );
  }

  Widget _buildGhostTurn() {
    final l10n = AppLocalizations.of(context);
    final safeTop = MediaQuery.of(context).padding.top;
    final safeBottom = MediaQuery.of(context).padding.bottom;
    final header = _header(
      myTurn: false,
      leading: GameControlButton(
        icon: Icons.arrow_back_ios_new_rounded,
        onTap: () async {
          final pop = await _confirmLeave();
          if (pop && mounted) Navigator.of(context).pop();
        },
      ),
    );
    final visit = _ghostVisit;
    final shown = visit == null ? <GhostDart>[] : visit.darts.take(_ghostDartsShown).toList();
    final total = shown.where((d) => !d.skipped).fold<int>(0, (s, d) => s + notationPoints(d.notation));

    return Container(
      color: AppTheme.gameBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: safeTop + 6),
          header,
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SizedBox(height: gameCameraHeight(context), child: _buildBoardPanel(shown, total, visit)),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  VisitLabelRow(
                    label: l10n.visitOf(_match.ghost.username),
                    total: total,
                    color: AppTheme.opponentPinkBright,
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 74,
                    child: Row(
                      children: List.generate(3, (i) {
                        final notation = i < shown.length ? shown[i].notation : null;
                        return Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(left: i == 0 ? 0 : 10),
                            child: DartVisitChip(
                              notation: notation,
                              accent: AppTheme.surfaceLight,
                              highlighted: notation != null && i == shown.length - 1,
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(12, 8, 12, safeBottom + 10),
            child: GhostRecBanner(eloEligible: _match.eloEligible),
          ),
        ],
      ),
    );
  }

  Widget _buildBoardPanel(List<GhostDart> shown, int total, GhostVisit? visit) {
    final l10n = AppLocalizations.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(color: AppTheme.gamePanelEmpty),
          LayoutBuilder(builder: (context, c) {
            final size = math.max(120.0, math.min(c.maxWidth - 40, c.maxHeight - 70));
            return Center(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: VirtualDartboard(
                  throws: shown.map((d) => d.skipped ? 'S0' : d.notation).toList(),
                  impacts: shown.map(ghostImpactUnit).toList(),
                  size: size,
                  flightId: _match.ghost.cosmetics?.flight,
                ),
              ),
            );
          }),
          if (_sending || _sendFailed)
            Center(child: _buildSendState(l10n))
          else if (visit != null && shown.isNotEmpty)
            Positioned(
              top: 8,
              right: 12,
              child: Text(
                (visit.busted && shown.length == visit.darts.length)
                    ? l10n.bust.toUpperCase()
                    : '+$total',
                style: const TextStyle(
                  color: AppTheme.opponentPinkBright,
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          Positioned(
            top: 10,
            left: 10,
            child: GameChip(text: l10n.ghostBadge, color: AppTheme.opponentPinkBright),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 10,
            child: Text(
              l10n.ghostPanelCaption(ghostShortDate(context, _match.ghost.playedAt)),
              textAlign: TextAlign.center,
              maxLines: 2,
              style: AppTheme.caption.copyWith(fontSize: 12, fontWeight: FontWeight.w700),
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
        ],
      ),
    );
  }

  Widget _buildSendState(AppLocalizations l10n) {
    if (_sendFailed) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(AppTheme.radiusRow)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(l10n.ghostSendFailed, style: AppTheme.rowTitle),
          const SizedBox(height: 10),
          ElevatedButton(onPressed: _sendVisit, child: Text(dsSentence(l10n.ghostRetry))),
        ]),
      );
    }
    return Column(mainAxisSize: MainAxisSize.min, children: [
      const GhostIcon(size: 40, color: AppTheme.opponentPink),
      const SizedBox(height: 12),
      Text(
        dsSentence(l10n.ghostThrowing),
        style: const TextStyle(color: AppTheme.opponentPinkBright, fontSize: 13, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 14),
      const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(color: AppTheme.opponentPink, strokeWidth: 2),
      ),
    ]);
  }

  Widget _buildEnd(GhostEnd end) {
    final l10n = AppLocalizations.of(context);
    final me = context.watch<AuthProvider>().currentUser;
    final String eloValue;
    final String eloCaption;
    Color eloColor = AppTheme.textPrimary;
    if (end.eloApplied && end.eloDelta != null) {
      eloValue = ghostSignedElo(end.eloDelta!);
      eloCaption = l10n.ghostEloCaption(me?.elo ?? 0);
      eloColor = end.eloDelta! >= 0 ? AppTheme.success : AppTheme.opponentPinkBright;
    } else if (end.eloHeld) {
      eloValue = end.eloDelta == null ? '—' : ghostSignedElo(end.eloDelta!);
      eloCaption = l10n.ghostEloHeldCaption;
      eloColor = AppTheme.textSecondary;
    } else {
      eloValue = '—';
      eloCaption = l10n.ghostEloNoneCaption;
    }
    final preCard = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          _EndTile(value: eloValue, label: eloCaption, color: eloColor),
          const SizedBox(width: 8),
          _EndTile(value: ghostAverage(context, end.average), label: l10n.ghostAverageLabel),
        ]),
        if (end.eloHeld || end.proofRequired) ...[
          const SizedBox(height: 10),
          Text(
            _proofUploading
                ? l10n.ghostProofSending
                : _proofSent == true
                    ? l10n.ghostProofSent
                    : _proofSent == false
                        ? l10n.ghostProofFailed
                        : l10n.ghostEloHeld,
            style: AppTheme.caption.copyWith(fontSize: 13),
          ),
        ] else if (!end.eloApplied) ...[
          const SizedBox(height: 10),
          Text(l10n.ghostEloNone, style: AppTheme.caption.copyWith(fontSize: 13)),
        ],
        const SizedBox(height: 14),
        XpSummaryPanel(since: _startedAt, expectRefId: _match.id),
        const SizedBox(height: 14),
      ],
    );
    return MatchEndView(
      didWin: end.won,
      title: end.won ? l10n.victory : l10n.defeat,
      subtitle: l10n.ghostVs(_match.ghost.username),
      badgeText: l10n.ghostBadge,
      scoreLine: '${end.playerLegsWon} – ${end.ghostLegsWon}',
      scoreCaption: l10n.bestOfN(_match.bestOf),
      preCard: preCard,
      // No « play another ghost »: a ghost is only offered by the ranked
      // queue after 5 min without an opponent (CONTRACT §14.12).
      panel: SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(dsSentence(l10n.ghostHome)),
        ),
      ),
    );
  }
}

class _EndTile extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  const _EndTile({required this.value, required this.label, this.color = AppTheme.textPrimary});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(AppTheme.radiusRow)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: color,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 2),
            Text(label, maxLines: 2, style: AppTheme.caption.copyWith(fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

/// "REC" in the camera panel: the turn is being filmed (FantomeMatch).
class _RecPill extends StatelessWidget {
  const _RecPill();

  @override
  Widget build(BuildContext context) {
    if (!ReplayBufferService.armed) return const SizedBox.shrink();
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppTheme.gameBackground.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 7,
          height: 7,
          decoration: const BoxDecoration(color: AppTheme.opponentPink, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text('REC', style: AppTheme.labelSmall.copyWith(color: AppTheme.opponentPinkBright, letterSpacing: 1)),
      ]),
    );
  }
}

/// One dart of the live player's visit.
class _Throw {
  final int baseScore;
  final ScoreMultiplier multiplier;

  /// What the model read for this dart, kept after a correction: the pair is
  /// the trust signal. Null for a dart typed by hand.
  final DartScore? aiReading;

  /// Phone wall clock when the dart registered (epoch ms).
  final int? t;

  _Throw(this.baseScore, this.multiplier, {this.aiReading, this.t});

  String get notation => switch (multiplier) {
        ScoreMultiplier.single => 'S$baseScore',
        ScoreMultiplier.double => 'D$baseScore',
        ScoreMultiplier.triple => 'T$baseScore',
      };

  static String _aiNotation(DartScore score) => switch (score.ring) {
        'triple' => 'T${score.segment}',
        'double' => 'D${score.segment}',
        'double_bull' => 'D25',
        'single_bull' => 'S25',
        'miss' => 'S0',
        _ => 'S${score.segment}',
      };

  GhostPostedDart toPosted() {
    final ai = aiReading;
    return GhostPostedDart(
      notation: notation,
      aiNotation: ai == null ? null : _aiNotation(ai),
      telemetry: ai?.telemetry ?? const {},
      t: t,
    );
  }
}
