// lib/migration.dart
// БІР РЕТ іске қосылатын скрипт.
// Орындау: ProfileScreen-дегі «Миграция» батырмасынан шақырыңыз,
// аяқталғаннан кейін батырманы өшіріп тастаңыз.
//
// Не жасайды:
//  1. Барлық admin-дерге businessCode жазады (жоқ болса)
//  2. Барлық admin-дерге негізгі қойма жасайды (жоқ болса)
//  3. Бар батчтарға (shops→users) warehouseId = mainWarehouseId жазады
//  4. shops/{uid}/... → users/{uid}/... деректерді ЖЫЛЖЫТАДЫ (migration v2)

import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

Future<void> runMigration({
  void Function(String)? onLog,
}) async {
  final db = FirebaseFirestore.instance;
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) {
    onLog?.call('Авторизацияланбаған — миграция тоқтатылды.');
    return;
  }

  onLog?.call('Миграция басталды...');

  // ── 1. businessCode ─────────────────────────────────────────────────────────
  final userDoc = await db.collection('users').doc(uid).get();
  final userData = userDoc.data() ?? {};

  if ((userData['businessCode'] as String? ?? '').isEmpty) {
    final code = List.generate(6, (_) => Random().nextInt(10)).join();
    await db.collection('users').doc(uid).update({'businessCode': code});
    onLog?.call('businessCode жазылды: $code');
  } else {
    onLog?.call('businessCode бар: ${userData['businessCode']}');
  }

  // ── 2. Негізгі қойма ────────────────────────────────────────────────────────
  final whSnap = await db
      .collection('users')
      .doc(uid)
      .collection('warehouses')
      .limit(1)
      .get();

  String mainWarehouseId;
  if (whSnap.docs.isEmpty) {
    final ref = db.collection('users').doc(uid).collection('warehouses').doc();
    await ref.set({
      'id': ref.id,
      'name': 'Негізгі қойма',
      'isMain': true,
      'createdAt': FieldValue.serverTimestamp(),
    });
    mainWarehouseId = ref.id;
    onLog?.call('Негізгі қойма жасалды: $mainWarehouseId');
  } else {
    mainWarehouseId = whSnap.docs.first.id;
    onLog?.call('Негізгі қойма бар: $mainWarehouseId');
  }

  // ── 3. shops/{uid}/products → users/{uid}/products ─────────────────────────
  final oldProducts =
      await db.collection('shops').doc(uid).collection('products').get();

  if (oldProducts.docs.isEmpty) {
    onLog?.call('shops/ деректері жоқ — жылжыту қажет емес.');
  } else {
    onLog?.call('${oldProducts.docs.length} тауар жылжытылады...');
    for (final pDoc in oldProducts.docs) {
      final newPRef =
          db.collection('users').doc(uid).collection('products').doc(pDoc.id);

      // Тауар деректерін жазамыз
      await newPRef.set(pDoc.data());

      // Батчтарды жылжытамыз
      final batchSnap = await db
          .collection('shops')
          .doc(uid)
          .collection('products')
          .doc(pDoc.id)
          .collection('batches')
          .get();

      for (final bDoc in batchSnap.docs) {
        final bData = {...bDoc.data()};
        if ((bData['warehouseId'] as String? ?? '').isEmpty) {
          bData['warehouseId'] = mainWarehouseId;
        }
        await newPRef.collection('batches').doc(bDoc.id).set(bData);
      }
    }
    onLog?.call('Тауарлар жылжытылды.');
  }

  // ── 4. shops/{uid}/sales_history → users/{uid}/sales_history ───────────────
  final oldSales =
      await db.collection('shops').doc(uid).collection('sales_history').get();

  if (oldSales.docs.isNotEmpty) {
    onLog?.call('${oldSales.docs.length} сату жылжытылады...');
    for (final sDoc in oldSales.docs) {
      final sData = {...sDoc.data()};
      if ((sData['warehouseId'] as String? ?? '').isEmpty) {
        sData['warehouseId'] = mainWarehouseId;
      }
      await db
          .collection('users')
          .doc(uid)
          .collection('sales_history')
          .doc(sDoc.id)
          .set(sData);
    }
    onLog?.call('Сатулар жылжытылды.');
  }

  // ── 5. joinStatus жоқ user-дарды жаңарту ────────────────────────────────────
  await db.collection('users').doc(uid).update({
    'joinStatus': 'active',
    'ownerId': uid,
  });

  onLog?.call('✅ Миграция аяқталды!');
}
