import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/order_model.dart';

/// Курьер табысының қысқаша қорытындысы (0051 — `courier_stats()`).
class CourierStats {
  final int todayCount, weekCount, totalCount;
  final double todayFee, weekFee, totalFee;
  const CourierStats({
    this.todayCount = 0,
    this.weekCount = 0,
    this.totalCount = 0,
    this.todayFee = 0,
    this.weekFee = 0,
    this.totalFee = 0,
  });

  factory CourierStats.fromMap(Map<String, dynamic> m) => CourierStats(
        todayCount: (m['todayCount'] as num?)?.toInt() ?? 0,
        weekCount: (m['weekCount'] as num?)?.toInt() ?? 0,
        totalCount: (m['totalCount'] as num?)?.toInt() ?? 0,
        todayFee: (m['todayFee'] as num?)?.toDouble() ?? 0,
        weekFee: (m['weekFee'] as num?)?.toDouble() ?? 0,
        totalFee: (m['totalFee'] as num?)?.toDouble() ?? 0,
      );
}

/// Курьер жағындағы деректер сервисі.
///
/// БАРЛЫҚ операция SECURITY DEFINER RPC арқылы (0051): курьер бөтен дүкеннің
/// тапсырысымен жұмыс істейді, ал оны RLS policy-мен сипаттау қалалар бойынша
/// JOIN талап етеді әрі оңай тесіледі. Әр RPC шақырушының белсенді курьер
/// екенін өзі тексереді.
class CourierService {
  final SupabaseClient _sb = Supabase.instance.client;

  List<OrderModel> _parse(dynamic res) {
    if (res is! List) return const [];
    return res
        .map((r) => OrderModel.fromMap(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  /// Өз қаласындағы, төлемі расталған, әлі ешкім алмаған жеткізулер.
  Future<List<OrderModel>> getAvailableOrders() async =>
      _parse(await _sb.rpc('courier_available_orders'));

  /// Өзіне бекітілгендері (белсендісі алда) + 30 күндік тарих.
  Future<List<OrderModel>> getMyOrders() async =>
      _parse(await _sb.rpc('courier_my_orders'));

  Future<CourierStats> getStats() async {
    try {
      final res = await _sb.rpc('courier_stats');
      if (res is Map) {
        return CourierStats.fromMap(Map<String, dynamic>.from(res));
      }
    } catch (_) {}
    return const CourierStats();
  }

  Future<void> takeOrder(String orderId) =>
      _sb.rpc('courier_take_order', params: {'p_order': orderId});

  Future<void> dropOrder(String orderId) =>
      _sb.rpc('courier_drop_order', params: {'p_order': orderId});

  /// Қоймадан алу — дүкен көрсететін [code] (pickup_code) арқылы расталады:
  /// курьердің қоймаға НАҚТЫ келгенінің дәлелі.
  Future<void> pickupOrder(String orderId, String code) => _sb.rpc(
      'courier_pickup_order', params: {'p_order': orderId, 'p_code': code});

  /// Клиентке беру. [swappedIndexes] — «өлшеп көру» бойынша клиент қосымша
  /// өлшемді алған позициялардың items ішіндегі индекстері (мыс. 38-дің
  /// орнына 39). Негізгі өлшем қоймаға қайтады, қосымшасы сатылады.
  Future<void> completeOrder(String orderId,
          {List<int> swappedIndexes = const []}) =>
      _sb.rpc('courier_complete_order',
          params: {'p_order': orderId, 'p_swaps': swappedIndexes});

  /// Клиент бас тартты — тауар қоймаға оралады, тапсырыс болдырылмайды.
  /// Жеткізу ақысы қайтарылмайды (клиент себетте келіскен).
  ///
  /// ⚠️ «Өлшеп көру» тапсырысында бұл жол ЖОҚ: онда әрқашан бір өлшем
  /// клиентте қалады, екіншісі қайтады (UI бұл батырманы жасырады).
  Future<void> returnOrder(String orderId, String reason) => _sb.rpc(
      'courier_return_order', params: {'p_order': orderId, 'p_reason': reason});

  // ── Курьермен ҚАЙТАРУ (возврат) — 0052 ─────────────────────────────────────
  //  Клиент қайтаруды курьермен рәсімдеді. Курьер клиенттен тауарды алып,
  //  дүкенге жеткізеді. Ақысы курьердікі әрі қайтарылатын тауар сомасынан
  //  ЕШҚАШАН шегерілмейді.

  List<Map<String, dynamic>> _rows(dynamic res) => res is List
      ? res.map((r) => Map<String, dynamic>.from(r as Map)).toList()
      : const [];

  Future<List<Map<String, dynamic>>> getAvailableReturns() async =>
      _rows(await _sb.rpc('courier_available_returns'));

  Future<List<Map<String, dynamic>>> getMyReturns() async =>
      _rows(await _sb.rpc('courier_my_returns'));

  Future<void> takeReturn(String returnId) =>
      _sb.rpc('courier_take_return', params: {'p_return': returnId});

  /// Клиенттен тауарды алды.
  Future<void> pickupReturn(String returnId) =>
      _sb.rpc('courier_pickup_return', params: {'p_return': returnId});

  /// Дүкенге тапсырды (одан әрі ақша қайтару дүкен экранында жүреді).
  Future<void> deliverReturn(String returnId) =>
      _sb.rpc('courier_deliver_return', params: {'p_return': returnId});
}
