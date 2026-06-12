import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/banner_model.dart';

/// `banners` root-коллекциясымен жұмыс істейтін қабат.
/// Клиент белсенді баршаны оқиды; superadmin қосады/өзгертеді/жояды.
///
/// Сұрыптау/фильтрация КЛИЕНТ жағында жасалады — бұл (where active + orderBy
/// order) композиттік индексін болдырмайды (жоба конвенциясы).
class BannerRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('banners');

  /// Клиент: белсенді әрі уақыт терезесіндегі баннерлер, order бойынша.
  Stream<List<BannerModel>> watchActiveBanners() {
    return _col.snapshots().map((s) {
      final now = DateTime.now();
      final list = s.docs
          .map(BannerModel.fromFirestore)
          .where((b) => b.isVisibleAt(now))
          .toList()
        ..sort((a, b) => a.order.compareTo(b.order));
      return list;
    });
  }

  /// Superadmin: барлық баннерлер, order бойынша.
  Stream<List<BannerModel>> watchAllBanners() {
    return _col.snapshots().map((s) => s.docs
        .map(BannerModel.fromFirestore)
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order)));
  }

  /// Жаңа баннер жасайды (id бос) немесе барын жаңартады.
  Future<void> saveBanner(BannerModel banner) async {
    if (banner.id.isEmpty) {
      await _col.add(banner.toMap());
    } else {
      await _col.doc(banner.id).set(banner.toMap(), SetOptions(merge: true));
    }
  }

  /// Тек active жалаушасын ауыстыру (тізімдегі Switch үшін).
  Future<void> setActive(String id, bool active) =>
      _col.doc(id).update({'active': active});

  Future<void> deleteBanner(String id) => _col.doc(id).delete();
}
