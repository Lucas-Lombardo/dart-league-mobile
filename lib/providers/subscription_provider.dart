import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/iap_service.dart';
import '../services/subscription_service.dart';

class SubscriptionProvider with ChangeNotifier {
  SubscriptionProvider() {
    if (Platform.isIOS) {
      _iapEventsSub = IapService.instance.events.listen(_onIapEvent);
    }
  }

  static const _appleManageSubscriptionUrl =
      'https://apps.apple.com/account/subscriptions';

  bool _isPremium = false;
  DateTime? _premiumExpiresAt;
  int? _matchesRemainingToday;
  int? _dailyLimit;
  bool _isLoading = false;
  String? _errorMessage;

  StreamSubscription<IapEvent>? _iapEventsSub;

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

  /// Starts checkout for the given plan. On iOS, triggers the native Apple
  /// purchase sheet via StoreKit. On other platforms, opens Stripe Checkout
  /// in the system browser. Returns true if the request was successfully
  /// initiated.
  Future<bool> startCheckout(SubscriptionPlan plan) async {
    _errorMessage = null;
    notifyListeners();

    if (Platform.isIOS) {
      try {
        return await IapService.instance.buy(plan);
      } catch (e) {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
        notifyListeners();
        return false;
      }
    }

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

  /// On iOS, deep-links to Apple's subscription management screen. On other
  /// platforms, opens the Stripe Billing Portal in the system browser.
  Future<bool> openManageSubscription() async {
    _errorMessage = null;
    notifyListeners();

    if (Platform.isIOS) {
      final uri = Uri.parse(_appleManageSubscriptionUrl);
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        _errorMessage = 'Could not open the App Store subscriptions page';
        notifyListeners();
        return false;
      }
      return true;
    }

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

  /// Returned by [restorePurchases].
  ///
  /// - [RestoreOutcome.restored] — restored at least one active subscription.
  /// - [RestoreOutcome.nothingToRestore] — restore completed but the account
  ///   had no purchases tied to it.
  /// - [RestoreOutcome.failed] — the restore call itself failed; [errorMessage]
  ///   contains the reason.
  /// - [RestoreOutcome.notSupported] — current platform doesn't support IAP
  ///   restore (e.g. Android keeps purchases tied to the Google account).
  Future<RestoreOutcome> restorePurchases() async {
    _errorMessage = null;
    notifyListeners();

    if (!Platform.isIOS) {
      return RestoreOutcome.notSupported;
    }

    final wasPremium = isPremiumActive;
    try {
      await IapService.instance.restorePurchases();
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
      return RestoreOutcome.failed;
    }

    // Give the backend a moment to process the JWS, then re-fetch status.
    await Future<void>.delayed(const Duration(milliseconds: 800));
    await refresh();

    if (isPremiumActive && !wasPremium) {
      return RestoreOutcome.restored;
    }
    if (isPremiumActive) {
      // Already premium before restore — treat as a successful no-op.
      return RestoreOutcome.restored;
    }
    return RestoreOutcome.nothingToRestore;
  }

  void _onIapEvent(IapEvent event) {
    switch (event.type) {
      case IapEventType.success:
        // Apple confirmed and backend was updated — pick up the new state.
        refresh();
        break;
      case IapEventType.canceled:
        // User dismissed the purchase sheet. No state change.
        break;
      case IapEventType.error:
        _errorMessage = event.message;
        notifyListeners();
        break;
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

  @override
  void dispose() {
    _iapEventsSub?.cancel();
    super.dispose();
  }
}

enum RestoreOutcome { restored, nothingToRestore, failed, notSupported }
