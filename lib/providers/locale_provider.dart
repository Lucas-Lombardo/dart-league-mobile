import 'package:flutter/material.dart';
import '../utils/storage_service.dart';
import '../services/user_service.dart';

class LocaleProvider extends ChangeNotifier {
  Locale _locale = const Locale('en');

  Locale get locale => _locale;

  LocaleProvider() {
    _loadLocale();
  }

  bool _disposed = false;

  Future<void> _loadLocale() async {
    final savedLanguageCode = await StorageService.getLanguage();

    if (savedLanguageCode != null) {
      _locale = Locale(savedLanguageCode);
    } else {
      final deviceLocale = WidgetsBinding.instance.platformDispatcher.locale;
      final deviceLanguageCode = deviceLocale.languageCode;

      if (['en', 'fr'].contains(deviceLanguageCode)) {
        _locale = Locale(deviceLanguageCode);
        await StorageService.saveLanguage(deviceLanguageCode);
      } else {
        _locale = const Locale('en');
        await StorageService.saveLanguage('en');
      }
    }
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
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
