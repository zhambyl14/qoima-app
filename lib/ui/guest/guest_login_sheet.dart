import 'package:flutter/material.dart';
import '../../theme/qoima_design.dart';
import '../auth/client_login_screen.dart';
import '../auth/login_screen.dart';

/// Guest «Войти и оформить» / «Войти» bottom sheet.
/// Phone → ClientLoginScreen (клиент: телефон + пароль).
/// Email → LoginScreen (продавец / владелец / модератор).
void showGuestLoginSheet(BuildContext context, {VoidCallback? onLoginSuccess}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => GuestLoginSheet(onLoginSuccess: onLoginSuccess),
  );
}

class GuestLoginSheet extends StatelessWidget {
  final VoidCallback? onLoginSuccess;
  const GuestLoginSheet({super.key, this.onLoginSuccess});

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      decoration: const BoxDecoration(
        color: cSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(22, 6, 22, bottom + 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                  color: cLine, borderRadius: BorderRadius.circular(2)),
            ),
          ),

          // Корзина сохранена
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cGreenTint,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Row(children: [
              const Icon(Icons.shopping_bag_outlined, color: cGreen, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Ваша корзина сохранена и будет доступна после входа.',
                  style: manrope(13, FontWeight.w500, color: cGreenDeep,
                      height: 1.4),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 20),

          Text('Войдите, чтобы оформить заказ',
              style: manrope(19, FontWeight.w800, color: cInk,
                  letterSpacing: -0.3)),
          const SizedBox(height: 4),
          Text('Выберите способ входа',
              style: manrope(13.5, FontWeight.w500, color: cInk2)),
          const SizedBox(height: 20),

          // Телефон — клиент
          _LoginOption(
            icon: Icons.phone_outlined,
            title: 'По номеру телефона',
            sub: 'Клиент — покупать товары',
            color: cGreen,
            tint: cGreenTint,
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ClientLoginScreen(
                      afterLogin: onLoginSuccess),
                ),
              );
            },
          ),
          const SizedBox(height: 12),

          // Email — продавец / владелец / суперадмин
          _LoginOption(
            icon: Icons.email_outlined,
            title: 'По Email',
            sub: 'Продавец, владелец или модератор',
            color: cBlue,
            tint: cBlueTint,
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => LoginScreen(afterLogin: onLoginSuccess),
                ),
              );
            },
          ),
          const SizedBox(height: 16),

          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Продолжить как гость',
                style: manrope(14, FontWeight.w600, color: cInk3)),
          ),
        ],
      ),
    );
  }
}

class _LoginOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String sub;
  final Color color;
  final Color tint;
  final VoidCallback onTap;
  const _LoginOption({
    required this.icon,
    required this.title,
    required this.sub,
    required this.color,
    required this.tint,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cLine, width: 1.3),
        ),
        child: Row(children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
                color: tint, borderRadius: BorderRadius.circular(13)),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: manrope(15, FontWeight.w700, color: cInk)),
                Text(sub,
                    style: manrope(12.5, FontWeight.w500, color: cInk3)),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: cInk3, size: 22),
        ]),
      ),
    );
  }
}
