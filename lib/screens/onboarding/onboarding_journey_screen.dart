import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../utils/app_theme.dart';
import '../../widgets/design_system.dart';
import 'onboarding_actions.dart';
import 'onboarding_home_card.dart' show onboardingRewardLine;
import 'onboarding_models.dart';
import 'onboarding_provider.dart';

/// Every step of the first 7 days on a timeline (mockup ecrans/DebutParcours):
/// done (filled dot, check), open (ringed dot, "Play now"), locked (lock,
/// greyed title, "opens tomorrow").
class OnboardingJourneyScreen extends StatefulWidget {
  const OnboardingJourneyScreen({super.key});

  static Route<void> route() =>
      MaterialPageRoute(builder: (_) => const OnboardingJourneyScreen());

  @override
  State<OnboardingJourneyScreen> createState() => _OnboardingJourneyScreenState();
}

class _OnboardingJourneyScreenState extends State<OnboardingJourneyScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) maybeReadOnboarding(context)?.refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = maybeWatchOnboarding(context)?.status ?? OnboardingStatus.none;
    final steps = status.steps;
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  DsIconButton(
                    icon: Icons.chevron_left_rounded,
                    tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      l10n.onboardingTitle,
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.2, color: AppTheme.textPrimary),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: steps.isEmpty
                  ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                      itemCount: steps.length,
                      itemBuilder: (context, i) => OnboardingStepTile(
                        step: steps[i],
                        today: status.day,
                        isLast: i == steps.length - 1,
                        bilanReady: status.bilan != null,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One step of the timeline: the dot and its line, the day, the title, the
/// reward, and "Play now" while it is open.
class OnboardingStepTile extends StatelessWidget {
  final OnboardingStep step;
  final int today;
  final bool isLast;
  final bool bilanReady;

  const OnboardingStepTile({
    super.key,
    required this.step,
    required this.today,
    required this.isLast,
    this.bilanReady = false,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final String dayLabel;
    if (step.isOpen && step.day <= today) {
      dayLabel = l10n.onboardingDayToday(step.day);
    } else if (step.isLocked && step.day == today + 1) {
      dayLabel = l10n.onboardingDayOpensTomorrow(step.day);
    } else {
      dayLabel = l10n.onboardingDayN(step.day);
    }
    final showPlay = step.isOpen && onboardingActionSupported(step.action);
    final showBilan = step.isDone && step.action == 'bilan' && bilanReady;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 28,
            child: Column(
              children: [
                _Dot(status: step.status),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      constraints: const BoxConstraints(minHeight: 14),
                      color: step.isDone ? AppTheme.primaryLight : AppTheme.surfaceLight,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 3, 0, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(dayLabel, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.textSecondary)),
                  const SizedBox(height: 2),
                  Text(
                    step.title.resolve(context),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: step.isLocked ? AppTheme.textSecondary : AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    onboardingRewardLine(context, step),
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.playerBlueBright),
                  ),
                  if (step.isOpen && step.threshold > 1) ...[
                    const SizedBox(height: 4),
                    Text('${step.progress} / ${step.threshold}', style: AppTheme.caption.copyWith(fontSize: 12)),
                  ],
                  if (showPlay || showBilan) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 44,
                      child: ElevatedButton(
                        onPressed: () => runOnboardingAction(context, step),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryLight,
                          foregroundColor: AppTheme.background,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 22),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusControl)),
                          textStyle: const TextStyle(fontFamily: AppTheme.fontFamily, fontSize: 15, fontWeight: FontWeight.w800),
                        ),
                        child: Text(showBilan ? l10n.onboardingSeeBilan : l10n.onboardingPlayNow),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  final OnboardingStepStatus status;
  const _Dot({required this.status});

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case OnboardingStepStatus.done:
        return Container(
          width: 28,
          height: 28,
          decoration: const BoxDecoration(color: AppTheme.primaryLight, shape: BoxShape.circle),
          child: const Icon(Icons.check_rounded, size: 16, color: AppTheme.background),
        );
      case OnboardingStepStatus.open:
        return Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: AppTheme.background,
            shape: BoxShape.circle,
            border: Border.all(color: AppTheme.primaryLight, width: 2),
          ),
        );
      case OnboardingStepStatus.locked:
        return Container(
          width: 28,
          height: 28,
          decoration: const BoxDecoration(color: AppTheme.surface, shape: BoxShape.circle),
          child: const Icon(Icons.lock_outline_rounded, size: 14, color: AppTheme.textSecondary),
        );
    }
  }
}
