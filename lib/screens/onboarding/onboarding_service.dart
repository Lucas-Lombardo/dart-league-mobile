import '../../services/api_service.dart';
import 'onboarding_models.dart';

/// GET /onboarding and POST /onboarding/bilan/seen (CONTRACT.md §14.2b).
class OnboardingService {
  const OnboardingService();

  /// The journey, after the server paid whatever became due (a day opened…).
  Future<OnboardingStatus> fetch() async {
    final response = await ApiService.get('/onboarding');
    return OnboardingStatus.fromJson(response);
  }

  /// The day-7 summary was shown: the card gives way to "Today".
  Future<void> markBilanSeen() async {
    await ApiService.post('/onboarding/bilan/seen', {});
  }
}
