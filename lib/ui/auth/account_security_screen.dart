import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_user.dart';
import '../../data/services/auth_service.dart';
import '../../theme/qoima_design.dart';
import 'telegram_verify_button.dart';

import '../../core/lang.dart';
/// Барлық рөлдерге ортақ «Жеке деректер» экраны: телефон/email/құпиясөз өзгерту.
/// Әр сезімтал өзгеріс алдында ағымдағы құпиясөзбен қайта аутентификация (reauth).
///
/// [showPhone] — телефонмен кіретін рөлдер үшін ғана (қазір: клиент). Seller/admin
/// телефон-кіруі іске қосылғанда (Q2) true берілуі мүмкін.
class AccountSecurityScreen extends StatelessWidget {
  final bool showPhone;
  const AccountSecurityScreen({super.key, this.showPhone = false});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cBg,
      body: Column(children: [
        QGradientHeader(
          title: tr('Личные данные', 'Жеке деректер'),
          subtitle: tr('Безопасность аккаунта', 'Аккаунт қауіпсіздігі'),
          showBack: true,
          onBack: () => Navigator.pop(context),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
            children: [
              QMenuItem(
                icon: Icons.badge_outlined,
                tone: 'green',
                title: tr('Имя', 'Есім'),
                subtitle: tr('Изменить отображаемое имя', 'Көрсетілетін есімді өзгерту'),
                onTap: () => _openSheet(context, const _ChangeNameSheet()),
              ),
              const SizedBox(height: 10),
              // Барлық рөл телефонмен кіреді — нөмір өзгерту әрқашан қолжетімді.
              QMenuItem(
                icon: Icons.phone_outlined,
                tone: 'green',
                title: tr('Номер телефона', 'Телефон нөмірі'),
                subtitle: tr('Изменить номер входа', 'Кіру нөмірін өзгерту'),
                onTap: () => _openSheet(context, const _ChangePhoneSheet()),
              ),
              const SizedBox(height: 10),
              QMenuItem(
                icon: Icons.lock_outline_rounded,
                tone: 'amber',
                title: tr('Пароль', 'Құпиясөз'),
                subtitle: tr('Изменение пароля', 'Құпиясөзді өзгерту'),
                onTap: () => _openSheet(context, const _ChangePasswordSheet()),
              ),
              const SizedBox(height: 24),
              Container(height: 1, color: cLine),
              const SizedBox(height: 16),
              QMenuItem(
                icon: Icons.delete_forever_outlined,
                tone: 'red',
                title: tr('Удалить аккаунт', 'Аккаунтты өшіру'),
                subtitle: tr('Безвозвратное удаление всех данных', 'Барлық деректі қайтарылмастай өшіру'),
                danger: true,
                onTap: () => _confirmDelete(context),
              ),
            ],
          ),
        ),
      ]),
    );
  }

  static void _openSheet(BuildContext context, Widget sheet) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => sheet,
    );
  }

  static Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(tr('Удалить аккаунт?', 'Аккаунтты өшіру керек пе?'),
            style: manrope(17, FontWeight.w800, color: cInk)),
        content: Text(
          tr(
              'Точно? Это действие необратимо: аккаунт, товары, продажи и весь магазин будут удалены безвозвратно.',
              'Нақты ма? Бұл әрекет қайтарылмайды: аккаунт, тауарлар, сатылымдар және бүкіл дүкен қайтарылмастай өшіріледі.'),
          style: manrope(14, FontWeight.w500, color: cInk2, height: 1.4),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Отмена', 'Болдырмау'),
                  style: manrope(14, FontWeight.w600, color: cInk2))),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: cRed,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10))),
              child: Text(tr('Удалить', 'Өшіру'))),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
          child: CircularProgressIndicator(color: cGreen, strokeWidth: 2)),
    );
    try {
      await AuthService().deleteAccount();
      navigator.popUntil((r) => r.isFirst);
    } on AuthFailure catch (e) {
      navigator.pop(); // жүктелу индикаторын жабу
      messenger.showSnackBar(SnackBar(
        content: Text(e.message),
        backgroundColor: cRed,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Ортақ парақ қабығы
// ─────────────────────────────────────────────────────────────────────────────
class _SheetShell extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _SheetShell({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: cSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      padding: EdgeInsets.fromLTRB(
          22, 10, 22, MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom + 26),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 18),
              decoration: BoxDecoration(
                  color: cLine, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          Text(title, style: manrope(19, FontWeight.w800, color: cInk)),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}

class _SecurityField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final bool obscure;
  final Widget? suffix;

  const _SecurityField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.obscure = false,
    this.suffix,
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
            color: cBg,
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
                style: manrope(15, FontWeight.w600, color: cInk),
                cursorColor: cGreen,
                decoration: InputDecoration(
                  hintText: hint,
                  hintStyle: manrope(15, FontWeight.w500, color: cInk3),
                  // Глобалды тема filled:true-ді өшіреміз (сұр контейнердің
                  // үстіне ақ толтыру қабаты түспеуі үшін).
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  focusedErrorBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  isDense: true,
                ),
              ),
            ),
            if (suffix != null) ...[suffix!, const SizedBox(width: 12)],
          ]),
        ),
        const SizedBox(height: 14),
      ],
    );
  }
}

class _SheetError extends StatelessWidget {
  final String message;
  const _SheetError(this.message);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Container(
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
                child: Text(message,
                    style: manrope(13, FontWeight.w500, color: cRed))),
          ]),
        ),
      );
}

void _toast(BuildContext context, String msg, {bool ok = true}) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(msg),
    behavior: SnackBarBehavior.floating,
    backgroundColor: ok ? cGreen : cRed,
  ));
}

// ─────────────────────────────────────────────────────────────────────────────
//  Есім өзгерту (сезімтал емес — reauth қажет емес)
// ─────────────────────────────────────────────────────────────────────────────
class _ChangeNameSheet extends StatefulWidget {
  const _ChangeNameSheet();
  @override
  State<_ChangeNameSheet> createState() => _ChangeNameSheetState();
}

class _ChangeNameSheetState extends State<_ChangeNameSheet> {
  final _auth = AuthService();
  late final _nameCtrl =
      TextEditingController(text: context.read<AppUser>().name);
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = tr('Введите имя', 'Есімді енгізіңіз'));
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _auth.updateDisplayName(name);
      if (!mounted) return;
      context.read<AppUser>().updateName(name);
      Navigator.pop(context);
      _toast(context, tr('Имя изменено', 'Есім өзгертілді'));
    } on AuthFailure catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = tr('Не удалось сохранить', 'Сақтау мүмкін болмады'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SheetShell(
      title: tr('Изменение имени', 'Есімді өзгерту'),
      children: [
        _SecurityField(
          controller: _nameCtrl,
          label: tr('Имя', 'Есім'),
          hint: tr('Ваше имя', 'Есіміңіз'),
          icon: Icons.badge_outlined,
        ),
        if (_error != null) _SheetError(_error!),
        QPrimaryButton(
          label: tr('Сохранить', 'Сақтау'),
          isLoading: _loading,
          onPressed: _submit,
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Телефон өзгерту
// ─────────────────────────────────────────────────────────────────────────────
class _ChangePhoneSheet extends StatefulWidget {
  const _ChangePhoneSheet();
  @override
  State<_ChangePhoneSheet> createState() => _ChangePhoneSheetState();
}

class _ChangePhoneSheetState extends State<_ChangePhoneSheet> {
  final _auth = AuthService();
  String? _verifiedPhone; // Telegram-мен расталған жаңа нөмір
  bool _loading = false;
  String? _error;

  Future<void> _submit() async {
    if (_verifiedPhone == null) {
      setState(() => _error = tr('Подтвердите новый номер через Telegram', 'Жаңа нөмірді Telegram арқылы растаңыз'));
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final newPhone = _verifiedPhone!;
    try {
      await _auth.changePhoneVerified(newPhone: newPhone);
      if (!mounted) return;
      context.read<AppUser>().updatePhone(newPhone);
      Navigator.pop(context);
      _toast(context, tr('Номер телефона изменён', 'Телефон нөмірі өзгертілді'));
    } on AuthFailure catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SheetShell(
      title: tr('Изменение номера телефона', 'Телефон нөмірін өзгерту'),
      children: [
        Text(
          tr('Подтвердите новый номер через Telegram — вход будет по нему.',
              'Жаңа нөмірді Telegram арқылы растаңыз — кіру сол нөмірмен болады.'),
          style: manrope(13, FontWeight.w500, color: cInk2, height: 1.4),
        ),
        const SizedBox(height: 14),
        TelegramVerifyButton(
          onVerified: (phone, _) => setState(() {
            _verifiedPhone = phone;
            _error = null;
          }),
        ),
        const SizedBox(height: 14),
        if (_error != null) _SheetError(_error!),
        QPrimaryButton(
          label: tr('Сохранить', 'Сақтау'),
          isLoading: _loading,
          onPressed: _submit,
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Құпиясөз өзгерту
// ─────────────────────────────────────────────────────────────────────────────
class _ChangePasswordSheet extends StatefulWidget {
  const _ChangePasswordSheet();
  @override
  State<_ChangePasswordSheet> createState() => _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends State<_ChangePasswordSheet> {
  final _auth = AuthService();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _verified = false; // Telegram растауы (иелік дәлелі)
  bool _loading = false;
  bool _obscureNew = true;
  String? _error;

  @override
  void dispose() {
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_verified) {
      setState(() => _error = tr('Подтвердите номер через Telegram', 'Нөмірді Telegram арқылы растаңыз'));
      return;
    }
    if (_newCtrl.text.length < 6) {
      setState(() => _error = tr('Пароль должен быть не короче 6 символов', 'Құпиясөз кем дегенде 6 таңба болуы керек'));
      return;
    }
    if (_newCtrl.text != _confirmCtrl.text) {
      setState(() => _error = tr('Пароли не совпадают', 'Құпиясөздер сәйкес келмейді'));
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Қолданушы кіріп тұр әрі Telegram нөмір иесі екенін дәлелдеді — ескі
      // пароль қажет емес.
      await _auth.changePassword(newPassword: _newCtrl.text);
      if (!mounted) return;
      Navigator.pop(context);
      _toast(context, tr('Пароль успешно изменён', 'Құпиясөз сәтті өзгертілді'));
    } on AuthFailure catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SheetShell(
      title: tr('Изменение пароля', 'Құпиясөзді өзгерту'),
      children: [
        Text(
          tr('Подтвердите свой номер через Telegram, затем задайте новый пароль.',
              'Нөміріңізді Telegram арқылы растап, жаңа құпиясөз қойыңыз.'),
          style: manrope(13, FontWeight.w500, color: cInk2, height: 1.4),
        ),
        const SizedBox(height: 14),
        TelegramVerifyButton(
          onVerified: (_, __) => setState(() {
            _verified = true;
            _error = null;
          }),
        ),
        const SizedBox(height: 14),
        if (_verified) ...[
          _SecurityField(
            controller: _newCtrl,
            label: tr('Новый пароль', 'Жаңа құпиясөз'),
            hint: tr('Минимум 6 символов', 'Кемінде 6 таңба'),
            icon: Icons.lock_reset_rounded,
            obscure: _obscureNew,
            suffix: GestureDetector(
              onTap: () => setState(() => _obscureNew = !_obscureNew),
              child: Icon(
                  _obscureNew
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: cInk3,
                  size: 20),
            ),
          ),
          _SecurityField(
            controller: _confirmCtrl,
            label: tr('Повторите новый пароль', 'Жаңа құпиясөзді қайталаңыз'),
            hint: tr('Повторите', 'Қайталаңыз'),
            icon: Icons.lock_reset_rounded,
            obscure: _obscureNew,
          ),
        ],
        if (_error != null) _SheetError(_error!),
        QPrimaryButton(
          label: tr('Сохранить', 'Сақтау'),
          isLoading: _loading,
          onPressed: _submit,
        ),
      ],
    );
  }
}
