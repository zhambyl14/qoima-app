import 'package:cloud_firestore/cloud_firestore.dart';

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

  factory WarehouseModel.fromJson(Map<String, dynamic> json, {String? docId}) {
    DateTime parseDate(dynamic raw) {
      if (raw is Timestamp) return raw.toDate();
      if (raw is DateTime) return raw;
      return DateTime.now();
    }

    return WarehouseModel(
      id: docId ?? json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      address: json['address'] as String?,
      note: json['note'] as String?,
      isMain: json['isMain'] as bool? ?? false,
      createdAt: parseDate(json['createdAt']),
      totalPairs: (json['totalPairs'] as num?)?.toInt() ?? 0,
      totalProducts: (json['totalProducts'] as num?)?.toInt() ?? 0,
    );
  }

  factory WarehouseModel.fromFirestore(DocumentSnapshot doc) =>
      WarehouseModel.fromJson(doc.data() as Map<String, dynamic>,
          docId: doc.id);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (address != null) 'address': address,
        if (note != null) 'note': note,
        'isMain': isMain,
        'createdAt': Timestamp.fromDate(createdAt),
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
