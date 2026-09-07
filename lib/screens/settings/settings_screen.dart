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
import '../../services/api_service.dart';
import '../../services/dataset_capture_service.dart';
import '../../utils/app_theme.dart';
import '../profile/replay_library_screen.dart';
import '../../utils/dart_caller_service.dart';
import '../../utils/dart_sound_service.dart';
import '../../utils/rank_translation.dart';
import '../../widgets/design_system.dart';
import '../../widgets/premium_badge.dart';
import 'edit_profile_screen.dart';
import 'subscription_screen.dart';
import '../../providers/referral_provider.dart';
import 'referral_screen.dart';
import 'redeem_referral_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Clip count for the replays row subtitle — best-effort, row works
  // without it.
  int? _replayCount;

  String _appVersion = '…';
  bool _callerEnabled = DartCallerService.enabled;
  bool _hapticsEnabled = HapticService.isEnabled;
  bool _datasetShareEnabled = DatasetCaptureService.shareEnabled;
  final Map<SoundCategory, bool> _soundEnabled = {
    for (final c in SoundCategory.values) c: DartSoundService.isEnabled(c),
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<ReferralProvider>().loadOverview();
    });
    ApiService.get('/replays/mine?limit=1').then((data) {
      if (!mounted) return;
      setState(() => _replayCount = (data['total'] as num?)?.toInt());
    }).catchError((Object e) {
      debugPrint('[Settings] replay count failed: $e');
    });
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
    final languageCode = context.watch<LocaleProvider>().locale.languageCode;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settings)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildProfileCard(l10n, user),

          // Replays live in the PROFILE (Lucas, 2026-08-03): personal
          // content, right above Premium so the quota reads as a natural
          // bridge to the row below it.
          const SizedBox(height: 16),
          _SettingsGroup(
            rows: [
              _buildReplaysRow(l10n, user),
              _buildSubscriptionRow(l10n),
              ..._buildReferralRows(l10n),
            ],
          ),

          const SizedBox(height: 16),
          _SettingsGroup(
            label: l10n.preferences,
            rows: [
              _SettingsRow(
                icon: Icons.language_rounded,
                title: l10n.language,
                value: languageCode == 'fr' ? 'Français' : 'English',
                onTap: () => _showLanguageDialog(context),
              ),
              _SettingsRow(
                icon: Icons.center_focus_weak_rounded,
                title: l10n.datasetShareTitle,
                subtitle: l10n.datasetShareDescription,
                toggle: _datasetShareEnabled,
                onToggle: (value) {
                  HapticService.selectionClick();
                  setState(() => _datasetShareEnabled = value);
                  DatasetCaptureService.setShareEnabled(value);
                },
              ),
            ],
          ),

          const SizedBox(height: 16),
          _SettingsGroup(
            label: l10n.soundsSection,
            rows: [
              _SettingsRow(
                icon: Icons.volume_up_outlined,
                title: l10n.voiceCaller,
                subtitle: l10n.voiceCallerDescription,
                toggle: _callerEnabled,
                onToggle: (value) {
                  HapticService.selectionClick();
                  setState(() => _callerEnabled = value);
                  DartCallerService.setEnabled(value);
                  // Preview so users hear what they just turned on.
                  if (value) DartCallerService.callScore(180);
                },
              ),
              _SettingsRow(
                icon: Icons.adjust_rounded,
                title: l10n.soundDartHit,
                subtitle: l10n.soundDartHitDescription,
                toggle: _soundEnabled[SoundCategory.dartHit]!,
                onToggle: (value) => _setSoundCategory(
                  SoundCategory.dartHit,
                  value,
                  preview: () =>
                      DartSoundService.playDartHit(20, ScoreMultiplier.triple),
                ),
              ),
              _SettingsRow(
                icon: Icons.notifications_none_rounded,
                title: l10n.soundTurn,
                subtitle: l10n.soundTurnDescription,
                toggle: _soundEnabled[SoundCategory.turn]!,
                onToggle: (value) => _setSoundCategory(
                  SoundCategory.turn,
                  value,
                  preview: DartSoundService.playYourTurn,
                ),
              ),
              _SettingsRow(
                icon: Icons.bolt_rounded,
                title: l10n.soundGameEffects,
                subtitle: l10n.soundGameEffectsDescription,
                toggle: _soundEnabled[SoundCategory.gameEffects]!,
                onToggle: (value) => _setSoundCategory(
                  SoundCategory.gameEffects,
                  value,
                  preview: DartSoundService.playBust,
                ),
              ),
              _SettingsRow(
                icon: Icons.search_rounded,
                title: l10n.soundMatchFound,
                subtitle: l10n.soundMatchFoundDescription,
                toggle: _soundEnabled[SoundCategory.matchFound]!,
                onToggle: (value) => _setSoundCategory(
                  SoundCategory.matchFound,
                  value,
                  preview: DartSoundService.playMatchFound,
                ),
              ),
              _SettingsRow(
                icon: Icons.vibration_rounded,
                title: l10n.haptics,
                subtitle: l10n.hapticsDescription,
                toggle: _hapticsEnabled,
                onToggle: (value) {
                  setState(() => _hapticsEnabled = value);
                  HapticService.setEnabled(value);
                  if (value) HapticService.mediumImpact();
                },
              ),
            ],
          ),

          const SizedBox(height: 16),
          _SettingsGroup(
            label: l10n.about,
            rows: [
              _SettingsRow(
                icon: Icons.info_outline_rounded,
                title: l10n.appVersion,
                value: _appVersion,
              ),
              _SettingsRow(
                icon: Icons.code_rounded,
                title: l10n.developer,
                value: 'Lucas Lombardo',
              ),
            ],
          ),

          const SizedBox(height: 16),
          _SettingsGroup(
            label: l10n.accountSection,
            side: BorderSide(color: AppTheme.error.withValues(alpha: 0.45)),
            rows: [
              _SettingsRow(
                icon: Icons.logout_rounded,
                title: l10n.logout,
                danger: true,
                chevron: false,
                onTap: () => _showLogoutDialog(context),
              ),
              _SettingsRow(
                icon: Icons.delete_outline_rounded,
                title: l10n.deleteAccount,
                danger: true,
                chevron: false,
                onTap: () => _showDeleteAccountDialog(context),
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  /// Initial disc, name (+ crown when premium), "ELO · rank" and the Modifier
  /// pill. No gold ring, no gradient: the crown is the only premium marker.
  Widget _buildProfileCard(AppLocalizations l10n, User? user) {
    final isPremium = context.watch<SubscriptionProvider>().isPremiumActive;
    final username = user?.username ?? l10n.accountInfoDefaultUsername;
    final initial = username.isNotEmpty ? username[0].toUpperCase() : '?';
    final rankLabel = user == null
        ? l10n.unranked
        : RankTranslation.translate(l10n, user.rank);

    return DsCard(
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.surfaceLight,
            ),
            child: Text(
              initial,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
                height: 1,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        username,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.titleLarge,
                      ),
                    ),
                    PremiumBadge(
                      isPremium: isPremium,
                      size: 14,
                      color: AppTheme.accent,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${user?.elo ?? 0} ${l10n.eloLabel} · $rankLabel',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.caption.copyWith(fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _OutlinePill(
            label: l10n.settingsEditShort,
            onTap: user == null
                ? null
                : () =>
                    AppNavigator.toScreen(context, const EditProfileScreen()),
          ),
        ],
      ),
    );
  }

  Widget _buildReplaysRow(AppLocalizations l10n, User? user) {
    final premium = user?.isPremiumActive == true;
    final count = _replayCount;
    final subtitle = count == null
        ? l10n.myReplaysSubtitle
        : premium
            ? l10n.replayClipsCount(count)
            : '${l10n.replayClipsCount(count)} · '
                '${l10n.replayFreeLeft((5 - count).clamp(0, 5))}';
    return _SettingsRow(
      icon: Icons.movie_outlined,
      title: l10n.myReplays,
      subtitle: subtitle,
      onTap: () =>
          AppNavigator.toScreen(context, const ReplayLibraryScreen()),
    );
  }

  /// The one gold icon of the screen.
  Widget _buildSubscriptionRow(AppLocalizations l10n) {
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

    return _SettingsRow(
      icon: Icons.workspace_premium_rounded,
      iconColor: AppTheme.accent,
      title: title,
      subtitle: subtitle,
      onTap: () {
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const SubscriptionScreen()));
      },
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

  /// Both sides of the referral program. The "I have a code" row only exists
  /// while the account is still eligible — a dead row would need explaining.
  List<Widget> _buildReferralRows(AppLocalizations l10n) {
    final referral = context.watch<ReferralProvider>();
    final overview = referral.overview;
    final hasCode = overview?.code != null;

    final rows = <Widget>[
      _SettingsRow(
        icon: Icons.card_giftcard_outlined,
        title: hasCode ? l10n.referralMyCodeTitle : l10n.referralCreateCodeTitle,
        subtitle: overview?.code ?? l10n.referralCreateCodeSubtitle,
        onTap: () {
          AppNavigator.toScreen(context, const ReferralScreen()).then((_) {
            if (mounted) context.read<ReferralProvider>().loadOverview();
          });
        },
      ),
    ];

    if (referral.canRedeem) {
      rows.add(
        _SettingsRow(
          icon: Icons.redeem_outlined,
          title: l10n.referralHaveCodeTitle,
          subtitle: l10n.referralHaveCodeSubtitle(
            overview?.refereeTrialDays ?? 7,
          ),
          onTap: () {
            AppNavigator.toScreen(context, const RedeemReferralScreen()).then((
              _,
            ) {
              if (!mounted) return;
              context.read<ReferralProvider>().loadOverview();
              context.read<SubscriptionProvider>().refresh();
            });
          },
        ),
      );
    } else if (overview?.referredByUsername != null) {
      rows.add(
        _SettingsRow(
          icon: Icons.redeem_outlined,
          title: l10n.referralRedeemTitle,
          subtitle: l10n.referralReferredBy(overview!.referredByUsername!),
        ),
      );
    }

    return rows;
  }

  void _showLogoutDialog(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.logout),
        content: Text(l10n.logoutConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            style: TextButton.styleFrom(foregroundColor: AppTheme.textSecondary),
            child: Text(l10n.cancel),
          ),
          ElevatedButton(
            onPressed: () async {
              final authProvider = context.read<AuthProvider>();
              // Referral state is per-account: drop it so the next sign-in
              // does not inherit this user's code and eligibility.
              final referralProvider = context.read<ReferralProvider>();
              // Pop with the dialog's context, but navigate with the screen's:
              // after the pop the dialog context is unmounted by the time the
              // (network) logout resolves, so guarding navigation on it meant
              // the first logout never left the settings screen.
              Navigator.pop(dialogContext);
              await authProvider.logout();
              referralProvider.reset();
              if (context.mounted) {
                AppNavigator.toLoginClearing(context);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.error,
              foregroundColor: Colors.white,
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
        title: Text(l10n.changeLanguage),
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
            style: TextButton.styleFrom(foregroundColor: AppTheme.textSecondary),
            child: Text(l10n.cancel),
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
    return Material(
      color: isSelected
          ? AppTheme.primary.withValues(alpha: 0.08)
          : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        side: BorderSide(
          color: isSelected ? AppTheme.primary : AppTheme.border,
          width: isSelected ? 1.5 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  style: AppTheme.rowTitle.copyWith(
                    color: isSelected
                        ? AppTheme.primaryLight
                        : AppTheme.textPrimary,
                  ),
                ),
              ),
              if (isSelected)
                const Icon(Icons.check_circle_rounded,
                    size: 20, color: AppTheme.primaryLight),
            ],
          ),
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
          title: Text(
            l10n.deleteAccount,
            style: AppTheme.titleLarge.copyWith(color: AppTheme.error),
          ),
          content: Text(l10n.deleteAccountWarning),
          actions: [
            TextButton(
              onPressed: isDeleting ? null : () => Navigator.pop(context),
              style:
                  TextButton.styleFrom(foregroundColor: AppTheme.textSecondary),
              child: Text(l10n.cancel),
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

/// A settings group: optional 11 / 700 label, then ONE 16 px card whose rows
/// are separated by hairlines.
class _SettingsGroup extends StatelessWidget {
  final String? label;
  final List<Widget> rows;
  final BorderSide? side;

  const _SettingsGroup({this.label, required this.rows, this.side});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (label != null) ...[
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(label!.toUpperCase(), style: AppTheme.labelSmall),
          ),
          const SizedBox(height: 8),
        ],
        DsCard(
          radius: AppTheme.radiusRow,
          padding: EdgeInsets.zero,
          side: side,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) const Divider(),
                rows[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// 52 px row: 20 px outlined icon, 15 / 600 title, optional caption, and on
/// the right a chevron, a value, or a switch. Destructive rows draw icon and
/// title in [AppTheme.error] and never show a chevron.
class _SettingsRow extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String title;
  final String? subtitle;
  final String? value;
  final bool? toggle;
  final ValueChanged<bool>? onToggle;
  final VoidCallback? onTap;
  final bool danger;
  final bool chevron;

  const _SettingsRow({
    required this.icon,
    required this.title,
    this.iconColor,
    this.subtitle,
    this.value,
    this.toggle,
    this.onToggle,
    this.onTap,
    this.danger = false,
    this.chevron = true,
  });

  @override
  Widget build(BuildContext context) {
    final titleColor = danger ? AppTheme.error : AppTheme.textPrimary;
    final Widget trailing;
    if (toggle != null) {
      trailing = Switch(
        value: toggle!,
        onChanged: onToggle,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      );
    } else if (value != null) {
      trailing = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value!,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
            ),
          ),
          if (onTap != null && chevron) ...[
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded,
                size: 18, color: AppTheme.textTertiary),
          ],
        ],
      );
    } else if (onTap != null && chevron) {
      trailing = const Icon(Icons.chevron_right_rounded,
          size: 20, color: AppTheme.textTertiary);
    } else {
      trailing = const SizedBox.shrink();
    }

    final content = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 52),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: iconColor ??
                  (danger ? AppTheme.error : const Color(0xFFCBD5E1)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.rowTitle.copyWith(color: titleColor),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.caption,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            trailing,
          ],
        ),
      ),
    );

    if (onTap == null) return content;
    return InkWell(
      onTap: () {
        HapticService.lightImpact();
        onTap!();
      },
      child: content,
    );
  }
}

/// Small outline pill ("Modifier"): 34 px, stadium, surfaceLight border.
class _OutlinePill extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  const _OutlinePill({required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const StadiumBorder(side: BorderSide(color: AppTheme.surfaceLight)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap == null
            ? null
            : () {
                HapticService.lightImpact();
                onTap!();
              },
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
