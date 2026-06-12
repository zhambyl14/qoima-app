import 'dart:async';
import 'package:flutter/material.dart';
import '../../data/services/auth_service.dart';
import '../../theme/qoima_design.dart';

/// «Поштаңызды тексеріңіз» экраны — тіркелуден кейін көрсетіледі.
/// [Қайта жіберу] растау сілтемесін қайта жібереді (қайта кіріп-шығу арқылы).
class VerifyEmailScreen extends StatefulWidget {
  final String email;
  final String password;
  const VerifyEmailScreen({
    super.key,
    required this.email,
    required this.password,
  });

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  final _authService = AuthService();
  bool _sending = false;
  int _cooldown = 0;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _cooldown = 45);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_cooldown <= 1) {
        t.cancel();
        setState(() => _cooldown = 0);
      } else {
        setState(() => _cooldown--);
      }
    });
  }

  Future<void> _resend() async {
    setState(() => _sending = true);
    try {
      await _authService.resendVerification(
        email: widget.email,
        password: widget.password,
      );
      if (!mounted) return;
      _startCooldown();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Растау сілтемесі қайта жіберілді'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: cGreen,
      ));
    } on AuthFailure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: cRed,
        ));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cBg,
      body: Column(children: [
        QGradientHeader(
          title: 'Поштаны растау',
          showBack: true,
          onBack: () => Navigator.pop(context),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 28, 22, 30),
            child: Column(children: [
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  color: cGreenTint,
                  borderRadius: BorderRadius.circular(26),
                ),
                child: const Icon(Icons.mark_email_unread_outlined,
                    color: cGreen, size: 40),
              ),
              const SizedBox(height: 22),
              Text('Поштаңызды тексеріңіз',
                  style: manrope(20, FontWeight.w800, color: cInk),
                  textAlign: TextAlign.center),
              const SizedBox(height: 10),
              Text(
                'Растау сілтемесі ${widget.email} адресіне жіберілді.',
                style: manrope(14.5, FontWeight.w500, color: cInk2, height: 1.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                'Сілтемені басып, осы экранға қайта оралыңыз да, кіріңіз.',
                style: manrope(13, FontWeight.w500, color: cInk3, height: 1.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 30),

              // Қайта жіберу
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton(
                  onPressed: (_sending || _cooldown > 0) ? null : _resend,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: cGreen,
                    side: const BorderSide(color: cGreen, width: 1.5),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15)),
                  ),
                  child: _sending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              color: cGreen, strokeWidth: 2))
                      : Text(
                          _cooldown > 0
                              ? 'Қайта жіберу ($_cooldown)'
                              : 'Қайта жіберу',
                          style:
                              manrope(15, FontWeight.w700, color: cGreen)),
                ),
              ),
              const SizedBox(height: 12),

              // Кіру экранына өту
              QPrimaryButton(
                label: 'Кіруге өту',
                onPressed: () => Navigator.pop(context),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
