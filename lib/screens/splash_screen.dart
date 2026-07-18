import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../providers/auth_provider.dart';
import '../providers/subscription_provider.dart';
import '../providers/app_update_provider.dart';
import '../services/push_notification_service.dart';
import '../utils/app_navigator.dart';
import '../utils/app_theme.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late AnimationController _entranceController;
  late AnimationController _flightController;
  late AnimationController _sweepController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _scaleAnimation = Tween<double>(begin: 0.72, end: 1.0).animate(
      CurvedAnimation(parent: _entranceController, curve: Curves.easeOutBack),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _entranceController, curve: Curves.easeIn),
    );

    _flightController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    );
    _sweepController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );

    _entranceController.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Respect the system reduced-motion setting: keep the loops still.
      if (!MediaQuery.of(context).disableAnimations) {
        _flightController.repeat();
        _sweepController.repeat();
      } else {
        _flightController.value = 0.4;
        _sweepController.value = 0.4;
      }
      _checkAuthAndNavigate();
    });
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _flightController.dispose();
    _sweepController.dispose();
    super.dispose();
  }

  Future<void> _checkAuthAndNavigate() async {
    // Fire-and-forget update check (non-blocking) so the home banner is ready
    // by the time we navigate. Runs before any await to avoid context-across-gap.
    unawaited(context.read<AppUpdateProvider>().check());

    final authProvider = context.read<AuthProvider>();
    await authProvider.checkAuthStatus();

    // Just enough for the logo entrance to land — the flight loop covers any
    // extra network wait, no need to make every launch pay a fixed 2s.
    await Future.delayed(const Duration(milliseconds: 800));

    if (mounted) {
      if (authProvider.isAuthenticated) {
        // Register push notification token for returning users
        await PushNotificationService.initialize();
        await PushNotificationService.registerToken();
        // Load subscription state for the authenticated user
        if (mounted) {
          unawaited(context.read<SubscriptionProvider>().refresh());
        }
        if (mounted) AppNavigator.toAuth(context, '/home');
      } else {
        AppNavigator.toAuth(context, '/login');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0B1120), AppTheme.background],
          ),
        ),
        child: Stack(
          children: [
            // Faint oversized target rings bleeding off the right edge.
            const Positioned.fill(
              child: CustomPaint(painter: _TargetRingsPainter()),
            ),
            Center(
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.asset(
                        'assets/logo/logo.png',
                        width: 220,
                        height: 220,
                        fit: BoxFit.contain,
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            l10n.competeRankWin,
                            style: TextStyle(
                              fontSize: 10.5,
                              letterSpacing: 3,
                              color: AppTheme.textSecondary.withValues(alpha: 0.75),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Dart flying along a dashed trajectory.
            Positioned(
              left: 0,
              right: 0,
              bottom: 120,
              height: 40,
              child: AnimatedBuilder(
                animation: _flightController,
                builder: (context, _) => CustomPaint(
                  painter: _FlightPathPainter(_flightController.value),
                ),
              ),
            ),
            // Thin indeterminate progress sweep hugging the bottom edge.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 3,
              child: AnimatedBuilder(
                animation: _sweepController,
                builder: (context, _) => CustomPaint(
                  painter: _SweepBarPainter(_sweepController.value),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TargetRingsPainter extends CustomPainter {
  const _TargetRingsPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(0xFF38BDF8).withValues(alpha: 0.07);
    final center = Offset(size.width + 60, size.height * 0.5);
    for (final radius in [170.0, 120.0, 70.0, 24.0]) {
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(_TargetRingsPainter oldDelegate) => false;
}

/// Dashed flight line + a dart crossing the screen left → right with a
/// slight arc and tilt, fading at both ends. [t] runs 0 → 1 per loop.
class _FlightPathPainter extends CustomPainter {
  final double t;

  const _FlightPathPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final midY = size.height / 2;

    // Dashed guide, faded at both edges.
    const dash = 8.0;
    const gap = 8.0;
    final dashPaint = Paint()..strokeWidth = 1.5;
    double x = 36;
    while (x < size.width - 36) {
      final edgeFade =
          ((x - 36) / (size.width * 0.15)).clamp(0.0, 1.0) *
          ((size.width - 36 - x) / (size.width * 0.15)).clamp(0.0, 1.0);
      dashPaint.color =
          const Color(0xFF38BDF8).withValues(alpha: 0.35 * edgeFade);
      canvas.drawLine(Offset(x, midY), Offset(x + dash, midY), dashPaint);
      x += dash + gap;
    }

    // Dart position: fade in/out at the extremes, gentle arc + tilt.
    final dartX = -40 + (size.width + 80) * t;
    final arc = -6 * (1 - (2 * t - 1) * (2 * t - 1)); // parabola, peak -6px
    final tilt = 0.07 - 0.14 * t; // ~+4° down to ~-4°
    final opacity = t < 0.08
        ? t / 0.08
        : t > 0.88
            ? (1 - t) / 0.12
            : 1.0;
    if (opacity <= 0) return;

    canvas.save();
    canvas.translate(dartX, midY + arc);
    canvas.rotate(tilt);
    _drawDart(canvas, opacity.clamp(0.0, 1.0));
    canvas.restore();
  }

  /// Draws a ~58×18 side-view dart centered on the origin, pointing right:
  /// blue flights, red shaft (echoing the logo), knurled steel barrel, needle.
  void _drawDart(Canvas canvas, double opacity) {
    canvas.translate(-29, -9);
    Color c(int argb, [double a = 1]) =>
        Color(argb).withValues(alpha: a * opacity);
    final fill = Paint();

    // Flights
    fill.color = c(0xFF7DD3FC);
    canvas.drawPath(
      Path()
        ..moveTo(13.5, 9)
        ..lineTo(3.5, 2.6)
        ..lineTo(2, 3.6)
        ..lineTo(6.6, 9)
        ..lineTo(2, 14.4)
        ..lineTo(3.5, 15.4)
        ..close(),
      fill,
    );
    fill.color = c(0xFF0EA5E9);
    canvas.drawPath(
      Path()
        ..moveTo(13.5, 9)
        ..lineTo(3.5, 2.6)
        ..lineTo(7.8, 9)
        ..lineTo(3.5, 15.4)
        ..close(),
      fill,
    );

    // Shaft
    fill.color = c(0xFFF43F5E);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          const Rect.fromLTWH(13, 7.9, 9.5, 2.2), const Radius.circular(1.1)),
      fill,
    );

    // Barrel + highlight + knurl ticks
    fill.color = c(0xFF94A3B8);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          const Rect.fromLTWH(22, 7.1, 13, 3.8), const Radius.circular(1.9)),
      fill,
    );
    fill.color = c(0xFFCBD5E1, 0.7);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          const Rect.fromLTWH(22, 7.1, 13, 1.5), const Radius.circular(0.75)),
      fill,
    );
    final tick = Paint()
      ..strokeWidth = 0.9
      ..color = c(0xFF475569);
    for (final tx in [24.5, 27.0, 29.5, 32.0]) {
      canvas.drawLine(Offset(tx, 6.9), Offset(tx, 11.1), tick);
    }

    // Taper cone + needle point
    fill.color = c(0xFF64748B);
    canvas.drawPath(
      Path()
        ..moveTo(35, 7.1)
        ..lineTo(40, 8.3)
        ..lineTo(40, 9.7)
        ..lineTo(35, 10.9)
        ..close(),
      fill,
    );
    fill.color = c(0xFFE2E8F0);
    canvas.drawPath(
      Path()
        ..moveTo(40, 8.3)
        ..lineTo(57, 8.8)
        ..lineTo(57, 9.2)
        ..lineTo(40, 9.7)
        ..close(),
      fill,
    );
  }

  @override
  bool shouldRepaint(_FlightPathPainter oldDelegate) => oldDelegate.t != t;
}

/// Indeterminate 3px progress sweep along the very bottom edge.
class _SweepBarPainter extends CustomPainter {
  final double t;

  const _SweepBarPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final track = Paint()
      ..color = const Color(0xFF334155).withValues(alpha: 0.5);
    canvas.drawRect(Offset.zero & size, track);

    final segWidth = size.width * 0.4;
    final left = -segWidth + (size.width + segWidth * 1.5) * t;
    final rect = Rect.fromLTWH(left, 0, segWidth, size.height);
    final seg = Paint()
      ..shader = const LinearGradient(
        colors: [Colors.transparent, AppTheme.primary, Color(0xFF38BDF8)],
      ).createShader(rect);
    canvas.drawRect(rect, seg);
  }

  @override
  bool shouldRepaint(_SweepBarPainter oldDelegate) => oldDelegate.t != t;
}
