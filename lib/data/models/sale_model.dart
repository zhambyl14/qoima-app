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
  final String paymentMethod;
  final String depositPaymentMethod;
  final String receiptNumber;
  final String saleType; // 'sale' | 'return' | 'writeoff'

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

  bool get isReturn => saleType == 'return';
  bool get isWriteOff => saleType == 'writeoff';
  bool get hasDiscount => basePrice > totalPrice + 0.5;

  double get effectiveDiscountPercent {
    if (discountPercent > 0) return discountPercent;
    if (basePrice <= 0 || !hasDiscount) return 0;
    return ((1 - totalPrice / basePrice) * 100);
  }

  /// Supabase `sales_history` жолынан (snake_case + JSONB).
  factory SaleModel.fromMap(Map<String, dynamic> m) {
    DateTime dt(dynamic v) =>
        v is String ? (DateTime.tryParse(v) ?? DateTime.now()) : DateTime.now();
    Map<String, int> im(dynamic v) {
      final raw = (v as Map?) ?? {};
      return raw.map((k, val) => MapEntry(k.toString(), (val as num).toInt()));
    }

    final total = (m['total_price'] as num?)?.toDouble() ?? 0;
    return SaleModel(
      id: m['id'] as String? ?? '',
      productId: m['product_id'] as String? ?? '',
      batchId: m['batch_id'] as String? ?? '',
      saleDate: dt(m['sale_date']),
      sizesSold: im(m['sizes_sold']),
      selectedSize: m['selected_size'] as String? ?? '',
      quantity: (m['quantity'] as num?)?.toInt() ?? 0,
      basePrice: (m['base_price'] as num?)?.toDouble() ?? total,
      totalPrice: total,
      discountPercent: (m['discount_percent'] as num?)?.toDouble() ?? 0,
      discountAmount: (m['discount_amount'] as num?)?.toDouble() ?? 0,
      sellerId: m['seller_id'] as String? ?? '',
      sellerName: m['seller_name'] as String? ?? '',
      warehouseId: m['warehouse_id'] as String? ?? '',
      isOnline: m['is_online'] as bool? ?? false,
      orderId: m['order_id'] as String? ?? '',
      deliveredByName: m['delivered_by_name'] as String? ?? '',
      productName: m['product_name'] as String? ?? '',
      purchasePrice: (m['purchase_price'] as num?)?.toDouble() ?? 0,
      paymentMethod: m['payment_method'] as String? ?? '',
      depositPaymentMethod: m['deposit_payment_method'] as String? ?? '',
      receiptNumber: m['receipt_number'] as String? ?? '',
      saleType: m['type'] as String? ?? 'sale',
    );
  }

  /// Supabase жазу үшін (snake_case; owner_uid сервисте қосылады).
  Map<String, dynamic> toMap() => {
        'product_id': productId.isEmpty ? null : productId,
        'batch_id': batchId.isEmpty ? null : batchId,
        'sale_date': saleDate.toIso8601String(),
        'sizes_sold': sizesSold,
        'selected_size': selectedSize,
        'quantity': quantity,
        'base_price': basePrice,
        'total_price': totalPrice,
        'discount_percent': discountPercent,
        'discount_amount': discountAmount,
        'seller_id': sellerId,
        'seller_name': sellerName,
        'warehouse_id': warehouseId.isEmpty ? null : warehouseId,
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
