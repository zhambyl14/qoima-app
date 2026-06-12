import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String uid;
  final String name;
  final String email;
  final String role; // 'admin' | 'seller' | 'superadmin'
  final String ownerId; // admin → өз uid; seller → admin uid (немесе '')
  final bool active;
  final DateTime? createdAt;
  // v2.2 жаңа өрістер
  final String businessCode; // admin: 6 цифрлы код; seller: ''
  final String assignedWarehouseId; // seller-ге бекітілген қойма; admin: ''
  final String joinStatus; // 'none' | 'pending' | 'active'
  // v7 — Terms & дүкен ашу заявкасы (тек admin/owner үшін)
  final bool termsAccepted; // шарттарды қабылдады ма
  final DateTime? termsAcceptedAt; // қашан қабылдады
  final String shopRequestId; // жіберілген заявка ID ('' = жоқ)
  // 'approved' | 'none' | 'pending' | 'rejected'.
  // Өріс жоқ болса 'approved' — ескі (бар) admin-дерді бұзбау үшін (grandfather).
  final String shopStatus;

  const UserModel({
    required this.uid,
    required this.name,
    required this.email,
    required this.role,
    required this.ownerId,
    this.active = true,
    this.createdAt,
    this.businessCode = '',
    this.assignedWarehouseId = '',
    this.joinStatus = 'none',
    this.termsAccepted = false,
    this.termsAcceptedAt,
    this.shopRequestId = '',
    this.shopStatus = 'approved',
  });

  bool get isAdmin => role == 'admin';
  bool get isSeller => role == 'seller';
  bool get isSuperadmin => role == 'superadmin';

  factory UserModel.fromJson(Map<String, dynamic> json, {String? docId}) {
    DateTime? parseDate(dynamic raw) {
      if (raw is Timestamp) return raw.toDate();
      if (raw is DateTime) return raw;
      return null;
    }

    final id = docId ?? json['uid'] as String? ?? '';
    return UserModel(
      uid: id,
      name: json['name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      role: json['role'] as String? ?? 'admin',
      ownerId: json['ownerId'] as String? ?? id,
      active: json['active'] as bool? ?? true,
      createdAt: parseDate(json['created_at']),
      businessCode: json['businessCode'] as String? ?? '',
      assignedWarehouseId: json['assignedWarehouseId'] as String? ?? '',
      joinStatus: json['joinStatus'] as String? ?? 'none',
      termsAccepted: json['termsAccepted'] as bool? ?? false,
      termsAcceptedAt: parseDate(json['termsAcceptedAt']),
      shopRequestId: json['shopRequestId'] as String? ?? '',
      shopStatus: json['shopStatus'] as String? ?? 'approved',
    );
  }

  factory UserModel.fromFirestore(DocumentSnapshot doc) =>
      UserModel.fromJson(doc.data() as Map<String, dynamic>, docId: doc.id);

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'name': name,
        'email': email,
        'role': role,
        'ownerId': ownerId,
        'active': active,
        if (createdAt != null) 'created_at': Timestamp.fromDate(createdAt!),
        'businessCode': businessCode,
        'assignedWarehouseId': assignedWarehouseId,
        'joinStatus': joinStatus,
        'termsAccepted': termsAccepted,
        if (termsAcceptedAt != null)
          'termsAcceptedAt': Timestamp.fromDate(termsAcceptedAt!),
        'shopRequestId': shopRequestId,
        'shopStatus': shopStatus,
      };
}
