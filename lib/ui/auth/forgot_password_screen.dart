import 'package:flutter/material.dart';
import '../../data/services/auth_service.dart';
import '../../theme/qoima_design.dart';

import '../../core/lang.dart';
/// Құпиясөзді қалпына келтіру: email → reset сілтемесі.
/// Аккаунттың бар-жоғын ЕШҚАШАН ашпаймыз — әрқашан бейтарап хабар.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _authService = AuthService();
  final _emailCtrl = TextEditingController();
  bool _isLoading = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailCtrl.text.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      setState(() => _error = tr('Неверный формат email', 'Email форматы қате'));
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      await _authService.sendPasswordReset(email);
      if (mounted) setState(() => _sent = true);
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = _emailCtrl.text.trim();
    return Scaffold(
      backgroundColor: cBg,
      body: Column(children: [
        QGradientHeader(
          title: tr('Восстановление пароля', 'Құпиясөзді қалпына келтіру'),
          showBack: true,
          onBack: () => Navigator.pop(context),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 26, 22, 30),
            child: _sent
                ? _buildSent(email)
                : Column(
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
                      Text(tr('Введите вашу почту', 'Поштаңызды енгізіңіз'),
                          style: manrope(19, FontWeight.w800, color: cInk)),
                      const SizedBox(height: 6),
                      Text(
                        tr('Мы отправим ссылку для восстановления пароля.', 'Құпиясөзді қалпына келтіру сілтемесін жібереміз.'),
                        style: manrope(13.5, FontWeight.w500, color: cInk2,
                            height: 1.5),
                      ),
                      const SizedBox(height: 22),
                      Text('Email',
                          style: manrope(12.5, FontWeight.w700, color: cInk2)),
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
                          const Icon(Icons.email_outlined,
                              color: cInk3, size: 19),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _emailCtrl,
                              keyboardType: TextInputType.emailAddress,
                              onChanged: (_) {
                                if (_error != null) {
                                  setState(() => _error = null);
                                }
                              },
                              style: manrope(15, FontWeight.w600, color: cInk),
                              cursorColor: cGreen,
                              decoration: InputDecoration(
                                hintText: 'example@mail.com',
                                hintStyle:
                                    manrope(15, FontWeight.w500, color: cInk3),
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                contentPadding: EdgeInsets.zero,
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                        ]),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: cRedTint,
                            borderRadius: BorderRadius.circular(12),
                            border:
                                Border.all(color: cRed.withValues(alpha: 0.3)),
                          ),
                          child: Row(children: [
                            const Icon(Icons.error_outline, color: cRed, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                                child: Text(_error!,
                                    style: manrope(13, FontWeight.w500,
                                        color: cRed))),
                          ]),
                        ),
                      ],
                      const SizedBox(height: 22),
                      QPrimaryButton(
                        label: tr('Отправить ссылку', 'Сілтеме жіберу'),
                        isLoading: _isLoading,
                        onPressed: _submit,
                      ),
                    ],
                  ),
          ),
        ),
      ]),
    );
  }

  Widget _buildSent(String email) => Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              color: cGreenTint,
              borderRadius: BorderRadius.circular(26),
            ),
            child: const Icon(Icons.mark_email_read_outlined,
                color: cGreen, size: 40),
          ),
          const SizedBox(height: 22),
          Text(tr('Проверьте почту', 'Тексеріңіз'),
              style: manrope(20, FontWeight.w800, color: cInk),
              textAlign: TextAlign.center),
          const SizedBox(height: 10),
          Text(
            tr('Если аккаунт существует, инструкция отправлена на $email.', 'Егер аккаунт болса, $email адресіне нұсқаулық жіберілді.'),
            style: manrope(14.5, FontWeight.w500, color: cInk2, height: 1.5),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 30),
          QPrimaryButton(
            label: tr('Вернуться ко входу', 'Кіруге оралу'),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      );
}
