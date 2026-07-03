/// admin / seller / superadmin профилі (Supabase `public.users` жолы).
class UserModel {
  final String uid;
  final String name;
  final String email;
  final String role; // 'admin' | 'seller' | 'superadmin'
  final String ownerId; // admin → өз uid; seller → admin uid (немесе '')
  final bool active;
  final DateTime? createdAt;
  final String businessCode; // admin: 6 цифрлы код; seller: ''
  final String assignedWarehouseId; // seller-ге бекітілген қойма; admin: ''
  final String joinStatus; // 'none' | 'pending' | 'active'
  final bool termsAccepted;
  final DateTime? termsAcceptedAt;
  final String shopRequestId; // жіберілген заявка ID ('' = жоқ)
  // 'approved' | 'none' | 'pending' | 'rejected'.
  final String shopStatus;
  // Жалпы блок (superadmin қояды): true болса иесі де, сатушылары да кіре алмайды.
  final bool blocked;
  final String blockReason;

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
    this.blocked = false,
    this.blockReason = '',
  });

  bool get isAdmin => role == 'admin';
  bool get isSeller => role == 'seller';
  bool get isSuperadmin => role == 'superadmin';

  static DateTime? _date(dynamic raw) {
    if (raw is DateTime) return raw;
    if (raw is String && raw.isNotEmpty) return DateTime.tryParse(raw);
    return null;
  }

  /// Supabase жолынан (snake_case бағандар).
  factory UserModel.fromMap(Map<String, dynamic> m) => UserModel(
        uid: m['id'] as String? ?? '',
        name: m['name'] as String? ?? '',
        email: m['email'] as String? ?? '',
        role: m['role'] as String? ?? 'admin',
        ownerId: m['owner_id'] as String? ?? '',
        active: m['active'] as bool? ?? true,
        createdAt: _date(m['created_at']),
        businessCode: m['business_code'] as String? ?? '',
        assignedWarehouseId: m['assigned_warehouse_id'] as String? ?? '',
        joinStatus: m['join_status'] as String? ?? 'none',
        termsAccepted: m['terms_accepted'] as bool? ?? false,
        termsAcceptedAt: _date(m['terms_accepted_at']),
        shopRequestId: m['shop_request_id'] as String? ?? '',
        shopStatus: m['shop_status'] as String? ?? 'approved',
        blocked: m['blocked'] as bool? ?? false,
        blockReason: m['block_reason'] as String? ?? '',
      );

  /// Supabase жазу үшін (snake_case; бос uuid → null).
  Map<String, dynamic> toMap() => {
        'id': uid,
        'name': name,
        'email': email,
        'role': role,
        'owner_id': ownerId.isEmpty ? null : ownerId,
        'active': active,
        'business_code': businessCode,
        'assigned_warehouse_id':
            assignedWarehouseId.isEmpty ? null : assignedWarehouseId,
        'join_status': joinStatus,
        'terms_accepted': termsAccepted,
        if (termsAcceptedAt != null)
          'terms_accepted_at': termsAcceptedAt!.toIso8601String(),
        'shop_request_id': shopRequestId,
        'shop_status': shopStatus,
      };
}
