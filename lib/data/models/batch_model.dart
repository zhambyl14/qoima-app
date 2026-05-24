import 'package:cloud_firestore/cloud_firestore.dart';

/// Модель партии (подколлекция "batches" внутри документа товара)
class BatchModel {
  final String id;
  final DateTime dateArrived;
  final double purchasePrice;
  final double sellingPrice;
  final Map<String, int> sizesQuantity;
  final String warehouseId; // қай қоймада

  const BatchModel({
    required this.id,
    required this.dateArrived,
    required this.purchasePrice,
    required this.sellingPrice,
    required this.sizesQuantity,
    this.warehouseId = '',
  });

  // ─── Вспомогательные геттеры ─────────────────────────────────────────────────

  /// Общее количество пар во всех размерах партии
  int get totalQuantity =>
      sizesQuantity.values.fold(0, (acc, qty) => acc + qty);

  /// Является ли партия полностью проданной
  bool get isSoldOut => sizesQuantity.values.every((qty) => qty <= 0);

  /// Маржинальность партии (цена продажи - себестоимость)
  double get margin => sellingPrice - purchasePrice;

  // ─── fromJson ────────────────────────────────────────────────────────────────
  factory BatchModel.fromJson(Map<String, dynamic> json, {String? docId}) {
    // Firestore возвращает Timestamp, при десериализации из Map — DateTime
    DateTime parseDate(dynamic raw) {
      if (raw is Timestamp) return raw.toDate();
      if (raw is DateTime) return raw;
      return DateTime.now();
    }

    // Приводим Map<dynamic, dynamic> из Firestore к Map<String, int>
    final rawSizes = json['sizes_quantity'] as Map<dynamic, dynamic>? ?? {};
    final sizesQuantity = rawSizes.map(
      (k, v) => MapEntry(k.toString(), (v as num).toInt()),
    );

    return BatchModel(
      id:            docId ?? json['id'] as String? ?? '',
      dateArrived:   parseDate(json['date_arrived']),
      purchasePrice: (json['purchase_price'] as num?)?.toDouble() ?? 0.0,
      sellingPrice:  (json['selling_price']  as num?)?.toDouble() ?? 0.0,
      sizesQuantity: sizesQuantity,
      warehouseId:   json['warehouseId'] as String? ?? '',
    );
  }

  // ─── fromFirestore ────────────────────────────────────────────────────────────
  factory BatchModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return BatchModel.fromJson(data, docId: doc.id);
  }

  // ─── toJson ──────────────────────────────────────────────────────────────────
  Map<String, dynamic> toJson() => {
        'id':             id,
        'date_arrived':   Timestamp.fromDate(dateArrived),
        'purchase_price': purchasePrice,
        'selling_price':  sellingPrice,
        'sizes_quantity': sizesQuantity,
        'warehouseId':    warehouseId,
      };

  // ─── copyWith ────────────────────────────────────────────────────────────────
  BatchModel copyWith({
    String? id,
    DateTime? dateArrived,
    double? purchasePrice,
    double? sellingPrice,
    Map<String, int>? sizesQuantity,
    String? warehouseId,
  }) => BatchModel(
    id:            id            ?? this.id,
    dateArrived:   dateArrived   ?? this.dateArrived,
    purchasePrice: purchasePrice ?? this.purchasePrice,
    sellingPrice:  sellingPrice  ?? this.sellingPrice,
    sizesQuantity: sizesQuantity ?? Map<String, int>.from(this.sizesQuantity),
    warehouseId:   warehouseId   ?? this.warehouseId,
  );

  /// Создаёт новую копию модели с изменённым количеством для конкретного размера.
  /// Используется при нажатии кнопок + / - во Flutter.
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