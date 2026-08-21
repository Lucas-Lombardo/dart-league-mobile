import 'package:flutter/foundation.dart';

import '../services/referral_service.dart';

/// Holds the referral state shared by the four entry points into the redeem
/// screen (post-signup, Settings, the Premium screen, the daily-limit dialog)
/// plus the referrer screen itself.
class ReferralProvider extends ChangeNotifier {
  ReferralOverview? _overview;
  ReferralEligibility _redeemEligibility = ReferralEligibility.unknown;
  bool _isLoading = false;
  bool _isMutating = false;
  ReferralError? _lastError;

  ReferralOverview? get overview => _overview;
  bool get isLoading => _isLoading;
  bool get isMutating => _isMutating;
  ReferralError? get lastError => _lastError;

  /// Drives whether "I have a referral code" is offered at all. Defaults to
  /// false so a not-yet-loaded state never shows a dead entry point.
  bool get canRedeem => _redeemEligibility.eligible;
  ReferralIneligibility? get ineligibilityReason => _redeemEligibility.reason;

  /// Cheap call behind every entry point. Failures leave the previous answer
  /// in place — a flaky network should not make the row flicker.
  Future<void> refreshEligibility() async {
    try {
      _redeemEligibility = await ReferralService.getEligibility();
      notifyListeners();
    } catch (e) {
      if (kDebugMode) debugPrint('Referral eligibility refresh failed: $e');
    }
  }

  Future<void> loadOverview() async {
    _isLoading = true;
    _lastError = null;
    notifyListeners();
    try {
      final overview = await ReferralService.getOverview();
      _overview = overview;
      _redeemEligibility = overview.redeem;
    } catch (e) {
      _lastError = ReferralError.unknown;
      if (kDebugMode) debugPrint('Referral overview load failed: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Creates the caller's code. Returns false and sets [lastError] on failure
  /// — most often [ReferralError.emailNotVerified].
  Future<bool> createCode() async {
    if (_isMutating) return false;
    _isMutating = true;
    _lastError = null;
    notifyListeners();
    try {
      await ReferralService.createCode();
      await loadOverview();
      return true;
    } on ReferralException catch (e) {
      _lastError = e.code;
      return false;
    } catch (_) {
      _lastError = ReferralError.unknown;
      return false;
    } finally {
      _isMutating = false;
      notifyListeners();
    }
  }

  /// Redeems a code and starts the caller's free premium days. The caller is
  /// responsible for refreshing SubscriptionProvider afterwards so the rest of
  /// the app sees the new entitlement.
  Future<ReferralRedeemResult?> redeem(String code) async {
    if (_isMutating) return null;
    _isMutating = true;
    _lastError = null;
    notifyListeners();
    try {
      final result = await ReferralService.redeem(code);
      _redeemEligibility = const ReferralEligibility(
        eligible: false,
        reason: ReferralIneligibility.alreadyReferred,
      );
      return result;
    } on ReferralException catch (e) {
      _lastError = e.code;
      return null;
    } catch (_) {
      _lastError = ReferralError.unknown;
      return null;
    } finally {
      _isMutating = false;
      notifyListeners();
    }
  }

  void clearError() {
    if (_lastError == null) return;
    _lastError = null;
    notifyListeners();
  }

  /// Called on logout so the next account does not inherit this one's state.
  void reset() {
    _overview = null;
    _redeemEligibility = ReferralEligibility.unknown;
    _isLoading = false;
    _isMutating = false;
    _lastError = null;
    notifyListeners();
  }
}
