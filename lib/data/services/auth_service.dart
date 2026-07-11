import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_model.dart';
import '../models/client_model.dart';
import '../../core/app_user.dart';

import '../../core/lang.dart';
/// Аутентификация қателерін UI-ге жеткізетін типтелген қате.
/// [code] — UI тармақтауы үшін.
class AuthFailure implements Exception {
  final String message;
  final String code;
  AuthFailure(this.message, {this.code = ''});
  @override
  String toString() => message;
}

/// Supabase Auth + Postgres профильдер.
///
/// БАРЛЫҚ рөл (client/seller/admin/superadmin) — ТЕЛЕФОН + ҚҰПИЯСӨЗБЕН
/// тіркеледі әрі кіреді. Email қолданушыға көрінбейді: Supabase password
/// логині идентификатор талап еткендіктен, телефоннан «синтетикалық» email
/// жасалады (`<цифрлар>@qoima.app`). Кіру: телефон → email_for_phone RPC →
/// signInWithPassword(email).
///
/// Телефон нөмірі тіркелуде Telegram боты арқылы РАСТАЛАДЫ (SMS-сіз, тегін) —
/// [startTelegramVerification] / [checkTelegramVerification]. Парольді
/// қалпына келтіру де солай ([resetPasswordViaTelegram]).
///
/// Верификация ЖОҚ: signUp бірден сессия ашады (Dashboard-та «Confirm email»
/// өшірулі + auto_confirm_email триггері). Профиль жолдарын `handle_new_user`
/// триггері signUp метадеректерінен жасайды.
class AuthService {
  final SupabaseClient _sb = Supabase.instance.client;

  User? get currentUser => _sb.auth.currentUser;
  String? get currentUid => _sb.auth.currentUser?.id;
  Stream<AuthState> get authStateChanges => _sb.auth.onAuthStateChange;

  /// Телефоннан жасырын (синтетикалық) email: `+77001234567` → `77001234567@qoima.app`.
  /// Supabase Auth password логині үшін ішкі идентификатор. Қолданушы көрмейді.
  static String _syntheticEmail(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    return '$digits@qoima.app';
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  CLIENT — телефон + құпиясөз (өзін-өзі тіркеу)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Жаңа клиентті тіркейді. Телефон Telegram-мен РАСТАЛҒАН болуы керек.
  /// Профильді триггер метадеректерден жасайды. Верификация жоқ — signUp соң
  /// сессия БІРДЕН басталады, gate ClientShell-ге өтеді.
  Future<void> registerClient({
    required String phoneNumber, // E.164: +7XXXXXXXXXX (Telegram-мен расталған)
    required String password,
    required String name,
    required String city,
  }) async {
    // a) Телефон бос па (anon RPC: телефон→email)
    final existing = await emailForPhone(phoneNumber);
    if (existing != null && existing.isNotEmpty) {
      throw AuthFailure(tr('Этот номер телефона уже зарегистрирован', 'Бұл телефон нөмір тіркелген'), code: 'phone-in-use');
    }

    // b) Auth аккаунты (синтетикалық email) + профиль метадеректері
    final cleanEmail = _syntheticEmail(phoneNumber);
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
      if (res.session == null) {
        await _sb.auth
            .signInWithPassword(email: cleanEmail, password: password);
      }
    } on AuthException catch (e) {
      throw _mapAuthError(e);
    }
  }

  /// Телефон → email RPC (кіруден бұрын anon шақырады). Барлық рөлге ортақ.
  Future<String?> emailForPhone(String phoneNumber) async {
    final res = await _sb.rpc('email_for_phone',
        params: {'p_phone': phoneNumber});
    return res as String?;
  }

  /// Телефон + құпиясөзбен кіру (барлық рөлге ортақ): RPC телефон→email →
  /// signInWithPassword.
  Future<void> loginWithPhonePassword({
    required String phoneNumber,
    required String password,
  }) async {
    final email = await emailForPhone(phoneNumber);
    if (email == null || email.isEmpty) {
      throw AuthFailure(tr('Аккаунт не найден', 'Аккаунт табылмады'), code: 'user-not-found');
    }
    try {
      await _sb.auth.signInWithPassword(email: email, password: password);
    } on AuthException catch (e) {
      throw _mapAuthError(e);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  TELEGRAM телефон растау (тіркелу + парольді қалпына келтіру)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Жаңа растау сессиясын бастайды: кездейсоқ токен қайтарады. Қосымша осы
  /// токенмен `t.me/<bot>?start=<token>` сілтемесін ашады.
  Future<String> startTelegramVerification() async {
    final res = await _sb.rpc('tg_start_verification');
    return res as String;
  }

  /// Растау статусын сұрайды (polling). Расталса phone (+7XXXXXXXXXX) қайтарады.
  Future<({bool verified, String? phone})> checkTelegramVerification(
      String token) async {
    final res = await _sb.rpc('tg_check_verification', params: {'p_token': token});
    final m = (res is Map) ? res.cast<String, dynamic>() : <String, dynamic>{};
    return (verified: m['verified'] == true, phone: m['phone'] as String?);
  }

  /// Парольді Telegram арқылы қалпына келтіреді: расталған токенмен edge
  /// функциясы (service_role) парольді жаңартады, содан соң жаңа парольмен
  /// кіреміз. [token] расталған (verified) болуы шарт.
  Future<void> resetPasswordViaTelegram({
    required String token,
    required String newPassword,
  }) async {
    try {
      final res = await _sb.functions.invoke('tg-reset-password',
          body: {'token': token, 'newPassword': newPassword});
      final data = res.data;
      final phone = (data is Map) ? data['phone'] as String? : null;
      if (res.status != 200 || phone == null || phone.isEmpty) {
        throw AuthFailure(tr('Не удалось сбросить пароль', 'Парольді қалпына келтіру сәтсіз'),
            code: 'reset-failed');
      }
      await loginWithPhonePassword(phoneNumber: phone, password: newPassword);
    } on FunctionException catch (e) {
      final detail = (e.details is Map) ? (e.details as Map)['error'] : null;
      switch (detail) {
        case 'not_verified':
          throw AuthFailure(tr('Номер не подтверждён', 'Нөмір расталмаған'), code: 'not-verified');
        case 'no_account':
          throw AuthFailure(tr('Аккаунт с этим номером не найден', 'Бұл нөмірмен аккаунт табылмады'),
              code: 'user-not-found');
        case 'weak_password':
          throw AuthFailure(tr('Пароль должен быть не короче 6 символов', 'Құпиясөз кем дегенде 6 таңба болуы керек'),
              code: 'weak-password');
        default:
          throw AuthFailure(tr('Не удалось сбросить пароль', 'Парольді қалпына келтіру сәтсіз'),
              code: 'reset-failed');
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  АККАУНТ ПАРАМЕТРЛЕРІ — жеке деректерді өзгерту (барлық рөлдер)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Телефон нөмірін өзгерту: reauth → бостығын тексеру → профильді жаңарту.
  /// Рөлге тәуелсіз екі кестені де жаңартады (тек бар жол өзгереді).
  Future<void> changePhoneNumber({
    required String currentPassword,
    required String newPhone, // E.164
  }) async {
    final user = _requireUser();
    await _reauth(user, currentPassword);

    final existing = await emailForPhone(newPhone);
    if (existing != null && existing.isNotEmpty && existing != user.email) {
      throw AuthFailure(tr('Этот номер привязан к другому аккаунту', 'Бұл нөмір басқа аккаунтта тіркелген'),
          code: 'phone-in-use');
    }
    await _sb.from('users').update({'phone': newPhone}).eq('id', user.id);
    await _sb.from('clients').update({'phone': newPhone}).eq('id', user.id);
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

  // ═══════════════════════════════════════════════════════════════════════════
  //  SELLER / ADMIN — телефон + құпиясөз
  // ═══════════════════════════════════════════════════════════════════════════

  /// seller/admin тіркеу. Телефон Telegram-мен РАСТАЛҒАН болуы керек.
  /// Профильді (+admin бизнес коды) триггер жасайды. Верификация жоқ — signUp
  /// соң сессия бірден басталады, gate рөлге қарай өтеді.
  Future<void> register({
    required String name,
    required String phoneNumber, // E.164 (Telegram-мен расталған)
    required String password,
    required String role, // 'admin' | 'seller'
  }) async {
    final existing = await emailForPhone(phoneNumber);
    if (existing != null && existing.isNotEmpty) {
      throw AuthFailure(tr('Этот номер телефона уже зарегистрирован', 'Бұл телефон нөмір тіркелген'), code: 'phone-in-use');
    }
    final cleanEmail = _syntheticEmail(phoneNumber);
    try {
      final res = await _sb.auth.signUp(
        email: cleanEmail,
        password: password,
        data: {'role': role, 'name': name.trim(), 'phone': phoneNumber},
      );
      if (res.session == null) {
        await _sb.auth
            .signInWithPassword(email: cleanEmail, password: password);
      }
    } on AuthException catch (e) {
      throw _mapAuthError(e);
    }
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

  /// Пайдаланушының есімін өзгертеді. Рөлге тәуелсіз — екі кестені де жаңартады
  /// (тек бар жол өзгереді: admin/seller → users, client → clients).
  Future<void> updateDisplayName(String name) async {
    final uid = currentUid;
    if (uid == null) {
      throw AuthFailure(tr('Войдите заново', 'Қайта кіріңіз'), code: 'no-user');
    }
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw AuthFailure(tr('Введите имя', 'Есімді енгізіңіз'), code: 'empty-name');
    }
    await _sb.from('users').update({'name': trimmed}).eq('id', uid);
    await _sb.from('clients').update({'name': trimmed}).eq('id', uid);
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
    if (uid == null) throw AuthFailure(tr('Войдите заново', 'Қайта кіріңіз'), code: 'no-user');
    await _sb.from('users').update({
      'owner_id': null,
      'join_status': 'none',
      'assigned_warehouse_id': null,
    }).eq('id', uid);
  }

  // ── Sign out ───────────────────────────────────────────────────────────────

  Future<void> signOut() async {
    AppUser.current.clear();
    await _sb.auth.signOut();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  Helpers
  // ═══════════════════════════════════════════════════════════════════════════

  User _requireUser() {
    final user = _sb.auth.currentUser;
    if (user == null || (user.email ?? '').isEmpty) {
      throw AuthFailure(tr('В целях безопасности войдите заново', 'Қауіпсіздік үшін қайта кіріңіз'),
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
      throw AuthFailure(tr('Неверный пароль', 'Құпиясөз қате'), code: 'wrong-password');
    }
  }

  /// Supabase Auth қателерін қазақша хабарларға түрлендіру.
  static AuthFailure _mapAuthError(AuthException e) {
    final msg = e.message.toLowerCase();
    if (msg.contains('already registered') ||
        msg.contains('already been registered') ||
        msg.contains('user already')) {
      return AuthFailure(tr('Этот номер уже зарегистрирован', 'Бұл нөмір тіркелген'), code: 'phone-in-use');
    }
    if (msg.contains('invalid login') ||
        msg.contains('invalid credentials') ||
        msg.contains('invalid email or password')) {
      return AuthFailure(tr('Неверный номер или пароль', 'Нөмір немесе құпиясөз қате'), code: 'wrong-password');
    }
    if (msg.contains('password should be') || msg.contains('weak')) {
      return AuthFailure(tr('Пароль должен быть не короче 6 символов', 'Құпиясөз кем дегенде 6 таңба болуы керек'),
          code: 'weak-password');
    }
    if (msg.contains('rate') || msg.contains('too many')) {
      return AuthFailure(tr('Слишком много запросов. Повторите позже', 'Тым көп сұраныс. Кейінірек қайталаңыз'),
          code: 'too-many-requests');
    }
    if (msg.contains('network')) {
      return AuthFailure(tr('Проверьте интернет-соединение', 'Интернет байланысын тексеріңіз'),
          code: 'network-request-failed');
    }
    return AuthFailure(tr('Ошибка: ${e.message}', 'Қате: ${e.message}'), code: 'unknown');
  }

  /// Ескі экрандар үшін үйлесімділік: қатені қазақша хабарға аударады.
  static String parseError(Object e) =>
      e is AuthFailure ? e.message : tr('Неизвестная ошибка', 'Белгісіз қате');
}
