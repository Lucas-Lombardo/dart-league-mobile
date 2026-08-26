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
import 'logic/checkout_routes.dart';
import 'logic/training_strategy.dart';
import 'training_end_screen.dart';

enum _VisionPhase { composing, result }

/// "Vision checkout" quiz — camera-free. The player is given a remaining
/// score and a dart budget, composes a finish on the segment keypad, and the
/// answer auto-validates as soon as the route is decided (finish, bust or out
/// of darts). Any mathematically valid double-out is accepted; the book route
/// is shown afterwards.
class CheckoutVisionScreen extends StatefulWidget {
  const CheckoutVisionScreen({super.key});

  @override
  State<CheckoutVisionScreen> createState() => _CheckoutVisionScreenState();
}

class _CheckoutVisionScreenState extends State<CheckoutVisionScreen> {
  static const int kQuestions = 10;

  final _rng = Random();

  late CheckoutQuestion _question;
  int _questionNumber = 1;
  _VisionPhase _phase = _VisionPhase.composing;
  final List<TrainingDart> _darts = [];
  ScoreMultiplier _multiplier = ScoreMultiplier.single;

  final Stopwatch _stopwatch = Stopwatch();
  Timer? _ticker;

  bool _resultSuccess = false;
  String? _resultReason;
  bool _resultIsBook = false;
  List<List<TrainingDart>> _alternatives = const [];

  int _correct = 0;
  int _streak = 0;
  int _bestStreak = 0;
  int _bookHits = 0;
  final List<int> _answerTimesMs = [];
  final List<Map<String, dynamic>> _history = [];

  bool _finished = false;
  bool _isSubmitting = false;
  String? _submitError;

  @override
  void initState() {
    super.initState();
    _question = pickCheckoutQuestion(_rng);
    _startTiming();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _startTiming() {
    _stopwatch
      ..reset()
      ..start();
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted && _phase == _VisionPhase.composing) setState(() {});
    });
  }

  // --- Question flow -------------------------------------------------------

  void _addDart(TrainingDart d) {
    if (_phase != _VisionPhase.composing) return;
    HapticService.mediumImpact();
    if (d.baseScore > 0) {
      DartSoundService.playDartHit(d.baseScore, d.multiplier);
    }
    setState(() => _darts.add(d));
    final v = validateCheckoutRoute(_question.target, _darts);
    if (v.success ||
        v.failReason != 'short' ||
        _darts.length >= _question.dartsAllowed) {
      _finishQuestion(v);
      return;
    }
  }

  void _removeLastDart() {
    if (_phase != _VisionPhase.composing || _darts.isEmpty) return;
    HapticService.lightImpact();
    setState(() => _darts.removeLast());
  }

  void _finishQuestion(CheckoutValidation v) {
    _stopwatch.stop();
    _ticker?.cancel();
    final elapsed = _stopwatch.elapsedMilliseconds;
    _answerTimesMs.add(elapsed);

    final playedNotations = _darts.map((d) => d.notation).toList();
    final recommended = recommendedCheckoutRoutes(
      _question.target,
      _question.dartsAllowed,
    );
    bool samePlayed(List<TrainingDart> r) =>
        _sameRoute(playedNotations, r.map((d) => d.notation).toList());
    final isBook = v.success && recommended.any(samePlayed);

    if (v.success) {
      _correct++;
      _streak++;
      _bestStreak = max(_bestStreak, _streak);
      if (isBook) _bookHits++;
      HapticService.mediumImpact();
      DartSoundService.playTurnFinished();
    } else {
      _streak = 0;
      HapticService.heavyImpact();
      DartSoundService.playBust();
    }

    final alternatives = recommended
        .where((r) => !samePlayed(r))
        .take(3)
        .toList();

    _history.add({
      'target': _question.target,
      'dartsAllowed': _question.dartsAllowed,
      'played': playedNotations,
      'success': v.success,
      'failReason': v.failReason,
      'book': isBook,
      'ms': elapsed,
    });

    setState(() {
      _phase = _VisionPhase.result;
      _resultSuccess = v.success;
      _resultReason = v.failReason;
      _resultIsBook = isBook;
      _alternatives = alternatives;
    });
  }

  bool _sameRoute(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _nextQuestion() {
    HapticService.mediumImpact();
    if (_questionNumber >= kQuestions) {
      setState(() => _finished = true);
      _submitResult();
      return;
    }
    setState(() {
      _questionNumber++;
      _question = pickCheckoutQuestion(_rng);
      _phase = _VisionPhase.composing;
      _darts.clear();
      _multiplier = ScoreMultiplier.single;
      _alternatives = const [];
    });
    _startTiming();
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
        type: TrainingType.checkoutVision,
        score: _accuracy,
        dartsThrown: 0,
        details: {
          'correct': _correct,
          'total': kQuestions,
          'accuracy': _accuracy,
          'averageAnswerMs': _averageMs,
          'bestStreak': _bestStreak,
          'bookRoutes': _bookHits,
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
    setState(() {
      _questionNumber = 1;
      _correct = 0;
      _streak = 0;
      _bestStreak = 0;
      _bookHits = 0;
      _answerTimesMs.clear();
      _history.clear();
      _finished = false;
      _isSubmitting = false;
      _submitError = null;
      _question = pickCheckoutQuestion(_rng);
      _phase = _VisionPhase.composing;
      _darts.clear();
      _multiplier = ScoreMultiplier.single;
      _alternatives = const [];
    });
    _startTiming();
  }

  String _formatSeconds(int ms) => '${(ms / 1000).toStringAsFixed(1)} s';

  String _dartLabel(TrainingDart d) {
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
        type: TrainingType.checkoutVision,
        score: _accuracy,
        dartsThrown: 0,
        showDartsThrown: false,
        completed: true,
        scoreLabel: l10n.trainingQuizAccuracyLabel,
        subtitle:
            '${l10n.trainingQuizTimeAvgLabel} ${_formatSeconds(_averageMs)} · '
            '${l10n.trainingCheckoutVisionBookCount(_bookHits)}',
        isSubmitting: _isSubmitting,
        submitError: _submitError,
        onPlayAgain: _resetAndReplay,
        onRetrySubmit: _submitError != null ? _submitResult : null,
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(l10n.trainingCheckoutVision),
        actions: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.13),
                borderRadius: BorderRadius.circular(99),
                border: Border.all(
                  color: AppTheme.primary.withValues(alpha: 0.4),
                ),
              ),
              child: Text(
                _formatSeconds(_stopwatch.elapsedMilliseconds),
                style: const TextStyle(
                  color: AppTheme.primary,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ],
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
            const SizedBox(height: 4),
            Expanded(
              child: _phase == _VisionPhase.composing
                  ? _buildComposing(l10n)
                  : _buildResult(l10n),
            ),
          ],
        ),
      ),
    );
  }

  // --- Composing view ------------------------------------------------------

  Widget _buildComposing(AppLocalizations l10n) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppTheme.surfaceLight.withValues(alpha: 0.5),
              ),
            ),
            child: Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.trainingRemaining.toUpperCase(),
                      style: AppTheme.labelLarge.copyWith(
                        color: AppTheme.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                    Text(
                      '${_question.target}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 44,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    l10n.trainingCheckoutVisionPrompt(_question.dartsAllowed),
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              for (var i = 0; i < _question.dartsAllowed; i++) ...[
                _dartSlot(i < _darts.length ? _darts[i] : null),
                const SizedBox(width: 10),
              ],
              if (_darts.isNotEmpty)
                IconButton(
                  onPressed: _removeLastDart,
                  icon: const Icon(
                    Icons.backspace_outlined,
                    color: AppTheme.textSecondary,
                    size: 22,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          _specialRow(l10n),
          const SizedBox(height: 10),
          _multiplierTabs(l10n),
          const SizedBox(height: 10),
          _numberGrid(),
        ],
      ),
    );
  }

  Widget _dartSlot(TrainingDart? d) {
    if (d == null) {
      return Container(
        width: 68,
        height: 54,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppTheme.textSecondary.withValues(alpha: 0.5),
            width: 1.5,
            style: BorderStyle.solid,
          ),
        ),
        alignment: Alignment.center,
        child: const Text(
          '?',
          style: TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
    }
    return Container(
      width: 68,
      height: 54,
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primary, width: 1.5),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            _dartLabel(d),
            style: const TextStyle(
              color: AppTheme.primary,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              height: 1.1,
            ),
          ),
          Text(
            '${d.points}',
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _specialRow(AppLocalizations l10n) {
    Widget button(String label, String value, Color color, TrainingDart dart) {
      return Expanded(
        child: Material(
          color: color.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _addDart(dart),
            child: Container(
              height: 52,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: color.withValues(alpha: 0.5),
                  width: 2,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: color,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                    ),
                  ),
                  Text(
                    value,
                    style: TextStyle(
                      color: color.withValues(alpha: 0.7),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        button(
          l10n.missButton,
          '0',
          AppTheme.error,
          const TrainingDart(0, ScoreMultiplier.single),
        ),
        const SizedBox(width: 10),
        button(
          l10n.singleBull,
          '25',
          AppTheme.accent,
          const TrainingDart(25, ScoreMultiplier.single),
        ),
        const SizedBox(width: 10),
        button(
          l10n.doubleBull,
          '50',
          AppTheme.success,
          const TrainingDart(25, ScoreMultiplier.double),
        ),
      ],
    );
  }

  Widget _multiplierTabs(AppLocalizations l10n) {
    Widget tab(ScoreMultiplier value, String label, String sub, Color color) {
      final selected = _multiplier == value;
      return Expanded(
        child: GestureDetector(
          onTap: () {
            HapticService.lightImpact();
            setState(() => _multiplier = value);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: 44,
            decoration: BoxDecoration(
              color: selected ? color.withValues(alpha: 0.18) : null,
              borderRadius: BorderRadius.circular(11),
              border: selected
                  ? Border.all(color: color.withValues(alpha: 0.6), width: 2)
                  : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: selected ? color : AppTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
                Text(
                  sub,
                  style: TextStyle(
                    color: selected
                        ? color.withValues(alpha: 0.7)
                        : AppTheme.textSecondary,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppTheme.gameBackground,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          tab(ScoreMultiplier.single, l10n.singleUpper, '×1', Colors.white),
          const SizedBox(width: 4),
          tab(ScoreMultiplier.double, l10n.doubleUpper, '×2', AppTheme.success),
          const SizedBox(width: 4),
          tab(ScoreMultiplier.triple, l10n.tripleUpper, '×3', AppTheme.error),
        ],
      ),
    );
  }

  Widget _numberGrid() {
    final Color valueColor;
    switch (_multiplier) {
      case ScoreMultiplier.single:
        valueColor = Colors.white;
        break;
      case ScoreMultiplier.double:
        valueColor = AppTheme.success;
        break;
      case ScoreMultiplier.triple:
        valueColor = AppTheme.error;
        break;
    }
    final factor = _multiplier == ScoreMultiplier.triple
        ? 3
        : _multiplier == ScoreMultiplier.double
        ? 2
        : 1;
    return GridView.count(
      crossAxisCount: 5,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1.28,
      children: [
        for (var n = 20; n >= 1; n--)
          Material(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _addDart(TrainingDart(n, _multiplier)),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppTheme.surfaceLight.withValues(alpha: 0.8),
                    width: 1.5,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '$n',
                      style: TextStyle(
                        color: valueColor,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                      ),
                    ),
                    if (factor > 1)
                      Text(
                        '=${n * factor}',
                        style: TextStyle(
                          color: valueColor.withValues(alpha: 0.7),
                          fontSize: 9,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  // --- Result view ---------------------------------------------------------

  Widget _buildResult(AppLocalizations l10n) {
    final color = _resultSuccess ? AppTheme.success : AppTheme.error;

    final String? reasonText;
    switch (_resultReason) {
      case 'below_zero':
        reasonText = l10n.trainingBustBelowZero;
        break;
      case 'not_double_finish':
        reasonText = l10n.trainingBustNotDouble;
        break;
      case 'left_one':
        reasonText = l10n.trainingBustLeftOne;
        break;
      case 'short':
        reasonText = l10n.trainingCheckoutVisionShort;
        break;
      default:
        reasonText = null;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: color.withValues(alpha: 0.6),
                    width: 2,
                  ),
                ),
                child: Icon(
                  _resultSuccess ? Icons.check : Icons.close,
                  color: color,
                  size: 40,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _resultSuccess
                    ? l10n.trainingCheckoutVisionOut
                    : l10n.trainingCheckoutVisionMissedTitle,
                style: TextStyle(
                  color: color,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (!_resultSuccess && reasonText != null) ...[
                const SizedBox(height: 4),
                Text(
                  reasonText,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              _routeChips(_darts, color),
              if (_resultIsBook) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(
                      color: AppTheme.accent.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.star, size: 14, color: AppTheme.accent),
                      const SizedBox(width: 6),
                      Text(
                        l10n.trainingCheckoutVisionBookRoute.toUpperCase(),
                        style: const TextStyle(
                          color: AppTheme.accent,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 18),
          if (_alternatives.isNotEmpty)
            _routesCard(
              (_resultSuccess
                      ? l10n.trainingCheckoutVisionOtherRoutes
                      : l10n.trainingCheckoutVisionRecommendedRoutes)
                  .toUpperCase(),
              _alternatives,
            ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _nextQuestion,
            style: AppTheme.primaryButtonStyle,
            child: Text(
              _questionNumber >= kQuestions
                  ? l10n.trainingComplete
                  : l10n.trainingQuizNext,
            ),
          ),
        ],
      ),
    );
  }

  Widget _routeChips(List<TrainingDart> route, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < route.length; i++) ...[
          if (i > 0) ...[
            const SizedBox(width: 8),
            const Icon(
              Icons.arrow_forward,
              size: 16,
              color: AppTheme.textSecondary,
            ),
            const SizedBox(width: 8),
          ],
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: color.withValues(alpha: 0.6),
                width: 1.5,
              ),
            ),
            child: Text(
              _dartLabel(route[i]),
              style: TextStyle(
                color: color,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _routesCard(String title, List<List<TrainingDart>> routes) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.surfaceLight.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTheme.labelLarge.copyWith(
              color: AppTheme.textSecondary,
              fontSize: 11,
            ),
          ),
          for (var i = 0; i < routes.length; i++) ...[
            if (i > 0)
              Divider(
                height: 16,
                color: AppTheme.surfaceLight.withValues(alpha: 0.65),
              )
            else
              const SizedBox(height: 10),
            Row(
              children: [
                Text(
                  routes[i].map(_dartLabel).join(' · '),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(
                  routes[i].map((d) => '${d.points}').join(' + '),
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
