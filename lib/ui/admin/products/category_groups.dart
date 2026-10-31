/// Тауар қосу формасында 29 категорияны ҚЫСҚАРТУ (ЕШҚАЙСЫСЫН өшірмей):
///   • алдымен дүкеннің өз категориялары (≤ [kPrimaryCategoryMax]);
///   • қалғаны «Басқа санаттар» астында, топтарға бөлініп.
///
/// Тазы логика (Flutter-сіз) — тесттеледі. Категориялардың өзі мен деректері
/// category_data.dart-та қалады (бір шындық көзі); мұнда тек топтау.
library;

import '../../../data/models/category_data.dart';

/// Алғашқы қатарда ең көбі қанша чип.
const int kPrimaryCategoryMax = 8;

/// Дүкенде өз тарихы аз болса, қысқа тізімді осы санға дейін әдепкімен толтырамыз.
const int kPrimaryCategoryMin = 5;

class CategoryGroup {
  final String id;
  final String titleRu, titleKk;
  final List<String> keys;
  const CategoryGroup(this.id, this.titleRu, this.titleKk, this.keys);
}

/// ⚠️ Жаңа категория category_data.dart-қа қосылса, мұнда да БІР топқа қосу
/// керек — test/category_groups_test.dart мұны тексереді (әйтпесе «Басқа
/// санаттар» ішінде жоғалып кетер еді).
const List<CategoryGroup> kCategoryGroups = [
  CategoryGroup('clothes', 'Одежда', 'Киім', [
    'tshirt',
    'outer',
    'pants',
    'dress',
    'underwear',
    'caps',
  ]),
  CategoryGroup('shoes_acc', 'Обувь и аксессуары', 'Аяқ киім және аксессуарлар', [
    'shoes',
    'acc',
    'jewelry',
  ]),
  CategoryGroup('home', 'Дом и быт', 'Үй және тұрмыс', [
    'furniture',
    'textile',
    'dishes',
    'home',
    'garden',
    'tools',
  ]),
  CategoryGroup('tech', 'Техника и электроника', 'Техника және электроника', [
    'electronics',
    'phones',
    'computers',
    'appliances',
  ]),
  CategoryGroup('other', 'Другое', 'Басқа', [
    'sport',
    'kids',
    'toys',
    'beauty',
    'pharmacy',
    'auto',
    'pets',
    'books',
    'stationery',
    'grocery',
  ]),
];

/// Дүкен категориясы (shop_apply_screen: Обувь/Одежда/Аксессуары/Спорт/Другое) →
/// жаңа дүкенге ұсынылатын ықтимал категория кілттері. «Другое»/бос/белгісіз
/// болса — [kDefaultPrimaryCategories].
const Map<String, List<String>> kStoreCategoryDefaults = {
  'Обувь': ['shoes', 'acc', 'underwear', 'caps', 'sport'],
  'Одежда': ['tshirt', 'outer', 'pants', 'dress', 'underwear', 'caps', 'acc', 'shoes'],
  'Аксессуары': ['acc', 'jewelry', 'caps', 'phones', 'beauty'],
  'Спорт': ['sport', 'shoes', 'tshirt', 'pants', 'outer', 'acc'],
};

/// Дүкен категориясы сәйкес келмесе — қысқа әдепкі тізім.
const List<String> kDefaultPrimaryCategories = [
  'shoes',
  'tshirt',
  'outer',
  'pants',
  'dress',
  'acc',
];

/// Дүкен категориясына сай әдепкі кілттер (каталогта жоқтары сүзіледі).
List<String> defaultCategoriesForStore(String? storeCategory) {
  final raw = kStoreCategoryDefaults[(storeCategory ?? '').trim()] ??
      kDefaultPrimaryCategories;
  return _onlyKnown(raw);
}

List<String> _onlyKnown(Iterable<String> keys) {
  final known = {for (final c in kCategories) c.key};
  return [for (final k in keys) if (known.contains(k)) k];
}

/// Алғашқы қатардағы категориялар (кілттер, тәртіппен, ≤ [max]):
///  1. соңғы қолданылған (жадыдан);
///  2. дүкеннің өз тауарларындағы категориялар — саны бойынша кему ретімен;
///  3. өз тарихы аз болса — дүкен түріне сай әдепкі тізіммен [min]-ге дейін;
///  4. [selected] (мысалы AI таңдаған) тізімде жоқ болса — ЕҢ АЛҒА қойылады,
///     таңдалғаны әрқашан көрінетін қатарда тұруы үшін.
List<String> primaryCategoryKeys({
  required Map<String, int> counts,
  String? lastUsed,
  String? storeCategory,
  String? selected,
  int max = kPrimaryCategoryMax,
  int min = kPrimaryCategoryMin,
}) {
  final known = {for (final c in kCategories) c.key};
  final out = <String>[];
  void add(String? k) {
    if (k == null || !known.contains(k) || out.contains(k)) return;
    if (out.length < max) out.add(k);
  }

  add(lastUsed);
  final byCount = counts.entries.where((e) => e.value > 0).toList()
    ..sort((a, b) {
      final c = b.value.compareTo(a.value);
      return c != 0 ? c : a.key.compareTo(b.key);
    });
  for (final e in byCount) {
    add(e.key);
  }
  if (out.length < min) {
    for (final k in defaultCategoriesForStore(storeCategory)) {
      if (out.length >= min) break;
      add(k);
    }
  }
  if (selected != null && known.contains(selected) && !out.contains(selected)) {
    if (out.length >= max) out.removeLast();
    out.insert(0, selected);
  }
  return out;
}

/// Категорияның қай топқа жататыны (топта жоқ болса — соңғы «Басқа»).
CategoryGroup groupOfCategory(String key) {
  for (final g in kCategoryGroups) {
    if (g.keys.contains(key)) return g;
  }
  return kCategoryGroups.last;
}

/// Іздеу: қысқа/толық атау, екі тілде де (кіші әріппен, ішкі жол бойынша).
bool categoryMatchesQuery(CategoryData c, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  return [c.nameRu, c.nameKk, c.shortRu, c.shortKk]
      .any((s) => s.toLowerCase().contains(q));
}
