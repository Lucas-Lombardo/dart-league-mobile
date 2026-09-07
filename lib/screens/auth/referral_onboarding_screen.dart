import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/referral_provider.dart';
import '../../providers/subscription_provider.dart';
import '../../utils/app_navigator.dart';
import '../../utils/app_theme.dart';
import '../../utils/haptic_service.dart';
import '../../widgets/design_system.dart';
import '../settings/redeem_referral_screen.dart';

/// The main route into the referral program: shown once, right after signup,
/// while the referrer's instructions ("install it and put my code") are still
/// fresh. Skippable in one tap — the other three entry points catch the rest.
///
/// Pops itself to /home either way.
class ReferralOnboardingScreen extends StatelessWidget {
  const ReferralOnboardingScreen({super.key});

  Future<void> _openRedeem(BuildContext context) async {
    HapticService.mediumImpact();
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const RedeemReferralScreen()));
    if (!context.mounted) return;
    await context.read<SubscriptionProvider>().refresh();
    if (context.mounted) _continue(context);
  }

  void _continue(BuildContext context) {
    AppNavigator.toAuth(context, '/home');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final days =
        context.watch<ReferralProvider>().overview?.refereeTrialDays ?? 7;

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Image.asset(
                    'assets/logo/logo-without-letters.png',
                    width: 72,
                    height: 72,
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  dsSentence(l10n.referralOnboardingTitle),
                  textAlign: TextAlign.center,
                  style: AppTheme.displayMedium,
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.referralOnboardingBody(days),
                  textAlign: TextAlign.center,
                  style: AppTheme.bodyLarge,
                ),
                const SizedBox(height: 32),
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () => _openRedeem(context),
                    child: Text(dsSentence(l10n.referralOnboardingAction)),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () {
                    HapticService.lightImpact();
                    _continue(context);
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.textSecondary,
                  ),
                  child: Text(dsSentence(l10n.referralOnboardingSkip)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
