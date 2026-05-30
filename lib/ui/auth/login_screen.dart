import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/l10n_ext.dart';
import '../../data/services/auth_service.dart';
import '../../theme/qoima_design.dart';
import 'register_screen.dart';
import 'client_login_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _authService = AuthService();

  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      await _authService.signIn(
        email: _emailCtrl.text,
        password: _passwordCtrl.text,
      );
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } on FirebaseAuthException catch (e) {
      setState(() => _errorMessage = AuthService.parseError(e));
    } catch (_) {
      if (mounted) setState(() => _errorMessage = context.l10n.unknownError);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cBg,
      body: Column(children: [
        // ── Gradient hero ─────────────────────────────────────────────
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

        // ── White bottom sheet ────────────────────────────────────────
        Container(
          decoration: const BoxDecoration(
            color: cSurface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
          ),
          padding: EdgeInsets.fromLTRB(
              22, 26, 22, MediaQuery.of(context).viewInsets.bottom + 30),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Вход продавца',
                    style: manrope(21, FontWeight.w800, color: cInk)),
                const SizedBox(height: 14),

                // Email
                _buildField(
                  controller: _emailCtrl,
                  label: context.l10n.email,
                  icon: Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return context.l10n.validationEmailRequired;
                    }
                    if (!v.contains('@')) return context.l10n.validationEmail;
                    return null;
                  },
                ),
                const SizedBox(height: 10),

                // Password
                _buildField(
                  controller: _passwordCtrl,
                  label: context.l10n.password,
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
                  validator: (v) {
                    if (v == null || v.isEmpty) {
                      return context.l10n.validationPasswordRequired;
                    }
                    if (v.length < 6) return context.l10n.validationPasswordMin;
                    return null;
                  },
                ),

                if (_errorMessage != null) ...[
                  const SizedBox(height: 10),
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
                          child: Text(_errorMessage!,
                              style: manrope(13, FontWeight.w500, color: cRed))),
                    ]),
                  ),
                ],

                const SizedBox(height: 14),
                QPrimaryButton(
                  label: context.l10n.signIn,
                  isLoading: _isLoading,
                  onPressed: _signIn,
                ),

                const SizedBox(height: 16),
                Container(height: 1, color: cLine),
                const SizedBox(height: 14),

                // Register link
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(context.l10n.noAccount,
                      style: manrope(13.5, FontWeight.w500, color: cInk2)),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(
                            builder: (_) => const RegisterScreen())),
                    child: Text(context.l10n.register,
                        style: manrope(13.5, FontWeight.w700, color: cGreen)),
                  ),
                ]),
                const SizedBox(height: 8),

                // Client login link
                Center(
                  child: GestureDetector(
                    onTap: () => Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const ClientLoginScreen())),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.person_outline_rounded,
                            color: cGreen, size: 18),
                        const SizedBox(width: 7),
                        Text('Войти как клиент',
                            style: manrope(14, FontWeight.w600, color: cInk2)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ]),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    bool obscureText = false,
    Widget? suffix,
    String? Function(String?)? validator,
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
              child: TextFormField(
                controller: controller,
                keyboardType: keyboardType,
                obscureText: obscureText,
                style: manrope(15, FontWeight.w600, color: cInk),
                validator: validator,
                cursorColor: cGreen,
                decoration: InputDecoration(
                  hintText: label,
                  hintStyle: manrope(15, FontWeight.w500, color: cInk3),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  focusedErrorBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  isDense: true,
                  errorStyle: const TextStyle(height: 0),
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
