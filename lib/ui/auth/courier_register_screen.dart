import 'package:flutter/material.dart';
import '../../core/kz_cities.dart';
import '../../core/lang.dart';
import '../../data/services/auth_service.dart';
import '../../theme/qoima_design.dart';
import 'auth_widgets.dart';
import 'telegram_verify_button.dart';
import '../../core/error_text.dart';

/// Курьерді тіркеу — 3 қадам: аты + қала · құпиясөз · телефонды растау.
///
/// Курьер дүкенге емес, ТІКЕЛЕЙ модераторға бағынады: ол бір қаладағы
/// бірнеше дүкеннің тапсырысын алып жүреді. Сондықтан тіркелген соң бірден
/// жұмысқа кірмейді — модератор бекітуін күтеді (courier_status='pending').
class CourierRegisterScreen extends StatefulWidget {
  const CourierRegisterScreen({super.key});

  @override
  State<CourierRegisterScreen> createState() => _CourierRegisterScreenState();
}

class _CourierRegisterScreenState extends State<CourierRegisterScreen> {
  static const _stepCount = 3;

  final _authService = AuthService();
  final _nameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  int _step = 0;
  String? _city;
  String? _verifiedPhone;
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
        if (_city == null) {
          return _setErr(tr('Выберите город работы', 'Жұмыс қалаңызды таңдаңыз'));
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
        role: 'courier',
        city: _city!,
      );
      // Сессия бірден басталады — gate «модератор бекітуін күтіңіз» экранына
      // өтеді (курьер әлі pending).
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } on AuthFailure catch (e) {
      _setErr(e.message);
    } catch (e) {
      _setErr(friendlyError(e));
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
          title: tr('Регистрация курьера', 'Курьерді тіркеу'),
          subtitle: tr('Доставляйте заказы по своему городу',
              'Өз қалаңызда тапсырыс жеткізіңіз'),
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
                  child: KeyedSubtree(key: ValueKey(_step), child: _stepBody()),
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
            AuthStepTitle(tr('О себе', 'Өзіңіз туралы'),
                hint: tr('Вы будете возить заказы по одному городу',
                    'Бір қала бойынша тапсырыс тасисыз')),
            const SizedBox(height: 16),
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
                    tr('После регистрации доступ откроет модератор — заказы появятся сразу после подтверждения.',
                        'Тіркелген соң рұқсатты модератор ашады — расталған бойда тапсырыстар шығады.'),
                    style: manrope(12, FontWeight.w600,
                        color: cGreenDeep, height: 1.4),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 20),
            AuthField(
              controller: _nameCtrl,
              label: tr('Ваше имя', 'Атыңыз'),
              hint: tr('Ваше имя', 'Атыңыз'),
              icon: Icons.person_outline_rounded,
              capitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
            ),
            const SizedBox(height: 16),
            Text(tr('Город работы', 'Жұмыс қаласы'),
                style: manrope(13, FontWeight.w700, color: kFieldLabel)),
            const SizedBox(height: 7),
            Container(
              decoration: BoxDecoration(
                color: cSurface,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(
                    color: _city != null ? cGreen : cLine, width: 1.5),
              ),
              child: DropdownButtonFormField<String>(
                initialValue: _city,
                isExpanded: true,
                icon: const Icon(Icons.expand_more_rounded, color: cInk3),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.location_city_outlined,
                      color: cGreen, size: 20),
                  hintText: tr('Выберите город', 'Қаланы таңдаңыз'),
                  hintStyle: manrope(15, FontWeight.w500, color: cInk3),
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  focusedErrorBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 15, horizontal: 6),
                  isDense: true,
                ),
                style: manrope(15, FontWeight.w600, color: cInk),
                dropdownColor: cSurface,
                borderRadius: BorderRadius.circular(14),
                items: kzCities
                    .map((c) => DropdownMenuItem(
                        value: c,
                        child: Text(trValue(c),
                            style:
                                manrope(15, FontWeight.w600, color: cInk))))
                    .toList(),
                onChanged: (v) => setState(() {
                  _city = v;
                  _error = null;
                }),
              ),
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
