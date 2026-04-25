enum TrainingType {
  aroundTheClock,
  aroundTheClockDouble,
  aroundTheClockTriple,
  bobs27,
  highScore,
  checkout50,
  checkout81,
  checkout121,
}

extension TrainingTypeX on TrainingType {
  String get apiValue {
    switch (this) {
      case TrainingType.aroundTheClock:
        return 'around_the_clock';
      case TrainingType.aroundTheClockDouble:
        return 'around_the_clock_double';
      case TrainingType.aroundTheClockTriple:
        return 'around_the_clock_triple';
      case TrainingType.bobs27:
        return 'bobs_27';
      case TrainingType.highScore:
        return 'high_score';
      case TrainingType.checkout50:
        return 'checkout_50';
      case TrainingType.checkout81:
        return 'checkout_81';
      case TrainingType.checkout121:
        return 'checkout_121';
    }
  }

  static TrainingType fromApi(String value) {
    switch (value) {
      case 'around_the_clock':
        return TrainingType.aroundTheClock;
      case 'around_the_clock_double':
        return TrainingType.aroundTheClockDouble;
      case 'around_the_clock_triple':
        return TrainingType.aroundTheClockTriple;
      case 'bobs_27':
        return TrainingType.bobs27;
      case 'high_score':
        return TrainingType.highScore;
      case 'checkout_50':
        return TrainingType.checkout50;
      case 'checkout_81':
        return TrainingType.checkout81;
      case 'checkout_121':
        return TrainingType.checkout121;
    }
    throw ArgumentError('Unknown training type: $value');
  }

  /// True if a higher numeric score is better (used for displaying "Best").
  bool get higherIsBetter {
    switch (this) {
      case TrainingType.aroundTheClock:
      case TrainingType.aroundTheClockDouble:
      case TrainingType.aroundTheClockTriple:
      case TrainingType.checkout81:
      case TrainingType.checkout121:
        return false;
      case TrainingType.bobs27:
      case TrainingType.highScore:
      case TrainingType.checkout50:
        return true;
    }
  }
}

class TrainingSessionRecord {
  final String id;
  final TrainingType type;
  final int score;
  final int dartsThrown;
  final bool completed;
  final Map<String, dynamic>? details;
  final DateTime? completedAt;
  final DateTime createdAt;

  TrainingSessionRecord({
    required this.id,
    required this.type,
    required this.score,
    required this.dartsThrown,
    required this.completed,
    required this.details,
    required this.completedAt,
    required this.createdAt,
  });

  factory TrainingSessionRecord.fromJson(Map<String, dynamic> json) {
    return TrainingSessionRecord(
      id: json['id'] as String,
      type: TrainingTypeX.fromApi(json['type'] as String),
      score: (json['score'] as num).toInt(),
      dartsThrown: (json['dartsThrown'] as num?)?.toInt() ?? 0,
      completed: json['completed'] as bool? ?? true,
      details: json['details'] is Map<String, dynamic>
          ? json['details'] as Map<String, dynamic>
          : null,
      completedAt: json['completedAt'] != null
          ? DateTime.tryParse(json['completedAt'] as String)
          : null,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

class TrainingTypeStats {
  final TrainingType type;
  final int sessions;
  final num? bestScore;
  final num? averageScore;
  final num? lastScore;
  final DateTime? lastPlayedAt;
  final int totalDarts;
  final bool higherIsBetter;

  TrainingTypeStats({
    required this.type,
    required this.sessions,
    required this.bestScore,
    required this.averageScore,
    required this.lastScore,
    required this.lastPlayedAt,
    required this.totalDarts,
    required this.higherIsBetter,
  });

  factory TrainingTypeStats.fromJson(Map<String, dynamic> json) {
    return TrainingTypeStats(
      type: TrainingTypeX.fromApi(json['type'] as String),
      sessions: (json['sessions'] as num?)?.toInt() ?? 0,
      bestScore: json['bestScore'] as num?,
      averageScore: json['averageScore'] as num?,
      lastScore: json['lastScore'] as num?,
      lastPlayedAt: json['lastPlayedAt'] != null
          ? DateTime.tryParse(json['lastPlayedAt'] as String)
          : null,
      totalDarts: (json['totalDarts'] as num?)?.toInt() ?? 0,
      higherIsBetter: json['higherIsBetter'] as bool? ?? true,
    );
  }

  factory TrainingTypeStats.empty(TrainingType type) => TrainingTypeStats(
        type: type,
        sessions: 0,
        bestScore: null,
        averageScore: null,
        lastScore: null,
        lastPlayedAt: null,
        totalDarts: 0,
        higherIsBetter: type.higherIsBetter,
      );
}
