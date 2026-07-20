import 'package:flutter/material.dart';
import '../../utils/app_theme.dart';

/// Redesigned end-of-match screen shared by ranked, friendly and tournament
/// matches: animated hero + headline, optional series score and tournament
/// badge, and an action panel supplied by the calling screen (accept/refuse,
/// accept/report or rematch). Both orientations keep every region inside a
/// scroll view so the screen can never overflow on short devices or with a
/// large system font scale.
class MatchEndView extends StatefulWidget {
  final bool didWin;
  final String title;
  final String subtitle;

  /// "2 – 1" for a BO3 series; null hides the score tile.
  final String? scoreLine;

  /// "Best of 3" caption under [scoreLine].
  final String? scoreCaption;

  /// Tournament name pill above the title; null hides it.
  final String? badgeText;

  /// Action card content (title/buttons). The card chrome (surface, border,
  /// glow) is applied here so every match type gets the same panel look.
  final Widget panel;

  const MatchEndView({
    super.key,
    required this.didWin,
    required this.title,
    required this.subtitle,
    required this.panel,
    this.scoreLine,
    this.scoreCaption,
    this.badgeText,
  });

  @override
  State<MatchEndView> createState() => _MatchEndViewState();
}

class _MatchEndViewState extends State<MatchEndView>
    with TickerProviderStateMixin {
  late final AnimationController _mainCtrl;
  late final AnimationController _glowCtrl;

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
    _glowCtrl = AnimationController(
        duration: const Duration(milliseconds: 1800), vsync: this)
      ..repeat(reverse: true);

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
    // state and stop the looping glow.
    if (!_reducedMotionApplied && MediaQuery.of(context).disableAnimations) {
      _reducedMotionApplied = true;
      _mainCtrl.stop();
      _mainCtrl.value = 1.0;
      _glowCtrl.stop();
    }
  }

  @override
  void dispose() {
    _mainCtrl.dispose();
    _glowCtrl.dispose();
    super.dispose();
  }

  Color get _accent => widget.didWin ? AppTheme.success : AppTheme.error;

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.surfaceGradient),
        child: SafeArea(
          child: isLandscape
              ? Row(children: [
                  Expanded(child: _scrollCentered(_buildHeadline(compact: true))),
                  Expanded(
                    child: _scrollCentered(Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 16),
                      child: _buildPanelCard(),
                    )),
                  ),
                ])
              : LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                    child: ConstrainedBox(
                      constraints:
                          BoxConstraints(minHeight: constraints.maxHeight - 40),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildHeadline(compact: false),
                          const SizedBox(height: 28),
                          _buildPanelCard(),
                        ],
                      ),
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

  Widget _buildHeadline({required bool compact}) {
    final heroSize = compact ? 88.0 : 116.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.badgeText != null) ...[
          FadeTransition(
            opacity: _detailsFade,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
                border:
                    Border.all(color: AppTheme.primary.withValues(alpha: 0.4)),
              ),
              child: Text(
                widget.badgeText!,
                style: const TextStyle(
                  color: AppTheme.primary,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          SizedBox(height: compact ? 14 : 20),
        ],
        FadeTransition(
          opacity: _heroFade,
          child: ScaleTransition(
            scale: _heroScale,
            child: AnimatedBuilder(
              animation: _glowCtrl,
              builder: (_, _) => Container(
                width: heroSize,
                height: heroSize,
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                  border: Border.all(color: _accent, width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: _accent
                          .withValues(alpha: 0.22 + 0.22 * _glowCtrl.value),
                      blurRadius: 22 + 16 * _glowCtrl.value,
                      spreadRadius: 2 + 6 * _glowCtrl.value,
                    ),
                  ],
                ),
                child: Icon(
                  widget.didWin
                      ? Icons.emoji_events
                      : Icons.sentiment_dissatisfied,
                  color: _accent,
                  size: heroSize * 0.5,
                ),
              ),
            ),
          ),
        ),
        SizedBox(height: compact ? 16 : 24),
        SlideTransition(
          position: _titleSlide,
          child: FadeTransition(
            opacity: _titleFade,
            child: Text(
              widget.title.toUpperCase(),
              style: TextStyle(
                color: _accent,
                fontSize: compact ? 28 : 34,
                fontWeight: FontWeight.w900,
                letterSpacing: 2.5,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        const SizedBox(height: 8),
        FadeTransition(
          opacity: _detailsFade,
          child: Text(
            widget.subtitle,
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 15),
            textAlign: TextAlign.center,
          ),
        ),
        if (widget.scoreLine != null) ...[
          SizedBox(height: compact ? 14 : 20),
          FadeTransition(
            opacity: _detailsFade,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.background,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: AppTheme.surfaceLight.withValues(alpha: 0.6)),
              ),
              child: Column(
                children: [
                  Text(
                    widget.scoreLine!,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: compact ? 24 : 30,
                      fontWeight: FontWeight.w800,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  if (widget.scoreCaption != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      widget.scoreCaption!.toUpperCase(),
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPanelCard() {
    return SlideTransition(
      position: _panelSlide,
      child: FadeTransition(
        opacity: _panelFade,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(16),
            border:
                Border.all(color: AppTheme.primary.withValues(alpha: 0.35)),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primary.withValues(alpha: 0.18),
                blurRadius: 26,
                spreadRadius: -12,
              ),
            ],
          ),
          child: widget.panel,
        ),
      ),
    );
  }
}
