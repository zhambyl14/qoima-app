import 'package:flutter/material.dart';
import '../../core/lang.dart';
import '../../theme/qoima_design.dart';
import 'auth_widgets.dart';
import 'client_register_screen.dart';
import 'register_screen.dart';

/// Тіркелудің бастапқы беті: аккаунт түрін таңдау —
/// Покупатель (клиент) немесе Продавец / магазин.
class RegisterChooserScreen extends StatelessWidget {
  const RegisterChooserScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cBg,
      body: Column(children: [
        AuthWizardHeader(
          title: tr('Регистрация', 'Тіркелу'),
          subtitle: tr('Выберите тип аккаунта', 'Аккаунт түрін таңдаңыз'),
          showLang: true,
          onBack: () => Navigator.pop(context),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
                22, 24, 22, MediaQuery.of(context).padding.bottom + 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _RoleCard(
                  icon: Icons.shopping_bag_outlined,
                  title: tr('Покупатель', 'Сатып алушы'),
                  subtitle: tr('Поиск и покупка обуви онлайн',
                      'Онлайн іздеу және сатып алу'),
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const ClientRegisterScreen())),
                ),
                const SizedBox(height: 16),
                _RoleCard(
                  icon: Icons.storefront_outlined,
                  title: tr('Продавец / магазин', 'Сатушы / дүкен'),
                  subtitle: tr('Учёт товара и онлайн-продажи',
                      'Тауар есебі және онлайн-сатылым'),
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const RegisterScreen())),
                ),
                const SizedBox(height: 24),
                Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(tr('Уже есть аккаунт?', 'Аккаунтыңыз бар ма?'),
                          style: manrope(14, FontWeight.w600, color: cInk2)),
                      const SizedBox(width: 5),
                      GestureDetector(
                        onTap: () => popToLogin(context),
                        child: Text(tr('Войти', 'Кіру'),
                            style:
                                manrope(14, FontWeight.w800, color: cGreen)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ]),
    );
  }
}

// ── Рөл картасы (үлкен) ───────────────────────────────────────────────────────
class _RoleCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _RoleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: cSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: cLine, width: 1.5),
          boxShadow: kShadowSm,
        ),
        child: Row(children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
                color: cGreenTint, borderRadius: BorderRadius.circular(16)),
            child: Icon(icon, color: cGreen, size: 29),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: manrope(17, FontWeight.w800, color: cInk)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: manrope(13, FontWeight.w500, color: cInk2,
                        height: 1.35)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right_rounded, color: cInk3, size: 24),
        ]),
      ),
    );
  }
}
