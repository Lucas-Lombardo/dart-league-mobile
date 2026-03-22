import 'package:flutter/foundation.dart' show debugPrint, kDebugMode, kIsWeb;
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_stripe/flutter_stripe.dart';

class PaymentService {
  static Future<bool> processPayment({
    required String clientSecret,
    required String merchantDisplayName,
  }) async {
    // Stripe payments not supported on web
    if (kIsWeb) {
      throw UnsupportedError('Stripe payments are not supported on web. Please use the mobile app.');
    }

    try {
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: clientSecret,
          merchantDisplayName: merchantDisplayName,
          returnURL: 'dartrivals://redirect',
          style: ThemeMode.dark,
          // Apple Pay configuration
          applePay: const PaymentSheetApplePay(
            merchantCountryCode: 'FR',
          ),
          // Google Pay configuration
          googlePay: PaymentSheetGooglePay(
            merchantCountryCode: 'FR',
            testEnv: kDebugMode,
          ),
        ),
      );

      await Stripe.instance.presentPaymentSheet();
      debugPrint('💳 Payment completed successfully');
      return true;
    } on StripeException catch (e) {
      debugPrint('💳 Stripe error: ${e.error.localizedMessage}');
      rethrow;
    } catch (e) {
      debugPrint('💳 Payment error: $e');
      rethrow;
    }
  }
}
