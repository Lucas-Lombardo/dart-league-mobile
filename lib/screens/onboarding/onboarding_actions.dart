import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/bot_match_config.dart';
import '../../models/bot_rank.dart';
import '../../providers/placement_provider.dart';
import '../../utils/app_theme.dart';
import '../home/friends_screen.dart';
import '../placement/placement_camera_setup_screen.dart';
import '../placement/placement_hub_screen.dart';
import 'onboarding_bilan_screen.dart';
import 'onboarding_models.dart';
import 'onboarding_provider.dart';

/// Step 2 of the journey: a short 301 against the easiest bot, one leg —
/// a first match finished in about six minutes, before the placement and
/// without its 501 double wall.
const BotMatchConfig onboardingBot301 = BotMatchConfig(
  gameMode: BotGameMode.x301,
  bestOf: 1,
  rank: BotRank.bronze,
);

/// Screens other features own, opened by a step's action. The daily challenge
/// belongs to its own feature: it registers its entry screen here (a missing
/// one just hides the "Play" button of that step).
final Map<String, WidgetBuilder> onboardingExternalScreens = {};

/// The actions this app version can run; any other one shows no button.
bool onboardingActionSupported(String action) => switch (action) {
      'bot_301' || 'placement' || 'friends' || 'bilan' => true,
      _ => onboardingExternalScreens.containsKey(action),
    };

/// Runs a step's "Play", then refreshes the journey on the way back (a step
/// may have been reached meanwhile).
Future<void> runOnboardingAction(BuildContext context, OnboardingStep step) async {
  final navigator = Navigator.of(context);
  final onboarding = maybeReadOnboarding(context);
  switch (step.action) {
    case 'bot_301':
      context.read<PlacementProvider>().startBotTrainingMatch(onboardingBot301);
      await navigator.push(MaterialPageRoute(
        builder: (_) => const PlacementCameraSetupScreen(),
      ));
    case 'placement':
      await navigator.push(MaterialPageRoute(
        builder: (_) => const PlacementHubScreen(),
      ));
    case 'friends':
      await navigator.push(MaterialPageRoute(
        builder: (_) => const _FriendsPage(),
      ));
    case 'bilan':
      await navigator.push(OnboardingBilanScreen.route());
    default:
      final builder = onboardingExternalScreens[step.action];
      if (builder == null) return;
      await navigator.push(MaterialPageRoute(builder: builder));
  }
  await onboarding?.refresh();
}

/// The Friends tab as a page, for the "Add a friend" step (its search sits in
/// the header).
class _FriendsPage extends StatelessWidget {
  const _FriendsPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(),
      body: const SafeArea(top: false, child: FriendsScreen()),
    );
  }
}
