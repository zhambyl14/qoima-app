/// Ревизия жазбасы (недостача): тауардан нешеу жетіспейтіні.
/// status: 'open' → «Списать» басылған соң 'written_off'.
class RevisionModel {
  static const String statusOpen = 'open';
  static const String statusWrittenOff = 'written_off';

  final String id;
  final String productId;
  final String productName;
  final String warehouseId;
  final Map<String, int> sizesMissing;
  final int quantity;
  final String note;
  final String status;
  final String createdBy;
  final String createdByName;
  final DateTime createdAt;
  final DateTime? writtenOffAt;

  const RevisionModel({
    required this.id,
    required this.productId,
    required this.productName,
    required this.warehouseId,
    required this.sizesMissing,
    required this.quantity,
    this.note = '',
    this.status = statusOpen,
    this.createdBy = '',
    this.createdByName = '',
    required this.createdAt,
    this.writtenOffAt,
  });

  bool get isOpen => status == statusOpen;

  factory RevisionModel.fromMap(Map<String, dynamic> m) {
    DateTime? dt(dynamic v) => v is String ? DateTime.tryParse(v) : null;
    final raw = (m['sizes_missing'] as Map?) ?? {};
    return RevisionModel(
      id: m['id'] as String? ?? '',
      productId: m['product_id'] as String? ?? '',
      productName: m['product_name'] as String? ?? '',
      warehouseId: m['warehouse_id'] as String? ?? '',
      sizesMissing: raw.map(
          (k, v) => MapEntry(k.toString(), (v as num).toInt())),
      quantity: (m['quantity'] as num?)?.toInt() ?? 0,
      note: m['note'] as String? ?? '',
      status: m['status'] as String? ?? statusOpen,
      createdBy: m['created_by'] as String? ?? '',
      createdByName: m['created_by_name'] as String? ?? '',
      createdAt: dt(m['created_at']) ?? DateTime.now(),
      writtenOffAt: dt(m['written_off_at']),
    );
  }
}
