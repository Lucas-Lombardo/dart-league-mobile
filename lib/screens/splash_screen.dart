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
/// fading in, a small primary spinner in the bottom third. Routes to home or
/// login once the session is checked (same timing as before).
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

    // Just enough for the logo entrance to land — the spinner covers any
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
/// tagline as a caption, a 22 px primary ring in the bottom third. The
/// entrance (scale 0.72 → 1 + fade) follows [entrance]; null = landed.
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
        Align(
          alignment: const Alignment(0, 0.62),
          child: FadeTransition(
            opacity: fade,
            child: const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: AppTheme.primary,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
