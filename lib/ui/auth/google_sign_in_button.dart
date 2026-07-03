import 'package:flutter/material.dart';
import '../../data/services/auth_service.dart';
import '../../theme/qoima_design.dart';

/// «Google арқылы жалғастыру» батырмасы + «немесе» бөлгіші.
/// Кіру де, тіркелу де бір ағын: Google сессиясы ашылады → профилі жоқ болса
/// gate CompleteProfileScreen көрсетеді (рөл + телефон/қала), бар болса —
/// бірден өз экранына өтеді.
class GoogleSignInButton extends StatefulWidget {
  /// Сәтті кіргеннен кейін (gate ауысуының алдында) шақырылады.
  final VoidCallback? afterLogin;
  const GoogleSignInButton({super.key, this.afterLogin});

  @override
  State<GoogleSignInButton> createState() => _GoogleSignInButtonState();
}

class _GoogleSignInButtonState extends State<GoogleSignInButton> {
  bool _loading = false;

  Future<void> _signIn() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      await AuthService().signInWithGoogle();
      if (!mounted) return;
      widget.afterLogin?.call();
      // Сессия ашылды — түбірге ораламыз, реактивті gate маршрутты шешеді
      // (профилі жоқ болса — тіркелуді аяқтау экраны).
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on AuthFailure catch (e) {
      if (!mounted || e.code == 'cancelled') return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.message),
        backgroundColor: cRed,
        behavior: SnackBarBehavior.floating,
      ));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Google арқылы кіру сәтсіз болды'),
        backgroundColor: cRed,
        behavior: SnackBarBehavior.floating,
      ));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      // ── «немесе» бөлгіші ────────────────────────────────────────────────
      Row(children: [
        Expanded(child: Container(height: 1, color: cLine)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child:
              Text('немесе', style: manrope(12.5, FontWeight.w500, color: cInk3)),
        ),
        Expanded(child: Container(height: 1, color: cLine)),
      ]),
      const SizedBox(height: 14),

      // ── Google батырмасы ────────────────────────────────────────────────
      SizedBox(
        width: double.infinity,
        height: 52,
        child: OutlinedButton(
          onPressed: _loading ? null : _signIn,
          style: OutlinedButton.styleFrom(
            backgroundColor: cSurface,
            side: const BorderSide(color: cLine, width: 1.5),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15)),
          ),
          child: _loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child:
                      CircularProgressIndicator(color: cGreen, strokeWidth: 2))
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const _GoogleLogo(),
                    const SizedBox(width: 10),
                    Text('Google арқылы жалғастыру',
                        style: manrope(14.5, FontWeight.w700, color: cInk)),
                  ],
                ),
        ),
      ),
    ]);
  }
}

/// Google «G» логотипі (asset-сіз, төрт түсті сегменттермен).
class _GoogleLogo extends StatelessWidget {
  const _GoogleLogo();

  @override
  Widget build(BuildContext context) =>
      const SizedBox(width: 20, height: 20, child: CustomPaint(painter: _GPainter()));
}

class _GPainter extends CustomPainter {
  const _GPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final stroke = size.width * 0.20;
    final r = (size.width - stroke) / 2;
    final c = size.center(Offset.zero);
    final arcRect = Rect.fromCircle(center: c, radius: r);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;

    // Төрт доға: қызыл (жоғары), сары (сол-төмен), жасыл (төмен), көк (оң).
    paint.color = const Color(0xFFEA4335); // red
    canvas.drawArc(arcRect, -2.35, 1.55, false, paint);
    paint.color = const Color(0xFFFBBC05); // yellow
    canvas.drawArc(arcRect, 2.35, 1.15, false, paint);
    paint.color = const Color(0xFF34A853); // green
    canvas.drawArc(arcRect, 0.8, 1.55, false, paint);
    paint.color = const Color(0xFF4285F4); // blue
    canvas.drawArc(arcRect, -0.05, 0.85, false, paint);
    // Көк көлденең сызық (G-дің «құйрығы»)
    canvas.drawRect(
        Rect.fromLTWH(c.dx, c.dy - stroke / 2, rect.width / 2 - stroke / 4,
            stroke),
        Paint()..color = const Color(0xFF4285F4));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
