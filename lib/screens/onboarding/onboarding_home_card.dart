import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../main.dart' show routeObserver;
import '../../models/progression.dart' show LocalizedText, itemTypeFrom;
import '../../utils/app_theme.dart';
import '../progression/progression_format.dart' show itemKindLabel;
import 'onboarding_actions.dart';
import 'onboarding_journey_screen.dart';
import 'onboarding_models.dart';
import 'onboarding_provider.dart';

/// "Tes 7 premiers jours" on the home (mockup ecrans/DebutAccueil): progress
/// "2 / 7" over seven segments, today's step with its reward and "Play", and
/// the premium waiting at the end. Takes the place of the "Today" block while
/// the journey runs; renders nothing otherwise. Refreshes itself when the
/// home comes back into view (a match may have reached a step).
class OnboardingHomeCard extends StatefulWidget {
  /// Space above the card when it shows (nothing when it does not).
  final double topSpacing;

  const OnboardingHomeCard({super.key, this.topSpacing = 14});

  @override
  State<OnboardingHomeCard> createState() => _OnboardingHomeCardState();
}

class _OnboardingHomeCardState extends State<OnboardingHomeCard> with RouteAware {
  ModalRoute<void>? _route;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) maybeReadOnboarding(context)?.refresh();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null && route != _route) {
      if (_route != null) routeObserver.unsubscribe(this);
      _route = route;
      routeObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    if (_route != null) routeObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPopNext() {
    final p = maybeReadOnboarding(context);
    // Nothing left to follow this session (old account, journey over).
    if (p == null || (p.status != null && !p.isActive)) return;
    p.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final status = maybeWatchOnboarding(context)?.status;
    if (status == null || !status.active) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(top: widget.topSpacing),
      child: OnboardingCard(status: status),
    );
  }
}

/// The card itself, stateless (tests pump it with a status).
class OnboardingCard extends StatelessWidget {
  final OnboardingStatus status;
  const OnboardingCard({super.key, required this.status});

  static const _segmentOn = Color(0xFF38BDF8);
  static const _segmentOff = Color(0xFF334155);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final total = status.totalCount > 0 ? status.totalCount : status.steps.length;
    return Material(
      color: AppTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        side: const BorderSide(color: AppTheme.primaryLight, width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(OnboardingJourneyScreen.route()),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Expanded(
                    child: Text(
                      l10n.onboardingTitle,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
                    ),
                  ),
                  Text(
                    '${status.doneCount} / $total',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  for (var i = 0; i < total; i++) ...[
                    if (i > 0) const SizedBox(width: 4),
                    Expanded(
                      child: Container(
                        height: 6,
                        decoration: BoxDecoration(
                          color: i < status.doneCount ? _segmentOn : _segmentOff,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              _StepLine(status: status),
              if (status.premiumDays > 0 && !status.isCompleted) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.only(top: 10),
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: AppTheme.border)),
                  ),
                  child: Row(
                    children: [
                      // Gold: the premium, nothing else.
                      const Icon(Icons.card_giftcard_rounded, size: 16, color: AppTheme.accent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          l10n.onboardingPremiumAtTheEnd(status.premiumDays),
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFFCBD5E1)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// "Aujourd'hui · jour 2 / Une volée à 60 ou plus / +80 XP" and its button;
/// tomorrow's step (locked) when today's are done; the summary when ready.
class _StepLine extends StatelessWidget {
  final OnboardingStatus status;
  const _StepLine({required this.status});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    String label;
    String title;
    String? reward;
    Widget? trailing;
    OnboardingStep? actionStep;

    final current = status.currentStep;
    if (status.bilanPending) {
      label = l10n.onboardingDayN(status.journeyDays);
      title = l10n.onboardingBilanReadyTitle;
      trailing = _PlayButton(label: l10n.onboardingSee, step: _bilanStep(status));
    } else if (current != null) {
      label = l10n.onboardingTodayDay(status.day);
      title = current.title.resolve(context);
      reward = onboardingRewardLine(context, current);
      actionStep = current;
      if (onboardingActionSupported(current.action)) {
        trailing = _PlayButton(label: l10n.play, step: current);
      }
    } else {
      final next = status.nextLockedStep;
      if (next == null) return const SizedBox.shrink();
      label = next.day == status.day + 1 ? l10n.onboardingTomorrowDay(next.day) : l10n.onboardingDayN(next.day);
      title = next.title.resolve(context);
      reward = onboardingRewardLine(context, next);
      trailing = const Icon(Icons.lock_outline_rounded, size: 18, color: AppTheme.textTertiary);
    }

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.textSecondary)),
              const SizedBox(height: 2),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: actionStep == null && !status.bilanPending ? AppTheme.textSecondary : AppTheme.textPrimary,
                ),
              ),
              if (reward != null && reward.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(reward, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.playerBlueBright)),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 12), trailing],
      ],
    );
  }

  static OnboardingStep _bilanStep(OnboardingStatus s) =>
      s.steps.where((x) => x.action == 'bilan').firstOrNull ??
      const OnboardingStep(id: 'bilan', day: 7, title: LocalizedText.empty, status: OnboardingStepStatus.done, action: 'bilan');
}

class _PlayButton extends StatelessWidget {
  final String label;
  final OnboardingStep step;
  const _PlayButton({required this.label, required this.step});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ElevatedButton(
        onPressed: () => runOnboardingAction(context, step),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primaryLight,
          foregroundColor: AppTheme.background,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusControl)),
          textStyle: const TextStyle(fontFamily: AppTheme.fontFamily, fontSize: 15, fontWeight: FontWeight.w800),
        ),
        child: Text(label),
      ),
    );
  }
}

/// "+150 XP · titre « Nouvelle recrue »", "+150 XP · 7 jours de premium ·
/// cadre de carte « Débutant »".
String onboardingRewardLine(BuildContext context, OnboardingStep step) {
  final l10n = AppLocalizations.of(context);
  final parts = <String>[
    if (step.xp > 0) l10n.onboardingXp(step.xp),
    if (step.premiumDays > 0) l10n.onboardingPremiumDays(step.premiumDays),
  ];
  final item = step.rewardItem;
  if (item != null) {
    final kind = itemKindLabel(l10n, itemTypeFrom(item.type));
    parts.add(l10n.onboardingRewardItem(kind, item.name.resolve(context)));
  }
  return parts.join(' · ');
}
