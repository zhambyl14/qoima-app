import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/cart_item_model.dart';
import '../models/product_model.dart';
import '../models/batch_model.dart';
import '../models/sale_model.dart';
import '../models/warehouse_model.dart';
import '../models/store_model.dart';
import '../models/reservation_model.dart';
import '../models/order_model.dart';
import '../models/promo_model.dart';
import '../models/revision_model.dart';
import '../../core/app_user.dart';
import '../../core/search_helper.dart';
import '../../core/stream_retry.dart';

import '../../core/lang.dart';

/// «Сұраныс сигналы» жолы — getDemandSignals() қайтарады.
class DemandSignalEntry {
  final String productId;
  final String name;
  final String imageUrl;
  final bool hidden;
  final int favorites;
  final int sold;
  final int available;

  const DemandSignalEntry({
    required this.productId,
    required this.name,
    required this.imageUrl,
    required this.hidden,
    required this.favorites,
    required this.sold,
    required this.available,
  });

  /// Таңдаулыға көп қосылған, бірақ қоймада ЖОҚ — жедел қайта әкелу керек.
  bool get needsRestock => available <= 0;

  /// Таңдаулыға қосылған, қоймада БАР, бірақ ӘЛІ сатылмаған — баға/фотоны
  /// тексеру керек болуы мүмкін.
  bool get notConverting => available > 0 && sold == 0;
}

/// Деректер сервисі (Supabase). Firestore иерархиясы `users/{adminUid}/...`
/// Postgres-те owner_uid/admin_uid сыртқы кілттеріне айналды. Атомдық қойма
/// операциялары RPC арқылы (adjust_batch_sizes, recompute_product_status, ...).
///
/// Класс аты UI-мен үйлесімділік үшін `FirestoreService` болып қалды.
class FirestoreService {
  final SupabaseClient _sb = Supabase.instance.client;

  FirestoreService();

  // ownerUid: admin → өз uid; seller → admin uid
  String get _ownerUid {
    final uid = AppUser.current.ownerUid.isNotEmpty
        ? AppUser.current.ownerUid
        : (_sb.auth.currentUser?.id ?? '');
    if (uid.isEmpty) {
      throw Exception(tr(
          'Пользователь не авторизован.', 'Пайдаланушы авторизацияланбаған.'));
    }
    return uid;
  }

  String get _adminUid => _ownerUid;

  /// Batch-тың жасырын өзіндік құнын batch_costs-тан қайтарады.
  Future<double> resolveBatchCost(String adminUid, String batchId,
      {Map<String, dynamic>? legacyBatchData}) async {
    try {
      final row = await _sb
          .from('batch_costs')
          .select('purchase_price')
          .eq('batch_id', batchId)
          .maybeSingle();
      return (row?['purchase_price'] as num?)?.toDouble() ?? 0;
    } catch (_) {
      return 0;
    }
  }

  // ── Products ─────────────────────────────────────────────────────────────────

  Future<String> addNewProduct({
    required ProductModel product,
    required BatchModel firstBatch,
    DateTime? dateArrived,
    required String warehouseId,
  }) async {
    final owner = _ownerUid;
    final prodRow = await _sb
        .from('products')
        .insert({...product.toMap(), 'owner_uid': owner})
        .select('id')
        .single();
    final productId = prodRow['id'] as String;
    // articul — БД трггерінен (products_set_articul_trg, 0035 миграция)
    // insert кезінде автоматты түрде тағайындалады: реттік санауыш,
    // қайталанбауға кепілдік береді. Мұнда қайта жазбаймыз.
    await _sb.from('products').update({
      'status': ProductModel.statusInStock,
    }).eq('id', productId);

    final batch = firstBatch.copyWith(
        dateArrived: dateArrived ?? DateTime.now(), warehouseId: warehouseId);
    final batchRow = await _sb
        .from('batches')
        .insert({
          ...batch.toMap(),
          'product_id': productId,
          'owner_uid': owner,
        })
        .select('id')
        .single();
    final batchId = batchRow['id'] as String;
    await _sb.from('batch_costs').insert({
      'batch_id': batchId,
      'owner_uid': owner,
      'product_id': productId,
      'purchase_price': firstBatch.purchasePrice,
    });
    final totalQty = firstBatch.sizesQuantity.values.fold(0, (a, b) => a + b);
    if (warehouseId.isNotEmpty) {
      await _sb.rpc('increment_warehouse_totals', params: {
        'p_wh': warehouseId,
        'p_pairs': totalQty,
        'p_products': 1,
      });
    }
    return productId;
  }

  Future<String> addNewBatchToProduct({
    required String productId,
    required BatchModel batch,
    DateTime? dateArrived,
    required String warehouseId,
  }) async {
    final owner = _ownerUid;
    final nb = batch.copyWith(
        dateArrived: dateArrived ?? DateTime.now(), warehouseId: warehouseId);
    final row = await _sb
        .from('batches')
        .insert({...nb.toMap(), 'product_id': productId, 'owner_uid': owner})
        .select('id')
        .single();
    final batchId = row['id'] as String;
    await _sb.from('batch_costs').insert({
      'batch_id': batchId,
      'owner_uid': owner,
      'product_id': productId,
      'purchase_price': batch.purchasePrice,
    });
    await _sb
        .from('products')
        .update({'status': ProductModel.statusInStock}).eq('id', productId);
    final totalQty = nb.sizesQuantity.values.fold(0, (a, b) => a + b);
    if (warehouseId.isNotEmpty) {
      await _sb.rpc('increment_warehouse_totals',
          params: {'p_wh': warehouseId, 'p_pairs': totalQty, 'p_products': 0});
    }
    return batchId;
  }

  // ⚠️ findMatchingProduct() ЖОЙЫЛДЫ (0062). Ол «дәл сондай тауар бар ма» деп
  // іздеп, тапса тауарды ЕСКІ карточкаға партия етіп қосатын. Бұл қате шешім
  // болды: «Товар қосу» дегеніміз — ЖАҢА тауар, ал повторный завоздың өз
  // экраны бар (RestockScreen). Енді қосу формалары ешқашан біріктірмейді,
  // тек [findSimilarProducts] арқылы ҰСЫНЫС береді.

  /// Дүкеннің барлық тауары (бір реттік оқу). «Повторный завоз» тізімі мен
  /// қосу формасындағы «ұқсас тауар» ескертуі осыны қолданады.
  Future<List<ProductModel>> getAllProducts() async {
    final rows = await _sb
        .from('products')
        .select()
        .eq('owner_uid', _ownerUid)
        .order('name', ascending: true);
    return rows.map(ProductModel.fromMap).toList();
  }

  /// ҰҚСАС (дәл емес) тауарлар — «сізде мұндай тауар бар, бұл повторный завоз
  /// емес пе?» ескертуі үшін.
  ///
  /// Нәтиже ЕШҚАШАН автоматты әрекетке айналмайды — админге көрсетіледі, ол
  /// шешеді: тізімнен бассa «Повторный завоз» экраны ашылады, баспаса тауар
  /// өз артикулымен бөлек сақталады.
  Future<List<ProductModel>> findSimilarProducts({
    required String name,
    String brand = '',
    String color = '',
    String categoryKey = '',
    int limit = 4,
  }) async {
    final q = name.trim();
    if (q.length < 3) return [];
    final all = cachedProducts ?? await getAllProducts();
    return rankSimilarProducts(all,
        name: q, brand: brand, color: color, categoryKey: categoryKey, limit: limit);
  }

  /// [findSimilarProducts]-тің таза бөлігі (желісіз, тесттеледі).
  ///
  /// Түс ТЕК ҚОСЫМША ұпай: екі жақта да түс бар әрі бірдей болса +20. Түссіз
  /// тауар (кітап, азық-түлік — color = '') түс арқылы ешқашан сәйкеспейді де,
  /// жазаланбайды да: бос == бос «бірдей түс» деп саналса, түссіз категорияның
  /// кез келген тауары жоғары шығып кетер еді. Ұқсастықты атау шешеді.
  static List<ProductModel> rankSimilarProducts(
    Iterable<ProductModel> all, {
    required String name,
    String brand = '',
    String color = '',
    String categoryKey = '',
    int limit = 4,
  }) {
    final q = name.trim();
    if (q.length < 3) return [];
    final scored = <({ProductModel product, int score})>[];
    for (final p in all) {
      if (categoryKey.isNotEmpty && p.effectiveCategoryKey != categoryKey) {
        continue;
      }
      var s = SearchHelper.score(p.name, q);
      if (s <= 0 && !SearchHelper.allWordsMatch('${p.name} ${p.brand}', q)) {
        continue;
      }
      if (brand.trim().isNotEmpty &&
          p.brand.toLowerCase() == brand.trim().toLowerCase()) {
        s += 30;
      }
      if (color.isNotEmpty && p.color.isNotEmpty && p.color == color) s += 20;
      scored.add((product: p, score: s));
    }
    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.take(limit).map((e) => e.product).toList();
  }

  /// Тауардың СОҢҒЫ партиясы (өзіндік құнымен). «Повторный завоз» формасын
  /// алдын ала толтыру үшін: сол размер линиясы, сол бағалар.
  Future<BatchModel?> lastBatchWithCost(String productId) async {
    final batches = await getBatches(productId);
    if (batches.isEmpty) return null;
    final last = batches.first; // date_arrived desc
    final cost = await resolveBatchCost(_ownerUid, last.id);
    return last.copyWith(purchasePrice: cost);
  }

  /// Осы дүкеннің тауарларынан бірегей брендтер (жиілігі бойынша, ең көп қолданылған
  /// алдында). Товар қосу формасында ұсыныс ретінде көрсетіледі — бренд қайта-қайта
  /// теруге тура келмейді.
  Future<List<String>> distinctBrands({String? categoryKey}) =>
      _distinctColumn('brand', categoryKey: categoryKey);

  /// Осы дүкеннің тауарларынан бұрын қолданылған тип/түрлер (өз нұсқаларын да).
  /// [categoryKey] берілсе — тек сол вид товардың типтерін/брендтерін қайтарады
  /// (мыс. футболка → футболка брендтері/типтері ғана).
  Future<List<String>> distinctTypes({String? categoryKey}) =>
      _distinctColumn('type', categoryKey: categoryKey);

  Future<List<String>> _distinctColumn(String column,
      {String? categoryKey}) async {
    try {
      var query =
          _sb.from('products').select(column).eq('owner_uid', _ownerUid);
      if (categoryKey != null && categoryKey.isNotEmpty) {
        query = query.eq('category_key', categoryKey);
      }
      final rows = await query;
      final counts = <String, int>{};
      for (final r in rows) {
        final v = (r[column] as String? ?? '').trim();
        if (v.isEmpty) continue;
        counts[v] = (counts[v] ?? 0) + 1;
      }
      final list = counts.keys.toList()
        ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
      return list;
    } catch (_) {
      return [];
    }
  }

  Stream<List<ProductModel>> watchProducts() => retryStream(() => _sb
      .from('products')
      .stream(primaryKey: ['id'])
      .eq('owner_uid', _ownerUid)
      .order('name', ascending: true)
      .map((rows) {
        final list = rows.map(ProductModel.fromMap).toList();
        _ProductsCache.set(list);
        return list;
      }));

  List<ProductModel>? get cachedProducts => _ProductsCache.get();

  Future<ProductModel?> getProduct(String productId) async {
    final row =
        await _sb.from('products').select().eq('id', productId).maybeSingle();
    return row == null ? null : ProductModel.fromMap(row);
  }

  /// Товар суреттерін ауыстырады, ЕСКІ URL-дерді қайтарады (шақырушы оларды
  /// Cloudinary-ден тазалауы үшін — restock кезінде жаңа фото ескіні DB-дан
  /// алмастырғанда, ескісі Cloudinary-де жетім қалмауы керек).
  /// Тауарды онлайн-витринадан жасыру/қайтару. [hidden]=true — клиентке
  /// көрсетілмейді (қоймада қалады). toMap айналып өтіп, тек осы бағанды
  /// жаңартады — өңдеудегі басқа деректерге әсер етпейді.
  Future<void> setStorefrontHidden(String productId, bool hidden) => _sb
      .from('products')
      .update({'storefront_hidden': hidden}).eq('id', productId);

  Future<List<String>> updateProductImages(
      String productId, List<String> imageUrls) async {
    final prow = await _sb
        .from('products')
        .select('images')
        .eq('id', productId)
        .maybeSingle();
    final oldImgs = (prow?['images'] as List?)
            ?.map((e) => e.toString())
            .where((u) => u.isNotEmpty)
            .toList() ??
        <String>[];
    await _sb
        .from('products')
        .update({'images': imageUrls}).eq('id', productId);
    return oldImgs;
  }

  /// Тауар карточкасын өңдеу: атауы, бренд, түрі, кімге, түсі, материалы,
  /// сипаттамасы, өндірілген елі, сезоны.
  /// Категория (category_key) өзгермейді — размерлер соған байланған.
  Future<void> updateProductInfo(
    String productId, {
    required String name,
    required String brand,
    required String type,
    required String material,
    required String category,
    required String color,
    required String description,
    required String country,
    required String season,
    String colorHex = '',
    String quickCode = '',
    String keywords = '',
    // null = description_kk-ге тимеу (0083 миграциясыз БД да жұмыс істейді);
    // бос емес/бос жол = жазу. ProductModel.descriptionKkPatch(old, new) береді.
    String? descriptionKk,
    // null = attributes-ке тимеу (0085-сіз БД да жұмыс істейді);
    // ProductModel.attributesPatch(old, new) береді.
    Map<String, dynamic>? attributes,
  }) =>
      _sb.from('products').update({
        if (attributes != null) 'attributes': attributes,
        'name': name.trim(),
        'brand': brand.trim(),
        'type': type,
        'material': material,
        'category': category,
        'color': color,
        'color_hex': colorHex.trim(),
        'description': description.trim(),
        if (descriptionKk != null) 'description_kk': descriptionKk.trim(),
        'country': country.trim(),
        'season': season,
        'quick_code': quickCode.trim(),
        'keywords': keywords.trim(),
      }).eq('id', productId);

  // ── Жылдам код (0062) ───────────────────────────────────────────────────────

  /// Осы дүкендегі жылдам кодты БАСҚА тауар иеленіп тұр ма.
  ///
  /// DB-де partial unique index бар (соңғы шеп), бірақ админге қатені
  /// «PostgrestException 23505» түрінде көрсету — қолданушыға түк айтпайды.
  /// Сондықтан сақтаудан бұрын тексеріп, кім иеленгенін атымен айтамыз.
  /// [exceptProductId] — өңдеп жатқан тауардың өзі (өз кодымен қақтығыспауы үшін).
  Future<ProductModel?> productWithQuickCode(String code,
      {String exceptProductId = ''}) async {
    final c = code.trim();
    if (c.isEmpty) return null;
    var q = _sb
        .from('products')
        .select()
        .eq('owner_uid', _ownerUid)
        .eq('quick_code', c);
    if (exceptProductId.isNotEmpty) q = q.neq('id', exceptProductId);
    final row = await q.limit(1).maybeSingle();
    return row == null ? null : ProductModel.fromMap(row);
  }

  // ── Batches ───────────────────────────────────────────────────────────────────

  Future<List<BatchModel>> getBatches(String productId) async {
    final rows = await _sb
        .from('batches')
        .select()
        .eq('product_id', productId)
        .order('date_arrived', ascending: false);
    return rows.map(BatchModel.fromMap).toList();
  }

  Stream<List<BatchModel>> watchBatches(String productId) => _sb
      .from('batches')
      .stream(primaryKey: ['id'])
      .eq('product_id', productId)
      .order('date_arrived', ascending: false)
      .map((rows) => rows.map(BatchModel.fromMap).toList());

  /// [watchBatches] + жасырын batch_costs-тан өзіндік құнды сіңіреді.
  Stream<List<BatchModel>> watchBatchesWithCost(String productId) => _sb
      .from('batches')
      .stream(primaryKey: ['id'])
      .eq('product_id', productId)
      .order('date_arrived', ascending: false)
      .asyncMap((rows) async {
        final batches = rows.map(BatchModel.fromMap).toList();
        Map<String, double> costMap = {};
        try {
          final costs = await _sb
              .from('batch_costs')
              .select('batch_id,purchase_price')
              .eq('product_id', productId);
          costMap = {
            for (final c in costs)
              c['batch_id'] as String:
                  (c['purchase_price'] as num?)?.toDouble() ?? 0
          };
        } catch (_) {}
        return batches
            .map((b) => costMap.containsKey(b.id)
                ? b.copyWith(purchasePrice: costMap[b.id])
                : b)
            .toList();
      });

  Future<void> updateBatchSizes(
          String productId, String batchId, Map<String, int> sizes) =>
      _sb.from('batches').update({'sizes_quantity': sizes}).eq('id', batchId);

  // ── Discounts ───────────────────────────────────────────────────────────────

  Future<void> setDiscount(
          String productId, String batchId, DiscountModel discount) =>
      _sb
          .from('batches')
          .update({'discount': discount.toMapJson()}).eq('id', batchId);

  Future<void> removeDiscount(String productId, String batchId) =>
      _sb.from('batches').update({'discount': null}).eq('id', batchId);

  Future<void> setDiscountBulk({
    required List<String> productIds,
    required DiscountModel discount,
  }) async {
    if (productIds.isEmpty) return;
    await _sb.from('batches').update(
        {'discount': discount.toMapJson()}).inFilter('product_id', productIds);
  }

  Future<void> removeDiscountBulk(List<String> productIds) async {
    if (productIds.isEmpty) return;
    await _sb
        .from('batches')
        .update({'discount': null}).inFilter('product_id', productIds);
  }

  /// Берілген қоймада batch-і бар тауарлардың id-лері.
  Future<List<String>> productIdsInWarehouse(String warehouseId) async {
    final rows = await _sb
        .from('batches')
        .select('product_id')
        .eq('owner_uid', _ownerUid)
        .eq('warehouse_id', warehouseId);
    return rows.map((r) => r['product_id'] as String).toSet().toList();
  }

  // ── Promo codes (admin CRUD) ──────────────────────────────────────────────

  Stream<List<PromoModel>> watchPromos() => _sb
      .from('promos')
      .stream(primaryKey: ['id'])
      .eq('admin_uid', _adminUid)
      .order('created_at', ascending: false)
      .map((rows) => rows.map(PromoModel.fromRow).toList());

  Future<bool> isPromoCodeUnique(String code, {String? exceptId}) async {
    final rows = await _sb
        .from('promos')
        .select('id')
        .eq('admin_uid', _adminUid)
        .eq('code', code.trim().toUpperCase());
    return rows.every((r) => r['id'] == exceptId);
  }

  Future<String> generateUniquePromoCode({int length = 6}) async {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random.secure();
    for (var attempt = 0; attempt < 10; attempt++) {
      final code =
          List.generate(length, (_) => chars[r.nextInt(chars.length)]).join();
      if (await isPromoCodeUnique(code)) return code;
    }
    return 'PROMO${DateTime.now().millisecondsSinceEpoch % 100000}';
  }

  Future<String> createPromo(PromoModel promo) async {
    final code = promo.code.trim().toUpperCase();
    if (code.isEmpty) {
      throw SaleException(
          tr('Введите код промокода', 'Промокод кодын енгізіңіз'));
    }
    if (!await isPromoCodeUnique(code)) {
      throw SaleException(
          tr('Такой промокод уже существует', 'Мұндай промокод бұрыннан бар'));
    }
    final row = await _sb
        .from('promos')
        .insert({
          ...promo.copyWith(code: code).toRow(),
          'admin_uid': _adminUid,
          'used_count': 0,
        })
        .select('id')
        .single();
    return row['id'] as String;
  }

  Future<void> setPromoActive(String promoId, bool active) =>
      _sb.from('promos').update({'active': active}).eq('id', promoId);

  Future<void> deletePromo(String promoId) async {
    final deleted =
        await _sb.from('promos').delete().eq('id', promoId).select('id');
    if (deleted.isEmpty) {
      throw SaleException(
          tr('Не удалось удалить промокод', 'Промокодты өшіру мүмкін болмады'));
    }
  }

  Future<void> updatePromo(PromoModel promo) async {
    final code = promo.code.trim().toUpperCase();
    if (!await isPromoCodeUnique(code, exceptId: promo.id)) {
      throw SaleException(
          tr('Такой промокод уже существует', 'Мұндай промокод бұрыннан бар'));
    }
    await _sb
        .from('promos')
        .update(promo.copyWith(code: code).toRow())
        .eq('id', promo.id);
  }

  Future<void> updateBatch({
    required String productId,
    required String batchId,
    required DateTime dateArrived,
    required double purchasePrice,
    required double sellingPrice,
    required Map<String, int> sizesQuantity,
  }) async {
    await _sb.from('batches').update({
      'date_arrived': dateArrived.toIso8601String(),
      'selling_price': sellingPrice,
      'sizes_quantity': sizesQuantity,
    }).eq('id', batchId);
    await _sb.from('batch_costs').upsert({
      'batch_id': batchId,
      'owner_uid': _ownerUid,
      'product_id': productId,
      'purchase_price': purchasePrice,
    });
    await _sb.rpc('recompute_product_status', params: {'p_product': productId});
  }

  /// Партияны өшіреді. Егер партиядан сатылым болса — өшірмей архивтейді (қате
  /// лақтырады). Партия өшкен соң товарда БАСҚА партия ДА, ЕШҚАНДАЙ сатылым ДА
  /// қалмаса — товар «жетім» деп есептеліп, жолы толық өшіріледі (share-сілтемесі
  /// бірден жабылады). Сол кезде товардың сурет URL-дері қайтарылады — шақырушы
  /// оларды Cloudinary-ден тазалайды. Әйтпесе бос тізім қайтады.
  Future<List<String>> deleteBatch(String productId, String batchId) async {
    // Осы партияға сілтейтін БЕЛСЕНДІ (әлі шешілмеген) тапсырыс бар ма —
    // болса өшірмейміз. Әйтпесе тапсырысты кейін болдырмау кезінде
    // adjust_batch_sizes «batch_not_found» лақтырып, cancel мәңгі бөгеледі.
    final activeStatuses = [
      OrderModel.statusPending,
      OrderModel.statusReserved,
      OrderModel.statusRejected,
    ];
    // Postgrest-тің .contains() әдісі List<Map> үшін JSON емес, Postgres
    // массив синтаксисін қолданады (мысалы: cs.{"{batchId: ...}"}) — бұл
    // жарамсыз JSON деп серверде PostgrestException (22P02) лақтырады.
    // Сондықтан items ішінен batchId сәйкестігін клиент жағында тексереміз.
    final activeOrdersRaw = await _sb
        .from('orders')
        .select('id, items')
        .inFilter('status', activeStatuses);
    final activeOrders = activeOrdersRaw.where((o) =>
        (o['items'] as List? ?? [])
            .any((it) => (it as Map)['batchId'] == batchId));
    if (activeOrders.isNotEmpty) {
      throw SaleException(tr(
          'По этой партии есть неоплаченный/незавершённый заказ. Сначала отмените или дождитесь его завершения.',
          'Бұл партия бойынша төленбеген/аяқталмаған тапсырыс бар. Алдымен оны болдырмаңыз немесе аяқталуын күтіңіз.'));
    }

    final sales = await _sb
        .from('sales_history')
        .select('id')
        .eq('product_id', productId)
        .eq('batch_id', batchId)
        .limit(1);
    if (sales.isNotEmpty) {
      // Сатылым байланысты — архивтейміз (аналитика сақталады).
      await _sb
          .from('batches')
          .update({'sizes_quantity': <String, int>{}}).eq('id', batchId);
      await _sb
          .rpc('recompute_product_status', params: {'p_product': productId});
      throw SaleException(tr(
          'По этой партии есть продажи. Партия не удалена, а перемещена в архив — аналитика сохранена.',
          'Бұл партия бойынша сатылымдар бар. Партия өшірілмеді, архивке жылжытылды — аналитика сақталды.'));
    }
    await _sb.from('batches').delete().eq('id', batchId);

    // Партия қалмады ма?
    final remaining = await _sb
        .from('batches')
        .select('id')
        .eq('product_id', productId)
        .limit(1);
    if (remaining.isEmpty) {
      // Товар бойынша ешқандай сатылым да жоқ па? (архивтелген партиялар да жоқ)
      final anySales = await _sb
          .from('sales_history')
          .select('id')
          .eq('product_id', productId)
          .limit(1);
      if (anySales.isEmpty) {
        // Жетім товар — жолды толық өшіреміз, суреттерін қайтарамыз.
        final prow = await _sb
            .from('products')
            .select('images')
            .eq('id', productId)
            .maybeSingle();
        final imgs = (prow?['images'] as List?)
                ?.map((e) => e.toString())
                .where((u) => u.isNotEmpty)
                .toList() ??
            <String>[];
        await _sb.from('products').delete().eq('id', productId);
        return imgs;
      }
    }
    await _sb.rpc('recompute_product_status', params: {'p_product': productId});
    return <String>[];
  }

  // ── Sales ─────────────────────────────────────────────────────────────────────

  /// Реттік чек нөмірі: `#NNNNN` (атомдық next_counter RPC).
  Future<String> nextReceiptNumber() async {
    try {
      final n = await _sb.rpc('next_counter',
          params: {'p_owner': _ownerUid, 'p_name': 'receipts'});
      return '#${(n as int).toString().padLeft(5, '0')}';
    } catch (_) {
      final n = DateTime.now().millisecondsSinceEpoch % 100000;
      return '#${n.toString().padLeft(5, '0')}';
    }
  }

  Future<void> makeSale({
    required String productId,
    required String batchId,
    required Map<String, int> sizesSold,
    double discountPercent = 0,
    required String warehouseId,
    String paymentMethod = 'cash',
    String? idempotencyKey,
    String receiptNumber = '',
  }) async {
    final owner = _ownerUid;
    final sellerId = AppUser.current.uid.isNotEmpty
        ? AppUser.current.uid
        : (_sb.auth.currentUser?.id ?? '');
    final sellerName = AppUser.current.name;

    final prod = await _sb
        .from('products')
        .select('name')
        .eq('id', productId)
        .maybeSingle();
    final productName = prod?['name'] as String? ?? '';
    final cost = await resolveBatchCost(owner, batchId);

    // Атомдық қойма азайту (oversell қорғауымен).
    final deltas = <String, int>{};
    sizesSold.forEach((k, v) {
      if (v > 0) deltas[k] = -v;
    });
    try {
      await _sb.rpc('adjust_batch_sizes', params: {
        'p_batch': batchId,
        'p_deltas': deltas,
        'p_field': 'sizes_quantity',
        'p_guard': true,
      });
    } on PostgrestException catch (e) {
      if (e.message.contains('insufficient_stock')) {
        throw SaleException(tr(
            'Недостаточно остатка на складе.', 'Қоймада қалдық жеткіліксіз.'));
      }
      rethrow;
    }

    final batchRow = await _sb
        .from('batches')
        .select('selling_price')
        .eq('id', batchId)
        .maybeSingle();
    final selling = (batchRow?['selling_price'] as num?)?.toDouble() ?? 0;
    final qty = sizesSold.values.fold(0, (a, b) => a + b);
    final base = selling * qty;
    final total = base * (1 - discountPercent / 100);
    final firstSize = sizesSold.keys.isNotEmpty ? sizesSold.keys.first : '';

    await _sb.from('sales_history').insert({
      'owner_uid': owner,
      'product_id': productId,
      'batch_id': batchId,
      'product_name': productName,
      'sale_date': DateTime.now().toIso8601String(),
      'sizes_sold': sizesSold,
      'selected_size': firstSize,
      'quantity': qty,
      'base_price': base,
      'total_price': total,
      'discount_percent': discountPercent,
      'discount_amount': base - total,
      'purchase_price': cost,
      'seller_id': sellerId,
      'seller_name': sellerName,
      'warehouse_id': warehouseId.isEmpty ? null : warehouseId,
      'payment_method': paymentMethod,
      'receipt_number': receiptNumber,
      'type': 'sale',
    });

    if (warehouseId.isNotEmpty) {
      await _sb.rpc('increment_warehouse_totals',
          params: {'p_wh': warehouseId, 'p_pairs': -qty, 'p_products': 0});
    }
    await _sb.rpc('recompute_product_status', params: {'p_product': productId});
  }

  Stream<List<SaleModel>> watchSalesHistory() => retryStream(() => _sb
      .from('sales_history')
      .stream(primaryKey: ['id'])
      .order('sale_date', ascending: false)
      .map((rows) => rows.map(SaleModel.fromMap).toList()));

  /// Тек берілген айдың сатулары (клиент жағында сүзіледі — RLS бизнес-скоуп).
  Stream<List<SaleModel>> watchSalesForMonth(DateTime month) {
    final from = DateTime(month.year, month.month, 1);
    final to = DateTime(month.year, month.month + 1, 1);
    return retryStream(() => _sb
        .from('sales_history')
        .stream(primaryKey: ['id'])
        .order('sale_date', ascending: false)
        .map((rows) => rows
            .map(SaleModel.fromMap)
            .where((s) => !s.saleDate.isBefore(from) && s.saleDate.isBefore(to))
            .toList()));
  }

  // ── Revisions (ревизия: недостача + списание) ────────────────────────────────

  Stream<List<RevisionModel>> watchRevisions() => retryStream(() => _sb
      .from('revisions')
      .stream(primaryKey: ['id'])
      .eq('owner_uid', _ownerUid)
      .order('created_at', ascending: false)
      .map((rows) => rows.map(RevisionModel.fromMap).toList()));

  /// Ашық (әлі списание жасалмаған) недостачалар саны — Главная badge.
  Stream<int> watchOpenRevisionsCount() =>
      watchRevisions().map((list) => list.where((r) => r.isOpen).length);

  /// Недостача жазбасын жасайды (қойма ӘЛІ азаймайды — тек «Списать» кезінде).
  Future<void> createRevision({
    required String productId,
    required String productName,
    required String warehouseId,
    required Map<String, int> sizesMissing,
    String note = '',
  }) async {
    final missing = Map<String, int>.fromEntries(
        sizesMissing.entries.where((e) => e.value > 0));
    if (missing.isEmpty) {
      throw SaleException(
          tr('Укажите количество недостачи', 'Жетіспеушілік санын көрсетіңіз'));
    }
    await _sb.from('revisions').insert({
      'owner_uid': _ownerUid,
      'product_id': productId,
      'product_name': productName,
      'warehouse_id': warehouseId.isEmpty ? null : warehouseId,
      'sizes_missing': missing,
      'quantity': missing.values.fold(0, (a, b) => a + b),
      'note': note.trim(),
      'status': RevisionModel.statusOpen,
      'created_by': AppUser.current.uid.isEmpty
          ? _sb.auth.currentUser?.id
          : AppUser.current.uid,
      'created_by_name': AppUser.current.name,
    });
  }

  Future<void> deleteRevision(String revisionId) => _sb
      .from('revisions')
      .delete()
      .eq('id', revisionId)
      .eq('status', RevisionModel.statusOpen);

  /// Недостачаны списание жасайды: қойманы FIFO бойынша азайтады да,
  /// sales_history-ге type='writeoff' жазба түсіреді. [amount] — дүкен иесі
  /// белгілеген списание сомасы (₸): түсім ретінде ИЕНІҢ атына жазылады
  /// (seller_id = owner), сондықтан «Продавцы» бөлімі мен аналитикаға пайда
  /// болып кіреді. Возвратқа жатпайды.
  Future<void> writeOffRevision(RevisionModel rev,
      {required double amount}) async {
    final owner = _ownerUid;
    if (!rev.isOpen) return; // идемпотентті — қайта басу қауіпсіз

    // Ескі→жаңа партиялар (FIFO), недостача қоймасы бойынша.
    var bq = _sb.from('batches').select().eq('product_id', rev.productId);
    if (rev.warehouseId.isNotEmpty) {
      bq = bq.eq('warehouse_id', rev.warehouseId);
    }
    final srcRows = await bq.order('date_arrived', ascending: true);
    if (srcRows.isEmpty) {
      throw SaleException(tr('Недостаточно остатка для списания',
          'Списаниеге қалдық жеткіліксіз'));
    }
    final cost = await resolveBatchCost(owner, srcRows.first['id'] as String);

    final remaining = Map<String, int>.from(rev.sizesMissing)
      ..removeWhere((_, v) => v <= 0);
    String firstBatchId = srcRows.first['id'] as String;
    for (final b in srcRows) {
      final bid = b['id'] as String;
      final bSizes = Map<String, int>.from(((b['sizes_quantity'] as Map?) ?? {})
          .map((k, v) => MapEntry(k.toString(), (v as num).toInt())));
      final deltas = <String, int>{};
      for (final size in remaining.keys.toList()) {
        final needed = remaining[size]!;
        if (needed <= 0) continue;
        final have = bSizes[size] ?? 0;
        if (have <= 0) continue;
        final take = needed > have ? have : needed;
        deltas[size] = -take;
        remaining[size] = needed - take;
      }
      if (deltas.isNotEmpty) {
        await _sb.rpc('adjust_batch_sizes', params: {
          'p_batch': bid,
          'p_deltas': deltas,
          'p_field': 'sizes_quantity',
          'p_guard': true,
        });
        firstBatchId = bid;
      }
      if (remaining.values.every((v) => v == 0)) break;
    }
    if (remaining.values.any((v) => v > 0)) {
      throw SaleException(tr('Недостаточно остатка для списания',
          'Списаниеге қалдық жеткіліксіз'));
    }

    final qty = rev.sizesMissing.values.fold(0, (a, b) => a + b);
    final firstSize =
        rev.sizesMissing.keys.isNotEmpty ? rev.sizesMissing.keys.first : '';
    // Списание сомасы ИЕНІҢ атына жазылады (пайда). Иенің uid = owner_uid.
    await _sb.from('sales_history').insert({
      'owner_uid': owner,
      'product_id': rev.productId,
      'batch_id': firstBatchId,
      'product_name': rev.productName,
      'sale_date': DateTime.now().toIso8601String(),
      'sizes_sold': rev.sizesMissing,
      'selected_size': firstSize,
      'quantity': qty,
      'base_price': amount,
      'total_price': amount,
      'discount_percent': 0.0,
      'discount_amount': 0.0,
      'purchase_price': cost,
      'seller_id': owner,
      'seller_name': AppUser.current.name,
      'warehouse_id': rev.warehouseId.isEmpty ? null : rev.warehouseId,
      'payment_method': '',
      'receipt_number': '',
      'type': 'writeoff',
    });

    if (rev.warehouseId.isNotEmpty) {
      await _sb.rpc('increment_warehouse_totals',
          params: {'p_wh': rev.warehouseId, 'p_pairs': -qty, 'p_products': 0});
    }
    await _sb.from('revisions').update({
      'status': RevisionModel.statusWrittenOff,
      'written_off_at': DateTime.now().toIso8601String(),
    }).eq('id', rev.id);
    await _sb
        .rpc('recompute_product_status', params: {'p_product': rev.productId});
  }

  Future<(Map<String, List<BatchModel>>, Map<String, String>)>
      getAllBatchesGrouped() async {
    final owner = _ownerUid;
    final prods =
        await _sb.from('products').select('id,name').eq('owner_uid', owner);
    final allBatches =
        await _sb.from('batches').select().eq('owner_uid', owner);
    final batches = <String, List<BatchModel>>{};
    final names = <String, String>{};
    for (final p in prods) {
      batches[p['id'] as String] = [];
      names[p['id'] as String] = p['name'] as String? ?? '';
    }
    for (final b in allBatches) {
      final pid = b['product_id'] as String?;
      if (pid == null) continue;
      (batches[pid] ??= []).add(BatchModel.fromMap(b));
    }
    return (batches, names);
  }

  /// «Сұраныс сигналы»: әр тауар бойынша таңдаулы (favorites) саны, барлық
  /// уақыттағы сатылым саны және қазіргі қолжетімді қор — admin осы
  /// деректен нақты нені қайта әкелу/жарнамалау керегін көреді (viewCount-тан
  /// айырмашылығы — таңдаулы «сатып алуға дайын» ниетті білдіреді).
  Future<List<DemandSignalEntry>> getDemandSignals() async {
    final owner = _ownerUid;
    final results = await Future.wait([
      _sb
          .from('products')
          .select('id,name,images,storefront_hidden')
          .eq('owner_uid', owner),
      _sb.from('favorites').select('product_id').eq('admin_uid', owner),
      _sb
          .from('sales_history')
          .select('product_id,quantity')
          .eq('owner_uid', owner)
          .eq('type', 'sale'),
      _sb
          .from('batches')
          .select('product_id,sizes_quantity,reserved_sizes')
          .eq('owner_uid', owner),
    ]);
    final products = results[0] as List;
    final favRows = results[1] as List;
    final saleRows = results[2] as List;
    final batchRows = results[3] as List;

    final favCount = <String, int>{};
    for (final r in favRows) {
      final pid = r['product_id'] as String?;
      if (pid == null) continue;
      favCount[pid] = (favCount[pid] ?? 0) + 1;
    }
    final soldQty = <String, int>{};
    for (final r in saleRows) {
      final pid = r['product_id'] as String?;
      if (pid == null) continue;
      soldQty[pid] =
          (soldQty[pid] ?? 0) + ((r['quantity'] as num?)?.toInt() ?? 0);
    }
    final availQty = <String, int>{};
    for (final r in batchRows) {
      final pid = r['product_id'] as String?;
      if (pid == null) continue;
      final batch = BatchModel.fromMap(r);
      availQty[pid] = (availQty[pid] ?? 0) + batch.totalAvailable;
    }

    return products
        .map((p) {
          final id = p['id'] as String;
          final images = (p['images'] as List?)?.cast<String>() ?? const [];
          return DemandSignalEntry(
            productId: id,
            name: p['name'] as String? ?? '',
            imageUrl: images.isNotEmpty ? images.first : '',
            hidden: p['storefront_hidden'] as bool? ?? false,
            favorites: favCount[id] ?? 0,
            sold: soldQty[id] ?? 0,
            available: availQty[id] ?? 0,
          );
        })
        .where((e) => e.favorites > 0)
        .toList()
      ..sort((a, b) => b.favorites.compareTo(a.favorites));
  }

  /// Тауар бойынша барлық уақыттағы ОНЛАЙН сатылым саны (product_id →
  /// дана) — витрина конверсиясын (қаралым→сатылым) есептеу үшін
  /// (storefront_manage_screen.dart).
  Future<Map<String, int>> getOnlineSoldQtyByProduct() async {
    final rows = await _sb
        .from('sales_history')
        .select('product_id,quantity')
        .eq('owner_uid', _ownerUid)
        .eq('type', 'sale')
        .eq('is_online', true);
    final result = <String, int>{};
    for (final r in rows) {
      final pid = r['product_id'] as String?;
      if (pid == null) continue;
      result[pid] =
          (result[pid] ?? 0) + ((r['quantity'] as num?)?.toInt() ?? 0);
    }
    return result;
  }

  Future<List<SaleModel>> getSalesForProduct(String productId) async {
    final rows = await _sb
        .from('sales_history')
        .select()
        .eq('product_id', productId)
        .order('sale_date', ascending: false);
    return rows.map(SaleModel.fromMap).toList();
  }

  Future<SaleModel?> getSaleById(String id) async {
    if (id.isEmpty) return null;
    final row =
        await _sb.from('sales_history').select().eq('id', id).maybeSingle();
    return row == null ? null : SaleModel.fromMap(row);
  }

  Future<double> getTotalRevenue({DateTime? from, DateTime? to}) async {
    var q = _sb
        .from('sales_history')
        .select('total_price')
        .eq('owner_uid', _ownerUid);
    if (from != null) q = q.gte('sale_date', from.toIso8601String());
    if (to != null) q = q.lte('sale_date', to.toIso8601String());
    final rows = await q;
    return rows.fold<double>(
        0, (s, r) => s + ((r['total_price'] as num?)?.toDouble() ?? 0));
  }

  Future<int> getArrivedPairsForMonth(DateTime month) async {
    final from = DateTime(month.year, month.month, 1);
    final to = DateTime(month.year, month.month + 1, 1);
    final rows = await _sb
        .from('batches')
        .select('sizes_quantity,date_arrived')
        .eq('owner_uid', _ownerUid)
        .gte('date_arrived', from.toIso8601String())
        .lt('date_arrived', to.toIso8601String());
    int total = 0;
    for (final b in rows) {
      final sq = (b['sizes_quantity'] as Map?) ?? {};
      total += sq.values.fold<int>(0, (s, v) => s + (v as num).toInt());
    }
    return total;
  }

  // ── Warehouses ────────────────────────────────────────────────────────────────

  Stream<List<WarehouseModel>> watchWarehouses() => _sb
      .from('warehouses')
      .stream(primaryKey: ['id'])
      .eq('owner_uid', _ownerUid)
      .order('created_at', ascending: true)
      .map((rows) => rows.map(WarehouseModel.fromMap).toList());

  Future<List<WarehouseModel>> getWarehouses() async {
    final rows = await _sb
        .from('warehouses')
        .select()
        .eq('owner_uid', _ownerUid)
        .order('created_at', ascending: true);
    return rows.map(WarehouseModel.fromMap).toList();
  }

  Future<String> createWarehouse({
    required String name,
    String? address,
    String? note,
    bool isMain = false,
  }) async {
    final owner = _ownerUid;
    final row = await _sb
        .from('warehouses')
        .insert({
          'owner_uid': owner,
          'name': name.trim(),
          if (address != null && address.isNotEmpty) 'address': address.trim(),
          if (note != null && note.isNotEmpty) 'note': note.trim(),
          'is_main': isMain,
        })
        .select('id')
        .single();
    final id = row['id'] as String;
    // Дүкеннің visible_warehouse_ids-іне қосамыз (бар болса).
    try {
      final store = await _sb
          .from('stores')
          .select('visible_warehouse_ids')
          .eq('admin_uid', owner)
          .maybeSingle();
      if (store != null) {
        final ids = ((store['visible_warehouse_ids'] as List?) ?? [])
            .map((e) => e.toString())
            .toList();
        if (!ids.contains(id)) {
          ids.add(id);
          await _sb.from('stores').update({
            'visible_warehouse_ids': ids,
            'updated_at': DateTime.now().toIso8601String(),
          }).eq('admin_uid', owner);
        }
      }
    } catch (_) {}
    return id;
  }

  Future<void> updateWarehouse({
    required String warehouseId,
    required String name,
    String? address,
    String? note,
  }) =>
      _sb.from('warehouses').update({
        'name': name.trim(),
        'address': address?.trim() ?? '',
        'note': note?.trim() ?? '',
      }).eq('id', warehouseId);

  Future<void> updateWarehouseLocation({
    required String warehouseId,
    required double lat,
    required double lng,
  }) =>
      _sb
          .from('warehouses')
          .update({'lat': lat, 'lng': lng}).eq('id', warehouseId);

  Future<void> deleteWarehouse(String warehouseId) =>
      _sb.from('warehouses').delete().eq('id', warehouseId);

  /// Қойманы өшіреді + оған байланысты batch-тарды босатады (warehouse_id=null).
  Future<void> deleteWarehouseDeep(String warehouseId) async {
    await _sb
        .from('batches')
        .update({'warehouse_id': null})
        .eq('owner_uid', _ownerUid)
        .eq('warehouse_id', warehouseId);
    await _sb.from('warehouses').delete().eq('id', warehouseId);
  }

  /// Товарлар + ӨЗ batch-тарымен. [warehouseId] берілсе — сол қойма бойынша сүзіледі.
  Stream<List<({ProductModel product, List<BatchModel> batches})>>
      watchProductsWithBatches({String warehouseId = ''}) =>
          retryStream(() => _sb
              .from('products')
              .stream(primaryKey: ['id'])
              .eq('owner_uid', _ownerUid)
              .order('name', ascending: true)
              .asyncMap((prows) async {
                final products = prows.map(ProductModel.fromMap).toList();
                var bq =
                    _sb.from('batches').select().eq('owner_uid', _ownerUid);
                if (warehouseId.isNotEmpty) {
                  bq = bq.eq('warehouse_id', warehouseId);
                }
                final brows = await bq;
                final byProduct = <String, List<BatchModel>>{};
                for (final b in brows) {
                  final pid = b['product_id'] as String?;
                  if (pid == null) continue;
                  (byProduct[pid] ??= []).add(BatchModel.fromMap(b));
                }
                final out =
                    <({ProductModel product, List<BatchModel> batches})>[];
                for (final p in products) {
                  final batches = byProduct[p.id] ?? [];
                  if (warehouseId.isNotEmpty && batches.isEmpty) continue;
                  out.add((product: p, batches: batches));
                }
                return out;
              }));

  Stream<List<ProductWithStock>> watchProductsInWarehouse(String warehouseId) =>
      watchProductsWithBatches(warehouseId: warehouseId).map((list) => list
          .map((e) => ProductWithStock(
                product: e.product,
                pairs: e.batches.fold<int>(0, (s, b) => s + b.totalQuantity),
              ))
          .toList());

  Stream<List<ProductWithStock>> watchAllProductPairs() =>
      watchProductsWithBatches().map((list) => list
          .map((e) => ProductWithStock(
                product: e.product,
                pairs: e.batches.fold<int>(0, (s, b) => s + b.totalQuantity),
              ))
          .toList());

  Future<int> countProductsInWarehouse(String warehouseId) async {
    final row = await _sb
        .from('warehouses')
        .select('total_products')
        .eq('id', warehouseId)
        .maybeSingle();
    return (row?['total_products'] as num?)?.toInt() ?? 0;
  }

  Future<int> countPairsInWarehouse(String warehouseId) async {
    final row = await _sb
        .from('warehouses')
        .select('total_pairs')
        .eq('id', warehouseId)
        .maybeSingle();
    return (row?['total_pairs'] as num?)?.toInt() ?? 0;
  }

  Future<int> countSellersInWarehouse(String warehouseId) async {
    final rows = await _sb
        .from('users')
        .select('role,join_status,assigned_warehouse_id')
        .eq('owner_id', _adminUid);
    return rows
        .where((d) =>
            d['role'] == 'seller' &&
            d['join_status'] == 'active' &&
            d['assigned_warehouse_id'] == warehouseId)
        .length;
  }

  /// Seller-дің өз профилін бақылау (WarehouseContext қойма ауысқанда реакция жасайды).
  Stream<String> watchSellerAssignedWarehouseId() => _sb
      .from('users')
      .stream(primaryKey: ['id'])
      .eq('id', _sb.auth.currentUser!.id)
      .map((rows) => rows.isEmpty
          ? ''
          : (rows.first['assigned_warehouse_id'] as String? ?? ''));

  // ── Seller join flow ──────────────────────────────────────────────────────────

  Future<void> sendJoinRequest(String businessCode) async {
    final sellerUid = _sb.auth.currentUser?.id;
    if (sellerUid == null) throw tr('Не авторизован', 'Авторизацияланбаған');

    // 0065: business_codes-ты бұрын кез келген тіркелген адам ТІЗІП оқи
    // алатын (bc_select using(true)) — бизнес-код қосылу қақпасы болғандықтан
    // қақпа мағынасыз болатын. Енді саясат иесіне ғана оқуға рұқсат етеді,
    // ал қосылу ағыны ДӘЛ сәйкестікті тексеретін RPC арқылы жүреді (тізім
    // қайтармайды).
    final adminUid = await _sb.rpc('business_code_owner',
        params: {'p_code': businessCode.trim().toUpperCase()}) as String?;
    if (adminUid == null || adminUid.isEmpty) {
      throw tr('Бизнес-код не найден. Введите корректный код.',
          'Бизнес-код табылмады. Дұрыс кодты енгізіңіз.');
    }

    // (seller_uid, admin_uid) бойынша unique — қайта жіберу жаңа жол қоспай,
    // бар жолды 'pending' етіп жаңартады (дубликат/406 болмайды).
    await _sb.from('join_requests').upsert({
      'admin_uid': adminUid,
      'seller_uid': sellerUid,
      'seller_name': AppUser.current.name,
      'seller_email': _sb.auth.currentUser?.email ?? '',
      'status': 'pending',
    }, onConflict: 'seller_uid,admin_uid');
    await _sb
        .from('users')
        .update({'join_status': 'pending'}).eq('id', sellerUid);
  }

  Future<void> cancelJoinRequest() async {
    final sellerUid = _sb.auth.currentUser!.id;
    await _sb
        .from('join_requests')
        .delete()
        .eq('seller_uid', sellerUid)
        .eq('status', 'pending');
    await _sb.from('users').update({'join_status': 'none'}).eq('id', sellerUid);
  }

  // approve/reject/remove — SECURITY DEFINER RPC арқылы: дүкен иесі сатушының
  // users жолын тікелей жаңарта алмайды (users_update саясаты тек id=auth.uid()).
  Future<void> approveJoinRequest({
    required String requestId,
    required String sellerId,
    required String warehouseId,
  }) async {
    await _sb.rpc('approve_join_request', params: {
      'p_request_id': requestId,
      'p_warehouse_id': warehouseId,
    });
  }

  Future<void> rejectJoinRequest({
    required String requestId,
    required String sellerId,
  }) async {
    await _sb.rpc('reject_join_request', params: {'p_request_id': requestId});
  }

  Future<void> removeSeller(String sellerId) =>
      _sb.rpc('remove_seller', params: {'p_seller_id': sellerId});

  Future<void> reassignSellerWarehouse(String sellerId, String warehouseId) =>
      _sb.rpc('reassign_seller_warehouse', params: {
        'p_seller_id': sellerId,
        'p_warehouse_id': warehouseId,
      });

  // ── Дүкеннен шығу сұранысы (seller → owner мақұлдауын күтеді) ────────────
  // join_requests-тегі бар (seller,admin) жолын қайта пайдаланамыз — жаңа
  // кесте/RPC қажет емес, RLS сатушыға өз жолын update етуге рұқсат береді
  // (joinreq_update: admin_uid = auth.uid() OR seller_uid = auth.uid()).
  Future<void> requestLeaveShop() async {
    final uid = _sb.auth.currentUser!.id;
    await _sb
        .from('join_requests')
        .update({'status': 'leave_pending'})
        .eq('seller_uid', uid)
        .eq('admin_uid', _ownerUid);
  }

  Future<void> cancelLeaveRequest() async {
    final uid = _sb.auth.currentUser!.id;
    await _sb
        .from('join_requests')
        .update({'status': 'approved'})
        .eq('seller_uid', uid)
        .eq('admin_uid', _ownerUid);
  }

  /// Owner жағы: сатушының шығу сұранысын қабылдамай, қайта 'approved' етеді.
  Future<void> rejectLeaveRequest(String requestId) async {
    await _sb
        .from('join_requests')
        .update({'status': 'approved'}).eq('id', requestId);
  }

  /// Ағымдағы сатушының join_requests статусы (leave_pending/approved/removed/...).
  Stream<String?> watchOwnJoinRequestStatus() {
    final uid = _sb.auth.currentUser?.id ?? '';
    if (uid.isEmpty) return Stream.value(null);
    return _sb
        .from('join_requests')
        .stream(primaryKey: ['id'])
        .eq('seller_uid', uid)
        .map((rows) {
          final mine =
              rows.where((d) => d['admin_uid'] == AppUser.current.ownerUid);
          return mine.isEmpty ? null : mine.first['status'] as String?;
        });
  }

  /// Owner сатушыны шығарған соң ('removed') true — SellerShell мәжбүрлі
  /// логаут үшін тыңдайды: owner_id/join_status ағымдағы сессияда реактивті
  /// емес (тек келесі кіруде _loadSession арқылы жаңарады).
  Stream<bool> watchOwnRemoval() =>
      watchOwnJoinRequestStatus().map((status) => status == 'removed');

  Stream<List<Map<String, dynamic>>> watchLeaveRequests() => _sb
      .from('join_requests')
      .stream(primaryKey: ['id'])
      .eq('admin_uid', _adminUid)
      .map((rows) => rows
          .where((d) => d['status'] == 'leave_pending')
          .map((d) => {
                'id': d['id'],
                'sellerId': d['seller_uid'],
                'sellerName': d['seller_name'],
                'sellerEmail': d['seller_email'],
              })
          .toList());

  Stream<List<Map<String, dynamic>>> watchActiveSellers() => _sb
      .from('users')
      .stream(primaryKey: ['id'])
      .eq('owner_id', _adminUid)
      .map((rows) => rows
          .where((d) => d['role'] == 'seller' && d['join_status'] == 'active')
          .map((d) => {
                'id': d['id'],
                'uid': d['id'],
                'name': d['name'],
                'email': d['email'],
                'role': d['role'],
                'assignedWarehouseId': d['assigned_warehouse_id'],
                'joinStatus': d['join_status'],
                'businessCode': d['business_code'],
              })
          .toList());

  Stream<List<Map<String, dynamic>>> watchPendingRequests() => _sb
      .from('join_requests')
      .stream(primaryKey: ['id'])
      .eq('admin_uid', _adminUid)
      .map((rows) {
        final docs = rows
            .where((d) => d['status'] == 'pending')
            .map((d) => {
                  'id': d['id'],
                  'sellerId': d['seller_uid'],
                  'sellerUid': d['seller_uid'],
                  'sellerName': d['seller_name'],
                  'sellerEmail': d['seller_email'],
                  'adminUid': d['admin_uid'],
                  'status': d['status'],
                  'requestedAt': d['created_at'],
                })
            .toList();
        docs.sort((a, b) => (b['requestedAt'] as String? ?? '')
            .compareTo(a['requestedAt'] as String? ?? ''));
        return docs;
      });

  // ── Transfers ─────────────────────────────────────────────────────────────────

  Stream<List<Map<String, dynamic>>> watchTransfers() => _sb
      .from('transfers')
      .stream(primaryKey: ['id'])
      .eq('owner_uid', _ownerUid)
      .order('created_at', ascending: false)
      .map((rows) => rows
          .map((d) => {
                'id': d['id'],
                'fromWarehouseId': d['from_warehouse_id'],
                'toWarehouseId': d['to_warehouse_id'],
                'productId': d['product_id'],
                'productName': d['product_name'],
                'sizes': d['sizes'],
                'totalQuantity': d['total_quantity'],
                'performedBy': d['performed_by'],
                'createdAt': d['created_at'],
              })
          .toList());

  Future<void> transferStock({
    required String fromWarehouseId,
    required String toWarehouseId,
    required String productId,
    required String productName,
    required Map<String, int> sizes,
  }) async {
    final owner = _ownerUid;
    // Көздегі ескі→жаңа партиялар (FIFO) бойынша азайтамыз.
    final srcRows = await _sb
        .from('batches')
        .select()
        .eq('product_id', productId)
        .eq('warehouse_id', fromWarehouseId)
        .order('date_arrived', ascending: true);
    if (srcRows.isEmpty) {
      throw SaleException(tr('Недостаточно остатка', 'Қалдық жеткіліксіз'));
    }

    final double transferCost =
        await resolveBatchCost(owner, srcRows.first['id'] as String);
    final remaining = Map<String, int>.from(sizes);
    for (final b in srcRows) {
      final bid = b['id'] as String;
      final bSizes = Map<String, int>.from(((b['sizes_quantity'] as Map?) ?? {})
          .map((k, v) => MapEntry(k.toString(), (v as num).toInt())));
      final deltas = <String, int>{};
      for (final size in remaining.keys.toList()) {
        final needed = remaining[size]!;
        if (needed <= 0) continue;
        final have = bSizes[size] ?? 0;
        if (have <= 0) continue;
        final take = needed > have ? have : needed;
        deltas[size] = -take;
        remaining[size] = needed - take;
      }
      if (deltas.isNotEmpty) {
        await _sb.rpc('adjust_batch_sizes', params: {
          'p_batch': bid,
          'p_deltas': deltas,
          'p_field': 'sizes_quantity',
          'p_guard': true,
        });
      }
      if (remaining.values.every((v) => v == 0)) break;
    }
    if (remaining.values.any((v) => v > 0)) {
      throw SaleException(tr('Недостаточно остатка', 'Қалдық жеткіліксіз'));
    }

    final sellingPrice =
        (srcRows.first['selling_price'] as num?)?.toDouble() ?? 0;
    final newBatch = await _sb
        .from('batches')
        .insert({
          'product_id': productId,
          'owner_uid': owner,
          'warehouse_id': toWarehouseId,
          'selling_price': sellingPrice,
          'sizes_quantity': sizes,
          'date_arrived': DateTime.now().toIso8601String(),
        })
        .select('id')
        .single();
    await _sb.from('batch_costs').insert({
      'batch_id': newBatch['id'] as String,
      'owner_uid': owner,
      'product_id': productId,
      'purchase_price': transferCost,
    });
    await _sb.from('transfers').insert({
      'owner_uid': owner,
      'from_warehouse_id': fromWarehouseId,
      'to_warehouse_id': toWarehouseId,
      'product_id': productId,
      'product_name': productName,
      'sizes': sizes,
      'total_quantity': sizes.values.fold(0, (a, b) => a + b),
      'performed_by': _sb.auth.currentUser?.id,
    });
  }

  // ── Store ─────────────────────────────────────────────────────────────────────

  Future<StoreModel?> getStore() async {
    final row = await _sb
        .from('stores')
        .select()
        .eq('admin_uid', _adminUid)
        .maybeSingle();
    return row == null ? null : StoreModel.fromMap(row);
  }

  Stream<StoreModel?> watchStore() => _sb
      .from('stores')
      .stream(primaryKey: ['admin_uid'])
      .eq('admin_uid', _adminUid)
      .map((rows) => rows.isEmpty ? null : StoreModel.fromMap(rows.first));

  Future<void> saveStore(StoreModel store) =>
      _sb.from('stores').upsert({...store.toMap(), 'admin_uid': _adminUid});

  // ── Дүкеннің жарнама push-ы (0043) ───────────────────────────────────────────

  /// Соңғы жіберілген хабарлама (аптасына 1 рет шектеу — UI-де көрсету үшін,
  /// нақты шектеу БД триггерінде). null — әлі ешқашан жібермеген.
  Future<DateTime?> getLastBroadcastAt() async {
    final row = await _sb
        .from('store_broadcasts')
        .select('created_at')
        .eq('admin_uid', _adminUid)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    if (row == null) return null;
    return DateTime.tryParse(row['created_at'] as String? ?? '');
  }

  Future<List<Map<String, dynamic>>> getBroadcastHistory() async {
    final rows = await _sb
        .from('store_broadcasts')
        .select()
        .eq('admin_uid', _adminUid)
        .order('created_at', ascending: false)
        .limit(20);
    return List<Map<String, dynamic>>.from(rows);
  }

  /// Триггер (0043) аптасына 1 реттен жиі жіберсе PostgrestException
  /// 'broadcast_rate_limited' хабарымен лақтырады — UI сол жолды тексереді.
  Future<void> sendStoreBroadcast(
          {required String title, required String body}) =>
      _sb.from('store_broadcasts').insert({
        'admin_uid': _adminUid,
        'title': title.trim(),
        'body': body.trim(),
      });

  /// Дүкен жолындағы тек берілген өрістерді жаңартады (басқа өрістерді
  /// ескірген локалды StoreModel-мен қайта жазып жібермеу үшін —
  /// saveStore толық upsert жасайды, ал бұл нақты өрістерге ғана тиеді).
  Future<void> updateStoreFields(Map<String, dynamic> fields) =>
      _sb.from('stores').update({
        ...fields,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('admin_uid', _adminUid);

  // ── Reservations ───────────────────────────────────────────────────────────────

  Future<void> createReservation(ReservationModel reservation) =>
      _sb.from('reservations').insert(reservation.toMap());

  Future<void> releaseReservation(String reservationId) => _sb
      .from('reservations')
      .update({'status': ReservationModel.statusExpired}).eq(
          'id', reservationId);

  Stream<List<ReservationModel>> watchActiveReservations() =>
      retryStream(() => _sb
          .from('reservations')
          .stream(primaryKey: ['id'])
          .eq('admin_uid', _adminUid)
          .map((rows) => rows
              .map(ReservationModel.fromMap)
              .where((r) =>
                  r.status == ReservationModel.statusActive &&
                  r.expiresAt.isAfter(DateTime.now()))
              .toList()));

  Future<void> cleanupExpiredReservations() async {
    await _sb
        .from('reservations')
        .update({'status': ReservationModel.statusExpired})
        .eq('status', ReservationModel.statusActive)
        .lt('expires_at', DateTime.now().toIso8601String());
  }

  // ── Product status recomputation ─────────────────────────────────────────────

  Future<void> recomputeProductStatus(String productId) =>
      _sb.rpc('recompute_product_status', params: {'p_product': productId});

  Future<void> recomputeAllProductStatuses() async {
    final rows =
        await _sb.from('products').select('id').eq('owner_uid', _ownerUid);
    for (final p in rows) {
      await recomputeProductStatus(p['id'] as String);
    }
  }

  /// Таза бастауда көшіретін ескі дерек жоқ — no-op (үйлесімділік үшін қалды).
  Future<int> migrateBatchCosts() async => 0;

  // ── Online orders ─────────────────────────────────────────────────────────────

  Stream<int> watchActiveOnlineCount() => watchOnlineOrders().map((orders) =>
      orders
          .where((o) =>
              o.status == OrderModel.statusPending ||
              o.status == OrderModel.statusReserved ||
              o.status == OrderModel.statusRejected ||
              o.status == OrderModel.statusConfirmed)
          .length);

  Stream<List<OrderModel>> watchOnlineOrders() => retryStream(() => _sb
      .from('orders')
      .stream(primaryKey: ['id'])
      .eq('admin_uid', _adminUid)
      .order('created_at', ascending: false)
      .map((rows) => rows.map(OrderModel.fromMap).toList()));

  /// Модератор (superadmin) — БАРЛЫҚ дүкендердің онлайн-тапсырыстары.
  /// RLS: superadmin барлық orders жолдарын оқи алуы керек (0024 миграция).
  Stream<List<OrderModel>> watchAllOnlineOrders() => retryStream(() => _sb
      .from('orders')
      .stream(primaryKey: ['id'])
      .order('created_at', ascending: false)
      .map((rows) => rows.map(OrderModel.fromMap).toList()));

  Future<OrderModel?> lookupOnlineOrder(String code) async {
    final num = int.tryParse(code.replaceAll('#', '').trim());
    if (num == null) return null;
    try {
      // admin_uid бойынша шектелген — order_number бұрын хэштен жасалатын
      // (ID-дан), сондықтан басқа дүкенде сол сан қайталанып, дұрыс емес
      // тапсырыс табылуы мүмкін еді. Енді реттік болса да, шектеу сақталады —
      // сатушы/әкімші тек ӨЗ дүкенінің тапсырысын іздеуі керек.
      final row = await _sb
          .from('orders')
          .select()
          .eq('admin_uid', _adminUid)
          .eq('order_number', num)
          .limit(1)
          .maybeSingle();
      return row == null ? null : OrderModel.fromMap(row);
    } catch (_) {
      return null;
    }
  }

  Future<OrderModel?> findActiveReservationForSize({
    required String productId,
    required String batchId,
    required String size,
  }) async {
    final rows = await _sb
        .from('orders')
        .select()
        .eq('admin_uid', _adminUid)
        .eq('order_type', OrderModel.typeSmartReservation);
    for (final r in rows) {
      final o = OrderModel.fromMap(r);
      if (o.status == OrderModel.statusCompleted ||
          o.status == OrderModel.statusCancelled ||
          o.status == OrderModel.statusReturned) {
        continue;
      }
      if (o.items.any((i) =>
          i.productId == productId && i.batchId == batchId && i.size == size)) {
        return o;
      }
    }
    return null;
  }

  // ── Тапсырыс статусын атомдық ауыстыру (race condition түзету, 0030) ────────
  // Қатарды серверде `for update` LOCK-тап, ағымдағы статусты тексереді.
  // Екі жақтан бір мезетте шақырылса — біреуі сәтті ауыстырады, екіншісі
  // ЖАҢА статусты көріп, ешбір side-effect (қойма/sales_history) орындамай,
  // түсінікті қатемен тоқтайды. Осыдан кейінгі бүкіл жазу — «жеңген» жаққа
  // ғана тиесілі, сондықтан қауіпсіз орындалады.
  Future<void> _claimOrder(
    String orderId,
    List<String> expected,
    String newStatus, {
    String actorRole = '',
    String actorUid = '',
    String actorName = '',
  }) async {
    try {
      await _sb.rpc('claim_order_transition', params: {
        'p_order': orderId,
        'p_expected': expected,
        'p_new_status': newStatus,
        'p_actor_role': actorRole,
        'p_actor_uid': actorUid,
        'p_actor_name': actorName,
      });
    } on PostgrestException catch (e) {
      if (e.message.contains('order_state_changed') ||
          e.message.contains('order_not_found')) {
        throw Exception(tr(
          'Заказ уже обработан — обновите список',
          'Тапсырыс өңделіп қойды — тізімді жаңартыңыз',
        ));
      }
      rethrow;
    }
  }

  // ── Payment receipt flow ─────────────────────────────────────────────────────

  Future<void> submitReceipt(OrderModel o, String receiptUrl) async {
    await _claimOrder(
        o.id,
        const [OrderModel.statusPending, OrderModel.statusRejected],
        OrderModel.statusPending);
    await _sb.from('orders').update({
      'receipt_url': receiptUrl,
      'receipt_submitted_at': DateTime.now().toIso8601String(),
      'rejection_reason': '',
      'rejected_at': null,
      'deadline_at': null,
    }).eq('id', o.id);
  }

  Future<void> resubmitReceipt(OrderModel o, String receiptUrl) =>
      submitReceipt(o, receiptUrl);

  /// Бронь депозитінің чегін дүкен иесі растады → reserved (1 сағат алу мерзімі).
  /// Барлық онлайн-төлем — модератор картасына аударым ('card').
  Future<void> confirmReservationDeposit(OrderModel o) async {
    await _claimOrder(
        o.id, const [OrderModel.statusPending], OrderModel.statusReserved);
    await _sb.from('orders').update({
      'payment_bank': 'card',
      'payment_confirmed_by': AppUser.current.uid,
      'payment_confirmed_at': DateTime.now().toIso8601String(),
      'deadline_at':
          DateTime.now().add(OrderModel.pickupWindow).toIso8601String(),
    }).eq('id', o.id);
  }

  /// Толық төлем чегін дүкен иесі растады → confirmed (беруге дайын).
  Future<void> confirmOnlinePayment(OrderModel o) async {
    await _claimOrder(
        o.id, const [OrderModel.statusPending], OrderModel.statusConfirmed);
    await _sb.from('orders').update({
      'payment_bank': 'card',
      'payment_confirmed_by': AppUser.current.uid,
      'payment_confirmed_at': DateTime.now().toIso8601String(),
      'deadline_at': null,
    }).eq('id', o.id);
  }

  Future<void> rejectReceipt(OrderModel o, String reason) async {
    await _claimOrder(
        o.id, const [OrderModel.statusPending], OrderModel.statusRejected);
    await _sb.from('orders').update({
      'rejection_reason': reason,
      'rejected_at': DateTime.now().toIso8601String(),
      'deadline_at':
          DateTime.now().add(OrderModel.receiptWindow).toIso8601String(),
    }).eq('id', o.id);
  }

  Future<void> confirmInStorePayment(OrderModel o,
      {String paymentMethod = 'cash'}) async {
    await _claimOrder(
        o.id, const [OrderModel.statusPending], OrderModel.statusConfirmed);
    await _sb.from('orders').update({
      'payment_confirmed_by': AppUser.current.uid,
      'payment_confirmed_at': DateTime.now().toIso8601String(),
      'in_store_payment_method': paymentMethod,
      'deadline_at': null,
    }).eq('id', o.id);
  }

  Future<void> handOverWithDoplate(OrderModel order, String doplaMethod,
          {List<int> swappedIndexes = const []}) =>
      _completeOrder(
        order.copyWith(inStorePaymentMethod: doplaMethod),
        expected: const [OrderModel.statusReserved],
        swappedIndexes: swappedIndexes,
      );

  /// [swappedIndexes] — «өлшеп көру» позицияларының items ішіндегі
  /// индекстері, ОНДА клиент негізгі емес, ҚОСАЛҚЫ (altSize) өлшемді алып
  /// кеткен. Дүкен/сатушы курьерсіз өзі бергенде де осы ақпарат керек —
  /// әйтпесе қойма/сатылым қате есептеледі (бұрынғы қате: әрқашан негізгі
  /// өлшем сатылды деп есептелетін).
  /// Сыйлық тапсырысының базадағы ең соңғы күйі (басқа құрылғыдан ауыстыру
  /// болған болуы мүмкін). Сыйлық емес болса — сол күйі қайтады.
  Future<OrderModel> freshGiftOrder(OrderModel o) async {
    if (!o.isGift) return o;
    final row = await _sb.from('orders').select().eq('id', o.id).maybeSingle();
    return row == null ? o : OrderModel.fromMap(row);
  }

  Future<void> markHandedOver(OrderModel order,
          {List<int> swappedIndexes = const []}) =>
      _completeOrder(order,
          expected: const [OrderModel.statusConfirmed],
          swappedIndexes: swappedIndexes);

  /// «Өлшеп көру» кезінде клиент таңдамаған өлшемді курьер қоймаға әкелді —
  /// дүкен қабылдады (0052). ТЕК осы сәтте қалдық қайта қолжетімді болады:
  /// оған дейін тауар физикалық түрде курьерде, жолда.
  Future<void> confirmReturnLeg(OrderModel order) =>
      _sb.rpc('store_confirm_return_leg', params: {'p_order': order.id});

  Future<void> confirmOnlineOrder(OrderModel order,
          {List<int> swappedIndexes = const []}) =>
      _completeOrder(order,
          expected: const [OrderModel.statusPending, OrderModel.statusReserved],
          swappedIndexes: swappedIndexes);

  /// Online тапсырысты аяқтайды: бронь болса қойманы азайтады, sales_history
  /// жазады, статусты completed қылады, чек нөмірін береді. [expected] —
  /// шақырылған жол бойынша нақты рұқсат етілген бастапқы статус(тар).
  Future<void> _completeOrder(OrderModel orderIn,
      {required List<String> expected,
      List<int> swappedIndexes = const []}) async {
    // 🎁 Сыйлық: экран ашылған соң басқа құрылғыдан ауыстыру болып, қосымша
    // төлем (gift_extra_due) өзгерсе — беруді тоқтатамыз, әйтпесе айырма
    // алынбай/тәсілі сұралмай қалады. Экран жаңартылып, қайта басылады.
    if (orderIn.isGift) {
      final fresh = await freshGiftOrder(orderIn);
      if (fresh.giftExtraDue != orderIn.giftExtraDue ||
          (fresh.items.isNotEmpty &&
              orderIn.items.isNotEmpty &&
              (fresh.items.first.productId != orderIn.items.first.productId ||
                  fresh.items.first.size != orderIn.items.first.size))) {
        throw Exception(tr(
            'Подарок только что изменён (обмен). Обновите список и повторите выдачу.',
            'Сыйлық жаңа ғана өзгертілді (ауыстыру). Тізімді жаңартып, қайта беріңіз.'));
      }
    }
    await _claimOrder(orderIn.id, expected, OrderModel.statusCompleted);
    var order = orderIn;
    // 🎁 Сыйлық (0070): позицияны алушы/дүкен ауыстырған болуы мүмкін (басқа
    // өлшем/тауар, қосымша төлем). Экрандағы көшірме ескірсе, сатылым тарихы
    // ескі тауармен жазылар еді — сондықтан базадан жаңасын оқимыз.
    if (orderIn.isGift) {
      final row =
          await _sb.from('orders').select().eq('id', orderIn.id).maybeSingle();
      if (row != null) {
        order = OrderModel.fromMap(row).copyWith(
            inStorePaymentMethod: orderIn.inStorePaymentMethod.isNotEmpty
                ? orderIn.inStorePaymentMethod
                : null);
      }
    }
    final seller = AppUser.current;
    // Онлайн-тапсырыстың чегіне БӨЛЕК санақ бермейміз — тапсырыс клиентке,
    // әкімшіге, сатушыға әлдеқашан белгілі order_number-ді қайталаймыз, әйтпесе
    // «неге чекте басқа нөмір» деген түсініксіздік туады (админ мен сатушы
    // бірдей операцияны екі түрлі санмен көрер еді).
    final receipt = order.orderNumber > 0
        ? '#${order.orderNumber.toString().padLeft(5, '0')}'
        : await nextReceiptNumber();

    final priceByBatch = <String, double>{};
    for (final item in order.items) {
      priceByBatch['${item.productId}_${item.batchId}'] =
          await resolveBatchCost(item.adminUid, item.batchId);
    }

    // Бронь: қойма + резервтен азайту.
    if (order.isSmartReservation) {
      for (final item in order.items) {
        await _sb.rpc('adjust_batch_sizes', params: {
          'p_batch': item.batchId,
          'p_deltas': {item.size: -item.qty},
          'p_field': 'sizes_quantity',
          'p_guard': false,
        });
        await _sb.rpc('adjust_batch_sizes', params: {
          'p_batch': item.batchId,
          'p_deltas': {item.size: -item.qty},
          'p_field': 'reserved_sizes',
          'p_guard': false,
        });
      }
    }

    // «Өлшеп көру»: [swappedIndexes] бойынша своп есептеледі — қосалқы
    // өлшемді алған позиция САТЫЛДЫ (қоймадан шығады), негізгі өлшем ДӘЛ
    // ҚАЗІР дүкенге қайтады (курьер жоқ, кідіріс керек емес). release_fitting_holds-тан
    // айырмашылығы — бұл своп-хабардар (0064).
    if (order.hasFitting) {
      try {
        await _sb.rpc('store_handover_fitting',
            params: {'p_order': order.id, 'p_swaps': swappedIndexes});
      } catch (_) {}
    }

    await _sb.from('orders').update({
      'delivered_by_uid': seller.uid,
      'delivered_by_name': seller.name,
      'seller_id': 'онлайн',
      'seller_name': 'Онлайн',
      'receipt_number': receipt,
      // Аяқталған тапсырыста дедлайн қалмауы керек — әйтпесе клиент экраны
      // оны «мерзімі өтті» деп қате авто-болдырмайды.
      'deadline_at': null,
      // handOverWithDoplate жолында ғана толтырылады (бронь доплатасы).
      if (order.inStorePaymentMethod.isNotEmpty)
        'in_store_payment_method': order.inStorePaymentMethod,
    }).eq('id', order.id);

    final promoFactor = order.total > 0 ? order.finalTotal / order.total : 1.0;
    // Онлайн-төлем әрқашан картаға аударым ('card') — тарихта «Оплата картой»
    // болып көрінеді. Бронь доплатасы — дүкенде qolma-qol/kaspi.
    // 🎁 Сыйлықтың қосымша төлемі (gift_extra_due) дүкенде алынады — бронь
    // доплатасымен бірдей жазамыз: payment_method = дүкендегі тәсіл,
    // deposit_payment_method = онлайн төленген бөлік (карта).
    final inStoreTopUp = order.isSmartReservation ||
        (order.isGift &&
            order.giftExtraDue > 0 &&
            order.inStorePaymentMethod.isNotEmpty);
    final payMethod = inStoreTopUp
        ? (order.inStorePaymentMethod.isNotEmpty
            ? order.inStorePaymentMethod
            : '')
        : (order.paymentBank.isNotEmpty ? order.paymentBank : 'card');
    final depositMethod = inStoreTopUp
        ? (order.paymentBank.isNotEmpty ? order.paymentBank : 'card')
        : '';

    final sales = <Map<String, dynamic>>[];
    for (var idx = 0; idx < order.items.length; idx++) {
      final item = order.items[idx];
      // Своп болса — іс жүзінде сатылған өлшем altSize, item.size емес
      // (store_handover_fitting дәл осылай қоймадан шығарады).
      final soldSize = swappedIndexes.contains(idx) && item.hasAltSize
          ? item.altSize
          : item.size;
      sales.add({
        'owner_uid': order.adminUid,
        'product_id': item.productId,
        'batch_id': item.batchId,
        'seller_id': 'онлайн',
        'seller_name': 'Онлайн',
        'is_online': true,
        'order_id': order.id,
        'delivered_by_name': seller.name,
        'base_price': item.originalSubtotal,
        'total_price': item.subtotal * promoFactor,
        'discount_amount': item.originalSubtotal - item.subtotal * promoFactor,
        'quantity': item.qty,
        'selected_size': soldSize,
        'sizes_sold': {soldSize: item.qty},
        'sale_date': DateTime.now().toIso8601String(),
        'warehouse_id': order.warehouseId.isEmpty ? null : order.warehouseId,
        'product_name': item.productName,
        'purchase_price':
            priceByBatch['${item.productId}_${item.batchId}'] ?? 0,
        'payment_method': payMethod,
        'deposit_payment_method': depositMethod,
        'receipt_number': receipt,
        'type': 'sale',
      });
    }
    // ── Қызмет кірістері (0053) — тауарсыз, quantity = 0 ────────────────────
    //  Серверлік `courier_complete_order` мұны өзі жазады; бұл жол дүкен
    //  тапсырысты ӨЗІ берген жағдайға арналған (курьерсіз). Екеуі бір пішімде
    //  болуы шарт, әйтпесе аналитика екі түрлі сан көрсетеді.
    final services = <Map<String, dynamic>>[];
    void addService(String name, double amount) {
      if (amount <= 0) return;
      services.add({
        'owner_uid': order.adminUid,
        'product_id': null,
        'batch_id': null,
        'seller_id': 'онлайн',
        'seller_name': 'Онлайн',
        'is_online': true,
        'order_id': order.id,
        'delivered_by_name': seller.name,
        'base_price': amount,
        'total_price': amount,
        'discount_amount': 0,
        'quantity': 0,
        'selected_size': '',
        'sizes_sold': <String, int>{},
        'sale_date': DateTime.now().toIso8601String(),
        'warehouse_id': order.warehouseId.isEmpty ? null : order.warehouseId,
        'product_name': name,
        'purchase_price': 0,
        'payment_method': payMethod,
        'deposit_payment_method': depositMethod,
        'receipt_number': receipt,
        'type': 'service',
      });
    }

    addService('Примерка / Өлшеп көру', order.fittingFee);
    // Жеткізу ақысы ӘДЕТТЕ курьердікі. Бірақ мұнда курьер жоқ — дүкен өзі
    // жеткізді, ақыны да өзі алды. Сондықтан ол дүкеннің қызмет кірісі.
    if (!order.hasCourier) {
      addService('Доставка магазином / Дүкен жеткізуі', order.deliveryFee);
      if (order.deliveryFee > 0) {
        try {
          await _sb.from('orders').update({
            'delivery_fee_collected': true,
            'delivery_fee_collected_at': DateTime.now().toIso8601String(),
          }).eq('id', order.id);
        } catch (_) {}
      }
    }
    if (services.isNotEmpty) {
      await _sb.from('sales_history').insert(services);
    }

    if (sales.isNotEmpty) await _sb.from('sales_history').insert(sales);

    for (final pid in order.items.map((i) => i.productId).toSet()) {
      await recomputeProductStatus(pid);
    }
  }

  /// Тапсырысты бас тарту + қойманы қалпына келтіру. [actorRole] — кім
  /// болдырмағаны (admin/seller/system-авто-мерзім) клиентке/басқа тарапқа
  /// «кім отменил» деп көрсету үшін жазылады (0030 — cancelled_by_*).
  /// Claim сәтті болмаса (тапсырыс бұрын аяқталған/болдырылған) — ешбір
  /// қойма/промокод жазбасы жүрмейді (race condition түзетілген).
  Future<void> cancelOnlineOrder(
    OrderModel order, {
    String actorRole = 'admin',
    String? actorUid,
    String? actorName,
  }) async {
    await _claimOrder(
      order.id,
      const [
        OrderModel.statusPending,
        OrderModel.statusReserved,
        OrderModel.statusRejected,
        OrderModel.statusConfirmed,
      ],
      OrderModel.statusCancelled,
      actorRole: actorRole,
      actorUid: actorUid ?? AppUser.current.uid,
      actorName: actorName ?? AppUser.current.name,
    );

    final oRow = await _sb
        .from('orders')
        .select(
            'promo_counts_usage,promo_id,client_uid,stock_restored,is_gift,items')
        .eq('id', order.id)
        .maybeSingle();
    if (oRow == null) return;

    // 🎁 Сыйлық (0070): алушы өлшем таңдамаған сыйлықта қойма ҰСТАЛМАҒАН
    // (stock_restored = true) — қайтаратын ештеңе жоқ (batchId бос). Таңдалған
    // сыйлықта локалды `order` ескірген болуы мүмкін → позицияларды базадан аламыз.
    final stockAlreadyBack = (oRow['stock_restored'] as bool? ?? false);
    final restoreItems = (oRow['is_gift'] as bool? ?? false)
        ? ((oRow['items'] as List?) ?? const [])
            .map((e) => CartItemModel.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : order.items;

    for (final item
        in stockAlreadyBack ? const <CartItemModel>[] : restoreItems) {
      try {
        await _sb.rpc('adjust_batch_sizes', params: {
          'p_batch': item.batchId,
          'p_deltas': {item.size: item.qty},
          'p_field':
              order.isSmartReservation ? 'reserved_sizes' : 'sizes_quantity',
          'p_guard': false,
        });
      } on PostgrestException catch (e) {
        // Партия өшірілген болуы мүмкін (мыс. модератор жойған) — қалпына
        // келтіретін ештеңе жоқ, бірақ тапсырысты болдырмау бөгелмеуі керек.
        if (!e.message.contains('batch_not_found')) rethrow;
      }
    }

    // «Өлшеп көру» броні де босайды (0050). Сыйлықта қосалқы өлшемді алушы
    // кейін қосады — локалды көшірмеде болмауы мүмкін, сондықтан базадағы
    // позициялар бойынша тексереміз.
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

    for (final pid in order.items.map((i) => i.productId).toSet()) {
      await recomputeProductStatus(pid);
    }
  }
}

class SaleException implements Exception {
  final String message;
  const SaleException(this.message);
  @override
  String toString() => 'SaleException: $message';
}

class ProductWithStock {
  final ProductModel product;
  final int pairs;
  const ProductWithStock({required this.product, required this.pairs});
}

// ── Pull-to-refresh helpers (Supabase realtime — нақты refresh қажет емес) ─────
extension RefreshX on FirestoreService {
  Future<void> refreshProducts() async {}
  Future<void> refreshSalesHistory() async {}
  Future<void> refreshOnlineOrders() async {}
  Future<void> refreshWarehouses() async {}
}

// ── Returns ────────────────────────────────────────────────────────────────────
extension ReturnsX on FirestoreService {
  /// 'requested' күйіндегі қайтарулар саны (AdminHome badge).
  Stream<int> watchNewReturnsCount() =>
      Supabase.instance.client.from('returns').stream(primaryKey: ['id']).map(
          (rows) => rows.where((r) => r['status'] == 'requested').length);
}

class _ProductsCache {
  static List<ProductModel>? _data;
  static DateTime? _at;

  static List<ProductModel>? get() {
    if (_data == null || _at == null) return null;
    if (DateTime.now().difference(_at!).inSeconds > 30) return null;
    return _data;
  }

  static void set(List<ProductModel> p) {
    _data = p;
    _at = DateTime.now();
  }
}
