import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/season.dart';
import '../providers/season_provider.dart';
import '../utils/app_theme.dart';
import '../utils/haptic_service.dart';
import '../utils/rank_translation.dart';
import '../utils/season_format.dart';

/// Bottom sheet opened by the season pill on the home card: a 17 / 700
/// title, one 52 px row per season (active first, then the closed ones,
/// newest first) with a check on the one the card displays, and
/// "Toutes les saisons ›" as the last row.
///
/// Returns the tapped season number, or [allSeasonsResult] for the link.
class SeasonPickerSheet extends StatelessWidget {
  static const int allSeasonsResult = -1;

  const SeasonPickerSheet({super.key});

  static Future<int?> show(BuildContext context) {
    // Surface + 24 px top corners come from the theme's bottomSheetTheme.
    return showModalBottomSheet<int>(
      context: context,
      builder: (_) => const SeasonPickerSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final provider = context.watch<SeasonProvider>();
    final active = provider.activeSeason;
    final selected = provider.selectedNumber;
    final rows = <Season>[
      ?active,
      ...provider.seasons.where((s) => s.isClosed).toList()
        ..sort((a, b) => b.number.compareTo(a.number)),
    ];

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.surfaceLight,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
              child: Text(l10n.seasonsTitle, style: AppTheme.titleLarge),
            ),
            for (final season in rows) ...[
              _SeasonRow(
                season: season,
                isActive: season.number == active?.number,
                isSelected: season.number == selected,
                standing: season.number == active?.number
                    ? provider.current?.me
                    : season.myStanding,
                timeLeft: season.number == active?.number ? provider.timeLeft : null,
                onTap: () {
                  HapticService.lightImpact();
                  Navigator.pop(context, season.number);
                },
              ),
              const Divider(),
            ],
            _AllSeasonsRow(
              onTap: () {
                HapticService.lightImpact();
                Navigator.pop(context, allSeasonsResult);
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// 52 px: "Saison 1  En cours · 84 j" over "Vous êtes #14 · 1486 · Or",
/// a check on the selected one.
class _SeasonRow extends StatelessWidget {
  final Season season;
  final bool isActive;
  final bool isSelected;
  final SeasonStanding? standing;
  final Duration? timeLeft;
  final VoidCallback onTap;

  const _SeasonRow({
    required this.season,
    required this.isActive,
    required this.isSelected,
    required this.standing,
    required this.timeLeft,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final me = standing;
    final String status;
    final String detail;
    if (isActive) {
      status = season.endAt != null
          ? '${l10n.seasonInProgress} · ${formatSeasonCountdown(l10n, timeLeft ?? season.timeLeft())}'
          : '${l10n.seasonInProgress} · ${l10n.seasonEndToBeAnnounced}';
      detail = me != null
          ? '${l10n.seasonYouAre(me.position)} · ${me.elo} · ${RankTranslation.translate(l10n, me.rank)}'
          : l10n.seasonNotRanked;
    } else {
      status = l10n.seasonEnded;
      detail = me != null
          ? '${l10n.seasonFinalRankLine(RankTranslation.translate(l10n, me.rank), me.position, season.playersCount ?? 0)} · ${me.elo}'
          : l10n.seasonNotRanked;
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: 52,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(
                        text: l10n.seasonN(season.number),
                        style: AppTheme.rowTitle,
                        children: [
                          TextSpan(
                            text: '  $status',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isActive ? AppTheme.primaryLight : AppTheme.textTertiary,
                            ),
                          ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.caption,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 24,
                child: isSelected
                    ? const Icon(Icons.check_rounded, size: 20, color: AppTheme.primaryLight)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The last row: "Toutes les saisons ›".
class _AllSeasonsRow extends StatelessWidget {
  final VoidCallback onTap;

  const _AllSeasonsRow({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: 52,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(AppLocalizations.of(context).seasonAllSeasons, style: AppTheme.rowTitle),
              ),
              const Icon(Icons.chevron_right_rounded, size: 20, color: AppTheme.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}
