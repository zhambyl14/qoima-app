import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/app_user.dart';
import '../models/product_question_model.dart';

/// Дүкен иесі (admin/seller) — өз тауарларының сұрақтарын көру + жауап беру.
class AdminQuestionsRepository {
  final SupabaseClient _sb = Supabase.instance.client;

  // admin → өз uid; seller → admin uid (AdminReviewsRepository үлгісімен).
  String get _ownerUid => AppUser.current.ownerUid.isNotEmpty
      ? AppUser.current.ownerUid
      : (_sb.auth.currentUser?.id ?? '');

  /// Дүкеннің барлық сұрақтары (жаңасы бірінші, realtime).
  Stream<List<ProductQuestionModel>> watchStoreQuestions() => _sb
      .from('product_questions')
      .stream(primaryKey: ['id'])
      .eq('admin_uid', _ownerUid)
      .order('created_at', ascending: false)
      .map((rows) => rows.map(ProductQuestionModel.fromMap).toList());

  /// Тауар id → (атауы, бірінші фото) — сұрақ карточкасында көрсету үшін.
  Future<Map<String, ({String name, String image})>> productsBrief() async {
    final rows = await _sb
        .from('products')
        .select('id,name,images')
        .eq('owner_uid', _ownerUid);
    return {
      for (final r in rows)
        r['id'] as String: (
          name: r['name'] as String? ?? '',
          image: ((r['images'] as List?)?.isNotEmpty ?? false)
              ? (r['images'] as List).first.toString()
              : '',
        ),
    };
  }

  /// Сұраққа жауап жазу/өзгерту; бос мәтін — жауапты өшіру.
  /// SECURITY DEFINER RPC — тек өз дүкенінің сұрағына рұқсат.
  Future<void> answer(String questionId, String answerText) => _sb.rpc(
      'answer_product_question',
      params: {'p_question': questionId, 'p_answer': answerText});
}
