import 'package:flutter/material.dart';

/// Centralized navigation helper that standardizes navigation patterns.
///
/// Navigation strategy:
/// - [toAuth]: Named route replacement for auth flow (login, register, etc.)
/// - [toHome]: Clear entire stack and go to home (after game completion, logout)
/// - [toScreen]: Standard push for detail/nested screens
/// - [replaceWith]: Replace current screen (camera setup -> game flow)
/// - [back]: Pop current screen with optional result
class AppNavigator {
  AppNavigator._();

  /// Navigate within auth flow using named route replacement.
  /// Used for: splash -> home/login, login -> home, register -> home, etc.
  static void toAuth(BuildContext context, String routeName) {
    Navigator.pushReplacementNamed(context, routeName);
  }

  /// Clear stack and navigate to named route.
  /// Used for: returning to home after game/tournament, logout -> login.
  static void toHomeClearing(BuildContext context) {
    Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
  }

  /// Clear stack and navigate to login.
  /// Used for: logout, session expiry.
  static void toLoginClearing(BuildContext context) {
    Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
  }

  /// Push a new screen onto the stack.
  /// Used for: detail screens, settings, nested navigation.
  static Future<T?> toScreen<T>(BuildContext context, Widget screen) {
    return Navigator.push<T>(
      context,
      MaterialPageRoute(builder: (context) => screen),
    );
  }

  /// Replace current screen with a new one (no back navigation).
  /// Used for: camera setup -> matchmaking/game, tournament flow transitions.
  static void replaceWith(BuildContext context, Widget screen) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (context) => screen),
    );
  }

  /// Pop current screen with optional result.
  static void back<T>(BuildContext context, [T? result]) {
    Navigator.pop(context, result);
  }
}
