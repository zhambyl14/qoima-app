enum DiscountType { percent, fixed }

enum DiscountScope { product, category, store }

class StoreDiscountModel {
  final String id;
  final String storeId;
  final DiscountType type;
  final double value;
  final DiscountScope scope;
  final String scopeId;
  final String scopeLabel;
  final List<String> targetProductIds;
  final bool hasDateLimit;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final bool isActive;
  final DateTime createdAt;

  const StoreDiscountModel({
    required this.id,
    required this.storeId,
    required this.type,
    required this.value,
    required this.scope,
    this.scopeId = '',
    required this.scopeLabel,
    this.targetProductIds = const [],
    this.hasDateLimit = false,
    this.startsAt,
    this.endsAt,
    this.isActive = true,
    required this.createdAt,
  });

  static DiscountScope _scope(String? s) {
    switch (s) {
      case 'category':
        return DiscountScope.category;
      case 'store':
        return DiscountScope.store;
      default:
        return DiscountScope.product;
    }
  }

  /// Supabase `store_discounts` жолынан (snake_case бағандар).
  factory StoreDiscountModel.fromMap(Map<String, dynamic> m) {
    DateTime? dtn(dynamic v) =>
        v is String && v.isNotEmpty ? DateTime.tryParse(v) : null;
    return StoreDiscountModel(
      id: m['id'] as String? ?? '',
      storeId: m['store_id'] as String? ?? '',
      type: m['type'] == 'fixed' ? DiscountType.fixed : DiscountType.percent,
      value: (m['value'] as num?)?.toDouble() ?? 0,
      scope: _scope(m['scope'] as String?),
      scopeId: m['scope_id'] as String? ?? '',
      scopeLabel: m['scope_label'] as String? ?? '',
      targetProductIds:
          (m['target_product_ids'] as List?)?.map((e) => e.toString()).toList() ??
              [],
      hasDateLimit: m['has_date_limit'] as bool? ?? false,
      startsAt: dtn(m['starts_at']),
      endsAt: dtn(m['ends_at']),
      isActive: m['is_active'] as bool? ?? true,
      createdAt: dtn(m['created_at']) ?? DateTime.now(),
    );
  }

  /// Supabase жазу үшін (snake_case; store_id сервисте қосылады).
  Map<String, dynamic> toMap() => {
        'type': type == DiscountType.fixed ? 'fixed' : 'percent',
        'value': value,
        'scope': scope.name,
        'scope_id': scopeId,
        'scope_label': scopeLabel,
        'target_product_ids': targetProductIds,
        'has_date_limit': hasDateLimit,
        'starts_at': startsAt?.toIso8601String(),
        'ends_at': endsAt?.toIso8601String(),
        'is_active': isActive,
      };

  String get displayValue => type == DiscountType.percent
      ? '−${value.toStringAsFixed(0)}%'
      : '−${_fmt(value.toInt())} ₸';

  int? get daysLeft {
    if (endsAt == null) return null;
    final d = endsAt!.difference(DateTime.now()).inDays;
    return d < 0 ? 0 : d;
  }

  static String _fmt(int v) {
    final s = v.toString();
    var out = '';
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) out += ' ';
      out += s[i];
    }
    return out;
  }
}
