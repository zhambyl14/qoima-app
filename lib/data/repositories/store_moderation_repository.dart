import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/product_model.dart';
import '../models/store_model.dart';
import '../models/user_model.dart';

/// Superadmin дүкендерді басқарады/блоктайды (Supabase `stores` + `users`).
class StoreModerationRepository {
  final SupabaseClient _sb = Supabase.instance.client;

  /// Барлық маркетплейс дүкендері (superadmin RLS барлығын көреді).
  Stream<List<StoreModel>> watchAllShops() =>
      _sb.from('stores').stream(primaryKey: ['admin_uid']).map((rows) {
        final list = rows.map(StoreModel.fromMap).toList()
          ..sort((a, b) =>
              a.storeName.toLowerCase().compareTo(b.storeName.toLowerCase()));
        return list;
      });

  // ── Онлайн блок: дүкен маркетплейстен жасырылады (иесі жұмысын жалғастырады) ─

  Future<void> blockStore({
    required String ownerUid,
    required String reason,
    required String blockedBy,
  }) =>
      _sb.from('stores').update({
        'status': 'blocked',
        'block_reason': reason,
        'blocked_at': DateTime.now().toIso8601String(),
        'blocked_by': blockedBy,
      }).eq('admin_uid', ownerUid);

  Future<void> unblockStore(String ownerUid) => _sb.from('stores').update({
        'status': 'active',
        'block_reason': '',
        'blocked_at': null,
        'blocked_by': '',
      }).eq('admin_uid', ownerUid);

  // ── Жалпы блок: иесі (және сатушылары каскадпен) ешқандай әрекет жасай ──────
  //   алмайды + онлайн дүкені де жасырылады.

  /// Барлық дүкен иелері (role='admin'; superadmin RLS барлығын көреді).
  Stream<List<UserModel>> watchOwners() =>
      _sb.from('users').stream(primaryKey: ['id']).eq('role', 'admin').map(
        (rows) {
          final list = rows.map(UserModel.fromMap).toList()
            ..sort((a, b) =>
                a.name.toLowerCase().compareTo(b.name.toLowerCase()));
          return list;
        },
      );

  Future<void> blockOwner({
    required String ownerUid,
    required String reason,
    required String blockedBy,
  }) async {
    await _sb.from('users').update({
      'blocked': true,
      'block_reason': reason,
      'blocked_at': DateTime.now().toIso8601String(),
      'blocked_by': blockedBy,
    }).eq('id', ownerUid);
    // Онлайн дүкенін де жасырамыз (stores жолы жоқ болса — 0 жол, қауіпсіз).
    await blockStore(ownerUid: ownerUid, reason: reason, blockedBy: blockedBy);
  }

  Future<void> unblockOwner(String ownerUid) async {
    await _sb.from('users').update({
      'blocked': false,
      'block_reason': '',
      'blocked_at': null,
      'blocked_by': '',
    }).eq('id', ownerUid);
    await unblockStore(ownerUid);
  }

  // ── Жазылым (подписка) — төлем аппликациядан тыс, база тек мерзімді сақтайды ──

  /// Жазылымды [months] айға ұзарту. Әлі белсенді болса — мерзім соңынан
  /// жалғасады (жинақталады); өтіп кеткен/жоқ болса — бүгіннен басталады.
  Future<void> grantSubscription({
    required String ownerUid,
    required int months,
    DateTime? currentUntil,
  }) async {
    final now = DateTime.now();
    final base = (currentUntil != null && currentUntil.isAfter(now))
        ? currentUntil
        : now;
    // Ай қосу (күн тасымалын DateTime өзі реттейді).
    final until = DateTime(base.year, base.month + months, base.day,
        base.hour, base.minute, base.second);
    await _sb.from('users').update({
      'subscription_until': until.toIso8601String(),
      if (currentUntil == null || !currentUntil.isAfter(now))
        'subscription_started_at': now.toIso8601String(),
      'subscription_plan': '$months ай',
    }).eq('id', ownerUid);
  }

  /// Нақты күнді қолмен қою (модератор күнтізбеден таңдайды).
  Future<void> setSubscriptionUntil({
    required String ownerUid,
    required DateTime until,
    String note = '',
  }) =>
      _sb.from('users').update({
        'subscription_until': until.toIso8601String(),
        'subscription_started_at': DateTime.now().toIso8601String(),
        'subscription_note': note,
      }).eq('id', ownerUid);

  /// Жазылымды тазалау (мерзім берілмеген күйге қайтару).
  Future<void> clearSubscription(String ownerUid) => _sb.from('users').update({
        'subscription_until': null,
        'subscription_started_at': null,
        'subscription_plan': '',
        'subscription_note': '',
      }).eq('id', ownerUid);

  // ── Дүкен товарлары (модератор заңсыз тауарды тексереді) ─────────────────────

  /// Иенің барлық товарлары (products.select саясаты — барлығына оқуға ашық).
  Stream<List<ProductModel>> watchOwnerProducts(String ownerUid) => _sb
      .from('products')
      .stream(primaryKey: ['id'])
      .eq('owner_uid', ownerUid)
      .order('created_at')
      .map((rows) => rows.map(ProductModel.fromMap).toList());
}
