import 'package:cloud_firestore/cloud_firestore.dart';
import 'cart_item_model.dart';

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
  final String note;
  final double depositAmount;
  final double deliveryFee;
  final String pickupCode;
  final int orderNumber;
  final String sellerId;
  final String sellerName;
  final String deliveredByUid;
  final String deliveredByName;
  // Чек нөмірі (#NNNNN) — тауар берілгенде реттік есептегіштен беріледі.
  // Заказ нөмірінен (orderNumber) БӨЛЕК идентификатор.
  final String receiptNumber;

  // ── Payment receipt flow ────────────────────────────────────────────────────
  final String receiptUrl;
  final DateTime? receiptSubmittedAt;
  final String paymentConfirmedBy;
  final DateTime? paymentConfirmedAt;
  final String rejectionReason;
  final DateTime? rejectedAt;
  // Клиенттің күту мерзімі (null = таймер жоқ, яғни тексерілуде немесе аяқталды)
  final DateTime? deadlineAt;
  // Бас тарту кезінде қалдық қайтарылды ма (қайталаудан қорғайды)
  final bool stockRestored;
  // Тапсырыс кезіндегі продавецтің төлем реквизиттері (снапшот)
  final String paymentCardNumber;
  final String paymentCardHolder;
  final String paymentBank;
  // Қоймада жасалған доплата әдісі ('cash' / 'kaspi' / 'halyk')
  final String inStorePaymentMethod;

  // ── Промокод (снапшот на момент заказа) ──────────────────────────────────────
  final String promoId;
  final String promoCode;
  final double promoDiscount; // скидка по промокоду, ₸
  // Этот заказ владеет счётчиком used_count промокода — при отмене вернуть ровно раз
  final bool promoCountsUsage;

  static const Duration receiptWindow = Duration(minutes: 30);
  static const Duration pickupWindow  = Duration(minutes: 60);

  static const String typeSmartReservation = 'smart_reservation';
  static const String typeClickCollect = 'click_collect';
  static const String typeDelivery = 'delivery';

  static const String statusReserved  = 'reserved';   // Бронь депозиті расталды
  static const String statusPending   = 'pending';    // Оплата тексерілуде
  static const String statusRejected  = 'rejected';   // Чек қабылданбады
  static const String statusConfirmed = 'confirmed';  // Оплата расталды · беруге дайын
  static const String statusReady     = 'ready';      // legacy — жаңа ағымда қолданылмайды
  static const String statusCompleted = 'completed';  // Берілді
  static const String statusCancelled = 'cancelled';  // Бас тартылды

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
    this.note = '',
    this.depositAmount = 0.0,
    this.deliveryFee = 0.0,
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
    this.paymentCardNumber = '',
    this.paymentCardHolder = '',
    this.paymentBank = '',
    this.inStorePaymentMethod = '',
    this.promoId = '',
    this.promoCode = '',
    this.promoDiscount = 0.0,
    this.promoCountsUsage = false,
  });

  double get total => items.fold(0.0, (s, i) => s + i.subtotal);
  // Итог после промокода (не ниже нуля)
  double get finalTotal => (total - promoDiscount).clamp(0.0, total);
  double get totalWithDelivery => finalTotal + deliveryFee;
  double get remainingAmount => (finalTotal - depositAmount).clamp(0.0, finalTotal);

  bool get isSmartReservation => orderType == typeSmartReservation;
  bool get isClickCollect => orderType == typeClickCollect;
  bool get isDelivery => orderType == typeDelivery;

  // Чек жіберілген, бірақ тексерілмеген
  bool get isAwaitingReview => status == statusPending && receiptUrl.isNotEmpty;

  // Тек confirmed кезінде ғана беруге болады
  bool get canHandOver => status == statusConfirmed;

  // Толық онлайн төлем жолы (бронь емес)
  bool get isFullPrepay => orderType != typeSmartReservation;

  // deadlineAt-қа негізделген таймер (клиент + admin/seller экрандарда)
  bool get isExpired =>
      deadlineAt != null && DateTime.now().isAfter(deadlineAt!);

  // Артта қалған legacy геттерлер (ReservationTimerWidget үшін сақталады)
  DateTime get expiresAt =>
      deadlineAt ?? createdAt.add(const Duration(hours: 1));
  int get minutesLeft =>
      expiresAt.difference(DateTime.now()).inMinutes.clamp(0, 60);

  factory OrderModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return OrderModel(
      id: doc.id,
      clientPhone: d['clientPhone'] as String? ?? '',
      clientName: d['clientName'] as String? ?? '',
      clientUid: d['clientUid'] as String? ?? '',
      adminUid: d['adminUid'] as String? ?? '',
      storeName: d['storeName'] as String? ?? '',
      warehouseId: d['warehouseId'] as String? ?? '',
      warehouseAddress: d['warehouseAddress'] as String? ?? '',
      storePhone: d['storePhone'] as String? ?? '',
      items: (d['items'] as List<dynamic>? ?? [])
          .map((e) => CartItemModel.fromJson(e as Map<String, dynamic>))
          .toList(),
      status: d['status'] as String? ?? statusPending,
      orderType: d['orderType'] as String? ?? typeClickCollect,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      address: d['address'] as String? ?? '',
      note: d['note'] as String? ?? '',
      depositAmount: (d['depositAmount'] as num?)?.toDouble() ?? 0.0,
      deliveryFee: (d['deliveryFee'] as num?)?.toDouble() ?? 0.0,
      pickupCode: d['pickupCode'] as String? ?? '',
      orderNumber: (d['orderNumber'] as num?)?.toInt() ?? 0,
      sellerId: d['sellerId'] as String? ?? 'онлайн',
      sellerName: d['sellerName'] as String? ?? 'Онлайн',
      deliveredByUid: d['deliveredByUid'] as String? ?? '',
      deliveredByName: d['deliveredByName'] as String? ?? '',
      receiptNumber: d['receiptNumber'] as String? ?? '',
      receiptUrl: d['receiptUrl'] as String? ?? '',
      receiptSubmittedAt:
          (d['receiptSubmittedAt'] as Timestamp?)?.toDate(),
      paymentConfirmedBy: d['paymentConfirmedBy'] as String? ?? '',
      paymentConfirmedAt:
          (d['paymentConfirmedAt'] as Timestamp?)?.toDate(),
      rejectionReason: d['rejectionReason'] as String? ?? '',
      rejectedAt: (d['rejectedAt'] as Timestamp?)?.toDate(),
      deadlineAt: (d['deadlineAt'] as Timestamp?)?.toDate(),
      stockRestored: d['stockRestored'] as bool? ?? false,
      paymentCardNumber: d['paymentCardNumber'] as String? ?? '',
      paymentCardHolder: d['paymentCardHolder'] as String? ?? '',
      paymentBank: d['paymentBank'] as String? ?? '',
      inStorePaymentMethod: d['inStorePaymentMethod'] as String? ?? '',
      promoId: d['promoId'] as String? ?? '',
      promoCode: d['promoCode'] as String? ?? '',
      promoDiscount: (d['promoDiscount'] as num?)?.toDouble() ?? 0.0,
      promoCountsUsage: d['promoCountsUsage'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'clientPhone': clientPhone,
        'clientName': clientName,
        'clientUid': clientUid,
        'adminUid': adminUid,
        'storeName': storeName,
        'warehouseId': warehouseId,
        'warehouseAddress': warehouseAddress,
        'storePhone': storePhone,
        'items': items.map((i) => i.toJson()).toList(),
        'status': status,
        'orderType': orderType,
        'createdAt': Timestamp.fromDate(createdAt),
        'address': address,
        'note': note,
        'depositAmount': depositAmount,
        'deliveryFee': deliveryFee,
        'pickupCode': pickupCode,
        'orderNumber': orderNumber,
        'sellerId': sellerId,
        'sellerName': sellerName,
        'deliveredByUid': deliveredByUid,
        'deliveredByName': deliveredByName,
        'receiptNumber': receiptNumber,
        'receiptUrl': receiptUrl,
        'receiptSubmittedAt': receiptSubmittedAt != null
            ? Timestamp.fromDate(receiptSubmittedAt!)
            : null,
        'paymentConfirmedBy': paymentConfirmedBy,
        'paymentConfirmedAt': paymentConfirmedAt != null
            ? Timestamp.fromDate(paymentConfirmedAt!)
            : null,
        'rejectionReason': rejectionReason,
        'rejectedAt':
            rejectedAt != null ? Timestamp.fromDate(rejectedAt!) : null,
        'deadlineAt':
            deadlineAt != null ? Timestamp.fromDate(deadlineAt!) : null,
        'paymentCardNumber': paymentCardNumber,
        'paymentCardHolder': paymentCardHolder,
        'paymentBank': paymentBank,
        'inStorePaymentMethod': inStorePaymentMethod,
        'promoId': promoId,
        'promoCode': promoCode,
        'promoDiscount': promoDiscount,
        'promoCountsUsage': promoCountsUsage,
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
    String? note,
    double? depositAmount,
    double? deliveryFee,
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
    String? paymentCardNumber,
    String? paymentCardHolder,
    String? paymentBank,
    String? inStorePaymentMethod,
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
        note: note ?? this.note,
        depositAmount: depositAmount ?? this.depositAmount,
        deliveryFee: deliveryFee ?? this.deliveryFee,
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
        paymentCardNumber: paymentCardNumber ?? this.paymentCardNumber,
        paymentCardHolder: paymentCardHolder ?? this.paymentCardHolder,
        paymentBank: paymentBank ?? this.paymentBank,
        inStorePaymentMethod: inStorePaymentMethod ?? this.inStorePaymentMethod,
        promoId: promoId ?? this.promoId,
        promoCode: promoCode ?? this.promoCode,
        promoDiscount: promoDiscount ?? this.promoDiscount,
        promoCountsUsage: promoCountsUsage ?? this.promoCountsUsage,
      );
}
