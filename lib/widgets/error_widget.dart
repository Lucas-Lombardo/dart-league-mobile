import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../utils/app_theme.dart';
import 'design_system.dart';

/// Inline error state: one surface card with the 32 px error icon,
/// "Oups !", the message as a caption and an outlined "Réessayer".
class CustomErrorWidget extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  final IconData icon;

  const CustomErrorWidget({
    super.key,
    required this.message,
    this.onRetry,
    this.icon = Icons.error_outline_rounded,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: DsCard(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 32, color: AppTheme.error),
              const SizedBox(height: 12),
              Text(
                l10n.oops,
                textAlign: TextAlign.center,
                style: AppTheme.rowTitle,
              ),
              const SizedBox(height: 6),
              Text(
                message,
                textAlign: TextAlign.center,
                style: AppTheme.caption,
              ),
              if (onRetry != null) ...[
                const SizedBox(height: 20),
                SizedBox(
                  height: 44,
                  child: OutlinedButton(
                    onPressed: onRetry,
                    child: Text(dsSentence(l10n.tryAgainUpper)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class NetworkErrorWidget extends StatelessWidget {
  final VoidCallback? onRetry;

  const NetworkErrorWidget({super.key, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return CustomErrorWidget(
      message: AppLocalizations.of(context).unableToConnectMessage,
      icon: Icons.wifi_off_rounded,
      onRetry: onRetry,
    );
  }
}
