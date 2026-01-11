import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/auth_provider.dart';
import 'providers/matchmaking_provider.dart';
import 'providers/game_provider.dart';
import 'screens/splash_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/home_screen.dart';
import 'utils/app_theme.dart';

void main() {
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
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => MatchmakingProvider()),
        ChangeNotifierProvider.value(value: gameProvider), // Use pre-created instance
      ],
      child: MaterialApp(
        title: 'Dart Legends',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.themeData,
        initialRoute: '/',
        routes: {
          '/': (context) => const SplashScreen(),
          '/login': (context) => const LoginScreen(),
          '/register': (context) => const RegisterScreen(),
          '/home': (context) => const HomeScreen(),
        },
      ),
    );
  }
}
