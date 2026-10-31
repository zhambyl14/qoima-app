import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/app_user.dart';

/// Дүкеннің өз тауарларынан алынған «әдеттері»: форма соған бейімделеді
/// (өз категориялары алдымен, өз елдері чип болып).
///
/// БІР жеңіл сұрау: тек `category_key, country` бағандары, бір рет. Тауар
/// бойынша қосымша сұрау жоқ (firestore_perf_conventions: N+1 болмасын).
class StoreUsage {
  /// categoryKey → тауар саны.
  final Map<String, int> categoryCounts;

  /// Бұрын қолданылған елдер, жиілігі бойынша кему ретімен (жазылуы сақталған).
  final List<String> countries;

  /// Дүкеннің өз категориясы (өтінімдегі: Обувь/Одежда/…); белгісіз болса бос.
  final String storeCategory;

  const StoreUsage({
    this.categoryCounts = const {},
    this.countries = const [],
    this.storeCategory = '',
  });

  /// `products` жолдарынан жинау (тазы — тесттеледі). Бос/жарамсыз мәндер
  /// өткізіліп жіберіледі; ел регистрге тәуелсіз біріктіріледі, алғашқы жазылуы
  /// көрсетіледі.
  factory StoreUsage.fromRows(Iterable<Map<String, dynamic>> rows,
      {String storeCategory = ''}) {
    final cats = <String, int>{};
    final countryCount = <String, int>{};
    final countryLabel = <String, String>{};
    for (final r in rows) {
      final k = (r['category_key'] as String? ?? '').trim();
      // Ескі аяқ киім тауарлары category_key-сіз: effectiveCategoryKey = shoes.
      final key = k.isEmpty ? 'shoes' : k;
      cats[key] = (cats[key] ?? 0) + 1;
      final c = (r['country'] as String? ?? '').trim();
      if (c.isEmpty) continue;
      final norm = c.toLowerCase();
      countryCount[norm] = (countryCount[norm] ?? 0) + 1;
      countryLabel.putIfAbsent(norm, () => c);
    }
    final sorted = countryCount.keys.toList()
      ..sort((a, b) => countryCount[b]!.compareTo(countryCount[a]!));
    return StoreUsage(
      categoryCounts: cats,
      countries: [for (final n in sorted) countryLabel[n]!],
      storeCategory: storeCategory,
    );
  }

  /// Желі/RLS қатесінде бос қайтады: форма әдепкі тізіммен жұмыс істей береді.
  static Future<StoreUsage> load({SupabaseClient? client}) async {
    final sb = client ?? Supabase.instance.client;
    final owner = AppUser.current.ownerUid.isNotEmpty
        ? AppUser.current.ownerUid
        : (sb.auth.currentUser?.id ?? '');
    if (owner.isEmpty) return const StoreUsage();
    try {
      final results = await Future.wait<Object?>([
        sb.from('products').select('category_key, country').eq('owner_uid', owner),
        sb
            .from('stores')
            .select('category')
            .eq('admin_uid', owner)
            .maybeSingle(),
      ]);
      final rows = (results[0] as List).cast<Map<String, dynamic>>();
      final store = results[1] as Map<String, dynamic>?;
      return StoreUsage.fromRows(rows,
          storeCategory: (store?['category'] as String? ?? '').trim());
    } catch (_) {
      return const StoreUsage();
    }
  }
}
