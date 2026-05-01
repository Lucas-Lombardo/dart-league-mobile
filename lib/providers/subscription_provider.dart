import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/subscription_service.dart';

class SubscriptionProvider with ChangeNotifier {
  bool _isPremium = false;
  DateTime? _premiumExpiresAt;
  int? _matchesRemainingToday;
  int? _dailyLimit;
  bool _isLoading = false;
  String? _errorMessage;

  bool get isPremium => _isPremium;
  DateTime? get premiumExpiresAt => _premiumExpiresAt;
  int? get matchesRemainingToday => _matchesRemainingToday;
  int? get dailyLimit => _dailyLimit;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// True when the user is premium and not yet expired.
  bool get isPremiumActive {
    if (!_isPremium) return false;
    if (_premiumExpiresAt == null) return true;
    return _premiumExpiresAt!.isAfter(DateTime.now());
  }

  /// True for free users who have used their daily slot.
  bool get hasReachedDailyLimit {
    if (isPremiumActive) return false;
    final remaining = _matchesRemainingToday;
    return remaining != null && remaining <= 0;
  }

  Future<void> refresh() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final status = await SubscriptionService.getStatus();
      _isPremium = status.isPremium;
      _premiumExpiresAt = status.premiumExpiresAt;
      _matchesRemainingToday = status.matchesRemainingToday;
      _dailyLimit = status.dailyLimit;
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      debugPrint('SubscriptionProvider.refresh failed: $_errorMessage');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Starts checkout for the given plan. Opens Stripe Checkout in the
  /// system browser. Returns true if the launch succeeded.
  Future<bool> startCheckout(SubscriptionPlan plan) async {
    _errorMessage = null;
    notifyListeners();
    try {
      final urlString = await SubscriptionService.createCheckoutUrl(plan);
      final uri = Uri.parse(urlString);
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        _errorMessage = 'Could not open Stripe Checkout';
        notifyListeners();
        return false;
      }
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  /// Opens the Stripe Billing Portal for managing the subscription.
  Future<bool> openManageSubscription() async {
    _errorMessage = null;
    notifyListeners();
    try {
      final urlString = await SubscriptionService.createPortalUrl();
      final uri = Uri.parse(urlString);
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        _errorMessage = 'Could not open billing portal';
        notifyListeners();
        return false;
      }
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  /// Reset state on logout.
  void clear() {
    _isPremium = false;
    _premiumExpiresAt = null;
    _matchesRemainingToday = null;
    _dailyLimit = null;
    _errorMessage = null;
    _isLoading = false;
    notifyListeners();
  }
}
