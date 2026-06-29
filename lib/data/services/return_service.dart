import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/return_model.dart';
import '../models/sale_model.dart';
import '../models/order_model.dart';
import '../../core/app_user.dart';

class ReturnService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ── Collection refs ──────────────────────────────────────────────────────────

  CollectionReference<Map<String, dynamic>> _returnsCol(String adminUid) =>
      _db.collection('users').doc(adminUid).collection('returns');

  CollectionReference<Map<String, dynamic>> _productsCol(String adminUid) =>
      _db.collection('users').doc(adminUid).collection('products');

  CollectionReference<Map<String, dynamic>> _batchesCol(
          String adminUid, String productId) =>
      _productsCol(adminUid).doc(productId).collection('batches');

  CollectionReference<Map<String, dynamic>> _salesHistoryCol(String adminUid) =>
      _db.collection('users').doc(adminUid).collection('sales_history');

  CollectionReference<Map<String, dynamic>> _warehousesCol(String adminUid) =>
      _db.collection('users').doc(adminUid).collection('warehouses');

  // Cross-store index so the client can find their returns without knowing adminUid.
  CollectionReference<Map<String, dynamic>> _returnsIndexCol(String clientUid) =>
      _db.collection('users').doc(clientUid).collection('returns_index');

  // Жасырын өзіндік құн (себестоимость) — doc id = batchId.
  DocumentReference<Map<String, dynamic>> _batchCostRef(
          String adminUid, String batchId) =>
      _db.collection('users').doc(adminUid).collection('batch_costs').doc(batchId);

  // Онлайн тапсырыстар топ-деңгейлі `orders` коллекциясында сақталады.
  DocumentReference<Map<String, dynamic>> _orderRef(String orderId) =>
      _db.collection('orders').doc(orderId);

  // ── Online cost resolution ─────────────────────────────────────────────────────

  // Онлайн сатылым жасалғанда sales_history-ге жазылған бірлік өзіндік құнды
  // (purchase_price) тапсырыс бойынша оқып, әр элементке (product|batch|size)
  // сәйкестендіреді. Возврат осы дәл құнды кері жазады → себестоимость балансталады.
  Future<Map<String, double>> _onlineCostByItem(
      String adminUid, String orderId) async {
    final map = <String, double>{};
    if (orderId.isEmpty) return map;
    try {
      final snap = await _salesHistoryCol(adminUid)
          .where('order_id', isEqualTo: orderId)
          .get();
      for (final d in snap.docs) {
        final data = d.data();
        if (data['type'] == 'return') continue; // тек нақты сатылым жазбалары
        final key =
            '${data['product_id']}|${data['batch_id']}|${data['selected_size']}';
        map[key] = (data['purchase_price'] as num?)?.toDouble() ?? 0;
      }
    } catch (_) {}
    return map;
  }

  // batch_costs-тан бірлік өзіндік құн (sales_history жазбасы табылмаған жағдайда).
  Future<double> _resolveBatchCost(String adminUid, String batchId) async {
    try {
      final doc = await _batchCostRef(adminUid, batchId).get();
      if (doc.exists) {
        return (doc.data()?['purchase_price'] as num?)?.toDouble() ?? 0;
      }
    } catch (_) {}
    return 0;
  }

  // ── ID generation ─────────────────────────────────────────────────────────────

  // Scans returns for the current year, finds the highest NNNN, increments by 1.
  // Uses the doc ID itself (RET-YYYY-NNNN) — no extra index or query field needed.
  Future<String> _nextReturnId(String adminUid) async {
    final year = DateTime.now().year;
    final snap = await _returnsCol(adminUid).get();
    int maxN = 0;
    for (final doc in snap.docs) {
      final parts = doc.id.split('-');
      if (parts.length == 3 && parts[0] == 'RET' && parts[1] == '$year') {
        final n = int.tryParse(parts[2]) ?? 0;
        if (n > maxN) maxN = n;
      }
    }
    return 'RET-$year-${(maxN + 1).toString().padLeft(4, '0')}';
  }

  // Клиент жаңа возврат нөмірін СКАНСЫЗ жасайды: ол дүкеннің бүкіл returns
  // коллекциясын оқи алмайды (ереже тек өз құжатына рұқсат береді), сондықтан
  // _nextReturnId (барлығын get) клиентте permission-denied берер еді.
  // Уақыт негізді бірегей нөмір — дүкен ішінде қақтығыс ықтималдығы жоқ деуге болады.
  String _clientReturnId() {
    final now = DateTime.now();
    final suffix =
        (now.millisecondsSinceEpoch % 100000).toString().padLeft(5, '0');
    return 'RET-${now.year}-$suffix';
  }

  // ── CLIENT side ───────────────────────────────────────────────────────────────

  Future<ReturnModel> createReturnRequest({
    required ReturnRequestInput input,
  }) async {
    try {
      final returnId = _clientReturnId();
      final now = DateTime.now();
      final model = ReturnModel(
        id: returnId,
        adminUid: input.adminUid,
        clientUid: input.clientUid,
        clientName: input.clientName,
        clientPhone: input.clientPhone,
        orderId: input.orderId,
        type: ReturnType.online,
        items: input.items,
        totalAmount: input.items.fold(0, (s, i) => s + i.subtotal),
        reason: input.reason,
        reasonNote: input.reasonNote,
        photoUrls: input.photoUrls,
        pickup: input.pickup,
        refundMethod: input.refundMethod,
        status: ReturnStatus.requested,
        createdAt: now,
      );

      final wb = _db.batch();
      wb.set(_returnsCol(input.adminUid).doc(returnId), model.toMap());
      // Client-side index for cross-store lookup.
      wb.set(
        _returnsIndexCol(input.clientUid).doc(returnId),
        {
          'adminUid': input.adminUid,
          'returnId': returnId,
          'created_at': Timestamp.fromDate(now),
        },
      );
      await wb.commit();
      return model;
    } catch (e) {
      debugPrint('[ReturnService.createReturnRequest] $e');
      rethrow;
    }
  }

  // Streams returns from the client-side index, then fetches each return doc.
  // N+1 reads are acceptable here — clients typically have few returns.
  Stream<List<ReturnModel>> watchClientReturns(String clientUid) {
    return _returnsIndexCol(clientUid).snapshots().asyncMap((indexSnap) async {
      if (indexSnap.docs.isEmpty) return <ReturnModel>[];
      final futures = indexSnap.docs.map((doc) {
        final adminUid = doc.data()['adminUid'] as String? ?? '';
        final returnId = doc.data()['returnId'] as String? ?? '';
        if (adminUid.isEmpty || returnId.isEmpty) return Future.value(null);
        return _returnsCol(adminUid).doc(returnId).get();
      });
      final docs = await Future.wait(futures);
      final result = <ReturnModel>[];
      for (final d in docs) {
        if (d != null && d.exists) {
          result.add(ReturnModel.fromMap(d.data()!, d.id));
        }
      }
      result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return result;
    });
  }

  Stream<ReturnModel?> watchReturn(String adminUid, String returnId) =>
      _returnsCol(adminUid).doc(returnId).snapshots().map((doc) =>
          doc.exists ? ReturnModel.fromMap(doc.data()!, doc.id) : null);

  // Only works when status == requested. Deletes from both collections.
  Future<void> cancelReturnRequest(String adminUid, String returnId) async {
    try {
      final returnDoc = await _returnsCol(adminUid).doc(returnId).get();
      if (!returnDoc.exists) return;
      final model = ReturnModel.fromMap(returnDoc.data()!, returnDoc.id);
      if (model.status != ReturnStatus.requested) {
        throw ReturnException('Тек "Сұраныс жіберілді" күйінде болдырмауға болады.');
      }
      final wb = _db.batch();
      wb.delete(_returnsCol(adminUid).doc(returnId));
      if (model.clientUid.isNotEmpty) {
        wb.delete(_returnsIndexCol(model.clientUid).doc(returnId));
      }
      await wb.commit();
    } catch (e) {
      debugPrint('[ReturnService.cancelReturnRequest] $e');
      rethrow;
    }
  }

  // ── SELLER side ───────────────────────────────────────────────────────────────

  Stream<List<ReturnModel>> watchSellerReturns(String adminUid) =>
      _returnsCol(adminUid).snapshots().map((s) {
        final list = s.docs
            .map((d) => ReturnModel.fromMap(d.data(), d.id))
            .toList();
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return list;
      });

  Future<void> approveReturn(
      String adminUid, String returnId, String sellerId) async {
    try {
      await _returnsCol(adminUid).doc(returnId).update({
        'status': ReturnStatus.approved.name,
        'seller_id': sellerId,
        'approved_at': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[ReturnService.approveReturn] $e');
      rethrow;
    }
  }

  Future<void> rejectReturn(
      String adminUid, String returnId, String reason) async {
    try {
      await _returnsCol(adminUid).doc(returnId).update({
        'status': ReturnStatus.rejected.name,
        'rejection_reason': reason,
        'rejected_at': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[ReturnService.rejectReturn] $e');
      rethrow;
    }
  }

  Future<void> markReceived({
    required String adminUid,
    required String returnId,
    required bool itemConditionOk,
    required List<String> conditionPhotos,
  }) async {
    try {
      await _returnsCol(adminUid).doc(returnId).update({
        'status': ReturnStatus.received.name,
        'item_condition_ok': itemConditionOk,
        'condition_photos': conditionPhotos,
        'received_at': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[ReturnService.markReceived] $e');
      rethrow;
    }
  }

  // Transitions received → refunded.
  // Тауар ӘРҚАШАН қоймаға қайтарылады (поступление) — «жарамсыз» нұсқасы жоқ.
  // Транзакция ішінде возврат статусы тексеріледі → қос басу екі рет
  // поступление жасамайды (идемпотентті).
  Future<void> completeRefund({
    required String adminUid,
    required String returnId,
    required RefundMethod method,
  }) async {
    try {
      final returnDoc = await _returnsCol(adminUid).doc(returnId).get();
      if (!returnDoc.exists) throw ReturnException('Возврат не найден.');
      final model = ReturnModel.fromMap(returnDoc.data()!, returnDoc.id);

      // Себестоимость аналитикасы балансталу үшін әр элементтің бірлік өзіндік
      // құнын транзакцияға дейін оқимыз (транзакция ішінде query істеуге болмайды).
      final costByItem = await _onlineCostByItem(adminUid, model.orderId ?? '');
      for (final item in model.items) {
        final key = '${item.productId}|${item.batchId}|${item.size}';
        if (!costByItem.containsKey(key)) {
          costByItem[key] = await _resolveBatchCost(adminUid, item.batchId);
        }
      }

      await _refundWithStockRestore(adminUid, returnId, method, model, costByItem);
    } catch (e) {
      debugPrint('[ReturnService.completeRefund] $e');
      rethrow;
    }
  }

  // Stock restore + refund in a single Firestore transaction.
  // All reads must precede all writes per Firestore rules.
  Future<void> _refundWithStockRestore(
    String adminUid,
    String returnId,
    RefundMethod method,
    ReturnModel model,
    Map<String, double> costByItem,
  ) async {
    final batchRefs = model.items
        .map((item) => _batchesCol(adminUid, item.productId).doc(item.batchId))
        .toList();
    final orderId = model.orderId ?? '';
    final orderRef = orderId.isNotEmpty ? _orderRef(orderId) : null;

    await _db.runTransaction((tx) async {
      // ── READ phase ──────────────────────────────────────────────────────────
      final returnRef = _returnsCol(adminUid).doc(returnId);
      final returnSnap = await tx.get(returnRef);
      final batchTxDocs = await Future.wait(batchRefs.map((r) => tx.get(r)));
      // Тапсырыс статусын идемпотентті жаңарту үшін оны да оқимыз (барлық оқу
      // жазудан бұрын болуы керек — Firestore транзакция ережесі).
      if (orderRef != null) await tx.get(orderRef);

      // ИДЕМПОТЕНТТІЛІК: егер возврат әлдеқашан қайтарылған болса — ештеңе істемейміз.
      // Бұл қос басу кезінде бір тауардың екі рет складқа түсуін болдырмайды.
      if (!returnSnap.exists) return;
      if (returnSnap.data()?['status'] == ReturnStatus.refunded.name) return;

      // ── WRITE phase ─────────────────────────────────────────────────────────
      final warehouseQtyDelta = <String, int>{};

      for (var i = 0; i < model.items.length; i++) {
        final item = model.items[i];
        final batchDoc = batchTxDocs[i];
        if (!batchDoc.exists) continue;

        final rawSizes =
            batchDoc.data()!['sizes_quantity'] as Map<dynamic, dynamic>? ?? {};
        final sizes = rawSizes
            .map((k, v) => MapEntry(k.toString(), (v as num).toInt()));
        sizes[item.size] = (sizes[item.size] ?? 0) + item.quantity;
        tx.update(batchRefs[i], {'sizes_quantity': sizes});

        // Collect warehouse increments (batch may not have warehouseId if very old)
        final wId = batchDoc.data()!['warehouseId'] as String? ?? '';
        if (wId.isNotEmpty) {
          warehouseQtyDelta[wId] = (warehouseQtyDelta[wId] ?? 0) + item.quantity;
        }
      }

      for (final entry in warehouseQtyDelta.entries) {
        tx.update(_warehousesCol(adminUid).doc(entry.key), {
          'totalPairs': FieldValue.increment(entry.value),
        });
      }

      // Әр элемент үшін бөлек теріс sales_history жазбасы (бірлік өзіндік құнымен).
      // Тапсырыста бірнеше тауар әртүрлі өзіндік құнмен болуы мүмкін, сондықтан
      // әрқайсысын жеке жазамыз → түсім де, себестоимость да, маржа да дәл балансталады.
      for (final item in model.items) {
        final key = '${item.productId}|${item.batchId}|${item.size}';
        final unitCost = costByItem[key] ?? 0;
        final saleRef = _salesHistoryCol(adminUid).doc();
        tx.set(saleRef, {
          'id': saleRef.id,
          'type': 'return',
          'return_id': model.id,
          'product_id': item.productId,
          'product_name': item.productTitle,
          'batch_id': item.batchId,
          'selected_size': item.size,
          'sale_date': FieldValue.serverTimestamp(),
          'quantity': item.quantity,
          // Теріс мәндер — қосынды түсім дұрыс қалады.
          'total_price': -item.subtotal,
          'base_price': -item.subtotal,
          'discount_percent': 0.0,
          'discount_amount': 0.0,
          // Онлайн сатылым 'онлайн' сатушыға жазылады (markHandedOver/
          // confirmOnlineOrder). Возврат та СОЛ бакетке жазылуы керек — әйтпесе
          // возвратты ҚАБЫЛДАҒАН тірі сатушының жеке аналитикасы негізсіз
          // минусқа кетеді (онлайн сатылым оған ешқашан жазылмаған).
          'seller_id': 'онлайн',
          'seller_name': 'Онлайн',
          'warehouseId': model.warehouseId ?? '',
          'is_online': model.type == ReturnType.online,
          'order_id': orderId,
          'payment_method': method.name,
          // Себестоимостьты кері жазу үшін бірлік өзіндік құн.
          'purchase_price': unitCost,
        });
      }

      // Тапсырысты «Қайтарылды» күйіне ауыстырамыз — ол «completed» тізімінен
      // шығып, онлайн түсім автоматты түрде азаяды (әрі «бас тарту» есебіне
      // қосылмайды, өйткені ол бөлек статус).
      if (orderRef != null) {
        tx.update(orderRef, {'status': OrderModel.statusReturned});
      }

      tx.update(returnRef, {
        'status': ReturnStatus.refunded.name,
        'refund_method': method.name,
        'refunded_at': FieldValue.serverTimestamp(),
      });
    });
  }

  // ── OFFLINE returns (seller in-store) ─────────────────────────────────────────

  // Returns recent offline sales (last [days] days) for the given admin store.
  // No composite index needed — all filtering is client-side.
  // If [query] is provided, filters by receiptNumber, sale id, or product name.
  Future<List<SaleModel>> findRecentSales({
    required String adminUid,
    String? receiptNumber,
    String? query,
    int days = 14,
  }) async {
    try {
      final cutoff = DateTime.now().subtract(Duration(days: days));
      final snap = await _salesHistoryCol(adminUid)
          .orderBy('sale_date', descending: true)
          .limit(500)
          .get();

      // Sales that already have a return (any non-rejected) — exclude them so a
      // sale can't be returned twice (over-refund) and so the negative return
      // entry itself never shows up as a returnable "sale".
      final returnsSnap = await _returnsCol(adminUid).get();
      final returnedSaleIds = <String>{};
      for (final d in returnsSnap.docs) {
        final data = d.data();
        if (data['status'] == ReturnStatus.rejected.name) continue;
        final sid = data['sale_id'] as String?;
        if (sid != null && sid.isNotEmpty) returnedSaleIds.add(sid);
      }

      var sales = snap.docs
          .map(SaleModel.fromFirestore)
          .where((s) =>
              !s.isReturn && // теріс қайтару жазбасын қайтаруға болмайды
              !s.isOnline &&
              s.saleDate.isAfter(cutoff) &&
              !returnedSaleIds.contains(s.id)) // бір сатылым — бір рет қайтару
          .toList();

      final effectiveQuery =
          query?.trim().isNotEmpty == true ? query!.trim() : receiptNumber?.trim();

      if (effectiveQuery != null && effectiveQuery.isNotEmpty) {
        final q = effectiveQuery.toUpperCase();
        sales = sales.where((s) {
          return s.id.toUpperCase().contains(q) ||
              s.receiptNumber.toUpperCase().contains(q) ||
              s.productName.toUpperCase().contains(q);
        }).toList();
      }
      return sales;
    } catch (e) {
      debugPrint('[ReturnService.findRecentSales] $e');
      rethrow;
    }
  }

  // Creates an offline return and immediately completes the stock restore
  // (seller has the item in hand). No multi-step approval flow.
  Future<ReturnModel> createOfflineReturn({
    required String adminUid,
    required SaleModel sourceSale,
    required List<ReturnItem> items,
    required ReturnReason reason,
    required RefundMethod method,
    required String sellerId,
  }) async {
    try {
      // Бір сатылым — бір рет қайтару. Екі рет кнопка басуды сервер деңгейінде де блоктаймыз.
      final existingSnap = await _returnsCol(adminUid).get();
      final alreadyReturned = existingSnap.docs.any((d) {
        final data = d.data();
        return data['sale_id'] == sourceSale.id &&
            data['status'] != ReturnStatus.rejected.name;
      });
      if (alreadyReturned) {
        throw ReturnException('Бұл сатылым бойынша қайтару бұрын жасалған.');
      }

      final returnId = await _nextReturnId(adminUid);
      final now = DateTime.now();
      final sellerName = AppUser.current.name;

      final model = ReturnModel(
        id: returnId,
        adminUid: adminUid,
        sellerId: sellerId,
        warehouseId: sourceSale.warehouseId.isNotEmpty
            ? sourceSale.warehouseId
            : null,
        clientUid: '',
        clientName: '',
        clientPhone: '',
        saleId: sourceSale.id,
        type: ReturnType.offline,
        items: items,
        totalAmount: items.fold(0, (s, i) => s + i.subtotal),
        reason: reason,
        photoUrls: const [],
        pickup: ReturnPickup.selfBring,
        refundMethod: method,
        status: ReturnStatus.refunded,
        createdAt: now,
        refundedAt: now,
        itemConditionOk: true,
        conditionPhotos: const [],
      );

      // Pre-read all batch docs to get current sizes and warehouseId.
      final batchRefs = items
          .map((i) => _batchesCol(adminUid, i.productId).doc(i.batchId))
          .toList();
      final batchDocs = await Future.wait(batchRefs.map((r) => r.get()));

      final wb = _db.batch();
      wb.set(_returnsCol(adminUid).doc(returnId), model.toMap());

      // Restore stock and update warehouse counters.
      final warehouseQtyDelta = <String, int>{};
      for (var i = 0; i < items.length; i++) {
        final item = items[i];
        final batchDoc = batchDocs[i];
        if (!batchDoc.exists) continue;

        final rawSizes = batchDoc.data()!['sizes_quantity']
            as Map<dynamic, dynamic>? ?? {};
        final sizes =
            rawSizes.map((k, v) => MapEntry(k.toString(), (v as num).toInt()));
        sizes[item.size] = (sizes[item.size] ?? 0) + item.quantity;
        wb.update(batchRefs[i], {'sizes_quantity': sizes});

        final wId = batchDoc.data()!['warehouseId'] as String? ?? '';
        if (wId.isNotEmpty) {
          warehouseQtyDelta[wId] =
              (warehouseQtyDelta[wId] ?? 0) + item.quantity;
        }
      }
      for (final entry in warehouseQtyDelta.entries) {
        wb.update(_warehousesCol(adminUid).doc(entry.key), {
          'totalPairs': FieldValue.increment(entry.value),
        });
      }

      // Negative sales_history entry.
      final saleRef = _salesHistoryCol(adminUid).doc();
      wb.set(saleRef, {
        'id': saleRef.id,
        'type': 'return',
        'return_id': returnId,
        'product_id': items.isNotEmpty ? items.first.productId : '',
        'product_name': items.isNotEmpty ? items.first.productTitle : '',
        'batch_id': items.isNotEmpty ? items.first.batchId : '',
        'sale_date': Timestamp.fromDate(now),
        'quantity': items.fold(0, (s, i) => s + i.quantity),
        'total_price': -model.totalAmount,
        'base_price': -model.totalAmount,
        'discount_percent': 0.0,
        'discount_amount': 0.0,
        // Теріс жазба ТҮПНҰСҚА сатылымның сатушысына қарсы жазылады — возвратты
        // ким басса да (админ/басқа сатушы), аналитика дұрыс сатушыдан шегереді.
        'seller_id':
            sourceSale.sellerId.isNotEmpty ? sourceSale.sellerId : sellerId,
        'seller_name':
            sourceSale.sellerName.isNotEmpty ? sourceSale.sellerName : sellerName,
        'warehouseId': sourceSale.warehouseId,
        'is_online': false,
        'payment_method': method.name,
        // Себестоимость аналитикасы дұрыс балансталу үшін сақтаймыз.
        'purchase_price': sourceSale.purchasePrice,
      });

      await wb.commit();
      return model;
    } catch (e) {
      debugPrint('[ReturnService.createOfflineReturn] $e');
      rethrow;
    }
  }

  // ── ADMIN side ────────────────────────────────────────────────────────────────

  Stream<List<ReturnModel>> watchAllReturns(String adminUid) =>
      _returnsCol(adminUid).snapshots().map((s) {
        final list = s.docs
            .map((d) => ReturnModel.fromMap(d.data(), d.id))
            .toList();
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return list;
      });

  // Computes analytics for a date range.
  // Avoids composite indexes: loads all documents client-side and filters.
  Future<ReturnAnalytics> computeAnalytics({
    required String adminUid,
    required DateRange range,
  }) async {
    try {
      final returnsSnap = await _returnsCol(adminUid).get();
      final allReturns = returnsSnap.docs
          .map((d) => ReturnModel.fromMap(d.data(), d.id))
          .where((r) =>
              r.createdAt.isAfter(range.from) &&
              r.createdAt.isBefore(range.to))
          .toList();

      final salesSnap = await _salesHistoryCol(adminUid)
          .orderBy('sale_date', descending: true)
          .get();
      final totalSales = salesSnap.docs
          .where((d) {
            final date = (d.data()['sale_date'] as Timestamp?)?.toDate();
            final isReturn = d.data()['type'] == 'return';
            return !isReturn &&
                date != null &&
                date.isAfter(range.from) &&
                date.isBefore(range.to);
          })
          .length;

      final reasonBreakdown = <ReturnReason, int>{};
      final productCounts = <String, ({String title, int count})>{};
      final perSellerClosed = <String, int>{};

      for (final r in allReturns) {
        reasonBreakdown[r.reason] = (reasonBreakdown[r.reason] ?? 0) + 1;

        for (final item in r.items) {
          final prev = productCounts[item.productId];
          productCounts[item.productId] = (
            title: item.productTitle,
            count: (prev?.count ?? 0) + item.quantity,
          );
        }

        if (r.sellerId != null && r.status == ReturnStatus.refunded) {
          perSellerClosed[r.sellerId!] =
              (perSellerClosed[r.sellerId!] ?? 0) + 1;
        }
      }

      final topProducts = productCounts.values.toList()
        ..sort((a, b) => b.count.compareTo(a.count));

      final returnRate =
          totalSales > 0 ? allReturns.length / totalSales * 100 : 0.0;

      return ReturnAnalytics(
        totalReturns: allReturns.length,
        totalSales: totalSales,
        returnRate: returnRate,
        reasonBreakdown: reasonBreakdown,
        topReturnedProducts: topProducts.take(10).toList(),
        perSellerClosed: perSellerClosed,
      );
    } catch (e) {
      debugPrint('[ReturnService.computeAnalytics] $e');
      rethrow;
    }
  }
}

// ── Exception ─────────────────────────────────────────────────────────────────

class ReturnException implements Exception {
  final String message;
  const ReturnException(this.message);

  @override
  String toString() => 'ReturnException: $message';
}
