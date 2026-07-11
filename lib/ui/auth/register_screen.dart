import 'package:flutter/material.dart';
import '../../core/l10n_ext.dart';
import '../../core/lang.dart';
import '../../data/services/auth_service.dart';
import '../../theme/qoima_design.dart';
import 'telegram_verify_button.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _nameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _authService = AuthService();

  String _role = 'admin'; // 'admin' | 'seller'
  String? _verifiedPhone; // Telegram-мен расталған нөмір (E.164)
  bool _isLoading = false;
  bool _obscurePass = true;
  bool _obscureConfirm = true;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    final l = context.l10n;
    if (_nameCtrl.text.trim().isEmpty) {
      _setErr(l.validationNameRequired);
      return;
    }
    if (_verifiedPhone == null) {
      _setErr(tr('Подтвердите номер через Telegram', 'Нөмірді Telegram арқылы растаңыз'));
      return;
    }
    if (_passwordCtrl.text.length < 6) {
      _setErr(l.validationPasswordMin);
      return;
    }
    if (_passwordCtrl.text != _confirmCtrl.text) {
      _setErr(l.validationPasswordMatch);
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      await _authService.register(
        name: _nameCtrl.text.trim(),
        phoneNumber: _verifiedPhone!,
        password: _passwordCtrl.text,
        role: _role,
      );
      // Сессия бірден басталды — түбір экранға ораламыз, реактивті gate
      // рөл бойынша дұрыс экранға ауыстырады.
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

  void _setErr(String msg) => setState(() => _error = msg);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cBg,
      body: SafeArea(
        child: CustomScrollView(slivers: [
          // ── Header ────────────────────────────────────────────────────
          SliverToBoxAdapter(
              child: Container(
            decoration: const BoxDecoration(
                gradient: LinearGradient(
                    colors: [Color(0xFF00713F), Color(0xFF00A862)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight)),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10)),
                      child: const Icon(Icons.arrow_back_ios_new,
                          color: Colors.white, size: 16))),
              const SizedBox(height: 20),
              Text(context.l10n.createAccount,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5)),
              const SizedBox(height: 4),
              Text(context.l10n.fillDetails,
                  style: const TextStyle(color: Colors.white60, fontSize: 14)),
            ]),
          )),

          SliverPadding(
            padding: const EdgeInsets.all(20),
            sliver: SliverList(
                delegate: SliverChildListDelegate([
              // ── Рөл таңдау ────────────────────────────────────────────
              Text(context.l10n.chooseRole,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: cInk)),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                    child: _RoleTile(
                  icon: Icons.storefront_rounded,
                  title: context.l10n.adminRole,
                  subtitle: context.l10n.adminRoleSubtitle,
                  selected: _role == 'admin',
                  onTap: () => setState(() => _role = 'admin'),
                )),
                const SizedBox(width: 12),
                Expanded(
                    child: _RoleTile(
                  icon: Icons.badge_outlined,
                  title: context.l10n.sellerRole,
                  subtitle: context.l10n.sellerRoleSubtitle,
                  selected: _role == 'seller',
                  onTap: () => setState(() => _role = 'seller'),
                )),
              ]),

              if (_role == 'seller') ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: cGreen.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: cGreen.withValues(alpha: 0.08))),
                  child: Row(children: [
                    const Icon(Icons.info_outline_rounded,
                        color: cGreen, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(
                      context.l10n.sellerRegisterHint,
                      style: const TextStyle(
                          fontSize: 12, color: cGreen),
                    )),
                  ]),
                ),
              ],
              const SizedBox(height: 18),

              // ── Деректер ─────────────────────────────────────────────
              _buildField(
                  controller: _nameCtrl,
                  label: context.l10n.yourName,
                  hint: context.l10n.namePlaceholder,
                  icon: Icons.person_outline_rounded),
              const SizedBox(height: 14),
              // Телефон — Telegram арқылы расталады (қолмен жазылмайды)
              Text(tr('Номер телефона', 'Телефон нөмірі'),
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700, color: cInk)),
              const SizedBox(height: 8),
              TelegramVerifyButton(
                onVerified: (phone, _) =>
                    setState(() => _verifiedPhone = phone),
              ),
              const SizedBox(height: 14),
              _buildField(
                  controller: _passwordCtrl,
                  label: context.l10n.password,
                  hint: context.l10n.passwordPlaceholder,
                  icon: Icons.lock_outline_rounded,
                  obscure: _obscurePass,
                  suffixIcon: IconButton(
                      icon: Icon(
                          _obscurePass
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          color: cInk3,
                          size: 20),
                      onPressed: () =>
                          setState(() => _obscurePass = !_obscurePass))),
              const SizedBox(height: 14),
              _buildField(
                  controller: _confirmCtrl,
                  label: context.l10n.confirmPassword,
                  hint: context.l10n.confirmPasswordPlaceholder,
                  icon: Icons.lock_outline_rounded,
                  obscure: _obscureConfirm,
                  suffixIcon: IconButton(
                      icon: Icon(
                          _obscureConfirm
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          color: cInk3,
                          size: 20),
                      onPressed: () =>
                          setState(() => _obscureConfirm = !_obscureConfirm))),
              const SizedBox(height: 16),

              // ── Қате ─────────────────────────────────────────────────
              if (_error != null)
                Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: cRedTint,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: cRed.withValues(alpha: 0.3))),
                    child: Row(children: [
                      const Icon(Icons.error_outline,
                          color: cRed, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(_error!,
                              style: const TextStyle(
                                  color: cRed, fontSize: 13))),
                    ])),
              const SizedBox(height: 20),

              // ── Кнопка ───────────────────────────────────────────────
              SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                      onPressed: _isLoading ? null : _register,
                      style: ElevatedButton.styleFrom(
                          backgroundColor: cGreen,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                          elevation: 0),
                      child: _isLoading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2))
                          : Text(context.l10n.register,
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w700)))),
              const SizedBox(height: 16),

              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(context.l10n.haveAccount,
                    style: const TextStyle(color: cInk2)),
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(context.l10n.signIn,
                        style: const TextStyle(
                            color: cGreen,
                            fontWeight: FontWeight.w700))),
              ]),
            ])),
          ),
        ]),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool obscure = false,
    Widget? suffixIcon,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      style: const TextStyle(fontSize: 15, color: cInk),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: const TextStyle(color: cInk3, fontSize: 14),
        prefixIcon: Icon(icon, color: cGreen, size: 20),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: cLine)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: cLine)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: cGreen, width: 1.5)),
      ),
    );
  }
}

// ── Рөл картасы ───────────────────────────────────────────────────────────────
class _RoleTile extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _RoleTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? cGreen.withValues(alpha: 0.08)
              : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: selected ? cGreen : cLine,
              width: selected ? 2 : 1),
          boxShadow: selected
              ? [
                  BoxShadow(
                      color: cGreen.withValues(alpha: 0.08),
                      blurRadius: 8,
                      offset: const Offset(0, 2))
                ]
              : [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 6,
                      offset: const Offset(0, 2))
                ],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon,
              color: selected ? cGreen : cInk3, size: 26),
          const SizedBox(height: 8),
          Text(title,
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: selected ? cGreen : cInk)),
          Text(subtitle,
              style:
                  const TextStyle(fontSize: 11, color: cInk2)),
          const SizedBox(height: 4),
          if (selected)
            Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                    color: cGreen,
                    borderRadius: BorderRadius.circular(4)),
                child: Text(context.l10n.selected,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w600))),
        ]),
      ),
    );
  }
}
