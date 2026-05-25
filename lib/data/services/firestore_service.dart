import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/product_model.dart';
import '../models/batch_model.dart';
import '../models/sale_model.dart';
import '../models/warehouse_model.dart';
import '../../core/app_user.dart';

class FirestoreService {
  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  FirestoreService({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _db   = firestore ?? FirebaseFirestore.instance,
        _auth = auth     ?? FirebaseAuth.instance;

  // ownerUid: admin → өз uid; seller → admin uid
  String get _ownerUid {
    final uid = AppUser.ownerUid.isNotEmpty
        ? AppUser.ownerUid
        : (_auth.currentUser?.uid ?? '');
    if (uid.isEmpty) throw Exception('Пайдаланушы авторизацияланбаған.');
    return uid;
  }

  String get _adminUid => _ownerUid;

  // ── Collection refs ──────────────────────────────────────────────────────────

  CollectionReference<Map<String, dynamic>> get _products =>
      _db.collection('users').doc(_ownerUid).collection('products');

  CollectionReference<Map<String, dynamic>> get _salesHistory =>
      _db.collection('users').doc(_ownerUid).collection('sales_history');

  CollectionReference<Map<String, dynamic>> _batches(String productId) =>
      _products.doc(productId).collection('batches');

  CollectionReference<Map<String, dynamic>> get _warehouses =>
      _db.collection('users').doc(_adminUid).collection('warehouses');

  CollectionReference<Map<String, dynamic>> get _joinRequests =>
      _db.collection('users').doc(_adminUid).collection('join_requests');

  CollectionReference<Map<String, dynamic>> get _transfers =>
      _db.collection('users').doc(_adminUid).collection('transfers');

  // ── Products ─────────────────────────────────────────────────────────────────

  Future<String> addNewProduct({
    required ProductModel product,
    required BatchModel firstBatch,
    DateTime? dateArrived,
    required String warehouseId,
  }) async {
    final productRef = _products.doc();
    final productId  = productRef.id;
    final articul    = 'QM-${productId.substring(0, 6).toUpperCase()}';
    final newProduct = product.copyWith(
        id: productId, articul: articul, status: ProductModel.statusInStock);
    final batchRef = _batches(productId).doc();
    final newBatch = firstBatch.copyWith(
        id: batchRef.id,
        dateArrived: dateArrived ?? DateTime.now(),
        warehouseId: warehouseId);
    final wb = _db.batch();
    wb.set(productRef, newProduct.toJson());
    wb.set(batchRef, newBatch.toJson());
    await wb.commit();
    return productId;
  }

  Future<String> addNewBatchToProduct({
    required String productId,
    required BatchModel batch,
    DateTime? dateArrived,
    required String warehouseId,
  }) async {
    final batchRef = _batches(productId).doc();
    final newBatch = batch.copyWith(
        id: batchRef.id,
        dateArrived: dateArrived ?? DateTime.now(),
        warehouseId: warehouseId);
    final wb = _db.batch();
    wb.update(_products.doc(productId), {'status': ProductModel.statusInStock});
    wb.set(batchRef, newBatch.toJson());
    await wb.commit();
    return batchRef.id;
  }

  Future<String?> findMatchingProduct({
    required String name, required String brand, required String type,
    required String material, required String category, required String color,
  }) async {
    final snap = await _products
        .where('name',  isEqualTo: name.trim())
        .where('brand', isEqualTo: brand.trim())
        .get();
    for (final doc in snap.docs) {
      final p = ProductModel.fromFirestore(doc);
      if (p.type == type && p.material == material &&
          p.category == category && p.color == color) { return p.id; }
    }
    return null;
  }

  Stream<List<ProductModel>> watchProducts() =>
      _products.orderBy('name').snapshots()
          .map((s) => s.docs.map(ProductModel.fromFirestore).toList());

  Future<ProductModel?> getProduct(String productId) async {
    final doc = await _products.doc(productId).get();
    if (!doc.exists) return null;
    return ProductModel.fromFirestore(doc);
  }

  Future<void> updateProductImages(String productId, List<String> imageUrls) =>
      _products.doc(productId).update({'images': imageUrls});

  // ── Batches ───────────────────────────────────────────────────────────────────

  Future<List<BatchModel>> getBatches(String productId) async {
    final snap = await _batches(productId)
        .orderBy('date_arrived', descending: true).get();
    return snap.docs.map(BatchModel.fromFirestore).toList();
  }

  Stream<List<BatchModel>> watchBatches(String productId) =>
      _batches(productId)
          .orderBy('date_arrived', descending: true)
          .snapshots()
          .map((s) => s.docs.map(BatchModel.fromFirestore).toList());

  Future<void> updateBatchSizes(
      String productId, String batchId, Map<String, int> sizes) =>
      _batches(productId).doc(batchId).update({'sizes_quantity': sizes});

  Future<void> updateBatch({
    required String productId, required String batchId,
    required DateTime dateArrived, required double purchasePrice,
    required double sellingPrice, required Map<String, int> sizesQuantity,
  }) async {
    final allSnap = await _batches(productId).get();
    final updatedAnyInStock = allSnap.docs.any((doc) {
      if (doc.id == batchId) return sizesQuantity.values.any((q) => q > 0);
      return BatchModel.fromFirestore(doc).sizesQuantity.values.any((q) => q > 0);
    });
    final wb = _db.batch();
    wb.update(_batches(productId).doc(batchId), {
      'date_arrived':   Timestamp.fromDate(dateArrived),
      'purchase_price': purchasePrice,
      'selling_price':  sellingPrice,
      'sizes_quantity': sizesQuantity,
    });
    wb.update(_products.doc(productId), {
      'status': updatedAnyInStock ? ProductModel.statusInStock : ProductModel.statusSold,
    });
    await wb.commit();
  }

  Future<void> deleteBatch(String productId, String batchId) async {
    final allSnap = await _batches(productId).get();
    final remaining = allSnap.docs
        .where((d) => d.id != batchId)
        .map(BatchModel.fromFirestore).toList();
    final anyInStock = remaining.any((b) => b.sizesQuantity.values.any((q) => q > 0));
    final newStatus = (remaining.isNotEmpty && anyInStock)
        ? ProductModel.statusInStock : ProductModel.statusSold;

    // If there are sales linked to this batch, archive it (zero out sizes,
    // mark isArchived=true) instead of deleting — this preserves analytics
    // and sales history integrity.
    final salesSnap = await _salesHistory
        .where('product_id', isEqualTo: productId)
        .where('batch_id',   isEqualTo: batchId)
        .limit(1).get();

    final wb = _db.batch();
    if (salesSnap.docs.isNotEmpty) {
      wb.update(_batches(productId).doc(batchId), {
        'sizes_quantity': <String, int>{},
        'isArchived':     true,
      });
    } else {
      wb.delete(_batches(productId).doc(batchId));
    }
    wb.update(_products.doc(productId), {'status': newStatus});
    await wb.commit();

    if (salesSnap.docs.isNotEmpty) {
      throw SaleException(
          'Бұл партиядан сату болған. Партия жойылмай архивке өтті — аналитика сақталды.');
    }
  }

  // ── Sales ─────────────────────────────────────────────────────────────────────

  Future<void> makeSale({
    required String productId,
    required String batchId,
    required Map<String, int> sizesSold,
    double discountPercent = 0,
    required String warehouseId,
    // Optional client-generated key; reusing the same key makes the operation
    // idempotent — the second call is a no-op if the document already exists.
    String? idempotencyKey,
  }) async {
    final sellerId   = AppUser.uid.isNotEmpty ? AppUser.uid : (_auth.currentUser?.uid ?? '');
    final sellerName = AppUser.name;
    final saleDocId  = idempotencyKey ?? _salesHistory.doc().id;

    await _db.runTransaction((transaction) async {
      // ── ALL reads must come before ANY writes (Firestore rule) ──────────
      final batchRef = _batches(productId).doc(batchId);
      final saleRef  = _salesHistory.doc(saleDocId);

      final batchDoc    = await transaction.get(batchRef);
      final existingDoc = await transaction.get(saleRef);

      // Early exits (no writes done yet)
      if (!batchDoc.exists) throw SaleException('Партия табылмады.');
      if (existingDoc.exists) return; // Idempotency: sale already recorded.

      final batch = BatchModel.fromFirestore(batchDoc);

      // Guard: batch must belong to the warehouse being sold from.
      // Catches the race condition where admin reassigns the seller's warehouse
      // while the seller is mid-sale and the WarehouseContext has already updated.
      if (batch.warehouseId.isNotEmpty && batch.warehouseId != warehouseId) {
        throw SaleException(
            'Ошибка: Ваша привязка к складу была изменена Админом. Данная продажа отменена.');
      }

      for (final entry in sizesSold.entries) {
        if (entry.value <= 0) continue;
        final available = batch.sizesQuantity[entry.key] ?? 0;
        if (available < entry.value) {
          throw SaleException('Размер ${entry.key}: қолда $available, сұратылған ${entry.value}');
        }
      }

      final updatedSizes = Map<String, int>.from(batch.sizesQuantity);
      for (final entry in sizesSold.entries) {
        if (entry.value > 0) {
          updatedSizes[entry.key] = (updatedSizes[entry.key] ?? 0) - entry.value;
        }
      }

      // Non-transactional read for allSoldOut check (was in original code).
      final allBatches = await _batches(productId).get();
      bool allSoldOut = true;
      for (final doc in allBatches.docs) {
        final b     = BatchModel.fromFirestore(doc);
        final sizes = b.id == batchId ? updatedSizes : b.sizesQuantity;
        if (sizes.values.any((q) => q > 0)) { allSoldOut = false; break; }
      }

      final qty        = sizesSold.values.fold(0, (a, b) => a + b);
      final basePrice  = batch.sellingPrice * qty;
      final totalPrice = basePrice * (1 - discountPercent / 100);
      final firstSize  = sizesSold.keys.isNotEmpty ? sizesSold.keys.first : '';

      // ── All writes at the end ────────────────────────────────────────────
      transaction.update(batchRef, {'sizes_quantity': updatedSizes});
      if (allSoldOut) {
        transaction.update(_products.doc(productId), {'status': ProductModel.statusSold});
      }

      transaction.set(saleRef, SaleModel(
        id:              saleRef.id,
        productId:       productId,
        batchId:         batchId,
        saleDate:        DateTime.now(),
        sizesSold:       sizesSold,
        selectedSize:    firstSize,
        quantity:        qty,
        basePrice:       basePrice,
        totalPrice:      totalPrice,
        discountPercent: discountPercent,
        discountAmount:  basePrice - totalPrice,
        sellerId:        sellerId,
        sellerName:      sellerName,
        warehouseId:     warehouseId,
      ).toJson());
    });
  }

  Stream<List<SaleModel>> watchSalesHistory() =>
      _salesHistory.orderBy('sale_date', descending: true)
          .snapshots()
          .map((s) => s.docs.map(SaleModel.fromFirestore).toList());

  Future<List<SaleModel>> getSalesForProduct(String productId) async {
    final snap = await _salesHistory
        .where('product_id', isEqualTo: productId)
        .orderBy('sale_date', descending: true).get();
    return snap.docs.map(SaleModel.fromFirestore).toList();
  }

  Future<double> getTotalRevenue({DateTime? from, DateTime? to}) async {
    Query<Map<String, dynamic>> q = _salesHistory;
    if (from != null) q = q.where('sale_date', isGreaterThanOrEqualTo: Timestamp.fromDate(from));
    if (to   != null) q = q.where('sale_date', isLessThanOrEqualTo:    Timestamp.fromDate(to));
    final snap = await q.get();
    return snap.docs.fold<double>(
        0, (s, d) => s + ((d.data()['total_price'] as num?)?.toDouble() ?? 0));
  }

  Future<int> getArrivedPairsForMonth(DateTime month) async {
    final from = DateTime(month.year, month.month, 1);
    final to   = DateTime(month.year, month.month + 1, 1);
    final products = await _products.get();
    int total = 0;
    for (final pDoc in products.docs) {
      final snap = await _batches(pDoc.id)
          .where('date_arrived', isGreaterThanOrEqualTo: Timestamp.fromDate(from))
          .where('date_arrived', isLessThan:             Timestamp.fromDate(to)).get();
      for (final bDoc in snap.docs) { total += BatchModel.fromFirestore(bDoc).totalQuantity; }
    }
    return total;
  }

  // ── Warehouses ────────────────────────────────────────────────────────────────

  Stream<List<WarehouseModel>> watchWarehouses() =>
      _warehouses.orderBy('createdAt').snapshots()
          .map((s) => s.docs.map(WarehouseModel.fromFirestore).toList());

  Future<List<WarehouseModel>> getWarehouses() async {
    final snap = await _warehouses.orderBy('createdAt').get();
    return snap.docs.map(WarehouseModel.fromFirestore).toList();
  }

  Future<String> createWarehouse({
    required String name,
    String? address,
    String? note,
    bool isMain = false,
  }) async {
    final ref = _warehouses.doc();
    await ref.set({
      'id':        ref.id,
      'name':      name.trim(),
      if (address != null && address.isNotEmpty) 'address': address.trim(),
      if (note    != null && note.isNotEmpty)    'note':    note.trim(),
      'isMain':    isMain,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  Future<void> updateWarehouse({
    required String warehouseId,
    required String name,
    String? address,
    String? note,
  }) => _warehouses.doc(warehouseId).update({
    'name':    name.trim(),
    'address': address?.trim() ?? '',
    'note':    note?.trim()    ?? '',
  });

  Future<void> deleteWarehouse(String warehouseId) =>
      _warehouses.doc(warehouseId).delete();

  /// Қойманы тереңдетіп өшіреді: оған байланысты batch-тарды да тазалайды
  Future<void> deleteWarehouseDeep(String warehouseId) async {
    final wb = _db.batch();
    wb.delete(_warehouses.doc(warehouseId));

    final productsSnap = await _products.get();
    for (final pDoc in productsSnap.docs) {
      final batchSnap = await _batches(pDoc.id)
          .where('warehouseId', isEqualTo: warehouseId).get();
      for (final bDoc in batchSnap.docs) {
        wb.update(bDoc.reference, {'warehouseId': ''});
      }
    }
    await wb.commit();
  }

  /// Returns all products that have at least one batch in [warehouseId],
  /// including sold-out ones (pairs == 0), so the "Продано" tab stays intact.
  Stream<List<ProductWithStock>> watchProductsInWarehouse(String warehouseId) =>
      _products.orderBy('name').snapshots().asyncMap((snap) async {
        final result = <ProductWithStock>[];
        for (final pDoc in snap.docs) {
          final batchSnap = await _batches(pDoc.id)
              .where('warehouseId', isEqualTo: warehouseId).get();
          // Skip products that have never had a batch in this warehouse.
          if (batchSnap.docs.isEmpty) continue;
          final pairs = batchSnap.docs.fold<int>(0, (acc, b) {
            final sq = (b.data()['sizes_quantity'] as Map<dynamic, dynamic>? ?? {});
            return acc + sq.values.fold<int>(0, (s, v) => s + ((v as num).toInt()));
          });
          result.add(ProductWithStock(
            product: ProductModel.fromFirestore(pDoc),
            pairs: pairs,
          ));
        }
        return result;
      });

  Future<int> countProductsInWarehouse(String warehouseId) async {
    final productsSnap = await _products.get();
    int count = 0;
    for (final pDoc in productsSnap.docs) {
      final batchSnap = await _batches(pDoc.id)
          .where('warehouseId', isEqualTo: warehouseId).get();
      final hasPairs = batchSnap.docs.any((b) {
        final sq = (b.data()['sizes_quantity'] as Map<dynamic, dynamic>? ?? {});
        return sq.values.any((v) => (v as num).toInt() > 0);
      });
      if (hasPairs) count++;
    }
    return count;
  }

  Future<int> countPairsInWarehouse(String warehouseId) async {
    final productsSnap = await _products.get();
    int total = 0;
    for (final pDoc in productsSnap.docs) {
      final batchSnap = await _batches(pDoc.id)
          .where('warehouseId', isEqualTo: warehouseId).get();
      for (final b in batchSnap.docs) {
        final sq = (b.data()['sizes_quantity'] as Map<dynamic, dynamic>? ?? {});
        total += sq.values.fold<int>(0, (s, v) => s + ((v as num).toInt()));
      }
    }
    return total;
  }

  Future<int> countSellersInWarehouse(String warehouseId) async {
    final snap = await _db.collection('users')
        .where('ownerId', isEqualTo: _adminUid)
        .get();
    return snap.docs
        .where((d) =>
            d.data()['role'] == 'seller' &&
            d.data()['joinStatus'] == 'active' &&
            d.data()['assignedWarehouseId'] == warehouseId)
        .length;
  }

  /// Seller's own user document stream — used by WarehouseContext to react
  /// instantly when an admin reassigns the seller to a different warehouse.
  Stream<String> watchSellerAssignedWarehouseId() =>
      _db.collection('users')
          .doc(_auth.currentUser!.uid)
          .snapshots()
          .map((doc) => doc.data()?['assignedWarehouseId'] as String? ?? '');

  // ── Seller join flow ──────────────────────────────────────────────────────────

  /// Бизнес-код арқылы admin-ді табып, қосылу сұрауын жіберу
  Future<void> sendJoinRequest(String businessCode) async {
    final query = await _db.collection('users')
        .where('businessCode', isEqualTo: businessCode.trim())
        .where('role', isEqualTo: 'admin')
        .limit(1).get();

    if (query.docs.isEmpty) {
      throw 'Бизнес-код табылмады. Дүкен иесінен қайта сұраңыз.';
    }

    final adminDoc = query.docs.first;
    final adminUid = adminDoc.id;
    final sellerUid = _auth.currentUser!.uid;

    // Бұрын жіберілмеген бе?
    final existing = await _db.collection('users').doc(adminUid)
        .collection('join_requests')
        .where('sellerId', isEqualTo: sellerUid)
        .where('status',   isEqualTo: 'pending')
        .limit(1).get();

    if (existing.docs.isNotEmpty) {
      throw 'Сіз бұл дүкенге ұсыныс жіберіп қойғансыз.';
    }

    final userDoc = await _db.collection('users').doc(sellerUid).get();
    final data    = userDoc.data() ?? {};

    await _db.collection('users').doc(adminUid)
        .collection('join_requests').add({
      'sellerId':    sellerUid,
      'sellerName':  data['name']  ?? '',
      'sellerEmail': data['email'] ?? '',
      'requestedAt': FieldValue.serverTimestamp(),
      'status':      'pending',
    });

    await _db.collection('users').doc(sellerUid).update({
      'joinStatus':     'pending',
      'pendingOwnerId': adminUid,
    });
  }

  /// Ұсынысты болдырмау (seller жағынан)
  Future<void> cancelJoinRequest() async {
    final sellerUid = _auth.currentUser!.uid;
    final sellerDoc = await _db.collection('users').doc(sellerUid).get();
    final pendingOwner = sellerDoc.data()?['pendingOwnerId'] as String? ?? '';

    if (pendingOwner.isNotEmpty) {
      final reqSnap = await _db.collection('users').doc(pendingOwner)
          .collection('join_requests')
          .where('sellerId', isEqualTo: sellerUid)
          .where('status',   isEqualTo: 'pending')
          .limit(1).get();
      for (final d in reqSnap.docs) { await d.reference.delete(); }
    }

    await _db.collection('users').doc(sellerUid).update({
      'joinStatus':                 'none',
      'pendingOwnerId':             FieldValue.delete(),
    });
  }

  /// Admin ұсынысты қабылдайды + қойма береді
  Future<void> approveJoinRequest({
    required String requestId,
    required String sellerId,
    required String warehouseId,
  }) async {
    final adminUid = _auth.currentUser!.uid;
    await _db.runTransaction((tx) async {
      tx.update(_db.collection('users').doc(sellerId), {
        'ownerId':             adminUid,
        'assignedWarehouseId': warehouseId,
        'joinStatus':          'active',
        'pendingOwnerId':      FieldValue.delete(),
      });
      tx.update(
        _db.collection('users').doc(adminUid)
            .collection('join_requests').doc(requestId),
        {'status': 'approved', 'approvedAt': FieldValue.serverTimestamp(),
         'assignedWarehouseId': warehouseId},
      );
    });
  }

  /// Admin ұсынысты қабылдамайды
  Future<void> rejectJoinRequest({
    required String requestId,
    required String sellerId,
  }) async {
    final adminUid = _auth.currentUser!.uid;
    await _db.collection('users').doc(adminUid)
        .collection('join_requests').doc(requestId)
        .update({'status': 'rejected'});
    await _db.collection('users').doc(sellerId).update({
      'joinStatus':     'none',
      'pendingOwnerId': FieldValue.delete(),
    });
  }

  /// Admin seller-ді дүкеннен шығарады (аккаунтты жоймайды)
  Future<void> removeSeller(String sellerId) async =>
      _db.collection('users').doc(sellerId).update({
        'ownerId':             FieldValue.delete(),
        'assignedWarehouseId': FieldValue.delete(),
        'joinStatus':          'none',
      });

  /// Seller-дің assignedWarehouseId-ін өзгерту
  Future<void> reassignSellerWarehouse(String sellerId, String warehouseId) =>
      _db.collection('users').doc(sellerId).update({
        'assignedWarehouseId': warehouseId,
      });

  /// Admin-дің белсенді seller-лері (1 where + client-side filter to avoid composite index)
  Stream<List<Map<String, dynamic>>> watchActiveSellers() =>
      _db.collection('users')
          .where('ownerId', isEqualTo: _adminUid)
          .snapshots()
          .map((s) => s.docs
              .where((d) =>
                  d.data()['role'] == 'seller' &&
                  d.data()['joinStatus'] == 'active')
              .map((d) => {...d.data(), 'id': d.id})
              .toList());

  /// Admin-дің күтудегі ұсыныстары (no orderBy to avoid composite index — client-side sort)
  Stream<List<Map<String, dynamic>>> watchPendingRequests() =>
      _joinRequests
          .where('status', isEqualTo: 'pending')
          .snapshots()
          .map((s) {
            final docs = s.docs.map((d) => {...d.data(), 'id': d.id}).toList();
            docs.sort((a, b) {
              final ta = (a['requestedAt'] as Timestamp?)?.toDate() ?? DateTime.now();
              final tb = (b['requestedAt'] as Timestamp?)?.toDate() ?? DateTime.now();
              return tb.compareTo(ta);
            });
            return docs;
          });

  // ── Transfers ─────────────────────────────────────────────────────────────────

  Stream<List<Map<String, dynamic>>> watchTransfers() =>
      _transfers.orderBy('createdAt', descending: true)
          .snapshots()
          .map((s) => s.docs.map((d) => {...d.data(), 'id': d.id}).toList());

  Future<void> transferStock({
    required String fromWarehouseId,
    required String toWarehouseId,
    required String productId,
    required String productName,
    required Map<String, int> sizes,
  }) async {
    await _db.runTransaction((tx) async {
      final fromBatchesSnap = await _products.doc(productId)
          .collection('batches')
          .where('warehouseId', isEqualTo: fromWarehouseId)
          .get();
      final fromBatches = fromBatchesSnap.docs.toList()
        ..sort((a, b) {
          final ta = (a.data()['date_arrived'] as Timestamp?)?.toDate() ?? DateTime(2000);
          final tb = (b.data()['date_arrived'] as Timestamp?)?.toDate() ?? DateTime(2000);
          return ta.compareTo(tb);
        });

      var remaining = Map<String, int>.from(sizes);
      for (final batch in fromBatches) {
        final batchSizes = Map<String, int>.from(
            (batch.data()['sizes_quantity'] as Map<dynamic, dynamic>? ?? {})
                .map((k, v) => MapEntry(k.toString(), (v as num).toInt())));
        bool changed = false;
        for (final size in remaining.keys.toList()) {
          final needed = remaining[size]!;
          if (needed <= 0) continue;
          final have = batchSizes[size] ?? 0;
          if (have <= 0) continue;
          final take = needed > have ? have : needed;
          batchSizes[size] = have - take;
          remaining[size]  = needed - take;
          changed = true;
        }
        if (changed) tx.update(batch.reference, {'sizes_quantity': batchSizes});
        if (remaining.values.every((v) => v == 0)) break;
      }

      if (remaining.values.any((v) => v > 0)) {
        throw SaleException('Қалдық жеткіліксіз');
      }

      // To warehouse-та жаңа batch жасаймыз
      final firstPrice = fromBatches.isNotEmpty ? fromBatches.first.data() : {};
      final newBatchRef = _products.doc(productId).collection('batches').doc();
      tx.set(newBatchRef, {
        'id':             newBatchRef.id,
        'warehouseId':    toWarehouseId,
        'purchase_price': firstPrice['purchase_price'] ?? 0,
        'selling_price':  firstPrice['selling_price']  ?? 0,
        'sizes_quantity': sizes,
        'date_arrived':   Timestamp.now(),
        'isTransfer':     true,
      });

      // Transfer тарихы
      final transferRef = _transfers.doc();
      tx.set(transferRef, {
        'fromWarehouseId': fromWarehouseId,
        'toWarehouseId':   toWarehouseId,
        'productId':       productId,
        'productName':     productName,
        'sizes':           sizes,
        'totalQuantity':   sizes.values.fold(0, (a, b) => a + b),
        'performedBy':     _auth.currentUser?.uid ?? '',
        'createdAt':       FieldValue.serverTimestamp(),
      });
    });
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
