import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/app_theme.dart';
import '../../utils/haptic_service.dart';

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
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(l10n.editProfile),
        backgroundColor: AppTheme.surface,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        children: [
          _buildEditableRow(
            icon: Icons.person_outline,
            label: l10n.username,
            value: user?.username ?? l10n.accountInfoDefaultUsername,
            onTap: user == null
                ? null
                : () => _showEditUsernameDialog(context, user.username),
          ),
          _buildEditableRow(
            icon: Icons.mail_outline,
            label: l10n.email,
            value: user?.email ?? l10n.accountInfoDefaultEmail,
            onTap: user == null
                ? null
                : () => _showEditEmailDialog(context, user.email),
          ),
        ],
      ),
    );
  }

  Widget _buildEditableRow({
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback? onTap,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.surfaceLight.withValues(alpha: 0.3)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap == null
            ? null
            : () {
                HapticService.lightImpact();
                onTap();
              },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: AppTheme.primary),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      value,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.edit, color: AppTheme.textSecondary, size: 18),
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
          backgroundColor: AppTheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(title, style: const TextStyle(color: Colors.white)),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: keyboardType,
            autocorrect: autocorrect,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: AppTheme.surfaceLight.withValues(alpha: 0.3),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.primary),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSubmitting
                  ? null
                  : () => Navigator.pop(dialogContext),
              child: Text(
                l10n.cancel,
                style: const TextStyle(color: AppTheme.textSecondary),
              ),
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
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: isSubmitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Text(l10n.save),
            ),
          ],
        ),
      ),
    );
  }
}
