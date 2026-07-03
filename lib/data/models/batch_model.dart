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

  static DateTime? _d(dynamic v) {
    if (v is DateTime) return v;
    if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
    return null;
  }

  factory DiscountModel.fromMap(Map<String, dynamic> m) => DiscountModel(
        active: m['active'] as bool? ?? false,
        type: m['type'] as String? ?? 'percent',
        value: (m['value'] as num?)?.toDouble() ?? 0,
        startsAt: _d(m['starts_at']),
        endsAt: _d(m['ends_at']),
      );

  /// Supabase JSONB үшін (ISO жолдар).
  Map<String, dynamic> toMapJson() => {
        'active': active,
        'type': type,
        'value': value,
        'starts_at': startsAt?.toIso8601String(),
        'ends_at': endsAt?.toIso8601String(),
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

  int get totalQuantity =>
      sizesQuantity.values.fold(0, (acc, qty) => acc + qty);

  int get totalAvailable =>
      sizesQuantity.keys.fold(0, (s, k) => s + availableForSize(k));

  bool get isSoldOut => totalAvailable <= 0;

  int availableForSize(String size) {
    final qty = sizesQuantity[size] ?? 0;
    final reserved = reservedSizes[size] ?? 0;
    return (qty - reserved).clamp(0, qty);
  }

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

  /// Supabase `batches` жолынан (snake_case + JSONB). purchase_price бөлек
  /// `batch_costs`-тан келеді — сервис оны copyWith арқылы сіңіреді.
  factory BatchModel.fromMap(Map<String, dynamic> m) {
    DateTime dt(dynamic v) => v is String
        ? (DateTime.tryParse(v) ?? DateTime.now())
        : (v is DateTime ? v : DateTime.now());
    Map<String, int> im(dynamic v) {
      final raw = (v as Map?) ?? {};
      return raw.map((k, val) => MapEntry(k.toString(), (val as num).toInt()));
    }

    final disc = m['discount'];
    return BatchModel(
      id: m['id'] as String? ?? '',
      dateArrived: dt(m['date_arrived']),
      purchasePrice: (m['purchase_price'] as num?)?.toDouble() ?? 0,
      sellingPrice: (m['selling_price'] as num?)?.toDouble() ?? 0,
      sizesQuantity: im(m['sizes_quantity']),
      reservedSizes: im(m['reserved_sizes']),
      warehouseId: m['warehouse_id'] as String? ?? '',
      discount: disc != null
          ? DiscountModel.fromMap(Map<String, dynamic>.from(disc as Map))
          : null,
    );
  }

  /// Supabase жазу үшін (snake_case; id/product_id/owner_uid сервисте; өзіндік
  /// құн БӨЛЕК batch_costs кестесіне жазылады, мұнда жоқ).
  Map<String, dynamic> toMap() => {
        'warehouse_id': warehouseId.isEmpty ? null : warehouseId,
        'date_arrived': dateArrived.toIso8601String(),
        'selling_price': sellingPrice,
        'sizes_quantity': sizesQuantity,
        'reserved_sizes': reservedSizes,
        if (discount != null) 'discount': discount!.toMapJson(),
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
