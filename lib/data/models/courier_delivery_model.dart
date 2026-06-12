import 'package:cloud_firestore/cloud_firestore.dart';

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

  factory CourierDeliveryModel.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return CourierDeliveryModel(
      id: doc.id,
      orderId: d['orderId'] as String? ?? '',
      orderNumber: (d['orderNumber'] as num?)?.toInt() ?? 0,
      amount: (d['amount'] as num?)?.toDouble() ?? 0.0,
      address: d['address'] as String? ?? '',
      clientName: d['clientName'] as String? ?? '',
      clientPhone: d['clientPhone'] as String? ?? '',
      warehouseAddresses:
          (d['warehouseAddresses'] as List<dynamic>? ?? [])
              .map((e) => e as String)
              .toList(),
      createdAt:
          (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      status: d['status'] as String? ?? statusNew,
    );
  }

  Map<String, dynamic> toJson() => {
        'orderId': orderId,
        'orderNumber': orderNumber,
        'amount': amount,
        'address': address,
        'clientName': clientName,
        'clientPhone': clientPhone,
        'warehouseAddresses': warehouseAddresses,
        'createdAt': Timestamp.fromDate(createdAt),
        'status': status,
      };
}
