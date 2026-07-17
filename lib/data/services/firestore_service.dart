import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart';
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
import '../../core/stream_retry.dart';

import '../../core/lang.dart';
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
    if (uid.isEmpty) throw Exception(tr('Пользователь не авторизован.', 'Пайдаланушы авторизацияланбаған.'));
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
    final articul = 'QM-${productId.substring(0, 6).toUpperCase()}';
    await _sb.from('products').update({
      'articul': articul,
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

  Future<String?> findMatchingProduct({
    required String name,
    required String brand,
    required String type,
    required String material,
    required String category,
    required String color,
  }) async {
    final rows = await _sb
        .from('products')
        .select()
        .eq('owner_uid', _ownerUid)
        .eq('name', name.trim())
        .eq('brand', brand.trim());
    for (final r in rows) {
      final p = ProductModel.fromMap(r);
      if (p.type == type &&
          p.material == material &&
          p.category == category &&
          p.color == color) {
        return p.id;
      }
    }
    return null;
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
    await _sb.from('products').update({'images': imageUrls}).eq('id', productId);
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
  }) =>
      _sb.from('products').update({
        'name': name.trim(),
        'brand': brand.trim(),
        'type': type,
        'material': material,
        'category': category,
        'color': color,
        'description': description.trim(),
        'country': country.trim(),
        'season': season,
      }).eq('id', productId);

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
    await _sb
        .from('batches')
        .update({'discount': discount.toMapJson()}).inFilter(
            'product_id', productIds);
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
    if (code.isEmpty) throw SaleException(tr('Введите код промокода', 'Промокод кодын енгізіңіз'));
    if (!await isPromoCodeUnique(code)) {
      throw SaleException(tr('Такой промокод уже существует', 'Мұндай промокод бұрыннан бар'));
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

  Future<void> deletePromo(String promoId) =>
      _sb.from('promos').delete().eq('id', promoId);

  Future<void> updatePromo(PromoModel promo) async {
    final code = promo.code.trim().toUpperCase();
    if (!await isPromoCodeUnique(code, exceptId: promo.id)) {
      throw SaleException(tr('Такой промокод уже существует', 'Мұндай промокод бұрыннан бар'));
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
      throw SaleException(
          tr('По этой партии есть продажи. Партия не удалена, а перемещена в архив — аналитика сохранена.', 'Бұл партия бойынша сатылымдар бар. Партия өшірілмеді, архивке жылжытылды — аналитика сақталды.'));
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
        throw SaleException(tr('Недостаточно остатка на складе.', 'Қоймада қалдық жеткіліксіз.'));
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
            .where((s) =>
                !s.saleDate.isBefore(from) && s.saleDate.isBefore(to))
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
      throw SaleException(tr('Укажите количество недостачи', 'Жетіспеушілік санын көрсетіңіз'));
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
      throw SaleException(tr('Недостаточно остатка для списания', 'Списаниеге қалдық жеткіліксіз'));
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
      throw SaleException(tr('Недостаточно остатка для списания', 'Списаниеге қалдық жеткіліксіз'));
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
    await _sb.rpc('recompute_product_status', params: {'p_product': rev.productId});
  }

  Future<(Map<String, List<BatchModel>>, Map<String, String>)>
      getAllBatchesGrouped() async {
    final owner = _ownerUid;
    final prods =
        await _sb.from('products').select('id,name').eq('owner_uid', owner);
    final allBatches = await _sb.from('batches').select().eq('owner_uid', owner);
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

  Future<List<SaleModel>> getSalesForProduct(String productId) async {
    final rows = await _sb
        .from('sales_history')
        .select()
        .eq('product_id', productId)
        .order('sale_date', ascending: false);
    return rows.map(SaleModel.fromMap).toList();
  }

  Future<double> getTotalRevenue({DateTime? from, DateTime? to}) async {
    var q =
        _sb.from('sales_history').select('total_price').eq('owner_uid', _ownerUid);
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
      watchProductsWithBatches({String warehouseId = ''}) => retryStream(() => _sb
          .from('products')
          .stream(primaryKey: ['id'])
          .eq('owner_uid', _ownerUid)
          .order('name', ascending: true)
          .asyncMap((prows) async {
            final products = prows.map(ProductModel.fromMap).toList();
            var bq = _sb.from('batches').select().eq('owner_uid', _ownerUid);
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
            final out = <({ProductModel product, List<BatchModel> batches})>[];
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

    final codeDoc = await _sb
        .from('business_codes')
        .select('admin_uid')
        .eq('code', businessCode.trim().toUpperCase())
        .maybeSingle();
    if (codeDoc == null) {
      throw tr('Бизнес-код не найден. Введите корректный код.', 'Бизнес-код табылмады. Дұрыс кодты енгізіңіз.');
    }
    final adminUid = codeDoc['admin_uid'] as String?;
    if (adminUid == null || adminUid.isEmpty) {
      throw tr('Код недействителен. Обратитесь к владельцу магазина.', 'Код жарамсыз. Дүкен иесіне хабарлаңыз.');
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
    if (srcRows.isEmpty) throw SaleException(tr('Недостаточно остатка', 'Қалдық жеткіліксіз'));

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
    final row =
        await _sb.from('stores').select().eq('admin_uid', _adminUid).maybeSingle();
    return row == null ? null : StoreModel.fromMap(row);
  }

  Stream<StoreModel?> watchStore() => _sb
      .from('stores')
      .stream(primaryKey: ['admin_uid'])
      .eq('admin_uid', _adminUid)
      .map((rows) => rows.isEmpty ? null : StoreModel.fromMap(rows.first));

  Future<void> saveStore(StoreModel store) =>
      _sb.from('stores').upsert({...store.toMap(), 'admin_uid': _adminUid});

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

  Future<OrderModel?> lookupOnlineOrder(String code) async {
    final num = int.tryParse(code.replaceAll('#', '').trim());
    if (num == null) return null;
    try {
      final row = await _sb
          .from('orders')
          .select()
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

  // ── Payment receipt flow ─────────────────────────────────────────────────────

  Future<void> submitReceipt(OrderModel o, String receiptUrl) =>
      _sb.from('orders').update({
        'receipt_url': receiptUrl,
        'receipt_submitted_at': DateTime.now().toIso8601String(),
        'status': OrderModel.statusPending,
        'rejection_reason': '',
        'rejected_at': null,
        'deadline_at': null,
      }).eq('id', o.id);

  Future<void> resubmitReceipt(OrderModel o, String receiptUrl) =>
      submitReceipt(o, receiptUrl);

  /// Бронь депозитінің чегін дүкен иесі растады → reserved (1 сағат алу мерзімі).
  /// Барлық онлайн-төлем — модератор картасына аударым ('card').
  Future<void> confirmReservationDeposit(OrderModel o) =>
      _sb.from('orders').update({
        'status': OrderModel.statusReserved,
        'payment_bank': 'card',
        'payment_confirmed_by': AppUser.current.uid,
        'payment_confirmed_at': DateTime.now().toIso8601String(),
        'deadline_at':
            DateTime.now().add(OrderModel.pickupWindow).toIso8601String(),
      }).eq('id', o.id);

  /// Толық төлем чегін дүкен иесі растады → confirmed (беруге дайын).
  Future<void> confirmOnlinePayment(OrderModel o) =>
      _sb.from('orders').update({
        'status': OrderModel.statusConfirmed,
        'payment_bank': 'card',
        'payment_confirmed_by': AppUser.current.uid,
        'payment_confirmed_at': DateTime.now().toIso8601String(),
        'deadline_at': null,
      }).eq('id', o.id);

  Future<void> rejectReceipt(OrderModel o, String reason) =>
      _sb.from('orders').update({
        'status': OrderModel.statusRejected,
        'rejection_reason': reason,
        'rejected_at': DateTime.now().toIso8601String(),
        'deadline_at':
            DateTime.now().add(OrderModel.receiptWindow).toIso8601String(),
      }).eq('id', o.id);

  Future<void> confirmInStorePayment(OrderModel o,
          {String paymentMethod = 'cash'}) =>
      _sb.from('orders').update({
        'status': OrderModel.statusConfirmed,
        'payment_confirmed_by': AppUser.current.uid,
        'payment_confirmed_at': DateTime.now().toIso8601String(),
        'in_store_payment_method': paymentMethod,
        'deadline_at': null,
      }).eq('id', o.id);

  Future<void> handOverWithDoplate(OrderModel order, String doplaMethod) async {
    if (order.status != OrderModel.statusReserved) {
      throw Exception(tr('Заказ не в статусе брони', 'Тапсырыс бронь күйінде емес'));
    }
    await _sb
        .from('orders')
        .update({'in_store_payment_method': doplaMethod}).eq('id', order.id);
    await markHandedOver(order.copyWith(
      status: OrderModel.statusConfirmed,
      inStorePaymentMethod: doplaMethod,
    ));
  }

  Future<void> markHandedOver(OrderModel order) =>
      _completeOrder(order, fromHandover: true);

  Future<void> confirmOnlineOrder(OrderModel order) =>
      _completeOrder(order, fromHandover: false);

  /// Online тапсырысты аяқтайды: бронь болса қойманы азайтады, sales_history
  /// жазады, статусты completed қылады, чек нөмірін береді.
  Future<void> _completeOrder(OrderModel order,
      {required bool fromHandover}) async {
    if (fromHandover && order.status != OrderModel.statusConfirmed) {
      throw Exception(tr('Оплата ещё не подтверждена администратором', 'Төлемді әкімші әлі растамаған'));
    }
    final seller = AppUser.current;
    final receipt = await nextReceiptNumber();

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

    await _sb.from('orders').update({
      'status': OrderModel.statusCompleted,
      'delivered_by_uid': seller.uid,
      'delivered_by_name': seller.name,
      'seller_id': 'онлайн',
      'seller_name': 'Онлайн',
      'receipt_number': receipt,
      // Аяқталған тапсырыста дедлайн қалмауы керек — әйтпесе клиент экраны
      // оны «мерзімі өтті» деп қате авто-болдырмайды.
      'deadline_at': null,
    }).eq('id', order.id);

    final promoFactor = order.total > 0 ? order.finalTotal / order.total : 1.0;
    // Онлайн-төлем әрқашан картаға аударым ('card') — тарихта «Оплата картой»
    // болып көрінеді. Бронь доплатасы — дүкенде qolma-qol/kaspi.
    final payMethod = order.isSmartReservation
        ? (order.inStorePaymentMethod.isNotEmpty
            ? order.inStorePaymentMethod
            : '')
        : (order.paymentBank.isNotEmpty ? order.paymentBank : 'card');
    final depositMethod = order.isSmartReservation
        ? (order.paymentBank.isNotEmpty ? order.paymentBank : 'card')
        : '';

    final sales = <Map<String, dynamic>>[];
    for (final item in order.items) {
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
        'selected_size': item.size,
        'sizes_sold': {item.size: item.qty},
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
    if (sales.isNotEmpty) await _sb.from('sales_history').insert(sales);

    for (final pid in order.items.map((i) => i.productId).toSet()) {
      await recomputeProductStatus(pid);
    }
  }

  /// Тапсырысты бас тарту + қойманы қалпына келтіру (идемпотентті — stock_restored).
  Future<void> cancelOnlineOrder(OrderModel order) async {
    final oRow = await _sb
        .from('orders')
        .select('stock_restored,promo_counts_usage,promo_id,client_uid')
        .eq('id', order.id)
        .maybeSingle();
    if (oRow == null) return;
    if (oRow['stock_restored'] == true) return;

    for (final item in order.items) {
      await _sb.rpc('adjust_batch_sizes', params: {
        'p_batch': item.batchId,
        'p_deltas': {item.size: item.qty},
        'p_field':
            order.isSmartReservation ? 'reserved_sizes' : 'sizes_quantity',
        'p_guard': false,
      });
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
      'status': OrderModel.statusCancelled,
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
  Stream<int> watchNewReturnsCount() => Supabase.instance.client
      .from('returns')
      .stream(primaryKey: ['id'])
      .map((rows) => rows.where((r) => r['status'] == 'requested').length);
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
