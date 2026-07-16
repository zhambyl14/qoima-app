import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/app_user.dart';
import '../models/review_model.dart';

/// Дүкен иесі (admin/seller) — өз тауарларының пікірлерін көру + жауап беру.
class AdminReviewsRepository {
  final SupabaseClient _sb = Supabase.instance.client;

  // admin → өз uid; seller → admin uid (FirestoreService._ownerUid үлгісімен).
  String get _ownerUid => AppUser.current.ownerUid.isNotEmpty
      ? AppUser.current.ownerUid
      : (_sb.auth.currentUser?.id ?? '');

  /// Дүкеннің барлық пікірлері (жаңасы бірінші, realtime).
  Stream<List<ReviewModel>> watchStoreReviews() => _sb
      .from('product_reviews')
      .stream(primaryKey: ['id'])
      .eq('admin_uid', _ownerUid)
      .order('created_at', ascending: false)
      .map((rows) => rows.map(ReviewModel.fromMap).toList());

  /// Тауар id → (атауы, бірінші фото) — пікір карточкасында көрсету үшін.
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

  /// Пікірге жауап жазу/өзгерту; бос мәтін — жауапты өшіру.
  /// SECURITY DEFINER RPC — тек өз дүкенінің пікіріне рұқсат.
  Future<void> reply(String reviewId, String replyText) =>
      _sb.rpc('reply_to_review',
          params: {'p_review': reviewId, 'p_reply': replyText});
}
