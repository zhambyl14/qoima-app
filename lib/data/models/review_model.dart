/// Тауар пікірі (product_reviews кестесі).
///
/// Жазу құқығы — тек РАСТАЛҒАН сатып алушыда (RLS: completed тапсырыста осы
/// тауар бар клиент). Оқу публичті. Бір клиент — бір тауарға бір пікір
/// (unique product_id+client_uid; өзгерту upsert арқылы).
class ReviewModel {
  final String id;
  final String productId;
  final String adminUid;
  final String clientUid;
  final String clientName;
  final int rating; // 1..5
  final String comment;
  // Дүкен жауабы (reply_to_review RPC арқылы жазылады; '' = жауап жоқ).
  final String sellerReply;
  final DateTime? sellerReplyAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get hasReply => sellerReply.trim().isNotEmpty;

  const ReviewModel({
    required this.id,
    required this.productId,
    required this.adminUid,
    required this.clientUid,
    required this.clientName,
    required this.rating,
    required this.comment,
    this.sellerReply = '',
    this.sellerReplyAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ReviewModel.fromMap(Map<String, dynamic> m) {
    DateTime dt(dynamic v) =>
        v is String ? (DateTime.tryParse(v) ?? DateTime.now()) : DateTime.now();
    return ReviewModel(
      id: m['id'] as String? ?? '',
      productId: m['product_id'] as String? ?? '',
      adminUid: m['admin_uid'] as String? ?? '',
      clientUid: m['client_uid'] as String? ?? '',
      clientName: m['client_name'] as String? ?? '',
      rating: (m['rating'] as num?)?.toInt() ?? 0,
      comment: m['comment'] as String? ?? '',
      sellerReply: m['seller_reply'] as String? ?? '',
      sellerReplyAt: m['seller_reply_at'] is String
          ? DateTime.tryParse(m['seller_reply_at'] as String)
          : null,
      createdAt: dt(m['created_at']),
      updatedAt: dt(m['updated_at']),
    );
  }
}
