import 'package:cloud_firestore/cloud_firestore.dart';

class SaleModel {
  final String id;
  final String productId;
  final String batchId;
  final DateTime saleDate;
  final Map<String, int> sizesSold;
  final String selectedSize;
  final int    quantity;
  final double basePrice;       // скидкасыз баға (sellingPrice × qty)
  final double totalPrice;      // скидкадан кейінгі түпкі баға
  final double discountPercent; // 0..100
  final double discountAmount;  // ₸ айырмашылығы
  final String sellerId;
  final String sellerName;
  final String warehouseId;
  final bool   isOnline;
  final String orderId;
  final String deliveredByName;

  const SaleModel({
    required this.id,
    required this.productId,
    required this.batchId,
    required this.saleDate,
    required this.sizesSold,
    required this.selectedSize,
    required this.quantity,
    required this.basePrice,
    required this.totalPrice,
    required this.discountPercent,
    required this.discountAmount,
    required this.sellerId,
    required this.sellerName,
    this.warehouseId     = '',
    this.isOnline        = false,
    this.orderId         = '',
    this.deliveredByName = '',
  });

  factory SaleModel.fromJson(Map<String, dynamic> json, {String? docId}) {
    DateTime parseDate(dynamic raw) {
      if (raw is Timestamp) return raw.toDate();
      if (raw is DateTime) return raw;
      return DateTime.now();
    }
    final rawSizes = json['sizes_sold'] as Map<dynamic, dynamic>? ?? {};
    final sizesSold = rawSizes.map(
        (k, v) => MapEntry(k.toString(), (v as num).toInt()));
    final totalPrice = (json['total_price'] as num?)?.toDouble() ?? 0.0;
    final basePrice  = (json['base_price']  as num?)?.toDouble() ?? totalPrice;
    return SaleModel(
      id:              docId ?? json['id'] as String? ?? '',
      productId:       json['product_id']  as String? ?? '',
      batchId:         json['batch_id']    as String? ?? '',
      saleDate:        parseDate(json['sale_date']),
      sizesSold:       sizesSold,
      selectedSize:    json['selected_size']    as String? ?? '',
      quantity:        (json['quantity']        as num?)?.toInt()    ?? 0,
      basePrice:       basePrice,
      totalPrice:      totalPrice,
      discountPercent: (json['discount_percent'] as num?)?.toDouble() ?? 0.0,
      discountAmount:  (json['discount_amount']  as num?)?.toDouble() ?? 0.0,
      sellerId:        json['seller_id']         as String? ?? '',
      sellerName:      json['seller_name']        as String? ?? '',
      warehouseId:     json['warehouseId']        as String? ?? '',
      isOnline:        json['is_online']          as bool?   ?? false,
      orderId:         json['order_id']           as String? ?? '',
      deliveredByName: json['delivered_by_name']  as String? ?? '',
    );
  }

  factory SaleModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return SaleModel.fromJson(data, docId: doc.id);
  }

  Map<String, dynamic> toJson() => {
    'id':               id,
    'product_id':       productId,
    'batch_id':         batchId,
    'sale_date':        Timestamp.fromDate(saleDate),
    'sizes_sold':       sizesSold,
    'selected_size':    selectedSize,
    'quantity':         quantity,
    'base_price':       basePrice,
    'total_price':      totalPrice,
    'discount_percent': discountPercent,
    'discount_amount':  discountAmount,
    'seller_id':         sellerId,
    'seller_name':       sellerName,
    'warehouseId':       warehouseId,
    'is_online':         isOnline,
    'order_id':          orderId,
    'delivered_by_name': deliveredByName,
  };

  SaleModel copyWith({
    String? id, String? productId, String? batchId, DateTime? saleDate,
    Map<String, int>? sizesSold, String? selectedSize, int? quantity,
    double? basePrice, double? totalPrice, double? discountPercent,
    double? discountAmount, String? sellerId, String? sellerName,
    String? warehouseId, bool? isOnline, String? orderId, String? deliveredByName,
  }) => SaleModel(
    id:              id              ?? this.id,
    productId:       productId       ?? this.productId,
    batchId:         batchId         ?? this.batchId,
    saleDate:        saleDate        ?? this.saleDate,
    sizesSold:       sizesSold       ?? this.sizesSold,
    selectedSize:    selectedSize    ?? this.selectedSize,
    quantity:        quantity        ?? this.quantity,
    basePrice:       basePrice       ?? this.basePrice,
    totalPrice:      totalPrice      ?? this.totalPrice,
    discountPercent: discountPercent ?? this.discountPercent,
    discountAmount:  discountAmount  ?? this.discountAmount,
    sellerId:        sellerId        ?? this.sellerId,
    sellerName:      sellerName      ?? this.sellerName,
    warehouseId:     warehouseId     ?? this.warehouseId,
    isOnline:        isOnline        ?? this.isOnline,
    orderId:         orderId         ?? this.orderId,
    deliveredByName: deliveredByName ?? this.deliveredByName,
  );
}
