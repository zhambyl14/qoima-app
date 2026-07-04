import 'package:flutter/material.dart';
import '../../core/lang.dart';

/// Категория товара (тип) для мульти-категорийного каталога Qoima v2.
///
/// Существующие «обувные» товары без поля `categoryKey` трактуются как `shoes`
/// (см. [ProductModel.effectiveCategoryKey]) — обратная совместимость.
///
/// Атаулар ru/kk қос нұсқада сақталады; [name]/[short]/[sizeLabel] —
/// ағымдағы тілге сай getter-лер (шақыру орындары өзгеріссіз).
class CategoryData {
  final String key; // 'shoes' | 'tshirt' | 'outer' | ...
  final String nameRu, nameKk; // полное название («Обувь»)
  final String shortRu, shortKk; // короткое («Обувь», «Футболки»)
  final String iconKey; // ключ иконки для CategoryIcon
  final String tone; // ключ тона (см. kCategoryTones)
  final String sizeLabelRu, sizeLabelKk; // подпись поля размера
  final List<String> sizes;

  const CategoryData({
    required this.key,
    required this.nameRu,
    required this.nameKk,
    required this.shortRu,
    required this.shortKk,
    required this.iconKey,
    required this.tone,
    required this.sizeLabelRu,
    required this.sizeLabelKk,
    required this.sizes,
  });

  String get name => tr(nameRu, nameKk);
  String get short => tr(shortRu, shortKk);
  String get sizeLabel => tr(sizeLabelRu, sizeLabelKk);
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
      nameRu: 'Обувь',
      nameKk: 'Аяқ киім',
      shortRu: 'Обувь',
      shortKk: 'Аяқ киім',
      iconKey: 'shoe',
      tone: 'green',
      sizeLabelRu: 'Размер',
      sizeLabelKk: 'Өлшем',
      sizes: ['36', '37', '38', '39', '40', '41', '42', '43', '44', '45']),
  CategoryData(
      key: 'tshirt',
      nameRu: 'Футболки и майки',
      nameKk: 'Футболкалар мен майкалар',
      shortRu: 'Футболки',
      shortKk: 'Футболкалар',
      iconKey: 'tshirt',
      tone: 'blue',
      sizeLabelRu: 'Размер',
      sizeLabelKk: 'Өлшем',
      sizes: ['XS', 'S', 'M', 'L', 'XL', 'XXL']),
  CategoryData(
      key: 'outer',
      nameRu: 'Верхняя одежда',
      nameKk: 'Сырт киім',
      shortRu: 'Куртки',
      shortKk: 'Күртелер',
      iconKey: 'jacket',
      tone: 'purple',
      sizeLabelRu: 'Размер',
      sizeLabelKk: 'Өлшем',
      sizes: ['S', 'M', 'L', 'XL', 'XXL']),
  CategoryData(
      key: 'caps',
      nameRu: 'Головные уборы',
      nameKk: 'Бас киімдер',
      shortRu: 'Головные',
      shortKk: 'Бас киім',
      iconKey: 'cap',
      tone: 'amber',
      sizeLabelRu: 'Обхват',
      sizeLabelKk: 'Айналымы',
      sizes: ['56', '57', '58', '59', '60', 'Univ']),
  CategoryData(
      key: 'pants',
      nameRu: 'Брюки и джинсы',
      nameKk: 'Шалбарлар мен джинсылар',
      shortRu: 'Брюки',
      shortKk: 'Шалбарлар',
      iconKey: 'pants',
      tone: 'slate',
      sizeLabelRu: 'Размер',
      sizeLabelKk: 'Өлшем',
      sizes: ['28', '30', '32', '34', '36', '38']),
  CategoryData(
      key: 'dress',
      nameRu: 'Платья и юбки',
      nameKk: 'Көйлектер мен юбкалар',
      shortRu: 'Платья',
      shortKk: 'Көйлектер',
      iconKey: 'dress',
      tone: 'pink',
      sizeLabelRu: 'Размер',
      sizeLabelKk: 'Өлшем',
      sizes: ['XS', 'S', 'M', 'L', 'XL']),
  CategoryData(
      key: 'acc',
      nameRu: 'Аксессуары',
      nameKk: 'Аксессуарлар',
      shortRu: 'Аксесс.',
      shortKk: 'Аксесс.',
      iconKey: 'bag',
      tone: 'green',
      sizeLabelRu: 'Размер',
      sizeLabelKk: 'Өлшем',
      sizes: ['Один размер']),
  CategoryData(
      key: 'sport',
      nameRu: 'Спорт',
      nameKk: 'Спорт',
      shortRu: 'Спорт',
      shortKk: 'Спорт',
      iconKey: 'sport',
      tone: 'blue',
      sizeLabelRu: 'Размер',
      sizeLabelKk: 'Өлшем',
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
