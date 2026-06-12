import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/store_model.dart';

/// Superadmin (маркетплейс модераторы) дүкендерді басқарады/блоктайды (v10).
/// Дүкен құжаты — `users/{ownerUid}/store/{ownerUid}`. Блоктау/босату тек
/// superadmin рұқсатымен (firestore.rules-те store жазуға superadmin қосылған).
class StoreModerationRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _storeRef(String ownerUid) =>
      _db.collection('users').doc(ownerUid).collection('store').doc(ownerUid);

  /// Барлық маркетплейс дүкендері (collectionGroup — `.where` жоқ, индекс
  /// талап етпеу үшін; сүзу/сұрыптау клиент жағында — ClientService конвенциясы).
  Stream<List<StoreModel>> watchAllShops() {
    return _db.collectionGroup('store').snapshots().map((s) {
      final list = s.docs.map(StoreModel.fromFirestore).toList()
        ..sort((a, b) => a.storeName
            .toLowerCase()
            .compareTo(b.storeName.toLowerCase()));
      return list;
    });
  }

  /// Superadmin — дүкенді блоктау.
  Future<void> blockStore({
    required String ownerUid,
    required String reason,
    required String blockedBy,
  }) async {
    await _storeRef(ownerUid).set({
      'status': 'blocked',
      'blockReason': reason,
      'blockedAt': Timestamp.now(),
      'blockedBy': blockedBy,
    }, SetOptions(merge: true));
  }

  /// Superadmin — блоктан шығару.
  Future<void> unblockStore(String ownerUid) async {
    await _storeRef(ownerUid).set({
      'status': 'active',
      'blockReason': '',
      'blockedAt': null,
      'blockedBy': '',
    }, SetOptions(merge: true));
  }
}
