import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/lang.dart';
import '../models/order_model.dart';

/// `get_gift_public` жауабы: сілтемені ашқан адамға (қонақ та) көрінетін сыйлық.
///
/// Алушыға баға жасырылса — [price] null (сервер жасырады). Сыйлаушы өз
/// сыйлығын әрқашан бағасымен көреді.
class GiftPublic {
  final String status; // awaiting_payment|ready_to_claim|claimed|cancelled|expired
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
  final List<String> availableSizes;
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
    this.availableSizes = const [],
    this.claimedSize = '',
    this.expiresAt,
    this.isGiver = false,
    this.isRecipient = false,
    this.orderId = '',
    this.orderStatus = '',
  });

  bool get isCourier => deliveryMode == 'courier';
  bool get readyToClaim => status == 'ready_to_claim';

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
      availableSizes: [
        for (final e in (m['available_sizes'] as List? ?? const []))
          e.toString(),
      ],
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

/// «Сыйлау» (0070) сервисі. Тапсырысты жасау да, алу да СЕРВЕР RPC-лерінде
/// (баға мен қойма клиентте есептелмейді).
class GiftService {
  final SupabaseClient _sb = Supabase.instance.client;

  String get _uid => _sb.auth.currentUser?.id ?? '';

  /// Сыйлық тапсырысын жасайды (статус pending, төлем чегі күтіледі).
  /// [courier] — true болса алушыға курьер жеткізеді (қалада қызмет болса).
  Future<OrderModel> createGift({
    required String productId,
    required bool courier,
    required String recipientName,
    required String message,
    required bool hidePrice,
  }) async {
    try {
      final res = await _sb.rpc('create_gift_order', params: {
        'p_product': productId,
        'p_delivery_mode': courier ? 'courier' : 'store',
        'p_recipient_name': recipientName.trim(),
        'p_message': message.trim(),
        'p_hide_price': hidePrice,
      });
      return OrderModel.fromMap(Map<String, dynamic>.from(res as Map));
    } on PostgrestException catch (e) {
      throw Exception(_message(e.message));
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
  Future<OrderModel> claim({
    required String token,
    required String size,
    required String address,
    required String city,
    required String phone,
  }) async {
    try {
      final res = await _sb.rpc('claim_gift', params: {
        'p_token': token,
        'p_size': size,
        'p_address': address.trim(),
        'p_city': city.trim(),
        'p_phone': phone.trim(),
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

  /// Маған келген сыйлықтар (орындалған claim бойынша).
  Stream<List<OrderModel>> watchGiftsReceived() {
    if (_uid.isEmpty) return Stream.value(const <OrderModel>[]);
    return _sb
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('gift_recipient_uid', _uid)
        .order('created_at', ascending: false)
        .map((rows) => rows.map(OrderModel.fromMap).toList());
  }

  /// RPC қате кодтарын пайдаланушыға түсінікті мәтінге айналдырады.
  static String _message(String raw) {
    final m = raw.toLowerCase();
    bool has(String k) => m.contains(k);
    if (has('feature_disabled')) {
      return tr('Функция временно отключена', 'Функция уақытша өшірулі');
    }
    if (has('not_authenticated')) {
      return tr('Войдите в аккаунт, чтобы продолжить',
          'Жалғастыру үшін аккаунтқа кіріңіз');
    }
    if (has('not_a_client')) {
      return tr('Подарки доступны только покупателям',
          'Сыйлық тек сатып алушыларға қолжетімді');
    }
    if (has('gift_out_of_stock')) {
      return tr('Этого товара сейчас нет в наличии',
          'Бұл тауар қазір қоймада жоқ');
    }
    if (has('product_unavailable') || has('store_unavailable')) {
      return tr('Товар или магазин сейчас недоступны',
          'Тауар немесе дүкен қазір қолжетімсіз');
    }
    if (has('courier_unavailable')) {
      return tr('В городе магазина нет курьерской доставки',
          'Дүкен қаласында курьерлік жеткізу жоқ');
    }
    if (has('gift_size_unavailable')) {
      return tr('Этот размер уже закончился — выберите другой',
          'Бұл өлшем таусылып қалды — басқасын таңдаңыз');
    }
    if (has('gift_city_unsupported')) {
      return tr('Курьер доставит подарок только в городе магазина',
          'Курьер сыйлықты тек дүкен қаласына жеткізеді');
    }
    if (has('gift_address_required')) {
      return tr('Укажите адрес доставки', 'Жеткізу мекенжайын көрсетіңіз');
    }
    if (has('gift_phone_required')) {
      return tr('Укажите номер телефона', 'Телефон нөмірін көрсетіңіз');
    }
    if (has('gift_size_required')) {
      return tr('Выберите размер', 'Өлшемді таңдаңыз');
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
      return tr('Срок получения подарка истёк',
          'Сыйлықты алу мерзімі өтіп кеткен');
    }
    if (has('gift_not_paid')) {
      return tr('Подарок ещё не оплачен', 'Сыйлық әлі төленбеген');
    }
    if (has('gift_not_found')) {
      return tr('Подарок не найден', 'Сыйлық табылмады');
    }
    return tr('Не удалось выполнить действие. Попробуйте ещё раз.',
        'Әрекетті орындау мүмкін болмады. Қайталап көріңіз.');
  }
}
