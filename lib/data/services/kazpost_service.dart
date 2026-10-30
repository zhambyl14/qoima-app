import 'package:supabase_flutter/supabase_flutter.dart';

/// Модератор қойған бір бағыт (0081). Бағыт бағытталған: Астана→Тараз пен
/// Тараз→Астана әртүрлі болуы мүмкін.
class KazpostRoute {
  final String fromCity;
  final String toCity;
  final double price;
  final bool isActive;

  const KazpostRoute({
    required this.fromCity,
    required this.toCity,
    required this.price,
    this.isActive = true,
  });

  factory KazpostRoute.fromMap(Map<String, dynamic> m) => KazpostRoute(
        fromCity: m['from_city'] as String? ?? '',
        toCity: m['to_city'] as String? ?? '',
        price: (m['price'] as num?)?.toDouble() ?? 0,
        isActive: m['is_active'] as bool? ?? true,
      );

  Map<String, dynamic> toMap() => {
        'from_city': fromCity,
        'to_city': toCity,
        'price': price,
        'is_active': isActive,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
}

/// Казпочта: баға, тариф кестесі, жөнелту және аяқтау (0081).
///
/// Баға есебі де, рұқсат та серверде: клиент тек [quote] нәтижесін көрсетеді,
/// ал orders триггері сол санды қайта салыстырады.
class KazpostService {
  final SupabaseClient _sb = Supabase.instance.client;

  static const _defaultFeeKey = 'delivery_kazpost_default_fee';

  /// adminUid → баға. Жауапта жоқ дүкенге Казпочта жоқ (бағыт жабық, дүкен бас
  /// тартқан немесе жалауша өшік).
  Future<Map<String, double>> quote({
    required List<String> adminUids,
    required String toCity,
  }) async {
    final ids = adminUids.where((e) => e.isNotEmpty).toSet().toList();
    if (ids.isEmpty || toCity.trim().isEmpty) return const {};
    final res = await _sb.rpc('kazpost_quote', params: {
      'p_admins': ids,
      'p_to': toCity,
    });
    if (res is! Map) return const {};
    return {
      for (final e in res.entries)
        e.key.toString(): (e.value as num).toDouble(),
    };
  }

  // ── Дүкен ────────────────────────────────────────────────────────────────

  Future<void> markShipped(String orderId, String tracking) async {
    await _sb.rpc('kazpost_mark_shipped', params: {
      'p_order': orderId,
      'p_tracking': tracking,
    });
  }

  /// Клиент «алдым» деді, немесе дүкен жіберген соң 7 күннен кейін жабады.
  Future<void> completeOrder(String orderId) async {
    await _sb.rpc('kazpost_complete_order', params: {'p_order': orderId});
  }

  /// Дүкен Казпочтамен жібергісі келмесе. toMap-та ӘДЕЙІ ЖОҚ, сондықтан бөлек.
  Future<void> setStoreEnabled(String adminUid, bool enabled) async {
    await _sb
        .from('stores')
        .update({'kazpost_enabled': enabled}).eq('admin_uid', adminUid);
  }

  // ── Модератор ────────────────────────────────────────────────────────────

  Future<List<KazpostRoute>> getRoutes() async {
    final rows = await _sb.from('kazpost_tariffs').select();
    return (rows as List)
        .map((e) => KazpostRoute.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// Бір қаладан шығатын бағыттарды бір әрекетпен сақтайды. [routes]-та жоқ
  /// баға өшіріледі де, ол бағытқа әдепкі баға жүреді.
  Future<void> saveRoutesFrom(
    String fromCity,
    List<KazpostRoute> routes, {
    required List<String> clearedToCities,
  }) async {
    if (routes.isNotEmpty) {
      await _sb
          .from('kazpost_tariffs')
          .upsert(routes.map((r) => r.toMap()).toList());
    }
    if (clearedToCities.isNotEmpty) {
      await _sb
          .from('kazpost_tariffs')
          .delete()
          .eq('from_city', fromCity)
          .inFilter('to_city', clearedToCities);
    }
  }

  /// null = әдепкі баға жоқ: кестеде жоқ бағыт жабық.
  Future<double?> getDefaultFee() async {
    final row = await _sb
        .from('app_settings')
        .select('value')
        .eq('key', _defaultFeeKey)
        .maybeSingle();
    return double.tryParse((row?['value'] ?? '').toString().trim());
  }

  Future<void> setDefaultFee(double? fee) async {
    await _sb.from('app_settings').upsert({
      'key': _defaultFeeKey,
      'value': fee == null ? '' : fee.toStringAsFixed(0),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }
}
