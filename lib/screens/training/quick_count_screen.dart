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
import '../../widgets/design_system.dart';
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

  /// "0:12" — whole seconds left on the answer clock.
  String _clock(int seconds) =>
      '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

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
      appBar: AppBar(title: Text(l10n.trainingQuickCount)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _QuizStatsRow(
                items: [
                  (
                    l10n.trainingQuizQuestionLabel,
                    '$_questionNumber / $kQuestions',
                  ),
                  (l10n.trainingQuizCorrectLabel, '$_correct'),
                  (l10n.trainingQuizStreakLabel, '$_streak'),
                ],
              ),
              const SizedBox(height: 14),
              Expanded(
                child: _phase == _QuizPhase.landing
                    ? _buildLanding(l10n)
                    : _buildAnswering(l10n),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The question card: "TU ES À" over the hero start score, plus either the
  /// landing hint or the visit that was just thrown.
  Widget _questionCard(AppLocalizations l10n, {required Widget footer}) {
    return DsCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Text(
            l10n.trainingQuizYouAreOn.toUpperCase(),
            style: AppTheme.labelSmall,
          ),
          const SizedBox(height: 8),
          Text('${_question.startScore}', style: _kHeroStyle),
          const SizedBox(height: 10),
          footer,
        ],
      ),
    );
  }

  Widget _buildLanding(AppLocalizations l10n) {
    final visible = _question.visit.take(_dartsShown).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _questionCard(
          l10n,
          footer: Text(
            l10n.trainingQuickCountWatch,
            textAlign: TextAlign.center,
            style: AppTheme.caption.copyWith(fontSize: 13),
          ),
        ),
        const SizedBox(height: 14),
        // The board takes whatever is left: full size on a tall phone, and
        // it simply shrinks on a short one instead of overflowing.
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = min(
                constraints.maxHeight,
                min(constraints.maxWidth, 280.0),
              );
              if (size < 40) return const SizedBox.shrink();
              return Center(
                child: VirtualDartboard(
                  throws: visible.map(_boardNotation).toList(),
                  size: size,
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 36,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < visible.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                _DartChip(label: _chipLabel(visible[i])),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAnswering(AppLocalizations l10n) {
    final feedback = _phase == _QuizPhase.feedback;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Centred in whatever the keypad leaves, and scrollable only on a
        // phone too short for card + clock + input; the keypad itself stays
        // pinned at the bottom, under the thumb.
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _questionCard(
                    l10n,
                    footer: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.remove_rounded,
                          size: 16,
                          color: AppTheme.textTertiary,
                        ),
                        const SizedBox(width: 8),
                        for (var i = 0; i < _question.visit.length; i++) ...[
                          if (i > 0) const SizedBox(width: 6),
                          _DartChip(
                            label: _chipLabel(_question.visit[i]),
                            compact: true,
                            onSurface: true,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  _timerBar(),
                  if (!feedback) ...[
                    const SizedBox(height: 14),
                    _inputDisplay(l10n),
                  ],
                ],
              ),
            ),
          ),
        ),
        if (feedback)
          Expanded(child: _buildFeedback(l10n))
        else ...[
          const SizedBox(height: 14),
          _keypad(l10n),
        ],
      ],
    );
  }

  /// 4 px clock hairline: primary, turning error under 20 %, with the
  /// seconds left as a caption.
  Widget _timerBar() {
    return AnimatedBuilder(
      animation: _timerController,
      builder: (context, _) {
        final remaining = 1 - _timerController.value;
        final urgent = remaining < 0.2;
        final secondsLeft = (kAnswerTime.inMilliseconds * remaining / 1000)
            .ceil();
        return Row(
          children: [
            Expanded(
              child: DsProgressBar(
                value: remaining,
                color: urgent ? AppTheme.error : AppTheme.primary,
                height: 4,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              _clock(secondsLeft),
              style: AppTheme.caption.copyWith(
                fontWeight: FontWeight.w700,
                color: urgent ? AppTheme.error : AppTheme.textSecondary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        );
      },
    );
  }

  /// The answer being typed: a surface field whose border lights up once a
  /// digit is in (the one place a coloured border expresses a state).
  Widget _inputDisplay(AppLocalizations l10n) {
    final empty = _input.isEmpty;
    return Container(
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        border: Border.all(
          color: empty ? AppTheme.border : AppTheme.primaryLight,
          width: empty ? 1 : 1.5,
        ),
      ),
      child: Text(
        empty ? l10n.trainingQuizScorePrompt : _input,
        style: empty
            ? const TextStyle(
                color: AppTheme.textTertiary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              )
            : const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 28,
                fontWeight: FontWeight.w800,
                height: 1,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
      ),
    );
  }

  Widget _buildFeedback(AppLocalizations l10n) {
    final color = _lastCorrect ? AppTheme.success : AppTheme.error;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.12),
              border: Border.all(color: color.withValues(alpha: 0.6), width: 2),
            ),
            child: Icon(
              _lastCorrect ? Icons.check_rounded : Icons.close_rounded,
              size: 28,
              color: color,
            ),
          ),
          const SizedBox(height: 14),
          if (_lastTimedOut) ...[
            Text(
              l10n.trainingQuizTimeUp,
              style: AppTheme.rowTitle.copyWith(color: color),
            ),
            const SizedBox(height: 6),
          ],
          Text(
            _lastCorrect
                ? '${_question.answer}'
                : l10n.trainingQuizItWas(_question.answer),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: color,
              fontSize: _lastCorrect ? 44 : 22,
              fontWeight: FontWeight.w800,
              height: 1,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _keypad(AppLocalizations l10n) {
    const keys = [
      '1',
      '2',
      '3',
      '4',
      '5',
      '6',
      '7',
      '8',
      '9',
      'back',
      '0',
      'ok',
    ];
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 2.0,
      children: [for (final k in keys) _keypadKey(l10n, k)],
    );
  }

  Widget _keypadKey(AppLocalizations l10n, String key) {
    if (key == 'ok') {
      // The one filled primary block of the screen.
      return ElevatedButton(
        onPressed: _input.isEmpty
            ? null
            : () {
                HapticService.lightImpact();
                _validate();
              },
        style: const ButtonStyle(
          padding: WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          ),
        ),
        child: Text(l10n.submit, maxLines: 1, overflow: TextOverflow.ellipsis),
      );
    }
    final isBack = key == 'back';
    return _PadKey(
      onTap: () {
        HapticService.lightImpact();
        if (isBack) {
          if (_input.isNotEmpty) {
            setState(() => _input = _input.substring(0, _input.length - 1));
          }
        } else if (_input.length < 3) {
          setState(() => _input += key);
        }
      },
      child: isBack
          ? const Icon(
              Icons.backspace_outlined,
              color: AppTheme.textSecondary,
              size: 22,
            )
          : Text(
              key,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w700,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
    );
  }
}

/// 56 / 800 tabular hero number of the question card.
const TextStyle _kHeroStyle = TextStyle(
  color: AppTheme.textPrimary,
  fontSize: 56,
  fontWeight: FontWeight.w800,
  letterSpacing: -1.5,
  height: 1,
  fontFeatures: [FontFeature.tabularFigures()],
);

/// Three columns of "LABEL / value": question progress, correct answers,
/// current streak.
class _QuizStatsRow extends StatelessWidget {
  final List<(String, String)> items;

  const _QuizStatsRow({required this.items});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final (label, value) in items)
          Expanded(
            child: Column(
              children: [
                // "Bonnes réponses" is wider than a third of a narrow
                // phone: shrink it rather than clip it.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label.toUpperCase(),
                    maxLines: 1,
                    style: AppTheme.labelSmall,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    height: 1,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// One dart of the visit ("T20", "D16", "Bull"): quiet chip, 15 / 700. On a
/// surface card it drops to the page background so it still reads as a chip.
class _DartChip extends StatelessWidget {
  final String label;
  final bool compact;
  final bool onSurface;

  const _DartChip({
    required this.label,
    this.compact = false,
    this.onSurface = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 14,
        vertical: compact ? 6 : 8,
      ),
      decoration: BoxDecoration(
        color: onSurface ? AppTheme.background : AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        border: Border.all(color: AppTheme.border),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: AppTheme.textPrimary,
          fontSize: compact ? 13 : 15,
          fontWeight: FontWeight.w700,
          height: 1.2,
        ),
      ),
    );
  }
}

/// Numeric pad key: surface, hairline, centred child.
class _PadKey extends StatelessWidget {
  final Widget child;
  final VoidCallback onTap;

  const _PadKey({required this.child, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        side: const BorderSide(color: AppTheme.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Center(child: child),
      ),
    );
  }
}
