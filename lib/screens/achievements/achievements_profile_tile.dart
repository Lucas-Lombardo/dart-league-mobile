import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../utils/app_theme.dart';
import '../../widgets/design_system.dart';
import 'achievement_models.dart';
import 'achievements_screen.dart';
import 'achievements_service.dart';

/// The "Achievements 18 / 60" tile of my profile (mockup ecrans/Profil),
/// opening the collection.
class AchievementsProfileTile extends StatefulWidget {
  /// Test seam: the network call.
  final Future<AchievementsSummary> Function()? load;
  const AchievementsProfileTile({super.key, this.load});

  @override
  State<AchievementsProfileTile> createState() => _AchievementsProfileTileState();
}

class _AchievementsProfileTileState extends State<AchievementsProfileTile> {
  late Future<AchievementsSummary> _future = _fetch();

  Future<AchievementsSummary> _fetch() => (widget.load ?? AchievementsService.summary)();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return FutureBuilder<AchievementsSummary>(
      future: _future,
      builder: (context, snap) {
        final s = snap.data;
        return DsCard(
          onTap: () async {
            await Navigator.of(context).push(AchievementsScreen.route());
            if (mounted) setState(() => _future = _fetch());
          },
          child: Row(
            children: [
              Expanded(
                child: Text(l10n.achievementsTitle, style: AppTheme.rowTitle.copyWith(fontWeight: FontWeight.w800)),
              ),
              if (s != null && s.total > 0)
                Text(
                  '${s.unlocked} / ${s.total}',
                  style: AppTheme.rowTitle.copyWith(color: AppTheme.textSecondary, fontWeight: FontWeight.w700),
                ),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right_rounded, color: AppTheme.textSecondary, size: 20),
            ],
          ),
        );
      },
    );
  }
}
