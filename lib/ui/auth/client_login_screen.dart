import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/phone_input.dart';
import '../../data/services/auth_service.dart';
import '../../theme/qoima_design.dart';
import 'google_sign_in_button.dart';
import 'login_screen.dart';
import 'client_register_screen.dart';
import 'forgot_password_screen.dart';

/// Клиенттің кіру экраны: телефон + құпиясөз.
/// Телефон → phoneIndex → email → Firebase Auth (auth_service ішінде).
class ClientLoginScreen extends StatefulWidget {
  /// Гость корзинасынан кірген кезде шақырылады — gate-тің өзі маршрутты
  /// шешеді, бірақ бұл callback анимация/UX мақсаттарында қолданылуы мүмкін.
  final VoidCallback? afterLogin;
  const ClientLoginScreen({super.key, this.afterLogin});

  @override
  State<ClientLoginScreen> createState() => _ClientLoginScreenState();
}

class _ClientLoginScreenState extends State<ClientLoginScreen> {
  final _authService = AuthService();
  final _phoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!isValidKzPhone(_phoneCtrl.text)) {
      setState(() => _errorMessage = 'Телефон нөмірін толық енгізіңіз');
      return;
    }
    if (_passwordCtrl.text.isEmpty) {
      setState(() => _errorMessage = 'Құпиясөзді енгізіңіз');
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
      // Сәтті — реактивті gate (main.dart) дұрыс экранға ауыстырады.
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } on AuthFailure catch (e) {
      setState(() => _errorMessage = e.message);
    } catch (_) {
      if (mounted) setState(() => _errorMessage = 'Белгісіз қате');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cBg,
      body: Column(children: [
        // ── Жоғарғы градиент ──────────────────────────────────────────────
        Expanded(
          child: Container(
            decoration: const BoxDecoration(gradient: kGrad),
            child: SafeArea(
              bottom: false,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 92,
                      height: 92,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(26),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.28),
                            width: 1.5),
                      ),
                      child: Image.asset('assets/images/logo.png',
                          width: 52, height: 52),
                    ),
                    const SizedBox(height: 22),
                    Text('Qoima',
                        style: manrope(38, FontWeight.w800,
                            color: Colors.white, letterSpacing: -1)),
                    const SizedBox(height: 6),
                    Text('Умный учёт обуви и онлайн-продажи',
                        style: manrope(15, FontWeight.w500,
                            color: Colors.white.withValues(alpha: 0.8))),
                  ],
                ),
              ),
            ),
          ),
        ),

        // ── Ақ төменгі парақ ──────────────────────────────────────────────
        Container(
          decoration: const BoxDecoration(
            color: cSurface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
          ),
          padding: EdgeInsets.fromLTRB(
              22, 26, 22, MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom + 30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Аккаунтқа кіру',
                  style: manrope(21, FontWeight.w800, color: cInk)),
              const SizedBox(height: 14),

              // Телефон
              _buildField(
                controller: _phoneCtrl,
                label: 'Телефон нөмірі',
                hint: '+7 (700) 000-00-00',
                icon: Icons.phone_outlined,
                keyboardType: TextInputType.phone,
                inputFormatters: [KzPhoneInputFormatter()],
              ),
              const SizedBox(height: 12),

              // Құпиясөз
              _buildField(
                controller: _passwordCtrl,
                label: 'Құпиясөз',
                hint: 'Құпиясөз',
                icon: Icons.lock_outlined,
                obscureText: _obscurePassword,
                suffix: GestureDetector(
                  onTap: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                  child: Icon(
                    _obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    color: cInk3,
                    size: 20,
                  ),
                ),
              ),

              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: GestureDetector(
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const ForgotPasswordScreen())),
                  child: Text('Құпиясөзді ұмыттыңыз ба?',
                      style: manrope(13, FontWeight.w600, color: cGreen)),
                ),
              ),

              if (_errorMessage != null) ...[
                const SizedBox(height: 10),
                _ErrorBox(_errorMessage!),
              ],

              const SizedBox(height: 14),
              QPrimaryButton(
                label: 'Кіру',
                isLoading: _isLoading,
                onPressed: _signIn,
              ),

              const SizedBox(height: 14),
              GoogleSignInButton(afterLogin: widget.afterLogin),

              const SizedBox(height: 14),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text('Аккаунтыңыз жоқ па?',
                    style: manrope(13.5, FontWeight.w500, color: cInk2)),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const ClientRegisterScreen())),
                  child: Text('Тіркелу',
                      style: manrope(13.5, FontWeight.w700, color: cGreen)),
                ),
              ]),
              const SizedBox(height: 10),
              Container(height: 1, color: cLine),
              const SizedBox(height: 12),

              // Сатушы ретінде кіру
              Center(
                child: GestureDetector(
                  onTap: () => Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (_) => const LoginScreen())),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.storefront_outlined,
                          color: cGreen, size: 18),
                      const SizedBox(width: 7),
                      Text('Войти как продавец',
                          style: manrope(14, FontWeight.w600, color: cInk2)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    bool obscureText = false,
    Widget? suffix,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: manrope(12.5, FontWeight.w700, color: cInk2)),
        const SizedBox(height: 6),
        Container(
          height: 52,
          decoration: BoxDecoration(
            color: cSurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cLine, width: 1.5),
          ),
          child: Row(children: [
            const SizedBox(width: 14),
            Icon(icon, color: cInk3, size: 19),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: controller,
                keyboardType: keyboardType,
                obscureText: obscureText,
                inputFormatters: inputFormatters?.cast(),
                style: manrope(15, FontWeight.w600, color: cInk),
                cursorColor: cGreen,
                decoration: InputDecoration(
                  hintText: hint,
                  hintStyle: manrope(15, FontWeight.w500, color: cInk3),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  isDense: true,
                ),
              ),
            ),
            if (suffix != null) ...[suffix, const SizedBox(width: 14)],
          ]),
        ),
      ],
    );
  }
}

// ── Error box ─────────────────────────────────────────────────────────────────
class _ErrorBox extends StatelessWidget {
  final String message;
  const _ErrorBox(this.message);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cRedTint,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cRed.withValues(alpha: 0.3)),
        ),
        child: Row(children: [
          const Icon(Icons.error_outline, color: cRed, size: 18),
          const SizedBox(width: 8),
          Expanded(
              child:
                  Text(message, style: manrope(13, FontWeight.w500, color: cRed))),
        ]),
      );
}
