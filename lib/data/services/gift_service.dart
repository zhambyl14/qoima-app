import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/error_text.dart';
import '../../core/lang.dart';
import '../models/order_model.dart';

/// Бір өлшем нұсқасы (`gift_size_options`): баға (алушыға жасырылса — null),
/// қосымша төлем, рұқсат (курьерде тек төленген сомадан қымбат емес) және
/// курьер примеркасына болатын қосалқы өлшемдер.
class GiftSizeOption {
  final String size;
  final double? price;
  final double extra;
  final bool allowed;
  final List<String> alts;

  const GiftSizeOption({
    required this.size,
    this.price,
    this.extra = 0,
    this.allowed = true,
    this.alts = const [],
  });

  factory GiftSizeOption.fromMap(Map<String, dynamic> m) => GiftSizeOption(
        size: m['size']?.toString() ?? '',
        price: (m['price'] as num?)?.toDouble(),
        extra: (m['extra'] as num?)?.toDouble() ?? 0,
        allowed: m['allowed'] as bool? ?? true,
        alts: [for (final e in (m['alts'] as List? ?? const [])) e.toString()],
      );

  static List<GiftSizeOption> listFrom(dynamic raw) => [
        for (final e in (raw as List? ?? const []))
          if (e is Map) GiftSizeOption.fromMap(Map<String, dynamic>.from(e)),
      ];
}

/// Ауыстыру парақшасындағы тауар (сыйлықтың өзі не сол дүкеннің басқа тауары).
class GiftExchangeProduct {
  final String id;
  final String name;
  final String brand;
  final String color;
  final String categoryKey;
  final String imageUrl;
  final bool nonReturnable;
  final bool isCurrent;
  final List<GiftSizeOption> sizes;

  const GiftExchangeProduct({
    required this.id,
    required this.name,
    this.brand = '',
    this.color = '',
    this.categoryKey = '',
    this.imageUrl = '',
    this.nonReturnable = false,
    this.isCurrent = false,
    this.sizes = const [],
  });

  /// Ең арзан рұқсат етілген өлшемнің қосымша төлемі (0 = сыйлыққа кіреді).
  double get minExtra {
    double? m;
    for (final s in sizes) {
      if (!s.allowed) continue;
      if (m == null || s.extra < m) m = s.extra;
    }
    return m ?? 0;
  }

  /// Ең арзан рұқсат етілген өлшемнің бағасы (жасырылса — null).
  double? get minPrice {
    double? m;
    for (final s in sizes) {
      if (!s.allowed || s.price == null) continue;
      if (m == null || s.price! < m) m = s.price;
    }
    return m;
  }

  bool get hasAllowed => sizes.any((s) => s.allowed);

  factory GiftExchangeProduct.fromMap(Map<String, dynamic> m) =>
      GiftExchangeProduct(
        id: m['id'] as String? ?? '',
        name: m['name'] as String? ?? '',
        brand: m['brand'] as String? ?? '',
        color: m['color'] as String? ?? '',
        categoryKey: m['category_key'] as String? ?? '',
        imageUrl: m['image_url'] as String? ?? '',
        nonReturnable: m['non_returnable'] as bool? ?? false,
        isCurrent: m['is_current'] as bool? ?? false,
        sizes: GiftSizeOption.listFrom(m['sizes']),
      );
}

/// `get_gift_exchange_options` жауабы.
class GiftExchangeOptions {
  final String mode; // 'claim' (алушы) | 'store' (дүкен)
  final bool courier;
  final bool completed;
  final double? credit; // алушыға баға жасырылса — null
  final bool hidePrice;
  final double extraDue;
  final bool locked; // қайтарылмайтын тауар — ауыстыруға болмайды
  final bool fittingAvailable;
  final String currentProductId;
  final String currentSize;
  final DateTime? exchangeUntil;
  final List<GiftExchangeProduct> products;

  const GiftExchangeOptions({
    required this.mode,
    this.courier = false,
    this.completed = false,
    this.credit,
    this.hidePrice = false,
    this.extraDue = 0,
    this.locked = false,
    this.fittingAvailable = false,
    this.currentProductId = '',
    this.currentSize = '',
    this.exchangeUntil,
    this.products = const [],
  });

  bool get isStore => mode == 'store';

  /// Қымбатырақ тауарға қосымша төлеммен ауысуға бола ма (курьерде — жоқ).
  bool get allowOver => !courier || completed;

  factory GiftExchangeOptions.fromMap(Map<String, dynamic> m) =>
      GiftExchangeOptions(
        mode: m['mode'] as String? ?? 'claim',
        courier: m['courier'] as bool? ?? false,
        completed: m['completed'] as bool? ?? false,
        credit: (m['credit'] as num?)?.toDouble(),
        hidePrice: m['hide_price'] as bool? ?? false,
        extraDue: (m['extra_due'] as num?)?.toDouble() ?? 0,
        locked: m['locked'] as bool? ?? false,
        fittingAvailable: m['fitting_available'] as bool? ?? false,
        currentProductId: m['current_product_id'] as String? ?? '',
        currentSize: m['current_size'] as String? ?? '',
        exchangeUntil: m['exchange_until'] is String
            ? DateTime.tryParse(m['exchange_until'] as String)?.toLocal()
            : null,
        products: [
          for (final e in (m['products'] as List? ?? const []))
            if (e is Map)
              GiftExchangeProduct.fromMap(Map<String, dynamic>.from(e)),
        ],
      );
}

/// `get_gift_public` жауабы: сілтемені ашқан адамға (қонақ та) көрінетін сыйлық.
///
/// Алушыға баға жасырылса — [price] null (сервер жасырады). Сыйлаушы өз
/// сыйлығын әрқашан бағасымен көреді.
class GiftPublic {
  final String
      status; // awaiting_payment|ready_to_claim|claimed|cancelled|expired
  final String giverFirstName;
  final String recipientName;
  final String message;
  final String productId;
  final String productName;
  final String brand;
  final String color;
  final String categoryKey;
  final List<String> images;
  final String storeAdminUid;
  final String storeName;
  final String storeCity;
  final String storeAddress;
  final double? price;
  final bool hidePrice;
  final String deliveryMode; // 'store' | 'courier'
  final double deliveryFee;

  /// Жеткізуді алушы өзі таңдайды (0078): дүкеннен алу немесе курьер.
  final bool deliveryOpen;
  final bool courierAvailable;

  /// Курьер таңдалса есік алдында курьерге төленетін жеткізу ақысы (болжам).
  final double courierFeeEstimate;
  final List<String> availableSizes;

  /// Өлшемдер бағасымен/қосымша төлемімен (тек ready_to_claim күйінде).
  final List<GiftSizeOption> sizeOptions;

  /// Сыйлаушы таңдап, брондаған өлшем (алушы әлі растамаған) — бос болуы мүмкін.
  final String chosenSize;

  /// Өлшемді сыйлаушы таңдаған: алушы өлшемді де, тауарды да өзгерте алмайды (0079).
  final bool sizeLocked;

  /// Сыйлық нақты адамға (телефон / тілек тізімі) арналған.
  final bool recipientBound;

  /// Қайтарылмайтын тауар: өлшем/тауар ауыстырылмайды.
  final bool nonReturnable;

  /// Курьер примеркасы (екінші өлшем) қолжетімді ме — ақысын сыйлаушы төлеген.
  final bool fittingAvailable;
  final double fittingFee;

  /// Алушы дүкенде беру кезінде төлейтін қосымша (тек сыйлаушы/алушыға).
  final double extraDue;

  /// Алынған сыйлықты дүкенде ауыстыру мерзімі (14 күн).
  final DateTime? exchangeUntil;
  final bool exchanged;
  final String claimedSize;
  final DateTime? expiresAt;
  final bool isGiver;
  final bool isRecipient;
  final String orderId;
  final String orderStatus;

  const GiftPublic({
    required this.status,
    this.giverFirstName = '',
    this.recipientName = '',
    this.message = '',
    this.productId = '',
    this.productName = '',
    this.brand = '',
    this.color = '',
    this.categoryKey = '',
    this.images = const [],
    this.storeAdminUid = '',
    this.storeName = '',
    this.storeCity = '',
    this.storeAddress = '',
    this.price,
    this.hidePrice = false,
    this.deliveryMode = 'store',
    this.deliveryFee = 0,
    this.deliveryOpen = false,
    this.courierAvailable = false,
    this.courierFeeEstimate = 0,
    this.availableSizes = const [],
    this.sizeOptions = const [],
    this.chosenSize = '',
    this.sizeLocked = false,
    this.recipientBound = false,
    this.nonReturnable = false,
    this.fittingAvailable = false,
    this.fittingFee = 0,
    this.extraDue = 0,
    this.exchangeUntil,
    this.exchanged = false,
    this.claimedSize = '',
    this.expiresAt,
    this.isGiver = false,
    this.isRecipient = false,
    this.orderId = '',
    this.orderStatus = '',
  });

  bool get isCourier => deliveryMode == 'courier';
  bool get readyToClaim => status == 'ready_to_claim';

  /// Сыйлық басқа адамға арналған (кірген бөгде адам ашты).
  bool get notForYou => status == 'not_for_you';

  factory GiftPublic.fromMap(Map<String, dynamic> m) {
    final p = Map<String, dynamic>.from((m['product'] as Map?) ?? const {});
    final s = Map<String, dynamic>.from((m['store'] as Map?) ?? const {});
    final imgs = <String>[
      for (final e in (p['images'] as List? ?? const []))
        if (e is String && e.isNotEmpty) e,
    ];
    final first = p['image_url'] as String? ?? '';
    if (imgs.isEmpty && first.isNotEmpty) imgs.add(first);
    return GiftPublic(
      status: m['status'] as String? ?? 'awaiting_payment',
      giverFirstName: m['giver_first_name'] as String? ?? '',
      recipientName: m['recipient_name'] as String? ?? '',
      message: m['message'] as String? ?? '',
      productId: p['id'] as String? ?? '',
      productName: p['name'] as String? ?? '',
      brand: p['brand'] as String? ?? '',
      color: p['color'] as String? ?? '',
      categoryKey: p['category_key'] as String? ?? '',
      images: imgs,
      storeAdminUid: s['admin_uid'] as String? ?? '',
      storeName: s['name'] as String? ?? '',
      storeCity: s['city'] as String? ?? '',
      storeAddress: s['address'] as String? ?? '',
      price: (m['price'] as num?)?.toDouble(),
      hidePrice: m['hide_price'] as bool? ?? false,
      deliveryMode: m['delivery_mode'] as String? ?? 'store',
      deliveryFee: (m['delivery_fee'] as num?)?.toDouble() ?? 0,
      deliveryOpen: m['delivery_open'] as bool? ?? false,
      courierAvailable: m['courier_available'] as bool? ?? false,
      courierFeeEstimate: (m['courier_fee_estimate'] as num?)?.toDouble() ?? 0,
      availableSizes: [
        for (final e in (m['available_sizes'] as List? ?? const []))
          e.toString(),
      ],
      sizeOptions: GiftSizeOption.listFrom(m['size_options']),
      chosenSize: m['chosen_size'] as String? ?? '',
      sizeLocked: m['size_locked'] as bool? ?? false,
      recipientBound: m['recipient_bound'] as bool? ?? false,
      nonReturnable: m['non_returnable'] as bool? ?? false,
      fittingAvailable: m['fitting_available'] as bool? ?? false,
      fittingFee: (m['fitting_fee'] as num?)?.toDouble() ?? 0,
      extraDue: (m['extra_due'] as num?)?.toDouble() ?? 0,
      exchangeUntil: m['exchange_until'] is String
          ? DateTime.tryParse(m['exchange_until'] as String)?.toLocal()
          : null,
      exchanged: m['exchanged'] as bool? ?? false,
      claimedSize: m['claimed_size'] as String? ?? '',
      expiresAt: m['expires_at'] is String
          ? DateTime.tryParse(m['expires_at'] as String)?.toLocal()
          : null,
      isGiver: m['is_giver'] as bool? ?? false,
      isRecipient: m['is_recipient'] as bool? ?? false,
      orderId: m['order_id'] as String? ?? '',
      orderStatus: m['order_status'] as String? ?? '',
    );
  }
}

/// Промокодты алдын ала тексеру нәтижесі (gift_promo_preview).
class GiftPromoPreview {
  final bool ok;
  final String reason; // ok == false болса: promo_* коды
  final double discount;
  final double price;
  final double minOrder;
  const GiftPromoPreview({
    required this.ok,
    this.reason = '',
    this.discount = 0,
    this.price = 0,
    this.minOrder = 0,
  });
}

/// «Сыйлау» (0070) сервисі. Тапсырысты жасау да, алу да, ауыстыру да СЕРВЕР
/// RPC-лерінде (баға мен қойма клиентте есептелмейді).
class GiftService {
  final SupabaseClient _sb = Supabase.instance.client;

  String get _uid => _sb.auth.currentUser?.id ?? '';

  /// Сыйлық тапсырысын жасайды (статус pending, төлем чегі күтіледі).
  /// [courier] — true болса «курьермен өлшеп көру» (ақысын сыйлаушы төлейді),
  /// сыйлық курьерге құлыпталады. false болса жеткізуді АЛУШЫ өзі таңдайды (0078).
  /// [size] — сыйлаушы өлшемді білсе: баға сол өлшемнің бағасы, қойма бірден
  /// брондалады (алушы кейін басқа қолжетімді өлшемге ауыстыра алады).
  Future<OrderModel> createGift({
    required String productId,
    required bool courier,
    required String recipientName,
    required String message,
    required bool hidePrice,
    String? size,
    String? promo,
    String? recipientPhone,
  }) async {
    final sz = (size ?? '').trim();
    try {
      final res = await _sb.rpc('create_gift_order', params: {
        'p_product': productId,
        'p_delivery_mode': courier ? 'courier' : 'open',
        'p_recipient_name': recipientName.trim(),
        'p_message': message.trim(),
        'p_hide_price': hidePrice,
        'p_size': sz.isEmpty ? null : sz,
        'p_promo': (promo ?? '').trim().isEmpty ? null : promo!.trim(),
        'p_recipient_phone': (recipientPhone ?? '').trim().isEmpty
            ? null
            : recipientPhone!.trim(),
      });
      return OrderModel.fromMap(Map<String, dynamic>.from(res as Map));
    } on PostgrestException catch (e) {
      throw Exception(_message(e.message, creating: true));
    }
  }

  /// Промокодты тексереді (жеңілдікті көрсету үшін; нақты есепті сервер жасайды).
  Future<GiftPromoPreview> previewPromo({
    required String productId,
    required String code,
    String? size,
  }) async {
    try {
      final res = await _sb.rpc('gift_promo_preview', params: {
        'p_product': productId,
        'p_size': (size ?? '').isEmpty ? null : size,
        'p_code': code.trim(),
      });
      final m = Map<String, dynamic>.from(res as Map);
      return GiftPromoPreview(
        ok: m['ok'] as bool? ?? false,
        reason: m['reason'] as String? ?? '',
        discount: (m['discount'] as num?)?.toDouble() ?? 0,
        price: (m['price'] as num?)?.toDouble() ?? 0,
        minOrder: (m['min_order'] as num?)?.toDouble() ?? 0,
      );
    } on PostgrestException catch (e) {
      throw Exception(_message(e.message, creating: true));
    }
  }

  /// Алушы Qoima-да тіркелген бе (телефон бойынша). Тіркелгенде тек аты қайтады.
  /// null — тіркелмеген (сыйлықты сілтеме арқылы жібереді).
  Future<String?> findRecipient(String phone) async {
    try {
      final res =
          await _sb.rpc('find_gift_recipient', params: {'p_phone': phone});
      final m = Map<String, dynamic>.from(res as Map);
      if (m['found'] != true) return null;
      return (m['first_name'] as String?) ?? '';
    } on PostgrestException {
      return null;
    }
  }

  /// Токен бойынша сыйлық (қонаққа да ашық). Табылмаса — null.
  Future<GiftPublic?> getPublic(String token) async {
    try {
      final res = await _sb.rpc('get_gift_public', params: {'p_token': token});
      if (res == null) return null;
      return GiftPublic.fromMap(Map<String, dynamic>.from(res as Map));
    } on PostgrestException catch (e) {
      throw Exception(_message(e.message));
    }
  }

  /// Алушы өлшем (және курьер болса мекенжай) таңдап, сыйлықты қабылдайды.
  /// [productId] — сол дүкеннің басқа тауары (null = сыйлықтың өз тауары).
  /// [altSize] — курьер примеркасына екінші өлшем (міндетті емес).
  Future<OrderModel> claim({
    required String token,
    required String size,
    required String address,
    required String city,
    required String phone,
    String? productId,
    String? altSize,
    String? delivery, // 'store' | 'courier' — тек алушы таңдайтын сыйлықта
  }) async {
    try {
      final res = await _sb.rpc('claim_gift', params: {
        'p_token': token,
        'p_size': size,
        'p_address': address.trim(),
        'p_city': city.trim(),
        'p_phone': phone.trim(),
        'p_product': (productId ?? '').isEmpty ? null : productId,
        'p_alt_size': (altSize ?? '').isEmpty ? null : altSize,
        'p_delivery': (delivery ?? '').isEmpty ? null : delivery,
      });
      return OrderModel.fromMap(Map<String, dynamic>.from(res as Map));
    } on PostgrestException catch (e) {
      throw Exception(_message(e.message));
    }
  }

  /// Тілек тізіміндегі брондалған позицияны сыйлыққа айналдырады: тапсырыс
  /// сыйлаушыда, алушы — тізім иесі. Бронь тапсырысқа байланады.
  Future<OrderModel> createRegistryGift({
    required String claimId,
    required String message,
    required bool hidePrice,
    bool fitting = false,
    String? promo,
  }) async {
    try {
      final res = await _sb.rpc('create_registry_gift_order', params: {
        'p_claim': claimId,
        'p_message': message.trim(),
        'p_hide_price': hidePrice,
        'p_fitting': fitting,
        'p_promo': (promo ?? '').trim().isEmpty ? null : promo!.trim(),
      });
      return OrderModel.fromMap(Map<String, dynamic>.from(res as Map));
    } on PostgrestException catch (e) {
      throw Exception(_message(e.message, creating: true));
    }
  }

  /// Ауыстыру нұсқалары: сыйлық тауарының өлшемдері + сол дүкеннің басқа
  /// тауарлары. Алушы (алғанға дейін) немесе дүкен қызметкері шақырады.
  Future<GiftExchangeOptions> getExchangeOptions(String token) async {
    try {
      final res = await _sb
          .rpc('get_gift_exchange_options', params: {'p_token': token});
      return GiftExchangeOptions.fromMap(Map<String, dynamic>.from(res as Map));
    } on PostgrestException catch (e) {
      throw Exception(_message(e.message));
    }
  }

  /// Дүкен кассада ауыстырады (басқа өлшем/тауар). Қойма мен баға серверде.
  Future<OrderModel> storeExchange({
    required String orderId,
    required String productId,
    required String size,
  }) async {
    try {
      final res = await _sb.rpc('gift_store_exchange', params: {
        'p_order': orderId,
        'p_product': productId,
        'p_size': size,
      });
      return OrderModel.fromMap(Map<String, dynamic>.from(res as Map));
    } on PostgrestException catch (e) {
      throw Exception(_message(e.message));
    }
  }

  /// Мен жіберген сыйлықтар (жаңасы бірінші). `stream`-де бір ғана eq()
  /// қолдануға болады, сондықтан is_gift Dart-та сүзіледі.
  Stream<List<OrderModel>> watchMyGiftsSent() {
    if (_uid.isEmpty) return Stream.value(const <OrderModel>[]);
    return _sb
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('client_uid', _uid)
        .order('created_at', ascending: false)
        .map((rows) => rows
            .where((r) => r['is_gift'] == true)
            .map(OrderModel.fromMap)
            .toList());
  }

  /// Маған келген бір сыйлық (тазартылған `get_my_received_gifts` ішінен).
  Future<OrderModel?> receivedGift(String orderId) async {
    final res = await _sb.rpc('get_my_received_gifts');
    for (final e in (res as List? ?? const [])) {
      final m = Map<String, dynamic>.from(e as Map);
      if (m['id'] == orderId) return OrderModel.fromMap(m);
    }
    return null;
  }

  /// Маған келген сыйлықтар (орындалған claim бойынша).
  ///
  /// Алушыға `orders` кестесін оқу құқығы берілмейді (чек суреті, төлем
  /// деректері, жасырын баға) — тазартылған `get_my_received_gifts` RPC-і
  /// қолданылады. RPC realtime емес, сондықтан кезеңді сұрау (12 с).
  Stream<List<OrderModel>> watchGiftsReceived() {
    if (_uid.isEmpty) return Stream.value(const <OrderModel>[]);
    late final StreamController<List<OrderModel>> ctrl;
    Timer? timer;
    var busy = false;
    var loadedOnce = false;
    Future<void> load() async {
      if (busy || ctrl.isClosed) return;
      busy = true;
      try {
        final res = await _sb.rpc('get_my_received_gifts');
        final list = [
          for (final e in (res as List? ?? const []))
            OrderModel.fromMap(Map<String, dynamic>.from(e as Map)),
        ];
        loadedOnce = true;
        if (!ctrl.isClosed) ctrl.add(list);
      } catch (e, st) {
        // бір реттік желі қатесі жүктелген тізімді бұзбасын — тек алғашқы қате
        if (!loadedOnce && !ctrl.isClosed) ctrl.addError(e, st);
      } finally {
        busy = false;
      }
    }

    ctrl = StreamController<List<OrderModel>>(
      onListen: () {
        load();
        timer = Timer.periodic(const Duration(seconds: 12), (_) => load());
      },
      onCancel: () {
        timer?.cancel();
        ctrl.close();
      },
    );
    return ctrl.stream;
  }

  /// RPC қате кодтарын пайдаланушыға түсінікті мәтінге айналдырады.
  /// [creating] — сыйлық жасау кезінде (өлшем міндетті = қайтарылмайтын тауар).
  /// Қате/себеп кодының адам тіліндегі мәтіні (мыс. `promo_expired`).
  static String errorText(String raw) => _message(raw, creating: true);

  static String _message(String raw, {bool creating = false}) {
    final m = raw.toLowerCase();
    bool has(String k) => m.contains(k);
    if (has('feature_disabled') ||
        has('not_configured') ||
        has('not_eligible')) {
      return comingSoonText();
    }
    if (has('not_authenticated')) {
      return tr('Войдите в аккаунт, чтобы продолжить',
          'Жалғастыру үшін аккаунтқа кіріңіз');
    }
    if (has('not_a_client')) {
      return tr('Подарки доступны только покупателям',
          'Сыйлық тек сатып алушыларға қолжетімді');
    }
    if (has('gift_exchange_over_amount')) {
      return tr(
          'При доставке курьером можно выбрать товар не дороже подарка. Доплата возможна только при получении в магазине.',
          'Курьермен жеткізгенде сыйлықтан қымбат емес тауар ғана таңдалады. Қосымша төлем тек дүкеннен алғанда мүмкін.');
    }
    if (has('gift_non_returnable')) {
      return tr('Этот товар нельзя обменять — размер выбран отправителем',
          'Бұл тауарды ауыстыруға болмайды — өлшемді сыйлаушы таңдаған');
    }
    if (has('gift_fitting_unavailable')) {
      return tr('Примерка второго размера недоступна для этого подарка',
          'Бұл сыйлыққа екінші өлшемді өлшеп көру қолжетімсіз');
    }
    if (has('gift_alt_size_unavailable')) {
      return tr('Второго размера для примерки нет в наличии — выберите другой',
          'Өлшеп көруге екінші өлшем жоқ — басқасын таңдаңыз');
    }
    if (has('gift_product_unavailable')) {
      return tr('Этот товар сейчас недоступен — выберите другой',
          'Бұл тауар қазір қолжетімсіз — басқасын таңдаңыз');
    }
    if (has('gift_exchange_same')) {
      return tr('Выбран тот же товар и размер', 'Сол тауар мен өлшем таңдалды');
    }
    if (has('gift_exchange_expired')) {
      return tr('Срок обмена (14 дней) истёк',
          'Ауыстыру мерзімі (14 күн) өтіп кетті');
    }
    if (has('gift_handover_in_progress')) {
      return tr('Выдача подарка ещё оформляется — повторите через минуту',
          'Сыйлықты беру әлі рәсімделіп жатыр — бір минуттан соң қайталаңыз');
    }
    if (has('gift_status_forbidden')) {
      return tr('Оплаченный подарок нельзя отменить самостоятельно',
          'Төленген сыйлықтан өз бетіңізше бас тартуға болмайды');
    }
    if (has('gift_exchange_courier')) {
      return tr('Курьерский подарок можно обменять в магазине после получения',
          'Курьермен келетін сыйлықты алған соң дүкенде ауыстыруға болады');
    }
    if (has('gift_exchange_closed') || has('gift_not_claimed')) {
      return tr('Обмен для этого подарка сейчас недоступен',
          'Бұл сыйлықты қазір ауыстыру мүмкін емес');
    }
    if (has('gift_exchange_only')) {
      return tr(
          'Подарок можно только обменять — принесите товар в магазин (14 дней)',
          'Сыйлықты тек ауыстыруға болады — тауарды дүкенге апарыңыз (14 күн)');
    }
    if (has('not_your_order')) {
      return tr('Нет доступа к этому подарку', 'Бұл сыйлыққа рұқсат жоқ');
    }
    if (has('gift_out_of_stock')) {
      return tr(
          'Этого товара сейчас нет в наличии', 'Бұл тауар қазір қоймада жоқ');
    }
    if (has('product_unavailable') || has('store_unavailable')) {
      return tr('Товар или магазин сейчас недоступны',
          'Тауар немесе дүкен қазір қолжетімсіз');
    }
    if (has('courier_unavailable')) {
      return tr('Курьерская доставка в этом городе пока недоступна — выберите получение в магазине',
          'Бұл қалада курьерлік жеткізу әзірге қолжетімсіз — дүкеннен алуды таңдаңыз');
    }
    if (has('gift_size_unavailable')) {
      return tr('Этот размер уже закончился — выберите другой',
          'Бұл өлшем таусылып қалды — басқасын таңдаңыз');
    }
    if (has('gift_city_unsupported')) {
      return tr('Курьер доставит подарок только в городе магазина',
          'Курьер сыйлықты тек дүкен қаласына жеткізеді');
    }
    if (has('gift_size_locked')) {
      return tr(
          'Отправитель выбрал размер — его нельзя изменить. После получения можно обменять в магазине.',
          'Өлшемді сыйлаушы таңдаған — оны өзгертуге болмайды. Алған соң дүкенде ауыстыруға болады.');
    }
    if (has('gift_not_for_you')) {
      return tr('Этот подарок отправлен другому человеку',
          'Бұл сыйлық басқа адамға жіберілген');
    }
    if (has('promo_not_found')) {
      return tr('Промокод не найден', 'Промокод табылмады');
    }
    if (has('promo_inactive')) {
      return tr('Промокод больше не действует', 'Промокод енді жарамсыз');
    }
    if (has('promo_not_started')) {
      return tr('Промокод ещё не активен', 'Промокод әлі белсенді емес');
    }
    if (has('promo_expired')) {
      return tr('Срок действия промокода истёк', 'Промокодтың мерзімі өткен');
    }
    if (has('promo_exhausted')) {
      return tr('Лимит использований исчерпан', 'Қолдану лимиті таусылған');
    }
    if (has('promo_referral_self')) {
      return tr(
          'Нельзя использовать свой же код', 'Өз кодыңызды қолдануға болмайды');
    }
    if (has('promo_referral_first_only')) {
      return tr('Код друга действует только на первый заказ в этом магазине',
          'Дос коды бұл дүкендегі тек бірінші тапсырысқа жарамды');
    }
    if (has('promo_not_yours')) {
      return tr('Этот промокод выдан другому пользователю',
          'Бұл промокод басқа қолданушыға берілген');
    }
    if (has('promo_limit_user')) {
      return tr('Вы уже использовали этот промокод',
          'Сіз бұл промокодты бұрын қолдандыңыз');
    }
    if (has('promo_not_applicable')) {
      return tr('Промокод не применим к этому товару',
          'Промокод бұл тауарға қолданылмайды');
    }
    if (has('promo_min_order')) {
      return tr('Сумма меньше минимальной для этого промокода',
          'Сома бұл промокодтың ең аз сомасынан аз');
    }
    if (has('gift_delivery_required')) {
      return tr('Выберите, как получить подарок: в магазине или курьером',
          'Сыйлықты қалай алатыныңызды таңдаңыз: дүкеннен немесе курьермен');
    }
    if (has('registry_claim_not_active')) {
      return tr('Бронь устарела — выберите подарок из списка заново',
          'Бронь ескірген — тізімнен сыйлықты қайта таңдаңыз');
    }
    if (has('gift_address_required')) {
      return tr('Укажите адрес доставки', 'Жеткізу мекенжайын көрсетіңіз');
    }
    if (has('gift_phone_required')) {
      return tr('Укажите номер телефона', 'Телефон нөмірін көрсетіңіз');
    }
    if (has('gift_size_required')) {
      return creating
          ? tr('Этот товар нельзя обменять — подарите, зная размер',
              'Бұл тауарды ауыстыруға болмайды, өлшемін біліп сыйлаңыз')
          : tr('Выберите размер', 'Өлшемді таңдаңыз');
    }
    if (has('gift_already_claimed')) {
      return tr('Этот подарок уже получен', 'Бұл сыйлық бұрын алынған');
    }
    if (has('gift_self_claim')) {
      return tr('Это ваш собственный подарок — отправьте ссылку получателю',
          'Бұл сіздің өз сыйлығыңыз — сілтемені алушыға жіберіңіз');
    }
    if (has('gift_cancelled')) {
      return tr('Подарок отменён', 'Сыйлық бас тартылған');
    }
    if (has('gift_expired')) {
      return tr(
          'Срок получения подарка истёк', 'Сыйлықты алу мерзімі өтіп кеткен');
    }
    if (has('gift_not_paid')) {
      return tr('Подарок ещё не оплачен', 'Сыйлық әлі төленбеген');
    }
    if (has('gift_not_found')) {
      return tr('Подарок не найден', 'Сыйлық табылмады');
    }
    return genericErrorText();
  }
}
