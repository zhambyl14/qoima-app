class CartItemModel {
  final String productId;
  final String productName;
  final String batchId;
  final String size;
  final int qty;
  final double price; // итоговая цена со скидкой товара (effectivePrice)
  final double originalPrice; // цена без скидки (для зачёркнутой), 0 = нет скидки
  final String adminUid;
  final String storeName;
  final String imageUrl;
  final String warehouseId;
  final String warehouseAddress;
  // Себетте «тапсырысқа таңдалды ма» (Wildberries/Kaspi стилі — чекбокс).
  // Әдепкі true: бұрынғы тапсырыс беру логикасы бәрін алады.
  final bool selected;
  /// «Өлшеп көру» (0050): курьер ҚОСА алып баратын өлшем — сол тауар, сол
  /// партия, басқа өлшем. '' = жоқ. Ақшасы тек негізгі [size] үшін төленеді;
  /// бұл өлшем қоймада брондалады да, клиент оны таңдаса своп жасалады.
  /// Тек жеткізуде және сол қаладағы дүкенде мағыналы.
  final String altSize;
  /// Курьер своп жасағанда толтырылады (0052): клиент қосалқы өлшемді алды,
  /// ал МЫНАУ — бастапқы тапсырыстағы өлшем (қоймаға қайтарылады).
  final String swappedFrom;
  /// Клиент негізгі өлшемді алды — МЫНАУ қайтарылатын қосалқы өлшем.
  final String returnedSize;

  const CartItemModel({
    required this.productId,
    required this.productName,
    required this.batchId,
    required this.size,
    required this.qty,
    required this.price,
    this.originalPrice = 0,
    required this.adminUid,
    required this.storeName,
    required this.imageUrl,
    required this.warehouseId,
    this.warehouseAddress = '',
    this.selected = true,
    this.altSize = '',
    this.swappedFrom = '',
    this.returnedSize = '',
  });

  factory CartItemModel.fromJson(Map<String, dynamic> json) => CartItemModel(
        productId: json['productId'] as String? ?? '',
        productName: json['productName'] as String? ?? '',
        batchId: json['batchId'] as String? ?? '',
        size: json['size'] as String? ?? '',
        qty: (json['qty'] as num?)?.toInt() ?? 1,
        price: (json['price'] as num?)?.toDouble() ?? 0.0,
        originalPrice: (json['originalPrice'] as num?)?.toDouble() ?? 0.0,
        adminUid: json['adminUid'] as String? ?? '',
        storeName: json['storeName'] as String? ?? '',
        imageUrl: json['imageUrl'] as String? ?? '',
        warehouseId: json['warehouseId'] as String? ?? '',
        warehouseAddress: json['warehouseAddress'] as String? ?? '',
        selected: json['selected'] as bool? ?? true,
        altSize: json['altSize'] as String? ?? '',
        swappedFrom: json['swappedFrom'] as String? ?? '',
        returnedSize: json['returnedSize'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'productId': productId,
        'productName': productName,
        'batchId': batchId,
        'size': size,
        'qty': qty,
        'price': price,
        'originalPrice': originalPrice,
        'adminUid': adminUid,
        'storeName': storeName,
        'imageUrl': imageUrl,
        'warehouseId': warehouseId,
        'warehouseAddress': warehouseAddress,
        'selected': selected,
        if (altSize.isNotEmpty) 'altSize': altSize,
        if (swappedFrom.isNotEmpty) 'swappedFrom': swappedFrom,
        if (returnedSize.isNotEmpty) 'returnedSize': returnedSize,
      };

  CartItemModel copyWith({
    String? productId,
    String? productName,
    String? batchId,
    String? size,
    int? qty,
    double? price,
    double? originalPrice,
    String? adminUid,
    String? storeName,
    String? imageUrl,
    String? warehouseId,
    String? warehouseAddress,
    bool? selected,
    String? altSize,
  }) =>
      CartItemModel(
        productId: productId ?? this.productId,
        productName: productName ?? this.productName,
        batchId: batchId ?? this.batchId,
        size: size ?? this.size,
        qty: qty ?? this.qty,
        price: price ?? this.price,
        originalPrice: originalPrice ?? this.originalPrice,
        adminUid: adminUid ?? this.adminUid,
        storeName: storeName ?? this.storeName,
        imageUrl: imageUrl ?? this.imageUrl,
        warehouseId: warehouseId ?? this.warehouseId,
        warehouseAddress: warehouseAddress ?? this.warehouseAddress,
        selected: selected ?? this.selected,
        altSize: altSize ?? this.altSize,
        swappedFrom: swappedFrom,
        returnedSize: returnedSize,
      );

  bool get hasAltSize => altSize.isNotEmpty;

  /// «Өлшеп көру» аяқталған позиция: клиент қай өлшемді алды, қайсысы қайтады.
  bool get fittingResolved =>
      swappedFrom.isNotEmpty || returnedSize.isNotEmpty;
  String get returningSize =>
      swappedFrom.isNotEmpty ? swappedFrom : returnedSize;

  double get subtotal => price * qty;

  // Скидка товара активна, если оригинальная цена выше итоговой
  bool get hasDiscount => originalPrice > price && originalPrice > 0;
  double get originalSubtotal => (originalPrice > 0 ? originalPrice : price) * qty;
}
