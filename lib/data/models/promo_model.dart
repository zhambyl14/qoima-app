/// Промокод магазина (Supabase `promos`).
class PromoModel {
  final String id;
  final String code; // UPPERCASE, уникален в пределах магазина
  final String type; // 'percent' | 'amount'
  final double value;
  final String scope; // 'all' | 'products'
  final List<String> productIds;
  final int? maxUses;
  final int usedCount;
  final int? perUserLimit;
  final double minOrder;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final bool active;
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
  bool get isExhausted => maxUses != null && usedCount >= maxUses!;
  bool get isStarted => startsAt == null || !DateTime.now().isBefore(startsAt!);
  bool get isExpired => endsAt != null && DateTime.now().isAfter(endsAt!);
  bool get isLive => active && isStarted && !isExpired && !isExhausted;

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

  /// Supabase `promos` жолынан (snake_case бағандар).
  factory PromoModel.fromRow(Map<String, dynamic> m) {
    DateTime? dtn(dynamic v) =>
        v is String && v.isNotEmpty ? DateTime.tryParse(v) : null;
    return PromoModel(
      id: m['id'] as String? ?? '',
      code: (m['code'] as String? ?? '').toUpperCase(),
      type: m['type'] as String? ?? 'percent',
      value: (m['value'] as num?)?.toDouble() ?? 0,
      scope: m['scope'] as String? ?? 'all',
      productIds:
          (m['product_ids'] as List?)?.map((e) => e.toString()).toList() ?? [],
      maxUses: (m['max_uses'] as num?)?.toInt(),
      usedCount: (m['used_count'] as num?)?.toInt() ?? 0,
      perUserLimit: (m['per_user_limit'] as num?)?.toInt(),
      minOrder: (m['min_order'] as num?)?.toDouble() ?? 0,
      startsAt: dtn(m['starts_at']),
      endsAt: dtn(m['ends_at']),
      active: m['active'] as bool? ?? true,
      createdAt: dtn(m['created_at']),
    );
  }

  /// Supabase жазу үшін (snake_case; admin_uid/used_count сервисте басқарылады).
  Map<String, dynamic> toRow() => {
        'code': code.toUpperCase(),
        'type': type,
        'value': value,
        'scope': scope,
        'product_ids': productIds,
        'max_uses': maxUses,
        'per_user_limit': perUserLimit,
        'min_order': minOrder,
        'starts_at': startsAt?.toIso8601String(),
        'ends_at': endsAt?.toIso8601String(),
        'active': active,
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
  final double discount;
  final String? error;

  const PromoResult.ok(this.promo, this.discount) : error = null;
  const PromoResult.fail(this.error)
      : promo = null,
        discount = 0;

  bool get isOk => error == null && promo != null;
}
