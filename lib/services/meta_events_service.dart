import 'dart:io' show Platform;

import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:facebook_app_events/facebook_app_events.dart';
import 'package:flutter/foundation.dart';

import 'subscription_service.dart' show SubscriptionPlan;

/// Meta (Facebook) App Events — the attribution layer behind the paid Meta
/// campaigns.
///
/// The SDK reports installs and sessions on its own. What it cannot guess is
/// what a player is worth, so the two events that matter are pushed by hand:
/// [logSignUp] (an install turned into an account) and [logSubscription] (an
/// account turned into money). Meta optimises delivery on those, which is the
/// whole point of paying for the ads.
///
/// Everything here is best-effort and self-guarded, like the Firebase and IAP
/// inits in `main.dart`: a dropped analytics event must never take down a
/// signup or a purchase.
class MetaEventsService {
  MetaEventsService._();

  static final FacebookAppEvents _fb = FacebookAppEvents();

  /// Stripe prices (Android / web checkout). Apple gives us the real localized
  /// amount through `ProductDetails`, so these are only used off iOS — they
  /// must stay in sync with the Stripe products and with the fallback prices
  /// shown on the paywall (`subscription_screen.dart`).
  static const double _stripeMonthlyPriceEur = 4.99;
  static const double _stripeYearlyPriceEur = 49.99;
  static const String _stripeCurrency = 'EUR';

  static bool _initialized = false;

  /// iOS ATT outcome for this install. Not supported (so never asked) on
  /// Android, where the advertising ID is governed by the system setting.
  static TrackingStatus _trackingStatus = TrackingStatus.notSupported;
  static TrackingStatus get trackingStatus => _trackingStatus;

  static bool get _supported =>
      !kIsWeb && (Platform.isIOS || Platform.isAndroid);

  /// Wires the SDK up. Called once from `main()`, before `runApp`.
  static Future<void> init() async {
    if (_initialized || !_supported) return;
    _initialized = true;
    try {
      // Installs, sessions and in-app purchase events the SDK detects itself.
      await _fb.setAutoLogAppEventsEnabled(true);
      // IDFA / GAID alongside the events. On iOS the SDK gates this on the ATT
      // answer by itself, so enabling it here is not a consent bypass — it
      // just means "use the id once you're allowed to".
      await _fb.setAdvertiserIdCollectionEnabled(true);
      // Lets the events show up live in Meta's Events Manager test console
      // while developing, and stays silent in release.
      await _fb.setDebugLoggingEnabled(kDebugMode);
    } catch (e) {
      debugPrint('⚠️ MetaEventsService init failed: $e');
    }
  }

  /// Shows Apple's tracking prompt, once per install.
  ///
  /// Deliberately NOT called from `main()`: fired on a cold first frame the
  /// prompt is dismissed by reflex. It is called from the authenticated home
  /// shell instead, once the user has seen what the app is.
  ///
  /// Without the authorization Meta only gets aggregated SKAdNetwork data, so
  /// this prompt is what keeps iOS campaign optimisation usable.
  static Future<void> requestTrackingConsent() async {
    if (!_supported || !Platform.isIOS) return;
    try {
      _trackingStatus = await AppTrackingTransparency.trackingAuthorizationStatus;
      if (_trackingStatus != TrackingStatus.notDetermined) return;
      // Apple drops the prompt if the app isn't fully active yet.
      await Future<void>.delayed(const Duration(milliseconds: 500));
      _trackingStatus = await AppTrackingTransparency.requestTrackingAuthorization();
      debugPrint('ATT status: $_trackingStatus');
    } catch (e) {
      debugPrint('⚠️ ATT request failed: $e');
    }
  }

  /// An install became an account — the top-of-funnel conversion Meta
  /// optimises on before there is enough purchase volume to optimise on money.
  static Future<void> logSignUp({String method = 'email'}) async {
    if (!_supported) return;
    try {
      await _fb.logCompletedRegistration(registrationMethod: method);
    } catch (e) {
      debugPrint('⚠️ Meta logSignUp failed: $e');
    }
  }

  /// The paywall sent the user to Apple's sheet or to Stripe Checkout. Not a
  /// conversion by itself; it's the drop-off step between "saw the paywall"
  /// and "paid", which is what tells you whether the ads bring buyers or
  /// tourists.
  static Future<void> logCheckoutStarted(SubscriptionPlan plan) async {
    if (!_supported) return;
    try {
      await _fb.logInitiatedCheckout(
        totalPrice: _stripePriceFor(plan),
        currency: _stripeCurrency,
        contentId: _planId(plan),
        contentType: 'subscription',
        numItems: 1,
      );
    } catch (e) {
      debugPrint('⚠️ Meta logCheckoutStarted failed: $e');
    }
  }

  /// A NEW paid subscription. Never call this for a restore or a renewal:
  /// Meta would count the same player as a fresh conversion and bid up on
  /// whatever ad set they came from.
  ///
  /// [amount] / [currency] come from the store on iOS (the real localized
  /// price the user was charged) and fall back to the Stripe price elsewhere.
  static Future<void> logSubscription({
    required SubscriptionPlan plan,
    required String orderId,
    double? amount,
    String? currency,
  }) async {
    if (!_supported) return;
    final price = amount ?? _stripePriceFor(plan);
    final cur = currency ?? _stripeCurrency;
    try {
      // Purchase drives ROAS/value optimisation; Subscribe is the standard
      // event Meta's subscription reporting reads. Meta expects both.
      await _fb.logPurchase(
        amount: price,
        currency: cur,
        parameters: {'fb_content_id': _planId(plan)},
      );
      await _fb.logSubscribe(
        price: price,
        currency: cur,
        orderId: orderId,
      );
    } catch (e) {
      debugPrint('⚠️ Meta logSubscription failed: $e');
    }
  }

  static double _stripePriceFor(SubscriptionPlan plan) =>
      plan == SubscriptionPlan.monthly
          ? _stripeMonthlyPriceEur
          : _stripeYearlyPriceEur;

  static String _planId(SubscriptionPlan plan) =>
      plan == SubscriptionPlan.monthly ? 'premium_monthly' : 'premium_yearly';
}
