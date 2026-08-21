import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/services/referral_service.dart';

/// The referral API answers are parsed defensively and its failures are mapped
/// back from flattened strings — both are easy to get subtly wrong, and both
/// decide whether an entry point is shown or a helpful error is displayed.
void main() {
  group('ReferralOverview.fromJson', () {
    test('reads a fully populated payload', () {
      final overview = ReferralOverview.fromJson({
        'code': 'LUCAS-4K2',
        'canCreateCode': true,
        'isEmailVerified': true,
        'rewardMonthlyCents': 500,
        'rewardYearlyCents': 1000,
        'refereeTrialDays': 7,
        'earnedCents': 1500,
        'pendingCents': 500,
        'referees': [
          {
            'id': 'u1',
            'username': 'MikeD180',
            'status': 'reward_paid',
            'plan': 'yearly',
            'rewardAmountCents': 1000,
            'trialEndsAt': '2026-08-26T12:00:00.000Z',
          },
          {
            'id': 'u2',
            'username': 'Tom_Cricket',
            'status': 'trial',
            'plan': null,
            'rewardAmountCents': null,
            'trialEndsAt': null,
          },
        ],
        'redeem': {'eligible': false, 'reason': 'already_referred'},
        'referredByUsername': null,
      });

      expect(overview.code, 'LUCAS-4K2');
      expect(overview.earnedCents, 1500);
      expect(overview.referees, hasLength(2));
      expect(overview.referees.first.status, ReferralStatus.rewardPaid);
      expect(overview.referees.first.plan, ReferralPlan.yearly);
      expect(overview.referees.last.status, ReferralStatus.trial);
      expect(overview.referees.last.plan, isNull);
      expect(overview.redeem.eligible, isFalse);
      expect(overview.redeem.reason, ReferralIneligibility.alreadyReferred);
    });

    test('survives an empty payload with sane defaults', () {
      final overview = ReferralOverview.fromJson(const {});

      expect(overview.code, isNull);
      expect(overview.canCreateCode, isFalse);
      expect(overview.refereeTrialDays, 7);
      expect(overview.rewardMonthlyCents, 500);
      expect(overview.rewardYearlyCents, 1000);
      expect(overview.referees, isEmpty);
      expect(overview.redeem.eligible, isFalse);
    });

    // A status added server-side must not crash an installed build.
    test('falls back to trial on an unknown status', () {
      final referee = ReferralReferee.fromJson(const {
        'id': 'u3',
        'username': 'Future',
        'status': 'something_new',
      });

      expect(referee.status, ReferralStatus.trial);
    });
  });

  group('ReferralEligibility', () {
    test('defaults to ineligible so no dead entry point is ever shown', () {
      expect(ReferralEligibility.unknown.eligible, isFalse);
      expect(ReferralEligibility.fromJson(const {}).eligible, isFalse);
    });

    test('maps each ineligibility reason', () {
      ReferralIneligibility? reasonFor(String raw) =>
          ReferralEligibility.fromJson({
            'eligible': false,
            'reason': raw,
          }).reason;

      expect(
        reasonFor('already_referred'),
        ReferralIneligibility.alreadyReferred,
      );
      expect(
        reasonFor('already_subscribed'),
        ReferralIneligibility.alreadySubscribed,
      );
      expect(reasonFor('account_too_old'), ReferralIneligibility.accountTooOld);
      expect(reasonFor('who_knows'), isNull);
    });
  });

  // The API layer flattens server errors into Exception('Error 400: CODE'),
  // so the machine-readable code has to be recovered from the message.
  group('error mapping', () {
    ReferralError codeFor(String message) {
      try {
        // ignore: only_throw_errors
        throw Exception(message);
      } catch (e) {
        return referralErrorFrom(e).code;
      }
    }

    test('recognises every server code', () {
      expect(
        codeFor('Error 400: REFERRAL_CODE_INVALID'),
        ReferralError.invalidCode,
      );
      expect(codeFor('Error 400: REFERRAL_CODE_SELF'), ReferralError.selfCode);
      expect(
        codeFor('Error 400: REFERRAL_CODE_REQUIRED'),
        ReferralError.invalidCode,
      );
      expect(
        codeFor('Error 400: ALREADY_REFERRED'),
        ReferralError.alreadyReferred,
      );
      expect(
        codeFor('Error 400: ALREADY_SUBSCRIBED'),
        ReferralError.alreadySubscribed,
      );
      expect(
        codeFor('Error 400: ACCOUNT_TOO_OLD'),
        ReferralError.accountTooOld,
      );
      expect(
        codeFor('Forbidden: EMAIL_NOT_VERIFIED'),
        ReferralError.emailNotVerified,
      );
    });

    test('falls back to unknown for anything else', () {
      expect(codeFor('Connection timeout'), ReferralError.unknown);
      expect(
        codeFor('Error 500: Internal server error'),
        ReferralError.unknown,
      );
    });
  });
}
