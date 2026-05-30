import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../data/services/auth_service.dart';
import '../../theme/qoima_design.dart';
import 'client_register_screen.dart';
import 'login_screen.dart';

class ClientLoginScreen extends StatefulWidget {
  const ClientLoginScreen({super.key});

  @override
  State<ClientLoginScreen> createState() => _ClientLoginScreenState();
}

class _ClientLoginScreenState extends State<ClientLoginScreen> {
  final _authService = AuthService();
  final _phoneCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();

  bool _isLoading = false;
  bool _otpSent = false;
  String? _verificationId;
  String? _errorMessage;

  Timer? _resendTimer;
  int _resendSeconds = 0;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _otpCtrl.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  void _startResendTimer() {
    _resendTimer?.cancel();
    setState(() => _resendSeconds = 42);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      if (_resendSeconds <= 1) {
        t.cancel();
        setState(() => _resendSeconds = 0);
      } else {
        setState(() => _resendSeconds--);
      }
    });
  }

  String get _timerText {
    final m = _resendSeconds ~/ 60;
    final s = _resendSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  String get _fullPhone => '+7${_phoneCtrl.text.trim()}';

  Future<void> _sendOtp() async {
    final phone = _phoneCtrl.text.trim();
    if (phone.length < 10) {
      setState(() => _errorMessage = 'Введите полный номер телефона');
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    await _authService.verifyPhone(
      phoneNumber: _fullPhone,
      onCodeSent: (verificationId) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _verificationId = verificationId;
              _otpSent = true;
              _isLoading = false;
            });
            _startResendTimer();
          }
        });
      },
      onError: (error) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _errorMessage = error;
              _isLoading = false;
            });
          }
        });
      },
    );
  }

  Future<void> _verifyOtp() async {
    final code = _otpCtrl.text.trim();
    if (code.length != 6) {
      setState(() => _errorMessage = 'Введите 6-значный код из SMS');
      return;
    }
    if (_verificationId == null) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final cred = await _authService.signInWithOtp(
        verificationId: _verificationId!,
        smsCode: code,
      );
      final uid = cred.user?.uid;
      if (uid == null || !mounted) return;

      final existing = await _authService.getClientDoc(uid);
      if (!mounted) return;

      if (existing != null) {
        Navigator.of(context).popUntil((route) => route.isFirst);
        return;
      }

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ClientRegisterScreen(uid: uid, phone: _fullPhone),
        ),
      );
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = AuthService.parsePhoneError(e);
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Неизвестная ошибка';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cBg,
      body: _otpSent ? _buildOtpScreen() : _buildLoginScreen(),
    );
  }

  // ── Login screen ─────────────────────────────────────────────────────────────
  Widget _buildLoginScreen() {
    return Column(children: [
      // Top gradient area
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

      // White bottom sheet
      Container(
        decoration: const BoxDecoration(
          color: cSurface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        padding: EdgeInsets.fromLTRB(
            22, 26, 22, MediaQuery.of(context).viewInsets.bottom + 30),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Вход в аккаунт',
                style: manrope(21, FontWeight.w800, color: cInk)),
            const SizedBox(height: 14),
            _buildPhoneField(),
            const SizedBox(height: 14),
            QPrimaryButton(
              label: 'Получить код',
              isLoading: _isLoading,
              onPressed: _sendOtp,
              icon: const Icon(Icons.chevron_right_rounded,
                  color: Colors.white, size: 20),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 10),
              _ErrorBox(_errorMessage!),
            ],
            const SizedBox(height: 16),
            Container(height: 1, color: cLine),
            const SizedBox(height: 14),
            Center(
              child: GestureDetector(
                onTap: () => Navigator.push(
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
    ]);
  }

  Widget _buildPhoneField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Номер телефона',
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
            const Icon(Icons.phone_outlined, color: cInk3, size: 19),
            const SizedBox(width: 10),
            Text('+7 ', style: manrope(15, FontWeight.w600, color: cInk)),
            Expanded(
              child: TextField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                maxLength: 10,
                style: manrope(15, FontWeight.w600, color: cInk),
                cursorColor: cGreen,
                decoration: InputDecoration(
                  hintText: '700 000 00 00',
                  hintStyle: manrope(15, FontWeight.w500, color: cInk3),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  counterText: '',
                  contentPadding: EdgeInsets.zero,
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 14),
          ]),
        ),
      ],
    );
  }

  // ── OTP screen ───────────────────────────────────────────────────────────────
  Widget _buildOtpScreen() {
    return Column(children: [
      QGradientHeader(
        title: 'Подтверждение',
        subtitle: _fullPhone,
        showBack: true,
      ),
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Мы отправили SMS с 6-значным кодом на ваш номер',
                style: manrope(14.5, FontWeight.w500, color: cInk2, height: 1.5),
              ),
              const SizedBox(height: 20),
              _OtpField(controller: _otpCtrl),
              const SizedBox(height: 20),
              Center(
                child: _resendSeconds > 0
                    ? RichText(
                        text: TextSpan(
                          style: manrope(14, FontWeight.w600, color: cInk3),
                          children: [
                            const TextSpan(text: 'Отправить повторно через '),
                            TextSpan(
                                text: _timerText,
                                style: manrope(14, FontWeight.w700,
                                    color: cGreen)),
                          ],
                        ),
                      )
                    : GestureDetector(
                        onTap: _isLoading ? null : _sendOtp,
                        child: Text('Отправить повторно',
                            style: manrope(14, FontWeight.w700, color: cGreen)),
                      ),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 14),
                _ErrorBox(_errorMessage!),
              ],
              const SizedBox(height: 24),
              QPrimaryButton(
                label: 'Подтвердить',
                isLoading: _isLoading,
                onPressed: _verifyOtp,
              ),
              const SizedBox(height: 12),
              Center(
                child: GestureDetector(
                  onTap: _isLoading
                      ? null
                      : () => setState(() {
                            _otpSent = false;
                            _verificationId = null;
                            _otpCtrl.clear();
                            _errorMessage = null;
                          }),
                  child: Text('Изменить номер',
                      style: manrope(14, FontWeight.w600, color: cInk2)),
                ),
              ),
            ],
          ),
        ),
      ),
    ]);
  }
}

// ── OTP 6-cell field ──────────────────────────────────────────────────────────
class _OtpField extends StatelessWidget {
  final TextEditingController controller;
  const _OtpField({required this.controller});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 60,
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        maxLength: 6,
        textAlign: TextAlign.center,
        style: manrope(24, FontWeight.w800, color: cInk, letterSpacing: 14),
        decoration: InputDecoration(
          hintText: '------',
          hintStyle: manrope(22, FontWeight.w400, color: cInk3, letterSpacing: 10),
          counterText: '',
          filled: true,
          fillColor: cSurface,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: const BorderSide(color: cLine, width: 1.5)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: const BorderSide(color: cLine, width: 1.5)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: const BorderSide(color: cGreen, width: 1.5)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        ),
      ),
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
