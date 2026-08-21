import 'api_service.dart';

/// Where a referral sits in its lifecycle. Mirrors the backend enum; unknown
/// values fall back to [trial] so a future status never crashes an old build.
enum ReferralStatus { trial, subscribed, rewardDue, rewardPaid, cancelled }

enum ReferralPlan { monthly, yearly }

/// Why the "I have a code" entry points are hidden for this account.
enum ReferralIneligibility { alreadyReferred, alreadySubscribed, accountTooOld }

/// Machine-readable failures the redeem/create endpoints can return, so the UI
/// can show the right sentence instead of a raw server string.
enum ReferralError {
  emailNotVerified,
  invalidCode,
  selfCode,
  alreadyReferred,
  alreadySubscribed,
  accountTooOld,
  unknown,
}

class ReferralException implements Exception {
  final ReferralError code;
  ReferralException(this.code);

  @override
  String toString() => 'ReferralException($code)';
}

ReferralStatus _statusFrom(String? raw) {
  switch (raw) {
    case 'subscribed':
      return ReferralStatus.subscribed;
    case 'reward_due':
      return ReferralStatus.rewardDue;
    case 'reward_paid':
      return ReferralStatus.rewardPaid;
    case 'cancelled':
      return ReferralStatus.cancelled;
    default:
      return ReferralStatus.trial;
  }
}

ReferralPlan? _planFrom(String? raw) {
  switch (raw) {
    case 'monthly':
      return ReferralPlan.monthly;
    case 'yearly':
      return ReferralPlan.yearly;
    default:
      return null;
  }
}

DateTime? _dateFrom(String? raw) {
  if (raw == null) return null;
  try {
    return DateTime.parse(raw).toLocal();
  } on FormatException {
    return null;
  }
}

class ReferralReferee {
  final String id;
  final String username;
  final ReferralStatus status;
  final ReferralPlan? plan;
  final int? rewardAmountCents;
  final DateTime? trialEndsAt;

  ReferralReferee({
    required this.id,
    required this.username,
    required this.status,
    this.plan,
    this.rewardAmountCents,
    this.trialEndsAt,
  });

  factory ReferralReferee.fromJson(Map<String, dynamic> json) {
    return ReferralReferee(
      id: json['id'] as String? ?? '',
      username: json['username'] as String? ?? '',
      status: _statusFrom(json['status'] as String?),
      plan: _planFrom(json['plan'] as String?),
      rewardAmountCents: json['rewardAmountCents'] as int?,
      trialEndsAt: _dateFrom(json['trialEndsAt'] as String?),
    );
  }
}

class ReferralEligibility {
  final bool eligible;
  final ReferralIneligibility? reason;

  const ReferralEligibility({required this.eligible, this.reason});

  /// Assume ineligible until the server says otherwise: showing a dead entry
  /// point is worse than showing none.
  static const ReferralEligibility unknown = ReferralEligibility(
    eligible: false,
  );

  factory ReferralEligibility.fromJson(Map<String, dynamic> json) {
    ReferralIneligibility? reason;
    switch (json['reason'] as String?) {
      case 'already_referred':
        reason = ReferralIneligibility.alreadyReferred;
        break;
      case 'already_subscribed':
        reason = ReferralIneligibility.alreadySubscribed;
        break;
      case 'account_too_old':
        reason = ReferralIneligibility.accountTooOld;
        break;
    }
    return ReferralEligibility(
      eligible: json['eligible'] as bool? ?? false,
      reason: reason,
    );
  }
}

class ReferralOverview {
  /// Null until the user creates one from Settings.
  final String? code;

  /// Creating a code requires a verified email — it is the payout channel.
  final bool canCreateCode;
  final bool isEmailVerified;
  final int rewardMonthlyCents;
  final int rewardYearlyCents;
  final int refereeTrialDays;
  final int earnedCents;
  final int pendingCents;
  final List<ReferralReferee> referees;
  final ReferralEligibility redeem;
  final String? referredByUsername;

  ReferralOverview({
    required this.code,
    required this.canCreateCode,
    required this.isEmailVerified,
    required this.rewardMonthlyCents,
    required this.rewardYearlyCents,
    required this.refereeTrialDays,
    required this.earnedCents,
    required this.pendingCents,
    required this.referees,
    required this.redeem,
    required this.referredByUsername,
  });

  factory ReferralOverview.fromJson(Map<String, dynamic> json) {
    final rawReferees = json['referees'] as List<dynamic>? ?? const [];
    return ReferralOverview(
      code: json['code'] as String?,
      canCreateCode: json['canCreateCode'] as bool? ?? false,
      isEmailVerified: json['isEmailVerified'] as bool? ?? false,
      rewardMonthlyCents: json['rewardMonthlyCents'] as int? ?? 500,
      rewardYearlyCents: json['rewardYearlyCents'] as int? ?? 1000,
      refereeTrialDays: json['refereeTrialDays'] as int? ?? 7,
      earnedCents: json['earnedCents'] as int? ?? 0,
      pendingCents: json['pendingCents'] as int? ?? 0,
      referees: rawReferees
          .whereType<Map<String, dynamic>>()
          .map(ReferralReferee.fromJson)
          .toList(),
      redeem: ReferralEligibility.fromJson(
        json['redeem'] as Map<String, dynamic>? ?? const {},
      ),
      referredByUsername: json['referredByUsername'] as String?,
    );
  }
}

class ReferralRedeemResult {
  final DateTime? bonusPremiumUntil;
  final String referrerUsername;

  ReferralRedeemResult({
    required this.bonusPremiumUntil,
    required this.referrerUsername,
  });
}

class ReferralService {
  static Future<ReferralOverview> getOverview() async {
    final response = await ApiService.get('/referrals/me');
    return ReferralOverview.fromJson(response as Map<String, dynamic>);
  }

  static Future<ReferralEligibility> getEligibility() async {
    final response = await ApiService.get('/referrals/eligibility');
    return ReferralEligibility.fromJson(response as Map<String, dynamic>);
  }

  static Future<String> createCode() async {
    try {
      final response = await ApiService.post('/referrals/code', const {});
      final code = (response as Map<String, dynamic>)['code'] as String?;
      if (code == null || code.isEmpty) {
        throw ReferralException(ReferralError.unknown);
      }
      return code;
    } catch (e) {
      throw referralErrorFrom(e);
    }
  }

  static Future<ReferralRedeemResult> redeem(String code) async {
    try {
      final response = await ApiService.post('/referrals/redeem', {
        'code': code.trim().toUpperCase(),
      });
      final map = response as Map<String, dynamic>;
      return ReferralRedeemResult(
        bonusPremiumUntil: _dateFrom(map['bonusPremiumUntil'] as String?),
        referrerUsername: map['referrerUsername'] as String? ?? '',
      );
    } catch (e) {
      throw referralErrorFrom(e);
    }
  }
}

/// The API layer flattens server errors into `Exception('Error 400: CODE')`,
/// so the machine-readable code has to be matched back out of the message.
ReferralException referralErrorFrom(Object error) {
  if (error is ReferralException) return error;
  final message = error.toString().toUpperCase();
  if (message.contains('EMAIL_NOT_VERIFIED')) {
    return ReferralException(ReferralError.emailNotVerified);
  }
  if (message.contains('REFERRAL_CODE_SELF')) {
    return ReferralException(ReferralError.selfCode);
  }
  if (message.contains('REFERRAL_CODE_INVALID') ||
      message.contains('REFERRAL_CODE_REQUIRED')) {
    return ReferralException(ReferralError.invalidCode);
  }
  if (message.contains('ALREADY_REFERRED')) {
    return ReferralException(ReferralError.alreadyReferred);
  }
  if (message.contains('ALREADY_SUBSCRIBED')) {
    return ReferralException(ReferralError.alreadySubscribed);
  }
  if (message.contains('ACCOUNT_TOO_OLD')) {
    return ReferralException(ReferralError.accountTooOld);
  }
  return ReferralException(ReferralError.unknown);
}
