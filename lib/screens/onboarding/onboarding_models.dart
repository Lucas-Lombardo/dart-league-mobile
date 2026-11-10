import '../../models/progression.dart' show LocalizedText;

/// "Your first 7 days" — GET /onboarding (docs/progression/CONTRACT.md
/// §14.2b). Every parser is defensive: a missing or odd field gives a default,
/// an unknown step status reads as locked, an unknown action shows no button.

enum OnboardingStepStatus { done, open, locked }

OnboardingStepStatus _stepStatus(dynamic raw) => switch (raw) {
      'done' => OnboardingStepStatus.done,
      'open' => OnboardingStepStatus.open,
      _ => OnboardingStepStatus.locked,
    };

int _int(dynamic v, [int fallback = 0]) => v is num ? v.toInt() : fallback;
double? _double(dynamic v) => v is num ? v.toDouble() : null;
String? _str(dynamic v) => v is String && v.isNotEmpty ? v : null;
DateTime? _date(dynamic v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;
Map<String, dynamic> _map(dynamic v) =>
    v is Map ? v.map((k, val) => MapEntry('$k', val)) : const {};

class OnboardingRewardItem {
  final String id;
  final String type;
  final LocalizedText name;
  const OnboardingRewardItem({required this.id, required this.type, required this.name});

  static OnboardingRewardItem? fromJson(dynamic json) {
    final m = _map(json);
    final id = _str(m['id']);
    if (id == null) return null;
    return OnboardingRewardItem(
      id: id,
      type: _str(m['type']) ?? '',
      name: LocalizedText.fromJson(m['name']),
    );
  }
}

class OnboardingStep {
  final String id;
  final int day;
  final LocalizedText title;
  final OnboardingStepStatus status;

  /// What "Play" opens: 'bot_301', 'placement', 'challenge', 'friends',
  /// 'bilan'… An action this app does not know shows no button.
  final String action;
  final int xp;
  final OnboardingRewardItem? rewardItem;
  final int premiumDays;
  final int progress;
  final int threshold;

  const OnboardingStep({
    required this.id,
    required this.day,
    required this.title,
    required this.status,
    required this.action,
    this.xp = 0,
    this.rewardItem,
    this.premiumDays = 0,
    this.progress = 0,
    this.threshold = 1,
  });

  bool get isDone => status == OnboardingStepStatus.done;
  bool get isOpen => status == OnboardingStepStatus.open;
  bool get isLocked => status == OnboardingStepStatus.locked;

  factory OnboardingStep.fromJson(dynamic json) {
    final m = _map(json);
    return OnboardingStep(
      id: _str(m['id']) ?? '',
      day: _int(m['day'], 1),
      title: LocalizedText.fromJson(m['title']),
      status: _stepStatus(m['status']),
      action: _str(m['action']) ?? 'none',
      xp: _int(m['xp']),
      rewardItem: OnboardingRewardItem.fromJson(m['rewardItem']),
      premiumDays: _int(m['premiumDays']),
      progress: _int(m['progress']),
      threshold: _int(m['threshold'], 1),
    );
  }
}

class OnboardingBilan {
  final int matches;
  final double? average;
  final double? averageStart;
  final double? averageDelta;
  final int? bestVisit;
  final String rank;

  const OnboardingBilan({
    required this.matches,
    this.average,
    this.averageStart,
    this.averageDelta,
    this.bestVisit,
    this.rank = 'unranked',
  });

  static OnboardingBilan? fromJson(dynamic json) {
    if (json is! Map) return null;
    final m = _map(json);
    final best = m['bestVisit'];
    return OnboardingBilan(
      matches: _int(m['matches']),
      average: _double(m['average']),
      averageStart: _double(m['averageStart']),
      averageDelta: _double(m['averageDelta']),
      bestVisit: best is num ? best.toInt() : null,
      rank: _str(m['rank']) ?? 'unranked',
    );
  }
}

class OnboardingStatus {
  /// Show the home card: the journey runs, or its summary is not seen yet.
  final bool active;

  /// 'none' | 'active' | 'completed' | 'expired'.
  final String status;
  final int day;
  final int journeyDays;
  final int maxDays;
  final int doneCount;
  final int totalCount;
  final String? currentStepId;
  final DateTime? nextUnlockAt;
  final List<OnboardingStep> steps;
  final int premiumDays;
  final DateTime? premiumUntil;
  final OnboardingBilan? bilan;
  final bool bilanSeen;

  const OnboardingStatus({
    this.active = false,
    this.status = 'none',
    this.day = 0,
    this.journeyDays = 7,
    this.maxDays = 14,
    this.doneCount = 0,
    this.totalCount = 0,
    this.currentStepId,
    this.nextUnlockAt,
    this.steps = const [],
    this.premiumDays = 0,
    this.premiumUntil,
    this.bilan,
    this.bilanSeen = false,
  });

  static const none = OnboardingStatus();

  bool get isCompleted => status == 'completed';

  /// The summary is ready and was never shown.
  bool get bilanPending => isCompleted && !bilanSeen && bilan != null;

  /// The step the card puts forward: the open one, else null.
  OnboardingStep? get currentStep {
    final id = currentStepId;
    if (id == null) return null;
    for (final s in steps) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// The next step that opens on a later day (for "Tomorrow: …").
  OnboardingStep? get nextLockedStep {
    for (final s in steps) {
      if (s.isLocked) return s;
    }
    return null;
  }

  factory OnboardingStatus.fromJson(dynamic json) {
    final m = _map(json);
    final steps = (m['steps'] is List ? m['steps'] as List : const [])
        .map(OnboardingStep.fromJson)
        .where((s) => s.id.isNotEmpty)
        .toList();
    return OnboardingStatus(
      active: m['active'] == true,
      status: _str(m['status']) ?? 'none',
      day: _int(m['day']),
      journeyDays: _int(m['journeyDays'], 7),
      maxDays: _int(m['maxDays'], 14),
      doneCount: _int(m['doneCount']),
      totalCount: _int(m['totalCount'], steps.length),
      currentStepId: _str(m['currentStepId']),
      nextUnlockAt: _date(m['nextUnlockAt']),
      steps: steps,
      premiumDays: _int(m['premiumDays']),
      premiumUntil: _date(m['premiumUntil']),
      bilan: OnboardingBilan.fromJson(m['bilan']),
      bilanSeen: m['bilanSeen'] == true,
    );
  }
}
