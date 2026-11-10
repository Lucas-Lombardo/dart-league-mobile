import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/progression.dart';
import '../../providers/progression_provider.dart';
import '../../utils/app_theme.dart';
import '../../widgets/progression/progression_widgets.dart';
import '../progression/progression_format.dart';
import 'league_models.dart';
import 'league_screen.dart';
import 'league_store.dart';
import 'league_widgets.dart';

/// "Monday" (mockup ecrans/LigueLundi.dc.html): last week's result, shown
/// once at the first app opening after Sunday's close. Shown before the
/// "Level up" screen when both are pending (the league XP often causes it):
/// same fade route, same dark background, one primary button.
class LeagueResultScreen extends StatelessWidget {
  final LeagueResult result;
  const LeagueResultScreen({super.key, required this.result});

  static bool _checking = false;

  static Route<bool> route(LeagueResult result) => PageRouteBuilder<bool>(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (_, _, _) => LeagueResultScreen(result: result),
        transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
      );

  /// Refreshes the league and shows last week's result if one is waiting.
  /// True when the screen was pushed — its pop brings the caller's
  /// `didPopNext` back, which then shows the next pending screen.
  static Future<bool> showIfPending(BuildContext context) async {
    if (_checking) return false;
    _checking = true;
    try {
      final store = LeagueStore.instance;
      await store.refresh();
      if (store.visible?.hasResult != true || !context.mounted) return false;
      final LeagueResult? result;
      try {
        result = await LeagueApi.getResult();
      } catch (e) {
        debugPrint('LeagueResultScreen.showIfPending: $e');
        return false;
      }
      if (result == null || store.isResultHandled(result.weekKey) || !context.mounted) return false;
      final navigator = Navigator.of(context);
      final seeLeague = navigator.push(route(result));
      unawaited(seeLeague.then((open) {
        if (open == true && navigator.mounted) {
          navigator.push(MaterialPageRoute(builder: (_) => const LeagueScreen()));
        }
      }));
      return true;
    } finally {
      _checking = false;
    }
  }

  void _close(BuildContext context, {bool openLeague = false}) {
    unawaited(LeagueApi.markResultSeen(result.weekKey).catchError((Object e) {
      debugPrint('LeagueResultScreen.markResultSeen: $e');
    }));
    LeagueStore.instance.markResultHandled(result.weekKey);
    Navigator.of(context).pop(openLeague);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final after = result.leagueAfter ?? result.league;
    final afterName = after?.name.resolve(context) ?? '';
    final headline = switch (result.outcome) {
      LeagueOutcome.promoted => l10n.leagueResultUp,
      LeagueOutcome.relegated => l10n.leagueResultDown,
      LeagueOutcome.stayed => l10n.leagueResultStay,
    };
    final progression = maybeWatchProgression(context);
    final items = result.itemIds.map((id) => progression?.item(id)).whereType<ItemDef>().toList();
    final monogram = progression?.summary?.cosmetics.monogram ?? '';
    final sentence = <String>[
      if (result.outcome == LeagueOutcome.promoted && result.promotedWith.isNotEmpty)
        result.promotedWith.length == 1
            ? l10n.leaguePromotedWithOne(result.promotedWith.first)
            : l10n.leaguePromotedWithMany(result.promotedWith.join(', ')),
      if (result.nextGroupSize != null && result.nextGroupSize! > 0)
        l10n.leagueNewWeek(result.nextGroupSize!, leagueEndsLabel(l10n, result.nextEndsAt, long: true)),
    ].join(' ');
    final hasNext = result.nextGroupSize != null;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close(context);
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0B1222),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 40, 20, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          l10n.leagueWeekFinished(result.weekNumber),
                          textAlign: TextAlign.center,
                          style: AppTheme.labelLarge.copyWith(fontWeight: FontWeight.w700, color: kLeagueMuted),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          headline,
                          textAlign: TextAlign.center,
                          style: AppTheme.displayLarge.copyWith(fontSize: 44, fontWeight: FontWeight.w800, height: 1.05),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          l10n.leagueName(afterName),
                          textAlign: TextAlign.center,
                          style: AppTheme.titleLarge.copyWith(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: after?.color ?? AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 28),
                        LeagueLadder(ladder: result.ladder, currentId: after?.id, currentColor: after?.color),
                        const SizedBox(height: 28),
                        Row(
                          children: [
                            Expanded(child: _Stat(value: l10n.leaguePlace(result.position), label: l10n.leagueOutOf(result.groupSize))),
                            const SizedBox(width: 8),
                            Expanded(child: _Stat(value: formatXp(result.points), label: l10n.leaguePointsLabel)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _Stat(
                                value: '+${formatXp(result.xp)}',
                                label: l10n.leagueXpLabel,
                                color: kLeagueAccentSoft,
                              ),
                            ),
                          ],
                        ),
                        for (final item in items) ...[
                          const SizedBox(height: 12),
                          _RewardRow(
                            leading: ProgressionItemVisual(item: item, monogramText: monogram, size: 40),
                            title: l10n.leagueRewardItem(_capitalized(itemKindLabel(l10n, item.type)), item.name.resolve(context)),
                            subtitle: item.source.label.resolve(context),
                          ),
                        ],
                        if (result.badge != null) ...[
                          const SizedBox(height: 12),
                          _RewardRow(
                            leading: BadgeMedal(badge: result.badge!, size: 40),
                            title: l10n.leaguePodiumBadge,
                            subtitle: l10n.leaguePodiumBadgeSub(l10n.leaguePlace(result.position)),
                          ),
                        ],
                        if (sentence.isNotEmpty) ...[
                          const SizedBox(height: 18),
                          Text(
                            sentence,
                            style: AppTheme.bodyMedium.copyWith(height: 1.5, color: const Color(0xFFE2E8F0)),
                          ),
                        ],
                        const Spacer(),
                        const SizedBox(height: 20),
                        SizedBox(
                          height: 52,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryLight,
                              foregroundColor: AppTheme.background,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusControl)),
                              textStyle: const TextStyle(fontFamily: AppTheme.fontFamily, fontSize: 16, fontWeight: FontWeight.w800),
                            ),
                            onPressed: () => _close(context, openLeague: hasNext),
                            child: Text(hasNext ? l10n.leagueSeeNewLeague : l10n.leagueContinue),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _capitalized(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}

class _Stat extends StatelessWidget {
  final String value;
  final String label;
  final Color? color;
  const _Stat({required this.value, required this.label, this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.titleLarge.copyWith(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: color ?? AppTheme.textPrimary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 2),
            Text(label, style: AppTheme.caption),
          ],
        ),
      );
}

class _RewardRow extends StatelessWidget {
  final Widget leading;
  final String title;
  final String subtitle;
  const _RewardRow({required this.leading, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(16)),
        child: Row(
          children: [
            SizedBox(width: 40, height: 40, child: Center(child: leading)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTheme.rowTitle.copyWith(fontWeight: FontWeight.w800)),
                  if (subtitle.isNotEmpty) Text(subtitle, style: AppTheme.caption.copyWith(fontSize: 13)),
                ],
              ),
            ),
          ],
        ),
      );
}
