import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/referral_provider.dart';
import '../../services/auth_service.dart';
import '../../services/referral_service.dart';
import '../../utils/app_theme.dart';
import '../../utils/haptic_service.dart';

/// The referrer side: create the code, see the two reward tiers, follow each
/// referee. Rewards are paid by hand, so nothing here ever promises a transfer
/// — only that an admin will get in touch.
class ReferralScreen extends StatefulWidget {
  const ReferralScreen({super.key});

  @override
  State<ReferralScreen> createState() => _ReferralScreenState();
}

class _ReferralScreenState extends State<ReferralScreen> {
  bool _resendingEmail = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ReferralProvider>().loadOverview();
    });
  }

  String _money(int cents) {
    if (cents % 100 == 0) return '${cents ~/ 100} €';
    return '${(cents / 100).toStringAsFixed(2)} €';
  }

  Future<void> _createCode() async {
    HapticService.mediumImpact();
    final referral = context.read<ReferralProvider>();
    final ok = await referral.createCode();
    if (!mounted || ok) return;
    final l10n = AppLocalizations.of(context);
    final message = referral.lastError == ReferralError.emailNotVerified
        ? l10n.referralErrorEmailNotVerified
        : l10n.referralErrorUnknown;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppTheme.error),
    );
  }

  Future<void> _copyCode(String code) async {
    HapticService.lightImpact();
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context).referralCodeCopied),
        backgroundColor: AppTheme.success,
      ),
    );
  }

  Future<void> _shareCode(String code, int days) async {
    HapticService.lightImpact();
    final l10n = AppLocalizations.of(context);
    await SharePlus.instance.share(
      ShareParams(text: l10n.referralShareMessage(code, days)),
    );
  }

  Future<void> _resendVerification() async {
    if (_resendingEmail) return;
    HapticService.lightImpact();
    setState(() => _resendingEmail = true);
    final l10n = AppLocalizations.of(context);
    try {
      await AuthService.resendVerification();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.referralEmailGateSent),
          backgroundColor: AppTheme.success,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.referralErrorUnknown),
          backgroundColor: AppTheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _resendingEmail = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final referral = context.watch<ReferralProvider>();
    final overview = referral.overview;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(l10n.referralTitle),
        backgroundColor: AppTheme.surface,
      ),
      body: referral.isLoading && overview == null
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primary),
            )
          : RefreshIndicator(
              color: AppTheme.primary,
              onRefresh: referral.loadOverview,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  if (overview == null)
                    _buildErrorCard(l10n)
                  else ...[
                    if (overview.code == null)
                      _buildCreateSection(l10n, overview)
                    else
                      _buildCodeCard(l10n, overview),
                    const SizedBox(height: 14),
                    _buildTiersCard(l10n, overview),
                    const SizedBox(height: 14),
                    _buildRefereesCard(l10n, overview),
                    const SizedBox(height: 20),
                    Text(
                      l10n.referralAdminContactNote,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 12.5,
                        height: 1.5,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildErrorCard(AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.surfaceLight.withValues(alpha: 0.4)),
      ),
      child: Text(
        l10n.referralErrorUnknown,
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 15),
      ),
    );
  }

  /// Before the code exists: the value proposition, then either the create
  /// button or the email gate that blocks it.
  Widget _buildCreateSection(AppLocalizations l10n, ReferralOverview overview) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 26),
          decoration: BoxDecoration(
            gradient: AppTheme.primaryGradient,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primary.withValues(alpha: 0.35),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            children: [
              Text(
                _money(overview.rewardYearlyCents),
                style: const TextStyle(
                  fontSize: 46,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  height: 1,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.referralCreateCodeSubtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                l10n.referralHaveCodeSubtitle(overview.refereeTrialDays),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.5,
                  color: Colors.white.withValues(alpha: 0.9),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (!overview.canCreateCode)
          _buildEmailGate(l10n)
        else
          SizedBox(
            height: 58,
            child: ElevatedButton(
              onPressed: context.watch<ReferralProvider>().isMutating
                  ? null
                  : _createCode,
              style: AppTheme.primaryButtonStyle,
              child: Text(l10n.referralCreateCodeTitle),
            ),
          ),
      ],
    );
  }

  Widget _buildEmailGate(AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFEAB308).withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFEAB308).withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 1),
                child: Icon(
                  Icons.mark_email_unread_outlined,
                  color: Color(0xFFEAB308),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  l10n.referralEmailGateBody,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: Color(0xFFFDE68A),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 46,
            child: ElevatedButton(
              onPressed: _resendingEmail ? null : _resendVerification,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEAB308),
                foregroundColor: AppTheme.background,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              child: _resendingEmail
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: AppTheme.background,
                      ),
                    )
                  : Text(l10n.referralEmailGateAction),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCodeCard(AppLocalizations l10n, ReferralOverview overview) {
    final code = overview.code!;
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
            l10n.referralYourCode,
            style: const TextStyle(
              color: AppTheme.primary,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    code,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 27,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _copyCode(code),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.copy,
                    color: AppTheme.primary,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            l10n.referralCodeExplainer(overview.refereeTrialDays),
            style: const TextStyle(
              fontSize: 13,
              height: 1.45,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 52,
            child: ElevatedButton.icon(
              onPressed: () => _shareCode(code, overview.refereeTrialDays),
              style: AppTheme.primaryButtonStyle,
              icon: const Icon(Icons.share, size: 19),
              label: Text(l10n.referralShareCode),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTiersCard(AppLocalizations l10n, ReferralOverview overview) {
    Widget tier({
      required String title,
      required String subtitle,
      required String amount,
      required Color color,
      bool highlight = false,
    }) {
      return Row(
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
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    if (highlight) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Text(
                          '×2',
                          style: TextStyle(
                            color: color,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            amount,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.surfaceLight.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.referralRewardsTitle,
            style: const TextStyle(
              color: AppTheme.primary,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          tier(
            title: l10n.referralMonthlyLabel,
            subtitle: l10n.referralMonthlySubtitle,
            amount: _money(overview.rewardMonthlyCents),
            color: AppTheme.primary,
          ),
          Divider(
            height: 26,
            thickness: 1,
            color: AppTheme.surfaceLight.withValues(alpha: 0.5),
          ),
          tier(
            title: l10n.referralYearlyLabel,
            subtitle: l10n.referralYearlySubtitle,
            amount: _money(overview.rewardYearlyCents),
            color: const Color(0xFFEAB308),
            highlight: true,
          ),
        ],
      ),
    );
  }

  Widget _buildRefereesCard(AppLocalizations l10n, ReferralOverview overview) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.surfaceLight.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(
                    l10n.referralRefereesTitle,
                    style: const TextStyle(
                      color: AppTheme.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
                if (overview.earnedCents > 0)
                  Text(
                    l10n.referralEarnedTotal(_money(overview.earnedCents)),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.success,
                    ),
                  )
                else if (overview.pendingCents > 0)
                  Text(
                    l10n.referralPendingTotal(_money(overview.pendingCents)),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.primary,
                    ),
                  ),
              ],
            ),
          ),
          if (overview.referees.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
              child: Text(
                l10n.referralNoRefereesYet,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppTheme.textSecondary,
                ),
              ),
            )
          else
            for (var i = 0; i < overview.referees.length; i++) ...[
              if (i > 0)
                Divider(
                  height: 1,
                  thickness: 1,
                  indent: 68,
                  color: AppTheme.surfaceLight.withValues(alpha: 0.35),
                ),
              _buildRefereeRow(l10n, overview.referees[i]),
            ],
        ],
      ),
    );
  }

  Widget _buildRefereeRow(AppLocalizations l10n, ReferralReferee referee) {
    late final IconData icon;
    late final Color color;
    late final String subtitle;
    final amount = _money(referee.rewardAmountCents ?? 0);

    switch (referee.status) {
      case ReferralStatus.rewardPaid:
        icon = Icons.check;
        color = AppTheme.success;
        subtitle = l10n.referralStatusRewardPaid(amount);
        break;
      case ReferralStatus.rewardDue:
        icon = Icons.euro;
        color = AppTheme.primary;
        subtitle = l10n.referralStatusRewardDue(amount);
        break;
      case ReferralStatus.subscribed:
        icon = Icons.hourglass_bottom;
        color = AppTheme.primary;
        subtitle = l10n.referralStatusSubscribed(amount);
        break;
      case ReferralStatus.cancelled:
        icon = Icons.block;
        color = AppTheme.textSecondary;
        subtitle = l10n.referralStatusCancelled;
        break;
      case ReferralStatus.trial:
        icon = Icons.schedule;
        color = const Color(0xFFEAB308);
        subtitle = l10n.referralStatusTrial;
        break;
    }

    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  referee.username,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                Text(subtitle, style: TextStyle(fontSize: 13, color: color)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
