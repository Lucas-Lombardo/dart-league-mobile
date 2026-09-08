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
import '../widgets/design_system.dart';

/// Launch screen: flat background, the shield, the wordmark and the tagline
/// fading in, the dart flying along its dashed trajectory in the bottom
/// third. Routes to home or login once the session is checked.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _entranceController;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _entranceController.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Respect the system reduced-motion setting: land immediately.
      if (MediaQuery.of(context).disableAnimations) {
        _entranceController.value = 1.0;
      }
      _checkAuthAndNavigate();
    });
  }

  @override
  void dispose() {
    _entranceController.dispose();
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
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SplashBody(entrance: _entranceController),
    );
  }
}

/// The splash visuals: 96 px shield, "DART RIVALS" 17 / 700 spaced, the
/// tagline as a caption, the flying dart in the bottom third. The entrance
/// (scale 0.72 → 1 + fade) follows [entrance]; null = landed.
class SplashBody extends StatelessWidget {
  final Animation<double>? entrance;

  const SplashBody({super.key, this.entrance});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final parent = entrance ?? kAlwaysCompleteAnimation;
    final scale = Tween<double>(begin: 0.72, end: 1.0).animate(
      CurvedAnimation(parent: parent, curve: Curves.easeOutBack),
    );
    final fade = CurvedAnimation(parent: parent, curve: Curves.easeIn);

    return Stack(
      children: [
        Center(
          child: ScaleTransition(
            scale: scale,
            child: FadeTransition(
              opacity: fade,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/logo/logo-without-letters.png',
                    width: 96,
                    height: 96,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'DART RIVALS',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.4,
                      color: AppTheme.textPrimary,
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      dsSentence(l10n.competeRankWin),
                      textAlign: TextAlign.center,
                      style: AppTheme.caption.copyWith(color: AppTheme.textTertiary),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 120,
          height: 40,
          child: FadeTransition(opacity: fade, child: const _DartFlight()),
        ),
      ],
    );
  }
}

/// The dart looping across the screen. Owns its own controller so the splash
/// body stays stateless; the loop is frozen mid-flight when the system asks
/// for reduced motion.
class _DartFlight extends StatefulWidget {
  const _DartFlight();

  @override
  State<_DartFlight> createState() => _DartFlightState();
}

class _DartFlightState extends State<_DartFlight> with SingleTickerProviderStateMixin {
  late final AnimationController _flight = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.of(context).disableAnimations) {
        _flight.value = 0.4;
      } else {
        _flight.repeat();
      }
    });
  }

  @override
  void dispose() {
    _flight.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _flight,
        builder: (context, _) => CustomPaint(
          painter: _FlightPathPainter(_flight.value),
        ),
      );
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
      dashPaint.color = AppTheme.primaryLight.withValues(alpha: 0.35 * edgeFade);
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
