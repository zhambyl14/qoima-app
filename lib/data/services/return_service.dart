import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/return_model.dart';
import '../models/sale_model.dart';
import '../models/order_model.dart';
import '../../core/app_user.dart';

import '../../core/lang.dart';
/// Қайтару (возврат) сервисі (Supabase).
class ReturnService {
  final SupabaseClient _sb = Supabase.instance.client;

  // ── Online cost resolution ─────────────────────────────────────────────────────

  /// Онлайн сатылымның бірлік өзіндік құнын (product|batch|size бойынша) оқиды.
  Future<Map<String, double>> _onlineCostByItem(
      String adminUid, String orderId) async {
    final map = <String, double>{};
    if (orderId.isEmpty) return map;
    try {
      final rows = await _sb
          .from('sales_history')
          .select('product_id,batch_id,selected_size,purchase_price,type')
          .eq('owner_uid', adminUid)
          .eq('order_id', orderId);
      for (final data in rows) {
        if (data['type'] == 'return') continue;
        final key =
            '${data['product_id']}|${data['batch_id']}|${data['selected_size']}';
        map[key] = (data['purchase_price'] as num?)?.toDouble() ?? 0;
      }
    } catch (_) {}
    return map;
  }

  Future<double> _resolveBatchCost(String adminUid, String batchId) async {
    try {
      final row = await _sb
          .from('batch_costs')
          .select('purchase_price')
          .eq('batch_id', batchId)
          .maybeSingle();
      return (row?['purchase_price'] as num?)?.toDouble() ?? 0;
    } catch (_) {}
    return 0;
  }

  // ── ID generation ─────────────────────────────────────────────────────────────

  Future<String> _nextReturnId(String adminUid) async {
    final year = DateTime.now().year;
    final rows =
        await _sb.from('returns').select('id').eq('admin_uid', adminUid);
    int maxN = 0;
    for (final r in rows) {
      final parts = (r['id'] as String).split('-');
      if (parts.length == 3 && parts[0] == 'RET' && parts[1] == '$year') {
        final n = int.tryParse(parts[2]) ?? 0;
        if (n > maxN) maxN = n;
      }
    }
    return 'RET-$year-${(maxN + 1).toString().padLeft(4, '0')}';
  }

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
      await _sb.from('returns').insert(model.toRow());
      return model;
    } catch (e) {
      debugPrint('[ReturnService.createReturnRequest] $e');
      rethrow;
    }
  }

  /// Клиенттің барлық дүкендердегі қайтарулары (returns.client_uid тікелей).
  Stream<List<ReturnModel>> watchClientReturns(String clientUid) => _sb
      .from('returns')
      .stream(primaryKey: ['id'])
      .eq('client_uid', clientUid)
      .order('created_at', ascending: false)
      .map((rows) => rows.map(ReturnModel.fromRow).toList());

  Stream<ReturnModel?> watchReturn(String adminUid, String returnId) => _sb
      .from('returns')
      .stream(primaryKey: ['id'])
      .eq('id', returnId)
      .map((rows) => rows.isEmpty ? null : ReturnModel.fromRow(rows.first));

  Future<void> cancelReturnRequest(String adminUid, String returnId) async {
    try {
      final row = await _sb
          .from('returns')
          .select('status')
          .eq('id', returnId)
          .maybeSingle();
      if (row == null) return;
      if (row['status'] != ReturnStatus.requested.name) {
        throw ReturnException(
            tr('Отменить можно только в статусе «Заявка отправлена».', 'Тек "Сұраныс жіберілді" күйінде болдырмауға болады.'));
      }
      await _sb.from('returns').delete().eq('id', returnId);
    } catch (e) {
      debugPrint('[ReturnService.cancelReturnRequest] $e');
      rethrow;
    }
  }

  // ── SELLER side ───────────────────────────────────────────────────────────────

  Stream<List<ReturnModel>> watchSellerReturns(String adminUid) => _sb
      .from('returns')
      .stream(primaryKey: ['id'])
      .eq('admin_uid', adminUid)
      .order('created_at', ascending: false)
      .map((rows) => rows.map(ReturnModel.fromRow).toList());

  Future<void> approveReturn(
      String adminUid, String returnId, String sellerId) async {
    await _sb.from('returns').update({
      'status': ReturnStatus.approved.name,
      'seller_id': sellerId,
      'approved_at': DateTime.now().toIso8601String(),
    }).eq('id', returnId);
  }

  Future<void> rejectReturn(
      String adminUid, String returnId, String reason) async {
    await _sb.from('returns').update({
      'status': ReturnStatus.rejected.name,
      'rejection_reason': reason,
      'rejected_at': DateTime.now().toIso8601String(),
    }).eq('id', returnId);
  }

  Future<void> markReceived({
    required String adminUid,
    required String returnId,
    required bool itemConditionOk,
    required List<String> conditionPhotos,
  }) async {
    await _sb.from('returns').update({
      'status': ReturnStatus.received.name,
      'item_condition_ok': itemConditionOk,
      'condition_photos': conditionPhotos,
      'received_at': DateTime.now().toIso8601String(),
    }).eq('id', returnId);
  }

  /// received → refunded: қойманы қалпына келтіреді + теріс sales_history жазады.
  Future<void> completeRefund({
    required String adminUid,
    required String returnId,
    required RefundMethod method,
  }) async {
    try {
      final rRow = await _sb
          .from('returns')
          .select()
          .eq('id', returnId)
          .maybeSingle();
      if (rRow == null) throw ReturnException(tr('Возврат не найден.', 'Қайтару табылмады.'));
      if (rRow['status'] == ReturnStatus.refunded.name) return; // идемпотентті
      final model = ReturnModel.fromRow(rRow);

      // Бірлік өзіндік құн (онлайн сатылымнан → batch_costs fallback).
      final costByItem = await _onlineCostByItem(adminUid, model.orderId ?? '');
      for (final item in model.items) {
        final key = '${item.productId}|${item.batchId}|${item.size}';
        if (!costByItem.containsKey(key)) {
          costByItem[key] = await _resolveBatchCost(adminUid, item.batchId);
        }
      }

      // Партиялардың қоймасын алдын ала оқимыз (warehouse delta үшін).
      final batchIds = model.items.map((i) => i.batchId).toSet().toList();
      final whByBatch = <String, String?>{};
      if (batchIds.isNotEmpty) {
        final brows = await _sb
            .from('batches')
            .select('id,warehouse_id')
            .inFilter('id', batchIds);
        for (final b in brows) {
          whByBatch[b['id'] as String] = b['warehouse_id'] as String?;
        }
      }

      // Қойманы қалпына келтіреміз.
      final warehouseQtyDelta = <String, int>{};
      for (final item in model.items) {
        await _sb.rpc('adjust_batch_sizes', params: {
          'p_batch': item.batchId,
          'p_deltas': {item.size: item.quantity},
          'p_field': 'sizes_quantity',
          'p_guard': false,
        });
        final wId = whByBatch[item.batchId];
        if (wId != null && wId.isNotEmpty) {
          warehouseQtyDelta[wId] = (warehouseQtyDelta[wId] ?? 0) + item.quantity;
        }
      }
      for (final entry in warehouseQtyDelta.entries) {
        await _sb.rpc('increment_warehouse_totals',
            params: {'p_wh': entry.key, 'p_pairs': entry.value, 'p_products': 0});
      }

      // Әр элемент үшін теріс sales_history жазбасы (себестоимостьты балансылау).
      final negSales = <Map<String, dynamic>>[];
      for (final item in model.items) {
        final key = '${item.productId}|${item.batchId}|${item.size}';
        negSales.add({
          'owner_uid': adminUid,
          'type': 'return',
          'return_id': model.id,
          'product_id': item.productId,
          'product_name': item.productTitle,
          'batch_id': item.batchId,
          'selected_size': item.size,
          'sale_date': DateTime.now().toIso8601String(),
          'quantity': item.quantity,
          'total_price': -item.subtotal,
          'base_price': -item.subtotal,
          'discount_percent': 0.0,
          'discount_amount': 0.0,
          'seller_id': 'онлайн',
          'seller_name': 'Онлайн',
          'warehouse_id': (model.warehouseId != null &&
                  model.warehouseId!.isNotEmpty)
              ? model.warehouseId
              : null,
          'is_online': model.type == ReturnType.online,
          'order_id': model.orderId ?? '',
          'payment_method': method.name,
          'purchase_price': costByItem[key] ?? 0,
        });
      }
      if (negSales.isNotEmpty) {
        await _sb.from('sales_history').insert(negSales);
      }

      // Тапсырысты «Қайтарылды» күйіне ауыстырамыз.
      if ((model.orderId ?? '').isNotEmpty) {
        await _sb
            .from('orders')
            .update({'status': OrderModel.statusReturned}).eq(
                'id', model.orderId as String);
      }

      await _sb.from('returns').update({
        'status': ReturnStatus.refunded.name,
        'refund_method': method.name,
        'refunded_at': DateTime.now().toIso8601String(),
      }).eq('id', returnId);

      // Қор қайтарылды — тауар статусын жаңартамыз.
      for (final pid in model.items.map((i) => i.productId).toSet()) {
        await _sb
            .rpc('recompute_product_status', params: {'p_product': pid});
      }
    } catch (e) {
      debugPrint('[ReturnService.completeRefund] $e');
      rethrow;
    }
  }

  // ── OFFLINE returns (seller in-store) ─────────────────────────────────────────

  Future<List<SaleModel>> findRecentSales({
    required String adminUid,
    String? receiptNumber,
    String? query,
    int days = 14,
  }) async {
    try {
      final cutoff = DateTime.now().subtract(Duration(days: days));
      final saleRows = await _sb
          .from('sales_history')
          .select()
          .eq('owner_uid', adminUid)
          .order('sale_date', ascending: false)
          .limit(500);

      final returnRows =
          await _sb.from('returns').select('sale_id,status').eq('admin_uid', adminUid);
      final returnedSaleIds = <String>{};
      for (final data in returnRows) {
        if (data['status'] == ReturnStatus.rejected.name) continue;
        final sid = data['sale_id'] as String?;
        if (sid != null && sid.isNotEmpty) returnedSaleIds.add(sid);
      }

      var sales = saleRows
          .map(SaleModel.fromMap)
          .where((s) =>
              !s.isReturn &&
              !s.isWriteOff && // списание возвратқа жатпайды
              !s.isOnline &&
              s.saleDate.isAfter(cutoff) &&
              !returnedSaleIds.contains(s.id))
          .toList();

      final effectiveQuery = query?.trim().isNotEmpty == true
          ? query!.trim()
          : receiptNumber?.trim();
      if (effectiveQuery != null && effectiveQuery.isNotEmpty) {
        final q = effectiveQuery.toUpperCase();
        sales = sales
            .where((s) =>
                s.id.toUpperCase().contains(q) ||
                s.receiptNumber.toUpperCase().contains(q) ||
                s.productName.toUpperCase().contains(q))
            .toList();
      }
      return sales;
    } catch (e) {
      debugPrint('[ReturnService.findRecentSales] $e');
      rethrow;
    }
  }

  Future<ReturnModel> createOfflineReturn({
    required String adminUid,
    required SaleModel sourceSale,
    required List<ReturnItem> items,
    required ReturnReason reason,
    required RefundMethod method,
    required String sellerId,
  }) async {
    try {
      // Бір сатылым — бір рет қайтару.
      final existing = await _sb
          .from('returns')
          .select('sale_id,status')
          .eq('admin_uid', adminUid)
          .eq('sale_id', sourceSale.id);
      final alreadyReturned = existing
          .any((d) => d['status'] != ReturnStatus.rejected.name);
      if (alreadyReturned) {
        throw ReturnException(
            tr('По этой продаже возврат уже был оформлен.', 'Бұл сатылым бойынша қайтару бұрын жасалған.'));
      }

      final returnId = await _nextReturnId(adminUid);
      final now = DateTime.now();
      final sellerName = AppUser.current.name;

      final model = ReturnModel(
        id: returnId,
        adminUid: adminUid,
        sellerId: sellerId,
        warehouseId:
            sourceSale.warehouseId.isNotEmpty ? sourceSale.warehouseId : null,
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
      await _sb.from('returns').insert(model.toRow());

      // Қойманы қалпына келтіру + warehouse есептегіш.
      final batchIds = items.map((i) => i.batchId).toSet().toList();
      final whByBatch = <String, String?>{};
      if (batchIds.isNotEmpty) {
        final brows = await _sb
            .from('batches')
            .select('id,warehouse_id')
            .inFilter('id', batchIds);
        for (final b in brows) {
          whByBatch[b['id'] as String] = b['warehouse_id'] as String?;
        }
      }
      final warehouseQtyDelta = <String, int>{};
      for (final item in items) {
        await _sb.rpc('adjust_batch_sizes', params: {
          'p_batch': item.batchId,
          'p_deltas': {item.size: item.quantity},
          'p_field': 'sizes_quantity',
          'p_guard': false,
        });
        final wId = whByBatch[item.batchId];
        if (wId != null && wId.isNotEmpty) {
          warehouseQtyDelta[wId] = (warehouseQtyDelta[wId] ?? 0) + item.quantity;
        }
      }
      for (final entry in warehouseQtyDelta.entries) {
        await _sb.rpc('increment_warehouse_totals',
            params: {'p_wh': entry.key, 'p_pairs': entry.value, 'p_products': 0});
      }

      // Теріс sales_history жазбасы (түпнұсқа сатушыға қарсы).
      await _sb.from('sales_history').insert({
        'owner_uid': adminUid,
        'type': 'return',
        'return_id': returnId,
        'product_id': items.isNotEmpty ? items.first.productId : null,
        'product_name': items.isNotEmpty ? items.first.productTitle : '',
        'batch_id': items.isNotEmpty ? items.first.batchId : null,
        'sale_date': now.toIso8601String(),
        'quantity': items.fold(0, (s, i) => s + i.quantity),
        'total_price': -model.totalAmount,
        'base_price': -model.totalAmount,
        'discount_percent': 0.0,
        'discount_amount': 0.0,
        'seller_id':
            sourceSale.sellerId.isNotEmpty ? sourceSale.sellerId : sellerId,
        'seller_name': sourceSale.sellerName.isNotEmpty
            ? sourceSale.sellerName
            : sellerName,
        'warehouse_id':
            sourceSale.warehouseId.isEmpty ? null : sourceSale.warehouseId,
        'is_online': false,
        'payment_method': method.name,
        'purchase_price': sourceSale.purchasePrice,
      });

      for (final pid in items.map((i) => i.productId).toSet()) {
        await _sb
            .rpc('recompute_product_status', params: {'p_product': pid});
      }
      return model;
    } catch (e) {
      debugPrint('[ReturnService.createOfflineReturn] $e');
      rethrow;
    }
  }

  // ── ADMIN side ────────────────────────────────────────────────────────────────

  Stream<List<ReturnModel>> watchAllReturns(String adminUid) => _sb
      .from('returns')
      .stream(primaryKey: ['id'])
      .eq('admin_uid', adminUid)
      .order('created_at', ascending: false)
      .map((rows) => rows.map(ReturnModel.fromRow).toList());

  Future<ReturnAnalytics> computeAnalytics({
    required String adminUid,
    required DateRange range,
  }) async {
    try {
      final returnRows =
          await _sb.from('returns').select().eq('admin_uid', adminUid);
      final allReturns = returnRows
          .map(ReturnModel.fromRow)
          .where((r) =>
              r.createdAt.isAfter(range.from) && r.createdAt.isBefore(range.to))
          .toList();

      final saleRows = await _sb
          .from('sales_history')
          .select('sale_date,type')
          .eq('owner_uid', adminUid);
      final totalSales = saleRows.where((d) {
        final raw = d['sale_date'];
        final date = raw is String ? DateTime.tryParse(raw) : null;
        return d['type'] != 'return' &&
            d['type'] != 'writeoff' &&
            date != null &&
            date.isAfter(range.from) &&
            date.isBefore(range.to);
      }).length;

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

      // Кілттер — UID; UI-да адам аты көрінуі үшін users-тен атқа айналдырамыз
      // (returns кестесінде seller_name сақталмайды).
      if (perSellerClosed.isNotEmpty) {
        final names = <String, String>{};
        try {
          final nameRows = await _sb
              .from('users')
              .select('id,name')
              .inFilter('id', perSellerClosed.keys.toList());
          for (final row in nameRows) {
            names[row['id'] as String] =
                ((row['name'] as String?) ?? '').trim();
          }
        } catch (_) {} // ат табылмаса — төмендегі fallback қолданылады
        final byName = <String, int>{};
        perSellerClosed.forEach((uid, cnt) {
          final n = names[uid] ?? '';
          final label = n.isNotEmpty
              ? n
              : (uid == adminUid
                  ? tr('Владелец', 'Иесі')
                  : tr('Продавец', 'Сатушы'));
          byName[label] = (byName[label] ?? 0) + cnt;
        });
        perSellerClosed
          ..clear()
          ..addAll(byName);
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
