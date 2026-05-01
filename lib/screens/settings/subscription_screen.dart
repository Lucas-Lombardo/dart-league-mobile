import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/subscription_provider.dart';
import '../../services/subscription_service.dart';
import '../../utils/app_theme.dart';
import '../../utils/haptic_service.dart';

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> with WidgetsBindingObserver {
  bool _isProcessing = false;

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

  @override
  Widget build(BuildContext context) {
    final subscription = context.watch<SubscriptionProvider>();
    final isPremium = subscription.isPremiumActive;
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(l10n.premium),
        backgroundColor: AppTheme.surface,
      ),
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
                  const SizedBox(height: 24),
                  if (isPremium)
                    _buildManageSection(l10n, subscription.premiumExpiresAt)
                  else
                    _buildPaywallSection(l10n),
                ],
              ),
            ),
    );
  }

  Widget _buildHero(AppLocalizations l10n, bool isPremium, DateTime? expiresAt) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFC107), Color(0xFFEAB308)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFEAB308).withValues(alpha: 0.4),
            blurRadius: 20,
            spreadRadius: 2,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          const Icon(Icons.workspace_premium, size: 64, color: Colors.white),
          const SizedBox(height: 12),
          Text(
            isPremium ? l10n.premiumActiveTitle : l10n.goPremiumTitle,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isPremium && expiresAt != null
                ? l10n.premiumRenewsOn.replaceAll(
                    '{date}',
                    DateFormat.yMMMd(Localizations.localeOf(context).toString()).format(expiresAt),
                  )
                : l10n.unlockUnlimitedMatches,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 14,
              fontWeight: FontWeight.w500,
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
        const SizedBox(height: 24),
        _buildPlanCard(
          plan: SubscriptionPlan.yearly,
          title: l10n.planYearly,
          price: '€49.99',
          period: '/${_yearShort(l10n)}',
          subtitle: l10n.yearlySubtitle,
          highlight: true,
          highlightLabel: l10n.bestValue,
        ),
        const SizedBox(height: 12),
        _buildPlanCard(
          plan: SubscriptionPlan.monthly,
          title: l10n.planMonthly,
          price: '€4.99',
          period: '/${_monthShort(l10n)}',
          subtitle: l10n.monthlySubtitle,
          highlight: false,
          highlightLabel: l10n.bestValue,
        ),
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            l10n.paywallFooter,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
        ),
      ],
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
      (l10n.benefitUnlimitedMatches, Icons.all_inclusive),
      (l10n.benefitPremiumBadge, Icons.workspace_premium),
      (l10n.benefitSupportDev, Icons.favorite),
    ];
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.surfaceLight.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.whatYouGet,
            style: const TextStyle(
              color: AppTheme.primary,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          for (final (label, icon) in benefits) ...[
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: AppTheme.primary, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                  ),
                ),
              ],
            ),
            if (label != benefits.last.$1) const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  Widget _buildPlanCard({
    required SubscriptionPlan plan,
    required String title,
    required String price,
    required String period,
    required String subtitle,
    required bool highlight,
    required String highlightLabel,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: _isProcessing ? null : () => _startCheckout(plan),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: highlight ? AppTheme.primary.withValues(alpha: 0.1) : AppTheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: highlight
                ? AppTheme.primary
                : AppTheme.surfaceLight.withValues(alpha: 0.4),
            width: highlight ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (highlight) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppTheme.primary,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            highlightLabel,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      price,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      period,
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                _isProcessing
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primary),
                        ),
                      )
                    : const Icon(Icons.arrow_forward_rounded, color: AppTheme.primary),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildManageSection(AppLocalizations l10n, DateTime? expiresAt) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.surfaceLight.withValues(alpha: 0.4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.statusLabel,
                style: const TextStyle(
                  color: AppTheme.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.check_circle, color: AppTheme.success, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    l10n.premiumActive,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              if (expiresAt != null) ...[
                const SizedBox(height: 8),
                Text(
                  l10n.nextRenewal.replaceAll(
                    '{date}',
                    DateFormat.yMMMd(Localizations.localeOf(context).toString()).format(expiresAt),
                  ),
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          height: 56,
          child: ElevatedButton.icon(
            onPressed: _isProcessing ? null : _openPortal,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 4,
            ),
            icon: _isProcessing
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(Icons.open_in_new),
            label: Text(
              l10n.manageSubscription,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            l10n.manageFooter,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
        ),
      ],
    );
  }
}
