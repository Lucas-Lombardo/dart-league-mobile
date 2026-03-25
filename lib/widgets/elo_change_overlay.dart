import 'dart:math';
import 'package:flutter/material.dart';
import '../utils/app_theme.dart';
import '../utils/haptic_service.dart';
import '../l10n/app_localizations.dart';

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
  late final AnimationController _pulseController;
  late final AnimationController _particleController;

  late final Animation<double> _backgroundFade;
  late final Animation<double> _iconScale;
  late final Animation<double> _iconFade;
  late final Animation<double> _titleFade;
  late final Animation<double> _barFade;
  late final Animation<double> _barProgress;
  late final Animation<double> _numberFade;
  late final Animation<double> _messageFade;
  late final Animation<double> _buttonFade;
  late final Animation<double> _glowPulse;

  @override
  void initState() {
    super.initState();

    // Main entrance sequence: 2s
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );

    // Bar fill animation: 1.5s, starts after entrance
    _barController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    // Glow pulse
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    // Particles (win only)
    _particleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    );

    // Staggered entrance
    _backgroundFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0, 0.15, curve: Curves.easeOut),
      ),
    );

    _iconScale = Tween<double>(begin: 0.3, end: 1).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.1, 0.35, curve: Curves.elasticOut),
      ),
    );

    _iconFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.1, 0.25, curve: Curves.easeOut),
      ),
    );

    _titleFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.25, 0.4, curve: Curves.easeOut),
      ),
    );

    _barFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.35, 0.5, curve: Curves.easeOut),
      ),
    );

    _numberFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.45, 0.6, curve: Curves.easeOut),
      ),
    );

    _messageFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.7, 0.85, curve: Curves.easeOut),
      ),
    );

    _buttonFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.85, 1.0, curve: Curves.easeOut),
      ),
    );

    _barProgress = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _barController,
        curve: Curves.easeInOut,
      ),
    );

    _glowPulse = Tween<double>(begin: 0.4, end: 1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _entranceController.forward();

    // Start bar animation after the bar fades in
    Future.delayed(const Duration(milliseconds: 1000), () {
      if (mounted) _barController.forward();
    });

    _pulseController.repeat(reverse: true);
    if (widget.isWin) _particleController.repeat();

    // Haptic when bar starts filling
    Future.delayed(const Duration(milliseconds: 1000), () {
      if (mounted) HapticService.mediumImpact();
    });

    // Haptic when bar finishes
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted) HapticService.heavyImpact();
    });
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _barController.dispose();
    _pulseController.dispose();
    _particleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.isWin ? AppTheme.success : AppTheme.error;
    final eloChange = widget.newElo - widget.oldElo;
    final l10n = AppLocalizations.of(context);

    return AnimatedBuilder(
      animation: Listenable.merge([
        _entranceController,
        _barController,
        _pulseController,
        _particleController,
      ]),
      builder: (context, _) {
        final currentElo =
            (widget.oldElo + (eloChange * _barProgress.value)).round();

        return Material(
          color: Colors.transparent,
          child: Stack(
            children: [
              // Background
              Opacity(
                opacity: _backgroundFade.value,
                child: Container(
                  color: AppTheme.background.withValues(alpha: 0.97),
                ),
              ),

              // Particles (win only)
              if (widget.isWin) ..._buildParticles(color),

              // Main content
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Icon
                      Opacity(
                        opacity: _iconFade.value,
                        child: Transform.scale(
                          scale: _iconScale.value,
                          child: Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: color.withValues(
                                      alpha: _glowPulse.value * 0.3),
                                  blurRadius: 40,
                                  spreadRadius: 8,
                                ),
                              ],
                            ),
                            child: Icon(
                              widget.isWin
                                  ? Icons.emoji_events
                                  : Icons.trending_down,
                              color: color,
                              size: 56,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Title
                      FadeTransition(
                        opacity: _titleFade,
                        child: Text(
                          widget.isWin
                              ? l10n.victory.toUpperCase()
                              : l10n.defeat.toUpperCase(),
                          style: AppTheme.displayLarge.copyWith(
                            color: color,
                            fontSize: 36,
                            letterSpacing: 4,
                          ),
                        ),
                      ),

                      const SizedBox(height: 40),

                      // ELO progress bar section
                      FadeTransition(
                        opacity: _barFade,
                        child: Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: AppTheme.surface,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: color.withValues(alpha: 0.3),
                              width: 1,
                            ),
                          ),
                          child: Column(
                            children: [
                              // ELO label
                              Text(
                                l10n.eloChange.toUpperCase(),
                                style: TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 3,
                                ),
                              ),

                              const SizedBox(height: 16),

                              // Animated ELO number
                              FadeTransition(
                                opacity: _numberFade,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      '$currentElo',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 48,
                                        fontWeight: FontWeight.w900,
                                        fontFeatures: const [
                                          FontFeature.tabularFigures()
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: color.withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        '${eloChange >= 0 ? '+' : ''}$eloChange',
                                        style: TextStyle(
                                          color: color,
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 20),

                              // Progress bar
                              _buildProgressBar(color),

                              const SizedBox(height: 8),

                              // Old -> New labels
                              FadeTransition(
                                opacity: _numberFade,
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      '${widget.oldElo}',
                                      style: TextStyle(
                                        color: AppTheme.textSecondary,
                                        fontSize: 13,
                                        fontFeatures: const [
                                          FontFeature.tabularFigures()
                                        ],
                                      ),
                                    ),
                                    Text(
                                      '${widget.newElo}',
                                      style: TextStyle(
                                        color: color,
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        fontFeatures: const [
                                          FontFeature.tabularFigures()
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Motivational message
                      FadeTransition(
                        opacity: _messageFade,
                        child: Text(
                          widget.isWin ? l10n.provenLegend : l10n.trainingPath,
                          style: AppTheme.bodyLarge.copyWith(fontSize: 15),
                          textAlign: TextAlign.center,
                        ),
                      ),

                      const SizedBox(height: 32),

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
                                  widget.isWin ? color : AppTheme.primary,
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
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildProgressBar(Color color) {
    // Bar shows movement from old elo position to new elo position
    // We use a range around the old elo to make the bar visually meaningful
    final eloChange = widget.newElo - widget.oldElo;
    final range = (eloChange.abs() * 4).clamp(100, 500);
    final barMin = widget.oldElo - (widget.isWin ? range ~/ 4 : range * 3 ~/ 4);
    final barMax = barMin + range;

    final oldFraction =
        ((widget.oldElo - barMin) / (barMax - barMin)).clamp(0.0, 1.0);
    final newFraction =
        ((widget.newElo - barMin) / (barMax - barMin)).clamp(0.0, 1.0);

    final currentFraction =
        oldFraction + (newFraction - oldFraction) * _barProgress.value;

    return SizedBox(
      height: 12,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Stack(
          children: [
            // Track
            Container(
              decoration: BoxDecoration(
                color: AppTheme.surfaceLight.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            // Fill
            FractionallySizedBox(
              widthFactor: currentFraction,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: widget.isWin
                        ? [color.withValues(alpha: 0.6), color]
                        : [color, color.withValues(alpha: 0.6)],
                  ),
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: _glowPulse.value * 0.5),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildParticles(Color color) {
    final random = Random(42);
    return List.generate(15, (i) {
      final startX = random.nextDouble() * 300 - 150;
      final startY = random.nextDouble() * 200 + 80;
      final size = random.nextDouble() * 5 + 2;
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
              color: color.withValues(alpha: 0.7),
              shape: BoxShape.circle,
            ),
          ),
        ),
      );
    });
  }
}
