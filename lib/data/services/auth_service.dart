import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user_model.dart';
import '../../core/app_user.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  User? get currentUser => _auth.currentUser;
  String? get currentUid => _auth.currentUser?.uid;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Тіркелу.
  /// Admin: businessCode автоматты жасалады. Қойма AdminOnboarding арқылы қосылады.
  /// Seller: joinStatus='none', ownerUid='', тікелей тіркеледі.
  Future<UserCredential> register({
    required String name,
    required String email,
    required String password,
    required String role,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    await credential.user?.updateDisplayName(name.trim());
    final uid = credential.user!.uid;

    try {
      if (role == 'admin') {
        final code = _generateBusinessCode();

        await _db.collection('users').doc(uid).set({
          'uid':                 uid,
          'name':                name.trim(),
          'email':               email.trim(),
          'role':                'admin',
          'ownerId':             uid,
          'active':              true,
          'created_at':          FieldValue.serverTimestamp(),
          'businessCode':        code,
          'assignedWarehouseId': '',
          'joinStatus':          'active',
        });

      } else {
        // Seller: еш тексеріссіз тіркеледі, joinStatus = 'none'
        await _db.collection('users').doc(uid).set({
          'uid':                 uid,
          'name':                name.trim(),
          'email':               email.trim(),
          'role':                'seller',
          'ownerId':             '',
          'active':              true,
          'created_at':          FieldValue.serverTimestamp(),
          'businessCode':        '',
          'assignedWarehouseId': '',
          'joinStatus':          'none',
        });
      }
    } catch (_) {
      await credential.user?.delete();
      rethrow;
    }

    return credential;
  }

  /// Кіру
  Future<UserCredential> signIn({
    required String email,
    required String password,
  }) async => _auth.signInWithEmailAndPassword(
      email: email.trim(), password: password);

  /// users/{uid} — толық UserModel қайтарады
  Future<UserModel?> getUserDoc(String uid) async {
    try {
      final doc = await _db.collection('users').doc(uid).get();
      if (!doc.exists) return null;
      return UserModel.fromFirestore(doc);
    } catch (_) {
      return null;
    }
  }

  /// Шығу
  Future<void> signOut() async {
    AppUser.clear();
    await _auth.signOut();
  }

  static String _generateBusinessCode() {
    final r = Random();
    return List.generate(6, (_) => r.nextInt(10)).join();
  }

  static String parseError(FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':    return 'Бұл email тіркелген.';
      case 'invalid-email':           return 'Email форматы дұрыс емес.';
      case 'weak-password':           return 'Пароль тым қарапайым (мин. 6 таңба).';
      case 'user-not-found':          return 'Пайдаланушы табылмады.';
      case 'wrong-password':          return 'Пароль қате.';
      case 'invalid-credential':      return 'Email немесе пароль қате.';
      case 'too-many-requests':       return 'Тым көп әрекет. Кейінірек қайта көріңіз.';
      case 'network-request-failed':  return 'Желі қатесі. Интернетті тексеріңіз.';
      default: return 'Қате: ${e.message ?? e.code}';
    }
  }
}
