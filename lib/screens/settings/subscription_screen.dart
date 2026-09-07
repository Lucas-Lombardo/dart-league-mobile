import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/subscription_provider.dart';
import '../../services/iap_service.dart';
import '../../services/subscription_service.dart';
import '../../utils/app_theme.dart';
import '../../utils/haptic_service.dart';
import '../../widgets/design_system.dart';
import '../../providers/referral_provider.dart';
import 'redeem_referral_screen.dart';

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> with WidgetsBindingObserver {
  static const String _termsOfUseUrl =
      'https://www.apple.com/legal/internet-services/itunes/dev/stdeula/';
  static const String _privacyPolicyUrl = 'https://api.dart-rivals.com/privacy';

  static const String _fallbackYearlyPrice = '€49.99';
  static const String _fallbackMonthlyPrice = '€4.99';

  bool _isProcessing = false;
  bool _isRestoring = false;

  /// Tapping a plan card selects it; the button under the cards buys it.
  /// Yearly is preselected — it is the "best price" card.
  SubscriptionPlan _selectedPlan = SubscriptionPlan.yearly;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SubscriptionProvider>().refresh();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      context.read<SubscriptionProvider>().refresh();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _startCheckout(SubscriptionPlan plan) async {
    if (_isProcessing) return;
    HapticService.mediumImpact();
    setState(() => _isProcessing = true);
    final provider = context.read<SubscriptionProvider>();
    final ok = await provider.startCheckout(plan);
    if (!mounted) return;
    setState(() => _isProcessing = false);
    if (!ok && provider.errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(provider.errorMessage!),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  Future<void> _openPortal() async {
    if (_isProcessing) return;
    HapticService.mediumImpact();
    setState(() => _isProcessing = true);
    final provider = context.read<SubscriptionProvider>();
    final ok = await provider.openManageSubscription();
    if (!mounted) return;
    setState(() => _isProcessing = false);
    if (!ok && provider.errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(provider.errorMessage!),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  Future<void> _restore() async {
    if (_isRestoring) return;
    HapticService.mediumImpact();
    setState(() => _isRestoring = true);
    final provider = context.read<SubscriptionProvider>();
    final outcome = await provider.restorePurchases();
    if (!mounted) return;
    setState(() => _isRestoring = false);
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    switch (outcome) {
      case RestoreOutcome.restored:
        messenger.showSnackBar(
          SnackBar(
            content: Text(l10n.restoreSuccess),
            backgroundColor: AppTheme.success,
          ),
        );
        break;
      case RestoreOutcome.nothingToRestore:
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.restoreNothingToRestore)),
        );
        break;
      case RestoreOutcome.failed:
        messenger.showSnackBar(
          SnackBar(
            content: Text(provider.errorMessage ?? l10n.restoreFailed),
            backgroundColor: AppTheme.error,
          ),
        );
        break;
      case RestoreOutcome.notSupported:
        // Should never be reached — button is iOS-only.
        break;
    }
  }

  Future<void> _openExternal(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  String _yearlyPrice() {
    if (Platform.isIOS) {
      return IapService.instance.priceFor(SubscriptionPlan.yearly) ??
          _fallbackYearlyPrice;
    }
    return _fallbackYearlyPrice;
  }

  String _monthlyPrice() {
    if (Platform.isIOS) {
      return IapService.instance.priceFor(SubscriptionPlan.monthly) ??
          _fallbackMonthlyPrice;
    }
    return _fallbackMonthlyPrice;
  }

  /// Legacy ALL-CAPS hero titles ("PASSEZ PREMIUM") in sentence case, with the
  /// product name kept capitalised: "Passez Premium".
  String _heroTitle(String raw) =>
      dsSentence(raw).replaceAll('premium', 'Premium');

  String _formatDate(DateTime date) =>
      DateFormat.yMMMd(Localizations.localeOf(context).toString()).format(date);

  @override
  Widget build(BuildContext context) {
    final subscription = context.watch<SubscriptionProvider>();
    final isPremium = subscription.isPremiumActive;
    // The hero celebrates the entitlement, but the plans stay visible for
    // anyone who isn't paying yet — a referee on referral bonus days is
    // premium and still needs to be able to subscribe.
    final showPaywall = !subscription.hasPaidSubscription;
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.premium)),
      body: subscription.isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : RefreshIndicator(
              color: AppTheme.primary,
              onRefresh: subscription.refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  _buildHero(l10n, isPremium, subscription.premiumExpiresAt),
                  const SizedBox(height: 14),
                  if (showPaywall)
                    _buildPaywallSection(l10n)
                  else
                    _buildManageSection(l10n, subscription.premiumExpiresAt),
                  const SizedBox(height: 14),
                  _buildLegalFooter(l10n),
                  const SizedBox(height: 8),
                ],
              ),
            ),
    );
  }

  /// Flat card, the crown on a gold disc — the one gold of the screen.
  Widget _buildHero(AppLocalizations l10n, bool isPremium, DateTime? expiresAt) {
    final caption = isPremium && expiresAt != null
        ? l10n.premiumRenewsOn.replaceAll('{date}', _formatDate(expiresAt))
        : l10n.unlockUnlimitedMatches;
    return DsCard(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.accent.withValues(alpha: 0.14),
            ),
            child: const Icon(Icons.workspace_premium_rounded,
                size: 26, color: AppTheme.accent),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _heroTitle(isPremium ? l10n.premiumActiveTitle : l10n.goPremiumTitle),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.displayMedium.copyWith(fontSize: 22),
                ),
                const SizedBox(height: 5),
                Text(
                  caption,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.caption.copyWith(fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaywallSection(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildBenefitsCard(l10n),
        const SizedBox(height: 14),
        _buildPlanCard(
          plan: SubscriptionPlan.yearly,
          title: l10n.planYearly,
          price: _yearlyPrice(),
          period: '/${_yearShort(l10n)}',
          subtitle: l10n.yearlySubtitle,
          badge: dsSentence(l10n.bestValue),
        ),
        const SizedBox(height: 10),
        _buildPlanCard(
          plan: SubscriptionPlan.monthly,
          title: l10n.planMonthly,
          price: _monthlyPrice(),
          period: '/${_monthShort(l10n)}',
          subtitle: l10n.monthlySubtitle,
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 52,
          child: ElevatedButton(
            onPressed: _isProcessing ? null : () => _startCheckout(_selectedPlan),
            child: _isProcessing
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Text(
                    _selectedPlan == SubscriptionPlan.yearly
                        ? l10n.premiumContinueYearly
                        : l10n.premiumContinueMonthly,
                  ),
          ),
        ),
        _buildReferralRow(l10n),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 18, 8, 0),
          child: Text(
            Platform.isIOS ? l10n.autoRenewDisclosure : l10n.paywallFooter,
            textAlign: TextAlign.center,
            style: AppTheme.caption.copyWith(
              fontSize: 11,
              color: AppTheme.textTertiary,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }

  /// Someone opening the paywall already wants premium — if they were given a
  /// code, this is when they remember it. Renders nothing when ineligible.
  Widget _buildReferralRow(AppLocalizations l10n) {
    final referral = context.watch<ReferralProvider>();
    if (!referral.canRedeem) return const SizedBox.shrink();
    final days = referral.overview?.refereeTrialDays ?? 7;

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Material(
        color: AppTheme.primary.withValues(alpha: 0.08),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusControl),
          side: BorderSide(color: AppTheme.primaryLight.withValues(alpha: 0.3)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () async {
            HapticService.lightImpact();
            final redeemed = await Navigator.of(context).push<bool>(
              MaterialPageRoute(builder: (_) => const RedeemReferralScreen()),
            );
            if (!mounted) return;
            await context.read<SubscriptionProvider>().refresh();
            if (mounted && redeemed == true) Navigator.of(context).pop();
          },
          child: SizedBox(
            height: 48,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  const Icon(Icons.card_giftcard_outlined,
                      size: 18, color: AppTheme.primaryLight),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      l10n.referralPaywallRow(days),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primaryLight,
                      ),
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded,
                      size: 16, color: AppTheme.primaryLight),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _yearShort(AppLocalizations l10n) {
    return Localizations.localeOf(context).languageCode == 'fr' ? 'an' : 'year';
  }

  String _monthShort(AppLocalizations l10n) {
    return Localizations.localeOf(context).languageCode == 'fr' ? 'mois' : 'month';
  }

  Widget _buildBenefitsCard(AppLocalizations l10n) {
    final benefits = [
      (l10n.benefitUnlimitedMatches, Icons.all_inclusive_rounded),
      (l10n.benefitPremiumBadge, Icons.workspace_premium_rounded),
      (l10n.benefitSupportDev, Icons.favorite_outline_rounded),
    ];
    return DsCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.whatYouGet.toUpperCase(), style: AppTheme.labelSmall),
          const SizedBox(height: 12),
          for (var i = 0; i < benefits.length; i++) ...[
            if (i > 0) const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 36),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(benefits[i].$2,
                        size: 17, color: AppTheme.primaryLight),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      benefits[i].$1,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.rowTitle,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Selected = primary at 8 % + 1.5 px primary border; otherwise a plain
  /// surface card. Tapping selects, the button below buys.
  Widget _buildPlanCard({
    required SubscriptionPlan plan,
    required String title,
    required String price,
    required String period,
    required String subtitle,
    String? badge,
  }) {
    final selected = _selectedPlan == plan;
    return DsCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      color: selected ? AppTheme.primary.withValues(alpha: 0.08) : AppTheme.surface,
      side: selected ? const BorderSide(color: AppTheme.primary, width: 1.5) : null,
      onTap: _isProcessing ? null : () => setState(() => _selectedPlan = plan),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.titleLarge,
                      ),
                    ),
                    if (badge != null) ...[
                      const SizedBox(width: 8),
                      DsPill(label: badge),
                    ],
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.caption,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                price,
                style: AppTheme.displayMedium.copyWith(
                  fontSize: 22,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 3),
              Text(period, style: AppTheme.caption),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildManageSection(AppLocalizations l10n, DateTime? expiresAt) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DsCard(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.statusLabel.toUpperCase(), style: AppTheme.labelSmall),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.check_circle_outline_rounded,
                      size: 20, color: AppTheme.success),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.premiumActive,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              if (expiresAt != null) ...[
                const SizedBox(height: 6),
                Text(
                  l10n.nextRenewal.replaceAll('{date}', _formatDate(expiresAt)),
                  style: AppTheme.caption,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 52,
          child: ElevatedButton(
            onPressed: _isProcessing ? null : _openPortal,
            child: _isProcessing
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Text(dsSentence(l10n.manageSubscription)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
          child: Text(
            Platform.isIOS ? l10n.autoRenewDisclosure : l10n.manageFooter,
            textAlign: TextAlign.center,
            style: AppTheme.caption.copyWith(
              fontSize: 11,
              color: AppTheme.textTertiary,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }

  /// Legal footer is shown on both paywall and manage screens so Apple
  /// reviewers can always find Terms / Privacy / Restore.
  Widget _buildLegalFooter(AppLocalizations l10n) {
    // Styles live on the Text children (AppTheme tokens carry the font);
    // a styleFrom(textStyle:) would drop the theme's family.
    final linkStyle = AppTheme.caption.copyWith(
      fontWeight: FontWeight.w600,
      decoration: TextDecoration.underline,
      decorationColor: AppTheme.textSecondary,
    );
    final compact = TextButton.styleFrom(
      foregroundColor: AppTheme.textSecondary,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      minimumSize: const Size(0, 32),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            TextButton(
              onPressed: () => _openExternal(_termsOfUseUrl),
              style: compact,
              child: Text(l10n.termsOfUse, style: linkStyle),
            ),
            Text('·', style: AppTheme.caption.copyWith(fontWeight: FontWeight.w600)),
            TextButton(
              onPressed: () => _openExternal(_privacyPolicyUrl),
              style: compact,
              child: Text(l10n.privacyPolicy, style: linkStyle),
            ),
          ],
        ),
        if (Platform.isIOS) ...[
          const SizedBox(height: 6),
          TextButton.icon(
            onPressed: _isRestoring ? null : _restore,
            style: compact,
            icon: _isRestoring
                ? const SizedBox(
                    height: 14,
                    width: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(AppTheme.textSecondary),
                    ),
                  )
                : const Icon(Icons.refresh_rounded,
                    size: 14, color: AppTheme.textSecondary),
            label: Text(
              l10n.restorePurchases,
              style: AppTheme.caption.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ],
    );
  }
}
