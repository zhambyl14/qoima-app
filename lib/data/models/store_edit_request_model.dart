import 'package:cloud_firestore/cloud_firestore.dart';

/// Owner дүкен мәліметтерін өзгерткісі келгенде жасалатын запрос (v10).
/// Әр [EditField]: { field, label, oldValue, newValue }. `field` — нақты
/// store құжатының кілті (storeName, city, description, ownerName, ownerIin,
/// phone, paymentCardNumber) — approve кезінде сол кілтпен store/main-ге қолданылады.
/// Top-level collection: `storeEditRequests/{editId}`.
class StoreEditRequestModel {
  final String id;
  final String ownerUid;
  final String shopName; // ағымдағы дүкен аты (тізімде көрсету үшін)

  /// Өзгертілген өрістер тізімі (тек өзгергендері)
  final List<EditField> changes;

  final String ownerComment; // иесінің түсініктемесі (опционалды)

  // 'pending' | 'approved' | 'rejected' | 'cancelled'
  final String status;

  final DateTime createdAt;
  final DateTime? reviewedAt;
  final String reviewedBy;
  final String reviewNote; // қайтару себебі (болса)

  const StoreEditRequestModel({
    required this.id,
    required this.ownerUid,
    required this.shopName,
    required this.changes,
    this.ownerComment = '',
    this.status = 'pending',
    required this.createdAt,
    this.reviewedAt,
    this.reviewedBy = '',
    this.reviewNote = '',
  });

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';
  bool get isCancelled => status == 'cancelled';

  factory StoreEditRequestModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return StoreEditRequestModel(
      id: doc.id,
      ownerUid: d['ownerUid'] as String? ?? '',
      shopName: d['shopName'] as String? ?? '',
      changes: (d['changes'] as List<dynamic>? ?? [])
          .map((e) => EditField.fromMap(e as Map<String, dynamic>))
          .toList(),
      ownerComment: d['ownerComment'] as String? ?? '',
      status: d['status'] as String? ?? 'pending',
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      reviewedAt: (d['reviewedAt'] as Timestamp?)?.toDate(),
      reviewedBy: d['reviewedBy'] as String? ?? '',
      reviewNote: d['reviewNote'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'ownerUid': ownerUid,
        'shopName': shopName,
        'changes': changes.map((c) => c.toMap()).toList(),
        'ownerComment': ownerComment,
        'status': status,
        'createdAt': Timestamp.fromDate(createdAt),
        'reviewedAt': reviewedAt != null ? Timestamp.fromDate(reviewedAt!) : null,
        'reviewedBy': reviewedBy,
        'reviewNote': reviewNote,
      };

  StoreEditRequestModel copyWith({
    String? status,
    DateTime? reviewedAt,
    String? reviewedBy,
    String? reviewNote,
  }) =>
      StoreEditRequestModel(
        id: id,
        ownerUid: ownerUid,
        shopName: shopName,
        changes: changes,
        ownerComment: ownerComment,
        createdAt: createdAt,
        status: status ?? this.status,
        reviewedAt: reviewedAt ?? this.reviewedAt,
        reviewedBy: reviewedBy ?? this.reviewedBy,
        reviewNote: reviewNote ?? this.reviewNote,
      );
}

class EditField {
  final String field; // 'phone' | 'paymentCardNumber' | 'description' | ...
  final String label; // 'Телефон', 'Номер карты' (UI-да көрсету үшін)
  final String oldValue;
  final String newValue;

  const EditField({
    required this.field,
    required this.label,
    required this.oldValue,
    required this.newValue,
  });

  factory EditField.fromMap(Map<String, dynamic> m) => EditField(
        field: m['field'] as String? ?? '',
        label: m['label'] as String? ?? '',
        oldValue: m['oldValue'] as String? ?? '',
        newValue: m['newValue'] as String? ?? '',
      );

  Map<String, dynamic> toMap() => {
        'field': field,
        'label': label,
        'oldValue': oldValue,
        'newValue': newValue,
      };
}
