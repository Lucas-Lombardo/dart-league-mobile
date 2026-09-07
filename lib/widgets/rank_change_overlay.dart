import 'package:flutter/material.dart';
import '../utils/app_theme.dart';
import '../utils/rank_translation.dart';
import '../utils/rank_utils.dart';
import '../utils/haptic_service.dart';
import '../l10n/app_localizations.dart';

/// Full-screen "your rank changed" overlay, shown after [EloChangeOverlay]
/// when the accepted result crossed a rank floor: sentence-case title, the
/// old badge → the new one (the rank is read on the badge image, its name
/// only as a caption), and the primary "Continuer à jouer" button pinned at
/// the bottom. Same staggered entrance as before; no glow, no particles.
class RankChangeOverlay extends StatefulWidget {
  final String oldRank;
  final String newRank;
  final VoidCallback onDismiss;

  const RankChangeOverlay({
    super.key,
    required this.oldRank,
    required this.newRank,
    required this.onDismiss,
  });

  /// Returns true if [newRank] is higher than [oldRank] in the tier order.
  static bool isRankUp(String oldRank, String newRank) {
    return _rankIndex(newRank) > _rankIndex(oldRank);
  }

  static int _rankIndex(String rank) {
    switch (rank.toLowerCase()) {
      case 'unranked':
        return 0;
      case 'bronze':
        return 1;
      case 'silver':
        return 2;
      case 'gold':
        return 3;
      case 'platinum':
        return 4;
      case 'diamond':
        return 5;
      case 'master':
        return 6;
      default:
        return 0;
    }
  }

  @override
  State<RankChangeOverlay> createState() => _RankChangeOverlayState();
}

class _RankChangeOverlayState extends State<RankChangeOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entranceController;

  late final Animation<double> _backgroundFade;
  late final Animation<double> _oldRankScale;
  late final Animation<double> _oldRankFade;
  late final Animation<double> _arrowFade;
  late final Animation<double> _arrowSlide;
  late final Animation<double> _newRankScale;
  late final Animation<double> _newRankFade;
  late final Animation<double> _textFade;
  late final Animation<double> _buttonFade;

  bool _isRankUp = false;

  @override
  void initState() {
    super.initState();
    _isRankUp = RankChangeOverlay.isRankUp(widget.oldRank, widget.newRank);

    // Main entrance sequence: 2.5s
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    );

    Animation<double> step(double from, double to, {Curve curve = Curves.easeOut}) =>
        Tween<double>(begin: 0, end: 1).animate(
          CurvedAnimation(
            parent: _entranceController,
            curve: Interval(from, to, curve: curve),
          ),
        );

    _backgroundFade = step(0, 0.2);
    _oldRankScale = Tween<double>(begin: 0.5, end: 1).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.1, 0.3, curve: Curves.elasticOut),
      ),
    );
    _oldRankFade = step(0.1, 0.25);
    _arrowFade = step(0.3, 0.45);
    _arrowSlide = Tween<double>(begin: 16, end: 0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.3, 0.5, curve: Curves.easeOut),
      ),
    );
    _newRankScale = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.45, 0.7, curve: Curves.elasticOut),
      ),
    );
    _newRankFade = step(0.45, 0.6);
    _textFade = step(0.65, 0.8);
    _buttonFade = step(0.8, 1.0);

    _entranceController.forward();

    // Haptic at the moment the new rank appears
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) HapticService.heavyImpact();
    });
  }

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return AnimatedBuilder(
      animation: _entranceController,
      builder: (context, _) {
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
                              FadeTransition(
                                opacity: _textFade,
                                child: Text(
                                  _isRankUp ? l10n.rankUp : l10n.rankDown,
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
                              const SizedBox(height: 40),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Opacity(
                                    opacity: _oldRankFade.value,
                                    child: Transform.scale(
                                      scale: _oldRankScale.value,
                                      child: _badge(l10n, widget.oldRank,
                                          size: 72, emphasis: false),
                                    ),
                                  ),
                                  Opacity(
                                    opacity: _arrowFade.value,
                                    child: Transform.translate(
                                      offset: Offset(-_arrowSlide.value, 0),
                                      child: const Padding(
                                        padding: EdgeInsets.symmetric(
                                            horizontal: 18),
                                        child: Icon(
                                          Icons.arrow_forward_rounded,
                                          color: AppTheme.textTertiary,
                                          size: 28,
                                        ),
                                      ),
                                    ),
                                  ),
                                  Opacity(
                                    opacity: _newRankFade.value,
                                    child: Transform.scale(
                                      scale: _newRankScale.value,
                                      child: _badge(l10n, widget.newRank,
                                          size: 112, emphasis: true),
                                    ),
                                  ),
                                ],
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

  /// A rank badge image with its localized name as a caption under it. Both
  /// columns share the tall badge's height, bottom-aligned, so the two
  /// captions sit on one line whatever the badge sizes.
  Widget _badge(
    AppLocalizations l10n,
    String rank, {
    required double size,
    required bool emphasis,
  }) {
    return SizedBox(
      height: 112 + 10 + 18,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: RankUtils.getRankBadge(rank, size: size),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 18,
            child: Text(
              RankTranslation.translate(l10n, rank),
              style: emphasis
                  ? const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    )
                  : AppTheme.caption,
            ),
          ),
        ],
      ),
    );
  }
}
