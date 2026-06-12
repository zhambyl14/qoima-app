import 'package:flutter/material.dart';

/// Категория товара (тип) для мульти-категорийного каталога Qoima v2.
///
/// Существующие «обувные» товары без поля `categoryKey` трактуются как `shoes`
/// (см. [ProductModel.effectiveCategoryKey]) — обратная совместимость.
class CategoryData {
  final String key; // 'shoes' | 'tshirt' | 'outer' | ...
  final String name; // полное название («Обувь»)
  final String short; // короткое («Обувь», «Футболки»)
  final String iconKey; // ключ иконки для CategoryIcon
  final String tone; // ключ тона (см. kCategoryTones)
  final String sizeLabel; // подпись поля размера («Размер», «Обхват»)
  final List<String> sizes;

  const CategoryData({
    required this.key,
    required this.name,
    required this.short,
    required this.iconKey,
    required this.tone,
    required this.sizeLabel,
    required this.sizes,
  });
}

class CategoryTone {
  final Color tint;
  final Color deep;
  const CategoryTone({required this.tint, required this.deep});
}

/// Восемь категорий товаров. Порядок важен — используется в горизонтальных
/// списках и фильтрах.
const List<CategoryData> kCategories = [
  CategoryData(
      key: 'shoes',
      name: 'Обувь',
      short: 'Обувь',
      iconKey: 'shoe',
      tone: 'green',
      sizeLabel: 'Размер',
      sizes: ['36', '37', '38', '39', '40', '41', '42', '43', '44', '45']),
  CategoryData(
      key: 'tshirt',
      name: 'Футболки и майки',
      short: 'Футболки',
      iconKey: 'tshirt',
      tone: 'blue',
      sizeLabel: 'Размер',
      sizes: ['XS', 'S', 'M', 'L', 'XL', 'XXL']),
  CategoryData(
      key: 'outer',
      name: 'Верхняя одежда',
      short: 'Куртки',
      iconKey: 'jacket',
      tone: 'purple',
      sizeLabel: 'Размер',
      sizes: ['S', 'M', 'L', 'XL', 'XXL']),
  CategoryData(
      key: 'caps',
      name: 'Головные уборы',
      short: 'Головные',
      iconKey: 'cap',
      tone: 'amber',
      sizeLabel: 'Обхват',
      sizes: ['56', '57', '58', '59', '60', 'Univ']),
  CategoryData(
      key: 'pants',
      name: 'Брюки и джинсы',
      short: 'Брюки',
      iconKey: 'pants',
      tone: 'slate',
      sizeLabel: 'Размер',
      sizes: ['28', '30', '32', '34', '36', '38']),
  CategoryData(
      key: 'dress',
      name: 'Платья и юбки',
      short: 'Платья',
      iconKey: 'dress',
      tone: 'pink',
      sizeLabel: 'Размер',
      sizes: ['XS', 'S', 'M', 'L', 'XL']),
  CategoryData(
      key: 'acc',
      name: 'Аксессуары',
      short: 'Аксесс.',
      iconKey: 'bag',
      tone: 'green',
      sizeLabel: 'Размер',
      sizes: ['Один размер']),
  CategoryData(
      key: 'sport',
      name: 'Спорт',
      short: 'Спорт',
      iconKey: 'sport',
      tone: 'blue',
      sizeLabel: 'Размер',
      sizes: ['S', 'M', 'L', 'XL']),
];

const String kDefaultCategoryKey = 'shoes';

/// Категория по ключу, либо `shoes` по умолчанию (обратная совместимость).
CategoryData categoryByKey(String? key) {
  for (final c in kCategories) {
    if (c.key == key) return c;
  }
  return kCategories.first; // shoes
}

const Map<String, CategoryTone> kCategoryTones = {
  'green': CategoryTone(tint: Color(0xFFE4F7EE), deep: Color(0xFF00713F)),
  'blue': CategoryTone(tint: Color(0xFFE4EEFE), deep: Color(0xFF1A5BD0)),
  'purple': CategoryTone(tint: Color(0xFFECE7FE), deep: Color(0xFF5A3DD0)),
  'amber': CategoryTone(tint: Color(0xFFFEF3DC), deep: Color(0xFF9A6A06)),
  'pink': CategoryTone(tint: Color(0xFFFDE8EB), deep: Color(0xFFB11A2B)),
  'slate': CategoryTone(tint: Color(0xFFEEF1F0), deep: Color(0xFF3C4D45)),
};

CategoryTone toneFor(String toneKey) =>
    kCategoryTones[toneKey] ?? kCategoryTones['green']!;

/// Целевые группы (кому предназначен товар).
const List<String> kTargetGroups = ['Мужчинам', 'Женщинам', 'Детям', 'Унисекс'];

/// Иконка категории. Material не содержит специализированных значков одежды,
/// поэтому используем наиболее близкие по смыслу.
class CategoryIcon extends StatelessWidget {
  final String kind;
  final double size;
  final Color? color;

  const CategoryIcon({
    super.key,
    required this.kind,
    this.size = 18,
    this.color,
  });

  static IconData iconFor(String kind) {
    switch (kind) {
      case 'shoe':
        return Icons.directions_walk_rounded;
      case 'tshirt':
        return Icons.checkroom_rounded;
      case 'jacket':
        return Icons.dry_cleaning_rounded;
      case 'cap':
        return Icons.sports_baseball_rounded;
      case 'pants':
        return Icons.airline_seat_legroom_extra_rounded;
      case 'dress':
        return Icons.woman_rounded;
      case 'bag':
        return Icons.shopping_bag_rounded;
      case 'sport':
        return Icons.fitness_center_rounded;
      default:
        return Icons.category_rounded;
    }
  }

  @override
  Widget build(BuildContext context) =>
      Icon(iconFor(kind), size: size, color: color);
}
