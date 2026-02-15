import 'package:flutter/foundation.dart';
import '../models/user.dart';
import '../services/auth_service.dart';
import '../services/push_notification_service.dart';
import '../utils/error_messages.dart';
import 'locale_provider.dart';

class AuthProvider extends ChangeNotifier {
  User? _currentUser;
  bool _isLoading = false;
  String? _errorMessage;
  LocaleProvider? _localeProvider;

  User? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isAuthenticated => _currentUser != null;

  void setLocaleProvider(LocaleProvider localeProvider) {
    _localeProvider = localeProvider;
  }

  Future<void> checkAuthStatus() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final user = await AuthService.getCurrentUser();
      _currentUser = user;
      if (user != null && _localeProvider != null) {
        _localeProvider!.setLocaleFromUser(user.language);
      }
    } catch (e) {
      _currentUser = null;
      _errorMessage = ErrorMessages.getUserFriendlyMessage(e.toString());
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> register({
    required String username,
    required String email,
    required String password,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final result = await AuthService.register(
        username: username,
        email: email,
        password: password,
      );
      _currentUser = result['user'];
      if (_currentUser != null && _localeProvider != null) {
        _localeProvider!.setLocaleFromUser(_currentUser!.language);
      }
      // Register push notification token
      await PushNotificationService.initialize();
      await PushNotificationService.registerToken();
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = ErrorMessages.getUserFriendlyMessage(e.toString());
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> login({
    required String email,
    required String password,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final result = await AuthService.login(
        email: email,
        password: password,
      );
      _currentUser = result['user'];
      if (_currentUser != null && _localeProvider != null) {
        _localeProvider!.setLocaleFromUser(_currentUser!.language);
      }
      // Register push notification token
      await PushNotificationService.initialize();
      await PushNotificationService.registerToken();
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = ErrorMessages.getUserFriendlyMessage(e.toString());
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    _isLoading = true;
    notifyListeners();

    try {
      await PushNotificationService.unregisterToken();
      await AuthService.logout();
      _currentUser = null;
      _errorMessage = null;
    } catch (e) {
      _errorMessage = ErrorMessages.getUserFriendlyMessage(e.toString());
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> deleteAccount() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await AuthService.deleteAccount();
      _currentUser = null;
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = ErrorMessages.getUserFriendlyMessage(e.toString());
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> forgotPassword({required String email}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await AuthService.forgotPassword(email: email);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = ErrorMessages.getUserFriendlyMessage(e.toString());
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> resendVerification() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await AuthService.resendVerification();
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = ErrorMessages.getUserFriendlyMessage(e.toString());
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  void updateUserFromJson(Map<String, dynamic> json) {
    try {
      _currentUser = User.fromJson(json);
      notifyListeners();
    } catch (_) {
      // JSON parsing failed, keep current user
    }
  }
}
