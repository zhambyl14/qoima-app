import 'package:cloud_firestore/cloud_firestore.dart';

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
  final List<String> targetProductIds; // batch-скидка нақты осы тауарларға жазылды
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

  factory StoreDiscountModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return StoreDiscountModel(
      id: doc.id,
      storeId: d['storeId'] as String? ?? '',
      type: d['type'] == 'fixed' ? DiscountType.fixed : DiscountType.percent,
      value: (d['value'] as num?)?.toDouble() ?? 0,
      scope: _scope(d['scope'] as String?),
      scopeId: d['scopeId'] as String? ?? '',
      scopeLabel: d['scopeLabel'] as String? ?? '',
      targetProductIds:
          (d['targetProductIds'] as List?)?.map((e) => e.toString()).toList() ?? [],
      hasDateLimit: d['hasDateLimit'] as bool? ?? false,
      startsAt: (d['startsAt'] as Timestamp?)?.toDate(),
      endsAt: (d['endsAt'] as Timestamp?)?.toDate(),
      isActive: d['isActive'] as bool? ?? true,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  static DiscountScope _scope(String? s) {
    switch (s) {
      case 'category': return DiscountScope.category;
      case 'store':    return DiscountScope.store;
      default:         return DiscountScope.product;
    }
  }

  Map<String, dynamic> toJson() => {
        'storeId': storeId,
        'type': type == DiscountType.fixed ? 'fixed' : 'percent',
        'value': value,
        'scope': scope.name,
        'scopeId': scopeId,
        'scopeLabel': scopeLabel,
        'targetProductIds': targetProductIds,
        'hasDateLimit': hasDateLimit,
        'startsAt': startsAt != null ? Timestamp.fromDate(startsAt!) : null,
        'endsAt': endsAt != null ? Timestamp.fromDate(endsAt!) : null,
        'isActive': isActive,
        'createdAt': Timestamp.fromDate(createdAt),
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
