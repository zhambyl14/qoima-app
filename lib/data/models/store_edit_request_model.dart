/// Owner дүкен мәліметтерін өзгерту запросы (Supabase `store_edit_requests`, v10).
class StoreEditRequestModel {
  final String id;
  final String ownerUid;
  final String shopName;
  final List<EditField> changes;
  final String ownerComment;
  final String status; // 'pending' | 'approved' | 'rejected' | 'cancelled'
  final DateTime createdAt;
  final DateTime? reviewedAt;
  final String reviewedBy;
  final String reviewNote;

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

  /// Supabase `store_edit_requests` жолынан (snake_case + changes JSONB).
  factory StoreEditRequestModel.fromMap(Map<String, dynamic> m) {
    DateTime? dtn(dynamic v) =>
        v is String && v.isNotEmpty ? DateTime.tryParse(v) : null;
    return StoreEditRequestModel(
      id: m['id'] as String? ?? '',
      ownerUid: m['owner_uid'] as String? ?? '',
      shopName: m['shop_name'] as String? ?? '',
      changes: (m['changes'] as List? ?? [])
          .map((e) => EditField.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList(),
      ownerComment: m['owner_comment'] as String? ?? '',
      status: m['status'] as String? ?? 'pending',
      createdAt: dtn(m['created_at']) ?? DateTime.now(),
      reviewedAt: dtn(m['reviewed_at']),
      reviewedBy: m['reviewed_by'] as String? ?? '',
      reviewNote: m['review_note'] as String? ?? '',
    );
  }

  /// Supabase жазу үшін (insert).
  Map<String, dynamic> toMap() => {
        'owner_uid': ownerUid,
        'shop_name': shopName,
        'changes': changes.map((c) => c.toMap()).toList(),
        'owner_comment': ownerComment,
        'status': status,
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
  final String label;
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
