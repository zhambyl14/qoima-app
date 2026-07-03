
import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';

// ── Enums ─────────────────────────────────────────────────────────────────────

enum ReturnType { online, offline }

enum ReturnReason { sizeNotFit, qualityBad, notAsDescribed, justDidntLike, other }

enum ReturnPickup { selfBring, courier }

// Айырбас (exchange) ӘДЕЙІ ЖОҚ: қайтару әдісі әрқашан төлем әдісіне тең болуы керек
// (карта → карта, қолма-қол → қолма-қол), әйтпесе есеп (отчёт) бұзылады.
enum RefundMethod { card, cash }

/// Төлем әдісіне қарай қайтару әдісін анықтайды — пайдаланушы таңдамайды.
/// 'cash' → қолма-қол; қалғаны (kaspi/halyk/card/transfer/онлайн) → карта.
RefundMethod refundMethodForPayment(String paymentMethod) {
  return paymentMethod.trim().toLowerCase() == 'cash'
      ? RefundMethod.cash
      : RefundMethod.card;
}

enum ReturnStatus { requested, approved, received, refunded, rejected }

// ── Enum label + tone extensions ──────────────────────────────────────────────

extension ReturnTypeLabels on ReturnType {
  String label(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    switch (this) {
      case ReturnType.online:  return l.returnTypeOnline;
      case ReturnType.offline: return l.returnTypeOffline;
    }
  }

  String get tone => this == ReturnType.online ? 'blue' : 'purple';
}

extension ReturnReasonLabels on ReturnReason {
  String label(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    switch (this) {
      case ReturnReason.sizeNotFit:     return l.returnReasonSizeNotFit;
      case ReturnReason.qualityBad:     return l.returnReasonQualityBad;
      case ReturnReason.notAsDescribed: return l.returnReasonNotAsDescribed;
      case ReturnReason.justDidntLike:  return l.returnReasonJustDidntLike;
      case ReturnReason.other:          return l.returnReasonOther;
    }
  }
}

extension ReturnPickupLabels on ReturnPickup {
  String label(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    switch (this) {
      case ReturnPickup.selfBring: return l.returnPickupSelf;
      case ReturnPickup.courier:   return l.returnPickupCourier;
    }
  }
}

extension RefundMethodLabels on RefundMethod {
  String label(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    switch (this) {
      case RefundMethod.card:     return l.returnRefundCard;
      case RefundMethod.cash:     return l.returnRefundCash;
    }
  }
}

extension ReturnStatusLabels on ReturnStatus {
  String label(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    switch (this) {
      case ReturnStatus.requested: return l.returnStatusRequested;
      case ReturnStatus.approved:  return l.returnStatusApproved;
      case ReturnStatus.received:  return l.returnStatusReceived;
      case ReturnStatus.refunded:  return l.returnStatusRefunded;
      case ReturnStatus.rejected:  return l.returnStatusRejected;
    }
  }

  String get tone {
    switch (this) {
      case ReturnStatus.requested: return 'amber';
      case ReturnStatus.approved:  return 'blue';
      case ReturnStatus.received:  return 'purple';
      case ReturnStatus.refunded:  return 'green';
      case ReturnStatus.rejected:  return 'red';
    }
  }
}

// ── ReturnItem ─────────────────────────────────────────────────────────────────

class ReturnItem {
  final String productId;
  final String productTitle;
  final String? productImage;
  final String batchId;
  final String size;
  final int quantity;
  final double pricePerUnit;

  const ReturnItem({
    required this.productId,
    required this.productTitle,
    this.productImage,
    required this.batchId,
    required this.size,
    required this.quantity,
    required this.pricePerUnit,
  });

  double get subtotal => pricePerUnit * quantity;

  Map<String, dynamic> toMap() => {
        'product_id': productId,
        'product_title': productTitle,
        if (productImage != null && productImage!.isNotEmpty)
          'product_image': productImage,
        'batch_id': batchId,
        'size': size,
        'quantity': quantity,
        'price_per_unit': pricePerUnit,
      };

  factory ReturnItem.fromMap(Map<String, dynamic> m) => ReturnItem(
        productId: m['product_id'] as String? ?? '',
        productTitle: m['product_title'] as String? ?? '',
        productImage: m['product_image'] as String?,
        batchId: m['batch_id'] as String? ?? '',
        size: m['size'] as String? ?? '',
        quantity: (m['quantity'] as num?)?.toInt() ?? 0,
        pricePerUnit: (m['price_per_unit'] as num?)?.toDouble() ?? 0,
      );
}

// ── ReturnModel ────────────────────────────────────────────────────────────────

class ReturnModel {
  final String id;
  final String adminUid;
  final String? sellerId;
  final String? warehouseId;
  final String clientUid;
  final String clientName;
  final String clientPhone;

  final String? orderId;
  final String? saleId;
  final ReturnType type;

  final List<ReturnItem> items;
  final double totalAmount;

  final ReturnReason reason;
  final String? reasonNote;
  final List<String> photoUrls;

  final ReturnPickup pickup;
  final RefundMethod refundMethod;

  final ReturnStatus status;

  final DateTime createdAt;
  final DateTime? approvedAt;
  final DateTime? receivedAt;
  final DateTime? refundedAt;
  final DateTime? rejectedAt;

  final String? rejectionReason;
  final String? sellerNote;

  // Set during markReceived step
  final bool? itemConditionOk;
  final List<String> conditionPhotos;

  const ReturnModel({
    required this.id,
    required this.adminUid,
    this.sellerId,
    this.warehouseId,
    required this.clientUid,
    required this.clientName,
    required this.clientPhone,
    this.orderId,
    this.saleId,
    required this.type,
    required this.items,
    required this.totalAmount,
    required this.reason,
    this.reasonNote,
    required this.photoUrls,
    required this.pickup,
    required this.refundMethod,
    required this.status,
    required this.createdAt,
    this.approvedAt,
    this.receivedAt,
    this.refundedAt,
    this.rejectedAt,
    this.rejectionReason,
    this.sellerNote,
    this.itemConditionOk,
    this.conditionPhotos = const [],
  });

  // ── Firestore ────────────────────────────────────────────────────────────────

  static DateTime? _ts(dynamic v) {
    if (v is DateTime) return v;
    if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
    return null;
  }

  static ReturnType _parseType(String s) =>
      ReturnType.values.firstWhere((e) => e.name == s, orElse: () => ReturnType.online);
  static ReturnReason _parseReason(String s) =>
      ReturnReason.values.firstWhere((e) => e.name == s, orElse: () => ReturnReason.other);
  static ReturnPickup _parsePickup(String s) =>
      ReturnPickup.values.firstWhere((e) => e.name == s, orElse: () => ReturnPickup.selfBring);
  static RefundMethod _parseRefund(String s) =>
      RefundMethod.values.firstWhere((e) => e.name == s, orElse: () => RefundMethod.cash);
  static ReturnStatus _parseStatus(String s) =>
      ReturnStatus.values.firstWhere((e) => e.name == s, orElse: () => ReturnStatus.requested);

  factory ReturnModel.fromMap(Map<String, dynamic> d, String docId) => ReturnModel(
        id: docId,
        adminUid: d['admin_uid'] as String? ?? '',
        sellerId: d['seller_id'] as String?,
        warehouseId: d['warehouse_id'] as String?,
        clientUid: d['client_uid'] as String? ?? '',
        clientName: d['client_name'] as String? ?? '',
        clientPhone: d['client_phone'] as String? ?? '',
        orderId: d['order_id'] as String?,
        saleId: d['sale_id'] as String?,
        type: _parseType(d['type'] as String? ?? ''),
        items: (d['items'] as List<dynamic>? ?? [])
            .map((e) => ReturnItem.fromMap(e as Map<String, dynamic>))
            .toList(),
        totalAmount: (d['total_amount'] as num?)?.toDouble() ?? 0,
        reason: _parseReason(d['reason'] as String? ?? ''),
        reasonNote: d['reason_note'] as String?,
        photoUrls: (d['photo_urls'] as List<dynamic>? ?? []).cast<String>(),
        pickup: _parsePickup(d['pickup'] as String? ?? ''),
        refundMethod: _parseRefund(d['refund_method'] as String? ?? ''),
        status: _parseStatus(d['status'] as String? ?? ''),
        createdAt: _ts(d['created_at']) ?? DateTime.now(),
        approvedAt: _ts(d['approved_at']),
        receivedAt: _ts(d['received_at']),
        refundedAt: _ts(d['refunded_at']),
        rejectedAt: _ts(d['rejected_at']),
        rejectionReason: d['rejection_reason'] as String?,
        sellerNote: d['seller_note'] as String?,
        itemConditionOk: d['item_condition_ok'] as bool?,
        conditionPhotos: (d['condition_photos'] as List<dynamic>? ?? []).cast<String>(),
      );

  /// Supabase `returns` жолынан (snake_case + JSONB items).
  factory ReturnModel.fromRow(Map<String, dynamic> m) =>
      ReturnModel.fromMap(m, m['id'] as String? ?? '');

  /// Supabase жазу үшін (snake_case, ISO даталар, id қамтылады).
  Map<String, dynamic> toRow() => {
        'id': id,
        'admin_uid': adminUid,
        if (sellerId != null) 'seller_id': sellerId,
        'warehouse_id':
            (warehouseId != null && warehouseId!.isNotEmpty) ? warehouseId : null,
        'client_uid': clientUid.isEmpty ? null : clientUid,
        'client_name': clientName,
        'client_phone': clientPhone,
        if (orderId != null) 'order_id': orderId,
        if (saleId != null) 'sale_id': saleId,
        'type': type.name,
        'items': items.map((i) => i.toMap()).toList(),
        'total_amount': totalAmount,
        'reason': reason.name,
        if (reasonNote != null) 'reason_note': reasonNote,
        'photo_urls': photoUrls,
        'pickup': pickup.name,
        'refund_method': refundMethod.name,
        'status': status.name,
        'created_at': createdAt.toIso8601String(),
        if (approvedAt != null) 'approved_at': approvedAt!.toIso8601String(),
        if (receivedAt != null) 'received_at': receivedAt!.toIso8601String(),
        if (refundedAt != null) 'refunded_at': refundedAt!.toIso8601String(),
        if (rejectedAt != null) 'rejected_at': rejectedAt!.toIso8601String(),
        if (rejectionReason != null) 'rejection_reason': rejectionReason,
        if (sellerNote != null) 'seller_note': sellerNote,
        if (itemConditionOk != null) 'item_condition_ok': itemConditionOk,
        'condition_photos': conditionPhotos,
      };

  ReturnModel copyWith({
    String? id,
    String? adminUid,
    String? sellerId,
    String? warehouseId,
    String? clientUid,
    String? clientName,
    String? clientPhone,
    String? orderId,
    String? saleId,
    ReturnType? type,
    List<ReturnItem>? items,
    double? totalAmount,
    ReturnReason? reason,
    String? reasonNote,
    List<String>? photoUrls,
    ReturnPickup? pickup,
    RefundMethod? refundMethod,
    ReturnStatus? status,
    DateTime? createdAt,
    DateTime? approvedAt,
    DateTime? receivedAt,
    DateTime? refundedAt,
    DateTime? rejectedAt,
    String? rejectionReason,
    String? sellerNote,
    bool? itemConditionOk,
    List<String>? conditionPhotos,
  }) =>
      ReturnModel(
        id: id ?? this.id,
        adminUid: adminUid ?? this.adminUid,
        sellerId: sellerId ?? this.sellerId,
        warehouseId: warehouseId ?? this.warehouseId,
        clientUid: clientUid ?? this.clientUid,
        clientName: clientName ?? this.clientName,
        clientPhone: clientPhone ?? this.clientPhone,
        orderId: orderId ?? this.orderId,
        saleId: saleId ?? this.saleId,
        type: type ?? this.type,
        items: items ?? this.items,
        totalAmount: totalAmount ?? this.totalAmount,
        reason: reason ?? this.reason,
        reasonNote: reasonNote ?? this.reasonNote,
        photoUrls: photoUrls ?? this.photoUrls,
        pickup: pickup ?? this.pickup,
        refundMethod: refundMethod ?? this.refundMethod,
        status: status ?? this.status,
        createdAt: createdAt ?? this.createdAt,
        approvedAt: approvedAt ?? this.approvedAt,
        receivedAt: receivedAt ?? this.receivedAt,
        refundedAt: refundedAt ?? this.refundedAt,
        rejectedAt: rejectedAt ?? this.rejectedAt,
        rejectionReason: rejectionReason ?? this.rejectionReason,
        sellerNote: sellerNote ?? this.sellerNote,
        itemConditionOk: itemConditionOk ?? this.itemConditionOk,
        conditionPhotos: conditionPhotos ?? this.conditionPhotos,
      );
}

// ── Input / query types ───────────────────────────────────────────────────────

class ReturnRequestInput {
  final String adminUid;
  final String clientUid;
  final String clientName;
  final String clientPhone;
  final String? orderId;
  final List<ReturnItem> items;
  final ReturnReason reason;
  final String? reasonNote;
  final List<String> photoUrls;
  final ReturnPickup pickup;
  final RefundMethod refundMethod;

  const ReturnRequestInput({
    required this.adminUid,
    required this.clientUid,
    required this.clientName,
    required this.clientPhone,
    this.orderId,
    required this.items,
    required this.reason,
    this.reasonNote,
    required this.photoUrls,
    required this.pickup,
    required this.refundMethod,
  });
}

class DateRange {
  final DateTime from;
  final DateTime to;

  const DateRange({required this.from, required this.to});

  static DateRange forDay(DateTime d) => DateRange(
        from: DateTime(d.year, d.month, d.day),
        to: DateTime(d.year, d.month, d.day + 1),
      );

  static DateRange forWeek(DateTime d) {
    final monday = d.subtract(Duration(days: d.weekday - 1));
    final from = DateTime(monday.year, monday.month, monday.day);
    return DateRange(from: from, to: from.add(const Duration(days: 7)));
  }

  static DateRange forMonth(DateTime d) => DateRange(
        from: DateTime(d.year, d.month, 1),
        to: DateTime(d.year, d.month + 1, 1),
      );

  static DateRange forYear(DateTime d) => DateRange(
        from: DateTime(d.year, 1, 1),
        to: DateTime(d.year + 1, 1, 1),
      );
}

class ReturnAnalytics {
  final int totalReturns;
  final int totalSales;
  final double returnRate;
  final Map<ReturnReason, int> reasonBreakdown;
  final List<({String title, int count})> topReturnedProducts;
  final Map<String, int> perSellerClosed;

  const ReturnAnalytics({
    required this.totalReturns,
    required this.totalSales,
    required this.returnRate,
    required this.reasonBreakdown,
    required this.topReturnedProducts,
    required this.perSellerClosed,
  });

  static ReturnAnalytics empty() => const ReturnAnalytics(
        totalReturns: 0,
        totalSales: 0,
        returnRate: 0,
        reasonBreakdown: {},
        topReturnedProducts: [],
        perSellerClosed: {},
      );
}
