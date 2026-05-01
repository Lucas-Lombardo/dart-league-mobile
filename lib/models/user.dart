DateTime? _tryParseDateTime(String? value) {
  if (value == null) return null;
  try {
    return DateTime.parse(value);
  } on FormatException {
    return null;
  }
}

class User {
  final String id;
  final String username;
  final String email;
  final int elo;
  final String rank;
  final int wins;
  final int losses;
  final String role;
  final bool isBanned;
  final DateTime? bannedUntil;
  final DateTime? createdAt;
  final String language;
  final bool isEmailVerified;
  final bool isPremium;
  final DateTime? premiumExpiresAt;

  User({
    required this.id,
    required this.username,
    required this.email,
    required this.elo,
    required this.rank,
    this.wins = 0,
    this.losses = 0,
    this.role = 'player',
    this.isBanned = false,
    this.bannedUntil,
    this.createdAt,
    this.language = 'en',
    this.isEmailVerified = false,
    this.isPremium = false,
    this.premiumExpiresAt,
  });

  /// Whether premium is currently active (true and not expired).
  bool get isPremiumActive {
    if (!isPremium) return false;
    if (premiumExpiresAt == null) return true;
    return premiumExpiresAt!.isAfter(DateTime.now());
  }

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String? ?? '',
      username: json['username'] as String? ?? 'Unknown',
      email: json['email'] as String? ?? '',
      elo: json['elo'] as int? ?? 1200,
      rank: json['rank'] as String? ?? 'unranked',
      wins: json['wins'] as int? ?? 0,
      losses: json['losses'] as int? ?? 0,
      role: json['role'] as String? ?? 'player',
      isBanned: json['isBanned'] as bool? ?? false,
      bannedUntil: _tryParseDateTime(json['bannedUntil'] as String?),
      createdAt: _tryParseDateTime(json['createdAt'] as String?),
      language: json['language'] as String? ?? 'en',
      isEmailVerified: json['isEmailVerified'] as bool? ?? false,
      isPremium: json['isPremium'] as bool? ?? false,
      premiumExpiresAt: _tryParseDateTime(json['premiumExpiresAt'] as String?),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'email': email,
      'elo': elo,
      'rank': rank,
      'wins': wins,
      'losses': losses,
      'role': role,
      'isBanned': isBanned,
      'language': language,
      'isEmailVerified': isEmailVerified,
      'isPremium': isPremium,
      if (bannedUntil != null) 'bannedUntil': bannedUntil!.toIso8601String(),
      if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
      if (premiumExpiresAt != null)
        'premiumExpiresAt': premiumExpiresAt!.toIso8601String(),
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is User && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
