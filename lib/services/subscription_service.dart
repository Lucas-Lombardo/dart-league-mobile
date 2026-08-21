import 'api_service.dart';

enum SubscriptionPlan { monthly, yearly }

class SubscriptionStatus {
  final bool isPremium;
  final DateTime? premiumExpiresAt;
  final int? matchesRemainingToday;
  final int? dailyLimit;

  /// True during the weekly Free Play window (Sat 20:00–00:00 Europe/Paris),
  /// when ranked is unlimited and friend matches are free for everyone.
  final bool freePlayActive;

  /// True only for a PAYING subscriber. A referee on their referral bonus days
  /// reports [isPremium] true but this false — they must still be offered the
  /// plans, since converting them is what the referral reward pays for.
  /// Absent on backends older than the referral program: defaults to
  /// [isPremium], which is the pre-referral behaviour.
  final bool hasPaidSubscription;

  SubscriptionStatus({
    required this.isPremium,
    this.premiumExpiresAt,
    this.matchesRemainingToday,
    this.dailyLimit,
    this.freePlayActive = false,
    required this.hasPaidSubscription,
  });

  factory SubscriptionStatus.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(String? value) {
      if (value == null) return null;
      try {
        return DateTime.parse(value);
      } on FormatException {
        return null;
      }
    }

    return SubscriptionStatus(
      isPremium: json['isPremium'] as bool? ?? false,
      premiumExpiresAt: parseDate(json['premiumExpiresAt'] as String?),
      matchesRemainingToday: json['matchesRemainingToday'] as int?,
      dailyLimit: json['dailyLimit'] as int?,
      freePlayActive: json['freePlayActive'] as bool? ?? false,
      hasPaidSubscription:
          json['hasPaidSubscription'] as bool? ??
          (json['isPremium'] as bool? ?? false),
    );
  }
}

class SubscriptionService {
  static Future<String> createCheckoutUrl(SubscriptionPlan plan) async {
    final response = await ApiService.post('/subscriptions/checkout', {
      'plan': plan == SubscriptionPlan.monthly ? 'monthly' : 'yearly',
    });
    final url = (response as Map<String, dynamic>)['url'] as String?;
    if (url == null || url.isEmpty) {
      throw Exception('No checkout URL returned');
    }
    return url;
  }

  static Future<String> createPortalUrl() async {
    final response = await ApiService.post('/subscriptions/portal', const {});
    final url = (response as Map<String, dynamic>)['url'] as String?;
    if (url == null || url.isEmpty) {
      throw Exception('No portal URL returned');
    }
    return url;
  }

  static Future<SubscriptionStatus> getStatus() async {
    final response = await ApiService.get('/subscriptions/status');
    return SubscriptionStatus.fromJson(response as Map<String, dynamic>);
  }
}
