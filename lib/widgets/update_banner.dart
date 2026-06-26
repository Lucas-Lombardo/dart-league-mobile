import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../providers/app_update_provider.dart';
import '../utils/app_theme.dart';
import '../utils/haptic_service.dart';

/// Dismissible "update available" banner for the home screen. Self-gating:
/// renders nothing unless an update is available and not already dismissed.
class UpdateBanner extends StatelessWidget {
  const UpdateBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppUpdateProvider>();
    if (!provider.shouldShowBanner) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context);
    final message = (provider.message != null && provider.message!.isNotEmpty)
        ? provider.message!
        : l10n.updateAvailableBody;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.system_update, color: AppTheme.primary, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.updateAvailableTitle,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 2),
                Text(
                  message,
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () {
              HapticService.lightImpact();
              context.read<AppUpdateProvider>().openStore();
            },
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: AppTheme.primary,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text(
              l10n.updateNow,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
          IconButton(
            onPressed: () {
              HapticService.lightImpact();
              context.read<AppUpdateProvider>().dismiss();
            },
            icon: const Icon(Icons.close, color: AppTheme.textSecondary, size: 20),
            tooltip: MaterialLocalizations.of(context).closeButtonLabel,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}
