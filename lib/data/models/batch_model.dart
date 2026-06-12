import 'package:cloud_firestore/cloud_firestore.dart';

// ── Discount attached to a batch ──────────────────────────────────────────────
class DiscountModel {
  final bool active;
  final String type; // 'percent' | 'amount'
  final double value;
  final DateTime? startsAt;
  final DateTime? endsAt;

  const DiscountModel({
    required this.active,
    required this.type,
    required this.value,
    this.startsAt,
    this.endsAt,
  });

  factory DiscountModel.fromMap(Map<String, dynamic> m) => DiscountModel(
        active: m['active'] as bool? ?? false,
        type: m['type'] as String? ?? 'percent',
        value: (m['value'] as num?)?.toDouble() ?? 0,
        startsAt: (m['starts_at'] as Timestamp?)?.toDate(),
        endsAt: (m['ends_at'] as Timestamp?)?.toDate(),
      );

  Map<String, dynamic> toMap() => {
        'active': active,
        'type': type,
        'value': value,
        'starts_at': startsAt != null ? Timestamp.fromDate(startsAt!) : null,
        'ends_at': endsAt != null ? Timestamp.fromDate(endsAt!) : null,
      };
}

// ── Effective price calculation (single source of truth) ──────────────────────
double effectivePrice(BatchModel batch) {
  final d = batch.discount;
  if (d == null || !d.active) return batch.sellingPrice;
  final now = DateTime.now();
  if (d.startsAt != null && now.isBefore(d.startsAt!)) return batch.sellingPrice;
  if (d.endsAt != null && now.isAfter(d.endsAt!)) return batch.sellingPrice;
  final raw = d.type == 'percent'
      ? batch.sellingPrice * (1 - d.value / 100)
      : batch.sellingPrice - d.value;
  return raw < 0 ? 0 : raw.roundToDouble();
}

bool hasActiveDiscount(BatchModel batch) =>
    effectivePrice(batch) < batch.sellingPrice;

int discountBadgePercent(BatchModel batch) {
  if (!hasActiveDiscount(batch)) return 0;
  return ((1 - effectivePrice(batch) / batch.sellingPrice) * 100).round();
}

class BatchModel {
  final String id;
  final DateTime dateArrived;
  final double purchasePrice;
  final double sellingPrice;
  final Map<String, int> sizesQuantity;
  final Map<String, int> reservedSizes;
  final String warehouseId;
  final DiscountModel? discount;

  const BatchModel({
    required this.id,
    required this.dateArrived,
    required this.purchasePrice,
    required this.sellingPrice,
    required this.sizesQuantity,
    Map<String, int>? reservedSizes,
    this.warehouseId = '',
    this.discount,
  }) : reservedSizes = reservedSizes ?? const {};

  // Physical total (ignores reservations)
  int get totalQuantity =>
      sizesQuantity.values.fold(0, (acc, qty) => acc + qty);

  // Net available after subtracting all reservations
  int get totalAvailable =>
      sizesQuantity.keys.fold(0, (s, k) => s + availableForSize(k));

  // Sold out when no unreserved stock remains
  bool get isSoldOut => totalAvailable <= 0;

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

    final rawDiscount = json['discount'] as Map<String, dynamic>?;
    return BatchModel(
      id: docId ?? json['id'] as String? ?? '',
      dateArrived: parseDate(json['date_arrived']),
      purchasePrice: (json['purchase_price'] as num?)?.toDouble() ?? 0.0,
      sellingPrice: (json['selling_price'] as num?)?.toDouble() ?? 0.0,
      sizesQuantity: sizesQuantity,
      reservedSizes: reservedSizes,
      warehouseId: json['warehouseId'] as String? ?? '',
      discount: rawDiscount != null
          ? DiscountModel.fromMap(rawDiscount)
          : null,
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
        if (discount != null) 'discount': discount!.toMap(),
      };

  BatchModel copyWith({
    String? id,
    DateTime? dateArrived,
    double? purchasePrice,
    double? sellingPrice,
    Map<String, int>? sizesQuantity,
    Map<String, int>? reservedSizes,
    String? warehouseId,
    Object? discount = _kSentinel,
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
        discount: identical(discount, _kSentinel)
            ? this.discount
            : discount as DiscountModel?,
      );

static const _kSentinel = Object();

  BatchModel updateSize(String size, int delta) {
    final updated = Map<String, int>.from(sizesQuantity);
    final current = updated[size] ?? 0;
    updated[size] = (current + delta).clamp(0, 9999);
    return copyWith(sizesQuantity: updated);
  }

  @override
  String toString() =>
      'BatchModel(id: $id, date: $dateArrived, total: $totalQuantity шт.)';
}
