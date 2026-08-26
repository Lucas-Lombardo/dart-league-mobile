import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/training.dart';
import '../../providers/game_provider.dart' show ScoreMultiplier;
import '../../services/training_service.dart';
import '../../utils/app_theme.dart';
import '../../utils/dart_sound_service.dart';
import '../../utils/haptic_service.dart';
import '../../widgets/virtual_dartboard.dart';
import 'logic/quick_count_questions.dart';
import 'logic/training_strategy.dart';
import 'training_end_screen.dart';

enum _QuizPhase { landing, answering, feedback }

/// "Compte rapide" quiz — the first camera-free drill. The starting score is
/// shown first, then a visit lands dart by dart on the virtual board (one
/// beat apart); one beat after the third dart the clock starts and the player
/// enters the remaining score on a numeric keypad.
class QuickCountScreen extends StatefulWidget {
  const QuickCountScreen({super.key});

  @override
  State<QuickCountScreen> createState() => _QuickCountScreenState();
}

class _QuickCountScreenState extends State<QuickCountScreen>
    with SingleTickerProviderStateMixin {
  static const int kQuestions = 10;
  static const Duration kAnswerTime = Duration(seconds: 30);
  /// Beat between the score announcement, each landing dart and the prompt.
  static const Duration kDartInterval = Duration(seconds: 2);
  static const Duration kFeedbackTime = Duration(milliseconds: 1100);

  final _rng = Random();

  late QuickCountQuestion _question;
  int _questionNumber = 1;
  _QuizPhase _phase = _QuizPhase.landing;
  int _dartsShown = 0;
  String _input = '';

  int _correct = 0;
  int _streak = 0;
  int _bestStreak = 0;
  bool _lastCorrect = false;
  bool _lastTimedOut = false;
  final List<int> _answerTimesMs = [];
  final List<Map<String, dynamic>> _history = [];

  late final AnimationController _timerController;
  DateTime? _answerStartedAt;
  Timer? _phaseTimer;

  bool _finished = false;
  bool _isSubmitting = false;
  String? _submitError;

  @override
  void initState() {
    super.initState();
    _timerController = AnimationController(vsync: this, duration: kAnswerTime)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) _onTimeout();
      });
    _question = generateQuickCountQuestion(_rng);
    _scheduleNextDart();
  }

  @override
  void dispose() {
    _phaseTimer?.cancel();
    _timerController.dispose();
    super.dispose();
  }

  // --- Question flow -------------------------------------------------------

  void _scheduleNextDart() {
    _phaseTimer = Timer(kDartInterval, () {
      if (!mounted) return;
      final dart = _question.visit[_dartsShown];
      setState(() => _dartsShown++);
      HapticService.lightImpact();
      if (dart.baseScore > 0) {
        DartSoundService.playDartHit(dart.baseScore, dart.multiplier);
      }
      if (_dartsShown < 3) {
        _scheduleNextDart();
      } else {
        _phaseTimer = Timer(kDartInterval, () {
          if (!mounted) return;
          setState(() => _phase = _QuizPhase.answering);
          _answerStartedAt = DateTime.now();
          _timerController.forward(from: 0);
        });
      }
    });
  }

  void _onTimeout() {
    if (_phase != _QuizPhase.answering) return;
    _resolveAnswer(given: null, timedOut: true);
  }

  void _validate() {
    if (_input.isEmpty || _phase != _QuizPhase.answering) return;
    _resolveAnswer(given: int.tryParse(_input), timedOut: false);
  }

  void _resolveAnswer({required int? given, required bool timedOut}) {
    _timerController.stop();
    final elapsed = timedOut
        ? kAnswerTime.inMilliseconds
        : DateTime.now().difference(_answerStartedAt!).inMilliseconds;
    final correct = !timedOut && given == _question.answer;

    _answerTimesMs.add(elapsed);
    if (correct) {
      _correct++;
      _streak++;
      _bestStreak = max(_bestStreak, _streak);
      HapticService.mediumImpact();
    } else {
      _streak = 0;
      HapticService.heavyImpact();
      DartSoundService.playBust();
    }
    _history.add({
      'start': _question.startScore,
      'visit': _question.visit.map((d) => d.notation).toList(),
      'expected': _question.answer,
      'given': given,
      'ms': elapsed,
      'correct': correct,
    });

    setState(() {
      _phase = _QuizPhase.feedback;
      _lastCorrect = correct;
      _lastTimedOut = timedOut;
    });
    _phaseTimer = Timer(kFeedbackTime, () {
      if (!mounted) return;
      if (_questionNumber >= kQuestions) {
        setState(() => _finished = true);
        _submitResult();
      } else {
        setState(() {
          _questionNumber++;
          _question = generateQuickCountQuestion(_rng);
          _phase = _QuizPhase.landing;
          _dartsShown = 0;
          _input = '';
        });
        _scheduleNextDart();
      }
    });
  }

  // --- Result --------------------------------------------------------------

  int get _accuracy => (_correct / kQuestions * 100).round();

  int get _averageMs => _answerTimesMs.isEmpty
      ? 0
      : (_answerTimesMs.reduce((a, b) => a + b) / _answerTimesMs.length)
            .round();

  Future<void> _submitResult() async {
    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });
    try {
      await TrainingService.submit(
        type: TrainingType.quickCount,
        score: _accuracy,
        dartsThrown: 0,
        details: {
          'correct': _correct,
          'total': kQuestions,
          'accuracy': _accuracy,
          'averageAnswerMs': _averageMs,
          'bestStreak': _bestStreak,
          'history': _history,
        },
      );
      if (mounted) setState(() => _isSubmitting = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _submitError = e.toString().replaceAll('Exception: ', '');
        });
      }
    }
  }

  void _resetAndReplay() {
    _phaseTimer?.cancel();
    _timerController.reset();
    setState(() {
      _questionNumber = 1;
      _correct = 0;
      _streak = 0;
      _bestStreak = 0;
      _answerTimesMs.clear();
      _history.clear();
      _finished = false;
      _isSubmitting = false;
      _submitError = null;
      _question = generateQuickCountQuestion(_rng);
      _phase = _QuizPhase.landing;
      _dartsShown = 0;
      _input = '';
    });
    _scheduleNextDart();
  }

  String _formatSeconds(int ms) => '${(ms / 1000).toStringAsFixed(1)} s';

  // --- Notation helpers ----------------------------------------------------

  /// [VirtualDartboard] parses spectator notations ('S25'/'D25' for bull),
  /// not the TrainingDart dialect ('B'/'DB').
  String _boardNotation(TrainingDart d) {
    if (d.baseScore == 25) {
      return d.multiplier == ScoreMultiplier.double ? 'D25' : 'S25';
    }
    return d.notation;
  }

  String _chipLabel(TrainingDart d) {
    if (d.baseScore == 0) return '0';
    if (d.baseScore == 25) {
      return d.multiplier == ScoreMultiplier.double ? 'Bull' : '25';
    }
    switch (d.multiplier) {
      case ScoreMultiplier.single:
        return '${d.baseScore}';
      case ScoreMultiplier.double:
        return 'D${d.baseScore}';
      case ScoreMultiplier.triple:
        return 'T${d.baseScore}';
    }
  }

  Color _chipColor(TrainingDart d) {
    if (d.baseScore == 0) return AppTheme.textSecondary;
    if (d.baseScore == 25) return AppTheme.accent;
    switch (d.multiplier) {
      case ScoreMultiplier.single:
        return AppTheme.textPrimary;
      case ScoreMultiplier.double:
        return AppTheme.success;
      case ScoreMultiplier.triple:
        return AppTheme.error;
    }
  }

  // --- UI ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (_finished) {
      return TrainingEndScreen(
        type: TrainingType.quickCount,
        score: _accuracy,
        dartsThrown: 0,
        showDartsThrown: false,
        completed: true,
        scoreLabel: l10n.trainingQuizAccuracyLabel,
        subtitle:
            '${l10n.trainingQuizTimeAvgLabel} ${_formatSeconds(_averageMs)} · '
            '${l10n.trainingQuizStreakLabel} $_bestStreak',
        isSubmitting: _isSubmitting,
        submitError: _submitError,
        onPlayAgain: _resetAndReplay,
        onRetrySubmit: _submitError != null ? _submitResult : null,
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(l10n.trainingQuickCount),
        actions: [if (_streak > 1) _streakChip()],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Text(
              l10n.trainingQuizQuestionProgress(_questionNumber, kQuestions),
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
              ),
            ),
            Expanded(
              child: _phase == _QuizPhase.landing
                  ? _buildLanding(l10n)
                  : _buildAnswering(l10n),
            ),
          ],
        ),
      ),
    );
  }

  Widget _streakChip() {
    return Center(
      child: Container(
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppTheme.accent.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: AppTheme.accent.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.local_fire_department,
              size: 15,
              color: AppTheme.accent,
            ),
            const SizedBox(width: 4),
            Text(
              '$_streak',
              style: const TextStyle(
                color: AppTheme.accent,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLanding(AppLocalizations l10n) {
    final boardSize = min(MediaQuery.of(context).size.width - 80, 300.0);
    final visible = _question.visit.take(_dartsShown).toList();
    return Column(
      children: [
        const SizedBox(height: 8),
        Text(
          l10n.trainingQuizYouAreOn.toUpperCase(),
          style: AppTheme.labelLarge.copyWith(color: AppTheme.textSecondary),
        ),
        Text(
          '${_question.startScore}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 52,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        VirtualDartboard(
          throws: visible.map(_boardNotation).toList(),
          size: boardSize,
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 40,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final d in visible) ...[
                _dartChip(d),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
        const Spacer(),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Text(
            l10n.trainingQuickCountWatch,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _dartChip(TrainingDart d, {bool compact = false}) {
    final color = _chipColor(d);
    final neutral = color == AppTheme.textPrimary;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 14,
        vertical: compact ? 5 : 8,
      ),
      decoration: BoxDecoration(
        color: neutral
            ? Colors.white.withValues(alpha: 0.06)
            : color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: neutral
              ? AppTheme.surfaceLight.withValues(alpha: 0.8)
              : color.withValues(alpha: 0.5),
          width: 1.5,
        ),
      ),
      child: Text(
        _chipLabel(d),
        style: TextStyle(
          color: neutral ? AppTheme.textPrimary : color,
          fontSize: compact ? 14 : 17,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildAnswering(AppLocalizations l10n) {
    final feedback = _phase == _QuizPhase.feedback;
    return Column(
      children: [
        const SizedBox(height: 6),
        _timerRing(),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${_question.startScore}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 10),
            const Icon(Icons.remove, size: 18, color: AppTheme.textSecondary),
            const SizedBox(width: 10),
            for (final d in _question.visit) ...[
              _dartChip(d, compact: true),
              const SizedBox(width: 6),
            ],
          ],
        ),
        const SizedBox(height: 10),
        if (feedback)
          Expanded(child: _buildFeedback(l10n))
        else ...[
          Text(
            l10n.trainingQuizScorePrompt.toUpperCase(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 40),
            height: 56,
            decoration: BoxDecoration(
              color: AppTheme.gamePanelEmpty,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppTheme.primary.withValues(alpha: 0.5),
                width: 1.5,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              _input.isEmpty ? ' ' : _input,
              style: const TextStyle(
                color: AppTheme.primary,
                fontSize: 30,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const Spacer(),
          _keypad(),
        ],
      ],
    );
  }

  Widget _timerRing() {
    return AnimatedBuilder(
      animation: _timerController,
      builder: (context, _) {
        final remaining = 1 - _timerController.value;
        final Color color;
        if (remaining > 0.4) {
          color = AppTheme.primary;
        } else if (remaining > 0.15) {
          color = AppTheme.accent;
        } else {
          color = AppTheme.error;
        }
        final secondsLeft =
            kAnswerTime.inMilliseconds * remaining / 1000;
        return SizedBox(
          width: 104,
          height: 104,
          child: CustomPaint(
            painter: _TimerRingPainter(remaining: remaining, color: color),
            child: Center(
              child: Text(
                secondsLeft.toStringAsFixed(1),
                style: TextStyle(
                  color: _phase == _QuizPhase.feedback
                      ? AppTheme.textSecondary
                      : Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFeedback(AppLocalizations l10n) {
    final color = _lastCorrect ? AppTheme.success : AppTheme.error;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          _lastCorrect ? Icons.check_circle_outline : Icons.cancel_outlined,
          size: 64,
          color: color,
        ),
        const SizedBox(height: 12),
        if (_lastTimedOut) ...[
          Text(
            l10n.trainingQuizTimeUp,
            style: TextStyle(
              color: color,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
        ],
        Text(
          _lastCorrect
              ? '${_question.answer}'
              : l10n.trainingQuizItWas(_question.answer),
          style: TextStyle(
            color: color,
            fontSize: _lastCorrect ? 44 : 24,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  Widget _keypad() {
    final keys = [
      '1', '2', '3',
      '4', '5', '6',
      '7', '8', '9',
      'back', '0', 'ok',
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.85,
        children: [for (final k in keys) _keypadButton(k)],
      ),
    );
  }

  Widget _keypadButton(String key) {
    final isBack = key == 'back';
    final isOk = key == 'ok';
    final Color bg;
    final Color border;
    if (isOk) {
      bg = AppTheme.primary;
      border = AppTheme.primary;
    } else if (isBack) {
      bg = AppTheme.error.withValues(alpha: 0.12);
      border = AppTheme.error.withValues(alpha: 0.4);
    } else {
      bg = AppTheme.surface;
      border = AppTheme.surfaceLight.withValues(alpha: 0.5);
    }
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          HapticService.lightImpact();
          if (isBack) {
            if (_input.isNotEmpty) {
              setState(
                () => _input = _input.substring(0, _input.length - 1),
              );
            }
          } else if (isOk) {
            _validate();
          } else if (_input.length < 3) {
            setState(() => _input += key);
          }
        },
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: border),
          ),
          alignment: Alignment.center,
          child: isBack
              ? const Icon(
                  Icons.backspace_outlined,
                  color: AppTheme.error,
                  size: 24,
                )
              : isOk
              ? const Icon(Icons.check, color: Colors.white, size: 26)
              : Text(
                  key,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
        ),
      ),
    );
  }
}

class _TimerRingPainter extends CustomPainter {
  final double remaining;
  final Color color;

  _TimerRingPainter({required this.remaining, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 5;
    final track = Paint()
      ..color = AppTheme.surface
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9;
    canvas.drawCircle(center, radius, track);
    if (remaining <= 0) return;
    final arc = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi / 2,
      2 * pi * remaining,
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(_TimerRingPainter oldDelegate) =>
      oldDelegate.remaining != remaining || oldDelegate.color != color;
}
