import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/order_model.dart';
import '../models/return_model.dart';

/// Курьер табысының БӨЛШЕКТЕЛГЕН қорытындысы (0053 — `courier_stats()`).
///
/// Барлық сан ашық: жеткізуден қанша, возработтан қанша, әлі клиенттен
/// алынбағаны қанша. Жасырын жол жоқ — курьер өз ақшасын толық көреді.
class CourierStats {
  final int todayCount, weekCount, totalCount;
  final double todayFee, weekFee, totalFee;
  /// Жеткізуден жиналған ақы.
  final double deliveryFee;
  /// Возврат тасудан жиналған ақы.
  final double returnFee;
  /// Клиент әлі төлемеген (курьер алмаған) ақы.
  final double uncollected;
  /// Қоймаға қайтаруы керек, әлі тапсырылмаған өлшемдер саны.
  final int pendingLegs;

  const CourierStats({
    this.todayCount = 0,
    this.weekCount = 0,
    this.totalCount = 0,
    this.todayFee = 0,
    this.weekFee = 0,
    this.totalFee = 0,
    this.deliveryFee = 0,
    this.returnFee = 0,
    this.uncollected = 0,
    this.pendingLegs = 0,
  });

  factory CourierStats.fromMap(Map<String, dynamic> m) => CourierStats(
        todayCount: (m['todayCount'] as num?)?.toInt() ?? 0,
        weekCount: (m['weekCount'] as num?)?.toInt() ?? 0,
        totalCount: (m['totalCount'] as num?)?.toInt() ?? 0,
        todayFee: (m['todayFee'] as num?)?.toDouble() ?? 0,
        weekFee: (m['weekFee'] as num?)?.toDouble() ?? 0,
        totalFee: (m['totalFee'] as num?)?.toDouble() ?? 0,
        deliveryFee: (m['deliveryFee'] as num?)?.toDouble() ?? 0,
        returnFee: (m['returnFee'] as num?)?.toDouble() ?? 0,
        uncollected: (m['uncollected'] as num?)?.toDouble() ?? 0,
        pendingLegs: (m['pendingLegs'] as num?)?.toInt() ?? 0,
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
  ///
  /// [feeCollected] — жеткізу ақысын клиенттен НАҚТЫ алды ма (0053). Ақы
  /// курьердікі әрі клиент оны тікелей курьерге береді, сондықтан бұл
  /// курьердің өз есебі: false болса, сома «алынбаған» болып қалады.
  Future<void> completeOrder(String orderId,
          {List<int> swappedIndexes = const [], bool feeCollected = true}) =>
      _sb.rpc('courier_complete_order', params: {
        'p_order': orderId,
        'p_swaps': swappedIndexes,
        'p_fee_collected': feeCollected,
      });

  /// Клиент бас тартты — тауар қоймаға оралады, тапсырыс болдырылмайды.
  /// Жеткізу ақысы қайтарылмайды (клиент себетте келіскен), сондықтан курьер
  /// оны алды ма — [feeCollected] арқылы өзі белгілейді (0056).
  ///
  /// ⚠️ «Өлшеп көру» тапсырысында бұл жол ЖОҚ: онда әрқашан бір өлшем
  /// клиентте қалады, екіншісі қайтады (UI бұл батырманы жасырады).
  Future<void> returnOrder(String orderId, String reason,
          {bool feeCollected = true}) =>
      _sb.rpc('courier_return_order', params: {
        'p_order': orderId,
        'p_reason': reason,
        'p_fee_collected': feeCollected,
      });

  // ── Курьермен ҚАЙТАРУ (возврат) — 0052 ─────────────────────────────────────
  //  Клиент қайтаруды курьермен рәсімдеді. Курьер клиенттен тауарды алып,
  //  дүкенге жеткізеді. Ақысы курьердікі әрі қайтарылатын тауар сомасынан
  //  ЕШҚАШАН шегерілмейді.

  /// 0054-тен бастап RPC-лер `jsonb` МАССИВІН қайтарады (дүкен аты, қойма
  /// мекенжайы қосылған байытылған жол).
  List<ReturnModel> _returns(dynamic res) => res is List
      ? res
          .map((r) => ReturnModel.fromRow(Map<String, dynamic>.from(r as Map)))
          .toList()
      : const [];

  /// Дүкен РАСТАҒАН (approved), курьермен қайтарылатын, әлі ешкім алмағандар.
  Future<List<ReturnModel>> getAvailableReturns() async =>
      _returns(await _sb.rpc('courier_available_returns'));

  Future<List<ReturnModel>> getMyReturns() async =>
      _returns(await _sb.rpc('courier_my_returns'));

  Future<void> takeReturn(String returnId) =>
      _sb.rpc('courier_take_return', params: {'p_return': returnId});

  /// Клиенттен тауарды алды. [feeCollected] — қайтару жеткізуінің ақысын
  /// клиенттен алды ма (ол ақы курьердікі, қайтарылатын сомадан шегерілмейді).
  Future<void> pickupReturn(String returnId, {bool feeCollected = true}) =>
      _sb.rpc('courier_pickup_return',
          params: {'p_return': returnId, 'p_fee_collected': feeCollected});

  /// Дүкенге тапсырды (одан әрі ақша қайтару дүкен экранында жүреді).
  Future<void> deliverReturn(String returnId) =>
      _sb.rpc('courier_deliver_return', params: {'p_return': returnId});
}
