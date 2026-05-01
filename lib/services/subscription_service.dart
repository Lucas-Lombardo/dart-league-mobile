import 'api_service.dart';

enum SubscriptionPlan { monthly, yearly }

class SubscriptionStatus {
  final bool isPremium;
  final DateTime? premiumExpiresAt;
  final int? matchesRemainingToday;
  final int? dailyLimit;

  SubscriptionStatus({
    required this.isPremium,
    this.premiumExpiresAt,
    this.matchesRemainingToday,
    this.dailyLimit,
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
