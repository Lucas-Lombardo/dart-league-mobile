import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../models/tournament.dart';
import '../providers/app_update_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/subscription_provider.dart';
import 'app_theme.dart';

/// Product spec: everyone can SEE every tournament; trying to enter one you
/// can't join explains exactly why in a popup. This runs every client-side
/// pre-check before registration — the backend enforces all of them again.
class TournamentRegistrationGate {
  TournamentRegistrationGate._();

  /// Returns true when registration may proceed. Otherwise shows the
  /// explanatory dialog and returns false.
  static Future<bool> run(BuildContext context, Tournament tournament) async {
    // 1) App version gate — outdated installs can't enter tournaments.
    final updateProvider = context.read<AppUpdateProvider>();
    final needsUpdate = await updateProvider.requiresTournamentUpdate();
    if (!context.mounted) return false;
    if (needsUpdate) {
      showUpdateRequiredDialog(context);
      return false;
    }

    // 2) Fresh profile. If we can't verify the account, don't silently let
    // the call through (a null user used to skip the email check entirely).
    final authProvider = context.read<AuthProvider>();
    await authProvider.checkAuthStatus();
    if (!context.mounted) return false;
    final user = authProvider.currentUser;
    if (user == null) {
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(l10n.profileUnavailable),
        backgroundColor: AppTheme.error,
      ));
      return false;
    }

    // 3) Verified email is required to enter tournaments.
    if (!user.isEmailVerified) {
      showEmailVerificationDialog(context);
      return false;
    }

    // 4) Capacity.
    if (tournament.currentParticipants >= tournament.maxParticipants) {
      final l10n = AppLocalizations.of(context);
      _showBlockedDialog(
        context,
        icon: Icons.group_off_outlined,
        title: l10n.tournamentFullTitle,
        body: l10n.tournamentFullBody,
      );
      return false;
    }

    // 5) Participation conditions (premium / rank).
    final isPremium = context.read<SubscriptionProvider>().isPremiumActive;
    final eligibility = tournament.eligibilityFor(
      userRank: user.rank,
      isPremium: isPremium,
    );
    if (eligibility != TournamentEligibility.eligible) {
      final l10n = AppLocalizations.of(context);
      final isPremiumIssue = eligibility == TournamentEligibility.premiumRequired;
      final rankLine = tournament.rankRequirementLabel.isNotEmpty
          ? '\n\n${l10n.requiredRank}: ${tournament.rankRequirementLabel}'
          : '';
      _showBlockedDialog(
        context,
        icon: isPremiumIssue ? Icons.workspace_premium : Icons.military_tech_outlined,
        title: l10n.notEligibleTitle,
        body: isPremiumIssue
            ? l10n.tournamentNotEligiblePremium
            : '${l10n.tournamentNotEligibleRank}$rankLine',
      );
      return false;
    }

    return true;
  }

  /// Maps a registration failure onto the right UX: the email and app-version
  /// 403s reopen their dialogs (the server is authoritative — a stale client
  /// pre-check can pass while the server refuses), everything else becomes a
  /// clean localized snackbar instead of a raw "Exception: …" dump.
  static void showRegistrationError(BuildContext context, String rawError) {
    final l10n = AppLocalizations.of(context);
    final raw = rawError.toLowerCase();

    if (raw.contains('email not verified')) {
      showEmailVerificationDialog(context);
      return;
    }
    if (raw.contains('update the app') || raw.contains('mets à jour')) {
      showUpdateRequiredDialog(context);
      return;
    }

    String message;
    if (raw.contains('tournament is full')) {
      message = l10n.tournamentFullBody;
    } else if (raw.contains('registration is not open')) {
      message = l10n.registrationNotOpenError;
    } else if (raw.contains('premium members')) {
      message = l10n.tournamentNotEligiblePremium;
    } else if (raw.contains('requires at least') || raw.contains('limited to')) {
      message = l10n.tournamentNotEligibleRank;
    } else {
      // Strip the technical wrapper the ApiService adds.
      message = rawError
          .replaceFirst('Exception: ', '')
          .replaceFirst(RegExp(r'^(Forbidden|Error \d+): '), '');
    }
    if (raw.contains('refunded')) {
      message = '$message\n${l10n.paymentRefunded}';
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppTheme.error),
    );
  }

  /// "Check your inbox" popup with a resend button that reports the truth
  /// about whether the email was actually sent.
  static void showEmailVerificationDialog(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final authProvider = context.read<AuthProvider>();
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.email_outlined, color: AppTheme.primary, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                l10n.emailNotVerifiedTitle,
                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 20),
              ),
            ),
          ],
        ),
        content: Text(
          l10n.emailVerificationRequired,
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 15),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.close, style: const TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () async {
              final sent = await authProvider.resendVerification();
              if (!dialogContext.mounted) return;
              Navigator.of(dialogContext).pop();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(sent ? l10n.verificationEmailSent : l10n.verificationEmailFailed),
                  backgroundColor: sent ? AppTheme.success : AppTheme.error,
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(l10n.resendEmail),
          ),
        ],
      ),
    );
  }

  /// "Update the app to join tournaments" popup with a store link.
  static void showUpdateRequiredDialog(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final updateProvider = context.read<AppUpdateProvider>();
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.system_update, color: AppTheme.primary, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                l10n.updateRequiredTitle,
                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 20),
              ),
            ),
          ],
        ),
        content: Text(
          l10n.tournamentUpdateRequiredBody,
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 15),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.close, style: const TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              updateProvider.openStore();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(l10n.updateNow),
          ),
        ],
      ),
    );
  }

  static void _showBlockedDialog(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String body,
  }) {
    final l10n = AppLocalizations.of(context);
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(icon, color: AppTheme.accent, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 20),
              ),
            ),
          ],
        ),
        content: Text(
          body,
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 15),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.close, style: const TextStyle(color: AppTheme.textSecondary)),
          ),
        ],
      ),
    );
  }
}
