import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_user.dart';
import '../../core/error_text.dart';
import '../../core/lang.dart';
import '../models/batch_model.dart';
import '../models/live_models.dart';
import '../models/product_model.dart';
import '../models/store_model.dart';

/// Эфирдің «сөресіндегі» тауар (хост таңдау торы үшін): қолжетімді саны
/// мен витрина бағасы (бірінші қолжетімді партияның effectivePrice-і).
class LiveShelfItem {
  final ProductModel product;
  final int available;
  final double price;
  const LiveShelfItem(
      {required this.product, required this.available, required this.price});
}

/// Live-сервис қатесі: [code] — SQL/edge fn-нің snake_case коды.
class LiveException implements Exception {
  final String code;
  final String message;
  const LiveException(this.code, this.message);
  @override
  String toString() => message;
}

/// Live shopping (0071) сервисі: RPC-лер, LiveKit токені, realtime ағындары.
///
/// Ағындар (watch*) тек initState-те құрылады — build() ішінде ЕМЕС.
class LiveService {
  final SupabaseClient _sb = Supabase.instance.client;

  // ── RPC ─────────────────────────────────────────────────────────────────────

  Future<LiveSession> start({
    required String title,
    required List<String> productIds,
    String? coverUrl,
  }) async {
    final res = await _sb.rpc('live_start', params: {
      'p_title': title,
      'p_product_ids': productIds,
      'p_cover_url': coverUrl,
    });
    return LiveSession.fromMap(Map<String, dynamic>.from(res as Map));
  }

  Future<LiveSession?> end(String sessionId) async {
    final res = await _sb.rpc('live_end', params: {'p_session': sessionId});
    return res is Map
        ? LiveSession.fromMap(Map<String, dynamic>.from(res))
        : null;
  }

  /// [productId] = null → бекітуді алып тастау. Тізімде жоқ дүкен тауары
  /// болса, сервер оны эфир тізіміне өзі қосады.
  Future<void> pin(String sessionId, String? productId) =>
      _sb.rpc('live_pin_product',
          params: {'p_session': sessionId, 'p_product': productId});

  /// Қайтарады: 'live' | 'ended' (cron жауып қойса — хост біледі).
  Future<String> heartbeat(String sessionId, int viewers) async {
    final res = await _sb.rpc('live_heartbeat',
        params: {'p_session': sessionId, 'p_viewers': viewers});
    return res as String? ?? LiveSession.statusEnded;
  }

  Future<void> sendMessage(String sessionId, String body) =>
      _sb.rpc('live_send_message',
          params: {'p_session': sessionId, 'p_body': body});

  /// Хост модерациясы: хабарды жою / қолданушыны чатта бұғаттау.
  Future<void> deleteMessage(String sessionId, int messageId) =>
      _sb.rpc('live_delete_message',
          params: {'p_session': sessionId, 'p_message': messageId});

  Future<void> muteUser(String sessionId, String userUid) =>
      _sb.rpc('live_mute_user',
          params: {'p_session': sessionId, 'p_user': userUid});

  /// false = шектеуден асты / эфир аяқталды (үнсіз).
  ///
  /// [count] — жиналған лайк саны (сервер 1..20-ға қысады).
  Future<bool> like(String sessionId, {int count = 1}) async {
    final res = await _sb
        .rpc('live_like', params: {'p_session': sessionId, 'p_count': count});
    return res == true;
  }

  Future<bool> trackCart(String sessionId, String productId) async {
    final res = await _sb.rpc('live_track_cart',
        params: {'p_session': sessionId, 'p_product': productId});
    return res == true;
  }

  /// LiveKit кіру токені (edge fn `livekit-token`). Хост/көрермен рөлін
  /// сервер өзі анықтайды.
  ///
  /// [asViewer] — қызметкер өз эфирін көрермен ретінде қарағанда: сервер бөлек
  /// identity береді, әйтпесе хостпен бірдей identity LiveKit-те хостты үзеді.
  Future<LiveToken> getToken(String sessionId, {bool asViewer = false}) async {
    try {
      final res = await _sb.functions.invoke('livekit-token', body: {
        'sessionId': sessionId,
        if (asViewer) 'asViewer': true,
      });
      final data = res.data;
      if (data is! Map || (data['token'] as String? ?? '').isEmpty) {
        throw LiveException('internal', liveErrorText('internal'));
      }
      return LiveToken.fromMap(Map<String, dynamic>.from(data));
    } on FunctionException catch (e) {
      final code = (e.details is Map) ? (e.details as Map)['error'] : null;
      final c = code is String ? code : 'internal';
      throw LiveException(c, liveErrorText(c));
    }
  }

  // ── Оқу ─────────────────────────────────────────────────────────────────────

  Future<LiveSession?> getSession(String sessionId) async {
    final row = await _sb
        .from('live_sessions')
        .select()
        .eq('id', sessionId)
        .maybeSingle();
    return row == null ? null : LiveSession.fromMap(row);
  }

  /// Қазір тірі эфирлер (басты бет қатары). Realtime ЕМЕС: бәрінің басты
  /// бетінде ағын ашу бір live_sessions жолының әр like/heartbeat-ін барлық
  /// қолданушыға таратар еді. Сондықтан UI мұны 30 с сайын polling жасайды;
  /// 'live' мәртебесін cron 2-3 минутта өзі жауып отырады (құрылғы сағатына
  /// тәуелді емес).
  Future<List<LiveSession>> getLiveSessions({int limit = 30}) async {
    final rows = await _sb
        .from('live_sessions')
        .select()
        .eq('status', LiveSession.statusLive)
        .order('started_at', ascending: false)
        .limit(limit);
    return rows.map<LiveSession>(LiveSession.fromMap).toList();
  }

  Future<LiveSession?> getLiveSessionForStore(String adminUid) async {
    if (adminUid.isEmpty) return null;
    final row = await _sb
        .from('live_sessions')
        .select()
        .eq('admin_uid', adminUid)
        .eq('status', LiveSession.statusLive)
        .order('started_at', ascending: false)
        .limit(1)
        .maybeSingle();
    return row == null ? null : LiveSession.fromMap(row);
  }

  Future<Map<String, ProductModel>> getProductsByIds(
      Iterable<String> ids) async {
    final list = ids.where((e) => e.isNotEmpty).toSet().toList();
    if (list.isEmpty) return {};
    final rows = await _sb.from('products').select().inFilter('id', list);
    return {for (final r in rows) r['id'] as String: ProductModel.fromMap(r)};
  }

  /// Ағымдағы қызметкердің дүкені (admin → өзі, seller → иесінің).
  Future<StoreModel?> getMyStore() async {
    final owner = AppUser.current.ownerUid;
    if (owner.isEmpty) return null;
    final row =
        await _sb.from('stores').select().eq('admin_uid', owner).maybeSingle();
    return row == null ? null : StoreModel.fromMap(row);
  }

  /// Хост эфирге таңдай алатын тауарлар: витринада көрінетін (фотосы бар,
  /// жасырылмаған, «В наличии»), дүкеннің көрінетін қоймаларында қоры бар.
  /// Партиялар бір сұраныспен (N+1 емес).
  Future<List<LiveShelfItem>> getHostProducts(StoreModel store) async {
    final owner = store.adminUid;
    // PostgREST әдепкіде 1000 жолда кеседі — беттеп оқимыз.
    final results = await Future.wait([
      _selectAll((from, to) => _sb
          .from('products')
          .select()
          .eq('owner_uid', owner)
          .eq('status', ProductModel.statusInStock)
          .eq('storefront_hidden', false)
          .order('id')
          .range(from, to)),
      _selectAll((from, to) => _sb
          .from('batches')
          .select()
          .eq('owner_uid', owner)
          .order('id')
          .range(from, to)),
    ]);
    final whIds = store.visibleWarehouseIds;
    final byProduct = <String, List<BatchModel>>{};
    for (final r in results[1]) {
      final b = BatchModel.fromMap(r);
      if (whIds.isNotEmpty && !whIds.contains(b.warehouseId)) continue;
      if (b.isEffectivelySoldOut) continue;
      (byProduct[r['product_id'] as String? ?? ''] ??= []).add(b);
    }
    final out = <LiveShelfItem>[];
    for (final r in results[0]) {
      final p = ProductModel.fromMap(r);
      if (p.images.isEmpty) continue;
      final batches = byProduct[p.id];
      if (batches == null || batches.isEmpty) continue;
      out.add(LiveShelfItem(
        product: p,
        available: batches.fold(0, (s, b) => s + b.totalAvailable),
        price: effectivePrice(batches.first),
      ));
    }
    out.sort((a, b) => a.product.name.compareTo(b.product.name));
    return out;
  }

  /// 1000 жолдық бет шегін айналып өту: бет таусылғанша оқиды.
  Future<List<Map<String, dynamic>>> _selectAll(
      Future<List<Map<String, dynamic>>> Function(int from, int to)
          page) async {
    const size = 1000;
    final out = <Map<String, dynamic>>[];
    for (var from = 0;; from += size) {
      final rows = await page(from, from + size - 1);
      out.addAll(rows);
      if (rows.length < size) break;
    }
    return out;
  }

  // ── Realtime ────────────────────────────────────────────────────────────────

  Stream<LiveSession?> watchSession(String sessionId) => _sb
      .from('live_sessions')
      .stream(primaryKey: ['id'])
      .eq('id', sessionId)
      .map((rows) => rows.isEmpty ? null : LiveSession.fromMap(rows.first));

  /// Соңғы 100 хабар — ЕСКІСІ алдымен (UI тікелей көрсете береді).
  Stream<List<LiveMessage>> watchMessages(String sessionId) => _sb
      .from('live_messages')
      .stream(primaryKey: ['id'])
      .eq('session_id', sessionId)
      .order('id', ascending: false)
      .limit(100)
      .map((rows) => rows.map(LiveMessage.fromMap).toList().reversed.toList());

  Stream<List<LiveProduct>> watchSessionProducts(String sessionId) => _sb
      .from('live_session_products')
      .stream(primaryKey: ['session_id', 'product_id'])
      .eq('session_id', sessionId)
      .order('position', ascending: true)
      .map((rows) => rows.map(LiveProduct.fromMap).toList());
}

/// Live қате кодын (SQL raise / edge fn {error}) адам оқитын мәтінге айналдырады.
String liveErrorText(Object? e) {
  String? code;
  if (e is String) code = e;
  if (e is LiveException) return e.message;
  if (e is PostgrestException) code = e.message;
  switch (code) {
    case 'feature_disabled':
      return tr('Функция временно отключена', 'Функция уақытша өшірулі');
    case 'not_configured':
      return tr('Эфиры пока не настроены. Попробуйте позже.',
          'Эфирлер әлі бапталмаған. Кейінірек қайталаңыз.');
    case 'live_not_found':
      return tr('Эфир не найден.', 'Эфир табылмады.');
    case 'live_ended':
      return tr('Эфир завершён.', 'Эфир аяқталды.');
    case 'store_unavailable':
      return tr('Магазин сейчас недоступен.', 'Дүкен қазір қолжетімсіз.');
    case 'store_not_found':
      return tr('Сначала создайте магазин.', 'Алдымен дүкен ашыңыз.');
    case 'store_not_published':
      return tr('Магазин не опубликован — эфир недоступен.',
          'Дүкен жарияланбаған — эфир қолжетімсіз.');
    case 'store_blocked':
      return tr('Магазин заблокирован.', 'Дүкен бұғатталған.');
    case 'user_blocked':
      return tr('Аккаунт заблокирован.', 'Аккаунт бұғатталған.');
    case 'subscription_frozen':
      return tr('Подписка истекла — эфир недоступен.',
          'Жазылым мерзімі өтті — эфир қолжетімсіз.');
    case 'too_many_products':
      return tr(
          'Не больше 50 товаров в эфире.', 'Эфирде 50-ден көп тауар болмайды.');
    case 'product_not_in_store':
    case 'product_not_in_live':
      return tr('Товар недоступен.', 'Тауар қолжетімсіз.');
    case 'live_rate_limited':
      return tr('Не так быстро — подождите пару секунд.',
          'Асықпаңыз — бірер секунд күтіңіз.');
    case 'live_muted':
      return tr('Вы не можете писать в чат этого эфира.',
          'Бұл эфирдің чатына жаза алмайсыз.');
    case 'invalid_message':
      return tr('Сообщение: от 1 до 300 символов.',
          'Хабар: 1-ден 300 таңбаға дейін.');
    case 'not_authorized':
    case 'invalid_session':
    case 'no_auth':
      return tr('Недостаточно прав.', 'Құқығыңыз жеткіліксіз.');
    case 'internal':
      return tr(
          'Не удалось подключиться к эфиру.', 'Эфирге қосылу мүмкін болмады.');
  }
  return friendlyError(e);
}
