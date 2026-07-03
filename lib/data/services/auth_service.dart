import 'dart:math';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_model.dart';
import '../models/client_model.dart';
import '../../core/app_user.dart';
import '../../core/supabase_config.dart';

/// Аутентификация қателерін UI-ге жеткізетін типтелген қате.
/// [code] — UI тармақтауы үшін.
class AuthFailure implements Exception {
  final String message;
  final String code;
  AuthFailure(this.message, {this.code = ''});
  @override
  String toString() => message;
}

/// Supabase Auth + Postgres профильдер (Firebase орнына).
///
/// Клиент: телефон + email + құпиясөз. Кіру — телефон→email RPC арқылы.
/// Верификация ЖОҚ: signUp бірден сессия ашады (Dashboard-та «Confirm email»
/// өшірулі + auto_confirm_email триггері). Профиль жолдарын `handle_new_user`
/// триггері signUp метадеректерінен жасайды.
class AuthService {
  final SupabaseClient _sb = Supabase.instance.client;

  // Google native кіру клиенті. serverClientId — WEB OAuth client ID
  // (idToken-ның audience-і Supabase-тегі тізіммен сәйкес болу үшін).
  static final GoogleSignIn _google = GoogleSignIn(
    serverClientId: SupabaseConfig.googleWebClientId,
  );

  User? get currentUser => _sb.auth.currentUser;
  String? get currentUid => _sb.auth.currentUser?.id;
  Stream<AuthState> get authStateChanges => _sb.auth.onAuthStateChange;

  // ═══════════════════════════════════════════════════════════════════════════
  //  CLIENT — телефон + email + құпиясөз (өзін-өзі тіркеу)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Жаңа клиентті тіркейді. Профильді триггер метадеректерден жасайды.
  /// Верификация жоқ — signUp соң сессия БІРДЕН басталады, gate ClientShell-ге өтеді.
  Future<void> registerClient({
    required String email,
    required String phoneNumber, // E.164: +7XXXXXXXXXX
    required String password,
    required String name,
    required String city,
  }) async {
    final cleanEmail = email.trim().toLowerCase();

    // a) Телефон бос па (anon RPC: телефон→email)
    final existing = await emailForPhone(phoneNumber);
    if (existing != null && existing.isNotEmpty) {
      throw AuthFailure('Бұл телефон нөмір тіркелген', code: 'phone-in-use');
    }

    // b) Auth аккаунты + профиль метадеректері (триггер clients жолын жасайды)
    try {
      final res = await _sb.auth.signUp(
        email: cleanEmail,
        password: password,
        data: {
          'role': 'client',
          'name': name.trim(),
          'phone': phoneNumber,
          'city': city,
        },
      );
      // «Confirm email» өшірулі болса сессия осында келеді. Қосулы қалып
      // қойса да auto_confirm_email триггері растап қояды — кіріп көреміз.
      if (res.session == null) {
        await _sb.auth
            .signInWithPassword(email: cleanEmail, password: password);
      }
    } on AuthException catch (e) {
      throw _mapAuthError(e);
    }
  }

  /// Телефон → email RPC (кіруден бұрын anon шақырады). phoneIndex орнына.
  Future<String?> emailForPhone(String phoneNumber) async {
    final res = await _sb.rpc('client_email_for_phone',
        params: {'p_phone': phoneNumber});
    return res as String?;
  }

  /// Телефон + құпиясөзбен кіру: RPC телефон→email → signInWithPassword.
  Future<void> loginWithPhonePassword({
    required String phoneNumber,
    required String password,
  }) async {
    final email = await emailForPhone(phoneNumber);
    if (email == null || email.isEmpty) {
      throw AuthFailure('Аккаунт табылмады', code: 'user-not-found');
    }
    try {
      await _sb.auth.signInWithPassword(email: email, password: password);
    } on AuthException catch (e) {
      throw _mapAuthError(e);
    }
  }

  /// Құпиясөзді қалпына келтіру сілтемесін жібереді (бейтарап хабар).
  Future<void> sendPasswordReset(String email) async {
    try {
      await _sb.auth.resetPasswordForEmail(email.trim());
    } on AuthException catch (_) {
      // Аккаунттың бар-жоғын ашпаймыз — UI бейтарап хабар көрсетеді.
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  АККАУНТ ПАРАМЕТРЛЕРІ — жеке деректерді өзгерту (барлық рөлдер)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Телефон нөмірін өзгерту: reauth → бостығын тексеру → профильді жаңарту.
  /// (Телефон Auth идентификаторы емес — тек clients жолында сақталады.)
  Future<void> changePhoneNumber({
    required String currentPassword,
    required String newPhone, // E.164
  }) async {
    final user = _requireUser();
    await _reauth(user, currentPassword);

    final existing = await emailForPhone(newPhone);
    if (existing != null && existing.isNotEmpty && existing != user.email) {
      throw AuthFailure('Бұл нөмір басқа аккаунтта тіркелген',
          code: 'phone-in-use');
    }
    await _sb.from('clients').update({'phone': newPhone}).eq('id', user.id);
  }

  /// Email өзгерту: reauth → updateUser(email). Supabase жаңа поштаға растау
  /// жібереді; расталған соң Auth email жаңарады, [syncEmailIfChanged] профильді
  /// сәйкестендіреді.
  Future<void> changeEmail({
    required String currentPassword,
    required String newEmail,
  }) async {
    final user = _requireUser();
    await _reauth(user, currentPassword);
    try {
      await _sb.auth.updateUser(
        UserAttributes(email: newEmail.trim().toLowerCase()),
      );
    } on AuthException catch (e) {
      throw _mapAuthError(e);
    }
  }

  /// Құпиясөзді өзгерту: ағымдағымен reauth → updateUser(password).
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final user = _requireUser();
    await _reauth(user, currentPassword);
    try {
      await _sb.auth.updateUser(UserAttributes(password: newPassword));
    } on AuthException catch (e) {
      throw _mapAuthError(e);
    }
  }

  /// Auth email профильдегіден өзгеше болса (өзгерту расталған) — профиль
  /// (users/clients) email-ін сәйкестендіреді.
  Future<void> syncEmailIfChanged() async {
    final user = _sb.auth.currentUser;
    final authEmail = user?.email?.toLowerCase();
    if (user == null || authEmail == null || authEmail.isEmpty) return;
    // users → clients ретімен тексеріп, сәйкессіздікті түзейміз.
    final u = await _sb.from('users').select('email').eq('id', user.id).maybeSingle();
    if (u != null) {
      if ((u['email'] as String?)?.toLowerCase() != authEmail) {
        await _sb.from('users').update({'email': authEmail}).eq('id', user.id);
      }
      return;
    }
    final c = await _sb.from('clients').select('email').eq('id', user.id).maybeSingle();
    if (c != null && (c['email'] as String?)?.toLowerCase() != authEmail) {
      await _sb.from('clients').update({'email': authEmail}).eq('id', user.id);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  SELLER / ADMIN — email + құпиясөз
  // ═══════════════════════════════════════════════════════════════════════════

  /// seller/admin тіркеу. Профильді (+admin бизнес коды) триггер жасайды.
  /// Верификация жоқ — signUp соң сессия бірден басталады, gate рөлге қарай өтеді.
  Future<void> register({
    required String name,
    required String email,
    required String password,
    required String role, // 'admin' | 'seller'
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    try {
      final res = await _sb.auth.signUp(
        email: cleanEmail,
        password: password,
        data: {'role': role, 'name': name.trim()},
      );
      if (res.session == null) {
        await _sb.auth
            .signInWithPassword(email: cleanEmail, password: password);
      }
    } on AuthException catch (e) {
      throw _mapAuthError(e);
    }
  }

  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    try {
      await _sb.auth.signInWithPassword(
          email: email.trim().toLowerCase(), password: password);
    } on AuthException catch (e) {
      throw _mapAuthError(e);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  GOOGLE-МЕН КІРУ (барлық рөлдер — қосымша кіру/тіркелу жолы)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Google аккаунтымен кіреді. Телефонда — native SDK (idToken →
  /// signInWithIdToken); вебте native SDK жоқ, сондықтан Supabase-тің OAuth
  /// redirect ағыны қолданылады (бет Google-ға өтіп, сессиямен қайта оралады).
  /// Алғаш кірген қолданушыда профиль болмайды — gate CompleteProfileScreen
  /// көрсетіп, рөл мен жетіспейтін деректерді (телефон/қала) сұрайды.
  Future<void> signInWithGoogle() async {
    if (kIsWeb) {
      try {
        await _sb.auth.signInWithOAuth(
          OAuthProvider.google,
          redirectTo: Uri.base.origin, // осы бетке қайта ораламыз
        );
      } on AuthException catch (e) {
        throw _mapAuthError(e);
      }
      return; // redirect кетеді — сессия бет қайта жүктелгенде келеді
    }

    GoogleSignInAccount? account;
    try {
      // Аккаунт таңдау диалогы әр жолы шығуы үшін алдымен тазалаймыз.
      try {
        await _google.signOut();
      } catch (_) {}
      account = await _google.signIn();
    } catch (e) {
      throw AuthFailure('Google қолжетімсіз: $e', code: 'google-unavailable');
    }
    if (account == null) {
      throw AuthFailure('Кіру тоқтатылды', code: 'cancelled');
    }
    final auth = await account.authentication;
    final idToken = auth.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw AuthFailure(
          'Google токені алынбады — Web Client ID баптауын тексеріңіз',
          code: 'no-id-token');
    }
    try {
      await _sb.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: auth.accessToken,
      );
    } on AuthException catch (e) {
      throw _mapAuthError(e);
    }
  }

  /// Ағымдағы қолданушының Google-ден келген аты (профиль prefill үшін).
  String get oauthDisplayName {
    final m = _sb.auth.currentUser?.userMetadata ?? {};
    return (m['full_name'] as String?) ?? (m['name'] as String?) ?? '';
  }

  /// Google-мен алғаш кірген қолданушы КЛИЕНТ профилін жасайды
  /// (тіркеу формасындағы міндетті деректер: телефон + аты + қала).
  Future<void> completeClientProfile({
    required String phoneNumber, // E.164
    required String name,
    required String city,
  }) async {
    final user = _requireUser();
    final existing = await emailForPhone(phoneNumber);
    if (existing != null && existing.isNotEmpty) {
      throw AuthFailure('Бұл телефон нөмір тіркелген', code: 'phone-in-use');
    }
    await _sb.from('clients').upsert({
      'id': user.id,
      'phone': phoneNumber,
      'email': (user.email ?? '').toLowerCase(),
      'name': name.trim(),
      'city': city,
      'email_verified': true,
    }, onConflict: 'id');
  }

  /// Google-мен алғаш кірген қолданушы БИЗНЕС профилін жасайды
  /// (role: 'admin' — дүкен иесі, бизнес-кодымен; 'seller' — сатушы).
  Future<void> completeBusinessProfile({
    required String name,
    required String role, // 'admin' | 'seller'
  }) async {
    final user = _requireUser();
    final email = (user.email ?? '').toLowerCase();
    if (role == 'admin') {
      final code = _generateBusinessCode();
      await _sb.from('users').upsert({
        'id': user.id,
        'name': name.trim(),
        'email': email,
        'role': 'admin',
        'owner_id': user.id,
        'business_code': code,
        'join_status': 'active',
      }, onConflict: 'id');
      await _sb
          .from('business_codes')
          .upsert({'code': code, 'admin_uid': user.id}, onConflict: 'code');
    } else {
      await _sb.from('users').upsert({
        'id': user.id,
        'name': name.trim(),
        'email': email,
        'role': 'seller',
        'owner_id': null,
        'join_status': 'none',
      }, onConflict: 'id');
    }
  }

  /// 6-цифрлы бизнес коды (handle_new_user триггеріндегі логикамен бірдей).
  static String _generateBusinessCode() {
    final r = Random();
    return List.generate(6, (_) => r.nextInt(10)).join();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  Профиль оқу
  // ═══════════════════════════════════════════════════════════════════════════

  Future<UserModel?> getUserDoc(String uid) async {
    try {
      final row =
          await _sb.from('users').select().eq('id', uid).maybeSingle();
      if (row == null) return null;
      return UserModel.fromMap(row);
    } catch (_) {
      return null;
    }
  }

  Future<ClientModel?> getClientDoc(String uid) async {
    try {
      final row =
          await _sb.from('clients').select().eq('id', uid).maybeSingle();
      if (row == null) return null;
      return ClientModel.fromMap(row);
    } catch (_) {
      return null;
    }
  }

  Future<void> updateClientCity(String uid, String city) async {
    await _sb.from('clients').update({'city': city}).eq('id', uid);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  ЖАЛПЫ БЛОК (superadmin қояды)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Ағымдағы қолданушының блок күйі (RPC, RLS айналып өтеді):
  /// source: 'self' — өзі блокталған; 'owner' — дүкен иесі блокталған (каскад).
  /// Қате болса блокталмаған деп есептейміз (кіруді бұғаттамау үшін).
  Future<({bool blocked, String reason, String source})>
      fetchBlockStatus() async {
    try {
      final res = await _sb.rpc('my_block_status');
      final m = (res is Map) ? res.cast<String, dynamic>() : <String, dynamic>{};
      return (
        blocked: m['blocked'] == true,
        reason: (m['reason'] as String?) ?? '',
        source: (m['source'] as String?) ?? '',
      );
    } catch (_) {
      return (blocked: false, reason: '', source: '');
    }
  }

  /// Seller дүкен иесінен босап шығады (иесі блокталғанда басқа дүкенге ауысу
  /// үшін): owner_id тазарады, join_status='none' → SellerJoinScreen.
  Future<void> detachFromOwner() async {
    final uid = currentUid;
    if (uid == null) throw AuthFailure('Қайта кіріңіз', code: 'no-user');
    await _sb.from('users').update({
      'owner_id': null,
      'join_status': 'none',
      'assigned_warehouse_id': null,
    }).eq('id', uid);
  }

  // ── Sign out ───────────────────────────────────────────────────────────────

  Future<void> signOut() async {
    AppUser.current.clear();
    // Google сессиясын да тазалаймыз (келесіде аккаунт таңдау шығуы үшін).
    // Вебте native плагин жоқ — тек Supabase signOut жеткілікті.
    if (!kIsWeb) {
      try {
        await _google.signOut();
      } catch (_) {}
    }
    await _sb.auth.signOut();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  Helpers
  // ═══════════════════════════════════════════════════════════════════════════

  User _requireUser() {
    final user = _sb.auth.currentUser;
    if (user == null || (user.email ?? '').isEmpty) {
      throw AuthFailure('Қауіпсіздік үшін қайта кіріңіз',
          code: 'requires-recent-login');
    }
    return user;
  }

  /// Ағымдағы құпиясөзді растау: қайта кіріп көреміз (Supabase-те reauth жоқ).
  Future<void> _reauth(User user, String currentPassword) async {
    try {
      await _sb.auth.signInWithPassword(
          email: user.email!, password: currentPassword);
    } on AuthException catch (_) {
      throw AuthFailure('Құпиясөз қате', code: 'wrong-password');
    }
  }

  /// Supabase Auth қателерін қазақша хабарларға түрлендіру.
  static AuthFailure _mapAuthError(AuthException e) {
    final msg = e.message.toLowerCase();
    if (msg.contains('already registered') ||
        msg.contains('already been registered') ||
        msg.contains('user already')) {
      return AuthFailure('Бұл email тіркелген', code: 'email-already-in-use');
    }
    if (msg.contains('invalid login') ||
        msg.contains('invalid credentials') ||
        msg.contains('invalid email or password')) {
      return AuthFailure('Email немесе құпиясөз қате', code: 'wrong-password');
    }
    if (msg.contains('email not confirmed')) {
      return AuthFailure('Поштаңызды растаңыз', code: 'email-not-confirmed');
    }
    if (msg.contains('token has expired') || msg.contains('invalid token') ||
        msg.contains('otp')) {
      return AuthFailure('Код қате немесе мерзімі өтті', code: 'invalid-otp');
    }
    if (msg.contains('password should be') || msg.contains('weak')) {
      return AuthFailure('Құпиясөз кем дегенде 6 таңба болуы керек',
          code: 'weak-password');
    }
    if (msg.contains('invalid email')) {
      return AuthFailure('Email форматы қате', code: 'invalid-email');
    }
    if (msg.contains('rate') || msg.contains('too many')) {
      return AuthFailure('Тым көп сұраныс. Кейінірек қайталаңыз',
          code: 'too-many-requests');
    }
    if (msg.contains('network')) {
      return AuthFailure('Интернет байланысын тексеріңіз',
          code: 'network-request-failed');
    }
    return AuthFailure('Қате: ${e.message}', code: 'unknown');
  }

  /// Ескі экрандар үшін үйлесімділік: қатені қазақша хабарға аударады.
  static String parseError(Object e) =>
      e is AuthFailure ? e.message : 'Белгісіз қате';
}
