import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/referral_provider.dart';
import '../../providers/subscription_provider.dart';
import '../../services/referral_service.dart';
import '../../utils/app_theme.dart';
import '../../utils/haptic_service.dart';

/// Where a referee enters their friend's code. Reached from four places: the
/// post-signup step, Settings, the Premium screen and the daily-limit dialog.
///
/// Pops `true` once the code is accepted so the caller can close whatever
/// brought the user here.
class RedeemReferralScreen extends StatefulWidget {
  const RedeemReferralScreen({super.key});

  @override
  State<RedeemReferralScreen> createState() => _RedeemReferralScreenState();
}

class _RedeemReferralScreenState extends State<RedeemReferralScreen> {
  final _controller = TextEditingController();
  ReferralRedeemResult? _result;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  int get _trialDays =>
      context.read<ReferralProvider>().overview?.refereeTrialDays ?? 7;

  String _errorText(AppLocalizations l10n, ReferralError error) {
    switch (error) {
      case ReferralError.invalidCode:
        return l10n.referralErrorInvalidCode;
      case ReferralError.selfCode:
        return l10n.referralErrorSelfCode;
      case ReferralError.alreadyReferred:
        return l10n.referralErrorAlreadyReferred;
      case ReferralError.alreadySubscribed:
        return l10n.referralErrorAlreadySubscribed;
      case ReferralError.accountTooOld:
        return l10n.referralErrorAccountTooOld;
      case ReferralError.emailNotVerified:
        return l10n.referralErrorEmailNotVerified;
      case ReferralError.unknown:
        return l10n.referralErrorUnknown;
    }
  }

  Future<void> _submit() async {
    final code = _controller.text.trim();
    if (code.isEmpty) return;
    HapticService.mediumImpact();

    final referral = context.read<ReferralProvider>();
    final result = await referral.redeem(code);
    if (!mounted) return;

    if (result == null) {
      final error = referral.lastError;
      if (error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_errorText(AppLocalizations.of(context), error)),
            backgroundColor: AppTheme.error,
          ),
        );
      }
      return;
    }

    // The entitlement just changed — pull it so the Play button, the paywall
    // and the badges all agree before the user lands back on the app.
    await context.read<SubscriptionProvider>().refresh();
    if (!mounted) return;
    setState(() => _result = result);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(l10n.referralRedeemTitle),
        backgroundColor: AppTheme.surface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(_result != null),
        ),
      ),
      body: SafeArea(
        child: _result != null ? _buildSuccess(l10n) : _buildForm(l10n),
      ),
    );
  }

  Widget _buildForm(AppLocalizations l10n) {
    final isMutating = context.watch<ReferralProvider>().isMutating;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),
          Center(
            child: Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.primary.withValues(alpha: 0.12),
              ),
              child: const Icon(
                Icons.card_giftcard,
                size: 42,
                color: AppTheme.primary,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.referralRedeemHeadline,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.referralRedeemBody(_trialDays),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14.5,
              height: 1.5,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 28),
          TextField(
            controller: _controller,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            onChanged: (_) => setState(() {}),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9\-]')),
              LengthLimitingTextInputFormatter(24),
              TextInputFormatter.withFunction(
                (_, next) => next.copyWith(text: next.text.toUpperCase()),
              ),
            ],
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: 2,
            ),
            decoration: InputDecoration(
              hintText: l10n.referralRedeemHint,
              hintStyle: TextStyle(
                color: AppTheme.textSecondary.withValues(alpha: 0.6),
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
              ),
              filled: true,
              fillColor: AppTheme.surface,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 18,
              ),
              suffixIcon: _controller.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(
                        Icons.clear,
                        color: AppTheme.textSecondary,
                      ),
                      onPressed: () {
                        _controller.clear();
                        setState(() {});
                      },
                    ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: AppTheme.surfaceLight.withValues(alpha: 0.6),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: AppTheme.primary, width: 2),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 58,
            child: ElevatedButton(
              onPressed: isMutating || _controller.text.trim().isEmpty
                  ? null
                  : _submit,
              style: AppTheme.primaryButtonStyle,
              child: isMutating
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.white,
                      ),
                    )
                  : Text(l10n.referralRedeemAction(_trialDays)),
            ),
          ),
          const SizedBox(height: 28),
          Text(
            l10n.referralRedeemFootnote,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.5,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccess(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 116,
              height: 116,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFC107), Color(0xFFEAB308)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFEAB308).withValues(alpha: 0.45),
                    blurRadius: 36,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: const Icon(
                Icons.workspace_premium,
                size: 58,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            l10n.referralRedeemSuccessTitle(_trialDays),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
              color: Color(0xFFEAB308),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            l10n.referralRedeemSuccessBody(_result!.referrerUsername),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15.5,
              height: 1.5,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 32),
          SizedBox(
            height: 58,
            child: ElevatedButton(
              onPressed: () {
                HapticService.mediumImpact();
                Navigator.of(context).pop(true);
              },
              style: AppTheme.primaryButtonStyle,
              child: Text(l10n.referralRedeemSuccessAction),
            ),
          ),
        ],
      ),
    );
  }
}
