class CartItemModel {
  final String productId;
  final String productName;
  final String batchId;
  final String size;
  final int    qty;
  final double price;
  final String adminUid;
  final String storeName;
  final String imageUrl;
  final String warehouseId;
  final String warehouseAddress;

  const CartItemModel({
    required this.productId,
    required this.productName,
    required this.batchId,
    required this.size,
    required this.qty,
    required this.price,
    required this.adminUid,
    required this.storeName,
    required this.imageUrl,
    required this.warehouseId,
    this.warehouseAddress = '',
  });

  factory CartItemModel.fromJson(Map<String, dynamic> json) => CartItemModel(
    productId:        json['productId']        as String? ?? '',
    productName:      json['productName']      as String? ?? '',
    batchId:          json['batchId']          as String? ?? '',
    size:             json['size']             as String? ?? '',
    qty:              (json['qty']             as num?)?.toInt()    ?? 1,
    price:            (json['price']           as num?)?.toDouble() ?? 0.0,
    adminUid:         json['adminUid']         as String? ?? '',
    storeName:        json['storeName']        as String? ?? '',
    imageUrl:         json['imageUrl']         as String? ?? '',
    warehouseId:      json['warehouseId']      as String? ?? '',
    warehouseAddress: json['warehouseAddress'] as String? ?? '',
  );

  Map<String, dynamic> toJson() => {
    'productId':        productId,
    'productName':      productName,
    'batchId':          batchId,
    'size':             size,
    'qty':              qty,
    'price':            price,
    'adminUid':         adminUid,
    'storeName':        storeName,
    'imageUrl':         imageUrl,
    'warehouseId':      warehouseId,
    'warehouseAddress': warehouseAddress,
  };

  CartItemModel copyWith({
    String? productId, String? productName, String? batchId,
    String? size, int? qty, double? price, String? adminUid,
    String? storeName, String? imageUrl, String? warehouseId,
    String? warehouseAddress,
  }) => CartItemModel(
    productId:        productId        ?? this.productId,
    productName:      productName      ?? this.productName,
    batchId:          batchId          ?? this.batchId,
    size:             size             ?? this.size,
    qty:              qty              ?? this.qty,
    price:            price            ?? this.price,
    adminUid:         adminUid         ?? this.adminUid,
    storeName:        storeName        ?? this.storeName,
    imageUrl:         imageUrl         ?? this.imageUrl,
    warehouseId:      warehouseId      ?? this.warehouseId,
    warehouseAddress: warehouseAddress ?? this.warehouseAddress,
  );

  double get subtotal => price * qty;
}
