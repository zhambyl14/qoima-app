import 'package:cloud_firestore/cloud_firestore.dart';

class ClientModel {
  final String uid;
  final String phone;
  final String name;
  final String city;
  final DateTime createdAt;

  const ClientModel({
    required this.uid,
    required this.phone,
    required this.name,
    this.city = '',
    required this.createdAt,
  });

  factory ClientModel.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return ClientModel(
      uid: doc.id,
      phone: d['phone'] as String? ?? '',
      name: d['name'] as String? ?? '',
      city: d['city'] as String? ?? '',
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'phone': phone,
        'name': name,
        'city': city,
        'role': 'client',
        'createdAt': Timestamp.fromDate(createdAt),
      };

  ClientModel copyWith(
          {String? uid,
          String? phone,
          String? name,
          String? city,
          DateTime? createdAt}) =>
      ClientModel(
        uid: uid ?? this.uid,
        phone: phone ?? this.phone,
        name: name ?? this.name,
        city: city ?? this.city,
        createdAt: createdAt ?? this.createdAt,
      );
}
