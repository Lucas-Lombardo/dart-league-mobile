import 'package:flutter/material.dart';
import '../providers/game_provider.dart' show ScoreMultiplier;
import '../services/dart_scoring_service.dart';
import '../utils/app_theme.dart';
import '../utils/haptic_service.dart';
import '../utils/dart_sound_service.dart';
import '../l10n/app_localizations.dart';
import 'design_system.dart';
import 'interactive_dartboard.dart';

/// Shows a modal bottom sheet for correcting a dart score.
///
/// Returns the selected [DartScore] or null if dismissed.
Future<DartScore?> showDartboardEditModal(
  BuildContext context, {
  required int dartIndex,
  DartScore? currentScore,
}) {
  return showModalBottomSheet<DartScore>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppTheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) => _DartEditSheet(
      dartIndex: dartIndex,
      currentScore: currentScore,
    ),
  );
}

/// The theme sheet (r24): a sentence-case title with the dart's current value
/// as a pill, the tap-to-pick dartboard with the selected bed highlighted, a
/// row of quick chips (S / D / T, miss, bull) to refine the pick, the readout
/// of the selection, then ONE primary "Valider" and a text "Annuler". The
/// returned [DartScore] is built exactly as before (ring names, bull and miss
/// encodings), only the picking changed: select, then validate.
class _DartEditSheet extends StatefulWidget {
  final int dartIndex;
  final DartScore? currentScore;

  const _DartEditSheet({
    required this.dartIndex,
    this.currentScore,
  });

  @override
  State<_DartEditSheet> createState() => _DartEditSheetState();
}

class _DartEditSheetState extends State<_DartEditSheet> {
  ScoreMultiplier _multiplier = ScoreMultiplier.single;

  /// 1–20, 25 for the bull, 0 for a miss, null while nothing is picked.
  int? _number;

  @override
  void initState() {
    super.initState();
    // Start from the dart's current value so "Valider" without a change is a
    // no-op re-emit, and the board shows what the AI read.
    final current = widget.currentScore;
    if (current == null) return;
    switch (current.ring) {
      case 'miss':
        _number = 0;
      case 'double_bull':
        _number = 25;
        _multiplier = ScoreMultiplier.double;
      case 'single_bull':
        _number = 25;
      case 'triple':
        _number = current.segment;
        _multiplier = ScoreMultiplier.triple;
      case 'double':
        _number = current.segment;
        _multiplier = ScoreMultiplier.double;
      default:
        if (current.segment >= 1 && current.segment <= 20) {
          _number = current.segment;
        }
    }
  }

  bool get _isMiss => _number == 0;
  bool get _isBull => _number == 25;

  void _onBoardTap(int number, ScoreMultiplier multiplier) {
    setState(() {
      _number = number;
      // A miss keeps the current multiplier chip; the bull can't be a triple.
      if (number == 25) {
        _multiplier = multiplier == ScoreMultiplier.triple
            ? ScoreMultiplier.single
            : multiplier;
      } else if (number != 0) {
        _multiplier = multiplier;
      }
    });
  }

  void _setMultiplier(ScoreMultiplier m) {
    HapticService.lightImpact();
    setState(() {
      _multiplier = m;
      if (_isMiss) _number = null;
    });
  }

  void _pickMiss() {
    HapticService.lightImpact();
    DartSoundService.playDartHit(0, ScoreMultiplier.single);
    setState(() => _number = 0);
  }

  void _pickBull() {
    HapticService.lightImpact();
    final m = _multiplier == ScoreMultiplier.triple
        ? ScoreMultiplier.single
        : _multiplier;
    DartSoundService.playDartHit(25, m);
    setState(() {
      _number = 25;
      _multiplier = m;
    });
  }

  void _validate() {
    final number = _number;
    if (number == null) return;
    HapticService.mediumImpact();
    if (number == 0) {
      Navigator.pop(context, DartScore(
        score: 0, segment: 0, ring: 'miss', radius: 2.0, angle: 0,
      ));
      return;
    }
    final ring = _multiplierToRing(number, _multiplier);
    final score = _computeScore(number, _multiplier);
    Navigator.pop(context, DartScore(
      score: score,
      segment: number == 25 ? 0 : number,
      ring: ring,
      radius: 0,
      angle: 0,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Cap the sheet so it never overflows in short viewports (landscape
    // phones) — the scrollable body absorbs the difference. In landscape the
    // board sits beside the controls and the sheet may use almost the whole
    // viewport since vertical space is already at a premium.
    final mq = MediaQuery.of(context);
    final isLandscape = mq.orientation == Orientation.landscape;
    final maxHeight = mq.size.height * (isLandscape ? 0.97 : 0.92);

    final header = Row(
      children: [
        Expanded(
          child: Text(
            l10n.editDartNumber(widget.dartIndex + 1),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.titleLarge,
          ),
        ),
        if (widget.currentScore != null) ...[
          const SizedBox(width: 10),
          DsPill(
            label: widget.currentScore!.formatted,
            color: AppTheme.textSecondary,
          ),
        ],
      ],
    );

    final controls = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildChips(l10n),
        const SizedBox(height: 12),
        _buildReadout(l10n),
        const SizedBox(height: 14),
        SizedBox(
          height: 48,
          child: ElevatedButton(
            onPressed: _number == null ? null : _validate,
            child: Text(l10n.submit),
          ),
        ),
        const SizedBox(height: 4),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
      ],
    );

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 10),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.surfaceLight,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                child: isLandscape
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: (mq.size.height * 0.62).clamp(180.0, 320.0),
                            height: (mq.size.height * 0.62).clamp(180.0, 320.0),
                            child: _buildBoard(),
                          ),
                          const SizedBox(width: 20),
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                header,
                                const SizedBox(height: 14),
                                controls,
                              ],
                            ),
                          ),
                        ],
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          header,
                          const SizedBox(height: 14),
                          Center(
                            child: SizedBox(
                              width: (mq.size.width - 56).clamp(200.0, 320.0),
                              height: (mq.size.width - 56).clamp(200.0, 320.0),
                              child: _buildBoard(),
                            ),
                          ),
                          const SizedBox(height: 16),
                          controls,
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBoard() {
    return InteractiveDartboard(
      onDartThrow: _onBoardTap,
      highlightNumber: _isMiss ? null : _number,
      highlightMultiplier: _isMiss || _number == null ? null : _multiplier,
    );
  }

  /// S / D / T · miss · bull. The multiplier chips stay selected next to a
  /// number or the bull (never next to a miss); the triple is inert on the
  /// bull, which has no triple ring.
  Widget _buildChips(AppLocalizations l10n) {
    final bullLabel = dsSentence(
      _multiplier == ScoreMultiplier.double ? l10n.bull50 : l10n.bull25,
    );
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        for (final (m, label) in [
          (ScoreMultiplier.single, l10n.singleShort),
          (ScoreMultiplier.double, l10n.doubleShort),
          (ScoreMultiplier.triple, l10n.tripleShort),
        ])
          _Chip(
            label: label,
            selected: !_isMiss && _multiplier == m,
            enabled: !(_isBull && m == ScoreMultiplier.triple),
            onTap: () => _setMultiplier(m),
          ),
        _Chip(
          label: dsSentence(l10n.missButton),
          selected: _isMiss,
          onTap: _pickMiss,
        ),
        _Chip(
          label: bullLabel,
          selected: _isBull,
          onTap: _pickBull,
        ),
      ],
    );
  }

  /// "T20 · 60 pts" — what "Valider" will send.
  Widget _buildReadout(AppLocalizations l10n) {
    final number = _number;
    final String text;
    if (number == null) {
      text = '—';
    } else if (number == 0) {
      text = dsSentence(l10n.missButton);
    } else {
      final prefix = switch (_multiplier) {
        ScoreMultiplier.single => l10n.singleShort,
        ScoreMultiplier.double => l10n.doubleShort,
        ScoreMultiplier.triple => l10n.tripleShort,
      };
      text = '$prefix$number · ${l10n.ptsLabel(_computeScore(number, _multiplier))}';
    }
    return Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: number == null ? AppTheme.textTertiary : AppTheme.textPrimary,
        fontSize: 15,
        fontWeight: FontWeight.w700,
        height: 1,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }

  static String _multiplierToRing(int baseScore, ScoreMultiplier multiplier) {
    if (baseScore == 25) {
      return multiplier == ScoreMultiplier.double ? 'double_bull' : 'single_bull';
    }
    if (baseScore == 0) return 'miss';
    switch (multiplier) {
      case ScoreMultiplier.triple:
        return 'triple';
      case ScoreMultiplier.double:
        return 'double';
      case ScoreMultiplier.single:
        return 'inner_single';
    }
  }

  static int _computeScore(int baseScore, ScoreMultiplier multiplier) {
    if (baseScore == 25) {
      return multiplier == ScoreMultiplier.double ? 50 : 25;
    }
    switch (multiplier) {
      case ScoreMultiplier.triple:
        return baseScore * 3;
      case ScoreMultiplier.double:
        return baseScore * 2;
      case ScoreMultiplier.single:
        return baseScore;
    }
  }
}

/// Quick-pick chip: surface with a hairline; selected = primary at 14 % with
/// a primaryLight border and label.
class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _Chip({
    required this.label,
    required this.selected,
    this.enabled = true,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = !enabled
        ? AppTheme.textTertiary
        : selected
            ? AppTheme.primaryLight
            : AppTheme.textPrimary;
    return Material(
      color: selected
          ? AppTheme.primary.withValues(alpha: 0.14)
          : AppTheme.surface,
      shape: StadiumBorder(
        side: BorderSide(
          color: selected ? AppTheme.primaryLight : AppTheme.border,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Container(
          height: 34,
          constraints: const BoxConstraints(minWidth: 44),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}
