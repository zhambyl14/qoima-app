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

  /// Каталогтағы плитка суреті (фон түсі жоқ — тек фото). Бос болса
  /// [CategoryIcon] fallback ретінде көрсетіледі.
  final String imageUrl;

  /// Каталогта «кому» (Мужские/Женские/…) деңгейі керек пе. Киім-аяқ киім
  /// категорияларында — иә; тұрмыстық техника, азық-түлік т.б. үшін артық,
  /// сондықтан категориядан бірден тауар түріне өтеді.
  final bool hasAudience;

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
    this.imageUrl = '',
    this.hasAudience = false,
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

const String _kOneSize = 'Один размер';
const List<String> _kOneSizeOnly = [_kOneSize];

/// Тауар категориялары. Тәртібі маңызды — каталогта, сүзгілерде және тауар
/// қосу экрандарында ДӘЛ осы тізім қолданылады (бір ғана шындық көзі).
///
/// ⚠️ `key` мәндері дерекқорда сақталады — барын ӨЗГЕРТПЕҢІЗ, тек жаңасын
/// қосыңыз.
const List<CategoryData> kCategories = [
  // ── Мода ───────────────────────────────────────────────────────────────
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
      hasAudience: true,
      imageUrl:
          'https://images.unsplash.com/photo-1651013691313-81b822df0044?w=500&q=75&auto=format&fit=crop',
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
      hasAudience: true,
      imageUrl:
          'https://images.unsplash.com/photo-1583743814966-8936f5b7be1a?w=500&q=75&auto=format&fit=crop',
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
      hasAudience: true,
      imageUrl:
          'https://images.unsplash.com/photo-1624548140129-74786c5f1279?w=500&q=75&auto=format&fit=crop',
      sizes: ['S', 'M', 'L', 'XL', 'XXL']),
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
      hasAudience: true,
      imageUrl:
          'https://images.unsplash.com/photo-1602293589930-45aad59ba3ab?w=500&q=75&auto=format&fit=crop',
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
      hasAudience: true,
      imageUrl:
          'https://images.unsplash.com/photo-1779398969439-99c38b9df638?w=500&q=75&auto=format&fit=crop',
      sizes: ['XS', 'S', 'M', 'L', 'XL']),
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
      hasAudience: true,
      imageUrl:
          'https://images.unsplash.com/photo-1588850561407-ed78c282e89b?w=500&q=75&auto=format&fit=crop',
      sizes: ['56', '57', '58', '59', '60', 'Univ']),
  CategoryData(
      key: 'underwear',
      nameRu: 'Нижнее бельё',
      nameKk: 'Іш киім',
      shortRu: 'Бельё',
      shortKk: 'Іш киім',
      iconKey: 'underwear',
      tone: 'pink',
      sizeLabelRu: 'Размер',
      sizeLabelKk: 'Өлшем',
      hasAudience: true,
      imageUrl:
          'https://images.unsplash.com/photo-1631024724206-6ccc65ab31bd?w=500&q=75&auto=format&fit=crop',
      sizes: ['XS', 'S', 'M', 'L', 'XL', 'XXL']),
  CategoryData(
      key: 'acc',
      nameRu: 'Аксессуары',
      nameKk: 'Аксессуарлар',
      shortRu: 'Аксесс.',
      shortKk: 'Аксесс.',
      iconKey: 'bag',
      tone: 'brown',
      sizeLabelRu: 'Размер',
      sizeLabelKk: 'Өлшем',
      hasAudience: true,
      imageUrl:
          'https://images.unsplash.com/photo-1598532163257-ae3c6b2524b6?w=500&q=75&auto=format&fit=crop',
      sizes: _kOneSizeOnly),
  CategoryData(
      key: 'jewelry',
      nameRu: 'Украшения',
      nameKk: 'Әшекейлер',
      shortRu: 'Украшения',
      shortKk: 'Әшекейлер',
      iconKey: 'jewelry',
      tone: 'indigo',
      sizeLabelRu: 'Размер',
      sizeLabelKk: 'Өлшем',
      hasAudience: true,
      imageUrl:
          'https://images.unsplash.com/photo-1543294001-f7cd5d7fb516?w=500&q=75&auto=format&fit=crop',
      sizes: ['15', '16', '17', '18', '19', '20', _kOneSize]),
  CategoryData(
      key: 'sport',
      nameRu: 'Спорт и туризм',
      nameKk: 'Спорт және туризм',
      shortRu: 'Спорт',
      shortKk: 'Спорт',
      iconKey: 'sport',
      tone: 'lime',
      sizeLabelRu: 'Размер',
      sizeLabelKk: 'Өлшем',
      hasAudience: true,
      imageUrl:
          'https://images.unsplash.com/photo-1638536532686-d610adfc8e5c?w=500&q=75&auto=format&fit=crop',
      sizes: ['XS', 'S', 'M', 'L', 'XL', 'XXL', _kOneSize]),

  // ── Балалар ────────────────────────────────────────────────────────────
  CategoryData(
      key: 'kids',
      nameRu: 'Детские товары',
      nameKk: 'Балалар тауарлары',
      shortRu: 'Детские',
      shortKk: 'Балалар',
      iconKey: 'kids',
      tone: 'cyan',
      sizeLabelRu: 'Возраст',
      sizeLabelKk: 'Жасы',
      imageUrl:
          'https://images.unsplash.com/photo-1714392512700-4cab9e51710b?w=500&q=75&auto=format&fit=crop',
      sizes: [
        '0-1 год',
        '1-3 года',
        '3-6 лет',
        '6-9 лет',
        '9-12 лет',
        _kOneSize
      ]),
  CategoryData(
      key: 'toys',
      nameRu: 'Игрушки',
      nameKk: 'Ойыншықтар',
      shortRu: 'Игрушки',
      shortKk: 'Ойыншық',
      iconKey: 'toys',
      tone: 'amber',
      sizeLabelRu: 'Размер',
      sizeLabelKk: 'Өлшем',
      imageUrl:
          'https://images.unsplash.com/photo-1596461404969-9ae70f2830c1?w=500&q=75&auto=format&fit=crop',
      sizes: _kOneSizeOnly),

  // ── Красота және денсаулық ─────────────────────────────────────────────
  CategoryData(
      key: 'beauty',
      nameRu: 'Красота и уход',
      nameKk: 'Сұлулық және күтім',
      shortRu: 'Красота',
      shortKk: 'Сұлулық',
      iconKey: 'beauty',
      tone: 'pink',
      sizeLabelRu: 'Объём',
      sizeLabelKk: 'Көлемі',
      imageUrl:
          'https://images.unsplash.com/photo-1596462502278-27bfdc403348?w=500&q=75&auto=format&fit=crop',
      sizes: _kOneSizeOnly),
  CategoryData(
      key: 'pharmacy',
      nameRu: 'Аптека и здоровье',
      nameKk: 'Дәріхана және денсаулық',
      shortRu: 'Аптека',
      shortKk: 'Дәріхана',
      iconKey: 'pharmacy',
      tone: 'red',
      sizeLabelRu: 'Размер',
      sizeLabelKk: 'Өлшем',
      imageUrl:
          'https://images.unsplash.com/photo-1607619056574-7b8d3ee536b2?w=500&q=75&auto=format&fit=crop',
      sizes: _kOneSizeOnly),

  // ── Электроника ────────────────────────────────────────────────────────
  CategoryData(
      key: 'electronics',
      nameRu: 'ТВ, аудио, видео',
      nameKk: 'ТВ, аудио, видео',
      shortRu: 'Электроника',
      shortKk: 'Электроника',
      iconKey: 'electronics',
      tone: 'indigo',
      sizeLabelRu: 'Размер',
      sizeLabelKk: 'Өлшем',
      imageUrl:
          'https://images.unsplash.com/photo-1646861039459-fd9e3aabf3fb?w=500&q=75&auto=format&fit=crop',
      sizes: _kOneSizeOnly),
  CategoryData(
      key: 'phones',
      nameRu: 'Телефоны и гаджеты',
      nameKk: 'Телефондар мен гаджеттер',
      shortRu: 'Телефоны',
      shortKk: 'Телефондар',
      iconKey: 'phone',
      tone: 'slate',
      sizeLabelRu: 'Память',
      sizeLabelKk: 'Жады',
      imageUrl:
          'https://images.unsplash.com/photo-1571053172280-f955a42c3554?w=500&q=75&auto=format&fit=crop',
      sizes: ['64 ГБ', '128 ГБ', '256 ГБ', '512 ГБ', '1 ТБ', _kOneSize]),
  CategoryData(
      key: 'computers',
      nameRu: 'Компьютеры',
      nameKk: 'Компьютерлер',
      shortRu: 'Компьютеры',
      shortKk: 'Компьютер',
      iconKey: 'computer',
      tone: 'blue',
      sizeLabelRu: 'Размер',
      sizeLabelKk: 'Өлшем',
      imageUrl:
          'https://images.unsplash.com/photo-1587831990711-23ca6441447b?w=500&q=75&auto=format&fit=crop',
      sizes: _kOneSizeOnly),
  CategoryData(
      key: 'appliances',
      nameRu: 'Бытовая техника',
      nameKk: 'Тұрмыстық техника',
      shortRu: 'Техника',
      shortKk: 'Техника',
      iconKey: 'appliances',
      tone: 'cyan',
      sizeLabelRu: 'Размер',
      sizeLabelKk: 'Өлшем',
      imageUrl:
          'https://images.unsplash.com/photo-1626806819282-2c1dc01a5e0c?w=500&q=75&auto=format&fit=crop',
      sizes: _kOneSizeOnly),

  // ── Үй ─────────────────────────────────────────────────────────────────
  CategoryData(
      key: 'furniture',
      nameRu: 'Мебель',
      nameKk: 'Жиһаз',
      shortRu: 'Мебель',
      shortKk: 'Жиһаз',
      iconKey: 'furniture',
      tone: 'brown',
      sizeLabelRu: 'Размер',
      sizeLabelKk: 'Өлшем',
      imageUrl:
          'https://images.unsplash.com/photo-1555041469-a586c61ea9bc?w=500&q=75&auto=format&fit=crop',
      sizes: _kOneSizeOnly),
  CategoryData(
      key: 'textile',
      nameRu: 'Домашний текстиль',
      nameKk: 'Үй тоқымасы',
      shortRu: 'Текстиль',
      shortKk: 'Тоқыма',
      iconKey: 'textile',
      tone: 'purple',
      sizeLabelRu: 'Размер',
      sizeLabelKk: 'Өлшем',
      imageUrl:
          'https://images.unsplash.com/photo-1601276174812-63280a55656e?w=500&q=75&auto=format&fit=crop',
      sizes: [
        '1.5-спальный',
        '2-спальный',
        'Евро',
        'Семейный',
        _kOneSize
      ]),
  CategoryData(
      key: 'dishes',
      nameRu: 'Посуда',
      nameKk: 'Ыдыс-аяқ',
      shortRu: 'Посуда',
      shortKk: 'Ыдыс',
      iconKey: 'dishes',
      tone: 'green',
      sizeLabelRu: 'Объём',
      sizeLabelKk: 'Көлемі',
      imageUrl:
          'https://images.unsplash.com/photo-1556910096-6f5e72db6803?w=500&q=75&auto=format&fit=crop',
      sizes: _kOneSizeOnly),
  CategoryData(
      key: 'home',
      nameRu: 'Товары для дома',
      nameKk: 'Үй тауарлары',
      shortRu: 'Для дома',
      shortKk: 'Үйге',
      iconKey: 'home',
      tone: 'amber',
      sizeLabelRu: 'Размер',
      sizeLabelKk: 'Өлшем',
      imageUrl:
          'https://images.unsplash.com/photo-1616046229478-9901c5536a45?w=500&q=75&auto=format&fit=crop',
      sizes: _kOneSizeOnly),
  CategoryData(
      key: 'garden',
      nameRu: 'Дача и сад',
      nameKk: 'Саяжай және бақша',
      shortRu: 'Дача',
      shortKk: 'Саяжай',
      iconKey: 'garden',
      tone: 'lime',
      sizeLabelRu: 'Размер',
      sizeLabelKk: 'Өлшем',
      imageUrl:
          'https://images.unsplash.com/photo-1621460248083-6271cc4437a8?w=500&q=75&auto=format&fit=crop',
      sizes: _kOneSizeOnly),
  CategoryData(
      key: 'tools',
      nameRu: 'Строительство и ремонт',
      nameKk: 'Құрылыс және жөндеу',
      shortRu: 'Ремонт',
      shortKk: 'Жөндеу',
      iconKey: 'tools',
      tone: 'orange',
      sizeLabelRu: 'Размер',
      sizeLabelKk: 'Өлшем',
      imageUrl:
          'https://images.unsplash.com/photo-1645651964715-d200ce0939cc?w=500&q=75&auto=format&fit=crop',
      sizes: _kOneSizeOnly),

  // ── Басқа ──────────────────────────────────────────────────────────────
  CategoryData(
      key: 'auto',
      nameRu: 'Автотовары',
      nameKk: 'Автотауарлар',
      shortRu: 'Авто',
      shortKk: 'Авто',
      iconKey: 'auto',
      tone: 'slate',
      sizeLabelRu: 'Размер',
      sizeLabelKk: 'Өлшем',
      imageUrl:
          'https://images.unsplash.com/photo-1571335746824-742511d49bce?w=500&q=75&auto=format&fit=crop',
      sizes: _kOneSizeOnly),
  CategoryData(
      key: 'pets',
      nameRu: 'Зоотовары',
      nameKk: 'Жануарларға арналған',
      shortRu: 'Зоотовары',
      shortKk: 'Зоотауар',
      iconKey: 'pets',
      tone: 'brown',
      sizeLabelRu: 'Размер',
      sizeLabelKk: 'Өлшем',
      imageUrl:
          'https://images.unsplash.com/photo-1548199973-03cce0bbc87b?w=500&q=75&auto=format&fit=crop',
      sizes: _kOneSizeOnly),
  CategoryData(
      key: 'books',
      nameRu: 'Книги',
      nameKk: 'Кітаптар',
      shortRu: 'Книги',
      shortKk: 'Кітаптар',
      iconKey: 'books',
      tone: 'red',
      sizeLabelRu: 'Размер',
      sizeLabelKk: 'Өлшем',
      imageUrl:
          'https://images.unsplash.com/photo-1610116306796-6fea9f4fae38?w=500&q=75&auto=format&fit=crop',
      sizes: _kOneSizeOnly),
  CategoryData(
      key: 'stationery',
      nameRu: 'Канцелярские товары',
      nameKk: 'Кеңсе тауарлары',
      shortRu: 'Канцелярия',
      shortKk: 'Кеңсе',
      iconKey: 'stationery',
      tone: 'indigo',
      sizeLabelRu: 'Размер',
      sizeLabelKk: 'Өлшем',
      imageUrl:
          'https://images.unsplash.com/photo-1654931800100-2ecf6eee7c64?w=500&q=75&auto=format&fit=crop',
      sizes: _kOneSizeOnly),
  CategoryData(
      key: 'grocery',
      nameRu: 'Продукты питания',
      nameKk: 'Азық-түлік',
      shortRu: 'Продукты',
      shortKk: 'Азық-түлік',
      iconKey: 'grocery',
      tone: 'green',
      sizeLabelRu: 'Вес / объём',
      sizeLabelKk: 'Салмағы / көлемі',
      imageUrl:
          'https://images.unsplash.com/photo-1542838132-92c53300491e?w=500&q=75&auto=format&fit=crop',
      sizes: _kOneSizeOnly),
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
  'teal': CategoryTone(tint: Color(0xFFE0F5F1), deep: Color(0xFF0C6B5E)),
  'red': CategoryTone(tint: Color(0xFFFDE7E7), deep: Color(0xFFC0392B)),
  'indigo': CategoryTone(tint: Color(0xFFE7EAFB), deep: Color(0xFF2F3EA8)),
  'brown': CategoryTone(tint: Color(0xFFF3EAE1), deep: Color(0xFF7A4E24)),
  'lime': CategoryTone(tint: Color(0xFFEDF6DC), deep: Color(0xFF4D7A0B)),
  'cyan': CategoryTone(tint: Color(0xFFE0F3F9), deep: Color(0xFF06657F)),
  'orange': CategoryTone(tint: Color(0xFFFEEDE0), deep: Color(0xFFAA5310)),
};

CategoryTone toneFor(String toneKey) =>
    kCategoryTones[toneKey] ?? kCategoryTones['green']!;

/// Целевые группы (кому предназначен товар).
const List<String> kTargetGroups = ['Мужчинам', 'Женщинам', 'Детям', 'Унисекс'];

/// Кому — канонические значения поля `category` товара (единый список для
/// всех категорий; используется в добавлении и редактировании товара).
const List<String> kProductTargetGroups = [
  'Мужские',
  'Женские',
  'Унисекс',
  'Детские',
];

/// Тип товара (вид/модель) для каждой категории — источник истины для
/// дропдаунов добавления/редактирования И для уровня «тип» в каталоге.
const Map<String, List<String>> kTypesByCategory = {
  // ⚠️ Бар түрлерді ӨШІРМЕҢІЗ/АТЫН ӨЗГЕРТПЕҢІЗ — сақталған тауарлар соған
  // сілтейді. Жаңасын тізім соңына қосыңыз + lang.dart-қа қазақша аудармасы
  // (category_attributes_test тексереді). Суреті міндетті емес (kTypeImages).
  'shoes': [
    'Туфли',
    'Кеды',
    'Кроссовки',
    'Ботинки',
    'Сапоги',
    'Сланцы',
    'Босоножки',
    'Лоферы',
    'Мокасины',
    'Слипоны',
    'Угги',
    'Тапочки',
  ],
  'tshirt': [
    'Футболка',
    'Оверсайз',
    'Поло',
    'Базовая',
    'С принтом',
    'Рубашка',
    'Лонгслив',
    'Майка',
    'Топ',
    'Блузка',
    'Водолазка',
    'Свитер',
  ],
  'outer': [
    'Куртка',
    'Пуховик',
    'Ветровка',
    'Пальто',
    'Худи',
    'Свитшот',
    'Жилет',
    'Парка',
    'Шуба',
    'Дублёнка',
    'Плащ',
    'Бомбер',
  ],
  'pants': [
    'Джинсы',
    'Карго',
    'Шорты',
    'Спортивные',
    'Брюки',
    'Леггинсы',
    'Чиносы',
    'Джоггеры',
    'Палаццо',
    'Комбинезон',
    'Бриджи',
  ],
  'dress': [
    'Платье',
    'Юбка',
    'Сарафан',
    'Костюм',
    'Вечернее платье',
    'Платье-рубашка',
    'Платье-футляр',
    'Юбка-карандаш',
    'Плиссированная юбка',
    'Национальное платье',
  ],
  'caps': [
    'Кепка',
    'Шапка',
    'Панама',
    'Бини',
    'Бандана',
    'Берет',
    'Шляпа',
    'Ушанка',
    'Балаклава',
    'Платок',
    'Тюбетейка',
  ],
  'underwear': [
    'Трусы',
    'Бюстгальтер',
    'Носки',
    'Пижама',
    'Термобельё',
    'Колготки',
    'Боди',
    'Комплект белья',
    'Купальник',
    'Плавки',
    'Халат',
  ],
  'acc': [
    'Ремень',
    'Сумка',
    'Очки',
    'Кошелек',
    'Рюкзак',
    'Перчатки',
    'Шарф',
    'Галстук',
    'Зонт',
    'Клатч',
    'Поясная сумка',
    'Чемодан',
  ],
  'jewelry': [
    'Кольцо',
    'Серьги',
    'Цепочка',
    'Браслет',
    'Кулон',
    'Часы',
    'Подвеска',
    'Колье',
    'Брошь',
    'Комплект',
    'Пирсинг',
    'Запонки',
  ],
  'sport': [
    'Спортивный костюм',
    'Леггинсы',
    'Топ',
    'Шорты',
    'Тренажёр',
    'Велосипед',
    'Палатка',
    'Мяч',
    'Гантели',
    'Коврик для йоги',
    'Самокат',
    'Спальный мешок',
  ],
  'kids': [
    'Коляска',
    'Автокресло',
    'Детская одежда',
    'Подгузники',
    'Детское питание',
    'Кроватка',
    'Детская обувь',
    'Бутылочки и соски',
    'Ходунки',
    'Манеж',
    'Слинг',
    'Конверт для новорождённых',
  ],
  'toys': [
    'Конструктор',
    'Кукла',
    'Мягкая игрушка',
    'Настольная игра',
    'Машинка',
    'Развивающая игрушка',
    'Пазл',
    'Радиоуправляемая игрушка',
    'Игровой набор',
    'Игрушка для малышей',
    'Робот',
    'Набор для творчества',
  ],
  'beauty': [
    'Парфюм',
    'Уход за лицом',
    'Уход за волосами',
    'Декоративная косметика',
    'Маникюр',
    'Приборы для красоты',
    'Уход за телом',
    'Мужской уход',
    'Защита от солнца',
    'Аксессуары для волос',
    'Подарочные наборы',
  ],
  'pharmacy': [
    'Витамины',
    'Медтехника',
    'Первая помощь',
    'Гигиена',
    'Оптика',
    'Лекарства без рецепта',
    'Ортопедия',
    'Тесты',
    'Маски и антисептики',
    'Контактные линзы',
    'Для мамы и малыша',
  ],
  'electronics': [
    'Телевизор',
    'Наушники',
    'Колонка',
    'Игровая приставка',
    'Фотоаппарат',
    'Проектор',
    'Саундбар',
    'Умная колонка',
    'Микрофон',
    'Медиаплеер',
    'Экшн-камера',
    'Видеорегистратор',
  ],
  'phones': [
    'Смартфон',
    'Планшет',
    'Смарт-часы',
    'Чехол',
    'Зарядка',
    'Повербанк',
    'Кнопочный телефон',
    'Защитное стекло',
    'Кабель',
    'Держатель',
    'Фитнес-браслет',
    'Электронная книга',
  ],
  'computers': [
    'Ноутбук',
    'Монитор',
    'Клавиатура',
    'Мышь',
    'Комплектующие',
    'Принтер',
    'Системный блок',
    'Моноблок',
    'Веб-камера',
    'Роутер',
    'Флешка и диски',
    'Сумка для ноутбука',
  ],
  'appliances': [
    'Холодильник',
    'Стиральная машина',
    'Пылесос',
    'Микроволновка',
    'Чайник',
    'Кондиционер',
    'Плита',
    'Посудомоечная машина',
    'Утюг',
    'Блендер',
    'Мультиварка',
    'Обогреватель',
  ],
  'furniture': [
    'Диван',
    'Кровать',
    'Шкаф',
    'Стол',
    'Стул',
    'Полка',
    'Кресло',
    'Тумба',
    'Комод',
    'Стеллаж',
    'Матрас',
    'Детская мебель',
  ],
  'textile': [
    'Постельное бельё',
    'Одеяло',
    'Подушка',
    'Плед',
    'Полотенце',
    'Штора',
    'Покрывало',
    'Наволочка',
    'Наматрасник',
    'Скатерть',
    'Ковёр',
  ],
  'dishes': [
    'Кастрюля',
    'Сковорода',
    'Тарелка',
    'Кружка',
    'Столовые приборы',
    'Контейнер',
    'Набор посуды',
    'Казан',
    'Стакан',
    'Бокал',
    'Чайный сервиз',
    'Поднос',
  ],
  'home': [
    'Хранение',
    'Освещение',
    'Декор',
    'Для уборки',
    'Ванная',
    'Кухня',
    'Зеркало',
    'Настенные часы',
    'Вазы и цветы',
    'Бытовая химия',
    'Ароматы для дома',
    'Сушилка для белья',
  ],
  'garden': [
    'Садовый инвентарь',
    'Мангал',
    'Бассейн',
    'Мебель для дачи',
    'Семена',
    'Теплица',
    'Удобрения',
    'Полив',
    'Садовая техника',
    'Горшки и кашпо',
    'Растения',
  ],
  'tools': [
    'Электроинструмент',
    'Ручной инструмент',
    'Крепёж',
    'Отделка',
    'Сантехника',
    'Электрика',
    'Измерительный инструмент',
    'Лакокрасочные материалы',
    'Двери и окна',
    'Средства защиты',
    'Сварка',
    'Лестницы и стремянки',
  ],
  'auto': [
    'Шины',
    'Диски',
    'Масла',
    'Автохимия',
    'Автозапчасти',
    'Аксессуары для авто',
    'Аккумуляторы',
    'Дворники',
    'Фильтры',
    'Коврики',
    'Автоэлектроника',
    'Инструменты для авто',
  ],
  'pets': [
    'Корм',
    'Игрушки для питомцев',
    'Лежанка',
    'Переноска',
    'Аквариум',
    'Уход',
    'Лакомства',
    'Наполнитель',
    'Ошейник и поводок',
    'Миски',
    'Одежда для питомцев',
    'Ветаптека',
  ],
  'books': [
    'Художественная',
    'Детская',
    'Учебная',
    'Бизнес',
    'Кулинария',
    'Комиксы',
    'Детективы',
    'Фантастика',
    'Психология',
    'История',
    'Поэзия',
    'Религия',
  ],
  'stationery': [
    'Тетради',
    'Ручки',
    'Школьный рюкзак',
    'Папки',
    'Бумага',
    'Для творчества',
    'Карандаши',
    'Маркеры',
    'Пеналы',
    'Ежедневники',
    'Калькуляторы',
    'Клей и ножницы',
  ],
  'grocery': [
    'Бакалея',
    'Напитки',
    'Сладости',
    'Снеки',
    'Консервы',
    'Чай и кофе',
    'Молочные продукты',
    'Мясо и птица',
    'Овощи и фрукты',
    'Хлеб и выпечка',
    'Замороженные продукты',
    'Национальные продукты',
  ],
};

/// Тауар ТҮРІНІҢ (тип товара) каталогтағы суреті — канондық түр атауы →
/// фото URL. Тек [kTypesByCategory]-дегі стандарт түрлерге бар; админ өзі
/// қосқан «Свой вариант» түрлері картада БОЛМАЙДЫ — олар категорияның
/// иконкасымен көрсетіледі ([typeImageUrl] бос жол қайтарады).
const Map<String, String> kTypeImages = {
  'Туфли':
      'https://images.unsplash.com/photo-1668069226492-508742b03147?w=400&q=70&auto=format&fit=crop',
  'Кеды':
      'https://images.unsplash.com/photo-1562105962-2fbaaf107fe3?w=400&q=70&auto=format&fit=crop',
  'Кроссовки':
      'https://images.unsplash.com/photo-1542291026-7eec264c27ff?w=400&q=70&auto=format&fit=crop',
  'Ботинки':
      'https://images.unsplash.com/photo-1605733160314-4fc7dac4bb16?w=400&q=70&auto=format&fit=crop',
  'Сапоги':
      'https://images.unsplash.com/photo-1605812860427-4024433a70fd?w=400&q=70&auto=format&fit=crop',
  'Сланцы':
      'https://images.unsplash.com/photo-1692536631218-ce4264088abe?w=400&q=70&auto=format&fit=crop',
  'Босоножки':
      'https://images.unsplash.com/photo-1662132090867-57a37fa1edf8?w=400&q=70&auto=format&fit=crop',
  'Лоферы':
      'https://images.unsplash.com/photo-1616406432452-07bc5938759d?w=400&q=70&auto=format&fit=crop',
  'Футболка':
      'https://images.unsplash.com/photo-1523381294911-8d3cead13475?w=400&q=70&auto=format&fit=crop',
  'Оверсайз':
      'https://images.unsplash.com/photo-1529374255404-311a2a4f1fd9?w=400&q=70&auto=format&fit=crop',
  'Поло':
      'https://images.unsplash.com/photo-1489987707025-afc232f7ea0f?w=400&q=70&auto=format&fit=crop',
  'Базовая':
      'https://images.unsplash.com/photo-1562157873-818bc0726f68?w=400&q=70&auto=format&fit=crop',
  'С принтом':
      'https://images.unsplash.com/photo-1775979654476-89575df179bd?w=400&q=70&auto=format&fit=crop',
  'Рубашка':
      'https://images.unsplash.com/photo-1740711152088-88a009e877bb?w=400&q=70&auto=format&fit=crop',
  'Лонгслив':
      'https://images.unsplash.com/photo-1620799140408-edc6dcb6d633?w=400&q=70&auto=format&fit=crop',
  'Куртка':
      'https://images.unsplash.com/photo-1624548140129-74786c5f1279?w=400&q=70&auto=format&fit=crop',
  'Пуховик':
      'https://images.unsplash.com/photo-1706765779494-2705542ebe74?w=400&q=70&auto=format&fit=crop',
  'Ветровка':
      'https://images.unsplash.com/photo-1611308725032-74f0a551d018?w=400&q=70&auto=format&fit=crop',
  'Пальто':
      'https://images.unsplash.com/photo-1539533113208-f6df8cc8b543?w=400&q=70&auto=format&fit=crop',
  'Худи':
      'https://images.unsplash.com/photo-1620799140188-3b2a02fd9a77?w=400&q=70&auto=format&fit=crop',
  'Свитшот':
      'https://images.unsplash.com/photo-1618354691551-44de113f0164?w=400&q=70&auto=format&fit=crop',
  'Жилет':
      'https://images.unsplash.com/photo-1713881917939-b558c8f50ccd?w=400&q=70&auto=format&fit=crop',
  'Джинсы':
      'https://images.unsplash.com/photo-1714729382668-7bc3bb261662?w=400&q=70&auto=format&fit=crop',
  'Карго':
      'https://images.unsplash.com/photo-1548883354-7622d03aca27?w=400&q=70&auto=format&fit=crop',
  'Шорты':
      'https://images.unsplash.com/photo-1591195853828-11db59a44f6b?w=400&q=70&auto=format&fit=crop',
  'Спортивные':
      'https://images.unsplash.com/photo-1650461970708-7bf32499516d?w=400&q=70&auto=format&fit=crop',
  'Брюки':
      'https://images.unsplash.com/photo-1624378439575-d8705ad7ae80?w=400&q=70&auto=format&fit=crop',
  'Леггинсы':
      'https://images.unsplash.com/photo-1606902965551-dce093cda6e7?w=400&q=70&auto=format&fit=crop',
  'Платье':
      'https://images.unsplash.com/photo-1533659828870-95ee305cee3e?w=400&q=70&auto=format&fit=crop',
  'Юбка':
      'https://images.unsplash.com/photo-1509182469511-7f0b50bfa63e?w=400&q=70&auto=format&fit=crop',
  'Сарафан':
      'https://images.unsplash.com/photo-1528813569347-f16dd076e347?w=400&q=70&auto=format&fit=crop',
  'Костюм':
      'https://images.unsplash.com/photo-1571513722275-4b41940f54b8?w=400&q=70&auto=format&fit=crop',
  'Кепка':
      'https://images.unsplash.com/photo-1588850561407-ed78c282e89b?w=400&q=70&auto=format&fit=crop',
  'Шапка':
      'https://images.unsplash.com/photo-1576871337632-b9aef4c17ab9?w=400&q=70&auto=format&fit=crop',
  'Панама':
      'https://images.unsplash.com/photo-1648422204972-4278784a9863?w=400&q=70&auto=format&fit=crop',
  'Бини':
      'https://images.unsplash.com/photo-1633964124833-f4f3928c55bb?w=400&q=70&auto=format&fit=crop',
  'Бандана':
      'https://images.unsplash.com/photo-1521292990768-4e3e7ea81810?w=400&q=70&auto=format&fit=crop',
  'Трусы':
      'https://images.unsplash.com/photo-1633699124189-17c808027f4a?w=400&q=70&auto=format&fit=crop',
  'Носки':
      'https://images.unsplash.com/photo-1631024724206-6ccc65ab31bd?w=400&q=70&auto=format&fit=crop',
  'Пижама':
      'https://images.unsplash.com/photo-1681157819947-5faaa3d8388a?w=400&q=70&auto=format&fit=crop',
  'Термобельё':
      'https://images.unsplash.com/photo-1717127412108-ed8a5d68338f?w=400&q=70&auto=format&fit=crop',
  'Колготки':
      'https://images.unsplash.com/photo-1705532301641-f0d542cd6c99?w=400&q=70&auto=format&fit=crop',
  'Ремень':
      'https://images.unsplash.com/photo-1664286074176-5206ee5dc878?w=400&q=70&auto=format&fit=crop',
  'Сумка':
      'https://images.unsplash.com/photo-1598532163257-ae3c6b2524b6?w=400&q=70&auto=format&fit=crop',
  'Очки':
      'https://images.unsplash.com/photo-1511499767150-a48a237f0083?w=400&q=70&auto=format&fit=crop',
  'Кошелек':
      'https://images.unsplash.com/photo-1627123424574-724758594e93?w=400&q=70&auto=format&fit=crop',
  'Рюкзак':
      'https://images.unsplash.com/photo-1553062407-98eeb64c6a62?w=400&q=70&auto=format&fit=crop',
  'Перчатки':
      'https://images.unsplash.com/photo-1515273283790-38b8a1dc851e?w=400&q=70&auto=format&fit=crop',
  'Шарф':
      'https://images.unsplash.com/photo-1609803384069-19f3e5a70e75?w=400&q=70&auto=format&fit=crop',
  'Кольцо':
      'https://images.unsplash.com/photo-1543294001-f7cd5d7fb516?w=400&q=70&auto=format&fit=crop',
  'Серьги':
      'https://images.unsplash.com/photo-1617038220319-276d3cfab638?w=400&q=70&auto=format&fit=crop',
  'Цепочка':
      'https://images.unsplash.com/photo-1601121141461-9d6647bca1ed?w=400&q=70&auto=format&fit=crop',
  'Браслет':
      'https://images.unsplash.com/photo-1633810543462-77c4a3b13f07?w=400&q=70&auto=format&fit=crop',
  'Кулон':
      'https://images.unsplash.com/photo-1589128777073-263566ae5e4d?w=400&q=70&auto=format&fit=crop',
  'Часы':
      'https://images.unsplash.com/photo-1523170335258-f5ed11844a49?w=400&q=70&auto=format&fit=crop',
  'Спортивный костюм':
      'https://images.unsplash.com/photo-1540254597053-3901b858d40f?w=400&q=70&auto=format&fit=crop',
  'Топ':
      'https://images.unsplash.com/photo-1611601679655-7c8bc197f0c6?w=400&q=70&auto=format&fit=crop',
  'Тренажёр':
      'https://images.unsplash.com/photo-1534438327276-14e5300c3a48?w=400&q=70&auto=format&fit=crop',
  'Велосипед':
      'https://images.unsplash.com/photo-1485965120184-e220f721d03e?w=400&q=70&auto=format&fit=crop',
  'Палатка':
      'https://images.unsplash.com/photo-1504280390367-361c6d9f38f4?w=400&q=70&auto=format&fit=crop',
  'Мяч':
      'https://images.unsplash.com/photo-1579952363873-27f3bade9f55?w=400&q=70&auto=format&fit=crop',
  'Коляска':
      'https://images.unsplash.com/photo-1714392512700-4cab9e51710b?w=400&q=70&auto=format&fit=crop',
  'Автокресло':
      'https://images.unsplash.com/photo-1619719287848-883c8f26efbc?w=400&q=70&auto=format&fit=crop',
  'Детская одежда':
      'https://images.unsplash.com/photo-1525507119028-ed4c629a60a3?w=400&q=70&auto=format&fit=crop',
  'Подгузники':
      'https://images.unsplash.com/photo-1584839404042-8bc21d240e91?w=400&q=70&auto=format&fit=crop',
  'Детское питание':
      'https://images.unsplash.com/photo-1491013516836-7db643ee125a?w=400&q=70&auto=format&fit=crop',
  'Кроватка':
      'https://images.unsplash.com/photo-1543346242-2b8e41fb91ca?w=400&q=70&auto=format&fit=crop',
  'Конструктор':
      'https://images.unsplash.com/photo-1587654780291-39c9404d746b?w=400&q=70&auto=format&fit=crop',
  'Кукла':
      'https://images.unsplash.com/photo-1612506001235-f0d0892aa11b?w=400&q=70&auto=format&fit=crop',
  'Мягкая игрушка':
      'https://images.unsplash.com/photo-1602734846297-9299fc2d4703?w=400&q=70&auto=format&fit=crop',
  'Настольная игра':
      'https://images.unsplash.com/photo-1629760946220-5693ee4c46ac?w=400&q=70&auto=format&fit=crop',
  'Машинка':
      'https://images.unsplash.com/photo-1581235720704-06d3acfcb36f?w=400&q=70&auto=format&fit=crop',
  'Развивающая игрушка':
      'https://images.unsplash.com/photo-1618842676088-c4d48a6a7c9d?w=400&q=70&auto=format&fit=crop',
  'Парфюм':
      'https://images.unsplash.com/photo-1523293182086-7651a899d37f?w=400&q=70&auto=format&fit=crop',
  'Уход за лицом':
      'https://images.unsplash.com/photo-1580870069867-74c57ee1bb07?w=400&q=70&auto=format&fit=crop',
  'Уход за волосами':
      'https://images.unsplash.com/photo-1564141696939-9eb6e957ccfc?w=400&q=70&auto=format&fit=crop',
  'Декоративная косметика':
      'https://images.unsplash.com/photo-1626895872564-b691b6877b83?w=400&q=70&auto=format&fit=crop',
  'Маникюр':
      'https://images.unsplash.com/photo-1632345031435-8727f6897d53?w=400&q=70&auto=format&fit=crop',
  'Приборы для красоты':
      'https://images.unsplash.com/photo-1727364438136-6edc10ef0a52?w=400&q=70&auto=format&fit=crop',
  'Витамины':
      'https://images.unsplash.com/photo-1707129785947-ddc627a8bab9?w=400&q=70&auto=format&fit=crop',
  'Медтехника':
      'https://images.unsplash.com/photo-1615486511484-92e172cc4fe0?w=400&q=70&auto=format&fit=crop',
  'Первая помощь':
      'https://images.unsplash.com/photo-1624638760852-8ede1666ab07?w=400&q=70&auto=format&fit=crop',
  'Гигиена':
      'https://images.unsplash.com/photo-1583947215259-38e31be8751f?w=400&q=70&auto=format&fit=crop',
  'Оптика':
      'https://images.unsplash.com/photo-1614715838608-dd527c46231d?w=400&q=70&auto=format&fit=crop',
  'Телевизор':
      'https://images.unsplash.com/photo-1567690187548-f07b1d7bf5a9?w=400&q=70&auto=format&fit=crop',
  'Наушники':
      'https://images.unsplash.com/photo-1505740420928-5e560c06d30e?w=400&q=70&auto=format&fit=crop',
  'Колонка':
      'https://images.unsplash.com/photo-1608043152269-423dbba4e7e1?w=400&q=70&auto=format&fit=crop',
  'Игровая приставка':
      'https://images.unsplash.com/photo-1493711662062-fa541adb3fc8?w=400&q=70&auto=format&fit=crop',
  'Фотоаппарат':
      'https://images.unsplash.com/photo-1495745966610-2a67f2297e5e?w=400&q=70&auto=format&fit=crop',
  'Проектор':
      'https://images.unsplash.com/photo-1535016120720-40c646be5580?w=400&q=70&auto=format&fit=crop',
  'Смартфон':
      'https://images.unsplash.com/photo-1693822845595-862bacc31cf9?w=400&q=70&auto=format&fit=crop',
  'Планшет':
      'https://images.unsplash.com/photo-1561154464-82e9adf32764?w=400&q=70&auto=format&fit=crop',
  'Смарт-часы':
      'https://images.unsplash.com/photo-1579586337278-3befd40fd17a?w=400&q=70&auto=format&fit=crop',
  'Чехол':
      'https://images.unsplash.com/photo-1535157412991-2ef801c1748b?w=400&q=70&auto=format&fit=crop',
  'Зарядка':
      'https://images.unsplash.com/photo-1557767382-97b28f5488e7?w=400&q=70&auto=format&fit=crop',
  'Повербанк':
      'https://images.unsplash.com/photo-1566554738544-d962991c3fee?w=400&q=70&auto=format&fit=crop',
  'Ноутбук':
      'https://images.unsplash.com/photo-1525547719571-a2d4ac8945e2?w=400&q=70&auto=format&fit=crop',
  'Монитор':
      'https://images.unsplash.com/photo-1527443224154-c4a3942d3acf?w=400&q=70&auto=format&fit=crop',
  'Клавиатура':
      'https://images.unsplash.com/photo-1618384887929-16ec33fab9ef?w=400&q=70&auto=format&fit=crop',
  'Мышь':
      'https://images.unsplash.com/photo-1615663245857-ac93bb7c39e7?w=400&q=70&auto=format&fit=crop',
  'Комплектующие':
      'https://images.unsplash.com/photo-1660855551740-4474188debdb?w=400&q=70&auto=format&fit=crop',
  'Принтер':
      'https://images.unsplash.com/photo-1612815154858-60aa4c59eaa6?w=400&q=70&auto=format&fit=crop',
  'Холодильник':
      'https://images.unsplash.com/photo-1721613877687-c9099b698faa?w=400&q=70&auto=format&fit=crop',
  'Стиральная машина':
      'https://images.unsplash.com/photo-1626806819282-2c1dc01a5e0c?w=400&q=70&auto=format&fit=crop',
  'Пылесос':
      'https://images.unsplash.com/photo-1686178827149-6d55c72d81df?w=400&q=70&auto=format&fit=crop',
  'Микроволновка':
      'https://images.unsplash.com/photo-1585659722983-3a675dabf23d?w=400&q=70&auto=format&fit=crop',
  'Чайник':
      'https://images.unsplash.com/photo-1643114786355-ff9e52736eab?w=400&q=70&auto=format&fit=crop',
  'Кондиционер':
      'https://images.unsplash.com/photo-1718203862467-c33159fdc504?w=400&q=70&auto=format&fit=crop',
  'Диван':
      'https://images.unsplash.com/photo-1555041469-a586c61ea9bc?w=400&q=70&auto=format&fit=crop',
  'Кровать':
      'https://images.unsplash.com/photo-1635594202056-9ea3b497e5c0?w=400&q=70&auto=format&fit=crop',
  'Шкаф':
      'https://images.unsplash.com/photo-1672137233327-37b0c1049e77?w=400&q=70&auto=format&fit=crop',
  'Стол':
      'https://images.unsplash.com/photo-1611486212355-d276af4581c0?w=400&q=70&auto=format&fit=crop',
  'Стул':
      'https://images.unsplash.com/photo-1592078615290-033ee584e267?w=400&q=70&auto=format&fit=crop',
  'Полка':
      'https://images.unsplash.com/photo-1601027864736-b6121f34797e?w=400&q=70&auto=format&fit=crop',
  'Постельное бельё':
      'https://images.unsplash.com/photo-1601276174812-63280a55656e?w=400&q=70&auto=format&fit=crop',
  'Одеяло':
      'https://images.unsplash.com/photo-1595770972554-a21ab8487c29?w=400&q=70&auto=format&fit=crop',
  'Подушка':
      'https://images.unsplash.com/photo-1629949009765-40fc74c9ec21?w=400&q=70&auto=format&fit=crop',
  'Плед':
      'https://images.unsplash.com/photo-1515852216175-927860d2be80?w=400&q=70&auto=format&fit=crop',
  'Полотенце':
      'https://images.unsplash.com/photo-1523471826770-c437b4636fe6?w=400&q=70&auto=format&fit=crop',
  'Штора':
      'https://images.unsplash.com/photo-1509644851169-2acc08aa25b5?w=400&q=70&auto=format&fit=crop',
  'Кастрюля':
      'https://images.unsplash.com/photo-1518737003272-dac7c4760d5e?w=400&q=70&auto=format&fit=crop',
  'Сковорода':
      'https://images.unsplash.com/photo-1624031000828-dba1b7a3e4ce?w=400&q=70&auto=format&fit=crop',
  'Тарелка':
      'https://images.unsplash.com/photo-1571987530791-58e3e7744d99?w=400&q=70&auto=format&fit=crop',
  'Кружка':
      'https://images.unsplash.com/photo-1610632380989-680fe40816c6?w=400&q=70&auto=format&fit=crop',
  'Столовые приборы':
      'https://images.unsplash.com/photo-1607637508318-d22cfb4299d4?w=400&q=70&auto=format&fit=crop',
  'Контейнер':
      'https://images.unsplash.com/photo-1562571708-527276a391ac?w=400&q=70&auto=format&fit=crop',
  'Хранение':
      'https://images.unsplash.com/photo-1659729752087-98d8fef7b50c?w=400&q=70&auto=format&fit=crop',
  'Освещение':
      'https://images.unsplash.com/photo-1517991104123-1d56a6e81ed9?w=400&q=70&auto=format&fit=crop',
  'Декор':
      'https://images.unsplash.com/photo-1616046229478-9901c5536a45?w=400&q=70&auto=format&fit=crop',
  'Для уборки':
      'https://images.unsplash.com/photo-1563453392212-326f5e854473?w=400&q=70&auto=format&fit=crop',
  'Ванная':
      'https://images.unsplash.com/photo-1576698483491-8c43f0862543?w=400&q=70&auto=format&fit=crop',
  'Кухня':
      'https://images.unsplash.com/photo-1600489000022-c2086d79f9d4?w=400&q=70&auto=format&fit=crop',
  'Садовый инвентарь':
      'https://images.unsplash.com/photo-1621460248083-6271cc4437a8?w=400&q=70&auto=format&fit=crop',
  'Мангал':
      'https://images.unsplash.com/photo-1534177616072-ef7dc120449d?w=400&q=70&auto=format&fit=crop',
  'Бассейн':
      'https://images.unsplash.com/photo-1562844275-857f6e7c429e?w=400&q=70&auto=format&fit=crop',
  'Мебель для дачи':
      'https://images.unsplash.com/photo-1601654253194-260e0b6984f9?w=400&q=70&auto=format&fit=crop',
  'Семена':
      'https://images.unsplash.com/photo-1611843467160-25afb8df1074?w=400&q=70&auto=format&fit=crop',
  'Теплица':
      'https://images.unsplash.com/photo-1524486361537-8ad15938e1a3?w=400&q=70&auto=format&fit=crop',
  'Электроинструмент':
      'https://images.unsplash.com/photo-1645651964715-d200ce0939cc?w=400&q=70&auto=format&fit=crop',
  'Ручной инструмент':
      'https://images.unsplash.com/photo-1581783898377-1c85bf937427?w=400&q=70&auto=format&fit=crop',
  'Крепёж':
      'https://images.unsplash.com/photo-1613945831677-383c19ad7721?w=400&q=70&auto=format&fit=crop',
  'Отделка':
      'https://images.unsplash.com/photo-1562259949-e8e7689d7828?w=400&q=70&auto=format&fit=crop',
  'Сантехника':
      'https://images.unsplash.com/photo-1542013936693-884638332954?w=400&q=70&auto=format&fit=crop',
  'Электрика':
      'https://images.unsplash.com/photo-1553873002-785d775854c9?w=400&q=70&auto=format&fit=crop',
  'Шины':
      'https://images.unsplash.com/photo-1571335746824-742511d49bce?w=400&q=70&auto=format&fit=crop',
  'Диски':
      'https://images.unsplash.com/photo-1621712151262-60bd142ba19f?w=400&q=70&auto=format&fit=crop',
  'Масла':
      'https://images.unsplash.com/photo-1487754180451-c456f719a1fc?w=400&q=70&auto=format&fit=crop',
  'Автохимия':
      'https://images.unsplash.com/photo-1520340356584-f9917d1eea6f?w=400&q=70&auto=format&fit=crop',
  'Автозапчасти':
      'https://images.unsplash.com/photo-1606577924006-27d39b132ae2?w=400&q=70&auto=format&fit=crop',
  'Аксессуары для авто':
      'https://images.unsplash.com/photo-1533630217389-3a5e4dff5683?w=400&q=70&auto=format&fit=crop',
  'Корм':
      'https://images.unsplash.com/photo-1591946559594-8c6d3b7391eb?w=400&q=70&auto=format&fit=crop',
  'Игрушки для питомцев':
      'https://images.unsplash.com/photo-1591946614720-90a587da4a36?w=400&q=70&auto=format&fit=crop',
  'Лежанка':
      'https://images.unsplash.com/photo-1581888227599-779811939961?w=400&q=70&auto=format&fit=crop',
  'Переноска':
      'https://images.unsplash.com/photo-1608060375223-c5ab552bc9a9?w=400&q=70&auto=format&fit=crop',
  'Аквариум':
      'https://images.unsplash.com/photo-1606137029647-71daa7c9c5c8?w=400&q=70&auto=format&fit=crop',
  'Уход':
      'https://images.unsplash.com/photo-1561037404-61cd46aa615b?w=400&q=70&auto=format&fit=crop',
  'Художественная':
      'https://images.unsplash.com/photo-1541963463532-d68292c34b19?w=400&q=70&auto=format&fit=crop',
  'Детская':
      'https://images.unsplash.com/photo-1497633762265-9d179a990aa6?w=400&q=70&auto=format&fit=crop',
  'Учебная':
      'https://images.unsplash.com/photo-1456513080510-7bf3a84b82f8?w=400&q=70&auto=format&fit=crop',
  'Бизнес':
      'https://images.unsplash.com/photo-1512820790803-83ca734da794?w=400&q=70&auto=format&fit=crop',
  'Кулинария':
      'https://images.unsplash.com/photo-1542010589005-d1eacc3918f2?w=400&q=70&auto=format&fit=crop',
  'Комиксы':
      'https://images.unsplash.com/photo-1601645191163-3fc0d5d64e35?w=400&q=70&auto=format&fit=crop',
  'Тетради':
      'https://images.unsplash.com/photo-1612367980327-7454a7276aa7?w=400&q=70&auto=format&fit=crop',
  'Ручки':
      'https://images.unsplash.com/photo-1455390582262-044cdead277a?w=400&q=70&auto=format&fit=crop',
  'Школьный рюкзак':
      'https://images.unsplash.com/photo-1594608661623-aa0bd3a69d98?w=400&q=70&auto=format&fit=crop',
  'Папки':
      'https://images.unsplash.com/photo-1544396821-4dd40b938ad3?w=400&q=70&auto=format&fit=crop',
  'Бумага':
      'https://images.unsplash.com/photo-1771758249853-415175dc29b9?w=400&q=70&auto=format&fit=crop',
  'Для творчества':
      'https://images.unsplash.com/photo-1460661419201-fd4cecdf8a8b?w=400&q=70&auto=format&fit=crop',
  'Бакалея':
      'https://images.unsplash.com/photo-1584680226833-0d680d0a0794?w=400&q=70&auto=format&fit=crop',
  'Напитки':
      'https://images.unsplash.com/photo-1625865019845-7b2c89b8a8a9?w=400&q=70&auto=format&fit=crop',
  'Сладости':
      'https://images.unsplash.com/photo-1632687380457-05a1271e873b?w=400&q=70&auto=format&fit=crop',
  'Снеки':
      'https://images.unsplash.com/photo-1599490659213-e2b9527bd087?w=400&q=70&auto=format&fit=crop',
  'Консервы':
      'https://images.unsplash.com/photo-1626607007733-d09228471d9f?w=400&q=70&auto=format&fit=crop',
  'Чай и кофе':
      'https://images.unsplash.com/photo-1498804103079-a6351b050096?w=400&q=70&auto=format&fit=crop',
};

/// Түрдің суреті (бос жол — сурет жоқ, иконка fallback қолданылсын).
String typeImageUrl(String type) => kTypeImages[type.trim()] ?? '';

/// Сезонность товара — канонические значения поля `season` (необязательное).
const List<String> kSeasons = ['Лето', 'Зима', 'Осень', 'Весна'];

/// Материалы для каждой категории.
const Map<String, List<String>> kMaterialsByCategory = {
  'shoes': ['Кожа', 'Экокожа', 'Замша', 'Текстиль', 'Резина', 'Синтетика'],
  'tshirt': ['Хлопок', 'Полиэстер', 'Трикотаж', 'Вискоза', 'Лён', 'Синтетика'],
  'outer': ['Нейлон', 'Полиэстер', 'Пух', 'Шерсть', 'Мембрана', 'Синтетика'],
  'pants': ['Хлопок', 'Деним', 'Полиэстер', 'Лён', 'Велюр', 'Синтетика'],
  'dress': ['Хлопок', 'Шёлк', 'Трикотаж', 'Атлас', 'Вискоза', 'Синтетика'],
  'caps': ['Шерсть', 'Хлопок', 'Акрил', 'Вязка', 'Фетр'],
  'underwear': ['Хлопок', 'Полиэстер', 'Кружево', 'Микрофибра', 'Бамбук', 'Синтетика'],
  'acc': ['Кожа', 'Экокожа', 'Текстиль', 'Металл', 'Пластик'],
  'jewelry': ['Золото', 'Серебро', 'Сталь', 'Бижутерия', 'Металл'],
  'sport': ['Полиэстер', 'Спандекс', 'Сетка', 'Нейлон', 'Синтетика'],
  'kids': ['Пластик', 'Текстиль', 'Дерево', 'Металл', 'Силикон'],
  'toys': ['Пластик', 'Дерево', 'Плюш', 'Металл', 'Резина'],
  'beauty': ['Стекло', 'Пластик', 'Металл'],
  'pharmacy': ['Пластик', 'Стекло', 'Текстиль', 'Металл'],
  'electronics': ['Пластик', 'Металл', 'Стекло', 'Алюминий'],
  'phones': ['Пластик', 'Металл', 'Стекло', 'Силикон', 'Алюминий'],
  'computers': ['Пластик', 'Металл', 'Алюминий', 'Стекло'],
  'appliances': ['Металл', 'Пластик', 'Стекло', 'Нержавеющая сталь'],
  'furniture': ['Дерево', 'ЛДСП', 'МДФ', 'Металл', 'Стекло', 'Ткань'],
  'textile': ['Хлопок', 'Бязь', 'Сатин', 'Поплин', 'Микрофибра', 'Лён', 'Шерсть'],
  'dishes': ['Нержавеющая сталь', 'Керамика', 'Стекло', 'Чугун', 'Пластик', 'Фарфор'],
  'home': ['Пластик', 'Металл', 'Дерево', 'Стекло', 'Текстиль'],
  'garden': ['Металл', 'Пластик', 'Дерево', 'Резина'],
  'tools': ['Металл', 'Сталь', 'Пластик', 'Дерево'],
  'auto': ['Резина', 'Металл', 'Пластик', 'Алюминий'],
  'pets': ['Пластик', 'Металл', 'Текстиль', 'Дерево'],
  'books': ['Бумага', 'Твёрдый переплёт', 'Мягкий переплёт'],
  'stationery': ['Бумага', 'Пластик', 'Металл', 'Дерево'],
  'grocery': ['Стекло', 'Пластик', 'Бумага', 'Металл'],
};

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
      case 'underwear':
        return Icons.style_rounded;
      case 'bag':
        return Icons.shopping_bag_rounded;
      case 'jewelry':
        return Icons.diamond_rounded;
      case 'sport':
        return Icons.fitness_center_rounded;
      case 'kids':
        return Icons.child_friendly_rounded;
      case 'toys':
        return Icons.toys_rounded;
      case 'beauty':
        return Icons.spa_rounded;
      case 'pharmacy':
        return Icons.medical_services_rounded;
      case 'electronics':
        return Icons.tv_rounded;
      case 'phone':
        return Icons.smartphone_rounded;
      case 'computer':
        return Icons.laptop_mac_rounded;
      case 'appliances':
        return Icons.kitchen_rounded;
      case 'furniture':
        return Icons.chair_rounded;
      case 'textile':
        return Icons.bed_rounded;
      case 'dishes':
        return Icons.restaurant_rounded;
      case 'home':
        return Icons.home_rounded;
      case 'garden':
        return Icons.yard_rounded;
      case 'tools':
        return Icons.handyman_rounded;
      case 'auto':
        return Icons.directions_car_rounded;
      case 'pets':
        return Icons.pets_rounded;
      case 'books':
        return Icons.menu_book_rounded;
      case 'stationery':
        return Icons.edit_rounded;
      case 'grocery':
        return Icons.local_grocery_store_rounded;
      default:
        return Icons.category_rounded;
    }
  }

  @override
  Widget build(BuildContext context) =>
      Icon(iconFor(kind), size: size, color: color);
}
