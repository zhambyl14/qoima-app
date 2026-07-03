class CourierDeliveryModel {
  final String id;

  /// ID of the first sub-order this delivery belongs to.
  final String orderId;
  final int orderNumber;

  /// Delivery fee amount (from AppConfig at time of order).
  final double amount;

  /// Client's delivery address.
  final String address;
  final String clientName;
  final String clientPhone;

  /// Warehouse pickup addresses (where courier collects items).
  final List<String> warehouseAddresses;

  final DateTime createdAt;
  final String status;

  static const statusNew = 'new';
  static const statusAssigned = 'assigned';
  static const statusPicked = 'picked';
  static const statusDelivered = 'delivered';
  static const statusCancelled = 'cancelled';

  const CourierDeliveryModel({
    required this.id,
    required this.orderId,
    this.orderNumber = 0,
    required this.amount,
    required this.address,
    required this.clientName,
    required this.clientPhone,
    required this.warehouseAddresses,
    required this.createdAt,
    this.status = statusNew,
  });

  /// Supabase `courier_deliveries` жолынан (snake_case бағандар).
  factory CourierDeliveryModel.fromMap(Map<String, dynamic> m) {
    DateTime dt(dynamic v) =>
        v is String ? (DateTime.tryParse(v) ?? DateTime.now()) : DateTime.now();
    return CourierDeliveryModel(
      id: m['id'] as String? ?? '',
      orderId: m['order_id'] as String? ?? '',
      orderNumber: (m['order_number'] as num?)?.toInt() ?? 0,
      amount: (m['amount'] as num?)?.toDouble() ?? 0,
      address: m['address'] as String? ?? '',
      clientName: m['client_name'] as String? ?? '',
      clientPhone: m['client_phone'] as String? ?? '',
      warehouseAddresses:
          (m['warehouse_addresses'] as List?)?.map((e) => e.toString()).toList() ??
              [],
      createdAt: dt(m['created_at']),
      status: m['status'] as String? ?? statusNew,
    );
  }

  /// Supabase жазу үшін (snake_case).
  Map<String, dynamic> toMap() => {
        'order_id': orderId,
        'order_number': orderNumber,
        'amount': amount,
        'address': address,
        'client_name': clientName,
        'client_phone': clientPhone,
        'warehouse_addresses': warehouseAddresses,
        'status': status,
      };
}
