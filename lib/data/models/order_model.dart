import 'cart_item_model.dart';
import 'return_policy.dart';

/// Курьермен қоймаға қайтып келе жатқан позиция («өлшеп көру» кезінде клиент
/// таңдамаған өлшем). [fromHold] — ол броньда тұр ма (қосалқы өлшем) әлде
/// қоймадан алынған ба (негізгі өлшем): қоймаға қайтару жолы соған байланысты.
class ReturnLegItem {
  final String productId;
  final String batchId;
  final String productName;
  final String size;
  final int qty;
  final bool fromHold;

  const ReturnLegItem({
    required this.productId,
    required this.batchId,
    required this.productName,
    required this.size,
    required this.qty,
    required this.fromHold,
  });

  factory ReturnLegItem.fromJson(Map<String, dynamic> j) => ReturnLegItem(
        productId: j['productId'] as String? ?? '',
        batchId: j['batchId'] as String? ?? '',
        productName: j['productName'] as String? ?? '',
        size: j['size'] as String? ?? '',
        qty: (j['qty'] as num?)?.toInt() ?? 1,
        fromHold: j['fromHold'] as bool? ?? false,
      );
}

class OrderModel {
  final String id;
  final String clientPhone;
  final String clientName;
  final String clientUid;
  final String adminUid;
  final String storeName;
  final String warehouseId;
  final String warehouseAddress;
  final String storePhone; // дүкен админінің телефоны (снапшот заказ кезінде)
  final List<CartItemModel> items;
  final String status;
  final String orderType;
  final DateTime createdAt;
  final String address;
  /// Жеткізу ҚАЛАСЫ — клиент себетте таңдайды (снапшот).
  ///
  /// Бұрын қала тек [address] жолының ішінде еркін мәтін болатын. Дүкен өзі
  /// жеткізетін жағдайда сатушы қай қалаға жіберетінін білмей қалатын
  /// («Бараева 28» деген көше бірнеше қалада бар), әрі курьер қызметінің
  /// бар-жоғы клиенттің профиліндегі БОС қаладан анықталатын.
  final String clientCity;
  final String note;
  /// Клиент ДҮКЕНГЕ аударатын сома (тауар/депозит + «өлшеп көру»).
  /// ⚠️ 0053-тен бастап мұнда жеткізу ақысы ЖОҚ — ол курьердікі.
  final double depositAmount;
  /// Жеткізу ақысы — КУРЬЕРДІКІ. Клиент оны тапсырысты алған сәтте курьерге
  /// ТІКЕЛЕЙ төлейді, дүкеннің кассасына мүлде тимейді (0053).
  final double deliveryFee;

  // ── Казпочта (0081) ─────────────────────────────────────────────────────────
  // Бөлек баған: delivery_fee «курьерге» деп көрсетіледі және курьер есебіне
  // кіреді, ал бұл ақыны дүкен почтаға өзі төлейді. deposit_amount-қа КІРЕДІ
  // (бір аударым), бірақ sales_history-ге кірмейді — транзит ақша, кіріс емес.
  final double kazpostFee;
  final String postRecipientName;
  final String postRecipientPhone;
  final String postIndex;
  final String postTracking;
  final String postStatus; // '' | shipped | delivered
  final DateTime? postShippedAt;
  final DateTime? postDeliveredAt;

  // ── Қайтару шарттарының снапшоты (0082) ─────────────────────────────────────
  // Сату сәтінде сервер жазады. null — ескі тапсырыс, сыйлық немесе жалауша өшік.
  final ReturnPolicy? returnPolicy;
  final DateTime? returnNoticeAckAt;
  /// «Өлшеп көру» ақысы (0050) — ДҮКЕННІҢ қызмет кірісі: екінші жұп оның
  /// қоймасынан шығады, тәуекел де соныкі. Дүкенге аударылады.
  final double fittingFee;
  /// Курьер жеткізу ақысын клиенттен нақты алды ма (0053).
  final bool deliveryFeeCollected;
  final DateTime? deliveryFeeCollectedAt;
  /// Жеткізуді КІМ орындайды (0055):
  ///   'courier' — платформа курьері (қалада қызмет қосулы);
  ///   'store'   — дүкен өзі жеткізеді/жөнелтеді, шартын клиентпен келіседі.
  final String deliveryMode;
  /// Бір төлемнен шыққан суб-тапсырыстарды байланыстырады (0057).
  ///
  /// Себет дүкен/қойма бойынша бөлінеді — екі дүкеннен алса, екі тапсырыс
  /// жазылады. Бірақ клиент БІРЕУ, мекенжай БІРЕУ, курьердің бару жолы да
  /// БІРЕУ. Бұл id-сіз курьерге екі бөтен тапсырыс болып көрінетін де,
  /// біреуін бір курьер, екіншісін екінші курьер алып кетуі мүмкін еді.
  final String cartGroupId;
  final String pickupCode;
  final int orderNumber;
  final String sellerId;
  final String sellerName;
  final String deliveredByUid;
  final String deliveredByName;
  final String receiptNumber;

  // ── Payment receipt flow ────────────────────────────────────────────────────
  final String receiptUrl;
  final DateTime? receiptSubmittedAt;
  final String paymentConfirmedBy;
  final DateTime? paymentConfirmedAt;
  final String rejectionReason;
  final DateTime? rejectedAt;
  final DateTime? deadlineAt;
  /// Тапсырыс АЛЫНҒАН сәт (0045 триггері толтырады). Қайтару терезесі осыдан
  /// саналады — бұрын [createdAt] қолданылатын, ол ҚАТЕ еді: тапсырыс апталар
  /// бойы төлемді күтіп тұруы мүмкін, сонда клиент қолына алған күні
  /// «14 күн өтіп кеткен» болып шығатын.
  final DateTime? completedAt;
  final bool stockRestored;

  // ── Кім болдырмады (race-condition түзетуден кейін) ─────────────────────────
  final String cancelledByRole; // client|admin|seller|system
  final String cancelledByUid;
  final String cancelledByName;
  final DateTime? cancelledAt;
  final String paymentCardNumber;
  final String paymentCardHolder;
  final String paymentBank;
  final String inStorePaymentMethod;

  // ── Курьер (0051) ───────────────────────────────────────────────────────────
  final String courierUid;
  final String courierName;
  /// '' | assigned | picked_up | delivered
  final String courierStatus;
  final DateTime? courierTakenAt;
  final DateTime? courierPickedUpAt;

  // ── Айналымдағы өлшем (0052) ────────────────────────────────────────────────
  /// «Өлшеп көру» кезінде клиент ТАҢДАМАҒАН өлшем — курьермен қоймаға қайтып
  /// келе жатыр. Ол қоймаға дүкен «қабылдадым» дегенде ғана оралады, себебі
  /// физикалық түрде әлі курьерде.
  final List<ReturnLegItem> returnLeg;
  /// '' (жоқ) | pending (курьерде) | returned (дүкен қабылдады)
  final String returnLegStatus;

  // ── Промокод (снапшот на момент заказа) ──────────────────────────────────────
  final String promoId;
  final String promoCode;
  final double promoDiscount;
  final bool promoCountsUsage;

  // ── «Сыйлау» (0070) ─────────────────────────────────────────────────────────
  //  Сыйлық — кәдімгі тапсырыс, бірақ өлшемі алушы таңдағанша белгісіз.
  //  Бұл бағандарды ТЕК сервер RPC-лері (create_gift_order / claim_gift)
  //  жазады — сондықтан toMap-қа КІРМЕЙДІ.
  final bool isGift;
  final String giftToken;
  final String giftRecipientUid;
  final String giftRecipientName;
  final String giftRecipientPhone;
  final String giftMessage;
  final bool giftHidePrice;
  final DateTime? giftClaimedAt;
  final DateTime? giftExpiresAt;
  final String giftGiverName;
  /// Сыйлаушы төлеген ТАУАР сомасы (примерка/жеткізусіз) — ауыстыру ережесінің
  /// өлшемі: жаңа тауар бұдан арзан болса айырма қайтарылмайды, қымбат болса
  /// айырманы алушы дүкенде төлейді.
  final double giftPaidAmount;
  /// Алушы қымбатырақ тауарға ауысқанда дүкенде БЕРУ КЕЗІНДЕ төлейтін қосымша.
  /// (items[0].price = төленген + осы сома → [remainingAmount] дәл осыған тең.)
  final double giftExtraDue;
  /// Ауыстырулар тарихы (сервер жазады): {at, by, from_product, from_size,
  /// to_product, to_size, extra, after_handover}.
  final List<Map<String, dynamic>> giftExchangeLog;

  static const Duration receiptWindow = Duration(minutes: 30);
  static const Duration pickupWindow = Duration(minutes: 60);

  static const String typeSmartReservation = 'smart_reservation';
  static const String typeClickCollect = 'click_collect';
  static const String typeDelivery = 'delivery';

  static const String statusReserved = 'reserved';
  static const String statusPending = 'pending';
  static const String statusRejected = 'rejected';
  static const String statusConfirmed = 'confirmed';
  static const String statusReady = 'ready';
  static const String statusCompleted = 'completed';
  static const String statusCancelled = 'cancelled';
  static const String statusReturned = 'returned';

  static const String deliveryByCourier = 'courier';
  static const String deliveryByStore = 'store';
  static const String deliveryByKazpost = 'kazpost';
  static const String postShipped = 'shipped';
  static const String postDelivered = 'delivered';

  /// Дүкен «тапсырылды» деп жаба алатын ең ерте мерзім (0081 kazpost_complete_order).
  static const Duration postStoreCloseAfter = Duration(days: 7);

  const OrderModel({
    required this.id,
    required this.clientPhone,
    required this.clientName,
    this.clientUid = '',
    required this.adminUid,
    required this.storeName,
    required this.warehouseId,
    this.warehouseAddress = '',
    this.storePhone = '',
    required this.items,
    required this.status,
    required this.orderType,
    required this.createdAt,
    this.address = '',
    this.clientCity = '',
    this.note = '',
    this.depositAmount = 0.0,
    this.deliveryFee = 0.0,
    this.kazpostFee = 0.0,
    this.postRecipientName = '',
    this.postRecipientPhone = '',
    this.postIndex = '',
    this.postTracking = '',
    this.postStatus = '',
    this.postShippedAt,
    this.postDeliveredAt,
    this.returnPolicy,
    this.returnNoticeAckAt,
    this.fittingFee = 0.0,
    this.deliveryFeeCollected = false,
    this.deliveryFeeCollectedAt,
    this.deliveryMode = 'courier',
    this.cartGroupId = '',
    this.pickupCode = '',
    this.orderNumber = 0,
    this.sellerId = 'онлайн',
    this.sellerName = 'Онлайн',
    this.deliveredByUid = '',
    this.deliveredByName = '',
    this.receiptNumber = '',
    this.receiptUrl = '',
    this.receiptSubmittedAt,
    this.paymentConfirmedBy = '',
    this.paymentConfirmedAt,
    this.rejectionReason = '',
    this.rejectedAt,
    this.deadlineAt,
    this.completedAt,
    this.stockRestored = false,
    this.cancelledByRole = '',
    this.cancelledByUid = '',
    this.cancelledByName = '',
    this.cancelledAt,
    this.paymentCardNumber = '',
    this.paymentCardHolder = '',
    this.paymentBank = '',
    this.inStorePaymentMethod = '',
    this.courierUid = '',
    this.courierName = '',
    this.courierStatus = '',
    this.courierTakenAt,
    this.courierPickedUpAt,
    this.returnLeg = const [],
    this.returnLegStatus = '',
    this.promoId = '',
    this.promoCode = '',
    this.promoDiscount = 0.0,
    this.promoCountsUsage = false,
    this.isGift = false,
    this.giftToken = '',
    this.giftRecipientUid = '',
    this.giftRecipientName = '',
    this.giftRecipientPhone = '',
    this.giftMessage = '',
    this.giftHidePrice = false,
    this.giftClaimedAt,
    this.giftExpiresAt,
    this.giftGiverName = '',
    this.giftPaidAmount = 0,
    this.giftExtraDue = 0,
    this.giftExchangeLog = const [],
  });

  // ── «Сыйлау» күйлері ────────────────────────────────────────────────────────
  /// Алушы өлшем таңдаған (қойма азайған, тапсырыс дүкенге жалғасты).
  bool get isGiftClaimed => isGift && giftClaimedAt != null;

  /// Алушыны күтіп тұр: тапсырыс тірі, бірақ өлшем әлі таңдалмаған.
  bool get isGiftAwaitingRecipient =>
      isGift &&
      giftClaimedAt == null &&
      status != statusCancelled &&
      status != statusReturned;

  /// Алушы мерзімінде алмады (сыйлаушы дүкеннен қайтаруды сұрай алады).
  bool get isGiftExpired =>
      isGiftAwaitingRecipient &&
      giftExpiresAt != null &&
      DateTime.now().isAfter(giftExpiresAt!);

  /// Төлем расталды, алушы сілтемені ашып өлшем таңдай алады.
  bool get isGiftReadyToClaim =>
      isGiftAwaitingRecipient && status == statusConfirmed && !isGiftExpired;

  /// Алушыға көрсетілетін баға жасырын ба (сыйлаушы үшін ешқашан жасырылмайды).
  bool hideGiftPriceFor(String uid) =>
      isGift && giftHidePrice && uid != clientUid;

  /// Сыйлаушы өлшемді өзі таңдап, қойма брондалған (алушы әлі растамаған).
  bool get isGiftSizeReserved =>
      isGiftAwaitingRecipient &&
      items.isNotEmpty &&
      items.first.size.isNotEmpty &&
      items.first.batchId.isNotEmpty;

  /// Дүкеннен алатын сыйлық (курьер емес).
  bool get isGiftStorePickup => isGift && !isDelivery;

  /// Берілгенге дейін дүкенде алынатын қосымша төлем бар ма.
  bool get hasGiftExtraDue =>
      isGift && giftExtraDue > 0 && status != statusCompleted;

  /// Сыйлық позициясы қайтарылмайтын тауар ба (снапшот) — ауыстыруға болмайды.
  bool get isGiftLocked =>
      isGift && items.isNotEmpty && items.first.nonReturnable;

  /// Дүкен кассада ауыстыра ала ма (0070 gift_store_exchange ережесімен бірдей):
  ///  • дүкеннен алатын, алушы растаған, әлі берілмеген сыйлық;
  ///  • алынған сыйлық — [returnWindow] (14 күн) ішінде.
  bool get canGiftStoreExchange {
    if (!isGiftClaimed || isGiftLocked) return false;
    if (status == statusConfirmed || status == statusReady) {
      return !isDelivery && courierUid.isEmpty;
    }
    return status == statusCompleted &&
        DateTime.now().isBefore(returnDeadline);
  }

  /// Алынған сыйлықты ауыстыру мерзімі әлі өтпеген бе.
  bool get giftExchangeOpen =>
      isGift &&
      status == statusCompleted &&
      DateTime.now().isBefore(returnDeadline);

  double get total => items.fold(0.0, (s, i) => s + i.subtotal);
  double get finalTotal => (total - promoDiscount).clamp(0.0, total);

  // ── АҚША БӨЛІНУІ (0053) — жасырын бап жоқ ───────────────────────────────────
  //  Клиенттің шығыны ЕКІ бөлек төлемнен тұрады. Оларды қосып бір сан
  //  көрсетуге БОЛМАЙДЫ: ақшаны әртүрлі адам алады.
  //
  //    storeAmount   → ДҮКЕН  (алдын ала аударым + чек)
  //    courierAmount → КУРЬЕР (тапсырысты алған сәтте, қолма-қол)

  /// Дүкенге тиесілі сома: тауар (промодан кейін) + «өлшеп көру» қызметі.
  double get storeAmount => finalTotal + fittingFee;

  /// Курьерге тиесілі сома: жеткізу ақысы. Дүкеннің кірісі ЕМЕС.
  double get courierAmount => deliveryFee;

  /// Клиенттің жалпы шығыны — тек КӨРСЕТУ үшін (екі төлемнің қосындысы).
  double get clientTotal => storeAmount + courierAmount + kazpostFee;

  /// Клиент дүкенге аударатын сома: тауар + (бар болса) Казпочта.
  double get transferAmount => isSmartReservation
      ? depositAmount
      : storeAmount + kazpostFee;

  /// Дүкенде қалатын доплата (тек бронь үшін мағыналы).
  double get remainingAmount =>
      (storeAmount - depositAmount).clamp(0.0, storeAmount);

  bool get isSmartReservation => orderType == typeSmartReservation;
  bool get isClickCollect => orderType == typeClickCollect;
  bool get isDelivery => orderType == typeDelivery;

  // ── Курьер (0051) ───────────────────────────────────────────────────────────
  static const String courierAssigned = 'assigned';
  static const String courierPickedUp = 'picked_up';
  static const String courierDelivered = 'delivered';

  /// Тапсырысты платформа курьері жеткізе ме (қалада қызмет қосулы ма).
  /// false болса — дүкен өзі жеткізеді/жөнелтеді (0055).
  bool get byPlatformCourier =>
      isDelivery &&
      deliveryMode != deliveryByStore &&
      deliveryMode != deliveryByKazpost;
  bool get storeDeliversItself => isDelivery && deliveryMode == deliveryByStore;
  bool get isKazpost => isDelivery && deliveryMode == deliveryByKazpost;

  /// Посылка почтада, жолда.
  bool get postInTransit => isKazpost && postStatus == postShipped;

  /// Посылканы клиент өзі «алдым» деп жапты ма. Дүкен (7 күннен кейін) не cron
  /// жапса — жоқ: ол сәтте посылка әлі жолда болуы мүмкін.
  bool get postClosedByClient => deliveredByUid == clientUid;

  /// Тапсырыстың ешбір жолын қайтаруға болмайды (дүкен режимі басқа болса да).
  bool get allItemsNonReturnable =>
      items.isNotEmpty && items.every((i) => i.nonReturnable);

  /// Дүкен «тапсырылды» деп жаба ала ма (жібергеніне 7 күн өтті ме).
  bool get storeCanClosePost =>
      postInTransit &&
      postShippedAt != null &&
      DateTime.now().difference(postShippedAt!) >= postStoreCloseAfter;

  bool get hasCourier => courierUid.isNotEmpty;
  bool get courierOnWay => courierStatus == courierPickedUp;
  /// «Өлшеп көру» сұралған позициялар бар ма (курьер қосымша өлшем алып барады).
  bool get hasFitting => items.any((i) => i.hasAltSize);

  /// Курьерде қоймаға қайтып бара жатқан өлшем бар ма.
  bool get returnLegPending => returnLegStatus == 'pending';
  bool get returnLegDone => returnLegStatus == 'returned';
  bool get hasReturnLeg => returnLeg.isNotEmpty;

  // ── Қайтару терезесі — ЖАЛҒЫЗ КӨЗ ────────────────────────────────────────
  /// Клиент тапсырысты қолына алғаннан кейін қайтаруға берілетін мерзім.
  /// 0062-дегі `sweep_return_window_reminders` push-ы да дәл осы санға
  /// негізделген — екеуі әрдайым бір мәнде тұруы керек.
  static const Duration returnWindow = Duration(days: 14);

  /// Мерзім қашан бітеді. [completedAt] жоқ ескі жазбаларда ғана [createdAt]
  /// қолданылады (0045-ке дейін аяқталған тапсырыстар).
  DateTime get returnDeadline => (completedAt ?? createdAt).add(
      returnPolicy == null ? returnWindow : Duration(days: returnPolicy!.days));

  /// Осы тапсырысты қайтаруға принципті түрде бола ма (алынған + мерзімінде).
  /// Нақты батырманың көрінуі бұған ҚОСА «бұл тапсырыс бойынша қайтару бар ма»
  /// тексерісіне байланысты — ол ағын деңгейінде шешіледі.
  bool get returnable =>
      status == statusCompleted && DateTime.now().isBefore(returnDeadline);

  /// Мерзім бітуіне қалған күн (0 — бүгін бітеді/бітті).
  int get returnDaysLeft {
    final d = returnDeadline.difference(DateTime.now()).inHours;
    return d <= 0 ? 0 : (d / 24).ceil();
  }

  bool get isAwaitingReview => status == statusPending && receiptUrl.isNotEmpty;
  bool get canHandOver => status == statusConfirmed && !isKazpost;
  bool get isFullPrepay => orderType != typeSmartReservation;
  bool get isExpired =>
      deadlineAt != null && DateTime.now().isAfter(deadlineAt!);
  DateTime get expiresAt =>
      deadlineAt ?? createdAt.add(const Duration(hours: 1));
  int get minutesLeft =>
      expiresAt.difference(DateTime.now()).inMinutes.clamp(0, 60);

  /// Supabase `orders` жолынан (snake_case + items JSONB).
  factory OrderModel.fromMap(Map<String, dynamic> m) {
    DateTime dt(dynamic v) =>
        v is String ? (DateTime.tryParse(v) ?? DateTime.now()) : DateTime.now();
    DateTime? dtn(dynamic v) =>
        v is String && v.isNotEmpty ? DateTime.tryParse(v) : null;
    return OrderModel(
      id: m['id'] as String? ?? '',
      clientPhone: m['client_phone'] as String? ?? '',
      clientName: m['client_name'] as String? ?? '',
      clientUid: m['client_uid'] as String? ?? '',
      adminUid: m['admin_uid'] as String? ?? '',
      storeName: m['store_name'] as String? ?? '',
      warehouseId: m['warehouse_id'] as String? ?? '',
      warehouseAddress: m['warehouse_address'] as String? ?? '',
      storePhone: m['store_phone'] as String? ?? '',
      items: (m['items'] as List? ?? [])
          .map((e) => CartItemModel.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      status: m['status'] as String? ?? statusPending,
      orderType: m['order_type'] as String? ?? typeClickCollect,
      createdAt: dt(m['created_at']),
      address: m['address'] as String? ?? '',
      clientCity: m['client_city'] as String? ?? '',
      note: m['note'] as String? ?? '',
      depositAmount: (m['deposit_amount'] as num?)?.toDouble() ?? 0,
      deliveryFee: (m['delivery_fee'] as num?)?.toDouble() ?? 0,
      kazpostFee: (m['kazpost_fee'] as num?)?.toDouble() ?? 0,
      postRecipientName: m['post_recipient_name'] as String? ?? '',
      postRecipientPhone: m['post_recipient_phone'] as String? ?? '',
      postIndex: m['post_index'] as String? ?? '',
      postTracking: m['post_tracking'] as String? ?? '',
      postStatus: m['post_status'] as String? ?? '',
      postShippedAt: dtn(m['post_shipped_at']),
      postDeliveredAt: dtn(m['post_delivered_at']),
      returnPolicy: ReturnPolicy.fromSnapshot(m['return_policy']),
      returnNoticeAckAt: dtn(m['return_notice_ack_at']),
      fittingFee: (m['fitting_fee'] as num?)?.toDouble() ?? 0,
      deliveryFeeCollected: m['delivery_fee_collected'] as bool? ?? false,
      deliveryFeeCollectedAt: dtn(m['delivery_fee_collected_at']),
      deliveryMode: m['delivery_mode'] as String? ?? deliveryByCourier,
      cartGroupId: m['cart_group_id'] as String? ?? '',
      pickupCode: m['pickup_code'] as String? ?? '',
      orderNumber: (m['order_number'] as num?)?.toInt() ?? 0,
      sellerId: m['seller_id'] as String? ?? 'онлайн',
      sellerName: m['seller_name'] as String? ?? 'Онлайн',
      deliveredByUid: m['delivered_by_uid'] as String? ?? '',
      deliveredByName: m['delivered_by_name'] as String? ?? '',
      receiptNumber: m['receipt_number'] as String? ?? '',
      receiptUrl: m['receipt_url'] as String? ?? '',
      receiptSubmittedAt: dtn(m['receipt_submitted_at']),
      paymentConfirmedBy: m['payment_confirmed_by'] as String? ?? '',
      paymentConfirmedAt: dtn(m['payment_confirmed_at']),
      rejectionReason: m['rejection_reason'] as String? ?? '',
      rejectedAt: dtn(m['rejected_at']),
      deadlineAt: dtn(m['deadline_at']),
      completedAt: dtn(m['completed_at']),
      stockRestored: m['stock_restored'] as bool? ?? false,
      cancelledByRole: m['cancelled_by_role'] as String? ?? '',
      cancelledByUid: m['cancelled_by_uid'] as String? ?? '',
      cancelledByName: m['cancelled_by_name'] as String? ?? '',
      cancelledAt: dtn(m['cancelled_at']),
      paymentCardNumber: m['payment_card_number'] as String? ?? '',
      paymentCardHolder: m['payment_card_holder'] as String? ?? '',
      paymentBank: m['payment_bank'] as String? ?? '',
      inStorePaymentMethod: m['in_store_payment_method'] as String? ?? '',
      courierUid: m['courier_uid'] as String? ?? '',
      courierName: m['courier_name'] as String? ?? '',
      courierStatus: m['courier_status'] as String? ?? '',
      courierTakenAt: dtn(m['courier_taken_at']),
      courierPickedUpAt: dtn(m['courier_picked_up_at']),
      returnLeg: (m['return_leg'] as List? ?? [])
          .map((e) => ReturnLegItem.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      returnLegStatus: m['return_leg_status'] as String? ?? '',
      promoId: m['promo_id'] as String? ?? '',
      promoCode: m['promo_code'] as String? ?? '',
      promoDiscount: (m['promo_discount'] as num?)?.toDouble() ?? 0,
      promoCountsUsage: m['promo_counts_usage'] as bool? ?? false,
      isGift: m['is_gift'] as bool? ?? false,
      giftToken: m['gift_token'] as String? ?? '',
      giftRecipientUid: m['gift_recipient_uid'] as String? ?? '',
      giftRecipientName: m['gift_recipient_name'] as String? ?? '',
      giftRecipientPhone: m['gift_recipient_phone'] as String? ?? '',
      giftMessage: m['gift_message'] as String? ?? '',
      giftHidePrice: m['gift_hide_price'] as bool? ?? false,
      giftClaimedAt: dtn(m['gift_claimed_at']),
      giftExpiresAt: dtn(m['gift_expires_at']),
      giftGiverName: m['gift_giver_name'] as String? ?? '',
      giftPaidAmount: (m['gift_paid_amount'] as num?)?.toDouble() ?? 0,
      giftExtraDue: (m['gift_extra_due'] as num?)?.toDouble() ?? 0,
      giftExchangeLog: [
        for (final e in (m['gift_exchange_log'] as List? ?? const []))
          if (e is Map) Map<String, dynamic>.from(e),
      ],
    );
  }

  /// Supabase жазу үшін (snake_case; items JSONB ішінде camelCase қалады).
  Map<String, dynamic> toMap() => {
        'admin_uid': adminUid,
        'client_uid': clientUid.isEmpty ? null : clientUid,
        'client_phone': clientPhone,
        'client_name': clientName,
        'store_name': storeName,
        'store_phone': storePhone,
        'warehouse_id': warehouseId.isEmpty ? null : warehouseId,
        'warehouse_address': warehouseAddress,
        'items': items.map((i) => i.toJson()).toList(),
        'status': status,
        'order_type': orderType,
        'address': address,
        'client_city': clientCity,
        'note': note,
        'deposit_amount': depositAmount,
        'delivery_fee': deliveryFee,
        'fitting_fee': fittingFee,
        'delivery_mode': deliveryMode,
        // Тек Казпочтада: қалған кезде бағандар әдепкі мәнде қалады.
        // post_tracking/post_status/return_policy ӘДЕЙІ ЖОҚ — оларды сервер жазады.
        if (deliveryMode == deliveryByKazpost) ...{
          'kazpost_fee': kazpostFee,
          'post_recipient_name': postRecipientName,
          'post_recipient_phone': postRecipientPhone,
          'post_index': postIndex,
        },
        'pickup_code': pickupCode,
        'order_number': orderNumber,
        'seller_id': sellerId,
        'seller_name': sellerName,
        'delivered_by_uid': deliveredByUid,
        'delivered_by_name': deliveredByName,
        'receipt_number': receiptNumber,
        'receipt_url': receiptUrl,
        'receipt_submitted_at': receiptSubmittedAt?.toIso8601String(),
        'payment_confirmed_by': paymentConfirmedBy,
        'payment_confirmed_at': paymentConfirmedAt?.toIso8601String(),
        'rejection_reason': rejectionReason,
        'rejected_at': rejectedAt?.toIso8601String(),
        'deadline_at': deadlineAt?.toIso8601String(),
        'stock_restored': stockRestored,
        'payment_card_number': paymentCardNumber,
        'payment_card_holder': paymentCardHolder,
        'payment_bank': paymentBank,
        'in_store_payment_method': inStorePaymentMethod,
        'promo_id': promoId,
        'promo_code': promoCode,
        'promo_discount': promoDiscount,
        'promo_counts_usage': promoCountsUsage,
      };

  OrderModel copyWith({
    String? id,
    String? clientPhone,
    String? clientName,
    String? clientUid,
    String? adminUid,
    String? storeName,
    String? warehouseId,
    String? warehouseAddress,
    String? storePhone,
    List<CartItemModel>? items,
    String? status,
    String? orderType,
    DateTime? createdAt,
    String? address,
    String? clientCity,
    String? note,
    double? depositAmount,
    double? deliveryFee,
    double? kazpostFee,
    String? postRecipientName,
    String? postRecipientPhone,
    String? postIndex,
    String? postTracking,
    String? postStatus,
    DateTime? postShippedAt,
    DateTime? postDeliveredAt,
    ReturnPolicy? returnPolicy,
    DateTime? returnNoticeAckAt,
    double? fittingFee,
    bool? deliveryFeeCollected,
    DateTime? deliveryFeeCollectedAt,
    String? deliveryMode,
    String? cartGroupId,
    String? pickupCode,
    int? orderNumber,
    String? sellerId,
    String? sellerName,
    String? deliveredByUid,
    String? deliveredByName,
    String? receiptNumber,
    String? receiptUrl,
    DateTime? receiptSubmittedAt,
    String? paymentConfirmedBy,
    DateTime? paymentConfirmedAt,
    String? rejectionReason,
    DateTime? rejectedAt,
    DateTime? deadlineAt,
    DateTime? completedAt,
    bool? stockRestored,
    String? cancelledByRole,
    String? cancelledByUid,
    String? cancelledByName,
    DateTime? cancelledAt,
    String? paymentCardNumber,
    String? paymentCardHolder,
    String? paymentBank,
    String? inStorePaymentMethod,
    String? courierUid,
    String? courierName,
    String? courierStatus,
    DateTime? courierTakenAt,
    DateTime? courierPickedUpAt,
    List<ReturnLegItem>? returnLeg,
    String? returnLegStatus,
    String? promoId,
    String? promoCode,
    double? promoDiscount,
    bool? promoCountsUsage,
    bool? isGift,
    String? giftToken,
    String? giftRecipientUid,
    String? giftRecipientName,
    String? giftRecipientPhone,
    String? giftMessage,
    bool? giftHidePrice,
    DateTime? giftClaimedAt,
    DateTime? giftExpiresAt,
    String? giftGiverName,
    double? giftPaidAmount,
    double? giftExtraDue,
    List<Map<String, dynamic>>? giftExchangeLog,
  }) =>
      OrderModel(
        id: id ?? this.id,
        clientPhone: clientPhone ?? this.clientPhone,
        clientName: clientName ?? this.clientName,
        clientUid: clientUid ?? this.clientUid,
        adminUid: adminUid ?? this.adminUid,
        storeName: storeName ?? this.storeName,
        warehouseId: warehouseId ?? this.warehouseId,
        warehouseAddress: warehouseAddress ?? this.warehouseAddress,
        storePhone: storePhone ?? this.storePhone,
        items: items ?? this.items,
        status: status ?? this.status,
        orderType: orderType ?? this.orderType,
        createdAt: createdAt ?? this.createdAt,
        address: address ?? this.address,
        clientCity: clientCity ?? this.clientCity,
        note: note ?? this.note,
        depositAmount: depositAmount ?? this.depositAmount,
        deliveryFee: deliveryFee ?? this.deliveryFee,
        kazpostFee: kazpostFee ?? this.kazpostFee,
        postRecipientName: postRecipientName ?? this.postRecipientName,
        postRecipientPhone: postRecipientPhone ?? this.postRecipientPhone,
        postIndex: postIndex ?? this.postIndex,
        postTracking: postTracking ?? this.postTracking,
        postStatus: postStatus ?? this.postStatus,
        postShippedAt: postShippedAt ?? this.postShippedAt,
        postDeliveredAt: postDeliveredAt ?? this.postDeliveredAt,
        returnPolicy: returnPolicy ?? this.returnPolicy,
        returnNoticeAckAt: returnNoticeAckAt ?? this.returnNoticeAckAt,
        fittingFee: fittingFee ?? this.fittingFee,
        deliveryFeeCollected: deliveryFeeCollected ?? this.deliveryFeeCollected,
        deliveryFeeCollectedAt:
            deliveryFeeCollectedAt ?? this.deliveryFeeCollectedAt,
        deliveryMode: deliveryMode ?? this.deliveryMode,
        cartGroupId: cartGroupId ?? this.cartGroupId,
        pickupCode: pickupCode ?? this.pickupCode,
        orderNumber: orderNumber ?? this.orderNumber,
        sellerId: sellerId ?? this.sellerId,
        sellerName: sellerName ?? this.sellerName,
        deliveredByUid: deliveredByUid ?? this.deliveredByUid,
        deliveredByName: deliveredByName ?? this.deliveredByName,
        receiptNumber: receiptNumber ?? this.receiptNumber,
        receiptUrl: receiptUrl ?? this.receiptUrl,
        receiptSubmittedAt: receiptSubmittedAt ?? this.receiptSubmittedAt,
        paymentConfirmedBy: paymentConfirmedBy ?? this.paymentConfirmedBy,
        paymentConfirmedAt: paymentConfirmedAt ?? this.paymentConfirmedAt,
        rejectionReason: rejectionReason ?? this.rejectionReason,
        rejectedAt: rejectedAt ?? this.rejectedAt,
        deadlineAt: deadlineAt ?? this.deadlineAt,
        completedAt: completedAt ?? this.completedAt,
        stockRestored: stockRestored ?? this.stockRestored,
        cancelledByRole: cancelledByRole ?? this.cancelledByRole,
        cancelledByUid: cancelledByUid ?? this.cancelledByUid,
        cancelledByName: cancelledByName ?? this.cancelledByName,
        cancelledAt: cancelledAt ?? this.cancelledAt,
        paymentCardNumber: paymentCardNumber ?? this.paymentCardNumber,
        paymentCardHolder: paymentCardHolder ?? this.paymentCardHolder,
        paymentBank: paymentBank ?? this.paymentBank,
        inStorePaymentMethod: inStorePaymentMethod ?? this.inStorePaymentMethod,
        courierUid: courierUid ?? this.courierUid,
        courierName: courierName ?? this.courierName,
        courierStatus: courierStatus ?? this.courierStatus,
        courierTakenAt: courierTakenAt ?? this.courierTakenAt,
        courierPickedUpAt: courierPickedUpAt ?? this.courierPickedUpAt,
        returnLeg: returnLeg ?? this.returnLeg,
        returnLegStatus: returnLegStatus ?? this.returnLegStatus,
        promoId: promoId ?? this.promoId,
        promoCode: promoCode ?? this.promoCode,
        promoDiscount: promoDiscount ?? this.promoDiscount,
        promoCountsUsage: promoCountsUsage ?? this.promoCountsUsage,
        isGift: isGift ?? this.isGift,
        giftToken: giftToken ?? this.giftToken,
        giftRecipientUid: giftRecipientUid ?? this.giftRecipientUid,
        giftRecipientName: giftRecipientName ?? this.giftRecipientName,
        giftRecipientPhone: giftRecipientPhone ?? this.giftRecipientPhone,
        giftMessage: giftMessage ?? this.giftMessage,
        giftHidePrice: giftHidePrice ?? this.giftHidePrice,
        giftClaimedAt: giftClaimedAt ?? this.giftClaimedAt,
        giftExpiresAt: giftExpiresAt ?? this.giftExpiresAt,
        giftGiverName: giftGiverName ?? this.giftGiverName,
        giftPaidAmount: giftPaidAmount ?? this.giftPaidAmount,
        giftExtraDue: giftExtraDue ?? this.giftExtraDue,
        giftExchangeLog: giftExchangeLog ?? this.giftExchangeLog,
      );
}
