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
import '../../widgets/design_system.dart';

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
      appBar: AppBar(title: Text(l10n.referralTitle)),
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
                    const SizedBox(height: 18),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        l10n.referralAdminContactNote,
                        textAlign: TextAlign.center,
                        style: AppTheme.caption.copyWith(
                          color: AppTheme.textTertiary,
                          height: 1.5,
                        ),
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
    return DsCard(
      padding: const EdgeInsets.all(24),
      child: Text(
        l10n.referralErrorUnknown,
        textAlign: TextAlign.center,
        style: AppTheme.bodyMedium,
      ),
    );
  }

  /// Before the code exists: the value proposition on a flat card, then
  /// either the create button (the one filled block) or the email gate that
  /// blocks it.
  Widget _buildCreateSection(AppLocalizations l10n, ReferralOverview overview) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DsCard(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 22),
          child: Column(
            children: [
              Text(
                _money(overview.rewardYearlyCents),
                style: AppTheme.displayLarge,
              ),
              const SizedBox(height: 10),
              Text(
                l10n.referralCreateCodeSubtitle,
                textAlign: TextAlign.center,
                style: AppTheme.sectionTitle,
              ),
              const SizedBox(height: 4),
              Text(
                l10n.referralHaveCodeSubtitle(overview.refereeTrialDays),
                textAlign: TextAlign.center,
                style: AppTheme.caption.copyWith(fontSize: 13),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (!overview.canCreateCode)
          _buildEmailGate(l10n)
        else
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: context.watch<ReferralProvider>().isMutating
                  ? null
                  : _createCode,
              child: Text(dsSentence(l10n.referralCreateCodeTitle)),
            ),
          ),
      ],
    );
  }

  Widget _buildEmailGate(AppLocalizations l10n) {
    return DsCard(
      radius: AppTheme.radiusRow,
      padding: const EdgeInsets.all(16),
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
                  color: AppTheme.textSecondary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  l10n.referralEmailGateBody,
                  style: AppTheme.bodyMedium.copyWith(
                    color: AppTheme.textPrimary,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 44,
            child: OutlinedButton(
              onPressed: _resendingEmail ? null : _resendVerification,
              child: _resendingEmail
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.textSecondary,
                      ),
                    )
                  : Text(dsSentence(l10n.referralEmailGateAction)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCodeCard(AppLocalizations l10n, ReferralOverview overview) {
    final code = overview.code!;
    return DsCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.referralYourCode.toUpperCase(), style: AppTheme.labelSmall),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    code,
                    style: AppTheme.displayMedium.copyWith(
                      fontSize: 26,
                      letterSpacing: 1.5,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              DsIconButton(
                icon: Icons.content_copy_rounded,
                tooltip: l10n.referralCodeCopied,
                onTap: () => _copyCode(code),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            l10n.referralCodeExplainer(overview.refereeTrialDays),
            style: AppTheme.caption.copyWith(fontSize: 13, height: 1.45),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 52,
            child: ElevatedButton.icon(
              onPressed: () => _shareCode(code, overview.refereeTrialDays),
              icon: const Icon(Icons.ios_share_rounded, size: 18),
              label: Text(dsSentence(l10n.referralShareCode)),
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
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.rowTitle,
                      ),
                    ),
                    if (highlight) ...[
                      const SizedBox(width: 8),
                      const DsPill(label: '×2'),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.caption,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            amount,
            style: AppTheme.displayMedium.copyWith(
              fontSize: 22,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      );
    }

    return DsCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.referralRewardsTitle.toUpperCase(),
              style: AppTheme.labelSmall),
          const SizedBox(height: 14),
          tier(
            title: l10n.referralMonthlyLabel,
            subtitle: l10n.referralMonthlySubtitle,
            amount: _money(overview.rewardMonthlyCents),
          ),
          const Divider(height: 26),
          tier(
            title: l10n.referralYearlyLabel,
            subtitle: l10n.referralYearlySubtitle,
            amount: _money(overview.rewardYearlyCents),
            highlight: true,
          ),
        ],
      ),
    );
  }

  Widget _buildRefereesCard(AppLocalizations l10n, ReferralOverview overview) {
    return DsCard(
      radius: AppTheme.radiusRow,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(
                    l10n.referralRefereesTitle.toUpperCase(),
                    style: AppTheme.labelSmall,
                  ),
                ),
                if (overview.earnedCents > 0)
                  Text(
                    l10n.referralEarnedTotal(_money(overview.earnedCents)),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.success,
                    ),
                  )
                else if (overview.pendingCents > 0)
                  Text(
                    l10n.referralPendingTotal(_money(overview.pendingCents)),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.primaryLight,
                    ),
                  ),
              ],
            ),
          ),
          if (overview.referees.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 16),
              child: Text(
                l10n.referralNoRefereesYet,
                style: AppTheme.bodyMedium,
              ),
            )
          else
            for (var i = 0; i < overview.referees.length; i++) ...[
              if (i > 0) const Divider(),
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
        icon = Icons.check_circle_outline_rounded;
        color = AppTheme.success;
        subtitle = l10n.referralStatusRewardPaid(amount);
        break;
      case ReferralStatus.rewardDue:
        icon = Icons.euro_rounded;
        color = AppTheme.primaryLight;
        subtitle = l10n.referralStatusRewardDue(amount);
        break;
      case ReferralStatus.subscribed:
        icon = Icons.hourglass_bottom_rounded;
        color = AppTheme.primaryLight;
        subtitle = l10n.referralStatusSubscribed(amount);
        break;
      case ReferralStatus.cancelled:
        icon = Icons.block_rounded;
        color = AppTheme.textTertiary;
        subtitle = l10n.referralStatusCancelled;
        break;
      case ReferralStatus.trial:
        // The server keeps `trial` until a subscription; the end date tells
        // whether the free days are still running.
        final ended = referee.trialEndsAt?.isBefore(DateTime.now()) ?? false;
        if (ended) {
          icon = Icons.timer_off_outlined;
          color = AppTheme.textTertiary;
          subtitle = l10n.referralStatusTrialEnded;
        } else {
          icon = Icons.schedule_rounded;
          color = AppTheme.primaryLight;
          subtitle = l10n.referralStatusTrial;
        }
        break;
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 52),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    referee.username,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.rowTitle,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.caption.copyWith(color: color),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
