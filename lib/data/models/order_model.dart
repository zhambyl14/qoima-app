import 'package:cloud_firestore/cloud_firestore.dart';
import 'cart_item_model.dart';

class OrderModel {
  final String            id;
  final String            clientPhone;
  final String            clientName;
  final String            clientUid;
  final String            adminUid;
  final String            storeName;
  final String            warehouseId;
  final String            warehouseAddress;
  final List<CartItemModel> items;
  final String            status;
  final String            orderType;
  final DateTime          createdAt;
  final String            address;
  final String            note;
  final double            depositAmount;
  final double            deliveryFee;
  final String            pickupCode;

  static const String typeSmartReservation = 'smart_reservation';
  static const String typeClickCollect     = 'click_collect';
  static const String typeDelivery         = 'delivery';

  static const String statusReserved  = 'reserved';
  static const String statusPending   = 'pending';
  static const String statusConfirmed = 'confirmed';
  static const String statusReady     = 'ready';
  static const String statusCompleted = 'completed';
  static const String statusCancelled = 'cancelled';

  const OrderModel({
    required this.id,
    required this.clientPhone,
    required this.clientName,
    this.clientUid       = '',
    required this.adminUid,
    required this.storeName,
    required this.warehouseId,
    this.warehouseAddress = '',
    required this.items,
    required this.status,
    required this.orderType,
    required this.createdAt,
    this.address       = '',
    this.note          = '',
    this.depositAmount = 0.0,
    this.deliveryFee   = 0.0,
    this.pickupCode    = '',
  });

  double get total             => items.fold(0.0, (s, i) => s + i.subtotal);
  double get totalWithDelivery => total + deliveryFee;
  double get remainingAmount   => (total - depositAmount).clamp(0.0, total);

  bool get isSmartReservation => orderType == typeSmartReservation;
  bool get isClickCollect     => orderType == typeClickCollect;
  bool get isDelivery         => orderType == typeDelivery;

  DateTime get expiresAt   => createdAt.add(const Duration(hours: 1));
  int  get minutesLeft     => expiresAt.difference(DateTime.now()).inMinutes.clamp(0, 60);
  bool get isExpired       =>
      isSmartReservation &&
      DateTime.now().isAfter(expiresAt) &&
      status == statusReserved;

  factory OrderModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return OrderModel(
      id:               doc.id,
      clientPhone:      d['clientPhone']      as String? ?? '',
      clientName:       d['clientName']       as String? ?? '',
      clientUid:        d['clientUid']        as String? ?? '',
      adminUid:         d['adminUid']         as String? ?? '',
      storeName:        d['storeName']        as String? ?? '',
      warehouseId:      d['warehouseId']      as String? ?? '',
      warehouseAddress: d['warehouseAddress'] as String? ?? '',
      items:            (d['items'] as List<dynamic>? ?? [])
          .map((e) => CartItemModel.fromJson(e as Map<String, dynamic>))
          .toList(),
      status:        d['status']    as String? ?? statusPending,
      orderType:     d['orderType'] as String? ?? typeClickCollect,
      createdAt:     (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      address:       d['address']       as String? ?? '',
      note:          d['note']          as String? ?? '',
      depositAmount: (d['depositAmount'] as num?)?.toDouble() ?? 0.0,
      deliveryFee:   (d['deliveryFee']   as num?)?.toDouble() ?? 0.0,
      pickupCode:    d['pickupCode']     as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'clientPhone':      clientPhone,
    'clientName':       clientName,
    'clientUid':        clientUid,
    'adminUid':         adminUid,
    'storeName':        storeName,
    'warehouseId':      warehouseId,
    'warehouseAddress': warehouseAddress,
    'items':            items.map((i) => i.toJson()).toList(),
    'status':           status,
    'orderType':        orderType,
    'createdAt':        Timestamp.fromDate(createdAt),
    'address':          address,
    'note':             note,
    'depositAmount':    depositAmount,
    'deliveryFee':      deliveryFee,
    'pickupCode':       pickupCode,
  };

  OrderModel copyWith({
    String? id, String? clientPhone, String? clientName, String? clientUid,
    String? adminUid, String? storeName, String? warehouseId,
    String? warehouseAddress, List<CartItemModel>? items,
    String? status, String? orderType, DateTime? createdAt,
    String? address, String? note, double? depositAmount, double? deliveryFee,
    String? pickupCode,
  }) => OrderModel(
    id:               id               ?? this.id,
    clientPhone:      clientPhone      ?? this.clientPhone,
    clientName:       clientName       ?? this.clientName,
    clientUid:        clientUid        ?? this.clientUid,
    adminUid:         adminUid         ?? this.adminUid,
    storeName:        storeName        ?? this.storeName,
    warehouseId:      warehouseId      ?? this.warehouseId,
    warehouseAddress: warehouseAddress ?? this.warehouseAddress,
    items:            items            ?? this.items,
    status:           status           ?? this.status,
    orderType:        orderType        ?? this.orderType,
    createdAt:        createdAt        ?? this.createdAt,
    address:          address          ?? this.address,
    note:             note             ?? this.note,
    depositAmount:    depositAmount    ?? this.depositAmount,
    deliveryFee:      deliveryFee      ?? this.deliveryFee,
    pickupCode:       pickupCode       ?? this.pickupCode,
  );
}
