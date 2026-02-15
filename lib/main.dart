import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:firebase_core/firebase_core.dart';
import 'providers/auth_provider.dart';
import 'providers/matchmaking_provider.dart';
import 'providers/game_provider.dart';
import 'providers/friends_provider.dart';
import 'providers/locale_provider.dart';
import 'providers/tournament_provider.dart';
import 'providers/placement_provider.dart';
import 'l10n/app_localizations.dart';
import 'screens/splash_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/home_screen.dart';
import 'utils/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Firebase (skip on web — no FirebaseOptions configured)
  if (!kIsWeb) {
    try {
      await Firebase.initializeApp();
    } catch (e) {
      debugPrint('⚠️ Firebase init failed (push notifications disabled): $e');
    }
  }
  
  // Lock orientation to portrait mode only
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  
  // Create GameProvider eagerly at app startup so listeners are ready
  final gameProvider = GameProvider();
  
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
        ChangeNotifierProxyProvider<LocaleProvider, AuthProvider>(
          create: (context) {
            final authProvider = AuthProvider();
            authProvider.setLocaleProvider(
              Provider.of<LocaleProvider>(context, listen: false),
            );
            return authProvider;
          },
          update: (context, localeProvider, authProvider) {
            authProvider!.setLocaleProvider(localeProvider);
            return authProvider;
          },
        ),
        ChangeNotifierProvider(create: (_) => MatchmakingProvider()),
        ChangeNotifierProvider.value(value: gameProvider),
        ChangeNotifierProvider(create: (_) => FriendsProvider()),
        ChangeNotifierProvider(create: (_) => TournamentProvider()),
        ChangeNotifierProvider(create: (_) => PlacementProvider()),
      ],
      child: Consumer<LocaleProvider>(
        builder: (context, localeProvider, child) {
          return MaterialApp(
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
            initialRoute: '/',
            routes: {
              '/': (context) => const SplashScreen(),
              '/login': (context) => const LoginScreen(),
              '/register': (context) => const RegisterScreen(),
              '/home': (context) => const HomeScreen(),
            },
          );
        },
      ),
    );
  }
}
