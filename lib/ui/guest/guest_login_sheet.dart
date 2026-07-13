import 'package:flutter/material.dart';
import '../../core/lang.dart';
import '../../theme/qoima_design.dart';
import '../auth/auth_widgets.dart';
import '../auth/login_screen.dart';
import '../auth/register_chooser_screen.dart';

/// Гость «Войти и оформить» bottom sheet. Кіру біріңғай (телефон + пароль),
/// рөлді жүйе анықтайды — сондықтан бір ғана «Войти» әрекеті.
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
    final bottom = MediaQuery.of(context).viewInsets.bottom +
        MediaQuery.of(context).padding.bottom;
    return Container(
      decoration: const BoxDecoration(
        color: cSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(22, 6, 22, bottom + 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
                  tr('Ваша корзина сохранена и будет доступна после входа.',
                      'Себетіңіз сақталды, кіргеннен кейін қолжетімді болады.'),
                  style: manrope(13, FontWeight.w500,
                      color: cGreenDeep, height: 1.4),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 20),

          Text(tr('Войдите, чтобы оформить заказ',
              'Тапсырыс рәсімдеу үшін кіріңіз'),
              textAlign: TextAlign.center,
              style: manrope(19, FontWeight.w800,
                  color: cInk, letterSpacing: -0.3)),
          const SizedBox(height: 4),
          Text(
              tr('Единый вход для покупателей и продавцов',
                  'Сатып алушылар мен сатушыларға біріңғай кіру'),
              textAlign: TextAlign.center,
              style: manrope(13.5, FontWeight.w500, color: cInk2)),
          const SizedBox(height: 22),

          AuthPrimaryButton(
            label: tr('Войти', 'Кіру'),
            icon: Icons.login_rounded,
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => LoginScreen(afterLogin: onLoginSuccess),
                  settings: const RouteSettings(name: kLoginRouteName),
                ),
              );
            },
          ),
          const SizedBox(height: 14),

          Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(tr('Нет аккаунта?', 'Аккаунтыңыз жоқ па?'),
                    style: manrope(13.5, FontWeight.w600, color: cInk2)),
                const SizedBox(width: 5),
                GestureDetector(
                  onTap: () {
                    Navigator.pop(context);
                    // Логинді астына қоямыз — chooser/wizard-тен «Войти»
                    // біріңғай логинге дұрыс оралады ([popToLogin]).
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            LoginScreen(afterLogin: onLoginSuccess),
                        settings: const RouteSettings(name: kLoginRouteName),
                      ),
                    );
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const RegisterChooserScreen()),
                    );
                  },
                  child: Text(tr('Регистрация', 'Тіркелу'),
                      style: manrope(13.5, FontWeight.w800, color: cGreen)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('Продолжить как гость', 'Қонақ ретінде жалғастыру'),
                style: manrope(14, FontWeight.w600, color: cInk3)),
          ),
        ],
      ),
    );
  }
}
