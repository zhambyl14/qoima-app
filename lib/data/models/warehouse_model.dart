class WarehouseModel {
  final String id;
  final String name;
  final String? address;
  final String? note;
  final bool isMain;
  final DateTime createdAt;
  final int totalPairs;
  final int totalProducts;

  const WarehouseModel({
    required this.id,
    required this.name,
    this.address,
    this.note,
    this.isMain = false,
    required this.createdAt,
    this.totalPairs = 0,
    this.totalProducts = 0,
  });

  /// Supabase `warehouses` жолынан (snake_case бағандар).
  factory WarehouseModel.fromMap(Map<String, dynamic> m) {
    DateTime parse(dynamic raw) =>
        raw is String ? (DateTime.tryParse(raw) ?? DateTime.now()) : DateTime.now();
    return WarehouseModel(
      id: m['id'] as String? ?? '',
      name: m['name'] as String? ?? '',
      address: m['address'] as String?,
      note: m['note'] as String?,
      isMain: m['is_main'] as bool? ?? false,
      createdAt: parse(m['created_at']),
      totalPairs: (m['total_pairs'] as num?)?.toInt() ?? 0,
      totalProducts: (m['total_products'] as num?)?.toInt() ?? 0,
    );
  }

  /// Supabase жазу үшін (snake_case; owner_uid сервисте қосылады).
  Map<String, dynamic> toMap() => {
        'name': name,
        'address': address,
        'note': note,
        'is_main': isMain,
        'total_pairs': totalPairs,
        'total_products': totalProducts,
      };

  WarehouseModel copyWith({
    String? id,
    String? name,
    String? address,
    String? note,
    bool? isMain,
    DateTime? createdAt,
    int? totalPairs,
    int? totalProducts,
  }) =>
      WarehouseModel(
        id: id ?? this.id,
        name: name ?? this.name,
        address: address ?? this.address,
        note: note ?? this.note,
        isMain: isMain ?? this.isMain,
        createdAt: createdAt ?? this.createdAt,
        totalPairs: totalPairs ?? this.totalPairs,
        totalProducts: totalProducts ?? this.totalProducts,
      );
}
