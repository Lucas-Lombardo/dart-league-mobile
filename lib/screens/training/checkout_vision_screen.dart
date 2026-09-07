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
import 'logic/checkout_routes.dart';
import 'logic/training_strategy.dart';
import 'training_end_screen.dart';

enum _VisionPhase { composing, result }

/// "Vision checkout" quiz — camera-free, and the twin of the "Compte rapide"
/// screen: the same question card (group label, 56 / 800 hero number,
/// caption), the same three-column stat row and the same quiet keypad. The
/// player is given a remaining score and a dart budget, composes a finish on
/// the segment keypad, and the answer auto-validates as soon as the route is
/// decided (finish, bust or out of darts). Any mathematically valid
/// double-out is accepted; the book route is shown afterwards.
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
          // The clock runs on every question (it feeds "Temps moy." on the
          // end screen) — a quiet tabular caption, not a badge.
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                _formatSeconds(_stopwatch.elapsedMilliseconds),
                style: AppTheme.caption.copyWith(
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        ],
      ),
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
                child: _phase == _VisionPhase.composing
                    ? _buildComposing(l10n)
                    : _buildResult(l10n),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The question card: "RESTE" over the hero remaining score, and the dart
  /// budget as the caption.
  Widget _questionCard(AppLocalizations l10n) {
    return DsCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Text(
            l10n.trainingRemaining.toUpperCase(),
            style: AppTheme.labelSmall,
          ),
          const SizedBox(height: 8),
          Text('${_question.target}', style: _kHeroStyle),
          const SizedBox(height: 10),
          Text(
            l10n.trainingCheckoutVisionPrompt(_question.dartsAllowed),
            textAlign: TextAlign.center,
            style: AppTheme.caption.copyWith(fontSize: 13),
          ),
        ],
      ),
    );
  }

  // --- Composing view ------------------------------------------------------

  Widget _buildComposing(AppLocalizations l10n) {
    // Centred in the free height like the "Compte rapide" quiz, and
    // scrollable only on a phone too short for card + slots + keypad.
    return Center(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _questionCard(l10n),
            const SizedBox(height: 14),
            _slotsRow(),
            const SizedBox(height: 14),
            _specialRow(l10n),
            const SizedBox(height: 10),
            _multiplierTabs(l10n),
            const SizedBox(height: 10),
            _numberGrid(),
          ],
        ),
      ),
    );
  }

  /// The darts of the route being composed, plus the backspace.
  Widget _slotsRow() {
    return SizedBox(
      height: 54,
      child: Row(
        children: [
          for (var i = 0; i < _question.dartsAllowed; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            SizedBox(
              width: 84,
              child: _slot(i < _darts.length ? _darts[i] : null),
            ),
          ],
          const Spacer(),
          SizedBox(
            width: 54,
            child: _PadKey(
              onTap: _darts.isEmpty ? null : _removeLastDart,
              child: Icon(
                Icons.backspace_outlined,
                size: 20,
                color: _darts.isEmpty
                    ? AppTheme.textTertiary
                    : AppTheme.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _slot(TrainingDart? d) {
    if (d == null) {
      return Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusControl),
          border: Border.all(color: AppTheme.border),
        ),
        child: const Text(
          '—',
          style: TextStyle(
            color: AppTheme.textTertiary,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        border: Border.all(color: AppTheme.primaryLight),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            _dartLabel(d),
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${d.points}',
            style: AppTheme.caption.copyWith(fontSize: 11, height: 1),
          ),
        ],
      ),
    );
  }

  /// Miss, single bull and double bull — the three segments the number grid
  /// can't express.
  Widget _specialRow(AppLocalizations l10n) {
    Widget button(String label, String value, TrainingDart dart) {
      return Expanded(
        child: SizedBox(
          height: 52,
          child: _PadKey(
            onTap: () => _addDart(dart),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: AppTheme.caption.copyWith(
                    fontSize: 11,
                    height: 1,
                    color: AppTheme.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        button(
          dsSentence(l10n.missButton),
          '0',
          const TrainingDart(0, ScoreMultiplier.single),
        ),
        const SizedBox(width: 10),
        button(
          dsSentence(l10n.singleBull),
          '25',
          const TrainingDart(25, ScoreMultiplier.single),
        ),
        const SizedBox(width: 10),
        button(
          dsSentence(l10n.doubleBull),
          '50',
          const TrainingDart(25, ScoreMultiplier.double),
        ),
      ],
    );
  }

  /// Simple / Double / Triple: the system's segmented control (a quiet track,
  /// the selected segment on surfaceLight).
  Widget _multiplierTabs(AppLocalizations l10n) {
    Widget tab(ScoreMultiplier value, String label) {
      final selected = _multiplier == value;
      return Expanded(
        child: GestureDetector(
          onTap: () {
            HapticService.lightImpact();
            setState(() => _multiplier = value);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? AppTheme.surfaceLight : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: selected ? AppTheme.textPrimary : AppTheme.textSecondary,
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      height: 40,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          tab(ScoreMultiplier.single, dsSentence(l10n.singleUpper)),
          const SizedBox(width: 3),
          tab(ScoreMultiplier.double, dsSentence(l10n.doubleUpper)),
          const SizedBox(width: 3),
          tab(ScoreMultiplier.triple, dsSentence(l10n.tripleUpper)),
        ],
      ),
    );
  }

  Widget _numberGrid() {
    final factor = switch (_multiplier) {
      ScoreMultiplier.single => 1,
      ScoreMultiplier.double => 2,
      ScoreMultiplier.triple => 3,
    };
    return GridView.count(
      crossAxisCount: 5,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1.15,
      children: [
        for (var n = 20; n >= 1; n--)
          _PadKey(
            onTap: () => _addDart(TrainingDart(n, _multiplier)),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$n',
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                if (factor > 1) ...[
                  const SizedBox(height: 2),
                  Text(
                    '${n * factor}',
                    style: AppTheme.caption.copyWith(
                      fontSize: 11,
                      height: 1,
                      color: AppTheme.textTertiary,
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  // --- Result view ---------------------------------------------------------

  Widget _buildResult(AppLocalizations l10n) {
    final color = _resultSuccess ? AppTheme.success : AppTheme.error;

    final String? reasonText = switch (_resultReason) {
      'below_zero' => l10n.trainingBustBelowZero,
      'not_double_finish' => l10n.trainingBustNotDouble,
      'left_one' => l10n.trainingBustLeftOne,
      'short' => l10n.trainingCheckoutVisionShort,
      _ => null,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color.withValues(alpha: 0.12),
                      border: Border.all(
                        color: color.withValues(alpha: 0.6),
                        width: 2,
                      ),
                    ),
                    child: Icon(
                      _resultSuccess
                          ? Icons.check_rounded
                          : Icons.close_rounded,
                      color: color,
                      size: 28,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  dsSentence(
                    _resultSuccess
                        ? l10n.trainingCheckoutVisionOut
                        : l10n.trainingCheckoutVisionMissedTitle,
                  ),
                  textAlign: TextAlign.center,
                  style: AppTheme.displayMedium.copyWith(color: color),
                ),
                if (!_resultSuccess && reasonText != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    reasonText,
                    textAlign: TextAlign.center,
                    style: AppTheme.caption.copyWith(fontSize: 13),
                  ),
                ],
                const SizedBox(height: 14),
                _routeChips(_darts, color),
                if (_resultIsBook) ...[
                  const SizedBox(height: 12),
                  Center(
                    child: DsPill(
                      label: dsSentence(l10n.trainingCheckoutVisionBookRoute),
                      color: AppTheme.primaryLight,
                    ),
                  ),
                ],
                if (_alternatives.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  _routesCard(
                    (_resultSuccess
                            ? l10n.trainingCheckoutVisionOtherRoutes
                            : l10n.trainingCheckoutVisionRecommendedRoutes)
                        .toUpperCase(),
                    _alternatives,
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        // The one filled block of the screen.
        SizedBox(
          height: 52,
          child: ElevatedButton(
            onPressed: _nextQuestion,
            child: Text(
              _questionNumber >= kQuestions
                  ? dsSentence(l10n.trainingComplete)
                  : dsSentence(l10n.trainingQuizNext),
            ),
          ),
        ),
      ],
    );
  }

  /// The route the player played, "D16 → T20 → D8", tinted by the outcome.
  Widget _routeChips(List<TrainingDart> route, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < route.length; i++) ...[
          if (i > 0) ...[
            const SizedBox(width: 8),
            const Icon(
              Icons.arrow_forward_rounded,
              size: 16,
              color: AppTheme.textTertiary,
            ),
            const SizedBox(width: 8),
          ],
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppTheme.radiusControl),
              border: Border.all(color: color.withValues(alpha: 0.5)),
            ),
            child: Text(
              _dartLabel(route[i]),
              style: TextStyle(
                color: color,
                fontSize: 15,
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _routesCard(String title, List<List<TrainingDart>> routes) {
    return DsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTheme.labelSmall),
          for (var i = 0; i < routes.length; i++) ...[
            if (i > 0)
              const Divider(height: 20, color: AppTheme.border)
            else
              const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    routes[i].map(_dartLabel).join(' · '),
                    style: AppTheme.rowTitle,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  routes[i].map((d) => '${d.points}').join(' + '),
                  style: AppTheme.caption,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// 56 / 800 tabular hero number of the question card — the same one the
/// "Compte rapide" quiz uses.
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

/// Keypad key: surface, hairline, centred child. Disabled when [onTap] is
/// null (the backspace with nothing to erase).
class _PadKey extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;

  const _PadKey({required this.child, this.onTap});

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
