import 'package:cloud_firestore/cloud_firestore.dart';

class ClientModel {
  final String uid;
  final String phone;
  final String name;
  final DateTime createdAt;

  const ClientModel({
    required this.uid,
    required this.phone,
    required this.name,
    required this.createdAt,
  });

  factory ClientModel.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return ClientModel(
      uid: doc.id,
      phone: d['phone'] as String? ?? '',
      name: d['name'] as String? ?? '',
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'phone': phone,
        'name': name,
        'role': 'client',
        'createdAt': Timestamp.fromDate(createdAt),
      };

  ClientModel copyWith(
          {String? uid, String? phone, String? name, DateTime? createdAt}) =>
      ClientModel(
        uid: uid ?? this.uid,
        phone: phone ?? this.phone,
        name: name ?? this.name,
        createdAt: createdAt ?? this.createdAt,
      );
}
