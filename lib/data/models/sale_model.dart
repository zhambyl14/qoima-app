import 'package:cloud_firestore/cloud_firestore.dart';

class SaleModel {
  final String id;
  final String productId;
  final String batchId;
  final DateTime saleDate;
  final Map<String, int> sizesSold;
  final String selectedSize;
  final int quantity;
  final double basePrice; // скидкасыз баға (sellingPrice × qty)
  final double totalPrice; // скидкадан кейінгі түпкі баға
  final double discountPercent; // 0..100
  final double discountAmount; // ₸ айырмашылығы
  final String sellerId;
  final String sellerName;
  final String warehouseId;
  final bool isOnline;
  final String orderId;
  final String deliveredByName;
  final String productName;
  final double purchasePrice;
  // 'cash' = Наличный, 'kaspi' = Kaspi, 'halyk' = Halyk Bank, '' = unknown
  final String paymentMethod;
  // Бронь: онлайн депозиттің банкі ('kaspi'/'halyk'), басқа жағдайда бос
  final String depositPaymentMethod;
  // Чек нөмірі (ЧЕК-NNNNN офлайн, #NNNNN онлайн), сатылым кезінде жазылады
  final String receiptNumber;
  // 'sale' = қалыпты сатылым, 'return' = қайтару (теріс жазба, аналитиканы балансылайды)
  final String saleType;

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
    this.warehouseId = '',
    this.isOnline = false,
    this.orderId = '',
    this.deliveredByName = '',
    this.productName = '',
    this.purchasePrice = 0,
    this.paymentMethod = '',
    this.depositPaymentMethod = '',
    this.receiptNumber = '',
    this.saleType = 'sale',
  });

  // Қайтару жазбасы ма (теріс сома, аналитиканы балансылайды)
  bool get isReturn => saleType == 'return';

  // Скидка применена (товарная и/или промокод), если итог ниже базовой цены
  bool get hasDiscount => basePrice > totalPrice + 0.5;

  // Итоговый процент скидки (если discount_percent не записан — считаем сами)
  double get effectiveDiscountPercent {
    if (discountPercent > 0) return discountPercent;
    if (basePrice <= 0 || !hasDiscount) return 0;
    return ((1 - totalPrice / basePrice) * 100);
  }

  factory SaleModel.fromJson(Map<String, dynamic> json, {String? docId}) {
    DateTime parseDate(dynamic raw) {
      if (raw is Timestamp) return raw.toDate();
      if (raw is DateTime) return raw;
      return DateTime.now();
    }

    final rawSizes = json['sizes_sold'] as Map<dynamic, dynamic>? ?? {};
    final sizesSold =
        rawSizes.map((k, v) => MapEntry(k.toString(), (v as num).toInt()));
    final totalPrice = (json['total_price'] as num?)?.toDouble() ?? 0.0;
    final basePrice = (json['base_price'] as num?)?.toDouble() ?? totalPrice;
    return SaleModel(
      id: docId ?? json['id'] as String? ?? '',
      productId: json['product_id'] as String? ?? '',
      batchId: json['batch_id'] as String? ?? '',
      saleDate: parseDate(json['sale_date']),
      sizesSold: sizesSold,
      selectedSize: json['selected_size'] as String? ?? '',
      quantity: (json['quantity'] as num?)?.toInt() ?? 0,
      basePrice: basePrice,
      totalPrice: totalPrice,
      discountPercent: (json['discount_percent'] as num?)?.toDouble() ?? 0.0,
      discountAmount: (json['discount_amount'] as num?)?.toDouble() ?? 0.0,
      sellerId: json['seller_id'] as String? ?? '',
      sellerName: json['seller_name'] as String? ?? '',
      warehouseId: json['warehouseId'] as String? ?? '',
      isOnline: json['is_online'] as bool? ?? false,
      orderId: json['order_id'] as String? ?? '',
      deliveredByName: json['delivered_by_name'] as String? ?? '',
      productName: json['product_name'] as String? ?? '',
      purchasePrice: (json['purchase_price'] as num?)?.toDouble() ?? 0.0,
      paymentMethod: json['payment_method'] as String? ?? '',
      depositPaymentMethod: json['deposit_payment_method'] as String? ?? '',
      receiptNumber: json['receipt_number'] as String? ?? '',
      saleType: json['type'] as String? ?? 'sale',
    );
  }

  factory SaleModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return SaleModel.fromJson(data, docId: doc.id);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'product_id': productId,
        'batch_id': batchId,
        'sale_date': Timestamp.fromDate(saleDate),
        'sizes_sold': sizesSold,
        'selected_size': selectedSize,
        'quantity': quantity,
        'base_price': basePrice,
        'total_price': totalPrice,
        'discount_percent': discountPercent,
        'discount_amount': discountAmount,
        'seller_id': sellerId,
        'seller_name': sellerName,
        'warehouseId': warehouseId,
        'is_online': isOnline,
        'order_id': orderId,
        'delivered_by_name': deliveredByName,
        'product_name': productName,
        'purchase_price': purchasePrice,
        'payment_method': paymentMethod,
        'deposit_payment_method': depositPaymentMethod,
        'receipt_number': receiptNumber,
        'type': saleType,
      };

  SaleModel copyWith({
    String? id,
    String? productId,
    String? batchId,
    DateTime? saleDate,
    Map<String, int>? sizesSold,
    String? selectedSize,
    int? quantity,
    double? basePrice,
    double? totalPrice,
    double? discountPercent,
    double? discountAmount,
    String? sellerId,
    String? sellerName,
    String? warehouseId,
    bool? isOnline,
    String? orderId,
    String? deliveredByName,
    String? productName,
    double? purchasePrice,
    String? paymentMethod,
    String? depositPaymentMethod,
    String? receiptNumber,
    String? saleType,
  }) =>
      SaleModel(
        id: id ?? this.id,
        productId: productId ?? this.productId,
        batchId: batchId ?? this.batchId,
        saleDate: saleDate ?? this.saleDate,
        sizesSold: sizesSold ?? this.sizesSold,
        selectedSize: selectedSize ?? this.selectedSize,
        quantity: quantity ?? this.quantity,
        basePrice: basePrice ?? this.basePrice,
        totalPrice: totalPrice ?? this.totalPrice,
        discountPercent: discountPercent ?? this.discountPercent,
        discountAmount: discountAmount ?? this.discountAmount,
        sellerId: sellerId ?? this.sellerId,
        sellerName: sellerName ?? this.sellerName,
        warehouseId: warehouseId ?? this.warehouseId,
        isOnline: isOnline ?? this.isOnline,
        orderId: orderId ?? this.orderId,
        deliveredByName: deliveredByName ?? this.deliveredByName,
        productName: productName ?? this.productName,
        purchasePrice: purchasePrice ?? this.purchasePrice,
        paymentMethod: paymentMethod ?? this.paymentMethod,
        depositPaymentMethod: depositPaymentMethod ?? this.depositPaymentMethod,
        receiptNumber: receiptNumber ?? this.receiptNumber,
        saleType: saleType ?? this.saleType,
      );
}
