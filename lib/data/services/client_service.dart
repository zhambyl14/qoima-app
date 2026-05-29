import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/store_model.dart';
import '../models/product_model.dart';
import '../models/batch_model.dart';
import '../models/order_model.dart';
import '../models/warehouse_model.dart';

class ClientService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ── Stores ─────────────────────────────────────────────────────────────────

  Future<List<StoreModel>> getPublishedStores() async {
    // No .where() — collectionGroup + where requires a Collection Group index
    // that Firestore does not create by default. Filter client-side instead.
    final snap = await _db.collectionGroup('store').get();
    return snap.docs
        .map((d) => StoreModel.fromFirestore(d))
        .where((s) => s.isPublished)
        .toList();
  }

  // ── Products ───────────────────────────────────────────────────────────────

  Future<List<ProductModel>> getStoreProducts(String adminUid) async {
    final snap = await _db
        .collection('users')
        .doc(adminUid)
        .collection('products')
        .where('status', isEqualTo: ProductModel.statusInStock)
        .get();
    return snap.docs.map(ProductModel.fromFirestore).toList();
  }

  Future<List<BatchModel>> getProductBatches(
      String adminUid, String productId, List<String> warehouseIds) async {
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
            !b.isEffectivelySoldOut)
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
    final result = <({ProductModel product, List<BatchModel> batches})>[];
    for (final p in products) {
      final b = await getProductBatches(adminUid, p.id, whIds);
      if (b.isNotEmpty) result.add((product: p, batches: b));
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

  /// Places an order atomically — READ-BEFORE-WRITE pattern:
  /// Phase 1: all reads, Phase 2: validation, Phase 3: all writes.
  Future<OrderModel> placeOrder(OrderModel order) async {
    final code = await _uniquePickupCode();
    final orderNumber = 10000 + (DateTime.now().microsecondsSinceEpoch % 90000);

    final orderId = await _db.runTransaction<String>((tx) async {
      final orderRef = _db.collection('orders').doc();

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

      final placed = order.copyWith(
          id: orderRef.id,
          pickupCode: code,
          orderNumber: orderNumber,
          sellerId: 'онлайн',
          sellerName: 'Онлайн');
      tx.set(orderRef, placed.toJson());
      return orderRef.id;
    });

    return order.copyWith(
        id: orderId,
        pickupCode: code,
        orderNumber: orderNumber,
        sellerId: 'онлайн',
        sellerName: 'Онлайн');
  }

  // Sort client-side to avoid needing a composite index on clientPhone+createdAt
  Stream<List<OrderModel>> watchClientOrders(String clientPhone) {
    return _db
        .collection('orders')
        .where('clientPhone', isEqualTo: clientPhone)
        .snapshots()
        .map((snap) {
      final orders = snap.docs.map((d) => OrderModel.fromFirestore(d)).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return orders;
    });
  }

  /// Client-initiated cancel: updates order status.
  /// For SmartReservation, also releases the reserved_sizes in the batch.
  Future<void> cancelOrder(OrderModel order) async {
    await _db.runTransaction((tx) async {
      final orderRef = _db.collection('orders').doc(order.id);

      if (order.isSmartReservation &&
          order.status == OrderModel.statusReserved) {
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

      tx.update(orderRef, {'status': OrderModel.statusCancelled});
    });
  }
}
