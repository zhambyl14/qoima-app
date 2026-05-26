import 'package:cloud_firestore/cloud_firestore.dart';

class ReservationModel {
  final String id;
  final String productId;
  final String batchId;
  final String size;
  final int quantity;
  final String reservedBy;
  final DateTime expiresAt;
  final String status;

  static const String statusActive    = 'active';
  static const String statusCompleted = 'completed';
  static const String statusExpired   = 'expired';

  const ReservationModel({
    required this.id,
    required this.productId,
    required this.batchId,
    required this.size,
    required this.quantity,
    required this.reservedBy,
    required this.expiresAt,
    required this.status,
  });

  bool get isActive    => status == statusActive && expiresAt.isAfter(DateTime.now());
  int  get minutesLeft => expiresAt.difference(DateTime.now()).inMinutes.clamp(0, 60);

  factory ReservationModel.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return ReservationModel(
      id:         doc.id,
      productId:  d['productId']  as String? ?? '',
      batchId:    d['batchId']    as String? ?? '',
      size:       d['size']       as String? ?? '',
      quantity:   (d['quantity']  as num?)?.toInt() ?? 0,
      reservedBy: d['reservedBy'] as String? ?? '',
      expiresAt:  (d['expiresAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      status:     d['status']     as String? ?? statusExpired,
    );
  }

  Map<String, dynamic> toJson() => {
        'productId':  productId,
        'batchId':    batchId,
        'size':       size,
        'quantity':   quantity,
        'reservedBy': reservedBy,
        'expiresAt':  Timestamp.fromDate(expiresAt),
        'status':     status,
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
  }) =>
      ReservationModel(
        id:         id         ?? this.id,
        productId:  productId  ?? this.productId,
        batchId:    batchId    ?? this.batchId,
        size:       size       ?? this.size,
        quantity:   quantity   ?? this.quantity,
        reservedBy: reservedBy ?? this.reservedBy,
        expiresAt:  expiresAt  ?? this.expiresAt,
        status:     status     ?? this.status,
      );
}
