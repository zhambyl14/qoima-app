import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/store_edit_request_model.dart';
import '../models/store_model.dart';

/// `storeEditRequests` collection-імен жұмыс істейтін қабат (v10).
/// Owner дүкен мәліметтерін өзгерту запросын жібереді/бақылайды;
/// superadmin қабылдайды/қайтарады. Approve кезінде өзгерістер
/// `users/{ownerUid}/store/{ownerUid}` құжатына batch-пен қолданылады.
class StoreEditRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('storeEditRequests');

  DocumentReference<Map<String, dynamic>> _storeRef(String ownerUid) =>
      _db.collection('users').doc(ownerUid).collection('store').doc(ownerUid);

  // ── Owner ──────────────────────────────────────────────────────────────────

  /// Owner — өзгерту запросын жіберу. Жасалған құжаттың ID-сін қайтарады.
  Future<String> submitEdit(StoreEditRequestModel req) async {
    final doc = await _col.add(req.toJson());
    return doc.id;
  }

  /// Owner — өзінің ағымдағы pending запросын бақылау (болса).
  /// Композиттік индекс талап етпеу үшін status сүзу/сұрыптау клиент жағында.
  Stream<StoreEditRequestModel?> watchMyPending(String ownerUid) {
    return _col.where('ownerUid', isEqualTo: ownerUid).snapshots().map((s) {
      final pending = s.docs
          .map(StoreEditRequestModel.fromFirestore)
          .where((r) => r.isPending)
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return pending.isEmpty ? null : pending.first;
    });
  }

  /// Owner — өзінің ЕҢ СОҢҒЫ запросын (кез келген статус) бақылау. Pending күту
  /// экраны статус өзгерісіне (approved/rejected) реакция жасау үшін қолданады.
  Stream<StoreEditRequestModel?> watchMyLatest(String ownerUid) {
    return _col.where('ownerUid', isEqualTo: ownerUid).snapshots().map((s) {
      if (s.docs.isEmpty) return null;
      final list = s.docs.map(StoreEditRequestModel.fromFirestore).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list.first;
    });
  }

  /// Owner — запросты қайтарып алу (cancel).
  Future<void> cancelEdit(String editId) =>
      _col.doc(editId).update({'status': 'cancelled'});

  // ── Superadmin ───────────────────────────────────────────────────────────────

  /// Superadmin — барлық pending өзгерту запростары (жаңасы жоғарыда).
  Stream<List<StoreEditRequestModel>> watchPending() {
    return _col.where('status', isEqualTo: 'pending').snapshots().map((s) {
      final list = s.docs.map(StoreEditRequestModel.fromFirestore).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });
  }

  /// Superadmin — барлық запростар (фильтр үшін, жаңасы жоғарыда).
  Stream<List<StoreEditRequestModel>> watchAll() {
    return _col
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(StoreEditRequestModel.fromFirestore).toList());
  }

  /// Superadmin — ҚАБЫЛДАУ: store құжатына өзгерістерді қолданып, статусты жаңарт.
  Future<void> approveEdit({
    required StoreEditRequestModel req,
    required String reviewedBy,
  }) async {
    final batch = _db.batch();

    // 1) store құжатына барлық өзгертілген өрістерді қолдану (field = store кілті).
    final Map<String, dynamic> patch = {'updatedAt': Timestamp.now()};
    for (final c in req.changes) {
      patch[c.field] = c.newValue;
      // Дүкен аты өзгерсе — slug-ты да жаңартамыз (каталог сілтемесі үшін).
      if (c.field == 'storeName') {
        patch['storeSlug'] = StoreModel.generateSlug(c.newValue);
      }
    }
    batch.set(_storeRef(req.ownerUid), patch, SetOptions(merge: true));

    // 2) запрос статусын жаңарту.
    batch.update(_col.doc(req.id), {
      'status': 'approved',
      'reviewedAt': Timestamp.now(),
      'reviewedBy': reviewedBy,
      'reviewNote': '',
    });

    await batch.commit();
  }

  /// Superadmin — ҚАЙТАРУ (себеппен).
  Future<void> rejectEdit({
    required String editId,
    required String reviewedBy,
    required String reviewNote,
  }) async {
    await _col.doc(editId).update({
      'status': 'rejected',
      'reviewedAt': Timestamp.now(),
      'reviewedBy': reviewedBy,
      'reviewNote': reviewNote,
    });
  }
}
