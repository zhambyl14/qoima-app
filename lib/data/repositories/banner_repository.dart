import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/banner_model.dart';

/// `banners` кестесімен жұмыс істейтін қабат (Supabase).
/// Клиент белсенділерін оқиды; superadmin қосады/өзгертеді/жояды.
class BannerRepository {
  final SupabaseClient _sb = Supabase.instance.client;

  Stream<List<BannerModel>> watchActiveBanners() =>
      _sb.from('banners').stream(primaryKey: ['id']).map((rows) {
        final now = DateTime.now();
        final list = rows
            .map(BannerModel.fromMap)
            .where((b) => b.isVisibleAt(now))
            .toList()
          ..sort((a, b) => a.order.compareTo(b.order));
        return list;
      });

  Stream<List<BannerModel>> watchAllBanners() =>
      _sb.from('banners').stream(primaryKey: ['id']).map((rows) =>
          rows.map(BannerModel.fromMap).toList()
            ..sort((a, b) => a.order.compareTo(b.order)));

  Future<void> saveBanner(BannerModel banner) async {
    if (banner.id.isEmpty) {
      await _sb.from('banners').insert(banner.toRow());
    } else {
      await _sb.from('banners').update(banner.toRow()).eq('id', banner.id);
    }
  }

  Future<void> setActive(String id, bool active) =>
      _sb.from('banners').update({'active': active}).eq('id', id);

  Future<void> deleteBanner(String id) =>
      _sb.from('banners').delete().eq('id', id);
}
