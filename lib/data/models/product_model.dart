import 'dart:ui' show Color;

import '../../core/locale_context.dart';
import 'season_utils.dart' as su;

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
  // болса да, әр түрлі белгі = БӨЛЕК товар. Клиент detail-де нұсқа
  // ауыстырғышта көреді.
  final String variantNote;
  // HSV палитрадан таңдалған ерекше түстің нақты HEX коды ('#RRGGBB'). Бос болса —
  // color аты бойынша colorOptions-тан есептеледі.
  final String customColorHex;
  final String articul;
  // ── Жылдам код (0062) — ТЕК дүкен ішіндегілерге ────────────────────────────
  // Админ/сатушы офлайн сатқанда немесе қоймадан іздегенде тауарды атауымен
  // емес, өз қысқа санымен табады («103»). Артикул бұл рөлге жарамайды: ол
  // ГЛОБАЛЬ реттік нөмір (QM-0000123) — ұзын әрі есте қалмайды.
  // Дүкен ішінде БІРЕГЕЙ (DB-де partial unique index). Клиентке ЕШҚАШАН
  // көрсетілмейді және клиенттің іздеу буферіне кірмейді.
  final String quickCode;
  // «Ұқсас сөздер» — клиент тауарды не деп іздесе де табылу үшін
  // (мыс. «сникерс, беговые, спорттық»). Карточкада көрсетілмейді, тек
  // іздеуге қатысады.
  final String keywords;
  final String status; // "В наличии" | "Продано"
  final List<String> images;
  final String description; // описание товара (необязательно), по умолчанию русский
  // Қазақша сипаттама (0083, products.description_kk). Бос = аударма жоқ →
  // [descriptionFor] орысшаға қайтады. Дүкен иесі екі тілді де жаза алады.
  final String descriptionKk;
  final String country; // страна производства (необязательно)
  // Лето|Зима|Осень|Весна ('' = не указан). Бірнешеу болса — канондық мәндер
  // үтірмен: 'Лето,Зима' (season_utils.dart). Оқу/жазу үшін [seasonList],
  // [joinSeasons], [hasSeason] қолданыңыз — жолды қолмен бөлмеңіз.
  final String season;
  // Денормализацияланған рейтинг (product_reviews триггері жаңартады).
  // toMap-қа ӘДЕЙІ кірмейді — админ тауарды өңдегенде нөлденіп кетпеуі үшін.
  final double ratingAvg;
  final int ratingCount;
  // Тауар карточкасын клиент/қонақ ашқан рет саны (increment_product_view RPC
  // жаңартады). toMap-қа КІРМЕЙДІ — тек RPC арқылы өседі.
  final int viewCount;
  // true = онлайн-витринадан жасырылған (қоймада қалады). toMap-қа КІРМЕЙДІ —
  // тек setStorefrontHidden арқылы бөлек жаңартылады (өңдеуде жаңылмас үшін).
  final bool storefrontHidden;
  // ── Қайтарылмайтын тауар (0073) ─────────────────────────────────────────────
  // true = сатып алған соң қайтаруға болмайды. Иесі ТЕК superadmin дүкенге
  // рұқсат берсе ғана қоя алады (stores.allow_non_returnable; DB триггері
  // 'non_returnable_not_allowed' деп бөгейді). Сатылған сәтте orders.items[]
  // ішіне снапшот ретінде жазылады — кейін өзгерсе де ескі тапсырысқа әсер жоқ.
  final bool nonReturnable;
  // Тауарға қатысты қайтару түсіндірмесі (≤300), мыс. «Гигиеналық себеппен
  // қайтарылмайды». Клиент карточкада көреді.
  final String returnNote;

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
    this.quickCode = '',
    this.keywords = '',
    required this.status,
    required this.images,
    this.description = '',
    this.descriptionKk = '',
    this.country = '',
    this.season = '',
    this.ratingAvg = 0,
    this.ratingCount = 0,
    this.viewCount = 0,
    this.storefrontHidden = false,
    this.nonReturnable = false,
    this.returnNote = '',
  });

  /// Ключ категории с учётом обратной совместимости: товары, заведённые до
  /// мульти-категорийного каталога, не имеют `categoryKey` → это обувь.
  String get effectiveCategoryKey =>
      categoryKey.isEmpty ? 'shoes' : categoryKey;

  /// Сипаттама ұзындығының шегі (DB: products_description_kk_len, 0083).
  static const int descriptionMaxLength = 2000;

  /// Берілген тілдегі сипаттама ('kk' | 'ru'). Сол тілде бос болса — екіншісіне
  /// қайтады, ал екеуі де бос болса ''. Белгісіз тіл коды орысша болып есептеледі.
  String descriptionFor(String lang) {
    final primary = lang == 'kk' ? descriptionKk : description;
    final other = lang == 'kk' ? description : descriptionKk;
    return primary.trim().isNotEmpty ? primary : other;
  }

  /// Қосымшаның ағымдағы тіліндегі сипаттама (tr() сияқты LocaleContext-тен).
  String get localizedDescription => descriptionFor(LocaleContext.currentLang);

  /// Екі тілдің кез келгенінде мәтін бар ма.
  bool get hasDescription =>
      description.trim().isNotEmpty || descriptionKk.trim().isNotEmpty;

  /// `description_kk` бағанының жазу бөлігі. DB-де баған (0083) болмаса да
  /// ескі БД жұмысын жалғастыруы үшін БОС болса мүлде жіберілмейді.
  /// ≤ [descriptionMaxLength] қиылады (DB check).
  Map<String, dynamic> get _descriptionKkWrite {
    final t = descriptionKk.trim();
    if (t.isEmpty) return const {};
    return {
      'description_kk': t.length > descriptionMaxLength
          ? t.substring(0, descriptionMaxLength)
          : t
    };
  }

  /// `description_kk` UPDATE-те қалай жазылады: null = тимеу (бос→бос, ескі БД
  /// үшін қауіпсіз), әйтпесе жаңа мән (бос жол = қазақшаны өшіру).
  /// [previous] — өңдеуге дейінгі мән.
  static String? descriptionKkPatch(String previous, String next) {
    final n = next.trim();
    if (n.isEmpty && previous.trim().isEmpty) return null;
    return n.length > descriptionMaxLength
        ? n.substring(0, descriptionMaxLength)
        : n;
  }

  // ── Маусым (көп мәнді) — толығы season_utils.dart ──────────────────────────
  /// Канондық маусымдар тізімі (ескі бір мәнді жазба да → бір элемент).
  List<String> get seasonList => su.parseSeasons(season);

  /// Таңдалған маусымдарды `season` бағанына жазылатын жолға айналдырады.
  static String joinSeasons(Iterable<String> seasons) =>
      su.joinSeasons(seasons);

  /// Тауар осы маусымға жарай ма (көп мәннің кез келгені).
  bool hasSeason(String s) => su.seasonsContain(season, s);

  /// Клиент сүзгісі: [selected] бос болса — бәрі өтеді; әйтпесе тауардың кез
  /// келген маусымы таңдалғанмен сәйкессе.
  bool matchesSeasons(Iterable<String> selected,
          {bool includeUnspecified = false}) =>
      su.seasonsMatchFilter(season, selected,
          includeUnspecified: includeUnspecified);

  /// Көрсетілім: ағымдағы тілде «Жаз, Қыс» (бос болса '').
  String get seasonLabel => su.seasonsLabel(season);

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
      quickCode: json['quickCode'] as String? ?? '',
      keywords: json['keywords'] as String? ?? '',
      status: json['status'] as String? ?? statusInStock,
      images: List<String>.from(json['images'] as List? ?? []),
      description: json['description'] as String? ?? '',
      descriptionKk: json['descriptionKk'] as String? ?? '',
      country: json['country'] as String? ?? '',
      season: json['season'] as String? ?? '',
      nonReturnable: json['nonReturnable'] as bool? ?? false,
      returnNote: json['returnNote'] as String? ?? '',
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
        quickCode: m['quick_code'] as String? ?? '',
        keywords: m['keywords'] as String? ?? '',
        status: m['status'] as String? ?? statusInStock,
        images: (m['images'] as List?)?.map((e) => e.toString()).toList() ?? [],
        description: m['description'] as String? ?? '',
        descriptionKk: m['description_kk'] as String? ?? '',
        country: m['country'] as String? ?? '',
        season: m['season'] as String? ?? '',
        ratingAvg: (m['rating_avg'] as num?)?.toDouble() ?? 0,
        ratingCount: (m['rating_count'] as num?)?.toInt() ?? 0,
        viewCount: (m['view_count'] as num?)?.toInt() ?? 0,
        storefrontHidden: m['storefront_hidden'] as bool? ?? false,
        nonReturnable: m['non_returnable'] as bool? ?? false,
        returnNote: m['return_note'] as String? ?? '',
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
        'quick_code': quickCode.trim(),
        'keywords': keywords.trim(),
        'status': status,
        'images': images,
        'description': description,
        // 0083: бос болса жіберілмейді — ескі БД-да да тауар сақталады.
        ..._descriptionKkWrite,
        'country': country,
        'season': season,
        // 0073: иесінің жазуы. true тек дүкенге рұқсат болса өтеді (триггер).
        // ⚠️ 0073 миграциясы тірі БД-да болмаса, бұл бағандар PostgREST-те
        // «белгісіз баған» қатесін береді — миграция апптан БҰРЫН қолданылады.
        'non_returnable': nonReturnable,
        'return_note': returnNote.trim(),
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
        'quickCode': quickCode,
        'keywords': keywords,
        'status': status,
        'images': images,
        'description': description,
        if (descriptionKk.isNotEmpty) 'descriptionKk': descriptionKk,
        'country': country,
        'season': season,
        if (nonReturnable) 'nonReturnable': true,
        if (returnNote.isNotEmpty) 'returnNote': returnNote,
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
    String? quickCode,
    String? keywords,
    String? status,
    List<String>? images,
    String? description,
    String? descriptionKk,
    String? country,
    String? season,
    double? ratingAvg,
    int? ratingCount,
    int? viewCount,
    bool? storefrontHidden,
    bool? nonReturnable,
    String? returnNote,
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
      quickCode: quickCode ?? this.quickCode,
      keywords: keywords ?? this.keywords,
      status: status ?? this.status,
      images: images ?? this.images,
      description: description ?? this.description,
      descriptionKk: descriptionKk ?? this.descriptionKk,
      country: country ?? this.country,
      season: season ?? this.season,
      ratingAvg: ratingAvg ?? this.ratingAvg,
      ratingCount: ratingCount ?? this.ratingCount,
      viewCount: viewCount ?? this.viewCount,
      storefrontHidden: storefrontHidden ?? this.storefrontHidden,
      nonReturnable: nonReturnable ?? this.nonReturnable,
      returnNote: returnNote ?? this.returnNote,
    );
  }

  @override
  String toString() =>
      'ProductModel(id: $id, name: $name, color: $color, articul: $articul, status: $status)';
}
