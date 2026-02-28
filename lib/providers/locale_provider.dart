import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import '../utils/storage_service.dart';
import '../services/user_service.dart';

class LocaleProvider extends ChangeNotifier {
  Locale _locale = const Locale('en');

  Locale get locale => _locale;

  LocaleProvider() {
    _loadLocale();
  }

  Future<void> _loadLocale() async {
    final savedLanguageCode = await StorageService.getLanguage();
    
    if (savedLanguageCode != null) {
      // Use saved preference if available
      _locale = Locale(savedLanguageCode);
      debugPrint('🌍 Loaded saved language: $savedLanguageCode');
    } else {
      // Detect device locale and use if supported
      final deviceLocale = WidgetsBinding.instance.platformDispatcher.locale;
      final deviceLanguageCode = deviceLocale.languageCode;
      
      if (['en', 'fr'].contains(deviceLanguageCode)) {
        _locale = Locale(deviceLanguageCode);
        debugPrint('🌍 Detected device language: $deviceLanguageCode');
        // Save the detected language
        await StorageService.saveLanguage(deviceLanguageCode);
      } else {
        // Default to English for unsupported languages
        _locale = const Locale('en');
        debugPrint('🌍 Device language "$deviceLanguageCode" not supported, defaulting to en');
        await StorageService.saveLanguage('en');
      }
    }
    notifyListeners();
  }

  Future<void> setLocale(String languageCode) async {
    _locale = Locale(languageCode);
    await StorageService.saveLanguage(languageCode);
    notifyListeners();
    
    // Update language on backend
    try {
      await UserService.updateLanguage(languageCode);
    } catch (e) {
      // If backend update fails, still keep the local change
      debugPrint('Failed to update language on backend: $e');
    }
  }

  void setLocaleFromUser(String languageCode) {
    _locale = Locale(languageCode);
    notifyListeners();
  }

  /// Get the current language code (useful for signup)
  String get languageCode => _locale.languageCode;
}
