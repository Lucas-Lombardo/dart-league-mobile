import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'onboarding_models.dart';
import 'onboarding_service.dart';

/// "Your first 7 days" for the home screen: the card replaces "Today" while
/// [isActive]. Keeps the last good value on failure — a flaky network never
/// flips the home between the two blocks — and an old server (404) simply
/// means no journey.
class OnboardingProvider extends ChangeNotifier {
  OnboardingProvider({OnboardingService service = const OnboardingService()})
      : _service = service;

  final OnboardingService _service;
  OnboardingStatus? _status;
  Future<void>? _inFlight;

  OnboardingStatus? get status => _status;

  /// The home shows the journey card instead of the "Today" block.
  bool get isActive => _status?.active ?? false;

  /// Coalesces concurrent calls (the home card and a pull-to-refresh).
  Future<void> refresh() => _inFlight ??= _load().whenComplete(() => _inFlight = null);

  Future<void> _load() async {
    try {
      final next = await _service.fetch();
      _status = next;
      notifyListeners();
    } catch (e) {
      debugPrint('OnboardingProvider.refresh: $e');
    }
  }

  /// The summary screen was shown. The card stays until the server agrees,
  /// so a failed call simply shows it again next time.
  Future<void> markBilanSeen() async {
    try {
      await _service.markBilanSeen();
      final s = _status;
      if (s != null) {
        _status = OnboardingStatus(
          active: false,
          status: s.status,
          day: s.day,
          journeyDays: s.journeyDays,
          maxDays: s.maxDays,
          doneCount: s.doneCount,
          totalCount: s.totalCount,
          steps: s.steps,
          premiumDays: s.premiumDays,
          premiumUntil: s.premiumUntil,
          bilan: s.bilan,
          bilanSeen: true,
        );
        notifyListeners();
      }
    } catch (e) {
      debugPrint('OnboardingProvider.markBilanSeen: $e');
    }
  }

  void reset() {
    _status = null;
    notifyListeners();
  }

  @visibleForTesting
  void debugSeed(OnboardingStatus? status) {
    _status = status;
    notifyListeners();
  }
}

/// The provider when registered (null in a test tree without it).
OnboardingProvider? maybeWatchOnboarding(BuildContext context) {
  try {
    return Provider.of<OnboardingProvider>(context);
  } on ProviderNotFoundException {
    return null;
  }
}

OnboardingProvider? maybeReadOnboarding(BuildContext context) {
  try {
    return Provider.of<OnboardingProvider>(context, listen: false);
  } on ProviderNotFoundException {
    return null;
  }
}
