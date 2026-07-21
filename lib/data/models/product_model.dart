import 'dart:ui' show Color;

/// Модель товара (документ в коллекции "products")
class ProductModel {
  final String id;
  final String name;
  final String brand;
  final String type;
  final String material;
  final String category; // целевая группа / пол (напр. «Мужчинам», «Женские»)
  final String categoryKey; // тип товара v2: shoes|tshirt|outer|... ('' = shoes)
  final String color;
  // Ұсақ айырмашылық белгісі (мыс. «қара табан», «гүлі бар»). Бірдей модель/түс
  // болса да, әр түрлі белгі = БӨЛЕК товар (findMatchingProduct кимлікке қосады —
  // повторный завоз болмайды). Клиент detail-де нұсқа ауыстырғышта көреді.
  final String variantNote;
  // HSV палитрадан таңдалған ерекше түстің нақты HEX коды ('#RRGGBB'). Бос болса —
  // color аты бойынша colorOptions-тан есептеледі.
  final String customColorHex;
  final String articul;
  final String status; // "В наличии" | "Продано"
  final List<String> images;
  final String description; // описание товара (необязательно)
  final String country; // страна производства (необязательно)
  final String season; // Лето|Зима|Осень|Весна ('' = не указан)
  // Денормализацияланған рейтинг (product_reviews триггері жаңартады).
  // toMap-қа ӘДЕЙІ кірмейді — админ тауарды өңдегенде нөлденіп кетпеуі үшін.
  final double ratingAvg;
  final int ratingCount;
  // true = онлайн-витринадан жасырылған (қоймада қалады). toMap-қа КІРМЕЙДІ —
  // тек setStorefrontHidden арқылы бөлек жаңартылады (өңдеуде жаңылмас үшін).
  final bool storefrontHidden;

  const ProductModel({
    required this.id,
    required this.name,
    required this.brand,
    required this.type,
    required this.material,
    required this.category,
    this.categoryKey = '',
    required this.color,
    this.variantNote = '',
    this.customColorHex = '',
    required this.articul,
    required this.status,
    required this.images,
    this.description = '',
    this.country = '',
    this.season = '',
    this.ratingAvg = 0,
    this.ratingCount = 0,
    this.storefrontHidden = false,
  });

  /// Ключ категории с учётом обратной совместимости: товары, заведённые до
  /// мульти-категорийного каталога, не имеют `categoryKey` → это обувь.
  String get effectiveCategoryKey =>
      categoryKey.isEmpty ? 'shoes' : categoryKey;

  static const String statusInStock = 'В наличии';
  static const String statusSold = 'Продано';

  static const List<String> types = [
    'Туфли',
    'Кеды',
    'Кроссовки',
    'Ботинки',
    'Сланцы',
    'Босоножки',
  ];

  static const List<String> categories = [
    'Мужские',
    'Женские',
    'Унисекс',
    'Детские (мальчики)',
    'Детские (девочки)',
  ];

  static const List<Map<String, dynamic>> colorOptions = [
    {'name': 'Черный', 'hex': 0xFF1A1A1A},
    {'name': 'Белый', 'hex': 0xFFF5F5F5},
    {'name': 'Коричневый', 'hex': 0xFF795548},
    {'name': 'Серый', 'hex': 0xFF9E9E9E},
    {'name': 'Бежевый', 'hex': 0xFFD7C4A3},
    {'name': 'Красный', 'hex': 0xFFE53935},
    {'name': 'Зеленый', 'hex': 0xFF43A047},
    {'name': 'Синий', 'hex': 0xFF1E3A8A},
    {'name': 'Желтый', 'hex': 0xFFFDD835},
    {'name': 'Розовый', 'hex': 0xFFEC407A},
    {'name': 'Оранжевый', 'hex': 0xFFFF7043},
    {'name': 'Мульти', 'hex': 0xFFAB47BC},
  ];

  /// Цвет по названию (из [colorOptions]); null, если не найден.
  static Color? colorHex(String colorName) {
    for (final c in colorOptions) {
      if (c['name'] == colorName) {
        final hex = c['hex'] as int?;
        return hex != null ? Color(hex) : null;
      }
    }
    return null;
  }

  /// Нақты түс: custom HEX болса — соны, әйтпесе аты бойынша палитрадан.
  Color? get effectiveColor {
    final h = customColorHex.trim().replaceFirst('#', '');
    if (h.isNotEmpty) {
      final full = h.length == 6 ? 'FF$h' : h;
      final v = int.tryParse(full, radix: 16);
      if (v != null) return Color(v);
    }
    return colorHex(color);
  }

  factory ProductModel.fromJson(Map<String, dynamic> json, {String? docId}) {
    return ProductModel(
      id: docId ?? json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      brand: json['brand'] as String? ?? '',
      type: json['type'] as String? ?? '',
      material: json['material'] as String? ?? '',
      category: json['category'] as String? ?? '',
      categoryKey: json['categoryKey'] as String? ?? '',
      color: json['color'] as String? ?? '',
      variantNote: json['variantNote'] as String? ?? '',
      customColorHex: json['customColorHex'] as String? ?? '',
      articul: json['articul'] as String? ?? '',
      status: json['status'] as String? ?? statusInStock,
      images: List<String>.from(json['images'] as List? ?? []),
      description: json['description'] as String? ?? '',
      country: json['country'] as String? ?? '',
      season: json['season'] as String? ?? '',
    );
  }

  /// Supabase `products` жолынан (snake_case бағандар).
  factory ProductModel.fromMap(Map<String, dynamic> m) => ProductModel(
        id: m['id'] as String? ?? '',
        name: m['name'] as String? ?? '',
        brand: m['brand'] as String? ?? '',
        type: m['type'] as String? ?? '',
        material: m['material'] as String? ?? '',
        category: m['category'] as String? ?? '',
        categoryKey: m['category_key'] as String? ?? '',
        color: m['color'] as String? ?? '',
        variantNote: m['variant_note'] as String? ?? '',
        customColorHex: m['color_hex'] as String? ?? '',
        articul: m['articul'] as String? ?? '',
        status: m['status'] as String? ?? statusInStock,
        images: (m['images'] as List?)?.map((e) => e.toString()).toList() ?? [],
        description: m['description'] as String? ?? '',
        country: m['country'] as String? ?? '',
        season: m['season'] as String? ?? '',
        ratingAvg: (m['rating_avg'] as num?)?.toDouble() ?? 0,
        ratingCount: (m['rating_count'] as num?)?.toInt() ?? 0,
        storefrontHidden: m['storefront_hidden'] as bool? ?? false,
      );

  /// Supabase жазу үшін (snake_case; id/owner_uid сервисте қосылады;
  /// rating_avg/rating_count ӘДЕЙІ ЖОҚ — оларды тек DB триггері жазады).
  Map<String, dynamic> toMap() => {
        'name': name,
        'brand': brand,
        'type': type,
        'material': material,
        'category': category,
        'category_key': categoryKey,
        'color': color,
        'variant_note': variantNote,
        'color_hex': customColorHex,
        'articul': articul,
        'status': status,
        'images': images,
        'description': description,
        'country': country,
        'season': season,
      };

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'brand': brand,
        'type': type,
        'material': material,
        'category': category,
        'categoryKey': categoryKey,
        'color': color,
        'variantNote': variantNote,
        'customColorHex': customColorHex,
        'articul': articul,
        'status': status,
        'images': images,
        'description': description,
        'country': country,
        'season': season,
      };

  ProductModel copyWith({
    String? id,
    String? name,
    String? brand,
    String? type,
    String? material,
    String? category,
    String? categoryKey,
    String? color,
    String? variantNote,
    String? customColorHex,
    String? articul,
    String? status,
    List<String>? images,
    String? description,
    String? country,
    String? season,
    double? ratingAvg,
    int? ratingCount,
    bool? storefrontHidden,
  }) {
    return ProductModel(
      id: id ?? this.id,
      name: name ?? this.name,
      brand: brand ?? this.brand,
      type: type ?? this.type,
      material: material ?? this.material,
      category: category ?? this.category,
      categoryKey: categoryKey ?? this.categoryKey,
      color: color ?? this.color,
      variantNote: variantNote ?? this.variantNote,
      customColorHex: customColorHex ?? this.customColorHex,
      articul: articul ?? this.articul,
      status: status ?? this.status,
      images: images ?? this.images,
      description: description ?? this.description,
      country: country ?? this.country,
      season: season ?? this.season,
      ratingAvg: ratingAvg ?? this.ratingAvg,
      ratingCount: ratingCount ?? this.ratingCount,
      storefrontHidden: storefrontHidden ?? this.storefrontHidden,
    );
  }

  @override
  String toString() =>
      'ProductModel(id: $id, name: $name, color: $color, articul: $articul, status: $status)';
}
