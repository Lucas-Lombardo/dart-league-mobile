import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../models/tournament.dart';
import '../providers/app_update_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/subscription_provider.dart';
import '../screens/settings/subscription_screen.dart';
import '../services/tournament_service.dart';
import 'app_navigator.dart';
import 'app_theme.dart';

/// Product spec: everyone can SEE every tournament; trying to enter one you
/// can't join explains exactly why in a popup. This runs every client-side
/// pre-check before registration — the backend enforces all of them again.
class TournamentRegistrationGate {
  TournamentRegistrationGate._();

  /// Pre-checks before a player creates a tournament: an up-to-date app (the
  /// organiser is registered on creation) and a verified email.
  static Future<bool> runForOrganizer(BuildContext context) async {
    final updateProvider = context.read<AppUpdateProvider>();
    final needsUpdate = await updateProvider.requiresTournamentUpdate();
    if (!context.mounted) return false;
    if (needsUpdate) {
      showUpdateRequiredDialog(context);
      return false;
    }

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
    if (!user.isEmailVerified) {
      showEmailVerificationDialog(context);
      return false;
    }
    return true;
  }

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

    // 6) Players without premium: 2 tournaments a month.
    return checkMonthlyQuota(context, tournament.scheduledDate);
  }

  /// Fallback limit for the popup when the server refused a registration on
  /// its own (a stale pre-check). Keep in sync with
  /// TournamentService.FREE_MONTHLY_TOURNAMENT_LIMIT (backend).
  static const int freeMonthlyLimit = 2;

  /// Every tournament is free; a player without premium joins at most 2 a
  /// month (by start date). Asks the server what's left for [date]'s month:
  /// shows the popup and returns false when it's used up. A failed lookup
  /// lets the call through — the server enforces the quota again.
  static Future<bool> checkMonthlyQuota(BuildContext context, DateTime date) async {
    final MonthlyTournamentQuota quota;
    try {
      quota = await TournamentService.getMonthlyQuota(date);
    } catch (e) {
      debugPrint('Monthly tournament quota lookup failed: $e');
      return context.mounted;
    }
    if (!context.mounted) return false;
    if (!quota.reached) return true;
    showMonthlyLimitDialog(context, limit: quota.limit!, date: date);
    return false;
  }

  /// "2 tournois par mois": wait for next month, or go premium.
  static void showMonthlyLimitDialog(
    BuildContext context, {
    required int limit,
    DateTime? date,
  }) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => TournamentMonthlyLimitDialog(
        limit: limit,
        date: date,
        onLater: () => Navigator.of(dialogContext).pop(),
        onPremium: () {
          Navigator.of(dialogContext).pop();
          if (context.mounted) {
            AppNavigator.toScreen(context, const SubscriptionScreen());
          }
        },
      ),
    );
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
    // The server's monthly-quota refusal (EN / FR), when the pre-check missed it.
    if (raw.contains('tournaments this month') ||
        raw.contains('tournaments that month') ||
        raw.contains('tournois ce mois')) {
      showMonthlyLimitDialog(context, limit: freeMonthlyLimit);
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

/// The monthly-quota popup of players without premium (see
/// [TournamentRegistrationGate.checkMonthlyQuota]). Public so the preview
/// test can render it.
class TournamentMonthlyLimitDialog extends StatelessWidget {
  final int limit;

  /// The tournament's start; null = this month.
  final DateTime? date;
  final VoidCallback onLater;
  final VoidCallback onPremium;

  const TournamentMonthlyLimitDialog({
    super.key,
    required this.limit,
    this.date,
    required this.onLater,
    required this.onPremium,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final now = DateTime.now();
    final local = date?.toLocal();
    final thisMonth =
        local == null || (local.year == now.year && local.month == now.month);
    final body = thisMonth
        ? l10n.tournamentMonthlyLimitBody(limit)
        : l10n.tournamentMonthlyLimitBodyOtherMonth(
            limit,
            DateFormat('MMMM', Localizations.localeOf(context).toString())
                .format(local),
          );

    return AlertDialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          const Icon(Icons.workspace_premium, color: AppTheme.accent, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              l10n.tournamentMonthlyLimitTitle(limit),
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
          onPressed: onLater,
          child: Text(
            l10n.tournamentMonthlyLimitLater,
            style: const TextStyle(color: AppTheme.textSecondary),
          ),
        ),
        ElevatedButton(
          onPressed: onPremium,
          child: Text(l10n.upgradeToPremium),
        ),
      ],
    );
  }
}
