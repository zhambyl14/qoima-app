import 'package:cloud_firestore/cloud_firestore.dart';

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

  factory ClientModel.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return ClientModel(
      uid: doc.id,
      phone: d['phone'] as String? ?? '',
      email: d['email'] as String? ?? '',
      name: d['name'] as String? ?? '',
      city: d['city'] as String? ?? '',
      emailVerified: d['emailVerified'] as bool? ?? false,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'phone': phone,
        'email': email,
        'name': name,
        'city': city,
        'role': 'client',
        'emailVerified': emailVerified,
        'createdAt': Timestamp.fromDate(createdAt),
      };

  ClientModel copyWith(
          {String? uid,
          String? phone,
          String? email,
          String? name,
          String? city,
          bool? emailVerified,
          DateTime? createdAt}) =>
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
