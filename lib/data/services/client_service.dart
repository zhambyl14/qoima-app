import 'dart:math';
import 'package:flutter/foundation.dart' show ValueNotifier, debugPrint;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/store_model.dart';
import '../models/product_model.dart';
import '../models/category_attributes.dart';
import '../models/batch_model.dart';
import '../models/order_model.dart';
import '../models/review_model.dart';
import '../models/product_question_model.dart';
import '../models/warehouse_model.dart';
import '../models/cart_item_model.dart';
import '../models/promo_model.dart';
import '../../core/search_helper.dart';

import '../../core/lang.dart';
import '../../core/locale_context.dart';
/// Группа товаров-вариантов: одно и то же имя+бренд+тип, разные цвета.
class ProductGroup {
  final List<ProductModel> variants;
  ProductGroup(this.variants);

  ProductModel get main => variants.first;
  String get name => main.name;
  String get brand => main.brand;
  String get type => main.type;
  bool get hasVariants => variants.length > 1;
}

/// Схлопывает список товаров в группы по ключу name+brand+type.
List<ProductGroup> groupProducts(List<ProductModel> products) {
  final map = <String, List<ProductModel>>{};
  for (final p in products) {
    final key =
        '${p.name.trim().toLowerCase()}__${p.brand.trim().toLowerCase()}__${p.type.trim().toLowerCase()}';
    map.putIfAbsent(key, () => []).add(p);
  }
  return map.entries.map((e) => ProductGroup(e.value)).toList();
}

/// Әр түсті жеке карточка ретінде жаямыз.
List<({ProductGroup group, int index})> expandVariantCards(
    List<ProductGroup> groups) {
  final out = <({ProductGroup group, int index})>[];
  for (final g in groups) {
    for (var i = 0; i < g.variants.length; i++) {
      out.add((group: g, index: i));
    }
  }
  return out;
}

/// Категория сипаттамаларының іздеу мәтіні (0085): әр мән ЕКІ тілде де
/// («128 ГБ», «Қазақ тілі» / «Казахский»); мәтін/сан өрістері үшін белгісі де
/// («Автор Абай») — chips мәні өзі жеткілікті. Ағымдағы тілді уақытша
/// ауыстырады (tr/trValue синхронды) да, finally-де қайтарады.
String attributeSearchText(String? categoryKey, Map<String, dynamic> attrs) {
  if (attrs.isEmpty) return '';
  final defs = attributesFor(categoryKey);
  if (defs.isEmpty) return '';
  final saved = LocaleContext.currentLang;
  final out = StringBuffer();
  try {
    for (final lang in const ['ru', 'kk']) {
      LocaleContext.currentLang = lang;
      for (final d in defs) {
        final v = d.valueLabel(attrs[d.key]);
        if (v.isEmpty) continue;
        if (d.kind == AttrKind.text || d.kind == AttrKind.number) {
          out.write(' ${d.label}');
        }
        out.write(' $v');
      }
    }
  } finally {
    LocaleContext.currentLang = saved;
  }
  return out.toString();
}

// Топтың БАРЛЫҚ нұсқаларының барлық өрісі бір мәтінге жиналады: атауы, бренд,
// түр, түс, сипаттама, маусым, «кімге», айырмашылық белгісі. Канондық мәндер
// ru + ағымдағы тіл (trValue) түрінде де қосылады — «жасыл кеды» да, «зелёные
// кеды» да табылады.
String _searchBuffer(ProductGroup g) {
  final buf = StringBuffer();
  void add(String s) {
    if (s.trim().isNotEmpty) buf.write(' $s');
  }

  for (final v in g.variants) {
    add(v.name);
    add(v.brand);
    add(v.articul);
    add(v.type);
    add(trValue(v.type));
    add(v.color);
    add(trValue(v.color));
    add(v.description);
    // 0083: қазақша сипаттама да іздеуге қатысады (екі тілде де табылсын).
    add(v.descriptionKk);
    // Маусым көп мәнді болуы мүмкін ('Лето,Зима') — әрқайсысы жеке сөз.
    for (final s in v.seasonList) {
      add(s);
      add(trValue(s));
    }
    add(v.category);
    add(trValue(v.category));
    add(v.material);
    add(trValue(v.material));
    add(v.variantNote);
    // Категория сипаттамалары (өлшем, автор, кепілдік…) — екі тілде.
    add(attributeSearchText(v.effectiveCategoryKey, v.attributes));
    // «Ұқсас сөздер» (0062): дүкен өзі жазған синонимдер — «сникерс»,
    // «беговые», «спорттық». Тек ІЗДЕУГЕ қатысады, карточкада көрінбейді.
    add(v.keywords);
    // ⚠️ quickCode ӘДЕЙІ ЖОҚ: ол дүкеннің ішкі саны (офлайн сату/қоймадан
    // іздеу үшін). Клиент «103» деп іздегенде бөтен дүкендердің тауарлары
    // шықпауы керек.
  }
  return buf.toString();
}

bool productGroupMatches(ProductGroup g, String query) {
  if (query.trim().isEmpty) return true;

  // Артикул бойынша тікелей ішкі жол іздеу (typo-tolerant сөз салыстыруынан
  // бұрын) — код қысқа әрі бос орынсыз, тура сәйкестік жеткілікті.
  final q = query.trim().toLowerCase();
  for (final v in g.variants) {
    if (v.articul.isNotEmpty && v.articul.toLowerCase().contains(q)) {
      return true;
    }
  }

  // Әр сұраныс сөзі кез келген өріске сәйкес келсе жеткілікті (typo-толерантты).
  return SearchHelper.allWordsMatch(_searchBuffer(g), query);
}

int productGroupScore(ProductGroup g, String query) {
  final a = SearchHelper.score(g.main.name, query);
  final b = SearchHelper.score(g.main.brand, query);
  final c = SearchHelper.score(g.main.type, query);
  final d = SearchHelper.score(g.main.color, query);
  final best = [a, b, c, d].reduce((x, y) => x > y ? x : y);
  // Категория/түр/түс сәйкестігі атауы/бренд сәйкестігінен төменірек
  // салмақты — тек тең балл болғанда сұрыптауды тұрақтандыру үшін.
  return a >= b ? (a * 10 + best) : (b * 10 + best);
}

/// Каталогтағы/дүкендегі іздеу нәтижесі: [results] — табылған топтар,
/// [isFallback] — дәл сәйкестік табылмай, «ұқсас» (кез келген сөз сәйкес
/// келетін) нәтижелерге көшкенін білдіреді (UI-де хинт көрсету үшін).
typedef ProductSearchResult = ({List<ProductGroup> results, bool isFallback});

/// Сұраныс бойынша топтарды іздейді. Алдымен қатаң режим (барлық сөз
/// сәйкес келуі керек — [productGroupMatches]); нәтиже бос болса, клиент
/// «ештеңе табылмады» дегенді көрмеуі үшін босаң режимге көшеміз: кемінде
/// бір сөзі сәйкес келген топтарды сол сәйкестік санына қарай сұрыптап
/// («ұқсас тауарлар» ретінде) қайтарамыз.
ProductSearchResult searchProductGroups(
    List<ProductGroup> groups, String query) {
  final q = query.trim();
  if (q.isEmpty) return (results: groups, isFallback: false);

  final strict = groups.where((g) => productGroupMatches(g, q)).toList()
    ..sort((a, b) => productGroupScore(b, q).compareTo(productGroupScore(a, q)));
  if (strict.isNotEmpty) return (results: strict, isFallback: false);

  final scored = <(ProductGroup, int)>[];
  for (final g in groups) {
    final n = SearchHelper.matchedWordCount(_searchBuffer(g), q);
    if (n > 0) scored.add((g, n));
  }
  scored.sort((a, b) {
    final byCount = b.$2.compareTo(a.$2);
    if (byCount != 0) return byCount;
    return productGroupScore(b.$1, q).compareTo(productGroupScore(a.$1, q));
  });
  return (results: scored.map((e) => e.$1).toList(), isFallback: true);
}

/// Клиент жағындағы деректер сервисі (Supabase).
class ClientService {
  final SupabaseClient _sb = Supabase.instance.client;

  String get _uid => _sb.auth.currentUser?.id ?? '';

  // ── Favorites ───────────────────────────────────────────────────────────────

  Stream<List<String>> watchFavoriteIds() => _uid.isEmpty
      ? const Stream.empty()
      : _sb
          .from('favorites')
          .stream(primaryKey: ['client_uid', 'product_id'])
          .eq('client_uid', _uid)
          .map((rows) => rows.map((r) => r['product_id'] as String).toList());

  Stream<List<Map<String, dynamic>>> watchFavorites() => _uid.isEmpty
      ? const Stream.empty()
      : _sb
          .from('favorites')
          .stream(primaryKey: ['client_uid', 'product_id'])
          .eq('client_uid', _uid)
          .order('created_at', ascending: false)
          .map((rows) => rows
              .map((r) => {
                    'id': r['product_id'],
                    'productId': r['product_id'],
                    'productName': r['product_name'],
                    'imageUrl': r['image_url'],
                    'adminUid': r['admin_uid'],
                    'storeName': r['store_name'],
                    'price': r['price'],
                    'addedAt': r['created_at'],
                  })
              .toList());

  Future<void> addFavorite({
    required String productId,
    required String productName,
    required String imageUrl,
    required String adminUid,
    required String storeName,
    required double price,
  }) =>
      _sb.from('favorites').upsert({
        'client_uid': _uid,
        'product_id': productId,
        'product_name': productName,
        'image_url': imageUrl,
        'admin_uid': adminUid.isEmpty ? null : adminUid,
        'store_name': storeName,
        'price': price,
      });

  Future<void> removeFavorite(String productId) => _sb
      .from('favorites')
      .delete()
      .eq('client_uid', _uid)
      .eq('product_id', productId);

  /// Тауар карточкасын ашқанда қаралым санағышын +1 өсіреді (гость де,
  /// клиент те). Қате болса — үнсіз (санақ көрсетілім тәжірибесіне кедергі
  /// келтірмеуі керек).
  Future<void> incrementProductView(String productId) async {
    try {
      await _sb.rpc('increment_product_view', params: {'p_product': productId});
    } catch (_) {}
  }

  // ── Addresses ───────────────────────────────────────────────────────────────

  // ЕСКЕРТУ: Stream.empty() ЕМЕС — ол ешбір мән бермей бірден жабылады, сол
  // себепті .first шақырса (мыс. stores_list_screen.dart) StateError
  // лақтырады да, гость үшін бүкіл дүкендер тізімі қате экранына түсіп
  // қалатын (нақты багта табылды — мекенжай жоқ гость үшін де тізім
  // қалыпты көрінуі керек).
  Stream<List<Map<String, dynamic>>> watchAddresses() => _uid.isEmpty
      ? Stream.value(const <Map<String, dynamic>>[])
      : _sb
          .from('addresses')
          .stream(primaryKey: ['id'])
          .eq('client_uid', _uid)
          .order('created_at', ascending: false)
          .map((rows) => rows
              .map((r) => {
                    'id': r['id'],
                    'label': r['label'],
                    'address': r['address'],
                    'createdAt': r['created_at'],
                    'lat': (r['lat'] as num?)?.toDouble(),
                    'lng': (r['lng'] as num?)?.toDouble(),
                  })
              .toList());

  /// [lat]/[lng] — картадан белгіленген нүкте (міндетті емес); белгілі болса
  /// «Магазины» тізімінде осы мекенжайға ең жақын дүкен ұсынылады.
  Future<String> addAddress({
    required String label,
    required String address,
    double? lat,
    double? lng,
  }) async {
    final row = await _sb
        .from('addresses')
        .insert({
          'client_uid': _uid,
          'label': label.trim(),
          'address': address.trim(),
          'lat': lat,
          'lng': lng,
        })
        .select('id')
        .single();
    return row['id'] as String;
  }

  Future<void> deleteAddress(String id) =>
      _sb.from('addresses').delete().eq('id', id);

  // ── Stores ─────────────────────────────────────────────────────────────────

  Future<List<StoreModel>> getPublishedStores() async {
    final rows = await _sb
        .from('stores')
        .select()
        .eq('is_published', true)
        .neq('status', 'blocked');
    return rows.map(StoreModel.fromMap).toList();
  }

  /// Берілген дүкен иелерінің (admin_uid) витринада көрінетін, координатасы
  /// белгіленген қоймалары — «Магазины» картасы үшін. RLS (0036 миграция)
  /// автоматты түрде тек жарияланған дүкеннің visible_warehouse_ids-тегі
  /// қоймаларын қайтарады. ownerUid әр белгіні дүкенмен байланыстыру үшін.
  Future<List<({WarehouseModel warehouse, String ownerUid})>>
      getMappableWarehouses(List<String> adminUids) async {
    if (adminUids.isEmpty) return [];
    final rows = await _sb
        .from('warehouses')
        .select()
        .inFilter('owner_uid', adminUids)
        .not('lat', 'is', null)
        .not('lng', 'is', null);
    return rows
        .map((m) => (
              warehouse: WarehouseModel.fromMap(m),
              ownerUid: m['owner_uid'] as String? ?? '',
            ))
        .toList();
  }

  Future<StoreModel?> getStoreByAdminUid(String adminUid) async {
    if (adminUid.isEmpty) return null;
    final row = await _sb
        .from('stores')
        .select()
        .eq('admin_uid', adminUid)
        .maybeSingle();
    return row == null ? null : StoreModel.fromMap(row);
  }

  /// Бірнеше дүкен иесі бойынша топтық сұраныс (мысалы, «Мои бонусы»
  /// экранында әр бонустың қай дүкенге тиесілі екенін көрсету үшін).
  Future<Map<String, StoreModel>> getStoresByAdminUids(
      List<String> adminUids) async {
    if (adminUids.isEmpty) return {};
    final rows =
        await _sb.from('stores').select().inFilter('admin_uid', adminUids);
    final stores = rows.map(StoreModel.fromMap).toList();
    return {for (final s in stores) s.adminUid: s};
  }

  /// ProductModel дүкен иесінің uid-ін алып жүрмейді — push deep-link үшін
  /// (продукттан дүкенге секіру) бөлек сұраймыз.
  Future<String?> getProductOwnerUid(String productId) async {
    if (productId.isEmpty) return null;
    final row = await _sb
        .from('products')
        .select('owner_uid')
        .eq('id', productId)
        .maybeSingle();
    return row?['owner_uid'] as String?;
  }

  // ── Products ───────────────────────────────────────────────────────────────

  Future<ProductModel?> getProductById(
      String adminUid, String productId) async {
    if (productId.isEmpty) return null;
    final row =
        await _sb.from('products').select().eq('id', productId).maybeSingle();
    return row == null ? null : ProductModel.fromMap(row);
  }

  Future<List<ProductModel>> getStoreProducts(String adminUid) async {
    final rows = await _sb
        .from('products')
        .select()
        .eq('owner_uid', adminUid)
        .eq('status', ProductModel.statusInStock)
        // Витринадан жеке жасырылған тауарлар клиентке көрсетілмейді.
        .eq('storefront_hidden', false);
    return rows
        .map(ProductModel.fromMap)
        // Фотосы жоқ тауар онлайн-витринаға шықпайды (қоймада қалады, сатушы
        // карточкадан фото қосқанда автоматты шығады). Сток/тапсырысқа әсер жоқ.
        .where((p) => p.images.isNotEmpty)
        .toList();
  }

  /// Товардың batch-тары. [onlyAvailable]=true — тек қолжетімді (тауары бар).
  Future<List<BatchModel>> getProductBatches(
    String adminUid,
    String productId,
    List<String> warehouseIds, {
    bool onlyAvailable = true,
  }) async {
    final rows =
        await _sb.from('batches').select().eq('product_id', productId);
    return rows
        .map(BatchModel.fromMap)
        .where((b) =>
            (warehouseIds.isEmpty || warehouseIds.contains(b.warehouseId)) &&
            (!onlyAvailable || !b.isEffectivelySoldOut))
        .toList();
  }

  // ── Warehouses ─────────────────────────────────────────────────────────────

  Future<List<WarehouseModel>> getWarehouses(
      String adminUid, List<String> warehouseIds) async {
    if (adminUid.isEmpty) return [];
    final rows =
        await _sb.from('warehouses').select().eq('owner_uid', adminUid);
    return rows
        .map(WarehouseModel.fromMap)
        .where((w) => warehouseIds.isEmpty || warehouseIds.contains(w.id))
        .toList();
  }

  Future<WarehouseModel?> getWarehouseById(
      String adminUid, String warehouseId) async {
    if (warehouseId.isEmpty) return null;
    final row = await _sb
        .from('warehouses')
        .select()
        .eq('id', warehouseId)
        .maybeSingle();
    return row == null ? null : WarehouseModel.fromMap(row);
  }

  // ── Products with batches ──────────────────────────────────────────────────

  Future<List<({ProductModel product, List<BatchModel> batches})>>
      getStoreProductsWithBatches(String adminUid, List<String> whIds) async {
    final products = await getStoreProducts(adminUid);
    if (products.isEmpty) return [];
    final allBatches = await Future.wait(
      products.map((p) => getProductBatches(adminUid, p.id, whIds)),
    );
    final result = <({ProductModel product, List<BatchModel> batches})>[];
    for (var i = 0; i < products.length; i++) {
      final batches = allBatches[i];
      if (batches.isNotEmpty && batches.any((b) => !b.isSoldOut)) {
        result.add((product: products[i], batches: batches));
      }
    }
    return result;
  }

  /// Тауар карточкасының астындағы ұсыныстар: АЛДЫМЕН сол дүкендегі ұқсас
  /// тауарлар (бірдей категория → бірдей бренд → бірдей тип), содан кейін
  /// дүкеннің қалған тауарлары. Ағымдағы тауардың өзі мен оның түс нұсқалары
  /// ([excludeIds]) және қоры таусылғандар шығарылмайды.
  ///
  /// getStoreProductsWithBatches()-ті қайта қолданады (бағасы да керек) —
  /// жаңа RPC/сұраныс схемасы қажет емес.
  Future<List<({ProductModel product, List<BatchModel> batches})>>
      getRelatedProducts({
    required String adminUid,
    required ProductModel current,
    required List<String> visibleWarehouseIds,
    Set<String> excludeIds = const {},
    int limit = 10,
  }) async {
    final all =
        await getStoreProductsWithBatches(adminUid, visibleWarehouseIds);
    final skip = {current.id, ...excludeIds};
    final pool = all.where((e) => !skip.contains(e.product.id)).toList();
    if (pool.isEmpty) return [];

    int score(ProductModel p) {
      var s = 0;
      if (p.effectiveCategoryKey == current.effectiveCategoryKey) s += 4;
      if (p.brand.isNotEmpty &&
          p.brand.toLowerCase() == current.brand.toLowerCase()) {
        s += 2;
      }
      if (p.type.isNotEmpty && p.type == current.type) s += 1;
      return s;
    }

    pool.sort((a, b) {
      final d = score(b.product).compareTo(score(a.product));
      if (d != 0) return d;
      // Ұқсастығы бірдей болса — рейтингі жоғарысы алда.
      return b.product.ratingAvg.compareTo(a.product.ratingAvg);
    });
    return pool.take(limit).toList();
  }

  // ── Pickup code ────────────────────────────────────────────────────────────

  /// Тапсырысты беру коды — 6 ТАҢБАЛЫ САН.
  ///
  /// Бұрын «QM-A7K2» түрінде еді: курьер қоймада тұрып әріп пен санды
  /// шатастыратын (O/0, I/1), терген сайын қате шығатын. Сан-код телефон
  /// пернетақтасында бір қолмен теріледі әрі ауызша айтуға ыңғайлы.
  String _generatePickupCode() {
    final r = Random.secure();
    return List.generate(6, (_) => r.nextInt(10)).join();
  }

  // ── Referral (0044) ────────────────────────────────────────────────────────

  /// Клиенттің осы дүкенде АЯҚТАЛҒАН тапсырысы бар ма — шақыру коды тек
  /// бірінші тапсырысқа жарамды болуы үшін.
  Future<bool> _hasCompletedOrderInStore(String adminUid, String clientUid) async {
    if (clientUid.isEmpty) return false;
    final rows = await _sb
        .from('orders')
        .select('id')
        .eq('admin_uid', adminUid)
        .eq('client_uid', clientUid)
        .eq('status', 'completed')
        .limit(1);
    return rows.isNotEmpty;
  }

  /// Клиент осы дүкеннен сатып алды ма (шақыру коды тек сол кезде беріледі —
  /// 0049). Дүкенге ақша әкелмеген адам оның жеңілдігін тарата алмайды.
  Future<bool> hasPurchasedInStore(String adminUid) =>
      _hasCompletedOrderInStore(adminUid, _uid);

  /// «Промо» бөліміндегі «Досыңды шақыр» тізімі: клиент САТЫП АЛҒАН әрі
  /// шақыру бағдарламасы қосулы дүкендер (adminUid → пайыз).
  Future<Map<String, int>> getMyReferralStores() async {
    if (_uid.isEmpty) return {};
    try {
      final res = await _sb.rpc('my_referral_stores');
      if (res is! List) return {};
      return {
        for (final r in res)
          (r['admin_uid'] as String? ?? ''):
              (r['referral_percent'] as num?)?.toInt() ?? 0,
      }..removeWhere((k, v) => k.isEmpty || v <= 0);
    } catch (_) {
      return {};
    }
  }

  /// Клиенттің осы дүкендегі жеке шақыру коды (жоқ болса жасалады).
  /// null — дүкенде бағдарлама өшірулі, клиент кірмеген немесе бұл дүкеннен
  /// әлі сатып алмаған (0049).
  Future<String?> getMyReferralCode(String adminUid) async {
    if (_uid.isEmpty) return null;
    try {
      final res = await _sb
          .rpc('get_or_create_referral_code', params: {'p_admin': adminUid});
      final code = res as String?;
      return (code == null || code.isEmpty) ? null : code;
    } catch (_) {
      return null;
    }
  }

  /// Клиентке берілген, әлі қолданылмаған сыйлық промокодтары.
  Future<List<PromoModel>> getMyReferralRewards() async {
    if (_uid.isEmpty) return [];
    final rows = await _sb
        .from('promos')
        .select()
        .eq('only_for_uid', _uid)
        .eq('active', true)
        .order('created_at', ascending: false);
    return rows
        .map(PromoModel.fromRow)
        .where((p) => !p.isExhausted && !p.isExpired)
        .toList();
  }

  // ── Promo codes (client validation) ─────────────────────────────────────────

  Future<PromoResult> validatePromo({
    required String adminUid,
    required String code,
    required List<CartItemModel> items,
    required String clientUid,
  }) async {
    final norm = code.trim().toUpperCase();
    if (norm.isEmpty) return PromoResult.fail(tr('Введите промокод', 'Промокод енгізіңіз'));

    final row = await _sb
        .from('promos')
        .select()
        .eq('admin_uid', adminUid)
        .eq('code', norm)
        .limit(1)
        .maybeSingle();
    if (row == null) return PromoResult.fail(tr('Промокод не найден', 'Промокод табылмады'));
    final promo = PromoModel.fromRow(row);

    if (!promo.active) return PromoResult.fail(tr('Промокод отключён', 'Промокод өшірілген'));
    if (!promo.isStarted) {
      return PromoResult.fail(tr('Промокод ещё не активен', 'Промокод әлі белсенді емес'));
    }
    if (promo.isExpired) {
      return PromoResult.fail(tr('Срок действия промокода истёк', 'Промокодтың мерзімі өткен'));
    }
    if (promo.isExhausted) {
      return PromoResult.fail(tr('Лимит использований исчерпан', 'Қолдану лимиті таусылған'));
    }

    // ── Referral кодтары (0044) ──────────────────────────────────────────────
    // Шақыру коды: иесі өзі қолдана алмайды әрі тек СОЛ ДҮКЕНДЕГІ БІРІНШІ
    // тапсырыста жарамды (әйтпесе бір адам шексіз жеңілдік алар еді).
    if (promo.isReferralCode) {
      if (clientUid.isEmpty) {
        return PromoResult.fail(tr('Войдите, чтобы использовать код друга',
            'Дос кодын қолдану үшін кіріңіз'));
      }
      if (promo.referralOwnerUid == clientUid) {
        return PromoResult.fail(tr('Нельзя использовать свой же код',
            'Өз кодыңызды қолдануға болмайды'));
      }
      final hasOrder = await _hasCompletedOrderInStore(adminUid, clientUid);
      if (hasOrder) {
        return PromoResult.fail(tr(
            'Код друга действует только на первый заказ в этом магазине',
            'Дос коды бұл дүкендегі тек бірінші тапсырысқа жарамды'));
      }
    }
    // Сыйлық коды: ТЕК иесіне.
    if (promo.isReferralReward && promo.onlyForUid != clientUid) {
      return PromoResult.fail(tr('Этот промокод выдан другому пользователю',
          'Бұл промокод басқа қолданушыға берілген'));
    }

    if (promo.perUserLimit != null && clientUid.isNotEmpty) {
      try {
        final red = await _sb
            .from('promo_redemptions')
            .select('count')
            .eq('promo_id', promo.id)
            .eq('client_uid', clientUid)
            .maybeSingle();
        final used = (red?['count'] as num?)?.toInt() ?? 0;
        if (used >= promo.perUserLimit!) {
          return PromoResult.fail(tr('Вы уже использовали этот промокод', 'Сіз бұл промокодты бұрын қолдандыңыз'));
        }
      } catch (_) {}
    }

    final applicable = promo.scope == 'products'
        ? items.where((i) => promo.productIds.contains(i.productId)).toList()
        : items;
    if (applicable.isEmpty) {
      return PromoResult.fail(tr('Промокод не применим к этим товарам', 'Промокод бұл тауарларға қолданылмайды'));
    }
    final base = applicable.fold<double>(0, (s, i) => s + i.subtotal);

    if (base < promo.minOrder) {
      return PromoResult.fail(
          tr('Минимальная сумма заказа ${promo.minOrder.toStringAsFixed(0)} ₸', 'Тапсырыстың ең аз сомасы ${promo.minOrder.toStringAsFixed(0)} ₸'));
    }

    return PromoResult.ok(promo, promo.discountFor(base));
  }

  // ── Orders ─────────────────────────────────────────────────────────────────

  /// Batch availability: қол жетімді сан/өлшем (sizes_quantity − reserved_sizes).
  Future<Map<String, int>> getBatchAvailability(
      String adminUid, String productId, String batchId) async {
    final row = await _sb
        .from('batches')
        .select('sizes_quantity,reserved_sizes')
        .eq('id', batchId)
        .maybeSingle();
    if (row == null) return {};
    final sizes = ((row['sizes_quantity'] as Map?) ?? {})
        .map((k, v) => MapEntry(k.toString(), (v as num).toInt()));
    final reserved = ((row['reserved_sizes'] as Map?) ?? {})
        .map((k, v) => MapEntry(k.toString(), (v as num).toInt()));
    return {
      for (final k in sizes.keys) k: (sizes[k] ?? 0) - (reserved[k] ?? 0),
    };
  }

  /// Дүкен бойынша реттік тапсырыс нөмірі (next_counter RPC — receipts/
  /// return санақтарымен бірдей атомдық схема). Бұрын ID-дан хэшпен
  /// жасалатын — реттік болмай, әртүрлі дүкендерде сан ҚАЙТАЛАНУЫ мүмкін еді
  /// (lookupOnlineOrder қате дүкеннің тапсырысын тауып алу қаупі).
  Future<int> _nextOrderNumber(String adminUid) async {
    final n = await _sb.rpc('next_counter',
        params: {'p_owner': adminUid, 'p_name': 'orders'});
    return (n as num).toInt();
  }

  /// Тапсырыс жасайды: қойманы (RPC, oversell қорғауымен) өзгертеді, промокод
  /// есептегішін арттырады, тапсырысты жазады.
  Future<OrderModel> placeOrder(OrderModel order) async {
    final code = _generatePickupCode();

    // Дүкеннің төлем картасы + телефонын снапшот жасаймыз.
    String cardNumber = '', cardHolder = '', cardBank = '', storePhone = '';
    try {
      final s = await _sb
          .from('stores')
          .select(
              'payment_card_number,payment_card_holder,payment_bank,phone')
          .eq('admin_uid', order.adminUid)
          .maybeSingle();
      if (s != null) {
        cardNumber = s['payment_card_number'] as String? ?? '';
        cardHolder = s['payment_card_holder'] as String? ?? '';
        cardBank = s['payment_bank'] as String? ?? '';
        storePhone = s['phone'] as String? ?? '';
      }
    } catch (_) {}

    // Промокод лимитін АЛДЫН АЛА тексереміз (қойманы өзгертпес бұрын).
    final countsPromo = order.promoCountsUsage && order.promoId.isNotEmpty;
    if (countsPromo) {
      final p = await _sb
          .from('promos')
          .select('max_uses,used_count')
          .eq('id', order.promoId)
          .maybeSingle();
      if (p != null) {
        final maxU = (p['max_uses'] as num?)?.toInt();
        final used = (p['used_count'] as num?)?.toInt() ?? 0;
        if (maxU != null && used >= maxU) {
          throw Exception(tr('Лимит использований промокода исчерпан', 'Промокодты қолдану лимиті таусылған'));
        }
      }
    }

    // Қойма: бронь → reserved_sizes +qty; қалғаны → sizes_quantity −qty (guard).
    // Нақты алынғанын санап отырамыз: кейін құласа, ДӘЛ соны қайтару үшін.
    final stockTaken = <CartItemModel>[];
    for (final item in order.items) {
      try {
        await _sb.rpc('adjust_batch_sizes', params: {
          'p_batch': item.batchId,
          'p_deltas': {item.size: order.isSmartReservation ? item.qty : -item.qty},
          'p_field':
              order.isSmartReservation ? 'reserved_sizes' : 'sizes_quantity',
          'p_guard': true,
        });
        stockTaken.add(item);
      } catch (e) {
        await _undoPlacement(order, stock: stockTaken);
        if (e is PostgrestException &&
            (e.message.contains('insufficient_stock') ||
                e.message.contains('batch_not_found'))) {
          throw Exception(
              tr('Недостаточно остатка «${item.productName}» в размере ${item.size}', '«${item.productName}» ${item.size} өлшемінде жеткілікті қор жоқ'));
        }
        rethrow;
      }
    }

    // «Өлшеп көру» (0050): қосымша өлшем қоймада БРОНЬДАЛАДЫ — курьер жолда
    // келе жатқанда оны басқа біреу сатып ала алмауы үшін. Ақшасы алынбайды.
    // Бронь сәтсіз болса (сол өлшем таусылып қалды) — тапсырысты БҰЗБАЙМЫЗ,
    // тек сол позициядан қосымша өлшемді алып тастаймыз.
    var items = order.items;
    if (items.any((i) => i.hasAltSize)) {
      final adjusted = <CartItemModel>[];
      for (final item in items) {
        if (!item.hasAltSize) {
          adjusted.add(item);
          continue;
        }
        try {
          await _sb.rpc('adjust_batch_sizes', params: {
            'p_batch': item.batchId,
            'p_deltas': {item.altSize: item.qty},
            'p_field': 'reserved_sizes',
            'p_guard': true,
          });
          adjusted.add(item);
        } catch (_) {
          adjusted.add(item.copyWith(altSize: ''));
        }
      }
      items = adjusted;
    }

    // Промокод есептегішін арттырамыз.
    var promoTaken = false;
    if (countsPromo) {
      try {
        await _sb.rpc('adjust_promo_usage', params: {
          'p_promo': order.promoId,
          'p_client': order.clientUid.isEmpty ? null : order.clientUid,
          'p_delta': 1,
        });
        promoTaken = true;
      } catch (_) {}
    }

    final placed = order.copyWith(
      items: items,
      pickupCode: code,
      sellerId: 'онлайн',
      sellerName: 'Онлайн',
      deadlineAt: DateTime.now().add(OrderModel.receiptWindow),
      paymentCardNumber: cardNumber,
      paymentCardHolder: cardHolder,
      paymentBank: cardBank,
      storePhone: storePhone,
    );
    // ⚠️ Қойма жазудан БҰРЫН алынады, ал сервер енді жазуды жиі қайтарады (баға,
    // индекс, брон тексерістері). Қайтармасақ, тапсырыссыз қойма жоғалады: қайтаратын
    // тапсырыс та жоқ. Жазылып ҮЛГЕРГЕН тапсырысқа тимейміз — оның қоймасы өзінде.
    final Map<String, dynamic> row;
    try {
      row = await _sb.from('orders').insert(placed.toMap()).select('id').single();
    } catch (e) {
      if (e is PostgrestException || !await _orderMayExist(placed)) {
        await _undoPlacement(
          order,
          stock: stockTaken,
          altHolds: items.where((i) => i.hasAltSize).toList(),
          promo: promoTaken,
        );
      }
      rethrow;
    }
    final orderId = row['id'] as String;
    final orderNumber = await _nextOrderNumber(placed.adminUid);
    await _sb
        .from('orders')
        .update({'order_number': orderNumber}).eq('id', orderId);

    try {
      final seen = <String>{};
      for (final item in order.items) {
        if (seen.add(item.productId)) {
          await _sb.rpc('recompute_product_status',
              params: {'p_product': item.productId});
        }
      }
    } catch (_) {}

    return placed.copyWith(id: orderId, orderNumber: orderNumber);
  }

  /// Желі үзілсе сұраныс серверге жеткен-жетпегені белгісіз: жеткен болса, қойманы
  /// қайтару оны екі есе арттырады (тапсырыс болдырылғанда тағы қайтарылады).
  /// Білу мүмкін болмаса да true: желі жоқта қайтару бәрібір өтпейді.
  Future<bool> _orderMayExist(OrderModel placed) async {
    try {
      final row = await _sb
          .from('orders')
          .select('id')
          .eq('client_uid', placed.clientUid)
          .eq('admin_uid', placed.adminUid)
          .eq('pickup_code', placed.pickupCode)
          .maybeSingle();
      return row != null;
    } catch (_) {
      return true;
    }
  }

  /// [placeOrder] алған нәрсені қайтарады. Әр қадам өз try-ында: біреуі құласа да
  /// қалғаны орындалады, әрі шақырушы БАСТАПҚЫ қатені көреді.
  Future<void> _undoPlacement(
    OrderModel order, {
    List<CartItemModel> stock = const [],
    List<CartItemModel> altHolds = const [],
    bool promo = false,
  }) async {
    Future<void> attempt(String fn, Map<String, dynamic> params) async {
      try {
        await _sb.rpc(fn, params: params);
      } catch (e) {
        debugPrint('placeOrder undo failed: $fn $params: $e');
      }
    }

    for (final item in stock) {
      await attempt('adjust_batch_sizes', {
        'p_batch': item.batchId,
        'p_deltas': {item.size: order.isSmartReservation ? -item.qty : item.qty},
        'p_field':
            order.isSmartReservation ? 'reserved_sizes' : 'sizes_quantity',
        'p_guard': false,
      });
    }
    for (final item in altHolds) {
      await attempt('adjust_batch_sizes', {
        'p_batch': item.batchId,
        'p_deltas': {item.altSize: -item.qty},
        'p_field': 'reserved_sizes',
        'p_guard': false,
      });
    }
    if (promo) {
      await attempt('adjust_promo_usage', {
        'p_promo': order.promoId,
        'p_client': order.clientUid.isEmpty ? null : order.clientUid,
        'p_delta': -1,
      });
    }
  }

  /// Бір төлеммен жасалған суб-тапсырыстарды БІР топқа байлайды (0057).
  ///
  /// Себет дүкен/қойма бойынша бөлінеді, бірақ клиент те, мекенжай да, курьер
  /// баратын жол да біреу. Топсыз курьерге бұлар екі бөтен тапсырыс болып
  /// көрінетін: біреуін бір курьер, екіншісін екіншісі алып кетуі мүмкін еді
  /// де, клиент бір заказын екі курьерден бөлек-бөлек алатын.
  ///
  /// Топ id-і ретінде бірінші тапсырыстың id-і алынады — бөлек uuid генераторы
  /// қажет емес.
  Future<String> linkOrderGroup(List<String> orderIds) async {
    if (orderIds.length < 2) return '';
    final groupId = orderIds.first;
    try {
      await _sb
          .from('orders')
          .update({'cart_group_id': groupId}).inFilter('id', orderIds);
    } catch (_) {
      return '';
    }
    return groupId;
  }

  /// Клиенттің тапсырыстары (clientUid бойынша; client-side сұрыптау).
  // ── Қайта тапсырыс беру (0062) ─────────────────────────────────────────────

  /// Өткен тапсырысты себетке қайта салу нәтижесі: [items] — қазір қолжетімді
  /// (ЖАҢА бағамен, ЖАҢА партиямен) жолдар, [unavailable] — енді жоқ тауар
  /// атаулары.
  ///
  /// ⚠️ Тапсырыстағы `CartItemModel` — СНАПШОТ: ондағы `batchId` мен `price`
  /// айлар бұрынғы болуы мүмкін. Соны сол күйінде себетке салу — жоқ партияға
  /// тапсырыс жасау (checkout қате береді) немесе ескі бағаны тіреу деген сөз.
  /// Сондықтан әр жолды қайта шешеміз.
  Future<({List<CartItemModel> items, List<String> unavailable})> resolveReorder(
      OrderModel order) async {
    final items = <CartItemModel>[];
    final unavailable = <String>[];

    // Дүкеннің өзі жабылса/бұғатталса — түк қосылмайды.
    final store = await getStoreByAdminUid(order.adminUid);
    if (store == null || !store.isPublished || store.isBlocked) {
      return (
        items: items,
        unavailable: order.items.map((i) => i.productName).toList(),
      );
    }

    // Қойма мекенжайлары — бір рет (әр жол үшін қайта сұрамаймыз).
    final whAddress = <String, String>{};
    try {
      for (final w in await getWarehouses(order.adminUid, const [])) {
        whAddress[w.id] = w.address ?? '';
      }
    } catch (_) {}

    for (final old in order.items) {
      try {
        final p = await getProductById(order.adminUid, old.productId);
        if (p == null || p.storefrontHidden) {
          unavailable.add(old.productName);
          continue;
        }
        final batches =
            await getProductBatches(order.adminUid, old.productId, const []);
        // Бұрынғы партия әлі тұрса — соны аламыз (баға/қойма тұрақты болсын),
        // әйтпесе сол өлшемі бар кез келген партияны.
        BatchModel? pick;
        for (final b in batches) {
          if (b.availableForSize(old.size) <= 0) continue;
          if (b.id == old.batchId) {
            pick = b;
            break;
          }
          pick ??= b;
        }
        if (pick == null) {
          unavailable.add('${old.productName} (${old.size})');
          continue;
        }
        final price = effectivePrice(pick);
        items.add(CartItemModel(
          productId: p.id,
          productName: p.name,
          batchId: pick.id,
          size: old.size,
          qty: old.qty,
          price: price,
          originalPrice: price < pick.sellingPrice ? pick.sellingPrice : 0,
          adminUid: order.adminUid,
          storeName: store.storeName,
          imageUrl: p.images.isNotEmpty ? p.images.first : '',
          brand: p.brand,
          type: p.type,
          color: p.color,
          variantNote: p.variantNote,
          articul: p.articul,
          warehouseId: pick.warehouseId,
          warehouseAddress: whAddress[pick.warehouseId] ?? '',
        ));
      } catch (_) {
        unavailable.add(old.productName);
      }
    }
    return (items: items, unavailable: unavailable);
  }

  /// Бір тапсырыс (push-тен тікелей ашу үшін). RLS клиенттің өз тапсырысын
  /// ғана қайтарады, сондықтан бөтен id-мен ештеңе шықпайды.
  Future<OrderModel?> getOrderById(String orderId) async {
    if (orderId.isEmpty) return null;
    final row =
        await _sb.from('orders').select().eq('id', orderId).maybeSingle();
    return row == null ? null : OrderModel.fromMap(row);
  }

  Stream<List<OrderModel>> watchClientOrders(String clientUid) => _sb
      .from('orders')
      .stream(primaryKey: ['id'])
      .eq('client_uid', clientUid)
      .order('created_at', ascending: false)
      .map((rows) => rows.map(OrderModel.fromMap).toList());

  /// Клиент тапсырысты бас тартады. Бас тарту — атомдық `claim_order_transition`
  /// RPC арқылы (0030): қатар серверде LOCK-талып, ағымдағы статус тексеріледі,
  /// сондықтан дәл сол сәтте админ/сатушы «выдать»/«отменить» басса — тек
  /// біреуі ғана өтеді, қойма қосарланып өзгермейді. Расталған/аяқталған
  /// тапсырысты клиенттік авто-cancel ЕШҚАШАН өзгертпейді (claim өзі
  /// қабылдамайды).
  Future<void> cancelOrder(OrderModel order) async {
    try {
      await _sb.rpc('claim_order_transition', params: {
        'p_order': order.id,
        'p_expected': const [
          OrderModel.statusPending,
          OrderModel.statusReserved,
          OrderModel.statusRejected,
        ],
        'p_new_status': OrderModel.statusCancelled,
        'p_actor_role': 'client',
        'p_actor_uid': order.clientUid,
        'p_actor_name': order.clientName,
      });
    } on PostgrestException catch (e) {
      if (e.message.contains('order_state_changed') ||
          e.message.contains('order_not_found')) {
        return; // тапсырыс бұрын өңделген — үнсіз шығамыз (auto-cancel те шақырады)
      }
      rethrow;
    }

    final oRow = await _sb
        .from('orders')
        .select(
            'promo_counts_usage,promo_id,client_uid,stock_restored,is_gift,items')
        .eq('id', order.id)
        .maybeSingle();
    if (oRow == null) return;

    // 🎁 Сыйлық (0070): алушы өлшем таңдамаған сыйлықта қойма ҰСТАЛМАҒАН
    // (stock_restored = true болып жазылады) — қайтаратын ештеңе жоқ, әйтпесе
    // batchId бос → қате. Таңдалған (claim) сыйлықта локалды `order` ескірген
    // болуы мүмкін, сондықтан позицияларды базадан аламыз.
    final stockAlreadyBack = (oRow['stock_restored'] as bool? ?? false);
    final restoreItems = (oRow['is_gift'] as bool? ?? false)
        ? ((oRow['items'] as List?) ?? const [])
            .map((e) => CartItemModel.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : order.items;

    if (stockAlreadyBack) {
      // қойма бұрын қайтарылған / ешқашан ұсталмаған — өткізіп жібереміз
    } else if (order.isSmartReservation) {
      // Claim сәтті болды — тапсырыс pending/reserved/rejected күйінде
      // болғаны расталды, сондықтан резервтен азайту әрқашан орынды.
      for (final item in restoreItems) {
        try {
          await _sb.rpc('adjust_batch_sizes', params: {
            'p_batch': item.batchId,
            'p_deltas': {item.size: -item.qty},
            'p_field': 'reserved_sizes',
            'p_guard': false,
          });
        } on PostgrestException catch (e) {
          // Партия өшірілген болуы мүмкін — болдырмау бөгелмесін.
          if (!e.message.contains('batch_not_found')) rethrow;
        }
      }
    } else {
      for (final item in restoreItems) {
        try {
          await _sb.rpc('adjust_batch_sizes', params: {
            'p_batch': item.batchId,
            'p_deltas': {item.size: item.qty},
            'p_field': 'sizes_quantity',
            'p_guard': false,
          });
        } on PostgrestException catch (e) {
          if (!e.message.contains('batch_not_found')) rethrow;
        }
      }
    }

    // «Өлшеп көру» броні босайды (0050 — бір ғана ақиқат көзі: SQL функциясы).
    // Сыйлықта қосалқы өлшем алушы растағанда қосылады — локалды көшірмеде
    // болмауы мүмкін, сондықтан базадағы позициялар бойынша тексереміз.
    if (restoreItems.any((i) => i.hasAltSize)) {
      try {
        await _sb.rpc('release_fitting_holds', params: {'p_order': order.id});
      } catch (_) {}
    }

    final countsPromo = (oRow['promo_counts_usage'] as bool? ?? false) &&
        ((oRow['promo_id'] as String?) ?? '').isNotEmpty;
    if (countsPromo) {
      final clientUid = (oRow['client_uid'] as String?) ?? '';
      await _sb.rpc('adjust_promo_usage', params: {
        'p_promo': oRow['promo_id'],
        'p_client': clientUid.isEmpty ? null : clientUid,
        'p_delta': -1,
      });
    }

    await _sb.from('orders').update({
      'stock_restored': true,
    }).eq('id', order.id);

    try {
      final seen = <String>{};
      for (final item in order.items) {
        if (seen.add(item.productId)) {
          await _sb.rpc('recompute_product_status',
              params: {'p_product': item.productId});
        }
      }
    } catch (_) {}
  }

  // ── Reviews (пікірлер — тек расталған сатып алушы жазады) ───────────────────

  /// Тауар пікірлері (жаңасы бірінші). Оқу публичті — guest те көреді.
  Future<List<ReviewModel>> getProductReviews(String productId) async {
    if (productId.isEmpty) return [];
    final rows = await _sb
        .from('product_reviews')
        .select()
        .eq('product_id', productId)
        .order('created_at', ascending: false);
    return rows.map(ReviewModel.fromMap).toList();
  }

  /// Клиенттің ӨЗІ жазған барлық пікірлері (тауарлар бойынша) — тапсырыс
  /// тізімінде «бағаланды ма» белгісін көрсету үшін бір сұраныспен аламыз.
  Future<List<ReviewModel>> getMyReviews() async {
    if (_uid.isEmpty) return [];
    final rows =
        await _sb.from('product_reviews').select().eq('client_uid', _uid);
    return rows.map(ReviewModel.fromMap).toList();
  }

  /// Клиент осы тауарды сатып алған ба (completed тапсырыс бар ма)?
  /// RPC — RLS insert саясатымен бір логика (бір ақиқат көзі).
  Future<bool> canReviewProduct(String productId) async {
    if (_uid.isEmpty || productId.isEmpty) return false;
    try {
      final res = await _sb.rpc('client_purchased_product',
          params: {'p_product': productId});
      return res == true;
    } catch (_) {
      return false;
    }
  }

  /// Пікір жазу/өзгерту (бір тауарға бір пікір — upsert).
  Future<void> submitReview({
    required String productId,
    required String adminUid,
    required String clientName,
    required int rating,
    required String comment,
  }) =>
      _sb.from('product_reviews').upsert({
        'product_id': productId,
        'admin_uid': adminUid,
        'client_uid': _uid,
        'client_name': clientName,
        'rating': rating,
        'comment': comment.trim(),
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'product_id,client_uid');

  /// Өз пікірін өшіру.
  Future<void> deleteMyReview(String productId) => _sb
      .from('product_reviews')
      .delete()
      .eq('product_id', productId)
      .eq('client_uid', _uid);

  // ── Questions (Wildberries үлгісіндегі «Вопросы и ответы» — сатып алу
  //    міндетті емес, кез келген авторизацияланған клиент сұрай алады) ────────

  /// Тауар сұрақтары (жаңасы бірінші). Оқу публичті — guest те көреді.
  Future<List<ProductQuestionModel>> getProductQuestions(
      String productId) async {
    if (productId.isEmpty) return [];
    final rows = await _sb
        .from('product_questions')
        .select()
        .eq('product_id', productId)
        .order('created_at', ascending: false);
    return rows.map(ProductQuestionModel.fromMap).toList();
  }

  /// Жаңа сұрақ қою.
  Future<void> askProductQuestion({
    required String productId,
    required String adminUid,
    required String clientName,
    required String question,
  }) =>
      _sb.from('product_questions').insert({
        'product_id': productId,
        'admin_uid': adminUid,
        'client_uid': _uid,
        'client_name': clientName,
        'question': question.trim(),
      });

  /// Өз сұрағын өзгерту (тек жауап берілмеген болса — RLS деңгейінде де).
  Future<void> updateMyQuestion(String questionId, String question) => _sb
      .from('product_questions')
      .update({'question': question.trim()})
      .eq('id', questionId)
      .eq('client_uid', _uid);

  /// Өз сұрағын өшіру (тек жауап берілмеген болса — RLS деңгейінде де).
  Future<void> deleteMyQuestion(String questionId) => _sb
      .from('product_questions')
      .delete()
      .eq('id', questionId)
      .eq('client_uid', _uid);

  // ── Reports (шағымдар — кез келген авторизацияланған қолданушы) ─────────────

  /// Тауарға/дүкенге/пікірге шағым. [targetType]: product|store|review.
  Future<void> submitReport({
    required String targetType,
    required String targetId,
    required String targetName,
    required String reason,
    String comment = '',
    String adminUid = '',
    String storeName = '',
    String reporterName = '',
    String reporterPhone = '',
  }) =>
      _sb.from('content_reports').insert({
        'reporter_uid': _uid,
        'reporter_name': reporterName,
        'reporter_phone': reporterPhone,
        'target_type': targetType,
        'target_id': targetId,
        'target_name': targetName,
        'admin_uid': adminUid.isEmpty ? null : adminUid,
        'store_name': storeName,
        'reason': reason,
        'comment': comment.trim(),
      });

  // ── Hidden stores (клиент дүкенді өзі үшін жасырады — UGC block) ────────────

  /// Жасыру/ашу оқиғасында артады — home/catalog осыны тыңдап қайта жүктейді.
  static final ValueNotifier<int> hiddenStoresVersion = ValueNotifier(0);

  /// Клиент жасырған дүкендердің admin_uid жиыны. Guest → бос жиын.
  Future<Set<String>> getHiddenStoreIds() async {
    if (_uid.isEmpty) return {};
    try {
      final rows = await _sb
          .from('hidden_stores')
          .select('admin_uid')
          .eq('client_uid', _uid);
      return rows.map((r) => r['admin_uid'] as String).toSet();
    } catch (_) {
      return {};
    }
  }

  /// Жасырылған дүкендер тізімі (басқару экраны үшін).
  Future<List<Map<String, dynamic>>> getHiddenStores() async {
    if (_uid.isEmpty) return [];
    final rows = await _sb
        .from('hidden_stores')
        .select()
        .eq('client_uid', _uid)
        .order('created_at', ascending: false);
    return rows
        .map((r) => {
              'adminUid': r['admin_uid'],
              'storeName': r['store_name'],
              'createdAt': r['created_at'],
            })
        .toList();
  }

  Future<void> hideStore(String adminUid, String storeName) async {
    if (_uid.isEmpty || adminUid.isEmpty) return;
    await _sb.from('hidden_stores').upsert({
      'client_uid': _uid,
      'admin_uid': adminUid,
      'store_name': storeName,
    }, onConflict: 'client_uid,admin_uid');
    hiddenStoresVersion.value++;
  }

  Future<void> unhideStore(String adminUid) async {
    if (_uid.isEmpty) return;
    await _sb
        .from('hidden_stores')
        .delete()
        .eq('client_uid', _uid)
        .eq('admin_uid', adminUid);
    hiddenStoresVersion.value++;
  }
}
