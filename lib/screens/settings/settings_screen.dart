import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../providers/auth_provider.dart';
import '../../providers/game_provider.dart';
import '../../providers/locale_provider.dart';
import '../../providers/subscription_provider.dart';
import '../../l10n/app_localizations.dart';
import '../../models/user.dart';
import '../../utils/app_navigator.dart';
import '../../utils/haptic_service.dart';
import '../../utils/app_theme.dart';
import '../../utils/dart_caller_service.dart';
import '../../utils/dart_sound_service.dart';
import '../../utils/rank_translation.dart';
import '../../utils/rank_utils.dart';
import 'edit_profile_screen.dart';
import 'subscription_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _appVersion = 'Loading...';
  bool _callerEnabled = DartCallerService.enabled;
  bool _hapticsEnabled = HapticService.isEnabled;
  final Map<SoundCategory, bool> _soundEnabled = {
    for (final c in SoundCategory.values) c: DartSoundService.isEnabled(c),
  };

  @override
  void initState() {
    super.initState();
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
          _buildProfileHero(l10n, user),

          const SizedBox(height: 24),
          _buildSection(l10n.premium.toUpperCase()),
          _buildSubscriptionTile(l10n),

          const SizedBox(height: 24),
          _buildSection(l10n.preferences.toUpperCase()),
          _buildGroupCard([_buildLanguageRow(l10n)]),

          const SizedBox(height: 24),
          _buildSection(l10n.soundsSection.toUpperCase()),
          _buildGroupCard([
            _buildToggleRow(
              icon: Icons.record_voice_over,
              title: l10n.voiceCaller,
              subtitle: l10n.voiceCallerDescription,
              value: _callerEnabled,
              onChanged: (value) {
                HapticService.selectionClick();
                setState(() => _callerEnabled = value);
                DartCallerService.setEnabled(value);
                // Preview so users hear what they just turned on.
                if (value) DartCallerService.callScore(180);
              },
            ),
            _buildToggleRow(
              icon: Icons.adjust,
              title: l10n.soundDartHit,
              subtitle: l10n.soundDartHitDescription,
              value: _soundEnabled[SoundCategory.dartHit]!,
              onChanged: (value) => _setSoundCategory(
                SoundCategory.dartHit,
                value,
                preview: () =>
                    DartSoundService.playDartHit(20, ScoreMultiplier.triple),
              ),
            ),
            _buildToggleRow(
              icon: Icons.campaign,
              title: l10n.soundTurn,
              subtitle: l10n.soundTurnDescription,
              value: _soundEnabled[SoundCategory.turn]!,
              onChanged: (value) => _setSoundCategory(
                SoundCategory.turn,
                value,
                preview: DartSoundService.playYourTurn,
              ),
            ),
            _buildToggleRow(
              icon: Icons.celebration,
              title: l10n.soundGameEffects,
              subtitle: l10n.soundGameEffectsDescription,
              value: _soundEnabled[SoundCategory.gameEffects]!,
              onChanged: (value) => _setSoundCategory(
                SoundCategory.gameEffects,
                value,
                preview: DartSoundService.playBust,
              ),
            ),
            _buildToggleRow(
              icon: Icons.person_search,
              title: l10n.soundMatchFound,
              subtitle: l10n.soundMatchFoundDescription,
              value: _soundEnabled[SoundCategory.matchFound]!,
              onChanged: (value) => _setSoundCategory(
                SoundCategory.matchFound,
                value,
                preview: DartSoundService.playMatchFound,
              ),
            ),
            _buildToggleRow(
              icon: Icons.vibration,
              title: l10n.haptics,
              subtitle: l10n.hapticsDescription,
              value: _hapticsEnabled,
              onChanged: (value) {
                setState(() => _hapticsEnabled = value);
                HapticService.setEnabled(value);
                if (value) HapticService.mediumImpact();
              },
            ),
          ]),

          const SizedBox(height: 24),
          _buildSection(l10n.about.toUpperCase()),
          _buildGroupCard([
            _buildInfoRow(l10n.appVersion, _appVersion, Icons.info_outline),
            _buildInfoRow(l10n.developer, 'Lucas Lombardo', Icons.code),
          ], dividerIndent: 56),

          const SizedBox(height: 24),
          _buildSection(l10n.accountSection.toUpperCase()),
          _buildGroupCard([
            _buildDangerRow(
              icon: Icons.logout,
              label: l10n.logout,
              onTap: () => _showLogoutDialog(context),
            ),
            _buildDangerRow(
              icon: Icons.delete_forever,
              label: l10n.deleteAccount,
              onTap: () => _showDeleteAccountDialog(context),
            ),
          ], borderColor: AppTheme.error.withValues(alpha: 0.45)),
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

  Widget _buildProfileHero(AppLocalizations l10n, User? user) {
    final isPremium = context.watch<SubscriptionProvider>().isPremiumActive;
    final username = user?.username ?? l10n.accountInfoDefaultUsername;
    final initial = username.isNotEmpty ? username[0].toUpperCase() : '?';
    final rankLabel = user?.rank != null
        ? RankTranslation.translate(l10n, user!.rank)
        : 'Unranked';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.surface, Color(0xFF16233B)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isPremium
              ? const Color(0xFFEAB308).withValues(alpha: 0.5)
              : AppTheme.surfaceLight.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF38BDF8), Color(0xFF0369A1)],
              ),
              border: Border.all(
                color: isPremium ? const Color(0xFFEAB308) : Colors.transparent,
                width: 2,
              ),
            ),
            child: Text(
              initial,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 30,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  username,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (isPremium) ...[
                const SizedBox(width: 6),
                const Icon(
                  Icons.workspace_premium,
                  color: Color(0xFFEAB308),
                  size: 20,
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              _heroChip(
                leading: const Icon(
                  Icons.military_tech,
                  size: 15,
                  color: AppTheme.primary,
                ),
                label: 'ELO ${user?.elo ?? 0}',
              ),
              _heroChip(
                leading: RankUtils.getRankBadge(
                  user?.rank ?? 'unranked',
                  size: 16,
                ),
                label: rankLabel,
                color: const Color(0xFFEAB308),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: user == null
                ? null
                : () {
                    HapticService.lightImpact();
                    AppNavigator.toScreen(context, const EditProfileScreen());
                  },
            style: TextButton.styleFrom(
              backgroundColor: AppTheme.primary.withValues(alpha: 0.14),
              foregroundColor: AppTheme.primary,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.edit, size: 16),
            label: Text(
              l10n.editProfile,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroChip({
    required Widget leading,
    required String label,
    Color color = AppTheme.primary,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          leading,
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  // One bordered surface per section, rows separated by an inset hairline —
  // replaces the old one-Container-per-tile layout.
  Widget _buildGroupCard(
    List<Widget> rows, {
    Color? borderColor,
    double dividerIndent = 76,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: borderColor ?? AppTheme.surfaceLight.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 1,
                indent: dividerIndent,
                color: AppTheme.surfaceLight.withValues(alpha: 0.35),
              ),
            rows[i],
          ],
        ],
      ),
    );
  }

  Widget _buildDangerRow({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.error.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AppTheme.error),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: AppTheme.error,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLanguageRow(AppLocalizations l10n) {
    final localeProvider = context.watch<LocaleProvider>();
    final currentLanguage = localeProvider.locale.languageCode;

    return InkWell(
      onTap: () => _showLanguageDialog(context),
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

  void _setSoundCategory(
    SoundCategory category,
    bool value, {
    VoidCallback? preview,
  }) {
    HapticService.selectionClick();
    setState(() => _soundEnabled[category] = value);
    DartSoundService.setEnabled(category, value);
    // Preview so users hear what they just turned on.
    if (value) preview?.call();
  }

  Widget _buildToggleRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
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
            activeThumbColor: AppTheme.primary,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildSubscriptionTile(AppLocalizations l10n) {
    final subscription = context.watch<SubscriptionProvider>();
    final isPremium = subscription.isPremiumActive;
    final expiresAt = subscription.premiumExpiresAt;
    final locale = Localizations.localeOf(context).toString();
    final dateFormatter = DateFormat.yMMMd(locale);

    final title = isPremium ? l10n.premium : l10n.upgradeToPremium;
    final subtitle = isPremium
        ? (expiresAt != null
              ? l10n.premiumRenewsOn.replaceAll(
                  '{date}',
                  dateFormatter.format(expiresAt),
                )
              : l10n.premiumActive)
        : l10n.premiumFreeSubtitle;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isPremium
              ? const Color(0xFFEAB308).withValues(alpha: 0.5)
              : AppTheme.surfaceLight.withValues(alpha: 0.3),
          width: isPremium ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          HapticService.lightImpact();
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const SubscriptionScreen()));
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFEAB308).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.workspace_premium,
                  color: Color(0xFFEAB308),
                ),
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
              const Icon(Icons.chevron_right, color: AppTheme.textSecondary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.all(16),
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
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
        ],
      ),
    );
  }

  void _showLogoutDialog(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(l10n.logout, style: const TextStyle(color: Colors.white)),
        content: Text(
          l10n.logoutConfirm,
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(
              l10n.cancel,
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              final authProvider = context.read<AuthProvider>();
              // Pop with the dialog's context, but navigate with the screen's:
              // after the pop the dialog context is unmounted by the time the
              // (network) logout resolves, so guarding navigation on it meant
              // the first logout never left the settings screen.
              Navigator.pop(dialogContext);
              await authProvider.logout();
              if (context.mounted) {
                AppNavigator.toLoginClearing(context);
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
            child: Text(
              l10n.cancel,
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLanguageOption(
    String name,
    String code,
    String currentCode,
    VoidCallback onTap,
  ) {
    final isSelected = code == currentCode;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primary.withValues(alpha: 0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? AppTheme.primary
                : AppTheme.surfaceLight.withValues(alpha: 0.3),
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            l10n.deleteAccount,
            style: const TextStyle(
              color: AppTheme.error,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            l10n.deleteAccountWarning,
            style: const TextStyle(color: AppTheme.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: isDeleting ? null : () => Navigator.pop(context),
              child: Text(
                l10n.cancel,
                style: const TextStyle(color: AppTheme.textSecondary),
              ),
            ),
            ElevatedButton(
              onPressed: isDeleting
                  ? null
                  : () async {
                      setState(() {
                        isDeleting = true;
                      });

                      final success = await context
                          .read<AuthProvider>()
                          .deleteAccount();

                      if (context.mounted) {
                        Navigator.pop(context);

                        if (success) {
                          AppNavigator.toLoginClearing(context);
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                context.read<AuthProvider>().errorMessage ??
                                    l10n.errorOccurred,
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
