import 'package:flutter/material.dart';
import '../../core/lang.dart';
import '../../data/services/auth_service.dart';
import '../../theme/qoima_design.dart';
import 'auth_widgets.dart';
import 'telegram_verify_button.dart';

/// Сатушы / магазинді тіркеу — 3 қадамдық шебер:
/// 1) рөл (владелец/продавец) + аты · 2) құпиясөз (2 рет) ·
/// 3) телефонды Telegram-мен растау.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  static const _stepCount = 3;

  final _authService = AuthService();
  final _nameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  int _step = 0;
  String _role = 'admin'; // 'admin' = владелец магазина · 'seller' = продавец
  String? _verifiedPhone; // Telegram-мен расталған E.164 нөмір
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  void _setErr(String? msg) => setState(() => _error = msg);

  void _back() {
    FocusScope.of(context).unfocus();
    if (_step == 0) {
      Navigator.pop(context);
    } else {
      setState(() {
        _step--;
        _error = null;
      });
    }
  }

  Future<void> _next() async {
    FocusScope.of(context).unfocus();
    switch (_step) {
      case 0:
        if (_nameCtrl.text.trim().length < 2) {
          return _setErr(tr('Введите имя (минимум 2 символа)',
              'Атыңызды енгізіңіз (кемінде 2 таңба)'));
        }
        break;
      case 1:
        if (_passwordCtrl.text.length < 6) {
          return _setErr(tr('Пароль должен быть не короче 6 символов',
              'Құпиясөз кем дегенде 6 таңба болуы керек'));
        }
        if (_passwordCtrl.text != _confirmCtrl.text) {
          return _setErr(
              tr('Пароли не совпадают', 'Құпиясөздер сәйкес келмейді'));
        }
        break;
      case 2:
        return _register();
    }
    setState(() {
      _step++;
      _error = null;
    });
  }

  Future<void> _register() async {
    if (_verifiedPhone == null) {
      return _setErr(tr('Подтвердите номер через Telegram',
          'Нөмірді Telegram арқылы растаңыз'));
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
      // Сессия бірден басталды — реактивті gate рөл бойынша дұрыс экранға өтеді.
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } on AuthFailure catch (e) {
      _setErr(e.message);
    } catch (e) {
      _setErr(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  bool get _canSubmit => _step != 2 || _verifiedPhone != null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cBg,
      body: Column(children: [
        AuthWizardHeader(
          title: tr('Регистрация магазина', 'Дүкенді тіркеу'),
          subtitle: tr('Выберите роль и заполните данные',
              'Рөлді таңдап, деректерді толтырыңыз'),
          step: _step,
          stepCount: _stepCount,
          onBack: _isLoading ? () {} : _back,
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
                22,
                24,
                22,
                MediaQuery.of(context).viewInsets.bottom +
                    MediaQuery.of(context).padding.bottom +
                    28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  switchInCurve: Curves.easeOutCubic,
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: SlideTransition(
                      position: Tween<Offset>(
                              begin: const Offset(0.05, 0), end: Offset.zero)
                          .animate(anim),
                      child: child,
                    ),
                  ),
                  child: KeyedSubtree(
                    key: ValueKey(_step),
                    child: _stepBody(),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  AuthErrorBox(_error!),
                ],
                const SizedBox(height: 24),
                AuthPrimaryButton(
                  label: _step == _stepCount - 1
                      ? tr('Зарегистрироваться', 'Тіркелу')
                      : tr('Далее', 'Келесі'),
                  isLoading: _isLoading,
                  enabled: _canSubmit,
                  onPressed: _next,
                ),
                const SizedBox(height: 16),
                Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(tr('Уже есть аккаунт?', 'Аккаунтыңыз бар ма?'),
                          style: manrope(13.5, FontWeight.w600, color: cInk2)),
                      const SizedBox(width: 5),
                      GestureDetector(
                        onTap: _isLoading ? null : () => popToLogin(context),
                        child: Text(tr('Войти', 'Кіру'),
                            style:
                                manrope(13.5, FontWeight.w800, color: cGreen)),
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

  Widget _stepBody() {
    switch (_step) {
      case 0:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AuthStepTitle(tr('Выберите роль', 'Рөлді таңдаңыз'),
                hint: tr('Кто вы в магазине?', 'Дүкенде сіз кімсіз?')),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: _RoleTile(
                  icon: Icons.storefront_rounded,
                  title: tr('Владелец', 'Иесі'),
                  subtitle: tr('Полный контроль', 'Толық басқару'),
                  selected: _role == 'admin',
                  onTap: () => setState(() => _role = 'admin'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _RoleTile(
                  icon: Icons.badge_outlined,
                  title: tr('Продавец', 'Сатушы'),
                  subtitle: tr('По приглашению', 'Шақыру бойынша'),
                  selected: _role == 'seller',
                  onTap: () => setState(() => _role = 'seller'),
                ),
              ),
            ]),
            if (_role == 'seller') ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cGreenTint,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(children: [
                  const Icon(Icons.info_outline_rounded,
                      color: cGreenDeep, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      tr('После регистрации отправьте запрос владельцу магазина, чтобы получить доступ.',
                          'Тіркелген соң қолжетімділік алу үшін дүкен иесіне сұраныс жіберіңіз.'),
                      style: manrope(12, FontWeight.w600,
                          color: cGreenDeep, height: 1.4),
                    ),
                  ),
                ]),
              ),
            ],
            const SizedBox(height: 20),
            AuthField(
              controller: _nameCtrl,
              label: tr('Ваше имя', 'Атыңыз'),
              hint: tr('Ваше имя', 'Атыңыз'),
              icon: Icons.person_outline_rounded,
              capitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _next(),
            ),
          ],
        );
      case 1:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AuthStepTitle(tr('Придумайте пароль', 'Құпиясөз ойлап табыңыз'),
                hint: tr('Минимум 6 символов', 'Кемінде 6 таңба')),
            const SizedBox(height: 20),
            AuthPasswordField(
              controller: _passwordCtrl,
              label: tr('Пароль', 'Құпиясөз'),
              hint: tr('Пароль', 'Құпиясөз'),
              autofocus: true,
            ),
            const SizedBox(height: 16),
            AuthPasswordField(
              controller: _confirmCtrl,
              label: tr('Подтвердите пароль', 'Құпиясөзді растаңыз'),
              hint: tr('Подтвердите пароль', 'Құпиясөзді растаңыз'),
            ),
          ],
        );
      case 2:
      default:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AuthStepTitle(tr('Подтвердите номер', 'Нөмірді растаңыз'),
                hint: tr('Телефон подтверждается через Telegram — без SMS',
                    'Телефон Telegram арқылы расталады — SMS-сіз')),
            const SizedBox(height: 20),
            Text(tr('Номер телефона', 'Телефон нөмірі'),
                style: manrope(13, FontWeight.w700, color: kFieldLabel)),
            const SizedBox(height: 8),
            TelegramVerifyButton(
              onVerified: (phone, _) => setState(() {
                _verifiedPhone = phone;
                _error = null;
              }),
            ),
          ],
        );
    }
  }
}

// ── Рөл картасы (кіші, қатарда екеу) ──────────────────────────────────────────
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
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
        decoration: BoxDecoration(
          color: selected ? cGreenTint : cSurface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
              color: selected ? cGreen : cLine, width: selected ? 2 : 1.5),
        ),
        child: Column(children: [
          Icon(icon, color: selected ? cGreen : cInk3, size: 26),
          const SizedBox(height: 8),
          Text(title, style: manrope(14, FontWeight.w800, color: cInk)),
          const SizedBox(height: 1),
          Text(subtitle,
              textAlign: TextAlign.center,
              style: manrope(11.5, FontWeight.w500, color: cInk2)),
          const SizedBox(height: 8),
          AnimatedOpacity(
            duration: const Duration(milliseconds: 160),
            opacity: selected ? 1 : 0,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.check_circle_rounded, color: cGreen, size: 15),
              const SizedBox(width: 4),
              Text(tr('Выбрано', 'Таңдалды'),
                  style: manrope(11, FontWeight.w800, color: cGreen)),
            ]),
          ),
        ]),
      ),
    );
  }
}
