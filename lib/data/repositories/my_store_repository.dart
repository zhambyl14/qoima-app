import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/store_discount_model.dart';

/// «Менің дүкенім» скидка-кампанияларының тізімі.
/// Нақты баға өзгерісі batch-тарда (`DiscountModel`) сақталады — мұндағы құжаттар
/// тек кампания тізімін көрсету/басқару үшін (targetProductIds арқылы байланады).
class MyStoreRepository {
  final _db = FirebaseFirestore.instance;
  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  CollectionReference<Map<String, dynamic>> get _discounts =>
      _db.collection('users').doc(_uid).collection('discounts');

  Stream<List<StoreDiscountModel>> watchDiscounts() => _discounts
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((s) => s.docs.map(StoreDiscountModel.fromFirestore).toList());

  Future<void> addDiscount(StoreDiscountModel d) => _discounts.add(d.toJson());

  Future<void> toggleDiscount(String id, bool isActive) =>
      _discounts.doc(id).update({'isActive': isActive});

  Future<void> deleteDiscount(String id) => _discounts.doc(id).delete();

  Future<void> removeProductFromDiscount(String discountId, String productId) =>
      _discounts.doc(discountId).update({
        'targetProductIds': FieldValue.arrayRemove([productId]),
      });

  Future<void> addProductToDiscount(String discountId, String productId) =>
      _discounts.doc(discountId).update({
        'targetProductIds': FieldValue.arrayUnion([productId]),
      });
}
