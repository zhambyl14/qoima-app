import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user_model.dart';
import '../models/client_model.dart';
import '../../core/app_user.dart';

/// Аутентификация қателерін UI-ге жеткізетін типтелген қате.
/// [code] — UI тармақтауы үшін ('email-not-verified' → «Қайта жіберу» батырмасы).
class AuthFailure implements Exception {
  final String message;
  final String code;
  AuthFailure(this.message, {this.code = ''});
  @override
  String toString() => message;
}

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  User? get currentUser => _auth.currentUser;
  String? get currentUid => _auth.currentUser?.uid;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // ── Firestore doc ID қауіпсіздігі үшін email кодтау ('.' → ',') ──────────────
  static String encodeEmail(String email) =>
      email.trim().toLowerCase().replaceAll('.', ',');

  // ═══════════════════════════════════════════════════════════════════════════
  //  CLIENT — телефон + email + құпиясөз (өзін-өзі тіркеу)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Жаңа клиентті тіркейді.
  ///
  /// Ескерту (спецификациядан ауытқу): телефон бірегейлігі `phoneIndex`-тен
  /// тексеріледі (ол кіру іздеуі үшін ашық оқылады), ал email бірегейлігін
  /// Firebase Auth-тың өзі қамтамасыз етеді (`email-already-in-use`). Сондықтан
  /// emailIndex-ке алдын ала оқу жасалмайды — оны оқу үшін кіру қажет болар еді.
  Future<void> registerClient({
    required String email,
    required String phoneNumber, // E.164: +7XXXXXXXXXX
    required String password,
    required String name,
    required String city,
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    final enc = encodeEmail(cleanEmail);

    // a) Телефон бос па
    final phoneIdx = await _db.collection('phoneIndex').doc(phoneNumber).get();
    if (phoneIdx.exists) {
      throw AuthFailure('Бұл телефон нөмір тіркелген', code: 'phone-in-use');
    }

    // c) Auth аккаунтын жасау (email бірегейлігін Auth қамтамасыз етеді)
    UserCredential cred;
    try {
      cred = await _auth.createUserWithEmailAndPassword(
          email: cleanEmail, password: password);
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(_msg(e), code: e.code);
    }
    final uid = cred.user!.uid;

    try {
      // e) Batch: клиент профилі + индекстер
      final batch = _db.batch();
      batch.set(_db.collection('clients').doc(uid), {
        'uid': uid,
        'email': cleanEmail,
        'phone': phoneNumber,
        'name': name.trim(),
        'city': city,
        'role': 'client',
        'emailVerified': true,
        'createdAt': FieldValue.serverTimestamp(),
      });
      batch.set(_db.collection('phoneIndex').doc(phoneNumber), {
        'uid': uid,
        'email': cleanEmail,
      });
      batch.set(_db.collection('emailIndex').doc(enc), {
        'uid': uid,
        'phoneNumber': phoneNumber,
      });
      await batch.commit();
    } catch (e) {
      // Жартылай жасалған аккаунтты қайтарып аламыз — email қайта босайды.
      try {
        await cred.user?.delete();
      } catch (_) {}
      // phoneIndex жазуы rules деңгейінде бұғатталса (нөмірді басқа біреу
      // дәл сол сәтте иемденіп үлгерсе) — түсінікті хабар.
      if (e is FirebaseException && e.code == 'permission-denied') {
        throw AuthFailure('Бұл телефон нөмір тіркелген', code: 'phone-in-use');
      }
      rethrow;
    }
    // Тіркелген соң auth gate автоматты ClientShell-ге ауысады.
  }

  /// Телефон + құпиясөзбен кіру: phoneIndex → email → Auth → emailVerified гейті.
  Future<void> loginWithPhonePassword({
    required String phoneNumber,
    required String password,
  }) async {
    // a) Телефон → email
    final idx = await _db.collection('phoneIndex').doc(phoneNumber).get();
    final email = idx.data()?['email'] as String? ?? '';
    if (!idx.exists || email.isEmpty) {
      throw AuthFailure('Аккаунт табылмады', code: 'user-not-found');
    }

    // b) Кіру
    try {
      await _auth.signInWithEmailAndPassword(email: email, password: password);
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(_msg(e), code: e.code);
    }

    // c) Сәтті — маршрутты реактивті gate (main.dart) шешеді
  }

  /// Телефон бойынша тіркелген email-ді қайтарады (phoneIndex ашық оқылады).
  /// «Поштаны растаңыз» жағдайында сілтемені қайта жіберу үшін қажет.
  Future<String?> emailForPhone(String phoneNumber) async {
    final idx = await _db.collection('phoneIndex').doc(phoneNumber).get();
    return idx.data()?['email'] as String?;
  }

  /// Құпиясөзді қалпына келтіру сілтемесін жібереді. Аккаунттың бар-жоғын
  /// ашпаймыз — UI әрқашан бейтарап хабар көрсетеді.
  Future<void> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (e) {
      // Тек форматты/желілік қатені көрсетеміз; user-not-found — жұтылады.
      if (e.code == 'invalid-email') {
        throw AuthFailure('Email форматы қате', code: e.code);
      }
      if (e.code == 'network-request-failed') {
        throw AuthFailure('Интернет байланысын тексеріңіз', code: e.code);
      }
    }
  }

  /// Растау сілтемесін қайта жібереді. Тіркелуден/кіруден кейін пайдаланушы
  /// шығарылып қойғандықтан, сілтемені жіберу үшін қайта кіреміз де, шығамыз.
  Future<void> resendVerification({
    required String email,
    required String password,
  }) async {
    try {
      final cred = await _auth.signInWithEmailAndPassword(
          email: email.trim().toLowerCase(), password: password);
      await cred.user?.sendEmailVerification();
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(_msg(e), code: e.code);
    } finally {
      await _auth.signOut();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  АККАУНТ ПАРАМЕТРЛЕРІ — жеке деректерді өзгерту (барлық рөлдер)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Телефон нөмірін өзгерту: reauth → бостығын тексеру → транзакция.
  Future<void> changePhoneNumber({
    required String currentPassword,
    required String newPhone, // E.164
  }) async {
    final user = _requireUser();
    await _reauth(user, currentPassword);

    // Жаңа нөмір басқа аккаунтта тіркелмегенін тексереміз
    final idx = await _db.collection('phoneIndex').doc(newPhone).get();
    if (idx.exists && idx.data()?['uid'] != user.uid) {
      throw AuthFailure('Бұл нөмір басқа аккаунтта тіркелген',
          code: 'phone-in-use');
    }

    final profile = await _profileRef(user.uid);
    final oldPhone = profile.phone;
    if (oldPhone == newPhone) return;

    await _db.runTransaction((tx) async {
      if (oldPhone.isNotEmpty) {
        tx.delete(_db.collection('phoneIndex').doc(oldPhone));
      }
      tx.set(_db.collection('phoneIndex').doc(newPhone), {
        'uid': user.uid,
        'email': user.email,
      });
      tx.update(profile.ref, {profile.phoneField: newPhone});
    });
  }

  /// Email өзгерту: reauth → бостығын тексеру → verifyBeforeUpdateEmail.
  /// Auth email тек пайдаланушы ЖАҢА поштадағы сілтемені басқан соң жаңарады,
  /// сосын [syncEmailIfChanged] индекстер мен профильді сәйкестендіреді.
  Future<void> changeEmail({
    required String currentPassword,
    required String newEmail,
  }) async {
    final user = _requireUser();
    await _reauth(user, currentPassword);

    final clean = newEmail.trim().toLowerCase();
    final enc = encodeEmail(clean);
    final idx = await _db.collection('emailIndex').doc(enc).get();
    if (idx.exists && idx.data()?['uid'] != user.uid) {
      throw AuthFailure('Бұл email тіркелген', code: 'email-already-in-use');
    }

    try {
      await user.verifyBeforeUpdateEmail(clean);
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(_msg(e), code: e.code);
    }
  }

  /// Құпиясөзді өзгерту: ағымдағымен reauth → updatePassword.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final user = _requireUser();
    await _reauth(user, currentPassword);
    try {
      await user.updatePassword(newPassword);
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(_msg(e), code: e.code);
    }
  }

  /// Әр қосылғанда (auth күйі шешілген соң) шақырылады: Auth email профильдегі
  /// email-ден өзгеше болса (verifyBeforeUpdateEmail сілтемесі басылған),
  /// emailIndex + phoneIndex + профиль құжатын сәйкестендіреді.
  Future<void> syncEmailIfChanged() async {
    final user = _auth.currentUser;
    if (user == null) return;
    await user.reload();
    final fresh = _auth.currentUser;
    final authEmail = fresh?.email?.toLowerCase();
    if (fresh == null || authEmail == null || authEmail.isEmpty) return;

    final profile = await _profileRef(user.uid);
    if (!profile.exists) return;
    final storedEmail = profile.email.toLowerCase();
    if (storedEmail == authEmail) return; // өзгермеген

    final phone = profile.phone;
    final oldEnc = encodeEmail(storedEmail);
    final newEnc = encodeEmail(authEmail);

    await _db.runTransaction((tx) async {
      if (storedEmail.isNotEmpty) {
        tx.delete(_db.collection('emailIndex').doc(oldEnc));
      }
      tx.set(_db.collection('emailIndex').doc(newEnc), {
        'uid': user.uid,
        'phoneNumber': phone,
      });
      tx.update(profile.ref, {'email': authEmail});
      // phoneIndex кіру кезінде email-ді осы жерден алады — оны да жаңартамыз.
      if (phone.isNotEmpty) {
        tx.set(_db.collection('phoneIndex').doc(phone), {
          'uid': user.uid,
          'email': authEmail,
        });
      }
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  SELLER / ADMIN — email + құпиясөз (Q2: бұл өткелде өзгеріссіз)
  // ═══════════════════════════════════════════════════════════════════════════

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

  // ═══════════════════════════════════════════════════════════════════════════
  //  Профиль оқу
  // ═══════════════════════════════════════════════════════════════════════════

  Future<UserModel?> getUserDoc(String uid) async {
    try {
      final doc = await _db.collection('users').doc(uid).get();
      if (!doc.exists) return null;
      return UserModel.fromFirestore(doc);
    } catch (_) {
      return null;
    }
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

  Future<void> updateClientCity(String uid, String city) async {
    await _db.collection('clients').doc(uid).update({'city': city});
  }

  // ── Sign out ───────────────────────────────────────────────────────────────

  Future<void> signOut() async {
    AppUser.current.clear();
    await _auth.signOut();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  Helpers
  // ═══════════════════════════════════════════════════════════════════════════

  User _requireUser() {
    final user = _auth.currentUser;
    if (user == null || (user.email ?? '').isEmpty) {
      throw AuthFailure('Қауіпсіздік үшін қайта кіріңіз',
          code: 'requires-recent-login');
    }
    return user;
  }

  Future<void> _reauth(User user, String currentPassword) async {
    try {
      final cred = EmailAuthProvider.credential(
          email: user.email!, password: currentPassword);
      await user.reauthenticateWithCredential(cred);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
        throw AuthFailure('Құпиясөз қате', code: 'wrong-password');
      }
      throw AuthFailure(_msg(e), code: e.code);
    }
  }

  /// Пайдаланушының профиль құжатын табады: алдымен `users/{uid}` (seller/admin,
  /// телефон өрісі `phoneNumber`), болмаса `clients/{uid}` (клиент, өрісі `phone`).
  Future<_ProfileRef> _profileRef(String uid) async {
    final usersRef = _db.collection('users').doc(uid);
    final usersDoc = await usersRef.get();
    if (usersDoc.exists) {
      final d = usersDoc.data()!;
      return _ProfileRef(
        ref: usersRef,
        exists: true,
        phoneField: 'phoneNumber',
        phone: d['phoneNumber'] as String? ?? '',
        email: d['email'] as String? ?? '',
      );
    }
    final clientsRef = _db.collection('clients').doc(uid);
    final clientsDoc = await clientsRef.get();
    final d = clientsDoc.data();
    return _ProfileRef(
      ref: clientsRef,
      exists: clientsDoc.exists,
      phoneField: 'phone',
      phone: d?['phone'] as String? ?? '',
      email: d?['email'] as String? ?? '',
    );
  }

  static String _generateBusinessCode() {
    final r = Random();
    return List.generate(6, (_) => r.nextInt(10)).join();
  }

  /// Firebase Auth қателерін қазақша хабарларға түрлендіру (толық карта).
  static String _msg(FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':
        return 'Бұл email тіркелген';
      case 'wrong-password':
      case 'invalid-credential':
        return 'Құпиясөз қате';
      case 'user-not-found':
        return 'Аккаунт табылмады';
      case 'weak-password':
        return 'Құпиясөз кем дегенде 6 таңба болуы керек';
      case 'invalid-email':
        return 'Email форматы қате';
      case 'requires-recent-login':
        return 'Қауіпсіздік үшін қайта кіріңіз';
      case 'too-many-requests':
        return 'Тым көп сұраныс. Кейінірек қайталаңыз';
      case 'network-request-failed':
        return 'Интернет байланысын тексеріңіз';
      default:
        return 'Қате: ${e.message ?? e.code}';
    }
  }

  /// Seller/admin экрандары (login_screen, register_screen) қолданатын
  /// қатені қазақшаға аударатын ашық көмекші.
  static String parseError(FirebaseAuthException e) => _msg(e);
}

class _ProfileRef {
  final DocumentReference<Map<String, dynamic>> ref;
  final bool exists;
  final String phoneField;
  final String phone;
  final String email;
  const _ProfileRef({
    required this.ref,
    required this.exists,
    required this.phoneField,
    required this.phone,
    required this.email,
  });
}
