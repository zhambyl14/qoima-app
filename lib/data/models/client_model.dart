/// Клиент профилі (Supabase `public.clients` жолы).
class ClientModel {
  final String uid;
  final String phone;
  final String email;
  final String name;
  final String city;
  final bool emailVerified;
  final DateTime createdAt;

  const ClientModel({
    required this.uid,
    required this.phone,
    this.email = '',
    required this.name,
    this.city = '',
    this.emailVerified = false,
    required this.createdAt,
  });

  static DateTime _date(dynamic raw) {
    if (raw is DateTime) return raw;
    if (raw is String && raw.isNotEmpty) {
      return DateTime.tryParse(raw) ?? DateTime.now();
    }
    return DateTime.now();
  }

  /// Supabase жолынан (snake_case бағандар).
  factory ClientModel.fromMap(Map<String, dynamic> m) => ClientModel(
        uid: m['id'] as String? ?? '',
        phone: m['phone'] as String? ?? '',
        email: m['email'] as String? ?? '',
        name: m['name'] as String? ?? '',
        city: m['city'] as String? ?? '',
        emailVerified: m['email_verified'] as bool? ?? false,
        createdAt: _date(m['created_at']),
      );

  Map<String, dynamic> toMap() => {
        'id': uid,
        'phone': phone,
        'email': email,
        'name': name,
        'city': city,
        'email_verified': emailVerified,
      };

  ClientModel copyWith({
    String? uid,
    String? phone,
    String? email,
    String? name,
    String? city,
    bool? emailVerified,
    DateTime? createdAt,
  }) =>
      ClientModel(
        uid: uid ?? this.uid,
        phone: phone ?? this.phone,
        email: email ?? this.email,
        name: name ?? this.name,
        city: city ?? this.city,
        emailVerified: emailVerified ?? this.emailVerified,
        createdAt: createdAt ?? this.createdAt,
      );
}
