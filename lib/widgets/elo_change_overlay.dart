import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../utils/app_theme.dart';
import '../utils/haptic_service.dart';
import '../utils/rank_translation.dart';
import '../utils/rank_utils.dart';
import 'design_system.dart';

/// Full-screen "your ELO moved" overlay after a ranked result is accepted:
/// result disc, sentence-case title, one surface card with the counting ELO
/// number, the delta pill, the rank-band progress bar and the "next rank in
/// N pts" caption, and the primary "Continuer à jouer" button pinned at the
/// bottom. The staggered entrance and the 1.5 s count-up are kept; the glow,
/// the particles and the second colour are gone.
class EloChangeOverlay extends StatefulWidget {
  final int oldElo;
  final int newElo;
  final bool isWin;
  final VoidCallback onDismiss;

  const EloChangeOverlay({
    super.key,
    required this.oldElo,
    required this.newElo,
    required this.isWin,
    required this.onDismiss,
  });

  @override
  State<EloChangeOverlay> createState() => _EloChangeOverlayState();
}

class _EloChangeOverlayState extends State<EloChangeOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _entranceController;
  late final AnimationController _barController;

  late final Animation<double> _backgroundFade;
  late final Animation<double> _iconScale;
  late final Animation<double> _iconFade;
  late final Animation<double> _titleFade;
  late final Animation<double> _cardFade;
  late final Animation<double> _numberFade;
  late final Animation<double> _barProgress;
  late final Animation<double> _buttonFade;

  @override
  void initState() {
    super.initState();

    // Main entrance sequence: 2s
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );

    // Count-up animation: 1.5s, starts after entrance
    _barController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    Animation<double> step(double from, double to, {Curve curve = Curves.easeOut}) =>
        Tween<double>(begin: 0, end: 1).animate(
          CurvedAnimation(
            parent: _entranceController,
            curve: Interval(from, to, curve: curve),
          ),
        );

    _backgroundFade = step(0, 0.15);
    _iconScale = Tween<double>(begin: 0.3, end: 1).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.1, 0.35, curve: Curves.elasticOut),
      ),
    );
    _iconFade = step(0.1, 0.25);
    _titleFade = step(0.25, 0.4);
    _cardFade = step(0.35, 0.5);
    _numberFade = step(0.45, 0.6);
    _buttonFade = step(0.85, 1.0);

    _barProgress = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _barController, curve: Curves.easeInOut),
    );

    _entranceController.forward();

    // Start the count-up after the card fades in
    Future.delayed(const Duration(milliseconds: 1000), () {
      if (mounted) _barController.forward();
    });

    // Haptic when the count-up starts
    Future.delayed(const Duration(milliseconds: 1000), () {
      if (mounted) HapticService.mediumImpact();
    });

    // Haptic when it lands
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted) HapticService.heavyImpact();
    });
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _barController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.isWin ? AppTheme.success : AppTheme.error;
    final eloChange = widget.newElo - widget.oldElo;
    final l10n = AppLocalizations.of(context);

    return AnimatedBuilder(
      animation: Listenable.merge([_entranceController, _barController]),
      builder: (context, _) {
        final currentElo =
            (widget.oldElo + (eloChange * _barProgress.value)).round();

        return Material(
          color: Colors.transparent,
          child: Stack(
            children: [
              Opacity(
                opacity: _backgroundFade.value,
                child: Container(
                  color: AppTheme.background.withValues(alpha: 0.97),
                ),
              ),
              SafeArea(
                child: Column(
                  children: [
                    Expanded(
                      child: Center(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Opacity(
                                opacity: _iconFade.value,
                                child: Transform.scale(
                                  scale: _iconScale.value,
                                  child: Container(
                                    width: 88,
                                    height: 88,
                                    decoration: BoxDecoration(
                                      color: color.withValues(alpha: 0.12),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: color.withValues(alpha: 0.6),
                                        width: 2,
                                      ),
                                    ),
                                    child: Icon(
                                      widget.isWin
                                          ? Icons.emoji_events_outlined
                                          : Icons.trending_down_rounded,
                                      color: color,
                                      size: 38,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 18),
                              FadeTransition(
                                opacity: _titleFade,
                                child: Text(
                                  dsSentence(
                                      widget.isWin ? l10n.victory : l10n.defeat),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: AppTheme.textPrimary,
                                    fontSize: 34,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.7,
                                    height: 1,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 36),
                              FadeTransition(
                                opacity: _cardFade,
                                child: _buildEloCard(
                                  l10n,
                                  color: color,
                                  currentElo: currentElo,
                                  eloChange: eloChange,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                      child: FadeTransition(
                        opacity: _buttonFade,
                        child: SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            onPressed: widget.onDismiss,
                            child: Text(l10n.continuePlaying),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// The surface card: "ELO" label, counting number + delta pill, the rank
  /// band progress (floor of the current rank → floor of the next), and the
  /// "1601 → 1619 · Diamant dans 381 pts" caption. Thresholds come from
  /// rank_utils so this never disagrees with the home card.
  Widget _buildEloCard(
    AppLocalizations l10n, {
    required Color color,
    required int currentElo,
    required int eloChange,
  }) {
    // The band follows the counting number, so the bar visibly crosses a
    // rank floor when the match did.
    final rank = rankFromElo(currentElo) == 'unranked'
        ? 'bronze'
        : rankFromElo(currentElo);
    final isMax = rank == 'master';
    final finalRank = rankFromElo(widget.newElo) == 'unranked'
        ? 'bronze'
        : rankFromElo(widget.newElo);
    final needed = math.max(eloNeededForNextRank(finalRank, widget.newElo), 0);
    final nextLabel = RankTranslation.translate(l10n, nextRank(finalRank));

    return DsCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Text(
            l10n.eloLabel,
            style: AppTheme.labelSmall.copyWith(letterSpacing: 1.3),
          ),
          const SizedBox(height: 10),
          FadeTransition(
            opacity: _numberFade,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  '$currentElo',
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 56,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1.7,
                    height: 1,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 14),
                Container(
                  height: 34,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${eloChange >= 0 ? '+' : ''}$eloChange',
                    style: TextStyle(
                      color: color,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      height: 1,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          DsProgressBar(
            value: isMax ? 1 : rankProgress(rank, currentElo),
            height: 4,
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${RankTranslation.translate(l10n, rank)} · ${kRankThresholds[rank]}',
                style: AppTheme.caption.copyWith(fontWeight: FontWeight.w600),
              ),
              Text(
                isMax
                    ? l10n.maxRankReached
                    : '${RankTranslation.translate(l10n, nextRank(rank))} · ${kRankThresholds[nextRank(rank)]}',
                style: AppTheme.caption.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 14),
          FadeTransition(
            opacity: _numberFade,
            child: Text.rich(
              TextSpan(
                style: AppTheme.caption.copyWith(fontSize: 13),
                children: [
                  TextSpan(text: '${widget.oldElo} '),
                  const TextSpan(
                    text: '→',
                    style: TextStyle(color: AppTheme.textTertiary),
                  ),
                  TextSpan(
                    text: ' ${widget.newElo}',
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  TextSpan(
                    text: finalRank == 'master'
                        ? ' · ${l10n.maxRankReached}'
                        : ' · $nextLabel ${l10n.nextRankConnector} $needed pts',
                  ),
                ],
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}
