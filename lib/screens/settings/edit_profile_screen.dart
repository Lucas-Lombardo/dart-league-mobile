import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/app_theme.dart';
import '../../utils/haptic_service.dart';
import '../../widgets/design_system.dart';

/// Username / email editing, moved out of SettingsScreen when its profile
/// section became the read-only player-card hero.
class EditProfileScreen extends StatelessWidget {
  const EditProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.currentUser;
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.editProfile)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DsCard(
            radius: AppTheme.radiusRow,
            padding: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildEditableRow(
                  icon: Icons.person_outline_rounded,
                  label: l10n.username,
                  value: user?.username ?? l10n.accountInfoDefaultUsername,
                  onTap: user == null
                      ? null
                      : () => _showEditUsernameDialog(context, user.username),
                ),
                const Divider(),
                _buildEditableRow(
                  icon: Icons.mail_outline_rounded,
                  label: l10n.email,
                  value: user?.email ?? l10n.accountInfoDefaultEmail,
                  onTap: user == null
                      ? null
                      : () => _showEditEmailDialog(context, user.email),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Caption label over the current value, a pencil on the right.
  Widget _buildEditableRow({
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap == null
          ? null
          : () {
              HapticService.lightImpact();
              onTap();
            },
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 60),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Icon(icon, size: 20, color: const Color(0xFFCBD5E1)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: AppTheme.caption),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.rowTitle,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const Icon(Icons.edit_outlined,
                  size: 18, color: AppTheme.textTertiary),
            ],
          ),
        ),
      ),
    );
  }

  void _showEditUsernameDialog(BuildContext context, String currentUsername) {
    _showEditProfileFieldDialog(
      context: context,
      title: AppLocalizations.of(context).editUsername,
      initialValue: currentUsername,
      keyboardType: TextInputType.text,
      autocorrect: false,
      onSubmit: (value) =>
          context.read<AuthProvider>().updateProfile(username: value),
      successDetail: null,
    );
  }

  void _showEditEmailDialog(BuildContext context, String currentEmail) {
    final l10n = AppLocalizations.of(context);
    _showEditProfileFieldDialog(
      context: context,
      title: l10n.editEmail,
      initialValue: currentEmail,
      keyboardType: TextInputType.emailAddress,
      autocorrect: false,
      onSubmit: (value) =>
          context.read<AuthProvider>().updateProfile(email: value),
      successDetail: l10n.emailChangedVerifyHint,
    );
  }

  void _showEditProfileFieldDialog({
    required BuildContext context,
    required String title,
    required String initialValue,
    required TextInputType keyboardType,
    required bool autocorrect,
    required Future<bool> Function(String value) onSubmit,
    required String? successDetail,
  }) {
    final controller = TextEditingController(text: initialValue);
    final l10n = AppLocalizations.of(context);
    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: keyboardType,
            autocorrect: autocorrect,
            style: AppTheme.rowTitle,
          ),
          actions: [
            TextButton(
              onPressed: isSubmitting
                  ? null
                  : () => Navigator.pop(dialogContext),
              style:
                  TextButton.styleFrom(foregroundColor: AppTheme.textSecondary),
              child: Text(l10n.cancel),
            ),
            ElevatedButton(
              onPressed: isSubmitting
                  ? null
                  : () async {
                      final value = controller.text.trim();
                      if (value.isEmpty || value == initialValue) {
                        Navigator.pop(dialogContext);
                        return;
                      }

                      setDialogState(() => isSubmitting = true);
                      final success = await onSubmit(value);
                      if (!context.mounted) return;

                      if (success) {
                        Navigator.pop(dialogContext);
                        final message = successDetail != null
                            ? '${l10n.profileUpdated}. $successDetail'
                            : l10n.profileUpdated;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(message),
                            backgroundColor: AppTheme.primary,
                          ),
                        );
                      } else {
                        setDialogState(() => isSubmitting = false);
                        final error =
                            context.read<AuthProvider>().errorMessage ??
                            l10n.errorOccurred;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(error),
                            backgroundColor: AppTheme.error,
                          ),
                        );
                      }
                    },
              child: isSubmitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Text(dsSentence(l10n.save)),
            ),
          ],
        ),
      ),
    );
  }
}
