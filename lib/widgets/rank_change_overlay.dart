import 'dart:math';
import 'package:flutter/material.dart';
import '../utils/app_theme.dart';
import '../utils/rank_utils.dart';
import '../utils/haptic_service.dart';
import '../l10n/app_localizations.dart';

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

  static Color getRankColor(String rank) {
    switch (rank.toLowerCase()) {
      case 'bronze':
        return const Color(0xFFCD7F32);
      case 'silver':
        return const Color(0xFFC0C0C0);
      case 'gold':
        return const Color(0xFFFFD700);
      case 'platinum':
        return const Color(0xFF00CED1);
      case 'diamond':
        return const Color(0xFFB9F2FF);
      case 'master':
        return const Color(0xFFFF4500);
      default:
        return AppTheme.textSecondary;
    }
  }

  @override
  State<RankChangeOverlay> createState() => _RankChangeOverlayState();
}

class _RankChangeOverlayState extends State<RankChangeOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _entranceController;
  late final AnimationController _pulseController;
  late final AnimationController _particleController;

  late final Animation<double> _backgroundFade;
  late final Animation<double> _oldRankScale;
  late final Animation<double> _oldRankFade;
  late final Animation<double> _arrowFade;
  late final Animation<double> _arrowSlide;
  late final Animation<double> _newRankScale;
  late final Animation<double> _newRankFade;
  late final Animation<double> _textFade;
  late final Animation<double> _glowPulse;
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

    // Looping pulse for glow
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    // Particles
    _particleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    );

    // Staggered entrance animations
    _backgroundFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0, 0.2, curve: Curves.easeOut),
      ),
    );

    _oldRankScale = Tween<double>(begin: 0.5, end: 1).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.1, 0.3, curve: Curves.elasticOut),
      ),
    );

    _oldRankFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.1, 0.25, curve: Curves.easeOut),
      ),
    );

    _arrowFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.3, 0.45, curve: Curves.easeOut),
      ),
    );

    _arrowSlide = Tween<double>(begin: 20, end: 0).animate(
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

    _newRankFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.45, 0.6, curve: Curves.easeOut),
      ),
    );

    _textFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.65, 0.8, curve: Curves.easeOut),
      ),
    );

    _buttonFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.8, 1.0, curve: Curves.easeOut),
      ),
    );

    _glowPulse = Tween<double>(begin: 0.4, end: 1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _entranceController.forward();
    _pulseController.repeat(reverse: true);
    if (_isRankUp) _particleController.repeat();

    // Haptic at the moment the new rank appears
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) HapticService.heavyImpact();
    });
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _pulseController.dispose();
    _particleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final newRankColor = RankChangeOverlay.getRankColor(widget.newRank);
    final l10n = AppLocalizations.of(context);

    return AnimatedBuilder(
      animation: Listenable.merge([
        _entranceController,
        _pulseController,
        _particleController,
      ]),
      builder: (context, _) {
        return Material(
          color: Colors.transparent,
          child: Stack(
            children: [
              // Background
              Opacity(
                opacity: _backgroundFade.value,
                child: Container(
                  color: AppTheme.background.withValues(alpha: 0.95),
                ),
              ),

              // Particles (rank up only)
              if (_isRankUp)
                ..._buildParticles(newRankColor),

              // Main content
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Title
                    FadeTransition(
                      opacity: _textFade,
                      child: Text(
                        _isRankUp
                            ? l10n.rankUp.toUpperCase()
                            : l10n.rankDown.toUpperCase(),
                        style: TextStyle(
                          color: _isRankUp ? newRankColor : AppTheme.error,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 6,
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Old rank badge
                    Opacity(
                      opacity: _oldRankFade.value,
                      child: Transform.scale(
                        scale: _oldRankScale.value,
                        child: Column(
                          children: [
                            SizedBox(
                              width: 80,
                              height: 80,
                              child: RankUtils.getRankBadge(
                                  widget.oldRank, size: 80),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              widget.oldRank.toUpperCase(),
                              style: TextStyle(
                                color: RankChangeOverlay.getRankColor(
                                    widget.oldRank),
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Arrow
                    Opacity(
                      opacity: _arrowFade.value,
                      child: Transform.translate(
                        offset: Offset(
                            0, _isRankUp ? -_arrowSlide.value : _arrowSlide.value),
                        child: Icon(
                          _isRankUp
                              ? Icons.keyboard_double_arrow_up
                              : Icons.keyboard_double_arrow_down,
                          color: _isRankUp ? newRankColor : AppTheme.error,
                          size: 40,
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // New rank badge with glow
                    Opacity(
                      opacity: _newRankFade.value,
                      child: Transform.scale(
                        scale: _newRankScale.value,
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: newRankColor
                                    .withValues(alpha: _glowPulse.value * 0.5),
                                blurRadius: 50,
                                spreadRadius: 15,
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              SizedBox(
                                width: 120,
                                height: 120,
                                child: RankUtils.getRankBadge(
                                    widget.newRank, size: 120),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                widget.newRank.toUpperCase(),
                                style: TextStyle(
                                  color: newRankColor,
                                  fontSize: 28,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 48),

                    // Continue button
                    FadeTransition(
                      opacity: _buttonFade,
                      child: SizedBox(
                        width: 200,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: widget.onDismiss,
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                _isRankUp ? newRankColor : AppTheme.primary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: Text(
                            l10n.continuePlaying,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: 1,
                            ),
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

  List<Widget> _buildParticles(Color color) {
    final random = Random(42); // Fixed seed for deterministic layout
    return List.generate(20, (i) {
      final startX = random.nextDouble() * 400 - 200;
      final startY = random.nextDouble() * 200 + 100;
      final size = random.nextDouble() * 6 + 2;
      final speed = random.nextDouble() * 0.5 + 0.5;

      return Positioned(
        left: MediaQuery.of(context).size.width / 2 + startX,
        bottom: _particleController.value * startY * speed,
        child: Opacity(
          opacity: (1 - _particleController.value).clamp(0, 1),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.8),
              shape: BoxShape.circle,
            ),
          ),
        ),
      );
    });
  }
}
