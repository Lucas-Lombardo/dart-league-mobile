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
import '../../widgets/design_system.dart';

/// "The race restarts": the ELO overlay's vocabulary applied to the
/// season-close compression — an 88 px primary disc, "SAISON 2" + the title
/// and one sentence, one card with the starting ELO (delta pill), the rank
/// band, "1486 → 1350 · Vous restez Or" and two caption lines, then one
/// button. Ends the once-only flow: marks the recap seen, refreshes the
/// profile (new elo / rank) and pops back home.
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
  late final Animation<double> _cardIn;
  late final Animation<double> _numberIn;
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
      curve: const Interval(0.0, 0.3, curve: Curves.easeOut),
    );
    _cardIn = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.2, 0.55, curve: Curves.easeOutCubic),
    );
    _numberIn = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.45, 0.7, curve: Curves.easeOut),
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

  Widget _reveal(Animation<double> animation, Widget child) {
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.06),
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
    );
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
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _reveal(_headerIn, _buildHeader(l10n, nextNumber)),
                        const SizedBox(height: 28),
                        _reveal(
                          _cardIn,
                          _NewEloCard(
                            recap: recap,
                            nextNumber: nextNumber,
                            nextEnd: nextEnd,
                            numberIn: _numberIn,
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
                  opacity: _restIn,
                  child: SizedBox(
                    width: double.infinity,
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
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 88 px primary disc with the start flag, "SAISON 2", the title and the
  /// one-sentence explanation.
  Widget _buildHeader(AppLocalizations l10n, int nextNumber) {
    return Column(
      children: [
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.12),
            shape: BoxShape.circle,
            border: Border.all(
              color: AppTheme.primary.withValues(alpha: 0.6),
              width: 2,
            ),
          ),
          child: const Icon(Icons.flag_outlined, size: 38, color: AppTheme.primary),
        ),
        const SizedBox(height: 18),
        Text(
          l10n.seasonN(nextNumber).toUpperCase(),
          style: AppTheme.labelSmall.copyWith(letterSpacing: 1.3),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.seasonResetTitle,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 32,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.7,
            height: 1,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          l10n.seasonResetBody,
          textAlign: TextAlign.center,
          style: AppTheme.caption.copyWith(fontSize: 13, height: 1.45),
        ),
      ],
    );
  }
}

/// The surface card: "DÉPART SAISON 2", the new ELO with the delta pill, the
/// rank band framed by its two floors, "1486 → 1350 · Vous restez Or", then
/// the two caption lines (nobody stays Master; the prize).
class _NewEloCard extends StatelessWidget {
  final SeasonRecap recap;
  final int nextNumber;
  final DateTime? nextEnd;
  final Animation<double> numberIn;

  const _NewEloCard({
    required this.recap,
    required this.nextNumber,
    required this.nextEnd,
    required this.numberIn,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final rank = _bandRank(recap.rankAfter);
    final delta = recap.eloAfter - recap.eloBefore;
    final rankAfter = RankTranslation.translate(l10n, recap.rankAfter);
    final rankLine = recap.rankChanged
        ? l10n.seasonResetYouBecome(rankAfter)
        : l10n.seasonResetYouStay(rankAfter);
    final prizeLine = nextEnd != null
        ? l10n.seasonResetPrizeOn(formatSeasonDayShort(context, nextEnd!))
        : l10n.seasonResetPrize;
    final boldAt = rankLine.indexOf(rankAfter);

    return DsCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Text(
            l10n.seasonResetStartOf(nextNumber).toUpperCase(),
            style: AppTheme.labelSmall.copyWith(letterSpacing: 1.3),
          ),
          const SizedBox(height: 10),
          FadeTransition(
            opacity: numberIn,
            // scaleDown keeps the hero line on one row whatever the digits,
            // the locale or the user's text scale.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${recap.eloAfter}',
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
                      color: AppTheme.textSecondary.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${delta > 0 ? '+' : ''}$delta',
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        height: 1,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          DsProgressBar(
            value: rank == 'master' ? 1 : rankProgress(rank, recap.eloAfter),
            height: 4,
          ),
          const SizedBox(height: 8),
          _BandCaptions(rank: rank),
          const SizedBox(height: 14),
          FadeTransition(
            opacity: numberIn,
            child: Text.rich(
              TextSpan(
                style: AppTheme.caption.copyWith(fontSize: 13),
                children: [
                  TextSpan(text: '${recap.eloBefore} '),
                  const TextSpan(
                    text: '→',
                    style: TextStyle(color: AppTheme.textTertiary),
                  ),
                  TextSpan(
                    text: ' ${recap.eloAfter}',
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const TextSpan(text: ' · '),
                  if (boldAt < 0)
                    TextSpan(text: rankLine)
                  else ...[
                    TextSpan(text: rankLine.substring(0, boldAt)),
                    TextSpan(
                      text: rankAfter,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    TextSpan(text: rankLine.substring(boldAt + rankAfter.length)),
                  ],
                ],
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 18),
          const Divider(),
          const SizedBox(height: 14),
          _CaptionLine(icon: Icons.workspace_premium_outlined, text: l10n.seasonResetNoMaster),
          const SizedBox(height: 10),
          _CaptionLine(icon: Icons.emoji_events_outlined, text: prizeLine),
        ],
      ),
    );
  }
}

/// The band a rating is read on: unranked is drawn as bronze.
String _bandRank(String rank) {
  final r = rank.toLowerCase();
  return kRankThresholds.containsKey(r) ? r : 'bronze';
}

/// "Or · 1200 ........ Platine · 1600" under the progress bar.
class _BandCaptions extends StatelessWidget {
  final String rank;

  const _BandCaptions({required this.rank});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isMax = rank == 'master';
    final style = AppTheme.caption.copyWith(fontWeight: FontWeight.w600);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(
            '${RankTranslation.translate(l10n, rank)} · ${kRankThresholds[rank]}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            isMax
                ? l10n.maxRankReached
                : '${RankTranslation.translate(l10n, nextRank(rank))} · ${kRankThresholds[nextRank(rank)]}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
            style: style,
          ),
        ),
      ],
    );
  }
}

/// A 16 px outlined icon and one wrapped caption sentence.
class _CaptionLine extends StatelessWidget {
  final IconData icon;
  final String text;

  const _CaptionLine({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: AppTheme.textSecondary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: AppTheme.caption.copyWith(fontSize: 13, height: 1.35),
          ),
        ),
      ],
    );
  }
}
