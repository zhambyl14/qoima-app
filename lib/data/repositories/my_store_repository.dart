import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/store_discount_model.dart';

/// «Менің дүкенім» скидка-кампанияларының тізімі (Supabase `store_discounts`).
class MyStoreRepository {
  final SupabaseClient _sb = Supabase.instance.client;
  String get _uid => _sb.auth.currentUser?.id ?? '';

  Stream<List<StoreDiscountModel>> watchDiscounts() => _sb
      .from('store_discounts')
      .stream(primaryKey: ['id'])
      .eq('store_id', _uid)
      .order('created_at', ascending: false)
      .map((rows) => rows.map(StoreDiscountModel.fromMap).toList());

  Future<void> addDiscount(StoreDiscountModel d) =>
      _sb.from('store_discounts').insert({...d.toMap(), 'store_id': _uid});

  Future<void> toggleDiscount(String id, bool isActive) =>
      _sb.from('store_discounts').update({'is_active': isActive}).eq('id', id);

  Future<void> deleteDiscount(String id) =>
      _sb.from('store_discounts').delete().eq('id', id);

  Future<void> removeProductFromDiscount(
      String discountId, String productId) async {
    final row = await _sb
        .from('store_discounts')
        .select('target_product_ids')
        .eq('id', discountId)
        .maybeSingle();
    final ids = ((row?['target_product_ids'] as List?) ?? [])
        .map((e) => e.toString())
        .toList()
      ..remove(productId);
    await _sb
        .from('store_discounts')
        .update({'target_product_ids': ids}).eq('id', discountId);
  }

  Future<void> addProductToDiscount(String discountId, String productId) async {
    final row = await _sb
        .from('store_discounts')
        .select('target_product_ids')
        .eq('id', discountId)
        .maybeSingle();
    final ids = ((row?['target_product_ids'] as List?) ?? [])
        .map((e) => e.toString())
        .toList();
    if (!ids.contains(productId)) ids.add(productId);
    await _sb
        .from('store_discounts')
        .update({'target_product_ids': ids}).eq('id', discountId);
  }
}
