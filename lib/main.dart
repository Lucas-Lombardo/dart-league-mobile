import 'dart:async' show unawaited;
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'services/iap_service.dart';
import 'providers/auth_provider.dart';
import 'providers/matchmaking_provider.dart';
import 'providers/game_provider.dart';
import 'providers/friends_provider.dart';
import 'providers/locale_provider.dart';
import 'providers/tournament_provider.dart';
import 'providers/placement_provider.dart';
import 'providers/tournament_game_provider.dart';
import 'providers/presence_provider.dart';
import 'providers/subscription_provider.dart';
import 'providers/match_invite_provider.dart';
import 'providers/app_update_provider.dart';
import 'providers/chat_provider.dart';
import 'providers/referral_provider.dart';
import 'providers/season_provider.dart';
import 'l10n/app_localizations.dart';
import 'screens/splash_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/auth/forgot_password_screen.dart';
import 'screens/home_screen.dart';
import 'dev/delegate_bench.dart';
import 'services/api_service.dart';
import 'utils/storage_service.dart';
import 'services/dataset_capture_service.dart';
import 'services/meta_events_service.dart';
import 'services/model_selector.dart';
import 'utils/app_audio_context.dart';
import 'utils/app_navigator.dart';
import 'utils/app_theme.dart';
import 'utils/dart_caller_service.dart';
import 'utils/dart_sound_service.dart';
import 'utils/haptic_service.dart';
import 'widgets/matchmaking_navigation_gate.dart';
import 'widgets/friend_match_gate.dart';
import 'widgets/tournament_invite_gate.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final RouteObserver<ModalRoute<void>> routeObserver = RouteObserver<ModalRoute<void>>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Dev-only TFLite delegate bench (see lib/dev/delegate_bench.dart) —
  // compiled out unless launched with --dart-define=DELEGATE_BENCH=true.
  if (const bool.fromEnvironment('DELEGATE_BENCH')) {
    unawaited(DelegateBench.run());
  }

  // Context-free navigation (push-tap deep links) goes through this key.
  AppNavigator.navigatorKey = navigatorKey;
  
  // Initialize Firebase (skip on web — no FirebaseOptions configured)
  if (!kIsWeb) {
    try {
      await Firebase.initializeApp();
    } catch (e) {
      debugPrint('⚠️ Firebase init failed (push notifications disabled): $e');
    }
  }
  
  // Meta (Facebook) App Events — install/session attribution for the paid ad
  // campaigns. Guarded like Firebase above: analytics must never block boot.
  // The iOS ATT prompt is NOT asked here (see HomeScreen).
  await MetaEventsService.init();

  // Initialize Stripe (skip on web - not supported)
  if (!kIsWeb) {
    const stripeKey = String.fromEnvironment(
      'STRIPE_PUBLISHABLE_KEY',
      defaultValue: 'pk_test_51T1nHARtbfZQ2kA2avIkK0pLCQMnzU7JESQRCt4SGB1wCfJqMjjv8GZC1iUz5DdJtYtxhCt75XZuy2KfdFjRhZ5q00e8zVgNFX',
    );
    Stripe.publishableKey = stripeKey;
    Stripe.urlScheme = 'dartrivals';
    await Stripe.instance.applySettings();
  }

  // Initialize Apple In-App Purchase (iOS only). Failure here must not block
  // app startup — the paywall will show fallback pricing if products
  // don't load.
  if (!kIsWeb && Platform.isIOS) {
    try {
      await IapService.instance.init();
    } catch (e) {
      debugPrint('⚠️ IapService init failed: $e');
    }
  }
  
  // Lock orientation to portrait mode only
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  
  // Pick the AI model for this device (heavy on capable phones, small on the
  // rest) before anything can call loadModel. Self-guarded: a failed probe
  // keeps small, which runs everywhere. On Android "capable" is measured by
  // a background heavy-model run that init() kicks off (once per app
  // version); the first real model load waits for it.
  await ModelSelector.init();

  // Load the sound & haptics preferences so they're ready before any match.
  // Guarded like the Firebase/IAP inits above: these read flutter_secure_
  // storage, which throws a PlatformException on a corrupted Android keystore
  // (and after some backup restores). Unguarded, it aborted startup before
  // runApp — the whole app failed to boot over a caller preference. On
  // failure everything stays at its default (enabled).
  try {
    await DartCallerService.loadPreference();
    await DartSoundService.loadPreferences();
    await HapticService.loadPreference();
    await DatasetCaptureService.loadPreference();
  } catch (e) {
    debugPrint('⚠️ Sound preferences load failed: $e');
  }
  // Android: make the app's audioplayers context the plugin default BEFORE
  // any AudioPlayer exists, so no sound loading mid-match can reset the
  // phone's speakerphone underneath the WebRTC call (see AppAudioContext).
  try {
    await AppAudioContext.install();
  } catch (e) {
    debugPrint('⚠️ Audio context install failed: $e');
  }

  // Create GameProvider eagerly at app startup so listeners are ready
  final gameProvider = GameProvider();

  // A keychain write that fails is retried by StorageService; the line in
  // the server log is what lets us see it happen on a player's phone.
  StorageService.onPersistFailure = (key, error) {
    ApiService.reportClientEvent('storage.write_failed', '$key: $error');
  };

  // A session the server rejected waits for the current match to finish
  // before the app signs out: the match screen forfeits when it is left.
  ApiService.isMatchLive = () {
    if (gameProvider.gameStarted && !gameProvider.gameEnded) return true;
    if (gameProvider.isRankedSeries && !gameProvider.seriesEnded) return true;
    final context = navigatorKey.currentContext;
    if (context == null) return false;
    try {
      final tournament = context.read<TournamentGameProvider>();
      if (tournament.gameStarted && !tournament.gameEnded) return true;
      if (tournament.tournamentMatchId != null &&
          tournament.seriesWinnerId == null) {
        return true;
      }
    } catch (_) {
      // Provider tree not built yet.
    }
    return false;
  };

  // When the session is definitely gone, drop the signed-in state and show
  // the login form (e-mail prefilled).
  ApiService.onAuthFailure = () {
    final context = navigatorKey.currentContext;
    if (context != null) {
      try {
        context.read<AuthProvider>().handleSessionLost();
      } catch (_) {
        // Provider tree not built yet.
      }
    }
    navigatorKey.currentState?.pushNamedAndRemoveUntil('/login', (_) => false);
  };

  runApp(DartLegendsApp(gameProvider: gameProvider));
}

class DartLegendsApp extends StatelessWidget {
  final GameProvider gameProvider;
  
  const DartLegendsApp({super.key, required this.gameProvider});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LocaleProvider()),
        ChangeNotifierProvider(create: (_) => SubscriptionProvider()),
        ChangeNotifierProvider(create: (_) => PresenceProvider()),
        ChangeNotifierProxyProvider3<LocaleProvider, SubscriptionProvider, PresenceProvider, AuthProvider>(
          create: (context) {
            final authProvider = AuthProvider();
            authProvider.setLocaleProvider(
              Provider.of<LocaleProvider>(context, listen: false),
            );
            authProvider.setSubscriptionProvider(
              Provider.of<SubscriptionProvider>(context, listen: false),
            );
            authProvider.setPresenceProvider(
              Provider.of<PresenceProvider>(context, listen: false),
            );
            return authProvider;
          },
          update: (context, localeProvider, subscriptionProvider, presenceProvider, authProvider) {
            authProvider!.setLocaleProvider(localeProvider);
            authProvider.setSubscriptionProvider(subscriptionProvider);
            authProvider.setPresenceProvider(presenceProvider);
            return authProvider;
          },
        ),
        ChangeNotifierProvider(create: (_) => MatchmakingProvider()),
        ChangeNotifierProvider.value(value: gameProvider),
        ChangeNotifierProvider(create: (_) => FriendsProvider()),
        ChangeNotifierProvider(create: (_) => TournamentProvider()),
        ChangeNotifierProvider(create: (_) => PlacementProvider()),
        ChangeNotifierProvider(create: (_) => TournamentGameProvider()),
        ChangeNotifierProvider(create: (_) => MatchInviteProvider()),
        ChangeNotifierProvider(create: (_) => AppUpdateProvider()),
        ChangeNotifierProvider(create: (_) => ChatProvider()),
        ChangeNotifierProvider(create: (_) => ReferralProvider()),
        ChangeNotifierProvider(create: (_) => SeasonProvider()),
      ],
      child: Consumer<LocaleProvider>(
        builder: (context, localeProvider, child) {
          return MaterialApp(
            navigatorKey: navigatorKey,
            key: ValueKey(localeProvider.locale.languageCode),
            title: 'Dart Legends',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.themeData,
            locale: localeProvider.locale,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            navigatorObservers: [routeObserver],
            // Les réglages système « texte plus grand » (iOS/Android) font
            // exploser toutes les mises en page (pseudos tronqués, lignes
            // rognées) : on borne l'agrandissement à 1,1× — le texte grossit
            // un peu, rien ne casse.
            builder: (context, child) {
              final media = MediaQuery.of(context);
              return MediaQuery(
                data: media.copyWith(
                  textScaler: media.textScaler.clamp(maxScaleFactor: 1.1),
                ),
                child: MatchmakingNavigationGate(
                  navigatorKey: navigatorKey,
                  child: FriendMatchGate(
                    navigatorKey: navigatorKey,
                    child: TournamentInviteGate(
                      navigatorKey: navigatorKey,
                      child: child ?? const SizedBox.shrink(),
                    ),
                  ),
                ),
              );
            },
            initialRoute: '/',
            routes: {
              '/': (context) => const SplashScreen(),
              '/login': (context) => const LoginScreen(),
              '/register': (context) => const RegisterScreen(),
              '/home': (context) => const HomeScreen(),
              '/forgot-password': (context) => const ForgotPasswordScreen(),
            },
          );
        },
      ),
    );
  }
}
