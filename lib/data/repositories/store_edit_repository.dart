import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/store_edit_request_model.dart';
import '../models/store_model.dart';

/// `store_edit_requests` кестесімен жұмыс істейтін қабат (Supabase, v10).
/// Approve кезінде өзгерістер `stores` кестесіне қолданылады.
class StoreEditRepository {
  final SupabaseClient _sb = Supabase.instance.client;

  /// EditField.field (ескі store құжатының camelCase кілттері) → stores бағаны.
  static const _fieldToColumn = {
    'storeName': 'store_name',
    'city': 'city',
    'description': 'description',
    'ownerName': 'owner_name',
    'ownerIin': 'owner_iin',
    'phone': 'phone',
    'paymentCardNumber': 'payment_card_number',
    'kaspiLink': 'kaspi_link',
  };

  // ── Owner ──────────────────────────────────────────────────────────────────

  Future<String> submitEdit(StoreEditRequestModel req) async {
    final row = await _sb
        .from('store_edit_requests')
        .insert(req.toMap())
        .select('id')
        .single();
    return row['id'] as String;
  }

  Stream<StoreEditRequestModel?> watchMyPending(String ownerUid) => _sb
      .from('store_edit_requests')
      .stream(primaryKey: ['id'])
      .eq('owner_uid', ownerUid)
      .order('created_at', ascending: false)
      .map((rows) {
        final pending = rows
            .map(StoreEditRequestModel.fromMap)
            .where((r) => r.isPending)
            .toList();
        return pending.isEmpty ? null : pending.first;
      });

  Stream<StoreEditRequestModel?> watchMyLatest(String ownerUid) => _sb
      .from('store_edit_requests')
      .stream(primaryKey: ['id'])
      .eq('owner_uid', ownerUid)
      .order('created_at', ascending: false)
      .map((rows) =>
          rows.isEmpty ? null : StoreEditRequestModel.fromMap(rows.first));

  Future<void> cancelEdit(String editId) => _sb
      .from('store_edit_requests')
      .update({'status': 'cancelled'}).eq('id', editId);

  // ── Superadmin ───────────────────────────────────────────────────────────────

  Stream<List<StoreEditRequestModel>> watchPending() => _sb
      .from('store_edit_requests')
      .stream(primaryKey: ['id'])
      .eq('status', 'pending')
      .order('created_at', ascending: false)
      .map((rows) => rows.map(StoreEditRequestModel.fromMap).toList());

  Stream<List<StoreEditRequestModel>> watchAll() => _sb
      .from('store_edit_requests')
      .stream(primaryKey: ['id'])
      .order('created_at', ascending: false)
      .map((rows) => rows.map(StoreEditRequestModel.fromMap).toList());

  /// Superadmin — ҚАБЫЛДАУ: store кестесіне өзгерістерді қолданып, статусты жаңарт.
  Future<void> approveEdit({
    required StoreEditRequestModel req,
    required String reviewedBy,
  }) async {
    final patch = <String, dynamic>{
      'updated_at': DateTime.now().toIso8601String()
    };
    for (final c in req.changes) {
      final col = _fieldToColumn[c.field] ?? c.field;
      patch[col] = c.newValue;
      if (c.field == 'storeName') {
        patch['store_slug'] = StoreModel.generateSlug(c.newValue);
      }
    }
    await _sb.from('stores').update(patch).eq('admin_uid', req.ownerUid);
    await _sb.from('store_edit_requests').update({
      'status': 'approved',
      'reviewed_at': DateTime.now().toIso8601String(),
      'reviewed_by': reviewedBy,
      'review_note': '',
    }).eq('id', req.id);
  }

  Future<void> rejectEdit({
    required String editId,
    required String reviewedBy,
    required String reviewNote,
  }) =>
      _sb.from('store_edit_requests').update({
        'status': 'rejected',
        'reviewed_at': DateTime.now().toIso8601String(),
        'reviewed_by': reviewedBy,
        'review_note': reviewNote,
      }).eq('id', editId);
}
