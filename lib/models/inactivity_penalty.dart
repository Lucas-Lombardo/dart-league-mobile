/// A weekly "-100 ELO for a week of inactivity" penalty, shown in the user's
/// history. Mirrors the backend `inactivity_penalties` row.
class InactivityPenalty {
  final String id;
  final int amount;
  final int eloBefore;
  final int eloAfter;
  final DateTime createdAt;

  InactivityPenalty({
    required this.id,
    required this.amount,
    required this.eloBefore,
    required this.eloAfter,
    required this.createdAt,
  });

  factory InactivityPenalty.fromJson(Map<String, dynamic> json) {
    return InactivityPenalty(
      id: json['id'] as String? ?? '',
      amount: json['amount'] as int? ?? 0,
      eloBefore: json['eloBefore'] as int? ?? 0,
      eloAfter: json['eloAfter'] as int? ?? 0,
      createdAt: _tryParseDateTime(json['createdAt'] as String?) ?? DateTime.now(),
    );
  }
}

DateTime? _tryParseDateTime(String? value) {
  if (value == null) return null;
  try {
    return DateTime.parse(value);
  } on FormatException {
    return null;
  }
}
