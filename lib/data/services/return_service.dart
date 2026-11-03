import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/return_model.dart';
import '../models/sale_model.dart';
import '../../core/app_user.dart';

import '../../core/lang.dart';
import '../../core/error_text.dart';
/// Қайтару (возврат) сервисі (Supabase).
class ReturnService {
  final SupabaseClient _sb = Supabase.instance.client;

  // ── ID generation (атомды, дублсіз) ────────────────────────────────────────────

  /// Қайтару жазбасын АТОМДЫ реттік id-мен енгізеді. Ескі MAX+1 сканы (клиент
  /// жақта) read-after-write кідірісі/қатар жазуда бірдей id беріп,
  /// `returns_pkey` дублін тудыратын — оның орнына серверлік `next_counter`
  /// RPC-ін қолданамыз. Ескі жазбалармен (басқа нөмірлеу схемасы) сирек қиылыс
  /// болса — 23505-те келесі нөмірге өтіп қайталаймыз.
  Future<ReturnModel> _insertReturnWithCounter(
    String adminUid,
    ReturnModel Function(String id) build,
  ) async {
    final year = DateTime.now().year;
    PostgrestException? last;
    for (var attempt = 0; attempt < 15; attempt++) {
      final raw = await _sb.rpc('next_counter',
          params: {'p_owner': adminUid, 'p_name': 'return_$year'});
      final n = (raw as num).toInt();
      final id = 'RET-$year-${n.toString().padLeft(4, '0')}';
      final model = build(id);
      try {
        await _sb.from('returns').insert(model.toRow());
        return model;
      } on PostgrestException catch (e) {
        if (e.code == '23505') {
          last = e; // id бос емес (ескі жазба) — келесі нөмірге өтеміз
          continue;
        }
        rethrow;
      }
    }
    throw last ?? ReturnException(tr('Не удалось создать возврат', 'Қайтару жасалмады'));
  }

  /// Толық аяқталған (refunded) қайтарулардың фотоларын 1-2 күн өткен соң
  /// Cloudinary-ден өшіру кезегіне қояды (0035 миграция). Best-effort —
  /// админ қосымша ашқанда drainOrphans-пен бірге шақырылады.
  Future<void> sweepReturnedPhotos() async {
    try {
      await _sb.rpc('sweep_returned_photos');
    } catch (_) {}
  }

  // ── CLIENT side ───────────────────────────────────────────────────────────────

  Future<ReturnModel> createReturnRequest({
    required ReturnRequestInput input,
  }) async {
    try {
      final now = DateTime.now();
      final model = await _insertReturnWithCounter(
        input.adminUid,
        (id) => ReturnModel(
          id: id,
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
          pickupAddress: input.pickupAddress,
          postTracking: input.postTracking,
          refundMethod: input.refundMethod,
          status: ReturnStatus.requested,
          createdAt: now,
        ),
      );
      return model;
    } catch (e) {
      debugPrint('[ReturnService.createReturnRequest] $e');
      // 0070: сыйлық тапсырысы — тек дүкенде ауыстыру, ақша қайтарылмайды.
      if (e is PostgrestException && e.message.contains('gift_exchange_only')) {
        throw ReturnException(tr(
            'Подарок можно только обменять — принесите товар в магазин (14 дней)',
            'Сыйлықты тек ауыстыруға болады — тауарды дүкенге апарыңыз (14 күн)'));
      }
      // 0073: тапсырыс жолы «қайтарылмайды» деп снапшотталса — сервер бөгейді.
      if (e is PostgrestException &&
          (e.message.contains('item_non_returnable') ||
              e.message.contains('order_required') ||
              e.message.contains('order_mismatch') ||
              e.message.contains('item_not_in_order'))) {
        throw ReturnException(policyErrorText(e));
      }
      rethrow;
    }
  }

  // ── Қайтару саясаты (0073) ────────────────────────────────────────────────────

  /// Superadmin: дүкенге «қайтарылмайтын тауар» белгісін қоюға рұқсат беру/алу.
  /// Рұқсат алынса — дүкеннің тауарларындағы белгілер сервер жағында тазаланады;
  /// қайтарылады: тазаланған тауар саны.
  Future<int> setStoreNonReturnablePermission(
      String adminUid, bool allowed) async {
    final res = await _sb.rpc('set_store_non_returnable_permission',
        params: {'p_admin_uid': adminUid, 'p_allowed': allowed});
    return (res as num?)?.toInt() ?? 0;
  }

  /// Иесі: дүкеннің жалпы қайтару ережесі (≤500, модерациясыз).
  Future<void> setStoreReturnNote(String note) =>
      _sb.rpc('set_store_return_note', params: {'p_note': note.trim()});

  /// Дүкеннің толық қайтару шарттары (0082).
  Future<void> setStoreReturnPolicy({
    required String mode,
    required int days,
    required List<String> conditions,
    required String note,
  }) =>
      _sb.rpc('set_store_return_policy', params: {
        'p_mode': mode,
        'p_days': days,
        'p_conditions': conditions,
        'p_note': note.trim(),
      });

  /// Клиент посылканы жіберген соң трегін жазады (0081).
  Future<void> setPostTracking(String returnId, String tracking) =>
      _sb.rpc('return_set_post_tracking', params: {
        'p_return': returnId,
        'p_tracking': tracking,
      });

  /// Клиент «түсінікті» деді: хабарлама бұл тапсырысқа қайта шықпайды (0082).
  Future<void> ackReturnNotice(String orderId) =>
      _sb.rpc('ack_return_notice', params: {'p_order': orderId});

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

  /// «Тауарды қабылдадым» — СЕРВЕРДЕ, жол құлпымен (0057).
  ///
  /// Қайтарады: `true` — осы шақыру қабылдады; `false` — біреу бұрын
  /// қабылдап қойған (қате емес, бірақ UI мұны хабарлауы керек).
  Future<bool> markReceived({
    required String adminUid,
    required String returnId,
    required bool itemConditionOk,
    required List<String> conditionPhotos,
  }) async {
    final res = await _sb.rpc('return_mark_received', params: {
      'p_return': returnId,
      'p_condition_ok': itemConditionOk,
      'p_photos': conditionPhotos,
    });
    return res == 'received';
  }

  /// received → refunded: қойманы қалпына келтіреді + теріс sales_history
  /// жазады. Қайтарады: `true` — осы шақыру аяқтады; `false` — біреу бұрын
  /// аяқтап қойған.
  ///
  /// ⚠️ БҮКІЛ ОПЕРАЦИЯ СЕРВЕРДЕ, БІР ТРАНЗАКЦИЯДА (0057). Бұрын мұнда
  /// «статусты оқы → шешім қабылда → жаз» тізбегі тұрған: админ мен сатушы
  /// бір возратты бір мезгілде қабылдаса, ЕКЕУІ де «әлі refunded емес» деп
  /// көріп, қойма ЕКІ РЕТ артатын (1 дана → 3 дана). Мұндай жарысты клиент
  /// кодында жеңу мүмкін емес — сондықтан шешім `for update` құлпымен
  /// базада қабылданады.
  Future<bool> completeRefund({
    required String adminUid,
    required String returnId,
    required RefundMethod method,
  }) async {
    try {
      final res = await _sb.rpc('return_complete_refund',
          params: {'p_return': returnId, 'p_method': method.name});
      return res == 'refunded';
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

      final now = DateTime.now();
      final sellerName = AppUser.current.name;

      final model = await _insertReturnWithCounter(
        adminUid,
        (id) => ReturnModel(
          id: id,
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
        ),
      );
      final returnId = model.id;

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
            d['type'] != 'service' && // қызмет кірісі — сатылым емес

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

/// 0073 саясат қателерін (feature_disabled, item_non_returnable, т.б.)
/// адамша мәтінге айналдырады. Басқа қателер — friendlyError-ға қалдырылады.
String policyErrorText(Object? e) {
  final raw = e is PostgrestException ? e.message : (e?.toString() ?? '');
  final m = raw.toLowerCase();
  if (m.contains('feature_disabled')) {
    return comingSoonText();
  }
  if (m.contains('item_non_returnable')) {
    return tr('Этот товар возврату не подлежит — вы согласились с этим при покупке.',
        'Бұл тауар қайтарылмайды — сатып алу кезінде осымен келіскенсіз.');
  }
  if (m.contains('order_required') ||
      m.contains('order_mismatch') ||
      m.contains('item_not_in_order')) {
    return tr('Возврат можно оформить только по вашему заказу и его товарам.',
        'Қайтаруды тек өз тапсырысыңыз және ондағы тауарлар бойынша ғана рәсімдеуге болады.');
  }
  if (m.contains('non_returnable_not_allowed')) {
    return tr('Модератор ещё не разрешил вашему магазину товары без возврата.',
        'Модератор дүкеніңізге қайтарылмайтын тауарға рұқсат әлі бермеген.');
  }
  if (m.contains('note_too_long')) {
    return tr('Текст слишком длинный (до 500 символов).',
        'Мәтін тым ұзын (500 таңбаға дейін).');
  }
  return friendlyError(e);
}
