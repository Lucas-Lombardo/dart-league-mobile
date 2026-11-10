import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../utils/app_theme.dart';
import '../../utils/haptic_service.dart';
import '../../widgets/design_system.dart';
import 'ghost_models.dart';
import 'ghost_service.dart';
import 'ghost_widgets.dart';

/// "My ghost" in the settings: let my matches be replayed as ghosts (off =
/// no ghost of mine is offered again, so no notification and no owner XP
/// either), and the grouped "your ghost played" push on its own. Hidden until
/// the server answers — a backend without /ghost shows nothing.
class GhostSettingsSection extends StatefulWidget {
  const GhostSettingsSection({super.key});

  @override
  State<GhostSettingsSection> createState() => _GhostSettingsSectionState();
}

class _GhostSettingsSectionState extends State<GhostSettingsSection> {
  GhostSettings? _settings;

  @override
  void initState() {
    super.initState();
    GhostService.settings().then((s) {
      if (mounted) setState(() => _settings = s);
    }).catchError((Object _) {});
  }

  Future<void> _update({bool? enabled, bool? notify}) async {
    final before = _settings;
    if (before == null) return;
    HapticService.selectionClick();
    setState(() => _settings = GhostSettings(
          enabled: enabled ?? before.enabled,
          notify: notify ?? before.notify,
        ));
    try {
      final saved = await GhostService.updateSettings(enabled: enabled, notify: notify);
      if (mounted) setState(() => _settings = saved);
    } catch (_) {
      if (mounted) setState(() => _settings = before);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _settings;
    if (s == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(l10n.ghostSettingsSection.toUpperCase(), style: AppTheme.labelSmall),
          ),
          const SizedBox(height: 8),
          DsCard(
            radius: AppTheme.radiusRow,
            padding: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SwitchRow(
                  icon: const GhostIcon(size: 20, color: Color(0xFFCBD5E1)),
                  title: l10n.ghostSettingsEnabled,
                  subtitle: l10n.ghostSettingsEnabledHint,
                  value: s.enabled,
                  onChanged: (v) => _update(enabled: v),
                ),
                if (s.enabled) ...[
                  const Divider(),
                  _SwitchRow(
                    icon: const Icon(Icons.notifications_none_rounded, size: 20, color: Color(0xFFCBD5E1)),
                    title: l10n.ghostSettingsNotify,
                    subtitle: l10n.ghostSettingsNotifyHint,
                    value: s.notify,
                    onChanged: (v) => _update(notify: v),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final Widget icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _SwitchRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 52),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Row(
          children: [
            icon,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Two lines rather than « Ton fantôme a j… ».
                  Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppTheme.rowTitle),
                  const SizedBox(height: 2),
                  Text(subtitle, maxLines: 2, style: AppTheme.caption),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Switch(value: value, onChanged: onChanged, materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
          ],
        ),
      ),
    );
  }
}
