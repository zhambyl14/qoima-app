/// Тауар бойынша сұрақ-жауап (product_questions кестесі, Wildberries
/// «Вопросы и ответы» үлгісі). Жауап тек answer_product_question() RPC
/// арқылы жазылады.
class ProductQuestionModel {
  final String id;
  final String productId;
  final String adminUid;
  final String clientUid;
  final String clientName;
  final String question;
  final String answer;
  final DateTime? answeredAt;
  final DateTime createdAt;

  bool get hasAnswer => answer.trim().isNotEmpty;

  const ProductQuestionModel({
    required this.id,
    required this.productId,
    required this.adminUid,
    required this.clientUid,
    required this.clientName,
    required this.question,
    this.answer = '',
    this.answeredAt,
    required this.createdAt,
  });

  factory ProductQuestionModel.fromMap(Map<String, dynamic> m) {
    DateTime dt(dynamic v) =>
        v is String ? (DateTime.tryParse(v) ?? DateTime.now()) : DateTime.now();
    return ProductQuestionModel(
      id: m['id'] as String? ?? '',
      productId: m['product_id'] as String? ?? '',
      adminUid: m['admin_uid'] as String? ?? '',
      clientUid: m['client_uid'] as String? ?? '',
      clientName: m['client_name'] as String? ?? '',
      question: m['question'] as String? ?? '',
      answer: m['answer'] as String? ?? '',
      answeredAt: m['answered_at'] is String
          ? DateTime.tryParse(m['answered_at'] as String)
          : null,
      createdAt: dt(m['created_at']),
    );
  }
}
