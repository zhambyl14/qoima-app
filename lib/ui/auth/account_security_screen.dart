import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/app_user.dart';
import '../../core/phone_input.dart';
import '../../data/services/auth_service.dart';
import '../../theme/qoima_design.dart';

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
          title: 'Жеке деректер',
          subtitle: 'Аккаунт қауіпсіздігі',
          showBack: true,
          onBack: () => Navigator.pop(context),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
            children: [
              if (showPhone) ...[
                QMenuItem(
                  icon: Icons.phone_outlined,
                  tone: 'green',
                  title: 'Телефон нөмірі',
                  subtitle: 'Кіру нөмірін өзгерту',
                  onTap: () => _openSheet(context, const _ChangePhoneSheet()),
                ),
                const SizedBox(height: 10),
              ],
              QMenuItem(
                icon: Icons.email_outlined,
                tone: 'blue',
                title: 'Email',
                subtitle: 'Поштаны өзгерту',
                onTap: () => _openSheet(context, const _ChangeEmailSheet()),
              ),
              const SizedBox(height: 10),
              QMenuItem(
                icon: Icons.lock_outline_rounded,
                tone: 'amber',
                title: 'Құпиясөз',
                subtitle: 'Құпиясөзді өзгерту',
                onTap: () => _openSheet(context, const _ChangePasswordSheet()),
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
          22, 10, 22, MediaQuery.of(context).viewInsets.bottom + 26),
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
  final TextInputType? keyboard;
  final List<TextInputFormatter>? formatters;

  const _SecurityField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.obscure = false,
    this.suffix,
    this.keyboard,
    this.formatters,
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
                keyboardType: keyboard,
                inputFormatters: formatters,
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
//  Телефон өзгерту
// ─────────────────────────────────────────────────────────────────────────────
class _ChangePhoneSheet extends StatefulWidget {
  const _ChangePhoneSheet();
  @override
  State<_ChangePhoneSheet> createState() => _ChangePhoneSheetState();
}

class _ChangePhoneSheetState extends State<_ChangePhoneSheet> {
  final _auth = AuthService();
  final _passCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _passCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_passCtrl.text.isEmpty) {
      setState(() => _error = 'Ағымдағы құпиясөзді енгізіңіз');
      return;
    }
    if (!isValidKzPhone(_phoneCtrl.text)) {
      setState(() => _error = 'Телефон нөмірін толық енгізіңіз');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final newPhone = kzPhoneToE164(_phoneCtrl.text);
    try {
      await _auth.changePhoneNumber(
        currentPassword: _passCtrl.text,
        newPhone: newPhone,
      );
      if (!mounted) return;
      context.read<AppUser>().updatePhone(newPhone);
      Navigator.pop(context);
      _toast(context, 'Телефон нөмірі өзгертілді');
    } on AuthFailure catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SheetShell(
      title: 'Телефон нөмірін өзгерту',
      children: [
        _SecurityField(
          controller: _passCtrl,
          label: 'Ағымдағы құпиясөз',
          hint: 'Құпиясөз',
          icon: Icons.lock_outline_rounded,
          obscure: _obscure,
          suffix: GestureDetector(
            onTap: () => setState(() => _obscure = !_obscure),
            child: Icon(
                _obscure
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                color: cInk3,
                size: 20),
          ),
        ),
        _SecurityField(
          controller: _phoneCtrl,
          label: 'Жаңа телефон нөмірі',
          hint: '+7 (700) 000-00-00',
          icon: Icons.phone_outlined,
          keyboard: TextInputType.phone,
          formatters: [KzPhoneInputFormatter()],
        ),
        if (_error != null) _SheetError(_error!),
        QPrimaryButton(
          label: 'Сақтау',
          isLoading: _loading,
          onPressed: _submit,
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Email өзгерту
// ─────────────────────────────────────────────────────────────────────────────
class _ChangeEmailSheet extends StatefulWidget {
  const _ChangeEmailSheet();
  @override
  State<_ChangeEmailSheet> createState() => _ChangeEmailSheetState();
}

class _ChangeEmailSheetState extends State<_ChangeEmailSheet> {
  final _auth = AuthService();
  final _passCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _passCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_passCtrl.text.isEmpty) {
      setState(() => _error = 'Ағымдағы құпиясөзді енгізіңіз');
      return;
    }
    final email = _emailCtrl.text.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      setState(() => _error = 'Email форматы қате');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _auth.changeEmail(
        currentPassword: _passCtrl.text,
        newEmail: email,
      );
      if (!mounted) return;
      Navigator.pop(context);
      _toast(context, 'Жаңа поштаңызды тексеріңіз. Растау сілтемесі жіберілді.');
    } on AuthFailure catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SheetShell(
      title: 'Email өзгерту',
      children: [
        _SecurityField(
          controller: _passCtrl,
          label: 'Ағымдағы құпиясөз',
          hint: 'Құпиясөз',
          icon: Icons.lock_outline_rounded,
          obscure: _obscure,
          suffix: GestureDetector(
            onTap: () => setState(() => _obscure = !_obscure),
            child: Icon(
                _obscure
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                color: cInk3,
                size: 20),
          ),
        ),
        _SecurityField(
          controller: _emailCtrl,
          label: 'Жаңа email',
          hint: 'example@mail.com',
          icon: Icons.email_outlined,
          keyboard: TextInputType.emailAddress,
        ),
        if (_error != null) _SheetError(_error!),
        QPrimaryButton(
          label: 'Растау сілтемесін жіберу',
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
  final _currentCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _loading = false;
  bool _obscureCur = true;
  bool _obscureNew = true;
  String? _error;

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_currentCtrl.text.isEmpty) {
      setState(() => _error = 'Ағымдағы құпиясөзді енгізіңіз');
      return;
    }
    if (_newCtrl.text.length < 6) {
      setState(() => _error = 'Құпиясөз кем дегенде 6 таңба болуы керек');
      return;
    }
    if (_newCtrl.text != _confirmCtrl.text) {
      setState(() => _error = 'Құпиясөздер сәйкес келмейді');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _auth.changePassword(
        currentPassword: _currentCtrl.text,
        newPassword: _newCtrl.text,
      );
      if (!mounted) return;
      Navigator.pop(context);
      _toast(context, 'Құпиясөз сәтті өзгертілді');
    } on AuthFailure catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SheetShell(
      title: 'Құпиясөзді өзгерту',
      children: [
        _SecurityField(
          controller: _currentCtrl,
          label: 'Ағымдағы құпиясөз',
          hint: 'Құпиясөз',
          icon: Icons.lock_outline_rounded,
          obscure: _obscureCur,
          suffix: GestureDetector(
            onTap: () => setState(() => _obscureCur = !_obscureCur),
            child: Icon(
                _obscureCur
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                color: cInk3,
                size: 20),
          ),
        ),
        _SecurityField(
          controller: _newCtrl,
          label: 'Жаңа құпиясөз',
          hint: 'Кемінде 6 таңба',
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
          label: 'Жаңа құпиясөзді қайталаңыз',
          hint: 'Қайталаңыз',
          icon: Icons.lock_reset_rounded,
          obscure: _obscureNew,
        ),
        if (_error != null) _SheetError(_error!),
        QPrimaryButton(
          label: 'Сақтау',
          isLoading: _loading,
          onPressed: _submit,
        ),
      ],
    );
  }
}
