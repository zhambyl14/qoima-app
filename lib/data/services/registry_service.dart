import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/error_text.dart';
import '../../core/lang.dart';
import '../models/registry_model.dart';

/// «Той тілек тізімі» (0069) сервисі.
///
/// Иесінің CRUD-ы — тікелей кестелер (RLS: тек өз жолдары). Қонақтың жария
/// көрінісі, брондау және босату — тек SECURITY DEFINER RPC арқылы: claims
/// кестесіне клиент жаза да, оқи да алмайды (қонақ жеке басы құпия — тосын сый).
class RegistryService {
  final SupabaseClient _sb = Supabase.instance.client;

  String get _uid => _sb.auth.currentUser?.id ?? '';

  // ── Иесі: тізімдер ───────────────────────────────────────────────────────

  /// Менің тізімдерім (realtime). Экран initState-те бір рет жазылады.
  Stream<List<GiftRegistry>> watchMyRegistries() {
    final uid = _uid;
    if (uid.isEmpty) return Stream.value(const []);
    return _sb
        .from('gift_registries')
        .stream(primaryKey: ['id'])
        .eq('owner_uid', uid)
        .order('created_at', ascending: false)
        .map((rows) => rows.map(GiftRegistry.fromMap).toList());
  }

  /// Бір реттік тізім (тауар бетіндегі «Тізімге қосу» парағы үшін).
  Future<List<GiftRegistry>> getMyRegistries() async {
    final uid = _uid;
    if (uid.isEmpty) return const [];
    final rows = await _sb
        .from('gift_registries')
        .select()
        .eq('owner_uid', uid)
        .order('created_at', ascending: false);
    return rows.map(GiftRegistry.fromMap).toList();
  }

  /// Карточкадағы прогресс: registry_id → сандар (қонақ идентификаторынсыз).
  Future<Map<String, RegistrySummary>> getMySummaries() async {
    final res = await _sb.rpc('get_my_registries_summary');
    final out = <String, RegistrySummary>{};
    if (res is List) {
      for (final e in res) {
        if (e is Map) {
          final m = Map<String, dynamic>.from(e);
          out['${m['registry_id']}'] = RegistrySummary.fromMap(m);
        }
      }
    }
    return out;
  }

  Future<GiftRegistry> createRegistry({
    required String title,
    required String occasion,
    DateTime? eventDate,
    String message = '',
    String city = '',
  }) async {
    final row = await _sb
        .from('gift_registries')
        .insert({
          'owner_uid': _uid,
          'title': title.trim(),
          'occasion': occasion,
          'event_date': eventDate == null ? null : _dateOnly(eventDate),
          'message': message.trim().isEmpty ? null : message.trim(),
          'city': city.trim().isEmpty ? null : city.trim(),
        })
        .select()
        .single();
    return GiftRegistry.fromMap(row);
  }

  Future<void> updateRegistry(
    String id, {
    required String title,
    required String occasion,
    DateTime? eventDate,
    String message = '',
    String city = '',
    bool? isActive,
  }) async {
    await _sb.from('gift_registries').update({
      'title': title.trim(),
      'occasion': occasion,
      'event_date': eventDate == null ? null : _dateOnly(eventDate),
      'message': message.trim().isEmpty ? null : message.trim(),
      'city': city.trim().isEmpty ? null : city.trim(),
      if (isActive != null) 'is_active': isActive,
    }).eq('id', id);
  }

  /// Тек «қонақтарға ашық» жалауын ауыстырады (қалған өрістерге тимейді).
  Future<void> setActive(String id, bool isActive) async {
    await _sb
        .from('gift_registries')
        .update({'is_active': isActive}).eq('id', id);
  }

  Future<void> deleteRegistry(String id) async {
    await _sb.from('gift_registries').delete().eq('id', id);
  }

  String _dateOnly(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // ── Иесі: позициялар ─────────────────────────────────────────────────────

  /// Тізімге тауар қосады. Дәл сол тауар+өлшем бұрыннан болса — саны өседі
  /// (жаңа жол жасалмайды; unique index қайталауды көтермейді).
  Future<void> addItem({
    required String registryId,
    required String productId,
    required String adminUid,
    required String productName,
    required String imageUrl,
    required double price,
    String size = '',
    int qty = 1,
    String note = '',
  }) async {
    // Бар позицияның санын көбейтеді; 20-ға жетіп қойса — сәтті сияқты
    // көрсетпей, нақты қате береді (registry_qty_max).
    Future<bool> bump() async {
      final existing = await _sb
          .from('gift_registry_items')
          .select('id, qty_wanted')
          .eq('registry_id', registryId)
          .eq('product_id', productId)
          .eq('size', size)
          .maybeSingle();
      if (existing == null) return false;
      final cur = (existing['qty_wanted'] as num?)?.toInt() ?? 1;
      if (cur >= 20) throw Exception('registry_qty_max');
      await _sb
          .from('gift_registry_items')
          .update({'qty_wanted': (cur + qty).clamp(1, 20)}).eq(
              'id', existing['id'] as String);
      return true;
    }

    if (await bump()) return;
    try {
      await _sb.from('gift_registry_items').insert({
        'registry_id': registryId,
        'product_id': productId,
        'admin_uid': adminUid,
        'product_name': productName,
        'image_url': imageUrl,
        'size': size,
        'price': price,
        'qty_wanted': qty.clamp(1, 20),
        'note': note.trim().isEmpty ? null : note.trim(),
      });
    } on PostgrestException catch (e) {
      // Қос басу / екі құрылғы: unique (registry, product, size) бұзылды —
      // позиция бір сәт бұрын қосылған, сондықтан санын көбейтеміз.
      if (e.code == '23505' && await bump()) return;
      rethrow;
    }
  }

  Future<void> updateItem(String itemId, {int? qtyWanted, String? note}) async {
    final patch = <String, dynamic>{
      if (qtyWanted != null) 'qty_wanted': qtyWanted.clamp(1, 20),
      if (note != null) 'note': note.trim().isEmpty ? null : note.trim(),
    };
    if (patch.isEmpty) return;
    await _sb.from('gift_registry_items').update(patch).eq('id', itemId);
  }

  Future<void> removeItem(String itemId) async {
    await _sb.from('gift_registry_items').delete().eq('id', itemId);
  }

  // ── Қонақ ────────────────────────────────────────────────────────────────

  /// Жария көрініс (guest те шақыра алады). Табылмаса / өшірілген — null.
  Future<PublicRegistry?> getPublic(String token) async {
    final res = await _sb.rpc('get_registry_public', params: {
      'p_token': token,
    });
    if (res is Map) {
      return PublicRegistry.fromMap(Map<String, dynamic>.from(res));
    }
    return null;
  }

  /// Позицияны қонаққа брондайды → claim id. Қате кодтары [registryErrorText].
  Future<String> reserve(String itemId, {int qty = 1}) async {
    final res = await _sb.rpc('reserve_registry_item', params: {
      'p_item': itemId,
      'p_qty': qty,
    });
    return '$res';
  }

  Future<void> release(String claimId) async {
    await _sb.rpc('release_registry_claim', params: {'p_claim': claimId});
  }

  /// Берілген brond id-лерінің ішінен әлі жарамдыларын қайтарады
  /// (себеттегі ескірген тілек-жолдарды анықтау үшін). Қате болса — null
  /// (желі мәселесінде себетті бұғаттамаймыз).
  Future<Set<String>?> validClaimIds(Iterable<String> ids) async {
    final list = ids.where((e) => e.isNotEmpty).toList();
    if (list.isEmpty) return <String>{};
    try {
      final res = await _sb.rpc('registry_claims_still_valid', params: {
        'p_ids': list,
      });
      if (res is List) return res.map((e) => '$e').toSet();
    } catch (_) {}
    return null;
  }
}

/// RPC / RLS қателерін пайдаланушыға түсінікті мәтінге айналдырады.
/// Postgres `raise exception 'code'` коды PostgrestException.message ішінде.
String registryErrorText(Object e) {
  final raw =
      e is PostgrestException ? '${e.message} ${e.details ?? ''}' : '$e';
  bool has(String code) => raw.contains(code);
  if (has('feature_disabled')) {
    return tr('Функция временно отключена', 'Функция уақытша өшірулі');
  }
  if (has('registry_item_taken')) {
    return tr('Этот подарок уже выбрал другой гость',
        'Бұл сыйлықты басқа қонақ таңдап қойған');
  }
  if (has('registry_inactive')) {
    return tr('Список желаний закрыт', 'Тілек тізімі жабылған');
  }
  if (has('registry_own_item')) {
    return tr('Нельзя дарить подарок из своего списка',
        'Өз тізіміңізден сыйлық алуға болмайды');
  }
  if (has('registry_claim_limit')) {
    return tr('Слишком много активных броней — оформите или отмените часть',
        'Белсенді брондар тым көп — біразын рәсімдеңіз немесе бас тартыңыз');
  }
  if (has('registry_claim_in_order')) {
    return tr('Бронь уже в заказе — отмените заказ, чтобы освободить',
        'Бронь тапсырысқа кіріп кеткен — босату үшін тапсырысты бас тартыңыз');
  }
  if (has('registry_claim_not_active') || has('not_your_claim')) {
    return tr('Бронь уже неактивна', 'Бронь қазірдің өзінде белсенді емес');
  }
  if (has('registry_limit')) {
    return tr('Достигнут лимит списков (20)', 'Тізім лимиті толды (20)');
  }
  if (has('registry_items_limit')) {
    return tr('В списке не может быть больше 100 товаров',
        'Тізімде 100 тауардан көп болмайды');
  }
  if (has('registry_qty_max')) {
    return tr('Этот товар уже добавлен в максимальном количестве (20)',
        'Бұл тауар максимал санда (20) қосылған');
  }
  if (has('registry_item_unavailable')) {
    return tr('Товара сейчас нет в наличии', 'Тауар қазір қоймада жоқ');
  }
  if (has('registry_item_not_found')) {
    return tr('Подарок больше недоступен', 'Сыйлық енді қолжетімсіз');
  }
  if (has('not_authenticated')) {
    return tr('Войдите в аккаунт', 'Аккаунтқа кіріңіз');
  }
  if (has('invalid_qty')) {
    return tr('Некорректное количество', 'Саны дұрыс емес');
  }
  return friendlyError(e);
}
