import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/progression_provider.dart';
import '../../utils/app_theme.dart';
import '../../utils/rank_translation.dart';
import '../../utils/rank_utils.dart';
import '../../widgets/design_system.dart' show dsSentence;
import '../../widgets/progression/progression_widgets.dart';
import 'onboarding_models.dart';
import 'onboarding_provider.dart';

/// Day 7 (mockup ecrans/DebutBilan): the first week in numbers — matches,
/// best visit, average and its progress since day 1, rank — then what it
/// unlocks: the premium days and the "Débutant" frame. Leaving it (Continue or
/// back) marks it seen, and the home card gives way to "Today".
class OnboardingBilanScreen extends StatefulWidget {
  /// Shown as given (tests); null reads the provider.
  final OnboardingStatus? status;

  const OnboardingBilanScreen({super.key, this.status});

  static Route<void> route() => PageRouteBuilder<void>(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (_, _, _) => const OnboardingBilanScreen(),
        transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
      );

  @override
  State<OnboardingBilanScreen> createState() => _OnboardingBilanScreenState();
}

class _OnboardingBilanScreenState extends State<OnboardingBilanScreen> {
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    // The frame was just equipped server-side: "already on your card" reads
    // the summary, and the premium days change the badge on the home card.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ProgressionProvider? progression;
      try {
        progression = context.read<ProgressionProvider>();
      } on ProviderNotFoundException {
        progression = null;
      }
      unawaited(progression?.refreshSummary());
    });
  }

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    final nav = Navigator.of(context);
    unawaited(maybeReadOnboarding(context)?.markBilanSeen());
    if (nav.mounted) nav.pop();
  }

  String _fmt(double v, Locale locale) =>
      NumberFormat('0.0', locale.toLanguageTag()).format(v);

  Future<void> _share(OnboardingBilan bilan) async {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context);
    await SharePlus.instance.share(ShareParams(
      text: l10n.onboardingBilanShareText(
        bilan.matches,
        bilan.bestVisit?.toString() ?? '—',
        bilan.average != null ? _fmt(bilan.average!, locale) : '—',
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context);
    final status = widget.status ?? maybeWatchOnboarding(context)?.status ?? OnboardingStatus.none;
    final bilan = status.bilan ?? const OnboardingBilan(matches: 0);
    final frameStep = status.steps.where((s) => s.rewardItem?.type == 'frame').firstOrNull;
    final frame = frameStep?.rewardItem;
    final progression = maybeWatchProgression(context);
    final frameDef = frame == null ? null : progression?.item(frame.id);
    final equipped = frame != null && progression?.summary?.equipment.frame == frame.id;
    final until = status.premiumUntil;
    final delta = bilan.averageDelta;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 32, 20, 20),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight - 52),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        l10n.onboardingBilanSteps(status.doneCount, status.totalCount),
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.playerBlueBright),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        l10n.onboardingBilanTitle,
                        style: const TextStyle(
                          fontSize: 34,
                          height: 1.1,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.7,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 18),
                      // Two tiles side by side share one height, whichever
                      // label wraps (« moyenne · +6,4 / depuis le jour 1 »).
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(child: _StatTile(value: '${bilan.matches}', label: l10n.onboardingBilanMatches)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _StatTile(
                                value: bilan.bestVisit?.toString() ?? '—',
                                label: l10n.onboardingBilanBestVisit,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: _StatTile(
                                value: bilan.average != null ? _fmt(bilan.average!, locale) : '—',
                                label: l10n.onboardingBilanAverage,
                                delta: delta == null
                                    ? null
                                    : '${delta >= 0 ? '+' : '−'}${_fmt(delta.abs(), locale)}',
                                deltaPositive: (delta ?? 0) >= 0,
                                deltaSuffix: l10n.onboardingBilanSinceDay1,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(child: _RankTile(rank: bilan.rank)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        l10n.onboardingBilanUnlocks,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFFCBD5E1)),
                      ),
                      const SizedBox(height: 8),
                      if (status.premiumDays > 0)
                        _UnlockRow(
                          // Gold: premium, nothing else.
                          leading: const Icon(Icons.workspace_premium_outlined, size: 22, color: AppTheme.accent),
                          gold: true,
                          title: l10n.onboardingPremiumDays(status.premiumDays),
                          subtitle: until != null
                              ? l10n.onboardingBilanPremiumUntil(DateFormat.MMMMd(locale.toLanguageTag()).format(until))
                              : l10n.onboardingBilanPremiumPerks,
                        ),
                      if (frame != null) ...[
                        const SizedBox(height: 8),
                        _UnlockRow(
                          leading: frameDef != null
                              ? SizedBox(width: 40, height: 40, child: ProgressionItemVisual(item: frameDef, size: 40))
                              : Container(
                                  width: 40,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: AppTheme.background,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: AppTheme.playerBlueBright, width: 2),
                                  ),
                                ),
                          title: l10n.onboardingBilanFrame(frame.name.resolve(context)),
                          subtitle: equipped ? l10n.onboardingBilanEquipped : l10n.onboardingBilanInLocker,
                        ),
                      ],
                      const SizedBox(height: 18),
                      Text(
                        l10n.onboardingBilanNext,
                        style: const TextStyle(fontSize: 14, height: 1.5, color: Color(0xFFE2E8F0)),
                      ),
                      const Spacer(),
                      const SizedBox(height: 18),
                      SizedBox(
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _close,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryLight,
                            foregroundColor: AppTheme.background,
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusControl)),
                            textStyle: const TextStyle(fontFamily: AppTheme.fontFamily, fontSize: 16, fontWeight: FontWeight.w800),
                          ),
                          child: Text(dsSentence(l10n.continueButton)),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 48,
                        child: OutlinedButton(
                          onPressed: () => _share(bilan),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.textPrimary,
                            side: const BorderSide(color: AppTheme.surfaceLight),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusControl)),
                            textStyle: const TextStyle(fontFamily: AppTheme.fontFamily, fontSize: 15, fontWeight: FontWeight.w700),
                          ),
                          child: Text(l10n.onboardingBilanShare),
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
    );
  }
}

class _StatTile extends StatelessWidget {
  final String value;
  final String label;
  final String? delta;
  final bool deltaPositive;
  final String? deltaSuffix;

  const _StatTile({
    required this.value,
    required this.label,
    this.delta,
    this.deltaPositive = true,
    this.deltaSuffix,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 76),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: AppTheme.textPrimary,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 2),
          Text.rich(
            TextSpan(
              style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
              children: [
                TextSpan(text: label),
                if (delta != null) ...[
                  const TextSpan(text: ' · '),
                  TextSpan(
                    text: delta,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: deltaPositive ? const Color(0xFF4ADE80) : AppTheme.textSecondary,
                    ),
                  ),
                  if (deltaSuffix != null) TextSpan(text: ' $deltaSuffix'),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RankTile extends StatelessWidget {
  final String rank;
  const _RankTile({required this.rank});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 76),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          RankUtils.getRankBadge(rank, size: 44),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  rank == 'unranked' ? l10n.unranked : RankTranslation.translate(l10n, rank),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
                ),
                Text(l10n.onboardingBilanYourRank, style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UnlockRow extends StatelessWidget {
  final Widget leading;
  final String title;
  final String subtitle;
  final bool gold;

  const _UnlockRow({required this.leading, required this.title, required this.subtitle, this.gold = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: gold ? Border.all(color: AppTheme.accent.withValues(alpha: 0.55), width: 1.5) : null,
      ),
      child: Row(
        children: [
          leading,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppTheme.textPrimary)),
                const SizedBox(height: 1),
                Text(subtitle, style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
