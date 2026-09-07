import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../../services/replay_clips_store.dart';
import '../../utils/app_navigator.dart';
import '../../utils/app_theme.dart';
import '../../widgets/design_system.dart';
import '../../widgets/match_stats_card.dart';
import '../profile/replay_library_screen.dart';

/// End-of-match screen shared by ranked, friendly and tournament matches:
/// animated hero + headline, the two-coloured legs tile, the stats card, a
/// replays link, and the action panel supplied by the calling screen
/// (accept/refuse, accept/report or rematch) laid flat at the bottom. Both
/// orientations keep every region inside a scroll view so the screen can
/// never overflow on short devices or with a large system font scale.
class MatchEndView extends StatefulWidget {
  final bool didWin;
  final String title;
  final String subtitle;

  /// "2 – 1" for a BO3 series; null hides the score tile. A "my – theirs"
  /// line is drawn two-coloured (blue / rose); anything else in plain white.
  final String? scoreLine;

  /// "Best of 3" caption under [scoreLine].
  final String? scoreCaption;

  /// Tournament name pill above the title; null hides it.
  final String? badgeText;

  /// Action content (buttons). Laid out as-is at the bottom of the screen —
  /// no card around it, the system keeps one filled block per screen.
  final Widget panel;

  /// The replay clips captured during this match/series — sharing lives
  /// HERE, after the match, never in-game (deliberate: recording mid-match
  /// is one tap, everything else waits until the darts are done).
  final List<ReplayClip> replayClips;

  /// Optional card slotted between the clips row and the action panel — today
  /// the "report their winning visit" banner, which only the loser sees. Its
  /// own card on purpose: reporting a visit and contesting the score are two
  /// different things, and merging them into the result panel would blur that.
  final Widget? preCard;

  /// The match that just ended. When set, the screen shows its stats — the
  /// figures the server already holds and that this screen, the one every
  /// player sees after every match, used to leave out entirely. Null (bots,
  /// local matches) simply hides the card; so does cricket, which the server
  /// reports as having no X01 figures.
  final String? statsMatchId;

  const MatchEndView({
    super.key,
    required this.didWin,
    required this.title,
    required this.subtitle,
    required this.panel,
    this.scoreLine,
    this.scoreCaption,
    this.badgeText,
    this.replayClips = const [],
    this.preCard,
    this.statsMatchId,
  });

  @override
  State<MatchEndView> createState() => _MatchEndViewState();
}

class _MatchEndViewState extends State<MatchEndView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _mainCtrl;

  late final Animation<double> _heroScale;
  late final Animation<double> _heroFade;
  late final Animation<Offset> _titleSlide;
  late final Animation<double> _titleFade;
  late final Animation<double> _detailsFade;
  late final Animation<Offset> _panelSlide;
  late final Animation<double> _panelFade;

  bool _reducedMotionApplied = false;

  @override
  void initState() {
    super.initState();
    _mainCtrl = AnimationController(
        duration: const Duration(milliseconds: 1400), vsync: this);

    _heroScale = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(
        parent: _mainCtrl,
        curve: const Interval(0.0, 0.45, curve: Curves.elasticOut)));
    _heroFade = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(
        parent: _mainCtrl,
        curve: const Interval(0.0, 0.2, curve: Curves.easeIn)));
    _titleSlide = Tween<Offset>(begin: const Offset(0, 0.4), end: Offset.zero)
        .animate(CurvedAnimation(
            parent: _mainCtrl,
            curve: const Interval(0.3, 0.6, curve: Curves.easeOut)));
    _titleFade = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(
        parent: _mainCtrl,
        curve: const Interval(0.3, 0.55, curve: Curves.easeIn)));
    _detailsFade = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(
        parent: _mainCtrl,
        curve: const Interval(0.5, 0.75, curve: Curves.easeIn)));
    _panelSlide = Tween<Offset>(begin: const Offset(0, 0.12), end: Offset.zero)
        .animate(CurvedAnimation(
            parent: _mainCtrl,
            curve: const Interval(0.6, 0.95, curve: Curves.easeOut)));
    _panelFade = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(
        parent: _mainCtrl,
        curve: const Interval(0.6, 0.9, curve: Curves.easeIn)));

    _mainCtrl.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Respect the OS "reduce motion" setting: jump straight to the final
    // state.
    if (!_reducedMotionApplied && MediaQuery.of(context).disableAnimations) {
      _reducedMotionApplied = true;
      _mainCtrl.stop();
      _mainCtrl.value = 1.0;
    }
  }

  @override
  void dispose() {
    _mainCtrl.dispose();
    super.dispose();
  }

  Color get _accent => widget.didWin ? AppTheme.success : AppTheme.error;

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: isLandscape
            ? Row(children: [
                Expanded(child: _scrollCentered(_buildHeadline(compact: true))),
                Expanded(
                  child: _scrollCentered(Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ..._details(compact: true),
                        if (widget.preCard != null) widget.preCard!,
                        _buildPanel(),
                      ],
                    ),
                  )),
                ),
              ])
            : LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 40, 16, 24),
                  child: ConstrainedBox(
                    constraints:
                        BoxConstraints(minHeight: constraints.maxHeight - 64),
                    // Two groups: everything about the result at the top, the
                    // actions pinned to the bottom (spaceBetween on the
                    // min-height column), still one scroll view for short
                    // phones and large font scales.
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          children: [
                            _buildHeadline(compact: false),
                            const SizedBox(height: 16),
                            ..._details(compact: false),
                          ],
                        ),
                        Column(
                          children: [
                            const SizedBox(height: 24),
                            if (widget.preCard != null) widget.preCard!,
                            _buildPanel(),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _scrollCentered(Widget child) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: child,
        ),
      );

  /// Stats card + replays link, in that order, each followed by its gap.
  List<Widget> _details({required bool compact}) => [
        if (widget.statsMatchId != null) ...[
          _buildStatsCard(compact: compact),
          const SizedBox(height: 12),
        ],
        if (widget.replayClips.isNotEmpty) ...[
          _buildReplaysLink(),
          const SizedBox(height: 12),
        ],
      ];

  Widget _buildHeadline({required bool compact}) {
    final heroSize = compact ? 72.0 : 88.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.badgeText != null) ...[
          FadeTransition(
            opacity: _detailsFade,
            child: DsPill(label: widget.badgeText!),
          ),
          SizedBox(height: compact ? 12 : 16),
        ],
        FadeTransition(
          opacity: _heroFade,
          child: ScaleTransition(
            scale: _heroScale,
            child: Container(
              width: heroSize,
              height: heroSize,
              decoration: BoxDecoration(
                color: _accent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
                border: Border.all(
                  color: _accent.withValues(alpha: 0.6),
                  width: 2,
                ),
              ),
              child: Icon(
                widget.didWin
                    ? Icons.emoji_events_outlined
                    : Icons.sentiment_dissatisfied_outlined,
                color: _accent,
                size: compact ? 30 : 38,
              ),
            ),
          ),
        ),
        SizedBox(height: compact ? 14 : 18),
        SlideTransition(
          position: _titleSlide,
          child: FadeTransition(
            opacity: _titleFade,
            child: Text(
              dsSentence(widget.title),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: compact ? 28 : 34,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.7,
                height: 1,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        FadeTransition(
          opacity: _detailsFade,
          child: Text(
            widget.subtitle,
            textAlign: TextAlign.center,
            style: AppTheme.caption.copyWith(fontSize: 14),
          ),
        ),
        if (widget.scoreLine != null) ...[
          SizedBox(height: compact ? 14 : 18),
          FadeTransition(
            opacity: _detailsFade,
            child: _buildLegsTile(compact: compact),
          ),
        ],
      ],
    );
  }

  /// "2 – 1" over "AU MEILLEUR DE 3" on a 64 px surface tile. A line the
  /// callers built as "mine – theirs" gets the identity colours.
  Widget _buildLegsTile({required bool compact}) {
    final fontSize = compact ? 24.0 : 28.0;
    final base = TextStyle(
      fontSize: fontSize,
      fontWeight: FontWeight.w800,
      height: 1,
      color: AppTheme.textPrimary,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final parts = widget.scoreLine!.split(' – ');
    final Widget score = parts.length == 2
        ? Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(parts[0],
                  style: base.copyWith(color: AppTheme.playerBlueBright)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  '–',
                  style: base.copyWith(
                    color: AppTheme.textTertiary,
                    fontSize: fontSize * 0.72,
                  ),
                ),
              ),
              Text(parts[1],
                  style: base.copyWith(color: AppTheme.opponentPinkBright)),
            ],
          )
        : Text(widget.scoreLine!, style: base);

    return SizedBox(
      height: 64,
      child: DsCard(
        radius: AppTheme.radiusRow,
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            score,
            if (widget.scoreCaption != null) ...[
              const SizedBox(height: 5),
              Text(
                widget.scoreCaption!.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.labelSmall.copyWith(fontSize: 10, height: 1),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// One quiet link when clips were captured this match — the end screen
  /// must stay scroll-free down to the confirm/report panel, so the list
  /// itself lives in « Mes replays » (2026-08-03 feedback: the inline rows
  /// pushed the actions below the fold).
  Widget _buildReplaysLink() {
    final l10n = AppLocalizations.of(context);
    return SlideTransition(
      position: _panelSlide,
      child: FadeTransition(
        opacity: _panelFade,
        child: TextButton.icon(
          onPressed: () =>
              AppNavigator.toScreen(context, const ReplayLibraryScreen()),
          style: TextButton.styleFrom(
            foregroundColor: AppTheme.primaryLight,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            // Spelled-out family: a ButtonStyle textStyle does not inherit it.
            textStyle: const TextStyle(
              fontFamily: AppTheme.fontFamily,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          icon: const Icon(Icons.movie_outlined, size: 15),
          label: Text('${l10n.replayViewMine} (${widget.replayClips.length})'),
        ),
      ),
    );
  }

  /// Fades in with the rest of the details. The card renders nothing until its
  /// figures arrive, so this animation applies to an empty box first — which is
  /// exactly what keeps the actions below from jumping.
  Widget _buildStatsCard({required bool compact}) {
    return FadeTransition(
      opacity: _detailsFade,
      child: MatchStatsCard(matchId: widget.statsMatchId!, compact: compact),
    );
  }

  Widget _buildPanel() {
    return SlideTransition(
      position: _panelSlide,
      child: FadeTransition(opacity: _panelFade, child: widget.panel),
    );
  }
}
