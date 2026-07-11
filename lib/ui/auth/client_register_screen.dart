import 'package:flutter/material.dart';
import '../../core/kz_cities.dart';
import '../../data/services/auth_service.dart';
import '../../theme/qoima_design.dart';
import 'telegram_verify_button.dart';

import '../../core/lang.dart';
/// Клиентті тіркеу: Telegram-мен расталған телефон + құпиясөз + аты + қаласы.
class ClientRegisterScreen extends StatefulWidget {
  const ClientRegisterScreen({super.key});

  @override
  State<ClientRegisterScreen> createState() => _ClientRegisterScreenState();
}

class _ClientRegisterScreenState extends State<ClientRegisterScreen> {
  final _authService = AuthService();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  String? _selectedCity;
  String? _verifiedPhone; // Telegram-мен расталған нөмір (E.164)

  bool _isLoading = false;
  bool _obscurePass = true;
  bool _obscureConfirm = true;
  String? _error;

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  void _setErr(String? msg) => setState(() => _error = msg);

  Future<void> _register() async {
    // ── Валидация ────────────────────────────────────────────────────────────
    if (_verifiedPhone == null) {
      _setErr(tr('Подтвердите номер через Telegram', 'Нөмірді Telegram арқылы растаңыз'));
      return;
    }
    if (_passwordCtrl.text.length < 6) {
      _setErr(tr('Пароль должен быть не короче 6 символов', 'Құпиясөз кем дегенде 6 таңба болуы керек'));
      return;
    }
    if (_passwordCtrl.text != _confirmCtrl.text) {
      _setErr(tr('Пароли не совпадают', 'Құпиясөздер сәйкес келмейді'));
      return;
    }
    if (_nameCtrl.text.trim().length < 2) {
      _setErr(tr('Введите имя', 'Атыңызды енгізіңіз'));
      return;
    }
    if (_selectedCity == null) {
      _setErr(tr('Выберите город', 'Қаланы таңдаңыз'));
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });
    final password = _passwordCtrl.text;
    try {
      await _authService.registerClient(
        phoneNumber: _verifiedPhone!,
        password: password,
        name: _nameCtrl.text.trim(),
        city: _selectedCity!,
      );
      // Сессия бірден басталды — түбір экранға ораламыз, реактивті gate
      // ClientShell-ге ауыстырады.
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } on AuthFailure catch (e) {
      _setErr(e.message);
    } catch (e) {
      _setErr(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cBg,
      body: Column(children: [
        QGradientHeader(
          title: tr('Регистрация', 'Тіркелу'),
          subtitle: tr('Создание аккаунта покупателя', 'Сатып алушы аккаунтын жасау'),
          showBack: true,
          onBack: _isLoading ? null : () => Navigator.pop(context),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
                22, 20, 22, MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom + 30),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Телефон — Telegram арқылы расталады (қолмен жазылмайды)
                Text(tr('Номер телефона', 'Телефон нөмірі'),
                    style: manrope(12.5, FontWeight.w700, color: cInk2)),
                const SizedBox(height: 6),
                TelegramVerifyButton(
                  onVerified: (phone, _) =>
                      setState(() => _verifiedPhone = phone),
                ),
                const SizedBox(height: 14),

                // Құпиясөз
                _Field(
                  controller: _passwordCtrl,
                  label: tr('Пароль', 'Құпиясөз'),
                  hint: tr('Минимум 6 символов', 'Кемінде 6 таңба'),
                  icon: Icons.lock_outline_rounded,
                  obscure: _obscurePass,
                  suffix: _EyeButton(
                    obscured: _obscurePass,
                    onTap: () => setState(() => _obscurePass = !_obscurePass),
                  ),
                ),
                const SizedBox(height: 14),

                // Құпиясөзді қайталау
                _Field(
                  controller: _confirmCtrl,
                  label: tr('Повторите пароль', 'Құпиясөзді қайталаңыз'),
                  hint: tr('Повторите пароль', 'Құпиясөзді қайталаңыз'),
                  icon: Icons.lock_outline_rounded,
                  obscure: _obscureConfirm,
                  suffix: _EyeButton(
                    obscured: _obscureConfirm,
                    onTap: () =>
                        setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                ),
                const SizedBox(height: 14),

                // Аты
                _Field(
                  controller: _nameCtrl,
                  label: tr('Ваше имя', 'Атыңыз'),
                  hint: tr('Например: Алия', 'Мысалы: Алия'),
                  icon: Icons.person_outline_rounded,
                  capitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 14),

                // Қала
                Text(tr('Ваш город', 'Қалаңыз'),
                    style: manrope(12.5, FontWeight.w700, color: cInk2)),
                const SizedBox(height: 6),
                Container(
                  decoration: BoxDecoration(
                    color: cSurface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: _selectedCity != null ? cGreen : cLine,
                        width: 1.5),
                  ),
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedCity,
                    isExpanded: true,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.location_city_outlined,
                          color: cGreen, size: 19),
                      hintText: tr('Выберите город', 'Қаланы таңдаңыз'),
                      hintStyle: manrope(15, FontWeight.w500, color: cInk3),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
                      isDense: true,
                    ),
                    style: manrope(15, FontWeight.w600, color: cInk),
                    dropdownColor: cSurface,
                    items: kzCities
                        .map((c) => DropdownMenuItem(
                            value: c,
                            child: Text(trValue(c),
                                style: manrope(14, FontWeight.w500, color: cInk))))
                        .toList(),
                    onChanged: (v) => setState(() => _selectedCity = v),
                  ),
                ),

                if (_error != null) ...[
                  const SizedBox(height: 14),
                  _ErrorBox(_error!),
                ],

                const SizedBox(height: 22),
                QPrimaryButton(
                  label: tr('Регистрация', 'Тіркелу'),
                  isLoading: _isLoading,
                  onPressed: _register,
                ),
                const SizedBox(height: 14),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(tr('Уже есть аккаунт?', 'Аккаунтыңыз бар ма?'),
                      style: manrope(13.5, FontWeight.w500, color: cInk2)),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: _isLoading ? null : () => Navigator.pop(context),
                    child: Text(tr('Войти', 'Кіру'),
                        style: manrope(13.5, FontWeight.w700, color: cGreen)),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ]),
    );
  }
}

// ── Көп қолданылатын өрістер ──────────────────────────────────────────────────
class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final bool obscure;
  final Widget? suffix;
  final TextCapitalization capitalization;

  const _Field({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.obscure = false,
    this.suffix,
    this.capitalization = TextCapitalization.none,
  });

  @override
  Widget build(BuildContext context) {
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
                obscureText: obscure,
                textCapitalization: capitalization,
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
            if (suffix != null) ...[suffix!, const SizedBox(width: 12)],
          ]),
        ),
      ],
    );
  }
}

class _EyeButton extends StatelessWidget {
  final bool obscured;
  final VoidCallback onTap;
  const _EyeButton({required this.obscured, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Icon(
          obscured
              ? Icons.visibility_outlined
              : Icons.visibility_off_outlined,
          color: cInk3,
          size: 20,
        ),
      );
}

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
