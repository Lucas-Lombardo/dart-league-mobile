import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../providers/app_update_provider.dart';
import '../utils/app_theme.dart';
import '../utils/haptic_service.dart';
import 'design_system.dart';

/// Dismissible "update available" banner under the home header: a tinted
/// primary card (the only colored border of the screen — it expresses a
/// state), the title + message, a small "Mettre à jour" pill and a close
/// button. Self-gating: renders nothing unless an update is available and
/// not already dismissed.
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

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: DsCard(
        radius: AppTheme.radiusRow,
        color: AppTheme.primary.withValues(alpha: 0.08),
        side: BorderSide(color: AppTheme.primaryLight.withValues(alpha: 0.3)),
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        child: Row(
          children: [
            const Icon(
              Icons.system_update_alt_rounded,
              size: 18,
              color: AppTheme.primaryLight,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l10n.updateAvailableTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    message,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.caption,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Material(
              color: AppTheme.primary,
              borderRadius: BorderRadius.circular(999),
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () {
                  HapticService.lightImpact();
                  context.read<AppUpdateProvider>().openStore();
                },
                child: Container(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  alignment: Alignment.center,
                  child: Text(
                    l10n.updateNow,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      height: 1,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            DsIconButton(
              icon: Icons.close_rounded,
              size: 32,
              tooltip: MaterialLocalizations.of(context).closeButtonLabel,
              onTap: () => context.read<AppUpdateProvider>().dismiss(),
            ),
          ],
        ),
      ),
    );
  }
}
