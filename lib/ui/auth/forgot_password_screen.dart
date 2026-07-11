import 'package:flutter/material.dart';
import '../../data/services/auth_service.dart';
import '../../theme/qoima_design.dart';
import 'telegram_verify_button.dart';

import '../../core/lang.dart';
/// Құпиясөзді қалпына келтіру — Telegram арқылы (SMS-сіз).
///
/// Ағын: телефонды Telegram-мен растайды (иесі екені дәлелденеді) → жаңа
/// құпиясөз енгізеді → edge функциясы парольді жаңартады да, сол телефон+жаңа
/// парольмен КІРЕДІ → реактивті gate дұрыс экранға ауыстырады.
/// Барлық рөлге ортақ (клиент/сатушы/админ/суперадмин).
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _authService = AuthService();
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  String? _verifiedPhone;
  String? _verifyToken;
  bool _isLoading = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_verifiedPhone == null || _verifyToken == null) {
      setState(() => _error = tr('Подтвердите номер через Telegram', 'Нөмірді Telegram арқылы растаңыз'));
      return;
    }
    if (_passCtrl.text.length < 6) {
      setState(() => _error = tr('Пароль должен быть не короче 6 символов', 'Құпиясөз кем дегенде 6 таңба болуы керек'));
      return;
    }
    if (_passCtrl.text != _confirmCtrl.text) {
      setState(() => _error = tr('Пароли не совпадают', 'Құпиясөздер сәйкес келмейді'));
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      await _authService.resetPasswordViaTelegram(
        token: _verifyToken!,
        newPassword: _passCtrl.text,
      );
      // Сәтті — жаңа парольмен кірдік, реактивті gate экранды ауыстырады.
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = tr('Не удалось сбросить пароль', 'Парольді қалпына келтіру сәтсіз'));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final verified = _verifiedPhone != null;
    return Scaffold(
      backgroundColor: cBg,
      body: Column(children: [
        QGradientHeader(
          title: tr('Восстановление пароля', 'Құпиясөзді қалпына келтіру'),
          showBack: true,
          onBack: _isLoading ? null : () => Navigator.pop(context),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
                22, 26, 22, MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom + 30),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: cGreenTint,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Icon(Icons.lock_reset_rounded,
                      color: cGreen, size: 38),
                ),
                const SizedBox(height: 20),
                Text(tr('Подтвердите свой номер', 'Нөміріңізді растаңыз'),
                    style: manrope(19, FontWeight.w800, color: cInk)),
                const SizedBox(height: 6),
                Text(
                  tr('Подтвердите номер через Telegram, затем задайте новый пароль.',
                      'Нөмірді Telegram арқылы растап, жаңа құпиясөз қойыңыз.'),
                  style: manrope(13.5, FontWeight.w500, color: cInk2, height: 1.5),
                ),
                const SizedBox(height: 22),

                // 1) Telegram растау
                TelegramVerifyButton(
                  onVerified: (phone, token) => setState(() {
                    _verifiedPhone = phone;
                    _verifyToken = token;
                    _error = null;
                  }),
                ),

                // 2) Жаңа құпиясөз (растаудан кейін)
                if (verified) ...[
                  const SizedBox(height: 20),
                  Text(tr('Новый пароль', 'Жаңа құпиясөз'),
                      style: manrope(12.5, FontWeight.w700, color: cInk2)),
                  const SizedBox(height: 6),
                  _passwordBox(
                    controller: _passCtrl,
                    hint: tr('Минимум 6 символов', 'Кемінде 6 таңба'),
                    obscure: _obscure,
                    onToggle: () => setState(() => _obscure = !_obscure),
                  ),
                  const SizedBox(height: 14),
                  Text(tr('Повторите пароль', 'Құпиясөзді қайталаңыз'),
                      style: manrope(12.5, FontWeight.w700, color: cInk2)),
                  const SizedBox(height: 6),
                  _passwordBox(
                    controller: _confirmCtrl,
                    hint: tr('Повторите пароль', 'Құпиясөзді қайталаңыз'),
                    obscure: _obscure,
                    onToggle: () => setState(() => _obscure = !_obscure),
                  ),
                ],

                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Container(
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
                          child: Text(_error!,
                              style: manrope(13, FontWeight.w500, color: cRed))),
                    ]),
                  ),
                ],

                if (verified) ...[
                  const SizedBox(height: 22),
                  QPrimaryButton(
                    label: tr('Сохранить пароль', 'Құпиясөзді сақтау'),
                    isLoading: _isLoading,
                    onPressed: _submit,
                  ),
                ],
              ],
            ),
          ),
        ),
      ]),
    );
  }

  Widget _passwordBox({
    required TextEditingController controller,
    required String hint,
    required bool obscure,
    required VoidCallback onToggle,
  }) {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: cSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cLine, width: 1.5),
      ),
      child: Row(children: [
        const SizedBox(width: 14),
        const Icon(Icons.lock_outline_rounded, color: cInk3, size: 19),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            controller: controller,
            obscureText: obscure,
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
        GestureDetector(
          onTap: onToggle,
          child: Icon(
              obscure
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              color: cInk3,
              size: 20),
        ),
        const SizedBox(width: 14),
      ]),
    );
  }
}
