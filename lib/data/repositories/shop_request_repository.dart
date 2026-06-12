import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/shop_request_model.dart';
import '../models/store_model.dart';

/// `shopRequests` collection-імен жұмыс істейтін қабат.
/// Owner заявка жібереді/бақылайды; superadmin бекітеді/бас тартады.
class ShopRequestRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('shopRequests');

  // ── Owner ──────────────────────────────────────────────────────────────────

  /// Owner заявка жібереді. Жасалған құжаттың ID-сін қайтарады.
  Future<String> submitRequest(ShopRequestModel req) async {
    final doc = await _col.add(req.toJson());
    return doc.id;
  }

  /// Owner өз заявкасының ең соңғысын бақылайды.
  /// (where + orderBy композиттік индексін талап етпеу үшін сұрыптау клиент жағында.)
  Stream<ShopRequestModel?> watchMyRequest(String ownerUid) {
    return _col.where('ownerUid', isEqualTo: ownerUid).snapshots().map((s) {
      if (s.docs.isEmpty) return null;
      final list = s.docs.map(ShopRequestModel.fromFirestore).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list.first;
    });
  }

  /// Бекітілген заявка бойынша дүкенді owner ӨЗІ provision етеді
  /// (users/{uid}/store/{uid} + users/{uid}.shopStatus='approved').
  /// Құжат ID = ownerUid — FirestoreService (_storeDoc, watchStore/getStore/
  /// saveStore) дәл осы құжатпен жұмыс істейді.
  /// Бұл owner-дің өз құжаттарына жазу болғандықтан, қосымша ережелер қажет емес.
  Future<void> provisionApprovedShop(ShopRequestModel req) async {
    final now = DateTime.now();
    final batch = _db.batch();

    final storeRef = _db
        .collection('users')
        .doc(req.ownerUid)
        .collection('store')
        .doc(req.ownerUid);
    final store = StoreModel(
      adminUid: req.ownerUid,
      storeName: req.shopName,
      storeSlug: StoreModel.generateSlug(req.shopName),
      logoUrl: '',
      city: req.city,
      phone: req.ownerPhone,
      description: req.description,
      visibleWarehouseIds: const [],
      isPublished: true,
      createdAt: now,
      updatedAt: now,
      // v10 — заявкадан иесі мен қаржы деректерін көшіреміз.
      paymentCardNumber: req.cardNumber,
      paymentCardHolder: req.cardHolder,
      paymentBank: req.cardBank,
      ownerName: req.ownerName,
      ownerIin: req.ownerIin,
      category: req.category,
      status: 'active',
    );
    batch.set(storeRef, store.toJson(), SetOptions(merge: true));

    final userRef = _db.collection('users').doc(req.ownerUid);
    batch.set(userRef, {
      'shopStatus': 'approved',
      'shopRequestId': req.id,
      'shopName': req.shopName,
    }, SetOptions(merge: true));

    await batch.commit();
  }

  // ── Superadmin ───────────────────────────────────────────────────────────────

  /// Барлық pending заявкалар (badge/тізім үшін).
  Stream<List<ShopRequestModel>> watchPendingRequests() {
    return _col.where('status', isEqualTo: 'pending').snapshots().map((s) {
      final list = s.docs.map(ShopRequestModel.fromFirestore).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });
  }

  /// Барлық заявкалар (фильтр үшін, жаңасы жоғарыда).
  Stream<List<ShopRequestModel>> watchAllRequests() {
    return _col
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(ShopRequestModel.fromFirestore).toList());
  }

  /// Superadmin — бекіту.
  Future<void> approveRequest({
    required String requestId,
    required String reviewedBy,
  }) async {
    await _col.doc(requestId).update({
      'status': 'approved',
      'reviewedAt': Timestamp.now(),
      'reviewedBy': reviewedBy,
      'reviewNote': '',
    });
  }

  /// Superadmin — бас тарту (себебімен).
  Future<void> rejectRequest({
    required String requestId,
    required String reviewedBy,
    required String reviewNote,
  }) async {
    await _col.doc(requestId).update({
      'status': 'rejected',
      'reviewedAt': Timestamp.now(),
      'reviewedBy': reviewedBy,
      'reviewNote': reviewNote,
    });
  }
}
