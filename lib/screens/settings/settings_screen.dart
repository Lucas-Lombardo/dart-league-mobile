import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../providers/auth_provider.dart';
import '../../providers/locale_provider.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/haptic_service.dart';
import '../../utils/app_theme.dart';
import '../../utils/rank_translation.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _hapticEnabled = true;
  String _appVersion = 'Loading...';

  @override
  void initState() {
    super.initState();
    _hapticEnabled = HapticService.isEnabled;
    _loadAppVersion();
  }

  Future<void> _loadAppVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      setState(() {
        _appVersion = '${packageInfo.version} (${packageInfo.buildNumber})';
      });
    } catch (e) {
      setState(() {
        _appVersion = 'Unknown';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.currentUser;
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(l10n.settings),
        backgroundColor: AppTheme.surface,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        children: [
          _buildSection(l10n.profile.toUpperCase()),
          _buildAccountInfo(user?.username ?? 'User', user?.email ?? 'No email'),
          _buildAccountInfo(l10n.elo, '${user?.elo ?? 0}'),
          _buildAccountInfo(l10n.rank, user?.rank != null ? RankTranslation.translate(l10n, user!.rank) : 'Unranked'),
          
          const SizedBox(height: 24),
          _buildSection(l10n.preferences.toUpperCase()),
          _buildLanguageTile(l10n),
          _buildSwitchTile(
            'Haptic Feedback',
            'Vibrate on button presses',
            Icons.vibration,
            _hapticEnabled,
            (value) {
              setState(() {
                _hapticEnabled = value;
                HapticService.setEnabled(value);
              });
              if (value) {
                HapticService.mediumImpact();
              }
            },
          ),
          
          const SizedBox(height: 24),
          _buildSection(l10n.about.toUpperCase()),
          _buildInfoTile(l10n.appVersion, _appVersion, Icons.info_outline),
          _buildInfoTile(l10n.developer, 'Dart Legends Team', Icons.code),
          
          const SizedBox(height: 32),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ElevatedButton.icon(
              onPressed: () => _showLogoutDialog(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.error,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 4,
              ),
              icon: const Icon(Icons.logout),
              label: Text(
                l10n.logout.toUpperCase(),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: OutlinedButton.icon(
              onPressed: () => _showDeleteAccountDialog(context),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.error,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                side: const BorderSide(color: AppTheme.error, width: 2),
              ),
              icon: const Icon(Icons.delete_forever),
              label: Text(
                l10n.deleteAccount.toUpperCase(),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSection(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Text(
        title.toUpperCase(),
        style: AppTheme.labelLarge.copyWith(color: AppTheme.primary),
      ),
    );
  }

  Widget _buildAccountInfo(String label, String value) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.surfaceLight.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 16,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLanguageTile(AppLocalizations l10n) {
    final localeProvider = context.watch<LocaleProvider>();
    final currentLanguage = localeProvider.locale.languageCode;
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.surfaceLight.withValues(alpha: 0.3)),
      ),
      child: InkWell(
        onTap: () => _showLanguageDialog(context),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.language, color: AppTheme.primary),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.language,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    currentLanguage == 'fr' ? 'Français' : 'English',
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppTheme.textSecondary),
          ],
        ),
      ),
    );
  }

  Widget _buildSwitchTile(
    String title,
    String subtitle,
    IconData icon,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.surfaceLight.withValues(alpha: 0.3)),
      ),
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
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: AppTheme.primary,
            activeTrackColor: AppTheme.primary.withValues(alpha: 0.3),
            inactiveTrackColor: AppTheme.surfaceLight,
          ),
        ],
      ),
    );
  }

  Widget _buildInfoTile(String label, String value, IconData icon) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.surfaceLight.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.textSecondary),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 16,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  void _showLogoutDialog(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          l10n.logout,
          style: const TextStyle(color: Colors.white),
        ),
        content: Text(
          l10n.deleteAccountConfirm,
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel, style: const TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await context.read<AuthProvider>().logout();
              if (context.mounted) {
                Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(l10n.logout),
          ),
        ],
      ),
    );
  }

  void _showLanguageDialog(BuildContext context) {
    final localeProvider = context.read<LocaleProvider>();
    final currentLanguage = localeProvider.locale.languageCode;
    final l10n = AppLocalizations.of(context);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          l10n.changeLanguage,
          style: const TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildLanguageOption('English', 'en', currentLanguage, () {
              localeProvider.setLocale('en');
              Navigator.pop(context);
            }),
            const SizedBox(height: 8),
            _buildLanguageOption('Français', 'fr', currentLanguage, () {
              localeProvider.setLocale('fr');
              Navigator.pop(context);
            }),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel, style: const TextStyle(color: AppTheme.textSecondary)),
          ),
        ],
      ),
    );
  }

  Widget _buildLanguageOption(String name, String code, String currentCode, VoidCallback onTap) {
    final isSelected = code == currentCode;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primary.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppTheme.primary : AppTheme.surfaceLight.withValues(alpha: 0.3),
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                name,
                style: TextStyle(
                  color: isSelected ? AppTheme.primary : Colors.white,
                  fontSize: 16,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle, color: AppTheme.primary),
          ],
        ),
      ),
    );
  }

  void _showDeleteAccountDialog(BuildContext context) {
    bool isDeleting = false;
    final l10n = AppLocalizations.of(context);
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: AppTheme.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
            l10n.deleteAccount,
            style: const TextStyle(color: AppTheme.error, fontWeight: FontWeight.bold),
          ),
          content: Text(
            l10n.deleteAccountWarning,
            style: const TextStyle(color: AppTheme.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: isDeleting ? null : () => Navigator.pop(context),
              child: Text(l10n.cancel, style: const TextStyle(color: AppTheme.textSecondary)),
            ),
            ElevatedButton(
              onPressed: isDeleting ? null : () async {
                setState(() {
                  isDeleting = true;
                });
                
                final success = await context.read<AuthProvider>().deleteAccount();
                
                if (context.mounted) {
                  Navigator.pop(context);
                  
                  if (success) {
                    Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          context.read<AuthProvider>().errorMessage ?? l10n.errorOccurred,
                        ),
                        backgroundColor: AppTheme.error,
                      ),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.error,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: isDeleting 
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Text(l10n.yes),
            ),
          ],
        ),
      ),
    );
  }
}
