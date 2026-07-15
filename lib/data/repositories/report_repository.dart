import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/report_model.dart';

/// Superadmin — контент шағымдарын қарау/өңдеу (content_reports).
class ReportRepository {
  final SupabaseClient _sb = Supabase.instance.client;

  /// Барлық шағымдар (жаңасы бірінші, realtime).
  Stream<List<ReportModel>> watchReports() => _sb
      .from('content_reports')
      .stream(primaryKey: ['id'])
      .order('created_at', ascending: false)
      .map((rows) => rows.map(ReportModel.fromMap).toList());

  /// Шағымды жабу: [status] = 'resolved' | 'dismissed'.
  Future<void> resolve({
    required String reportId,
    required String status,
    required String resolvedBy,
    String note = '',
  }) =>
      _sb.from('content_reports').update({
        'status': status,
        'resolved_by': resolvedBy,
        'resolution_note': note,
        'resolved_at': DateTime.now().toIso8601String(),
      }).eq('id', reportId);

  /// Пікірді модерациялап өшіру (RLS: superadmin delete рұқсат етілген;
  /// products.rating триггер арқылы автоматты қайта есептеледі).
  Future<void> deleteReview(String reviewId) =>
      _sb.from('product_reviews').delete().eq('id', reviewId);
}
