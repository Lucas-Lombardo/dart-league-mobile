import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'app_theme.dart';

String localizedTournamentStatus(AppLocalizations l10n, String status) {
  switch (status) {
    case 'upcoming':
      return l10n.tournamentStatusUpcoming;
    case 'registration_open':
      return l10n.tournamentStatusRegistrationOpen;
    case 'registration_closed':
      return l10n.tournamentStatusRegistrationClosed;
    case 'in_progress':
      return l10n.tournamentStatusInProgress;
    case 'completed':
      return l10n.tournamentStatusCompleted;
    case 'cancelled':
      return l10n.tournamentStatusCancelled;
    default:
      return status;
  }
}

Color tournamentStatusColor(String status) {
  switch (status) {
    case 'registration_open':
      return AppTheme.success;
    case 'in_progress':
      return AppTheme.primary;
    case 'completed':
      return AppTheme.textSecondary;
    case 'cancelled':
      return AppTheme.error;
    default:
      return AppTheme.accent;
  }
}
