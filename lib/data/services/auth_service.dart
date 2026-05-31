import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user_model.dart';
import '../models/client_model.dart';
import '../../core/app_user.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  User? get currentUser => _auth.currentUser;
  String? get currentUid => _auth.currentUser?.uid;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

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
        final batch = _db.batch();

        batch.set(_db.collection('users').doc(uid), {
          'uid': uid,
          'name': name.trim(),
          'email': email.trim(),
          'role': 'admin',
          'ownerId': uid,
          'active': true,
          'created_at': FieldValue.serverTimestamp(),
          'businessCode': code,
          'assignedWarehouseId': '',
          'joinStatus': 'active',
        });

        // business_codes коллекциясына да жаз — seller іздейтін жер осы
        batch.set(_db.collection('business_codes').doc(code), {
          'adminUid': uid,
          'createdAt': FieldValue.serverTimestamp(),
        });

        await batch.commit();
      } else {
        await _db.collection('users').doc(uid).set({
          'uid': uid,
          'name': name.trim(),
          'email': email.trim(),
          'role': 'seller',
          'ownerId': '',
          'active': true,
          'created_at': FieldValue.serverTimestamp(),
          'businessCode': '',
          'assignedWarehouseId': '',
          'joinStatus': 'none',
        });
      }
    } catch (_) {
      await credential.user?.delete();
      rethrow;
    }

    return credential;
  }

  Future<UserCredential> signIn({
    required String email,
    required String password,
  }) async =>
      _auth.signInWithEmailAndPassword(email: email.trim(), password: password);

  Future<UserModel?> getUserDoc(String uid) async {
    try {
      final doc = await _db.collection('users').doc(uid).get();
      if (!doc.exists) return null;
      return UserModel.fromFirestore(doc);
    } catch (_) {
      return null;
    }
  }

  // ── Phone OTP ──────────────────────────────────────────────────────────────

  Future<void> verifyPhone({
    required String phoneNumber,
    required void Function(String verificationId) onCodeSent,
    required void Function(String error) onError,
  }) async {
    await _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      verificationCompleted: (_) {},
      verificationFailed: (FirebaseAuthException e) =>
          onError(parsePhoneError(e)),
      codeSent: (String verificationId, int? _) => onCodeSent(verificationId),
      codeAutoRetrievalTimeout: (_) {},
    );
  }

  Future<UserCredential> signInWithOtp({
    required String verificationId,
    required String smsCode,
  }) async {
    final credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: smsCode,
    );
    return _auth.signInWithCredential(credential);
  }

  Future<void> createClientDoc({
    required String uid,
    required String phone,
    required String name,
    String city = '',
  }) async {
    await _db.collection('clients').doc(uid).set({
      'uid': uid,
      'phone': phone,
      'name': name,
      'city': city,
      'role': 'client',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateClientCity(String uid, String city) async {
    await _db.collection('clients').doc(uid).update({'city': city});
  }

  Future<ClientModel?> getClientDoc(String uid) async {
    try {
      final ref = _db.collection('clients').doc(uid);
      final doc = await ref.get();
      if (!doc.exists) return null;
      return ClientModel.fromFirestore(doc);
    } catch (_) {
      return null;
    }
  }

  // ── Sign out ───────────────────────────────────────────────────────────────

  Future<void> signOut() async {
    AppUser.current.clear();
    await _auth.signOut();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  static String _generateBusinessCode() {
    final r = Random();
    return List.generate(6, (_) => r.nextInt(10)).join();
  }

  static String parseError(FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':
        return 'Бұл email тіркелген.';
      case 'invalid-email':
        return 'Email форматы дұрыс емес.';
      case 'weak-password':
        return 'Пароль тым қарапайым (мин. 6 таңба).';
      case 'user-not-found':
        return 'Пайдаланушы табылмады.';
      case 'wrong-password':
        return 'Пароль қате.';
      case 'invalid-credential':
        return 'Email немесе пароль қате.';
      case 'too-many-requests':
        return 'Тым көп әрекет. Кейінірек қайта көріңіз.';
      case 'network-request-failed':
        return 'Желі қатесі. Интернетті тексеріңіз.';
      default:
        return 'Қате: ${e.message ?? e.code}';
    }
  }

  static String parsePhoneError(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-phone-number':
        return 'Телефон нөмері дұрыс емес.';
      case 'too-many-requests':
        return 'Тым көп әрекет. Кейінірек қайта көріңіз.';
      case 'invalid-verification-code':
        return 'Код дұрыс емес.';
      case 'session-expired':
        return 'Сессия мерзімі өтті. Қайталаңыз.';
      case 'network-request-failed':
        return 'Желі қатесі. Интернетті тексеріңіз.';
      case 'billing-not-enabled':
        return 'Firebase Blaze жоспарын қосыңыз.';
      case 'app-not-authorized':
        return 'Қолданба авторизацияланбаған. SHA fingerprint тексеріңіз.';
      case 'missing-client-identifier':
        return 'reCAPTCHA қатесі. Қайта жүктеңіз.';
      case 'quota-exceeded':
        return 'SMS лимиті асты. Кейінірек қайта көріңіз.';
      default:
        final msg = e.message ?? '';
        if (msg.toLowerCase().contains('region') ||
            msg.toLowerCase().contains('not enabled')) {
          return 'Бұл аймақ үшін SMS қосылмаған. '
              'Firebase Console → Auth → Settings → SMS region policy-де +7 регионын қос.';
        }
        return 'Қате: ${e.message ?? e.code}';
    }
  }
}
