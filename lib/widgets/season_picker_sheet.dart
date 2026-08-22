import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/season.dart';
import '../providers/season_provider.dart';
import '../utils/app_theme.dart';
import '../utils/haptic_service.dart';
import '../utils/rank_translation.dart';
import '../utils/season_format.dart';

/// Bottom sheet opened by the season pill on the home ring: one row per
/// season (active first, then the closed ones, newest first), a check on the
/// one the ring displays, and an "All seasons ›" link to the posters.
///
/// Returns the tapped season number, or [allSeasonsResult] for the link.
class SeasonPickerSheet extends StatelessWidget {
  static const int allSeasonsResult = -1;

  const SeasonPickerSheet({super.key});

  static Future<int?> show(BuildContext context) {
    return showModalBottomSheet<int>(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
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
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.textSecondary.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 14, bottom: 4),
              child: _SheetTitle(),
            ),
            for (final season in rows)
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
            InkWell(
              onTap: () {
                HapticService.lightImpact();
                Navigator.pop(context, allSeasonsResult);
              },
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                height: 48,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      l10n.seasonAllSeasons,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primary,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.chevron_right, size: 16, color: AppTheme.primary),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetTitle extends StatelessWidget {
  const _SheetTitle();

  @override
  Widget build(BuildContext context) {
    return Text(
      AppLocalizations.of(context).seasonsTitle,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: Colors.white,
      ),
    );
  }
}

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
          ? '· ${l10n.seasonInProgress} · ${formatSeasonCountdown(l10n, timeLeft ?? season.timeLeft())}'
          : '· ${l10n.seasonInProgress} · ${l10n.seasonEndToBeAnnounced}';
      detail = me != null
          ? '${l10n.seasonYouAre(me.position)} · ${me.elo} · ${RankTranslation.translate(l10n, me.rank)}'
          : l10n.seasonNotRanked;
    } else {
      status = '· ${l10n.seasonEnded}';
      detail = me != null
          ? '${l10n.seasonFinalRankLine(RankTranslation.translate(l10n, me.rank), me.position, season.playersCount ?? 0)} · ${me.elo}'
          : l10n.seasonNotRanked;
    }

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: AppTheme.surfaceLight.withValues(alpha: 0.5)),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isActive
                    ? AppTheme.primary.withValues(alpha: 0.15)
                    : AppTheme.surfaceLight.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                l10n.seasonShort(season.number),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: isActive ? const Color(0xFF38BDF8) : AppTheme.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(
                      text: '${l10n.seasonN(season.number)} ',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                      children: [
                        TextSpan(
                          text: status,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: isActive
                                ? const Color(0xFF38BDF8)
                                : AppTheme.textSecondary,
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
                    style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              isSelected ? Icons.check : Icons.chevron_right,
              size: 18,
              color: isSelected ? AppTheme.primary : AppTheme.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}
