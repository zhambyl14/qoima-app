import 'dart:convert';

import '../../../data/models/category_data.dart';
import '../../../data/models/season_utils.dart';

/// Баға өрісінің мәні. "." сияқты сан емес мәтін, бос өріс — null.
double? parsePriceInput(String raw) {
  final v = double.tryParse(raw.trim());
  return (v == null || !v.isFinite) ? null : v;
}

/// Сату бағасы: нақты сан, 0-ден үлкен.
bool isValidSellingPrice(String raw) {
  final v = parsePriceInput(raw);
  return v != null && v > 0;
}

/// Сатып алу бағасы: нақты сан, 0 болуы мүмкін (сыйға алынған тауар).
bool isValidPurchasePrice(String raw) {
  final v = parsePriceInput(raw);
  return v != null && v >= 0;
}

/// Бағаны өріске қайта жазу: артық «.0»-сыз.
String formatPriceInput(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

/// Соңғы таңдау (SharedPreferences): категория/кімге/түр алдын ала таңдалады,
/// бағалар тек басып қоятын чип болады. Бағаны ӘДЕЙІ өздігінен толтырмаймыз:
/// байқамай сақталған қате баға — бір рет басудан әлдеқайда қымбат.
class AddProductMemory {
  static const String prefKey = 'add_product_last_v1';

  final String? category;
  final String? audience;
  final String? type;

  /// categoryKey → {'purchase': сан, 'selling': сан}
  final Map<String, Map<String, double>> prices;

  const AddProductMemory({
    this.category,
    this.audience,
    this.type,
    this.prices = const {},
  });

  /// Бүлінген/ескі JSON қате лақтырмайды — жай бос жады.
  factory AddProductMemory.parse(String? raw) {
    if (raw == null || raw.isEmpty) return const AddProductMemory();
    try {
      final m = jsonDecode(raw) as Map;
      final prices = <String, Map<String, double>>{};
      final rawPrices = m['prices'];
      if (rawPrices is Map) {
        rawPrices.forEach((k, v) {
          if (v is! Map) return;
          final entry = <String, double>{};
          for (final f in const ['purchase', 'selling']) {
            final n = v[f];
            if (n is num && n.isFinite) entry[f] = n.toDouble();
          }
          prices[k.toString()] = entry;
        });
      }
      return AddProductMemory(
        category: m['category'] as String?,
        audience: m['audience'] as String?,
        type: m['type'] as String?,
        prices: prices,
      );
    } catch (_) {
      return const AddProductMemory();
    }
  }

  String encode() => jsonEncode({
        'category': category,
        'audience': audience,
        'type': type,
        'prices': prices,
      });

  /// Сәтті сақтаудан кейінгі жаңа жады (басқа категория бағалары сақталады).
  AddProductMemory remember({
    required String category,
    String? audience,
    String? type,
    double? purchase,
    double? selling,
  }) =>
      AddProductMemory(
        category: category,
        audience: audience,
        type: type,
        prices: {
          ...prices,
          category: {
            ...?prices[category],
            if (purchase != null) 'purchase': purchase,
            if (selling != null) 'selling': selling,
          },
        },
      );

  double? lastPurchase(String? categoryKey) => prices[categoryKey]?['purchase'];
  double? lastSelling(String? categoryKey) => prices[categoryKey]?['selling'];

  /// Каталогта әлі бар мәндер ғана қайтады: category_data.dart өзгерсе ескі
  /// мән форма күйіне түсіп, тізімде жоқ таңдау болып қалмауы керек.
  ({String? category, String? audience, String? type}) validChoice() {
    final key = category;
    if (key == null || !kCategories.any((c) => c.key == key)) {
      return (category: null, audience: null, type: null);
    }
    return (
      category: key,
      audience: categoryByKey(key).hasAudience &&
              kProductTargetGroups.contains(audience)
          ? audience
          : null,
      type: (kTypesByCategory[key] ?? const <String>[]).contains(type)
          ? type
          : null,
    );
  }
}

/// Маусым чипін басу: таңдалмаған болса қосылады, таңдалған болса алынады.
/// Бірнешеуін (төртеуін де) таңдауға болады. Нәтиже — DB пішімі
/// (`Лето,Зима`, канондық ретпен); белгісіз/ескі мәндер сақталады.
String toggleSeasonValue(String raw, String season) {
  final current = parseSeasons(raw);
  final next = current.contains(season)
      ? [for (final s in current) if (s != season) s]
      : [...current, season];
  return joinSeasons(next);
}

/// «Тағы осындайды қосу»: сәтті сақтаудан кейін ашылатын ЖАҢА форманың
/// алдын ала толтырылатын өрістері. Түстер, размерлер, фото және жылдам код
/// КІРМЕЙДІ — олар әр тауарға бөлек. Ешқашан бар тауарға қосылмайды: бұл
/// әрдайым жаңа тауар (екі табаны әртүрлі ақ аяқ киім сияқты жағдайда иесі
/// атауын өзгертеді, мыс. «қара табан» қосады).
class AddProductTemplate {
  final String categoryKey;
  final String type;
  final String audience;
  final String name;
  final String brand;
  final String season;
  final String material;
  final String country;
  final String keywords;
  final String description;
  final String descriptionKk;
  final String purchase;
  final String selling;

  const AddProductTemplate({
    required this.categoryKey,
    this.type = '',
    this.audience = '',
    this.name = '',
    this.brand = '',
    this.season = '',
    this.material = '',
    this.country = '',
    this.keywords = '',
    this.description = '',
    this.descriptionKk = '',
    this.purchase = '',
    this.selling = '',
  });
}
