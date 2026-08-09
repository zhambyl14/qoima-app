import 'cart_item_model.dart';

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
  });

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
  double get clientTotal => storeAmount + courierAmount;

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
  bool get byPlatformCourier => isDelivery && deliveryMode != deliveryByStore;
  bool get storeDeliversItself => isDelivery && deliveryMode == deliveryByStore;

  bool get hasCourier => courierUid.isNotEmpty;
  bool get courierOnWay => courierStatus == courierPickedUp;
  /// «Өлшеп көру» сұралған позициялар бар ма (курьер қосымша өлшем алып барады).
  bool get hasFitting => items.any((i) => i.hasAltSize);

  /// Курьерде қоймаға қайтып бара жатқан өлшем бар ма.
  bool get returnLegPending => returnLegStatus == 'pending';
  bool get returnLegDone => returnLegStatus == 'returned';
  bool get hasReturnLeg => returnLeg.isNotEmpty;

  bool get isAwaitingReview => status == statusPending && receiptUrl.isNotEmpty;
  bool get canHandOver => status == statusConfirmed;
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
      );
}
