import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/store_model.dart';
import '../models/product_model.dart';
import '../models/batch_model.dart';
import '../models/order_model.dart';
import '../models/courier_delivery_model.dart';
import '../models/warehouse_model.dart';
import '../models/cart_item_model.dart';
import '../models/promo_model.dart';
import '../../core/search_helper.dart';

/// Группа товаров-вариантов: одно и то же имя+бренд+тип, разные цвета.
/// Используется для схлопывания цветовых вариантов в одну карточку каталога.
class ProductGroup {
  final List<ProductModel> variants; // same name+brand+type, different colors
  ProductGroup(this.variants);

  ProductModel get main => variants.first;
  String get name => main.name;
  String get brand => main.brand;
  String get type => main.type;
  bool get hasVariants => variants.length > 1;
}

/// Схлопывает список товаров в группы по ключу name+brand+type (без учёта
/// регистра/пробелов). Порядок групп сохраняется по первому появлению.
List<ProductGroup> groupProducts(List<ProductModel> products) {
  final map = <String, List<ProductModel>>{};
  for (final p in products) {
    final key =
        '${p.name.trim().toLowerCase()}__${p.brand.trim().toLowerCase()}__${p.type.trim().toLowerCase()}';
    map.putIfAbsent(key, () => []).add(p);
  }
  return map.entries.map((e) => ProductGroup(e.value)).toList();
}

/// Әр түсті жеке карточка ретінде жаямыз: топтың әр нұсқасы үшін бір
/// `(group, index)`. Карточка өз түсінен басталады (`index`), ал қалған түстер
/// сол карточкада ауыстырғыш ретінде көрінеді — басқанда сол түске ауысады.
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

/// Ақылды іздеу: топ сұранысқа сай ма (атау/бренд/тип/нұсқалар түсі).
/// «жасыл» сияқты сұраныс кез келген нұсқаның түсімен сәйкес болса да табады.
bool productGroupMatches(ProductGroup g, String query) {
  if (query.isEmpty) return true;
  final p = g.main;
  return SearchHelper.matches(p.name, query) ||
      SearchHelper.matches(p.brand, query) ||
      SearchHelper.matches(p.type, query) ||
      SearchHelper.matches(p.color, query) ||
      g.variants.any((v) => SearchHelper.matches(v.color, query));
}

/// Топтың іздеу сұранысына сәйкестік баллы (атау/бренд бойынша ең жоғарысы).
int productGroupScore(ProductGroup g, String query) {
  final a = SearchHelper.score(g.main.name, query);
  final b = SearchHelper.score(g.main.brand, query);
  return a > b ? a : b;
}

class ClientService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  CollectionReference<Map<String, dynamic>> get _favorites =>
      _db.collection('clients').doc(_uid).collection('favorites');

  CollectionReference<Map<String, dynamic>> get _addresses =>
      _db.collection('clients').doc(_uid).collection('addresses');

  // ── Favorites ───────────────────────────────────────────────────────────────

  Stream<List<String>> watchFavoriteIds() => _uid.isEmpty
      ? const Stream.empty()
      : _favorites.snapshots().map((s) => s.docs.map((d) => d.id).toList());

  Stream<List<Map<String, dynamic>>> watchFavorites() => _uid.isEmpty
      ? const Stream.empty()
      : _favorites
          .orderBy('addedAt', descending: true)
          .snapshots()
          .map((s) => s.docs
              .map((d) => {'id': d.id, ...d.data()})
              .toList());

  Future<void> addFavorite({
    required String productId,
    required String productName,
    required String imageUrl,
    required String adminUid,
    required String storeName,
    required double price,
  }) =>
      _favorites.doc(productId).set({
        'productId': productId,
        'productName': productName,
        'imageUrl': imageUrl,
        'adminUid': adminUid,
        'storeName': storeName,
        'price': price,
        'addedAt': FieldValue.serverTimestamp(),
      });

  Future<void> removeFavorite(String productId) =>
      _favorites.doc(productId).delete();

  // ── Addresses ───────────────────────────────────────────────────────────────

  Stream<List<Map<String, dynamic>>> watchAddresses() => _uid.isEmpty
      ? const Stream.empty()
      : _addresses
          .orderBy('createdAt', descending: true)
          .snapshots()
          .map((s) => s.docs
              .map((d) => {'id': d.id, ...d.data()})
              .toList());

  Future<String> addAddress({required String label, required String address}) async {
    final ref = await _addresses.add({
      'label': label.trim(),
      'address': address.trim(),
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  Future<void> deleteAddress(String id) => _addresses.doc(id).delete();

  // ── Stores ─────────────────────────────────────────────────────────────────

  Future<List<StoreModel>> getPublishedStores() async {
    // No .where() — collectionGroup + where requires a Collection Group index
    // that Firestore does not create by default. Filter client-side instead.
    final snap = await _db.collectionGroup('store').get();
    return snap.docs
        .map((d) => StoreModel.fromFirestore(d))
        .where((s) => s.isPublished && !s.isBlocked)
        .toList();
  }

  /// Дүкенді admin uid бойынша қайтарады (store doc id == adminUid).
  Future<StoreModel?> getStoreByAdminUid(String adminUid) async {
    if (adminUid.isEmpty) return null;
    final doc = await _db
        .collection('users')
        .doc(adminUid)
        .collection('store')
        .doc(adminUid)
        .get();
    return doc.exists ? StoreModel.fromFirestore(doc) : null;
  }

  // ── Products ───────────────────────────────────────────────────────────────

  /// Жеке товарды қайтарады (таңдаулылардан карточкаға өту үшін).
  Future<ProductModel?> getProductById(
      String adminUid, String productId) async {
    if (adminUid.isEmpty || productId.isEmpty) return null;
    final doc = await _db
        .collection('users')
        .doc(adminUid)
        .collection('products')
        .doc(productId)
        .get();
    return doc.exists ? ProductModel.fromFirestore(doc) : null;
  }

  Future<List<ProductModel>> getStoreProducts(String adminUid) async {
    final snap = await _db
        .collection('users')
        .doc(adminUid)
        .collection('products')
        .where('status', isEqualTo: ProductModel.statusInStock)
        .get();
    return snap.docs.map(ProductModel.fromFirestore).toList();
  }

  /// Товардың batch-тарын қайтарады.
  /// [onlyAvailable] = true (каталог) → тек қолжетімді (тауары бар) batch-тар.
  /// [onlyAvailable] = false (detail) → барлық batch-тар, соның ішінде OOS
  ///   (олардың размерлері detail-де сызылған күйде көрсетіледі).
  Future<List<BatchModel>> getProductBatches(
      String adminUid,
      String productId,
      List<String> warehouseIds, {
      bool onlyAvailable = true,
  }) async {
    final snap = await _db
        .collection('users')
        .doc(adminUid)
        .collection('products')
        .doc(productId)
        .collection('batches')
        .get();
    return snap.docs
        .map(BatchModel.fromFirestore)
        .where((b) =>
            (warehouseIds.isEmpty || warehouseIds.contains(b.warehouseId)) &&
            (!onlyAvailable || !b.isEffectivelySoldOut))
        .toList();
  }

  // ── Warehouses ─────────────────────────────────────────────────────────────

  Future<List<WarehouseModel>> getWarehouses(
      String adminUid, List<String> warehouseIds) async {
    if (adminUid.isEmpty) return [];
    final snap = await _db
        .collection('users')
        .doc(adminUid)
        .collection('warehouses')
        .get();
    return snap.docs
        .map(WarehouseModel.fromFirestore)
        .where((w) => warehouseIds.isEmpty || warehouseIds.contains(w.id))
        .toList();
  }

  Future<WarehouseModel?> getWarehouseById(
      String adminUid, String warehouseId) async {
    if (adminUid.isEmpty || warehouseId.isEmpty) return null;
    final doc = await _db
        .collection('users')
        .doc(adminUid)
        .collection('warehouses')
        .doc(warehouseId)
        .get();
    if (!doc.exists) return null;
    return WarehouseModel.fromFirestore(doc);
  }

  // ── Products with batches ──────────────────────────────────────────────────

  Future<List<({ProductModel product, List<BatchModel> batches})>>
      getStoreProductsWithBatches(String adminUid, List<String> whIds) async {
    final products = await getStoreProducts(adminUid);
    if (products.isEmpty) return [];
    // Fetch all batch collections in parallel instead of sequentially
    final allBatches = await Future.wait(
      products.map((p) => getProductBatches(adminUid, p.id, whIds)),
    );
    final result = <({ProductModel product, List<BatchModel> batches})>[];
    for (var i = 0; i < products.length; i++) {
      final batches = allBatches[i];
      // Batch-тары бар ЖӘНЕ кем дегенде бір размері қолжетімді тауарларды ғана
      // каталогта көрсетеміз. Толық sold-out тауарлар сүзіліп тасталады.
      if (batches.isNotEmpty && batches.any((b) => !b.isSoldOut)) {
        result.add((product: products[i], batches: batches));
      }
    }
    return result;
  }

  // ── Pickup code ────────────────────────────────────────────────────────────

  String _generatePickupCode() {
    // Excludes O, I, L to avoid visual confusion
    const chars = '0123456789ABCDEFGHJKMNPQRSTUVWXYZ';
    final r = Random.secure();
    final code = List.generate(4, (_) => chars[r.nextInt(chars.length)]).join();
    return 'QM-$code';
  }

  // Collision probability ~1/1.2M per active code — no need to query orders
  // (which clients can't read anyway due to Firestore security rules).
  Future<String> _uniquePickupCode() async => _generatePickupCode();

  // ── Promo codes (client validation) ─────────────────────────────────────────

  CollectionReference<Map<String, dynamic>> _promosOf(String adminUid) => _db
      .collection('users')
      .doc(adminUid)
      .collection('promos');

  /// Валидирует промокод для подмножества корзины одного магазина [adminUid].
  /// Проверки идут по порядку и возвращают понятную причину отказа (RU).
  /// [items] — позиции корзины этого магазина (цена уже со скидкой товара).
  Future<PromoResult> validatePromo({
    required String adminUid,
    required String code,
    required List<CartItemModel> items,
    required String clientUid,
  }) async {
    final norm = code.trim().toUpperCase();
    if (norm.isEmpty) return const PromoResult.fail('Введите промокод');

    // 1. Существует ли промокод в магазине корзины
    final snap =
        await _promosOf(adminUid).where('code', isEqualTo: norm).limit(1).get();
    if (snap.docs.isEmpty) {
      return const PromoResult.fail('Промокод не найден');
    }
    final promo = PromoModel.fromFirestore(snap.docs.first);

    // 2. Включён вручную
    if (!promo.active) return const PromoResult.fail('Промокод отключён');

    // 3. Срок действия
    if (!promo.isStarted) {
      return const PromoResult.fail('Промокод ещё не активен');
    }
    if (promo.isExpired) {
      return const PromoResult.fail('Срок действия промокода истёк');
    }

    // 4. Общий лимит использований
    if (promo.isExhausted) {
      return const PromoResult.fail('Лимит использований исчерпан');
    }

    // 5. Лимит на одного клиента
    if (promo.perUserLimit != null && clientUid.isNotEmpty) {
      try {
        final red = await _promosOf(adminUid)
            .doc(promo.id)
            .collection('redemptions')
            .doc(clientUid)
            .get();
        final used = (red.data()?['count'] as num?)?.toInt() ?? 0;
        if (used >= promo.perUserLimit!) {
          return const PromoResult.fail('Вы уже использовали этот промокод');
        }
      } catch (_) {}
    }

    // 6. Подходящие позиции (scope) и их сумма
    final applicable = promo.scope == 'products'
        ? items.where((i) => promo.productIds.contains(i.productId)).toList()
        : items;
    if (applicable.isEmpty) {
      return const PromoResult.fail('Промокод не применим к этим товарам');
    }
    final base = applicable.fold<double>(0, (s, i) => s + i.subtotal);

    // 7. Минимальная сумма заказа
    if (base < promo.minOrder) {
      return PromoResult.fail(
          'Минимальная сумма заказа ${promo.minOrder.toStringAsFixed(0)} ₸');
    }

    return PromoResult.ok(promo, promo.discountFor(base));
  }

  // ── Orders ─────────────────────────────────────────────────────────────────

  /// Batch availability: returns available qty per size (sizes_quantity − reserved_sizes).
  Future<Map<String, int>> getBatchAvailability(
      String adminUid, String productId, String batchId) async {
    final doc = await _db
        .collection('users')
        .doc(adminUid)
        .collection('products')
        .doc(productId)
        .collection('batches')
        .doc(batchId)
        .get();
    if (!doc.exists) return {};
    final data = doc.data()!;
    final sizes = (data['sizes_quantity'] as Map<dynamic, dynamic>? ?? {})
        .map((k, v) => MapEntry(k.toString(), (v as num).toInt()));
    final reserved = (data['reserved_sizes'] as Map<dynamic, dynamic>? ?? {})
        .map((k, v) => MapEntry(k.toString(), (v as num).toInt()));
    return {
      for (final k in sizes.keys) k: (sizes[k] ?? 0) - (reserved[k] ?? 0),
    };
  }

  /// Derives a readable 5-digit display number from a Firestore auto-generated ID.
  /// The ID is globally unique, so the derived number is collision-resistant
  /// without requiring a separate Firestore counter or extra security rules.
  static int _orderNumFromId(String id) {
    int h = 0;
    for (final ch in id.runes.take(8)) {
      final d = ch >= 97
          ? ch - 87 // a–z → 10–35
          : ch >= 65
              ? ch - 55 // A–Z → 10–35
              : ch >= 48
                  ? ch - 48 // 0–9 → 0–9
                  : 0;
      h = h * 36 + d;
    }
    return 10000 + h.abs() % 89000;
  }

  /// Places an order atomically — READ-BEFORE-WRITE pattern:
  /// Phase 1: all reads, Phase 2: validation, Phase 3: all writes.
  Future<OrderModel> placeOrder(OrderModel order) async {
    final code = await _uniquePickupCode();
    int assignedOrderNumber = 0;

    // Snapshot payment card + store phone so they never disappear for the client
    String cardNumber = '';
    String cardHolder = '';
    String cardBank = '';
    String storePhone = '';
    try {
      final storeSnap = await _db
          .collection('users')
          .doc(order.adminUid)
          .collection('store')
          .doc(order.adminUid)
          .get();
      if (storeSnap.exists) {
        final sd = storeSnap.data()!;
        cardNumber = sd['paymentCardNumber'] as String? ?? '';
        cardHolder = sd['paymentCardHolder'] as String? ?? '';
        cardBank = sd['paymentBank'] as String? ?? '';
        storePhone = sd['phone'] as String? ?? '';
      }
    } catch (_) {}

    final orderId = await _db.runTransaction<String>((tx) async {
      final orderRef = _db.collection('orders').doc();

      // Order number derived from the document ID — always unique, no extra
      // Firestore collection or security rules needed.
      assignedOrderNumber = _orderNumFromId(orderRef.id);

      // ── 1-КЕЗЕҢ: БАРЛЫҚ ОҚУ ────────────────────────────────────────────────
      final batchRefs = <DocumentReference>[];
      final batchDocs = <DocumentSnapshot>[];
      for (final item in order.items) {
        final ref = _db
            .collection('users')
            .doc(item.adminUid)
            .collection('products')
            .doc(item.productId)
            .collection('batches')
            .doc(item.batchId);
        final doc = await tx.get(ref);
        if (!doc.exists) {
          throw Exception('«${item.productName}» партиясы табылмады');
        }
        batchRefs.add(ref);
        batchDocs.add(doc);
      }

      // Промокод: читаем счётчик ДО любых записей (этот заказ владеет учётом)
      final countsPromo = order.promoCountsUsage && order.promoId.isNotEmpty;
      DocumentReference<Map<String, dynamic>>? promoRef;
      DocumentReference<Map<String, dynamic>>? redemptionRef;
      if (countsPromo) {
        promoRef =
            _promosOf(order.adminUid).doc(order.promoId);
        final promoDoc = await tx.get(promoRef);
        if (promoDoc.exists) {
          final pd = promoDoc.data()!;
          final maxUses = (pd['max_uses'] as num?)?.toInt();
          final usedCount = (pd['used_count'] as num?)?.toInt() ?? 0;
          if (maxUses != null && usedCount >= maxUses) {
            throw Exception('Лимит использований промокода исчерпан');
          }
          if (order.clientUid.isNotEmpty) {
            redemptionRef =
                promoRef.collection('redemptions').doc(order.clientUid);
            await tx.get(redemptionRef); // read before write (transaction rule)
          }
        } else {
          promoRef = null; // промокод удалён — просто не учитываем
        }
      }

      // ── 2-КЕЗЕҢ: ВАЛИДАЦИЯ (жазусыз) ───────────────────────────────────────
      for (var i = 0; i < order.items.length; i++) {
        final item = order.items[i];
        final data = batchDocs[i].data()! as Map<String, dynamic>;
        final rawSizes = data['sizes_quantity'] as Map<dynamic, dynamic>? ?? {};
        final sizes =
            rawSizes.map((k, v) => MapEntry(k.toString(), (v as num).toInt()));
        final rawRes = data['reserved_sizes'] as Map<dynamic, dynamic>? ?? {};
        final reserved =
            rawRes.map((k, v) => MapEntry(k.toString(), (v as num).toInt()));
        final available =
            (sizes[item.size] ?? 0) - (reserved[item.size] ?? 0);
        if (available < item.qty) {
          throw Exception(
              '«${item.productName}» ${item.size} өлшемінде тек $available дана бос');
        }
      }

      // ── 3-КЕЗЕҢ: БАРЛЫҚ ЖАЗУ ───────────────────────────────────────────────
      for (var i = 0; i < order.items.length; i++) {
        final item = order.items[i];
        if (order.isSmartReservation) {
          tx.update(batchRefs[i], {
            'reserved_sizes.${item.size}': FieldValue.increment(item.qty),
          });
        } else {
          tx.update(batchRefs[i], {
            'sizes_quantity.${item.size}': FieldValue.increment(-item.qty),
          });
        }
      }

      // Промокод: списываем счётчик ровно один раз (в этой же транзакции)
      if (promoRef != null) {
        tx.update(promoRef, {'used_count': FieldValue.increment(1)});
        if (redemptionRef != null) {
          tx.set(redemptionRef, {
            'count': FieldValue.increment(1),
            'code': order.promoCode,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
      }

      final placed = order.copyWith(
          id: orderRef.id,
          pickupCode: code,
          orderNumber: assignedOrderNumber,
          sellerId: 'онлайн',
          sellerName: 'Онлайн',
          deadlineAt: DateTime.now().add(OrderModel.receiptWindow),
          paymentCardNumber: cardNumber,
          paymentCardHolder: cardHolder,
          paymentBank: cardBank,
          storePhone: storePhone);
      tx.set(orderRef, placed.toJson());
      return orderRef.id;
    });

    final placed = order.copyWith(
        id: orderId,
        pickupCode: code,
        orderNumber: assignedOrderNumber,
        sellerId: 'онлайн',
        sellerName: 'Онлайн',
        deadlineAt: DateTime.now().add(OrderModel.receiptWindow),
        paymentCardNumber: cardNumber,
        paymentCardHolder: cardHolder,
        paymentBank: cardBank,
        storePhone: storePhone);

    // Best-effort: status жаңарту сәтсіз болса тапсырысқа әсер етпейді
    try {
      final seen = <String>{};
      for (final item in order.items) {
        if (seen.add(item.productId)) {
          await _recomputeProductStatus(item.adminUid, item.productId);
        }
      }
    } catch (_) {}

    return placed;
  }

  /// Тауар партициясының бос қалдығын есептеп product.status-ті жаңартады.
  Future<void> _recomputeProductStatus(
      String adminUid, String productId) async {
    final snap = await _db
        .collection('users')
        .doc(adminUid)
        .collection('products')
        .doc(productId)
        .collection('batches')
        .get();
    int avail = 0;
    for (final d in snap.docs) {
      avail += BatchModel.fromFirestore(d).totalAvailable;
    }
    await _db
        .collection('users')
        .doc(adminUid)
        .collection('products')
        .doc(productId)
        .update({
      'status':
          avail > 0 ? ProductModel.statusInStock : ProductModel.statusSold,
    });
  }

  // v11: клиент email+парольмен кіреді, сондықтан auth токенінде phone_number ЖОҚ.
  // Бұрын clientPhone бойынша сұрау Firestore ережелеріне (isOrderOwner →
  // token.phone_number) сүйенетін; енді ол бос → permission-denied → бос тізім.
  // Сол себепті тапсырыстарды clientUid (auth.uid) бойынша сұраймыз — ереже де
  // (isOrderOwner → auth.uid == clientUid) дәл осыны рұқсат етеді.
  // Sort client-side to avoid needing a composite index on clientUid+createdAt
  Stream<List<OrderModel>> watchClientOrders(String clientUid) {
    return _db
        .collection('orders')
        .where('clientUid', isEqualTo: clientUid)
        .snapshots()
        .map((snap) {
      final orders = snap.docs.map((d) => OrderModel.fromFirestore(d)).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return orders;
    });
  }

  /// Client-initiated cancel: restores stock and updates order status.
  /// Idempotent — double-tap / retry won't double-restore (stockRestored flag).
  Future<void> cancelOrder(OrderModel order) async {
    await _db.runTransaction((tx) async {
      final orderRef = _db.collection('orders').doc(order.id);

      // Idempotency: skip if stock was already restored
      final oSnap = await tx.get(orderRef);
      if (!oSnap.exists) return;
      if (oSnap.data()!['stockRestored'] == true) return;
      final od = oSnap.data()!;

      // Промокод: читаем счётчик ДО записей (вернём ровно один раз)
      final countsPromo = (od['promoCountsUsage'] as bool? ?? false) &&
          (od['promoId'] as String? ?? '').isNotEmpty;
      DocumentReference<Map<String, dynamic>>? promoRef;
      DocumentReference<Map<String, dynamic>>? redemptionRef;
      if (countsPromo) {
        promoRef = _promosOf(order.adminUid).doc(od['promoId'] as String);
        final pSnap = await tx.get(promoRef);
        if (!pSnap.exists) {
          promoRef = null; // промокод удалён — нечего возвращать
        } else if (order.clientUid.isNotEmpty) {
          redemptionRef =
              promoRef.collection('redemptions').doc(order.clientUid);
          await tx.get(redemptionRef);
        }
      }

      final liveStatus = od['status'] as String? ?? '';
      if (order.isSmartReservation) {
        // reserved_sizes was locked at order creation — release it
        final smartActive = liveStatus == OrderModel.statusPending ||
            liveStatus == OrderModel.statusReserved ||
            liveStatus == OrderModel.statusRejected;
        if (smartActive) {
          for (final item in order.items) {
            final batchRef = _db
                .collection('users')
                .doc(item.adminUid)
                .collection('products')
                .doc(item.productId)
                .collection('batches')
                .doc(item.batchId);
            tx.update(batchRef, {
              'reserved_sizes.${item.size}': FieldValue.increment(-item.qty),
            });
          }
        }
      } else {
        // ClickCollect / Delivery: sizes_quantity was decremented at creation — restore it
        for (final item in order.items) {
          final batchRef = _db
              .collection('users')
              .doc(item.adminUid)
              .collection('products')
              .doc(item.productId)
              .collection('batches')
              .doc(item.batchId);
          tx.update(batchRef, {
            'sizes_quantity.${item.size}': FieldValue.increment(item.qty),
          });
        }
      }

      // Промокод: возвращаем счётчик ровно один раз (вместе со складом)
      if (promoRef != null) {
        tx.update(promoRef, {'used_count': FieldValue.increment(-1)});
        if (redemptionRef != null) {
          tx.set(redemptionRef, {
            'count': FieldValue.increment(-1),
          }, SetOptions(merge: true));
        }
      }

      tx.update(orderRef, {
        'status': OrderModel.statusCancelled,
        'stockRestored': true,
      });
    });

    try {
      final seen = <String>{};
      for (final item in order.items) {
        if (seen.add(item.productId)) {
          await _recomputeProductStatus(item.adminUid, item.productId);
        }
      }
    } catch (_) {}
  }

  /// Creates one courier_deliveries record for a delivery order.
  /// Called once per cart checkout (not per warehouse sub-order).
  Future<void> createCourierDelivery(CourierDeliveryModel delivery) async {
    await _db.collection('courier_deliveries').add(delivery.toJson());
  }
}
