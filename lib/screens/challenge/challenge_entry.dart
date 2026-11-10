import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/auth_provider.dart';
import '../../services/push_notification_service.dart';
import '../../utils/app_theme.dart';
import '../../widgets/home_tiles.dart';
import '../onboarding/onboarding_actions.dart';
import '../progression/today_section.dart';
import 'challenge_api.dart';
import 'challenge_podium_screen.dart';
import 'challenge_screen.dart';
import 'challenge_widgets.dart';
import 'logic/challenge_strategy.dart';

/// Called once at startup (main.dart): the "first 7 days" journey opens the
/// challenge from its day-4 step — the only way in while the "Today" block
/// is hidden for new players.
void registerChallengeEntryPoints() {
  onboardingExternalScreens['challenge'] = (_) => const ChallengeScreen();
}

String? _userIdOf(BuildContext context) {
  try {
    return context.read<AuthProvider>().currentUser?.id;
  } on ProviderNotFoundException {
    // No auth in the tree (widget tests): the store's own account.
    return ChallengeStore.instance.userId;
  }
}

/// The "Daily challenge" row of the home "Today" block (mockup Accueil).
class ChallengeTodayRow extends StatelessWidget {
  const ChallengeTodayRow({super.key});

  /// Whether the row has something to show; also asks for a fresh snapshot
  /// when the cached one is stale (safe in a build: it notifies later).
  static bool isVisible(BuildContext context) {
    final userId = _userIdOf(context);
    ChallengeStore.instance.refreshIfStale(userId);
    return ChallengeStore.instance.todayFor(userId) != null;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ChallengeStore.instance,
      builder: (context, _) {
        final today = ChallengeStore.instance.todayFor(_userIdOf(context));
        if (today == null) return const SizedBox.shrink();
        final l10n = AppLocalizations.of(context);
        final ranked = today.ranked;
        final format = today.format.short.resolve(context);
        String subtitle = format;
        if (ranked != null && ranked.submitted && ranked.position != null && ranked.total != null) {
          subtitle = l10n.challengeRowDone(format, challengeOrdinal(context, ranked.position!), ranked.total!);
        } else if (ranked != null && ranked.submitted) {
          subtitle = l10n.challengeRowPlayed(format, challengeScoreText(today.format, ranked.score ?? 0, unfinished: l10n.challengeUnfinished));
        }
        return TodayRow(
          icon: Icons.track_changes_rounded,
          accent: ranked == null,
          title: l10n.challengeTitle,
          subtitle: subtitle,
          trailing: today.streak.current > 0
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.local_fire_department_outlined, size: 15, color: ChallengeColors.accent),
                    const SizedBox(width: 4),
                    Text(
                      l10n.challengeStreakDays(today.streak.current),
                      style: AppTheme.rowTitle.copyWith(fontSize: 14, fontWeight: FontWeight.w800),
                    ),
                  ],
                )
              : null,
          onTap: () async {
            final userId = _userIdOf(context);
            await ChallengeScreen.open(context);
            await ChallengeStore.instance.refresh(userId: userId);
          },
        );
      },
    );
  }
}

/// The « Défi du jour » tile of the home's « Aujourd'hui » (mockup AccFinal):
/// the format of the day and its XP, blue border until the ranked attempt is
/// played; then the place (or the score) instead of the XP.
class ChallengeTodayTile extends StatelessWidget {
  /// XP of the ranked attempt (GET /progression/content → xp.challenge);
  /// null leaves it out.
  final int? xp;
  const ChallengeTodayTile({super.key, this.xp});

  static bool isVisible(BuildContext context) => ChallengeTodayRow.isVisible(context);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ChallengeStore.instance,
      builder: (context, _) {
        final today = ChallengeStore.instance.todayFor(_userIdOf(context));
        if (today == null) return const SizedBox.shrink();
        final l10n = AppLocalizations.of(context);
        final ranked = today.ranked;
        final format = today.format.short.resolve(context);
        var detail = format;
        if (ranked != null && ranked.submitted && ranked.position != null && ranked.total != null) {
          detail = l10n.challengeRowDone(format, challengeOrdinal(context, ranked.position!), ranked.total!);
        } else if (ranked != null && ranked.submitted) {
          detail = l10n.challengeRowPlayed(
            format,
            challengeScoreText(today.format, ranked.score ?? 0, unfinished: l10n.challengeUnfinished),
          );
        }
        return HomeTodayTile(
          icon: Icons.track_changes_rounded,
          accent: ranked == null,
          title: l10n.challengeTitle,
          detail: detail,
          xp: ranked == null && xp != null ? l10n.homeXpGain(xp!) : null,
          onTap: () async {
            final userId = _userIdOf(context);
            await ChallengeScreen.open(context);
            await ChallengeStore.instance.refresh(userId: userId);
          },
        );
      },
    );
  }
}

/// Zero-size helper that lives on the home screen: opens the challenge from
/// its pushes ("daily_challenge" at 18:00, "daily_challenge_crown" when the
/// n°1 is paid) and keeps the snapshot fresh.
class ChallengeHomeHooks extends StatefulWidget {
  const ChallengeHomeHooks({super.key});

  @override
  State<ChallengeHomeHooks> createState() => _ChallengeHomeHooksState();
}

class _ChallengeHomeHooksState extends State<ChallengeHomeHooks> {
  static bool _isChallengePush(Map<String, dynamic> data) =>
      data['type'] == 'daily_challenge' || data['type'] == 'daily_challenge_crown';

  @override
  void initState() {
    super.initState();
    PushNotificationService.addOpenedListener(_onPushOpened);
    // App killed, then opened by the 18:00 push: the tap was dispatched
    // before this home row existed. Claim it now (once).
    final launch = PushNotificationService.claimLaunchData(_isChallengePush);
    if (launch != null) _onPushOpened(launch);
  }

  @override
  void dispose() {
    PushNotificationService.removeOpenedListener(_onPushOpened);
    super.dispose();
  }

  void _onPushOpened(Map<String, dynamic> data) {
    if (!mounted || !_isChallengePush(data)) return;
    PushNotificationService.markHandled(data);
    // Never navigate in the middle of a build (initState, or a listener
    // flushed while the home screen mounts): after this frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (data['type'] == 'daily_challenge') {
        ChallengeScreen.open(context);
      } else {
        final date = data['date'] is String ? data['date'] as String : null;
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChallengePodiumScreen(date: date)));
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
