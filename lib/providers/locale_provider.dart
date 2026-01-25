import 'package:flutter/material.dart';
import '../utils/storage_service.dart';
import '../services/user_service.dart';

class LocaleProvider extends ChangeNotifier {
  Locale _locale = const Locale('en');

  Locale get locale => _locale;

  LocaleProvider() {
    _loadLocale();
  }

  Future<void> _loadLocale() async {
    final languageCode = await StorageService.getLanguage();
    if (languageCode != null) {
      _locale = Locale(languageCode);
      notifyListeners();
    }
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
      print('Failed to update language on backend: $e');
    }
  }

  void setLocaleFromUser(String languageCode) {
    _locale = Locale(languageCode);
    notifyListeners();
  }
}
