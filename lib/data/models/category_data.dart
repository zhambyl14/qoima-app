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
          'https://images.unsplash.com/photo-1542291026-7eec264c27ff?w=500&q=75&auto=format&fit=crop',
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
          'https://images.unsplash.com/photo-1496747611176-843222e1e57c?w=500&q=75&auto=format&fit=crop',
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
          'https://images.unsplash.com/photo-1511707171634-5f897ff02aa9?w=500&q=75&auto=format&fit=crop',
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
          'https://images.unsplash.com/photo-1525547719571-a2d4ac8945e2?w=500&q=75&auto=format&fit=crop',
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
  'shoes': [
    'Туфли',
    'Кеды',
    'Кроссовки',
    'Ботинки',
    'Сапоги',
    'Сланцы',
    'Босоножки',
    'Лоферы'
  ],
  'tshirt': [
    'Футболка',
    'Оверсайз',
    'Поло',
    'Базовая',
    'С принтом',
    'Рубашка',
    'Лонгслив'
  ],
  'outer': [
    'Куртка',
    'Пуховик',
    'Ветровка',
    'Пальто',
    'Худи',
    'Свитшот',
    'Жилет'
  ],
  'pants': ['Джинсы', 'Карго', 'Шорты', 'Спортивные', 'Брюки', 'Леггинсы'],
  'dress': ['Платье', 'Юбка', 'Сарафан', 'Костюм'],
  'caps': ['Кепка', 'Шапка', 'Панама', 'Бини', 'Бандана'],
  'underwear': ['Трусы', 'Бюстгальтер', 'Носки', 'Пижама', 'Термобельё', 'Колготки'],
  'acc': ['Ремень', 'Сумка', 'Очки', 'Кошелек', 'Рюкзак', 'Перчатки', 'Шарф'],
  'jewelry': ['Кольцо', 'Серьги', 'Цепочка', 'Браслет', 'Кулон', 'Часы'],
  'sport': [
    'Спортивный костюм',
    'Леггинсы',
    'Топ',
    'Шорты',
    'Тренажёр',
    'Велосипед',
    'Палатка',
    'Мяч'
  ],
  'kids': [
    'Коляска',
    'Автокресло',
    'Детская одежда',
    'Подгузники',
    'Детское питание',
    'Кроватка'
  ],
  'toys': [
    'Конструктор',
    'Кукла',
    'Мягкая игрушка',
    'Настольная игра',
    'Машинка',
    'Развивающая игрушка'
  ],
  'beauty': [
    'Парфюм',
    'Уход за лицом',
    'Уход за волосами',
    'Декоративная косметика',
    'Маникюр',
    'Приборы для красоты'
  ],
  'pharmacy': ['Витамины', 'Медтехника', 'Первая помощь', 'Гигиена', 'Оптика'],
  'electronics': [
    'Телевизор',
    'Наушники',
    'Колонка',
    'Игровая приставка',
    'Фотоаппарат',
    'Проектор'
  ],
  'phones': [
    'Смартфон',
    'Планшет',
    'Смарт-часы',
    'Чехол',
    'Зарядка',
    'Повербанк'
  ],
  'computers': [
    'Ноутбук',
    'Монитор',
    'Клавиатура',
    'Мышь',
    'Комплектующие',
    'Принтер'
  ],
  'appliances': [
    'Холодильник',
    'Стиральная машина',
    'Пылесос',
    'Микроволновка',
    'Чайник',
    'Кондиционер'
  ],
  'furniture': ['Диван', 'Кровать', 'Шкаф', 'Стол', 'Стул', 'Полка'],
  'textile': [
    'Постельное бельё',
    'Одеяло',
    'Подушка',
    'Плед',
    'Полотенце',
    'Штора'
  ],
  'dishes': [
    'Кастрюля',
    'Сковорода',
    'Тарелка',
    'Кружка',
    'Столовые приборы',
    'Контейнер'
  ],
  'home': ['Хранение', 'Освещение', 'Декор', 'Для уборки', 'Ванная', 'Кухня'],
  'garden': [
    'Садовый инвентарь',
    'Мангал',
    'Бассейн',
    'Мебель для дачи',
    'Семена',
    'Теплица'
  ],
  'tools': [
    'Электроинструмент',
    'Ручной инструмент',
    'Крепёж',
    'Отделка',
    'Сантехника',
    'Электрика'
  ],
  'auto': ['Шины', 'Диски', 'Масла', 'Автохимия', 'Автозапчасти', 'Аксессуары для авто'],
  'pets': ['Корм', 'Игрушки для питомцев', 'Лежанка', 'Переноска', 'Аквариум', 'Уход'],
  'books': ['Художественная', 'Детская', 'Учебная', 'Бизнес', 'Кулинария', 'Комиксы'],
  'stationery': ['Тетради', 'Ручки', 'Школьный рюкзак', 'Папки', 'Бумага', 'Для творчества'],
  'grocery': ['Бакалея', 'Напитки', 'Сладости', 'Снеки', 'Консервы', 'Чай и кофе'],
};

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
