import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/lang.dart';
import '../../core/phone_input.dart';
import '../../data/services/auth_service.dart';
import '../../theme/qoima_design.dart';
import 'auth_widgets.dart';
import 'register_chooser_screen.dart';
import 'forgot_password_screen.dart';

/// Біріңғай кіру: телефон + құпиясөз. Рөлді (client/seller/admin/superadmin)
/// жүйе автоматты анықтайды — «сатушы / клиент» ауыстырғышы жоқ.
class LoginScreen extends StatefulWidget {
  /// Гость flow-дан келгенде — gate маршрутты шешеді, callback тек UX үшін.
  final VoidCallback? afterLogin;
  const LoginScreen({super.key, this.afterLogin});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _authService = AuthService();

  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!isValidKzPhone(_phoneCtrl.text)) {
      setState(() => _errorMessage =
          tr('Введите номер телефона полностью', 'Телефон нөмірін толық енгізіңіз'));
      return;
    }
    if (_passwordCtrl.text.isEmpty) {
      setState(() =>
          _errorMessage = tr('Введите пароль', 'Құпиясөзді енгізіңіз'));
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      await _authService.loginWithPhonePassword(
        phoneNumber: kzPhoneToE164(_phoneCtrl.text),
        password: _passwordCtrl.text,
      );
      widget.afterLogin?.call();
      // Сәтті — реактивті gate (main.dart) рөл бойынша дұрыс экранға ауыстырады.
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } on AuthFailure catch (e) {
      setState(() => _errorMessage = e.message);
    } catch (_) {
      if (mounted) {
        setState(() =>
            _errorMessage = tr('Неизвестная ошибка', 'Белгісіз қате'));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom +
        MediaQuery.of(context).padding.bottom;
    return Scaffold(
      backgroundColor: cBg,
      body: Column(children: [
        // ── Жасыл hero + логотип + тіл ауыстырғыш ─────────────────────────
        Expanded(
          child: Stack(children: [
            const Positioned.fill(
                child: DecoratedBox(
                    decoration: BoxDecoration(gradient: kAuthGrad))),
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 10, 22, 0),
                child: Align(
                  alignment: Alignment.topRight,
                  child: const AuthLangSwitch(),
                ),
              ),
            ),
            SafeArea(
              bottom: false,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Логотиптің өз фоны бар (толық шаршы) — бұрыштарын дөңгелетеміз.
                    ClipRRect(
                      borderRadius: BorderRadius.circular(26),
                      child: Image.asset('assets/images/logo.png',
                          width: 92, height: 92, fit: BoxFit.cover),
                    ),
                    const SizedBox(height: 20),
                    Text('Qoima',
                        style: manrope(34, FontWeight.w800,
                            color: Colors.white, letterSpacing: -0.8)),
                    const SizedBox(height: 6),
                    Text(
                        tr('Умный учёт обуви и онлайн-продажи',
                            'Аяқ киімнің ақылды есебі және онлайн-сатылым'),
                        textAlign: TextAlign.center,
                        style: manrope(14, FontWeight.w500,
                            color: Colors.white.withValues(alpha: 0.85))),
                  ],
                ),
              ),
            ),
          ]),
        ),

        // ── Ақ төменгі парақ (форма) ──────────────────────────────────────
        Container(
          decoration: const BoxDecoration(
            color: cBg,
            borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
          ),
          transform: Matrix4.translationValues(0, -22, 0),
          padding: EdgeInsets.fromLTRB(24, 28, 24, bottomInset + 30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(tr('Вход в аккаунт', 'Аккаунтқа кіру'),
                  style: manrope(24, FontWeight.w800, color: cInk)),
              const SizedBox(height: 7),
              Row(children: [
                const Icon(Icons.verified_user_rounded,
                    color: cGreen, size: 16),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                      tr('Единый вход для покупателей и продавцов',
                          'Сатып алушылар мен сатушыларға біріңғай кіру'),
                      style: manrope(12.5, FontWeight.w600, color: cGreen)),
                ),
              ]),
              const SizedBox(height: 22),

              AuthField(
                controller: _phoneCtrl,
                label: tr('Номер телефона', 'Телефон нөмірі'),
                hint: '+7 (700) 000-00-00',
                icon: Icons.call_outlined,
                keyboardType: TextInputType.phone,
                // Макс 10 цифр (+7 елкоды бөлек): толық маска «+7 (700) 000-00-00»
                // 18 таңба → 11-ші цифр таза бұғатталады (жылжымайды).
                inputFormatters: [
                  LengthLimitingTextInputFormatter(18),
                  KzPhoneInputFormatter(),
                ],
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 16),

              AuthPasswordField(
                controller: _passwordCtrl,
                label: tr('Пароль', 'Құпиясөз'),
                hint: tr('Пароль', 'Құпиясөз'),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _signIn(),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: GestureDetector(
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const ForgotPasswordScreen())),
                  child: Text(
                      tr('Забыли пароль?', 'Құпиясөзді ұмыттыңыз ба?'),
                      style: manrope(13, FontWeight.w700, color: cGreen)),
                ),
              ),

              if (_errorMessage != null) ...[
                const SizedBox(height: 14),
                AuthErrorBox(_errorMessage!),
              ],

              const SizedBox(height: 22),
              AuthPrimaryButton(
                label: tr('Войти', 'Кіру'),
                isLoading: _isLoading,
                onPressed: _signIn,
              ),

              const SizedBox(height: 22),
              Container(height: 1, color: cLine),
              const SizedBox(height: 18),

              Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(tr('Нет аккаунта?', 'Аккаунтыңыз жоқ па?'),
                        style: manrope(14, FontWeight.w600, color: cInk2)),
                    const SizedBox(width: 5),
                    GestureDetector(
                      onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  const RegisterChooserScreen())),
                      child: Text(tr('Регистрация', 'Тіркелу'),
                          style:
                              manrope(14, FontWeight.w800, color: cGreen)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ]),
    );
  }
}
