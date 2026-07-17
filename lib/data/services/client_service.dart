import 'dart:math';
import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/store_model.dart';
import '../models/product_model.dart';
import '../models/batch_model.dart';
import '../models/order_model.dart';
import '../models/review_model.dart';
import '../models/warehouse_model.dart';
import '../models/cart_item_model.dart';
import '../models/promo_model.dart';
import '../../core/search_helper.dart';

import '../../core/lang.dart';
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

bool productGroupMatches(ProductGroup g, String query) {
  if (query.isEmpty) return true;
  final p = g.main;
  return SearchHelper.matches(p.name, query) ||
      SearchHelper.matches(p.brand, query) ||
      SearchHelper.matches(p.type, query) ||
      SearchHelper.matches(p.color, query) ||
      g.variants.any((v) => SearchHelper.matches(v.color, query));
}

int productGroupScore(ProductGroup g, String query) {
  final a = SearchHelper.score(g.main.name, query);
  final b = SearchHelper.score(g.main.brand, query);
  return a > b ? a : b;
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

  // ── Addresses ───────────────────────────────────────────────────────────────

  Stream<List<Map<String, dynamic>>> watchAddresses() => _uid.isEmpty
      ? const Stream.empty()
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
                  })
              .toList());

  Future<String> addAddress(
      {required String label, required String address}) async {
    final row = await _sb
        .from('addresses')
        .insert({
          'client_uid': _uid,
          'label': label.trim(),
          'address': address.trim(),
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

  Future<StoreModel?> getStoreByAdminUid(String adminUid) async {
    if (adminUid.isEmpty) return null;
    final row = await _sb
        .from('stores')
        .select()
        .eq('admin_uid', adminUid)
        .maybeSingle();
    return row == null ? null : StoreModel.fromMap(row);
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
    return rows.map(ProductModel.fromMap).toList();
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

  // ── Pickup code ────────────────────────────────────────────────────────────

  String _generatePickupCode() {
    const chars = '0123456789ABCDEFGHJKMNPQRSTUVWXYZ';
    final r = Random.secure();
    final code = List.generate(4, (_) => chars[r.nextInt(chars.length)]).join();
    return 'QM-$code';
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

  static int _orderNumFromId(String id) {
    int h = 0;
    for (final ch in id.runes.take(8)) {
      final d = ch >= 97
          ? ch - 87
          : ch >= 65
              ? ch - 55
              : ch >= 48
                  ? ch - 48
                  : 0;
      h = h * 36 + d;
    }
    return 10000 + h.abs() % 89000;
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
    for (final item in order.items) {
      try {
        await _sb.rpc('adjust_batch_sizes', params: {
          'p_batch': item.batchId,
          'p_deltas': {item.size: order.isSmartReservation ? item.qty : -item.qty},
          'p_field':
              order.isSmartReservation ? 'reserved_sizes' : 'sizes_quantity',
          'p_guard': true,
        });
      } on PostgrestException catch (e) {
        if (e.message.contains('insufficient_stock') ||
            e.message.contains('batch_not_found')) {
          throw Exception(
              tr('Недостаточно остатка «${item.productName}» в размере ${item.size}', '«${item.productName}» ${item.size} өлшемінде жеткілікті қор жоқ'));
        }
        rethrow;
      }
    }

    // Промокод есептегішін арттырамыз.
    if (countsPromo) {
      try {
        await _sb.rpc('adjust_promo_usage', params: {
          'p_promo': order.promoId,
          'p_client': order.clientUid.isEmpty ? null : order.clientUid,
          'p_delta': 1,
        });
      } catch (_) {}
    }

    final placed = order.copyWith(
      pickupCode: code,
      sellerId: 'онлайн',
      sellerName: 'Онлайн',
      deadlineAt: DateTime.now().add(OrderModel.receiptWindow),
      paymentCardNumber: cardNumber,
      paymentCardHolder: cardHolder,
      paymentBank: cardBank,
      storePhone: storePhone,
    );
    final row =
        await _sb.from('orders').insert(placed.toMap()).select('id').single();
    final orderId = row['id'] as String;
    final orderNumber = _orderNumFromId(orderId);
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

  /// Клиенттің тапсырыстары (clientUid бойынша; client-side сұрыптау).
  Stream<List<OrderModel>> watchClientOrders(String clientUid) => _sb
      .from('orders')
      .stream(primaryKey: ['id'])
      .eq('client_uid', clientUid)
      .order('created_at', ascending: false)
      .map((rows) => rows.map(OrderModel.fromMap).toList());

  /// Клиент тапсырысты бас тартады: қойманы қалпына келтіреді (идемпотентті).
  Future<void> cancelOrder(OrderModel order) async {
    final oRow = await _sb
        .from('orders')
        .select('status,stock_restored,promo_counts_usage,promo_id,client_uid')
        .eq('id', order.id)
        .maybeSingle();
    if (oRow == null) return;
    if (oRow['stock_restored'] == true) return;
    final liveStatus = oRow['status'] as String? ?? '';
    // Тек белсенді төлем күйлерін болдырмауға болады — расталған/аяқталған
    // тапсырысты клиенттік авто-cancel ЕШҚАШАН өзгертпейді.
    const cancellable = {
      OrderModel.statusPending,
      OrderModel.statusReserved,
      OrderModel.statusRejected,
    };
    if (!cancellable.contains(liveStatus)) return;

    if (order.isSmartReservation) {
      final smartActive = liveStatus == OrderModel.statusPending ||
          liveStatus == OrderModel.statusReserved ||
          liveStatus == OrderModel.statusRejected;
      if (smartActive) {
        for (final item in order.items) {
          await _sb.rpc('adjust_batch_sizes', params: {
            'p_batch': item.batchId,
            'p_deltas': {item.size: -item.qty},
            'p_field': 'reserved_sizes',
            'p_guard': false,
          });
        }
      }
    } else {
      for (final item in order.items) {
        await _sb.rpc('adjust_batch_sizes', params: {
          'p_batch': item.batchId,
          'p_deltas': {item.size: item.qty},
          'p_field': 'sizes_quantity',
          'p_guard': false,
        });
      }
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
