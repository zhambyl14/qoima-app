import 'package:flutter/material.dart';
import '../../core/kz_cities.dart';
import '../../core/lang.dart';
import '../../data/services/auth_service.dart';
import '../../theme/qoima_design.dart';
import 'auth_widgets.dart';
import 'telegram_verify_button.dart';

/// Сатып алушыны тіркеу — 4 қадамдық шебер:
/// 1) аты · 2) құпиясөз (2 рет) · 3) қала · 4) телефонды Telegram-мен растау.
class ClientRegisterScreen extends StatefulWidget {
  const ClientRegisterScreen({super.key});

  @override
  State<ClientRegisterScreen> createState() => _ClientRegisterScreenState();
}

class _ClientRegisterScreenState extends State<ClientRegisterScreen> {
  static const _stepCount = 4;

  final _authService = AuthService();
  final _nameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  int _step = 0;
  String? _selectedCity;
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

  /// Ағымдағы қадамды тексеріп, келесіге өтеді (соңғы қадамда — тіркейді).
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
        if (_selectedCity == null) {
          return _setErr(tr('Выберите город', 'Қаланы таңдаңыз'));
        }
        break;
      case 3:
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
      await _authService.registerClient(
        phoneNumber: _verifiedPhone!,
        password: _passwordCtrl.text,
        name: _nameCtrl.text.trim(),
        city: _selectedCity!,
      );
      // Сессия бірден басталды — реактивті gate ClientShell-ге ауыстырады.
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } on AuthFailure catch (e) {
      _setErr(e.message);
    } catch (e) {
      _setErr(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  bool get _canSubmit => _step != 3 || _verifiedPhone != null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cBg,
      body: Column(children: [
        AuthWizardHeader(
          title: tr('Регистрация покупателя', 'Сатып алушыны тіркеу'),
          subtitle: tr('Создание аккаунта клиента', 'Клиент аккаунтын жасау'),
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
            AuthStepTitle(tr('Как вас зовут?', 'Атыңыз кім?'),
                hint: tr('Введите имя для профиля',
                    'Профиль үшін атыңызды енгізіңіз')),
            const SizedBox(height: 20),
            AuthField(
              controller: _nameCtrl,
              label: tr('Ваше имя', 'Атыңыз'),
              hint: tr('Например: Алия', 'Мысалы: Алия'),
              icon: Icons.person_outline_rounded,
              capitalization: TextCapitalization.words,
              autofocus: true,
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
              hint: tr('Минимум 6 символов', 'Кемінде 6 таңба'),
              autofocus: true,
            ),
            const SizedBox(height: 16),
            AuthPasswordField(
              controller: _confirmCtrl,
              label: tr('Повторите пароль', 'Құпиясөзді қайталаңыз'),
              hint: tr('Повторите пароль', 'Құпиясөзді қайталаңыз'),
            ),
          ],
        );
      case 2:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AuthStepTitle(tr('Ваш город', 'Қалаңыз'),
                hint: tr('Выберите город доставки',
                    'Жеткізу қаласын таңдаңыз')),
            const SizedBox(height: 20),
            Text(tr('Ваш город', 'Қалаңыз'),
                style: manrope(13, FontWeight.w700, color: kFieldLabel)),
            const SizedBox(height: 7),
            Container(
              decoration: BoxDecoration(
                color: cSurface,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(
                    color: _selectedCity != null ? cGreen : cLine,
                    width: 1.5),
              ),
              child: DropdownButtonFormField<String>(
                initialValue: _selectedCity,
                isExpanded: true,
                icon: const Icon(Icons.expand_more_rounded, color: cInk3),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.location_city_outlined,
                      color: cGreen, size: 20),
                  hintText: tr('Выберите город', 'Қаланы таңдаңыз'),
                  hintStyle: manrope(15, FontWeight.w500, color: cInk3),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
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
                  _selectedCity = v;
                  _error = null;
                }),
              ),
            ),
          ],
        );
      case 3:
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
