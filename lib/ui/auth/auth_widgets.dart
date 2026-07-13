import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/locale_context.dart';
import '../../theme/qoima_design.dart';

/// Логин экранының маршрут аты — тіркелу ағынынан «Войти» сілтемесі осы
/// экранға дейін popUntil жасайды ([popToLogin]).
const String kLoginRouteName = 'auth/login';

/// Auth-тың жасыл градиенті (дизайн: 158° #0A7B3C → #12934A → #25A85E).
const LinearGradient kAuthGrad = LinearGradient(
  begin: Alignment.topRight,
  end: Alignment.bottomLeft,
  colors: [Color(0xFF25A85E), Color(0xFF12934A), Color(0xFF0A7B3C)],
  stops: [0.0, 0.5, 1.0],
);

/// Өріс белгісінің түсі (дизайн #3A423C).
const Color kFieldLabel = Color(0xFF3A423C);

/// Тіркелу ағынынан логинге дейін жоғарылату (chooser/wizard → login).
void popToLogin(BuildContext context) {
  Navigator.of(context)
      .popUntil((r) => r.settings.name == kLoginRouteName || r.isFirst);
}

// ── ҚАЗ/РУС тіл ауыстырғышы (жасыл фонда: логин + тіркелу бастапқы беттері) ────
class AuthLangSwitch extends StatelessWidget {
  const AuthLangSwitch({super.key});

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<LocaleContext>().locale.languageCode;
    final ctx = context.read<LocaleContext>();
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        _seg('ҚАЗ', lang == 'kk', () => ctx.setLocale(const Locale('kk'))),
        _seg('РУС', lang == 'ru', () => ctx.setLocale(const Locale('ru'))),
      ]),
    );
  }

  Widget _seg(String label, bool active, VoidCallback onTap) => GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
          decoration: BoxDecoration(
            color: active ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text(label,
              style: manrope(11.5, FontWeight.w800,
                  color: active ? cGreenDeep : Colors.white)),
        ),
      );
}

// ── Жапсырмалы енгізу өрісі (дизайн стилінде) ─────────────────────────────────
class AuthField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final TextCapitalization capitalization;
  final bool obscure;
  final bool autofocus;
  final Widget? suffix;
  final TextInputAction? textInputAction;
  final void Function(String)? onSubmitted;

  const AuthField({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.keyboardType,
    this.inputFormatters,
    this.capitalization = TextCapitalization.none,
    this.obscure = false,
    this.autofocus = false,
    this.suffix,
    this.textInputAction,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: manrope(13, FontWeight.w700, color: kFieldLabel)),
        const SizedBox(height: 7),
        Container(
          height: 54,
          decoration: BoxDecoration(
            color: cSurface,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: cLine, width: 1.5),
          ),
          child: Row(children: [
            const SizedBox(width: 15),
            Icon(icon, color: cGreen, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: controller,
                keyboardType: keyboardType,
                inputFormatters: inputFormatters,
                textCapitalization: capitalization,
                obscureText: obscure,
                autofocus: autofocus,
                textInputAction: textInputAction,
                onSubmitted: onSubmitted,
                style: manrope(15, FontWeight.w600, color: cInk),
                cursorColor: cGreen,
                decoration: InputDecoration(
                  hintText: hint,
                  hintStyle: manrope(15, FontWeight.w500, color: cInk3),
                  // Глобалды тема filled:true — оны өшіреміз, әйтпесе теманың
                  // тік бұрышты ақ толтыруы контейнердің дөңгелек бұрыштарынан
                  // асып, сұр фонға «қосымша қабат» болып көрінеді.
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  focusedErrorBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  isDense: true,
                ),
              ),
            ),
            if (suffix != null) ...[suffix!, const SizedBox(width: 8)],
          ]),
        ),
      ],
    );
  }
}

// ── Құпиясөз өрісі (көз батырмасын өзі басқарады) ─────────────────────────────
class AuthPasswordField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final bool autofocus;
  final TextInputAction? textInputAction;
  final void Function(String)? onSubmitted;

  const AuthPasswordField({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    this.autofocus = false,
    this.textInputAction,
    this.onSubmitted,
  });

  @override
  State<AuthPasswordField> createState() => _AuthPasswordFieldState();
}

class _AuthPasswordFieldState extends State<AuthPasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return AuthField(
      controller: widget.controller,
      label: widget.label,
      hint: widget.hint,
      icon: Icons.lock_outline_rounded,
      obscure: _obscure,
      autofocus: widget.autofocus,
      textInputAction: widget.textInputAction,
      onSubmitted: widget.onSubmitted,
      suffix: GestureDetector(
        onTap: () => setState(() => _obscure = !_obscure),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(
            _obscure
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
            color: cInk3,
            size: 21,
          ),
        ),
      ),
    );
  }
}

// ── Негізгі градиентті батырма (дизайн CTA) ───────────────────────────────────
class AuthPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool enabled;
  final IconData? icon;

  const AuthPrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.isLoading = false,
    this.enabled = true,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final active = enabled && !isLoading && onPressed != null;
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: active
              ? const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF16A653), Color(0xFF0E8B42)])
              : null,
          color: active ? null : cInk3.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(15),
          boxShadow: active
              ? [
                  BoxShadow(
                      color: const Color(0xFF0E8B42).withValues(alpha: 0.45),
                      blurRadius: 22,
                      offset: const Offset(0, 12))
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(15),
            onTap: active ? onPressed : null,
            child: Center(
              child: isLoading
                  ? const SizedBox(
                      width: 23,
                      height: 23,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.4))
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (icon != null) ...[
                          Icon(icon, color: Colors.white, size: 20),
                          const SizedBox(width: 9),
                        ],
                        Text(label,
                            style: manrope(16, FontWeight.w800,
                                color: Colors.white)),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Тіркелу шеберінің жасыл тақырыбы (артқа + тақырып + қадам нүктелері) ───────
class AuthWizardHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final VoidCallback onBack;

  /// Бастапқы бет (тіл ауыстырғыш көрсету).
  final bool showLang;

  /// Қадам индикаторы: [step] (0-негізді) және барлық [stepCount].
  final int? step;
  final int? stepCount;

  const AuthWizardHeader({
    super.key,
    required this.title,
    required this.onBack,
    this.subtitle,
    this.showLang = false,
    this.step,
    this.stepCount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: kAuthGrad),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                GestureDetector(
                  onTap: onBack,
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Icon(Icons.arrow_back_rounded,
                        color: Colors.white, size: 22),
                  ),
                ),
                const Spacer(),
                if (showLang) const AuthLangSwitch(),
              ]),
              const SizedBox(height: 16),
              Text(title,
                  style: manrope(23, FontWeight.w800,
                      color: Colors.white, letterSpacing: -0.4)),
              if (subtitle != null) ...[
                const SizedBox(height: 3),
                Text(subtitle!,
                    style: manrope(13, FontWeight.w500,
                        color: Colors.white.withValues(alpha: 0.85))),
              ],
              if (stepCount != null && step != null) ...[
                const SizedBox(height: 16),
                Row(
                  children: List.generate(stepCount!, (i) {
                    final done = i <= step!;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      margin: const EdgeInsets.only(right: 6),
                      width: i == step! ? 24 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: done
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.32),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    );
                  }),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Қате қорабы ───────────────────────────────────────────────────────────────
class AuthErrorBox extends StatelessWidget {
  final String message;
  const AuthErrorBox(this.message, {super.key});

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
              child: Text(message,
                  style: manrope(13, FontWeight.w500, color: cRed))),
        ]),
      );
}

// ── Қадам ішіндегі тақырып (үлкен) + көмекші мәтін ────────────────────────────
class AuthStepTitle extends StatelessWidget {
  final String title;
  final String? hint;
  const AuthStepTitle(this.title, {super.key, this.hint});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: manrope(21, FontWeight.w800, color: cInk)),
        if (hint != null) ...[
          const SizedBox(height: 4),
          Text(hint!,
              style: manrope(13.5, FontWeight.w500, color: cInk2, height: 1.4)),
        ],
      ],
    );
  }
}
