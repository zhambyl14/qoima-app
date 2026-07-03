class ReservationModel {
  final String id;
  final String productId;
  final String batchId;
  final String size;
  final int quantity;
  final String reservedBy;
  final DateTime expiresAt;
  final String status;
  final String clientPhone;
  final String warehouseId;
  final String adminUid;
  final String orderType;

  static const String statusActive = 'active';
  static const String statusCompleted = 'completed';
  static const String statusExpired = 'expired';

  const ReservationModel({
    required this.id,
    required this.productId,
    required this.batchId,
    required this.size,
    required this.quantity,
    required this.reservedBy,
    required this.expiresAt,
    required this.status,
    this.clientPhone = '',
    this.warehouseId = '',
    this.adminUid = '',
    this.orderType = '',
  });

  bool get isActive =>
      status == statusActive && expiresAt.isAfter(DateTime.now());
  int get minutesLeft =>
      expiresAt.difference(DateTime.now()).inMinutes.clamp(0, 60);

  /// Supabase `reservations` жолынан (snake_case бағандар).
  factory ReservationModel.fromMap(Map<String, dynamic> m) {
    DateTime dt(dynamic v) =>
        v is String ? (DateTime.tryParse(v) ?? DateTime.now()) : DateTime.now();
    return ReservationModel(
      id: m['id'] as String? ?? '',
      productId: m['product_id'] as String? ?? '',
      batchId: m['batch_id'] as String? ?? '',
      size: m['size'] as String? ?? '',
      quantity: (m['quantity'] as num?)?.toInt() ?? 0,
      reservedBy: m['reserved_by'] as String? ?? '',
      expiresAt: dt(m['expires_at']),
      status: m['status'] as String? ?? statusExpired,
      clientPhone: m['client_phone'] as String? ?? '',
      warehouseId: m['warehouse_id'] as String? ?? '',
      adminUid: m['admin_uid'] as String? ?? '',
      orderType: m['order_type'] as String? ?? '',
    );
  }

  /// Supabase жазу үшін (snake_case; бос uuid → null).
  Map<String, dynamic> toMap() => {
        if (id.isNotEmpty) 'id': id,
        'admin_uid': adminUid.isEmpty ? null : adminUid,
        'product_id': productId.isEmpty ? null : productId,
        'batch_id': batchId.isEmpty ? null : batchId,
        'size': size,
        'quantity': quantity,
        'reserved_by': reservedBy.isEmpty ? null : reservedBy,
        'expires_at': expiresAt.toIso8601String(),
        'status': status,
        'client_phone': clientPhone,
        'warehouse_id': warehouseId.isEmpty ? null : warehouseId,
        'order_type': orderType,
      };

  ReservationModel copyWith({
    String? id,
    String? productId,
    String? batchId,
    String? size,
    int? quantity,
    String? reservedBy,
    DateTime? expiresAt,
    String? status,
    String? clientPhone,
    String? warehouseId,
    String? adminUid,
    String? orderType,
  }) =>
      ReservationModel(
        id: id ?? this.id,
        productId: productId ?? this.productId,
        batchId: batchId ?? this.batchId,
        size: size ?? this.size,
        quantity: quantity ?? this.quantity,
        reservedBy: reservedBy ?? this.reservedBy,
        expiresAt: expiresAt ?? this.expiresAt,
        status: status ?? this.status,
        clientPhone: clientPhone ?? this.clientPhone,
        warehouseId: warehouseId ?? this.warehouseId,
        adminUid: adminUid ?? this.adminUid,
        orderType: orderType ?? this.orderType,
      );
}
