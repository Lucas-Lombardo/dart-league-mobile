import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/referral_provider.dart';
import '../../providers/subscription_provider.dart';
import '../../services/referral_service.dart';
import '../../utils/app_theme.dart';
import '../../utils/haptic_service.dart';
import '../../widgets/design_system.dart';

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
      appBar: AppBar(
        title: Text(l10n.referralRedeemTitle),
        // Custom back so the caller learns whether a code was accepted.
        leading: IconButton(
          icon: const BackButtonIcon(),
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
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.primary.withValues(alpha: 0.14),
              ),
              child: const Icon(
                Icons.card_giftcard_outlined,
                size: 34,
                color: AppTheme.primaryLight,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.referralRedeemHeadline,
            textAlign: TextAlign.center,
            style: AppTheme.displayMedium,
          ),
          const SizedBox(height: 8),
          Text(
            l10n.referralRedeemBody(_trialDays),
            textAlign: TextAlign.center,
            style: AppTheme.bodyLarge,
          ),
          const SizedBox(height: 28),
          TextField(
            controller: _controller,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.done,
            textAlign: TextAlign.center,
            onSubmitted: (_) => _submit(),
            onChanged: (_) => setState(() {}),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9\-]')),
              LengthLimitingTextInputFormatter(24),
              TextInputFormatter.withFunction(
                (_, next) => next.copyWith(text: next.text.toUpperCase()),
              ),
            ],
            style: AppTheme.displayMedium.copyWith(
              fontSize: 22,
              letterSpacing: 2,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
            decoration: InputDecoration(
              hintText: l10n.referralRedeemHint,
              hintStyle: AppTheme.displayMedium.copyWith(
                fontSize: 22,
                letterSpacing: 2,
                color: AppTheme.textTertiary,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 18,
              ),
              suffixIcon: _controller.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(
                        Icons.close_rounded,
                        size: 20,
                        color: AppTheme.textSecondary,
                      ),
                      onPressed: () {
                        _controller.clear();
                        setState(() {});
                      },
                    ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: isMutating || _controller.text.trim().isEmpty
                  ? null
                  : _submit,
              child: isMutating
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(dsSentence(l10n.referralRedeemAction(_trialDays))),
            ),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              l10n.referralRedeemFootnote,
              textAlign: TextAlign.center,
              style: AppTheme.caption.copyWith(
                color: AppTheme.textTertiary,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The crown on its gold disc: this is the premium moment, the one place
  /// gold is allowed.
  Widget _buildSuccess(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.accent.withValues(alpha: 0.14),
              ),
              child: const Icon(
                Icons.workspace_premium_rounded,
                size: 44,
                color: AppTheme.accent,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            dsSentence(l10n.referralRedeemSuccessTitle(_trialDays)),
            textAlign: TextAlign.center,
            style: AppTheme.displayMedium,
          ),
          const SizedBox(height: 12),
          Text(
            l10n.referralRedeemSuccessBody(_result!.referrerUsername),
            textAlign: TextAlign.center,
            style: AppTheme.bodyLarge,
          ),
          const SizedBox(height: 32),
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: () {
                HapticService.mediumImpact();
                Navigator.of(context).pop(true);
              },
              child: Text(dsSentence(l10n.referralRedeemSuccessAction)),
            ),
          ),
        ],
      ),
    );
  }
}
