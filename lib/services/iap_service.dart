import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'api_service.dart';
import 'subscription_service.dart';

class IapProductIds {
  static const String monthly = 'premium_monthly';
  static const String yearly = 'premium_yearly';
  static const Set<String> all = {monthly, yearly};
}

/// iOS-only singleton wrapping [InAppPurchase] for the App Store subscriptions.
/// On Android/web, [init] is a no-op and [buy] / [restorePurchases] throw.
class IapService {
  IapService._();
  static final IapService instance = IapService._();

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _subscription;

  final Map<String, ProductDetails> _products = {};
  bool _initialized = false;
  bool _storeAvailable = false;

  final ValueNotifier<bool> isProcessing = ValueNotifier<bool>(false);
  final StreamController<IapEvent> _events = StreamController<IapEvent>.broadcast();
  Stream<IapEvent> get events => _events.stream;

  bool get isInitialized => _initialized;
  bool get isStoreAvailable => _storeAvailable;

  ProductDetails? productFor(SubscriptionPlan plan) {
    return _products[_productIdFor(plan)];
  }

  /// Localized price string for the given plan (e.g. "€4,99"). Returns null
  /// when the product is unknown.
  String? priceFor(SubscriptionPlan plan) => productFor(plan)?.price;

  Future<void> init() async {
    if (_initialized) return;
    if (!Platform.isIOS) return;

    _storeAvailable = await _iap.isAvailable();
    if (!_storeAvailable) {
      debugPrint('IapService: store unavailable on this device');
      _initialized = true;
      return;
    }

    _subscription = _iap.purchaseStream.listen(
      _onPurchasesUpdated,
      onError: (Object error) {
        debugPrint('IapService: purchaseStream error: $error');
        _events.add(IapEvent.error(error.toString()));
      },
      onDone: () {
        _subscription?.cancel();
        _subscription = null;
      },
    );

    final response = await _iap.queryProductDetails(IapProductIds.all);
    if (response.error != null) {
      debugPrint('IapService: queryProductDetails error: ${response.error}');
    }
    if (response.notFoundIDs.isNotEmpty) {
      debugPrint('IapService: products not found: ${response.notFoundIDs}');
    }
    for (final product in response.productDetails) {
      _products[product.id] = product;
    }

    _initialized = true;
  }

  Future<bool> buy(SubscriptionPlan plan) async {
    if (!Platform.isIOS) {
      throw StateError('IapService.buy is iOS-only');
    }
    if (!_storeAvailable) {
      throw StateError('App Store is not available on this device');
    }
    final product = _products[_productIdFor(plan)];
    if (product == null) {
      throw StateError('Product not loaded: ${_productIdFor(plan)}');
    }

    isProcessing.value = true;
    try {
      final purchaseParam = PurchaseParam(productDetails: product);
      return await _iap.buyNonConsumable(purchaseParam: purchaseParam);
    } catch (e) {
      isProcessing.value = false;
      rethrow;
    }
  }

  /// Restores purchases for the current Apple ID. Results arrive via
  /// the purchase stream — the same flow as a fresh purchase.
  Future<void> restorePurchases() async {
    if (!Platform.isIOS) return;
    if (!_storeAvailable) {
      throw StateError('App Store is not available on this device');
    }
    isProcessing.value = true;
    await _iap.restorePurchases();
  }

  Future<void> _onPurchasesUpdated(List<PurchaseDetails> purchases) async {
    var sawSuccess = false;
    var sawError = false;
    String? lastError;

    for (final purchase in purchases) {
      switch (purchase.status) {
        case PurchaseStatus.pending:
          // Show spinner; nothing else to do.
          break;
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          try {
            await _verifyWithBackend(purchase);
            sawSuccess = true;
          } catch (e) {
            sawError = true;
            lastError = e.toString().replaceAll('Exception: ', '');
            debugPrint('IapService: backend verify failed: $e');
          }
          if (purchase.pendingCompletePurchase) {
            await _iap.completePurchase(purchase);
          }
          break;
        case PurchaseStatus.error:
          sawError = true;
          lastError = purchase.error?.message ?? 'Purchase failed';
          if (purchase.pendingCompletePurchase) {
            await _iap.completePurchase(purchase);
          }
          break;
        case PurchaseStatus.canceled:
          if (purchase.pendingCompletePurchase) {
            await _iap.completePurchase(purchase);
          }
          _events.add(const IapEvent.canceled());
          break;
      }
    }

    isProcessing.value = false;
    if (sawSuccess) {
      _events.add(const IapEvent.success());
    } else if (sawError) {
      _events.add(IapEvent.error(lastError ?? 'Purchase failed'));
    }
  }

  Future<void> _verifyWithBackend(PurchaseDetails purchase) async {
    await ApiService.post('/subscriptions/apple/verify', {
      'signedTransaction': purchase.verificationData.serverVerificationData,
    });
  }

  String _productIdFor(SubscriptionPlan plan) {
    switch (plan) {
      case SubscriptionPlan.monthly:
        return IapProductIds.monthly;
      case SubscriptionPlan.yearly:
        return IapProductIds.yearly;
    }
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
    await _events.close();
    isProcessing.dispose();
  }
}

enum IapEventType { success, canceled, error }

class IapEvent {
  final IapEventType type;
  final String? message;

  const IapEvent._(this.type, [this.message]);
  const IapEvent.success() : this._(IapEventType.success);
  const IapEvent.canceled() : this._(IapEventType.canceled);
  const IapEvent.error(String message) : this._(IapEventType.error, message);
}
