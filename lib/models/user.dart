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
  });

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
      bannedUntil: json['bannedUntil'] != null ? DateTime.parse(json['bannedUntil'] as String) : null,
      createdAt: json['createdAt'] != null ? DateTime.parse(json['createdAt'] as String) : null,
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
      if (bannedUntil != null) 'bannedUntil': bannedUntil!.toIso8601String(),
      if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
    };
  }
}
