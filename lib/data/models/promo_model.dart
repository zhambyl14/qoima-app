import 'package:cloud_firestore/cloud_firestore.dart';

/// Промокод магазина: `users/{adminUid}/promos/{promoId}`.
/// Учёт «кто уже применял» — подколлекция `redemptions/{clientUid}`.
class PromoModel {
  final String id;
  final String code; // UPPERCASE, уникален в пределах магазина
  final String type; // 'percent' | 'amount'
  final double value; // 20 (%) или 5000 (₸)
  final String scope; // 'all' | 'products'
  final List<String> productIds; // если scope == 'products'
  final int? maxUses; // всего использований (null = ∞)
  final int usedCount; // счётчик
  final int? perUserLimit; // на 1 клиента (null = ∞)
  final double minOrder; // мин. сумма заказа (0 = нет)
  final DateTime? startsAt;
  final DateTime? endsAt;
  final bool active; // ручной вкл/выкл
  final DateTime? createdAt;

  const PromoModel({
    required this.id,
    required this.code,
    required this.type,
    required this.value,
    this.scope = 'all',
    this.productIds = const [],
    this.maxUses,
    this.usedCount = 0,
    this.perUserLimit = 1,
    this.minOrder = 0,
    this.startsAt,
    this.endsAt,
    this.active = true,
    this.createdAt,
  });

  bool get isPercent => type == 'percent';

  // Достигнут общий лимит использований
  bool get isExhausted => maxUses != null && usedCount >= maxUses!;

  bool get isStarted =>
      startsAt == null || !DateTime.now().isBefore(startsAt!);
  bool get isExpired => endsAt != null && DateTime.now().isAfter(endsAt!);

  // Активен «прямо сейчас» (для UI/применения)
  bool get isLive => active && isStarted && !isExpired && !isExhausted;

  // Сколько дней осталось до конца действия (null = бессрочно)
  int? get daysLeft {
    if (endsAt == null) return null;
    final diff = endsAt!.difference(DateTime.now()).inDays;
    return diff < 0 ? 0 : diff;
  }

  /// Скидка от суммы [base] (₸). Не больше самой суммы.
  double discountFor(double base) {
    if (base <= 0) return 0;
    final raw = isPercent ? base * value / 100 : value;
    final d = raw > base ? base : raw;
    return d < 0 ? 0 : d.roundToDouble();
  }

  factory PromoModel.fromMap(Map<String, dynamic> m, String id) => PromoModel(
        id: id,
        code: (m['code'] as String? ?? '').toUpperCase(),
        type: m['type'] as String? ?? 'percent',
        value: (m['value'] as num?)?.toDouble() ?? 0,
        scope: m['scope'] as String? ?? 'all',
        productIds: (m['product_ids'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
        maxUses: (m['max_uses'] as num?)?.toInt(),
        usedCount: (m['used_count'] as num?)?.toInt() ?? 0,
        perUserLimit: (m['per_user_limit'] as num?)?.toInt(),
        minOrder: (m['min_order'] as num?)?.toDouble() ?? 0,
        startsAt: (m['starts_at'] as Timestamp?)?.toDate(),
        endsAt: (m['ends_at'] as Timestamp?)?.toDate(),
        active: m['active'] as bool? ?? true,
        createdAt: (m['created_at'] as Timestamp?)?.toDate(),
      );

  factory PromoModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) =>
      PromoModel.fromMap(doc.data() ?? {}, doc.id);

  Map<String, dynamic> toMap() => {
        'code': code.toUpperCase(),
        'type': type,
        'value': value,
        'scope': scope,
        'product_ids': productIds,
        'max_uses': maxUses,
        'used_count': usedCount,
        'per_user_limit': perUserLimit,
        'min_order': minOrder,
        'starts_at': startsAt != null ? Timestamp.fromDate(startsAt!) : null,
        'ends_at': endsAt != null ? Timestamp.fromDate(endsAt!) : null,
        'active': active,
        'created_at':
            createdAt != null ? Timestamp.fromDate(createdAt!) : FieldValue.serverTimestamp(),
      };

  PromoModel copyWith({
    String? id,
    String? code,
    String? type,
    double? value,
    String? scope,
    List<String>? productIds,
    Object? maxUses = _kSentinel,
    int? usedCount,
    Object? perUserLimit = _kSentinel,
    double? minOrder,
    Object? startsAt = _kSentinel,
    Object? endsAt = _kSentinel,
    bool? active,
    DateTime? createdAt,
  }) =>
      PromoModel(
        id: id ?? this.id,
        code: code ?? this.code,
        type: type ?? this.type,
        value: value ?? this.value,
        scope: scope ?? this.scope,
        productIds: productIds ?? this.productIds,
        maxUses: identical(maxUses, _kSentinel) ? this.maxUses : maxUses as int?,
        usedCount: usedCount ?? this.usedCount,
        perUserLimit: identical(perUserLimit, _kSentinel)
            ? this.perUserLimit
            : perUserLimit as int?,
        minOrder: minOrder ?? this.minOrder,
        startsAt:
            identical(startsAt, _kSentinel) ? this.startsAt : startsAt as DateTime?,
        endsAt: identical(endsAt, _kSentinel) ? this.endsAt : endsAt as DateTime?,
        active: active ?? this.active,
        createdAt: createdAt ?? this.createdAt,
      );

  static const _kSentinel = Object();
}

/// Результат валидации промокода для корзины конкретного магазина.
class PromoResult {
  final PromoModel? promo;
  final double discount; // итоговая скидка по промокоду (₸)
  final String? error; // понятная причина отказа (RU), null если ок

  const PromoResult.ok(this.promo, this.discount) : error = null;
  const PromoResult.fail(this.error)
      : promo = null,
        discount = 0;

  bool get isOk => error == null && promo != null;
}
