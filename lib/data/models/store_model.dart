import 'package:cloud_firestore/cloud_firestore.dart';

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
  });

  static String generateSlug(String name) => name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9а-яёА-ЯЁ\s]'), '')
      .trim()
      .replaceAll(RegExp(r'\s+'), '-');

  factory StoreModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return StoreModel(
      adminUid: doc.id,
      storeName: d['storeName'] as String? ?? '',
      storeSlug: d['storeSlug'] as String? ?? '',
      logoUrl: d['logoUrl'] as String? ?? '',
      city: d['city'] as String? ?? '',
      phone: d['phone'] as String? ?? '',
      description: d['description'] as String? ?? '',
      address: d['address'] as String? ?? '',
      visibleWarehouseIds: (d['visibleWarehouseIds'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      isPublished: d['isPublished'] as bool? ?? false,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (d['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      deliveryFeeCity: (d['deliveryFeeCity'] as num?)?.toDouble() ?? 1500.0,
      deliveryFreeThreshold:
          (d['deliveryFreeThreshold'] as num?)?.toDouble() ?? 0.0,
      paymentCardNumber: d['paymentCardNumber'] as String? ?? '',
      paymentCardHolder: d['paymentCardHolder'] as String? ?? '',
      paymentBank: d['paymentBank'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'adminUid': adminUid,
        'storeName': storeName,
        'storeSlug': storeSlug,
        'logoUrl': logoUrl,
        'city': city,
        'phone': phone,
        'description': description,
        'address': address,
        'visibleWarehouseIds': visibleWarehouseIds,
        'isPublished': isPublished,
        'createdAt': Timestamp.fromDate(createdAt),
        'updatedAt': Timestamp.fromDate(updatedAt),
        'deliveryFeeCity': deliveryFeeCity,
        'deliveryFreeThreshold': deliveryFreeThreshold,
        'paymentCardNumber': paymentCardNumber,
        'paymentCardHolder': paymentCardHolder,
        'paymentBank': paymentBank,
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
      );
}
