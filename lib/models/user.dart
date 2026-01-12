class User {
  final String id;
  final String username;
  final String email;
  final int elo;
  final String rank;
  final DateTime? createdAt;

  User({
    required this.id,
    required this.username,
    required this.email,
    required this.elo,
    required this.rank,
    this.createdAt,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String? ?? '',
      username: json['username'] as String? ?? 'Unknown',
      email: json['email'] as String? ?? '',
      elo: json['elo'] as int? ?? 1200,
      rank: json['rank'] as String? ?? 'unranked',
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
      if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
    };
  }
}
