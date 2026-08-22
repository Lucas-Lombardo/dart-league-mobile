import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/season.dart';
import '../../providers/auth_provider.dart';
import '../../providers/season_provider.dart';
import '../../utils/app_theme.dart';
import '../../utils/haptic_service.dart';
import '../../utils/rank_translation.dart';
import '../../utils/rank_utils.dart';
import '../../utils/season_format.dart';

/// "The race restarts": before → after the season-close compression, the
/// rank band with both marks, three sentences, one button. Ends the
/// once-only flow: marks the recap seen, refreshes the profile (new elo /
/// rank) and pops back home.
class SeasonNewEloScreen extends StatefulWidget {
  final SeasonRecap recap;

  const SeasonNewEloScreen({super.key, required this.recap});

  static Route<void> route(SeasonRecap recap) {
    return PageRouteBuilder<void>(
      opaque: true,
      pageBuilder: (_, _, _) => SeasonNewEloScreen(recap: recap),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
      transitionDuration: const Duration(milliseconds: 300),
    );
  }

  @override
  State<SeasonNewEloScreen> createState() => _SeasonNewEloScreenState();
}

class _SeasonNewEloScreenState extends State<SeasonNewEloScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _headerIn;
  late final Animation<double> _beforeIn;
  late final Animation<double> _afterIn;
  late final Animation<double> _bandIn;
  late final Animation<double> _restIn;
  bool _reducedMotionApplied = false;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 1600),
      vsync: this,
    );
    _headerIn = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.0, 0.25, curve: Curves.easeOut),
    );
    _beforeIn = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.15, 0.4, curve: Curves.easeOut),
    );
    _afterIn = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.35, 0.65, curve: Curves.elasticOut),
    );
    _bandIn = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.5, 0.8, curve: Curves.easeOut),
    );
    _restIn = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.75, 1.0, curve: Curves.easeIn),
    );
    _ctrl.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Respect the OS "reduce motion" setting: jump straight to the final
    // state (same guard as tournament_end_screen).
    if (!_reducedMotionApplied && MediaQuery.of(context).disableAnimations) {
      _reducedMotionApplied = true;
      _ctrl.stop();
      _ctrl.value = 1.0;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _play() async {
    if (_leaving) return;
    setState(() => _leaving = true);
    HapticService.mediumImpact();
    final seasons = context.read<SeasonProvider>();
    final auth = context.read<AuthProvider>();
    // Acknowledge first, then refresh elo/rank in the profile. If the
    // acknowledgement fails the screens simply come back at the next launch.
    await seasons.markRecapSeen(widget.recap.season.number);
    await Future.wait([auth.checkAuthStatus(), seasons.refresh()]);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final recap = widget.recap;
    final next = recap.nextSeason;
    final nextNumber = next?.number ?? recap.season.number + 1;
    final nextEnd = next?.endAt;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: Container(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, -1.15),
              radius: 0.9,
              colors: [Color(0x590EA5E9), Colors.transparent],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          FadeTransition(
                            opacity: _headerIn,
                            child: Column(
                              children: [
                                Text(
                                  l10n.seasonN(nextNumber).toUpperCase(),
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 2.2,
                                    color: Color(0xFF38BDF8),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  l10n.seasonResetTitle,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.5,
                                    height: 1.15,
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  l10n.seasonResetBody,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    height: 1.5,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 26),
                          _BeforeAfter(
                            recap: recap,
                            beforeIn: _beforeIn,
                            afterIn: _afterIn,
                            nextNumber: nextNumber,
                          ),
                          const SizedBox(height: 18),
                          FadeTransition(
                            opacity: _bandIn,
                            child: _RankBand(
                              before: recap.eloBefore,
                              after: recap.eloAfter,
                            ),
                          ),
                          const SizedBox(height: 18),
                          FadeTransition(
                            opacity: _restIn,
                            child: _Sentences(recap: recap, nextEnd: nextEnd),
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  ),
                  FadeTransition(
                    opacity: _restIn,
                    child: SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _leaving ? null : _play,
                        child: _leaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(l10n.seasonResetPlay(nextNumber)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BeforeAfter extends StatelessWidget {
  final SeasonRecap recap;
  final Animation<double> beforeIn;
  final Animation<double> afterIn;
  final int nextNumber;

  const _BeforeAfter({
    required this.recap,
    required this.beforeIn,
    required this.afterIn,
    required this.nextNumber,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        Expanded(
          child: FadeTransition(
            opacity: beforeIn,
            child: Opacity(
              opacity: 0.55,
              child: Column(
                children: [
                  RankUtils.getRankBadge(recap.rankBefore, size: 56),
                  const SizedBox(height: 6),
                  Text(
                    '${recap.eloBefore}',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary,
                      decoration: TextDecoration.lineThrough,
                      decorationColor: AppTheme.secondary,
                      decorationThickness: 2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    l10n.seasonResetEndOf(recap.season.number),
                    style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 14),
        const Icon(Icons.arrow_forward, size: 28, color: Color(0xFF38BDF8)),
        const SizedBox(width: 14),
        Expanded(
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.6, end: 1).animate(afterIn),
            child: FadeTransition(
              opacity: afterIn,
              child: Column(
                children: [
                  RankUtils.getRankBadge(recap.rankAfter, size: 72),
                  const SizedBox(height: 6),
                  Text(
                    '${recap.eloAfter}',
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.primary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    l10n.seasonResetStartOf(nextNumber),
                    style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Relative widths of the six tiers on the band (Master is wider).
const List<double> kRankBandWidths = [16, 16, 16, 16, 16, 20];

/// Where the Master segment stops for placement purposes.
const int kRankBandMasterCeiling = 3000;

/// 0..1 horizontal position of a rating on the rank band. Tier floors come
/// from rank_utils (mirrors the backend); inside a tier the position is
/// linear. 1486 → 0.434, 1350 → 0.38 (the validated mockup values).
double rankBandFraction(int elo) {
  final total = kRankBandWidths.fold<double>(0, (a, b) => a + b);
  var offset = 0.0;
  for (var i = 0; i < kRankedTiers.length; i++) {
    final floor = kRankThresholds[kRankedTiers[i]]!;
    final last = i == kRankedTiers.length - 1;
    final ceiling = last
        ? kRankBandMasterCeiling
        : kRankThresholds[kRankedTiers[i + 1]]!;
    if (elo < ceiling || last) {
      final inTier = ((elo - floor) / (ceiling - floor)).clamp(0.0, 1.0);
      return (offset + kRankBandWidths[i] * inTier) / total;
    }
    offset += kRankBandWidths[i];
  }
  return 1;
}

/// The six tiers as a band (Master wider), the "before" mark above and the
/// "start" mark below.
class _RankBand extends StatelessWidget {
  final int before;
  final int after;

  const _RankBand({required this.before, required this.after});

  static const _widths = kRankBandWidths;
  static const _colors = <Color>[
    Color(0xFFCD7F32),
    Color(0xFFC0C0C0),
    Color(0xFFEAB308),
    Color(0xFF5EEAD4),
    Color(0xFF818CF8),
    Color(0xFFF43F5E),
  ];

  static double fraction(int elo) => rankBandFraction(elo);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final beforeX = width * fraction(before);
        final afterX = width * fraction(after);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 24,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: beforeX,
                    bottom: 0,
                    child: Opacity(
                      opacity: 0.6,
                      child: _Mark(
                        label: '$before · ${l10n.seasonResetBefore}',
                        color: AppTheme.textSecondary,
                        labelAbove: true,
                        alignRight: fraction(before) > 0.7,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: SizedBox(
                height: 10,
                child: Row(
                  children: [
                    for (var i = 0; i < _widths.length; i++)
                      Expanded(
                        flex: _widths[i].round(),
                        child: ColoredBox(color: _colors[i].withValues(alpha: 0.55)),
                      ),
                  ],
                ),
              ),
            ),
            SizedBox(
              height: 26,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: afterX,
                    top: 0,
                    child: _Mark(
                      label: '$after · ${l10n.seasonResetStart}',
                      color: AppTheme.primary,
                      labelAbove: false,
                      alignRight: fraction(after) > 0.7,
                    ),
                  ),
                ],
              ),
            ),
            Row(
              children: [
                for (var i = 0; i < kRankedTiers.length; i++)
                  Expanded(
                    flex: _widths[i].round(),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: i == 0
                          ? Alignment.centerLeft
                          : (i == kRankedTiers.length - 1
                              ? Alignment.centerRight
                              : Alignment.center),
                      child: Text(
                        RankTranslation.translate(l10n, kRankedTiers[i]).toUpperCase(),
                        style: const TextStyle(
                          fontSize: 9.5,
                          letterSpacing: 0.76,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// A 2 × 8 tick with its label, anchored on the tick's x.
class _Mark extends StatelessWidget {
  final String label;
  final Color color;
  final bool labelAbove;
  /// Near the right edge, grow the label leftwards so it stays on screen.
  final bool alignRight;

  const _Mark({
    required this.label,
    required this.color,
    required this.labelAbove,
    required this.alignRight,
  });

  @override
  Widget build(BuildContext context) {
    final text = Text(
      label,
      softWrap: false,
      style: TextStyle(
        fontSize: 10.5,
        height: 1.15,
        fontWeight: labelAbove ? FontWeight.w400 : FontWeight.w700,
        color: color,
      ),
    );
    final tick = Container(width: 2, height: 8, color: color);
    // A 2 px wide anchor at the tick's x; the label overflows it to the
    // right (or to the left near the edge) without affecting layout.
    final height = labelAbove ? 24.0 : 26.0;
    return SizedBox(
      width: 2,
      height: height,
      child: OverflowBox(
        minWidth: 0,
        maxWidth: 220,
        minHeight: 0,
        maxHeight: height,
        alignment: labelAbove
            ? (alignRight ? Alignment.bottomRight : Alignment.bottomLeft)
            : (alignRight ? Alignment.topRight : Alignment.topLeft),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: alignRight ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: labelAbove ? [text, const SizedBox(height: 2), tick] : [tick, const SizedBox(height: 2), text],
        ),
      ),
    );
  }
}

class _Sentences extends StatelessWidget {
  final SeasonRecap recap;
  final DateTime? nextEnd;

  const _Sentences({required this.recap, required this.nextEnd});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final rankAfter = RankTranslation.translate(l10n, recap.rankAfter);
    final rankLine = recap.rankChanged
        ? l10n.seasonResetYouBecome(rankAfter)
        : l10n.seasonResetYouStay(rankAfter);
    final prizeLine = nextEnd != null
        ? l10n.seasonResetPrizeOn(formatSeasonDayShort(context, nextEnd!))
        : l10n.seasonResetPrize;

    Widget row(Widget icon, String text, {String? bold}) {
      final i = bold == null ? -1 : text.indexOf(bold);
      return Row(
        children: [
          SizedBox(width: 16, child: icon),
          const SizedBox(width: 10),
          Expanded(
            child: i < 0
                ? Text(text, style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary))
                : Text.rich(
                    TextSpan(
                      style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary),
                      children: [
                        TextSpan(text: text.substring(0, i)),
                        TextSpan(
                          text: bold,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        TextSpan(text: text.substring(i + bold!.length)),
                      ],
                    ),
                  ),
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.surfaceLight.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          row(
            const Icon(Icons.check, size: 16, color: AppTheme.success),
            rankLine,
            bold: rankAfter,
          ),
          const SizedBox(height: 10),
          row(
            const Icon(Icons.workspace_premium_outlined, size: 16, color: AppTheme.secondary),
            l10n.seasonResetNoMaster,
          ),
          const SizedBox(height: 10),
          row(
            const Icon(Icons.emoji_events_outlined, size: 16, color: AppTheme.gold),
            prizeLine,
          ),
        ],
      ),
    );
  }
}
