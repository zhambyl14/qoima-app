import 'package:cloud_firestore/cloud_firestore.dart';

class BatchModel {
  final String id;
  final DateTime dateArrived;
  final double purchasePrice;
  final double sellingPrice;
  final Map<String, int> sizesQuantity;
  final Map<String, int> reservedSizes;
  final String warehouseId;

  const BatchModel({
    required this.id,
    required this.dateArrived,
    required this.purchasePrice,
    required this.sellingPrice,
    required this.sizesQuantity,
    Map<String, int>? reservedSizes,
    this.warehouseId = '',
  }) : reservedSizes = reservedSizes ?? const {};

  // Physical total (ignores reservations)
  int get totalQuantity =>
      sizesQuantity.values.fold(0, (acc, qty) => acc + qty);

  // Physically sold out (no stock at all)
  bool get isSoldOut => sizesQuantity.values.every((qty) => qty <= 0);

  // Available for a specific size after subtracting reservations
  int availableForSize(String size) {
    final qty = sizesQuantity[size] ?? 0;
    final reserved = reservedSizes[size] ?? 0;
    return (qty - reserved).clamp(0, qty);
  }

  // All sizes with available (unreserved) stock
  Map<String, int> get availableSizes {
    final result = <String, int>{};
    for (final size in sizesQuantity.keys) {
      final avail = availableForSize(size);
      if (avail > 0) result[size] = avail;
    }
    return result;
  }

  bool get isEffectivelySoldOut => availableSizes.isEmpty;

  double get margin => sellingPrice - purchasePrice;

  factory BatchModel.fromJson(Map<String, dynamic> json, {String? docId}) {
    DateTime parseDate(dynamic raw) {
      if (raw is Timestamp) return raw.toDate();
      if (raw is DateTime) return raw;
      return DateTime.now();
    }

    final rawSizes = json['sizes_quantity'] as Map<dynamic, dynamic>? ?? {};
    final sizesQuantity = rawSizes.map(
      (k, v) => MapEntry(k.toString(), (v as num).toInt()),
    );

    final rawReserved = json['reserved_sizes'] as Map<dynamic, dynamic>? ?? {};
    final reservedSizes = rawReserved.map(
      (k, v) => MapEntry(k.toString(), (v as num).toInt()),
    );

    return BatchModel(
      id: docId ?? json['id'] as String? ?? '',
      dateArrived: parseDate(json['date_arrived']),
      purchasePrice: (json['purchase_price'] as num?)?.toDouble() ?? 0.0,
      sellingPrice: (json['selling_price'] as num?)?.toDouble() ?? 0.0,
      sizesQuantity: sizesQuantity,
      reservedSizes: reservedSizes,
      warehouseId: json['warehouseId'] as String? ?? '',
    );
  }

  factory BatchModel.fromFirestore(DocumentSnapshot doc) =>
      BatchModel.fromJson(doc.data() as Map<String, dynamic>, docId: doc.id);

  Map<String, dynamic> toJson() => {
        'id': id,
        'date_arrived': Timestamp.fromDate(dateArrived),
        'purchase_price': purchasePrice,
        'selling_price': sellingPrice,
        'sizes_quantity': sizesQuantity,
        'reserved_sizes': reservedSizes,
        'warehouseId': warehouseId,
      };

  BatchModel copyWith({
    String? id,
    DateTime? dateArrived,
    double? purchasePrice,
    double? sellingPrice,
    Map<String, int>? sizesQuantity,
    Map<String, int>? reservedSizes,
    String? warehouseId,
  }) =>
      BatchModel(
        id: id ?? this.id,
        dateArrived: dateArrived ?? this.dateArrived,
        purchasePrice: purchasePrice ?? this.purchasePrice,
        sellingPrice: sellingPrice ?? this.sellingPrice,
        sizesQuantity:
            sizesQuantity ?? Map<String, int>.from(this.sizesQuantity),
        reservedSizes:
            reservedSizes ?? Map<String, int>.from(this.reservedSizes),
        warehouseId: warehouseId ?? this.warehouseId,
      );

  BatchModel updateSize(String size, int delta) {
    final updated = Map<String, int>.from(sizesQuantity);
    final current = updated[size] ?? 0;
    updated[size] = (current + delta).clamp(0, 9999);
    return copyWith(sizesQuantity: updated);
  }

  @override
  String toString() =>
      'BatchModel(id: $id, date: $dateArrived, total: $totalQuantity пар)';
}
