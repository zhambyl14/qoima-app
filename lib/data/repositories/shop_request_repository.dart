import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/shop_request_model.dart';
import '../models/store_model.dart';

/// `shop_requests` кестесімен жұмыс істейтін қабат (Supabase).
/// Owner заявка жібереді/бақылайды; superadmin бекітеді/бас тартады.
class ShopRequestRepository {
  final SupabaseClient _sb = Supabase.instance.client;

  // ── Owner ──────────────────────────────────────────────────────────────────

  Future<String> submitRequest(ShopRequestModel req) async {
    final row =
        await _sb.from('shop_requests').insert(req.toMap()).select('id').single();
    return row['id'] as String;
  }

  Stream<ShopRequestModel?> watchMyRequest(String ownerUid) => _sb
      .from('shop_requests')
      .stream(primaryKey: ['id'])
      .eq('owner_uid', ownerUid)
      .order('created_at', ascending: false)
      .map((rows) =>
          rows.isEmpty ? null : ShopRequestModel.fromMap(rows.first));

  /// Бекітілген заявка бойынша дүкенді owner ӨЗІ provision етеді
  /// (stores upsert + users.shop_status='approved').
  Future<void> provisionApprovedShop(ShopRequestModel req) async {
    final now = DateTime.now();
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
      paymentCardNumber: req.cardNumber,
      paymentCardHolder: req.cardHolder,
      paymentBank: req.cardBank,
      kaspiLink: req.kaspiLink,
      bankQrs: req.bankQrs,
      ownerName: req.ownerName,
      ownerIin: req.ownerIin,
      category: req.category,
      status: 'active',
    );
    await _sb.from('stores').upsert({...store.toMap(), 'admin_uid': req.ownerUid});
    await _sb.from('users').update({
      'shop_status': 'approved',
      'shop_request_id': req.id,
    }).eq('id', req.ownerUid);
  }

  // ── Superadmin ───────────────────────────────────────────────────────────────

  Stream<List<ShopRequestModel>> watchPendingRequests() => _sb
      .from('shop_requests')
      .stream(primaryKey: ['id'])
      .eq('status', 'pending')
      .order('created_at', ascending: false)
      .map((rows) => rows.map(ShopRequestModel.fromMap).toList());

  Stream<List<ShopRequestModel>> watchAllRequests() => _sb
      .from('shop_requests')
      .stream(primaryKey: ['id'])
      .order('created_at', ascending: false)
      .map((rows) => rows.map(ShopRequestModel.fromMap).toList());

  Future<void> approveRequest({
    required String requestId,
    required String reviewedBy,
  }) =>
      _sb.from('shop_requests').update({
        'status': 'approved',
        'reviewed_at': DateTime.now().toIso8601String(),
        'reviewed_by': reviewedBy,
        'review_note': '',
      }).eq('id', requestId);

  Future<void> rejectRequest({
    required String requestId,
    required String reviewedBy,
    required String reviewNote,
  }) =>
      _sb.from('shop_requests').update({
        'status': 'rejected',
        'reviewed_at': DateTime.now().toIso8601String(),
        'reviewed_by': reviewedBy,
        'review_note': reviewNote,
      }).eq('id', requestId);
}
