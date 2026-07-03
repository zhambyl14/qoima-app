class StoreModel {
  final String adminUid;
  final String storeName;
  final String storeSlug;
  final String logoUrl;
  final String city;
  final String phone;
  final String description;
  final String address;
  final List<String> visibleWarehouseIds;
  final bool isPublished;
  final DateTime createdAt;
  final DateTime updatedAt;
  final double deliveryFeeCity;
  final double deliveryFreeThreshold;
  final String paymentCardNumber;
  final String paymentCardHolder;
  final String paymentBank;
  // v10 — иесі (заявкадан көшіріледі) және модерация күйі
  final String ownerName;
  final String ownerIin;
  final String category;
  final String status; // 'active' | 'blocked'
  final String blockReason;
  final DateTime? blockedAt;
  final String blockedBy;

  bool get isBlocked => status == 'blocked';

  const StoreModel({
    required this.adminUid,
    required this.storeName,
    required this.storeSlug,
    required this.logoUrl,
    required this.city,
    required this.phone,
    required this.description,
    this.address = '',
    required this.visibleWarehouseIds,
    required this.isPublished,
    required this.createdAt,
    required this.updatedAt,
    this.deliveryFeeCity = 1500.0,
    this.deliveryFreeThreshold = 0.0,
    this.paymentCardNumber = '',
    this.paymentCardHolder = '',
    this.paymentBank = '',
    this.ownerName = '',
    this.ownerIin = '',
    this.category = '',
    this.status = 'active',
    this.blockReason = '',
    this.blockedAt,
    this.blockedBy = '',
  });

  static String generateSlug(String name) => name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9а-яёА-ЯЁ\s]'), '')
      .trim()
      .replaceAll(RegExp(r'\s+'), '-');

  /// Supabase `stores` жолынан (snake_case бағандар; admin_uid = PK).
  factory StoreModel.fromMap(Map<String, dynamic> m) {
    DateTime dt(dynamic v) =>
        v is String ? (DateTime.tryParse(v) ?? DateTime.now()) : DateTime.now();
    return StoreModel(
      adminUid: m['admin_uid'] as String? ?? '',
      storeName: m['store_name'] as String? ?? '',
      storeSlug: m['store_slug'] as String? ?? '',
      logoUrl: m['logo_url'] as String? ?? '',
      city: m['city'] as String? ?? '',
      phone: m['phone'] as String? ?? '',
      description: m['description'] as String? ?? '',
      address: m['address'] as String? ?? '',
      visibleWarehouseIds:
          (m['visible_warehouse_ids'] as List?)?.map((e) => e.toString()).toList() ??
              [],
      isPublished: m['is_published'] as bool? ?? false,
      createdAt: dt(m['created_at']),
      updatedAt: dt(m['updated_at']),
      deliveryFeeCity: (m['delivery_fee_city'] as num?)?.toDouble() ?? 1500,
      deliveryFreeThreshold:
          (m['delivery_free_threshold'] as num?)?.toDouble() ?? 0,
      paymentCardNumber: m['payment_card_number'] as String? ?? '',
      paymentCardHolder: m['payment_card_holder'] as String? ?? '',
      paymentBank: m['payment_bank'] as String? ?? '',
      ownerName: m['owner_name'] as String? ?? '',
      ownerIin: m['owner_iin'] as String? ?? '',
      category: m['category'] as String? ?? '',
      status: m['status'] as String? ?? 'active',
      blockReason: m['block_reason'] as String? ?? '',
      blockedAt: m['blocked_at'] is String
          ? DateTime.tryParse(m['blocked_at'] as String)
          : null,
      blockedBy: m['blocked_by'] as String? ?? '',
    );
  }

  /// Supabase жазу үшін (snake_case; admin_uid upsert кезінде сервисте қосылады).
  Map<String, dynamic> toMap() => {
        'store_name': storeName,
        'store_slug': storeSlug,
        'logo_url': logoUrl,
        'city': city,
        'phone': phone,
        'description': description,
        'address': address,
        'visible_warehouse_ids': visibleWarehouseIds,
        'is_published': isPublished,
        'delivery_fee_city': deliveryFeeCity,
        'delivery_free_threshold': deliveryFreeThreshold,
        'payment_card_number': paymentCardNumber,
        'payment_card_holder': paymentCardHolder,
        'payment_bank': paymentBank,
        'owner_name': ownerName,
        'owner_iin': ownerIin,
        'category': category,
        'status': status,
        'block_reason': blockReason,
        'blocked_at': blockedAt?.toIso8601String(),
        'blocked_by': blockedBy,
        'updated_at': DateTime.now().toIso8601String(),
      };

  StoreModel copyWith({
    String? adminUid,
    String? storeName,
    String? storeSlug,
    String? logoUrl,
    String? city,
    String? phone,
    String? description,
    String? address,
    List<String>? visibleWarehouseIds,
    bool? isPublished,
    DateTime? createdAt,
    DateTime? updatedAt,
    double? deliveryFeeCity,
    double? deliveryFreeThreshold,
    String? paymentCardNumber,
    String? paymentCardHolder,
    String? paymentBank,
    String? ownerName,
    String? ownerIin,
    String? category,
    String? status,
    String? blockReason,
    DateTime? blockedAt,
    String? blockedBy,
  }) =>
      StoreModel(
        adminUid: adminUid ?? this.adminUid,
        storeName: storeName ?? this.storeName,
        storeSlug: storeSlug ?? this.storeSlug,
        logoUrl: logoUrl ?? this.logoUrl,
        city: city ?? this.city,
        phone: phone ?? this.phone,
        description: description ?? this.description,
        address: address ?? this.address,
        visibleWarehouseIds: visibleWarehouseIds ?? this.visibleWarehouseIds,
        isPublished: isPublished ?? this.isPublished,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        deliveryFeeCity: deliveryFeeCity ?? this.deliveryFeeCity,
        deliveryFreeThreshold:
            deliveryFreeThreshold ?? this.deliveryFreeThreshold,
        paymentCardNumber: paymentCardNumber ?? this.paymentCardNumber,
        paymentCardHolder: paymentCardHolder ?? this.paymentCardHolder,
        paymentBank: paymentBank ?? this.paymentBank,
        ownerName: ownerName ?? this.ownerName,
        ownerIin: ownerIin ?? this.ownerIin,
        category: category ?? this.category,
        status: status ?? this.status,
        blockReason: blockReason ?? this.blockReason,
        blockedAt: blockedAt ?? this.blockedAt,
        blockedBy: blockedBy ?? this.blockedBy,
      );
}
