import 'package:cloud_firestore/cloud_firestore.dart';

/// Модель товара (документ в коллекции "products")
class ProductModel {
  final String id;
  final String name;
  final String brand;
  final String type;
  final String material;
  final String category;
  final String color;
  final String articul;
  final String status; // "В наличии" | "Продано"
  final List<String> images;

  const ProductModel({
    required this.id,
    required this.name,
    required this.brand,
    required this.type,
    required this.material,
    required this.category,
    required this.color,
    required this.articul,
    required this.status,
    required this.images,
  });

  static const String statusInStock = 'В наличии';
  static const String statusSold    = 'Продано';

  static const List<String> types = [
    'Туфли', 'Кеды', 'Кроссовки', 'Ботинки', 'Сланцы', 'Босоножки',
  ];

  static const List<String> categories = [
    'Мужские', 'Женские', 'Унисекс', 'Детские (мальчики)', 'Детские (девочки)',
  ];

  static const List<Map<String, dynamic>> colorOptions = [
    {'name': 'Черный',     'hex': 0xFF1A1A1A},
    {'name': 'Белый',      'hex': 0xFFF5F5F5},
    {'name': 'Коричневый', 'hex': 0xFF795548},
    {'name': 'Серый',      'hex': 0xFF9E9E9E},
    {'name': 'Бежевый',    'hex': 0xFFD7C4A3},
    {'name': 'Красный',    'hex': 0xFFE53935},
    {'name': 'Зеленый',    'hex': 0xFF43A047},
    {'name': 'Синий',      'hex': 0xFF1E3A8A},
    {'name': 'Желтый',     'hex': 0xFFFDD835},
    {'name': 'Розовый',    'hex': 0xFFEC407A},
    {'name': 'Оранжевый',  'hex': 0xFFFF7043},
    {'name': 'Мульти',     'hex': 0xFFAB47BC},
  ];

  factory ProductModel.fromJson(Map<String, dynamic> json, {String? docId}) {
    return ProductModel(
      id:       docId ?? json['id'] as String? ?? '',
      name:     json['name']     as String? ?? '',
      brand:    json['brand']    as String? ?? '',
      type:     json['type']     as String? ?? '',
      material: json['material'] as String? ?? '',
      category: json['category'] as String? ?? '',
      color:    json['color']    as String? ?? '',
      articul:  json['articul']  as String? ?? '',
      status:   json['status']   as String? ?? statusInStock,
      images:   List<String>.from(json['images'] as List? ?? []),
    );
  }

  factory ProductModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ProductModel.fromJson(data, docId: doc.id);
  }

  Map<String, dynamic> toJson() => {
    'id':       id,
    'name':     name,
    'brand':    brand,
    'type':     type,
    'material': material,
    'category': category,
    'color':    color,
    'articul':  articul,
    'status':   status,
    'images':   images,
  };

  ProductModel copyWith({
    String? id, String? name, String? brand, String? type,
    String? material, String? category, String? color,
    String? articul, String? status, List<String>? images,
  }) {
    return ProductModel(
      id:       id       ?? this.id,
      name:     name     ?? this.name,
      brand:    brand    ?? this.brand,
      type:     type     ?? this.type,
      material: material ?? this.material,
      category: category ?? this.category,
      color:    color    ?? this.color,
      articul:  articul  ?? this.articul,
      status:   status   ?? this.status,
      images:   images   ?? this.images,
    );
  }

  @override
  String toString() =>
      'ProductModel(id: $id, name: $name, color: $color, articul: $articul, status: $status)';
}