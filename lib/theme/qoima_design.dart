import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show SystemUiOverlayStyle, HapticFeedback;
import 'package:google_fonts/google_fonts.dart';

// ═════════════════════════════════════════════════════════════════════════════
// ҚОЙМА · ДИЗАЙН ЖҮЙЕСІ
// Бүкіл қосымшаның түсі, көлеңкесі, қарпі мен негізгі виджеттері ОСЫ файлда.
// Мұндағы бір токенді өзгерту — барлық экранға бірдей әсер етеді.
// ═════════════════════════════════════════════════════════════════════════════

// ── Color palette ─────────────────────────────────────────────────────────────
// Брендтік жасыл (лого/иконка #156945 отбасы) — зәйтүн емес, таза изумруд.
const cGreen = Color(0xFF00A862); // негізгі бренд түсі (мәтін/иконка/акцент)
const cGreenDeep = Color(0xFF00713F); // қанық — жасыл фондағы мәтін үшін
const cGreenBright =
    Color(0xFF16D888); // жарқын акцент (нүкте, glow, highlight)
const cGreenTint = Color(0xFFE9FBF2); // ашық төсеніш (бұрын E4F7EE — жарқыраты)
const cGreenTint2 = Color(0xFFD3F4E3); // тереңірек төсеніш / жиек

// Нейтралдар. cInk2/cInk3 әдейі қоюлатылды — 12-13px қосалқы мәтін
// ақ фонда оқылатын болуы үшін (ескі cInk3 контрасты 2.6:1 ғана еді).
const cInk = Color(0xFF0B1512); // басты мәтін
const cInk2 = Color(0xFF4A5F57); // қосалқы мәтін (≈6.8:1 — AA)
const cInk3 = Color(0xFF7C8F87); // үшінші дәреже: белгі, иконка, hint (≈3.4:1)
const cLine = Color(0xFFE9EFEC); // жиек
const cLine2 = Color(0xFFF3F7F5); // ең жеңіл төсеніш
const cBg = Color(0xFFF4F7F6); // экран фоны (бұрынғыдан жарық әрі тазарақ)
const cSurface = Color(0xFFFFFFFF);

// Семантикалық реңдер — қаныққан «негіз» + жарқын «төсеніш» + оқылатын «мәтін».
const cAmber = Color(0xFFFFA51F);
const cAmberTint = Color(0xFFFFF4DE);
const cAmberInk = Color(0xFF8F6103);
const cRed = Color(0xFFF23B4F);
const cRedTint = Color(0xFFFFEBEE);
const cRedInk = Color(0xFFC01B31);
const cBlue = Color(0xFF2F7DF6);
const cBlueTint = Color(0xFFE8F1FF);
const cBlueInk = Color(0xFF1558CE);
const cPurple = Color(0xFF7C5CFC);
const cPurpleTint = Color(0xFFEFEAFF);
const cPurpleInk = Color(0xFF5638D6);

// ── Radius scale ──────────────────────────────────────────────────────────────
const double kR8 = 8;
const double kR12 = 12;
const double kR14 = 14;
const double kR16 = 16;
const double kR20 = 20;
const double kR24 = 24;
const double kRPill = 999;

// ── Gradients ─────────────────────────────────────────────────────────────────
/// Хедер градиенті — қоюдан жарыққа қарай диагональ.
const kGrad = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF00693C), Color(0xFF00A862), Color(0xFF16CC80)],
  stops: [0.0, 0.52, 1.0],
);

/// Басты батырма — жарық жоғарыдан түсетіндей (жарық → қанық).
/// Ақ мәтіннің контрасты орта есеппен ~3.6:1 (жалғыз cGreen-де 3.1 еді).
const kGradBtn = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF00B96A), Color(0xFF00814B)],
);

/// Қауіпті әрекет батырмасы (өшіру/бас тарту).
const kGradDanger = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFFFF5A6B), Color(0xFFDE2038)],
);

// ── Shadows ───────────────────────────────────────────────────────────────────
// Екі қабатты: жақын «контакт» көлеңкесі + алыс жұмсақ «ортаң» көлеңкесі.
// Бір қабатты көлеңкеге қарағанда әлдеқайда табиғи әрі жұмсақ көрінеді.
const kShadowXs = [
  BoxShadow(color: Color(0x0A0B1512), blurRadius: 2, offset: Offset(0, 1)),
];
const kShadowSm = [
  BoxShadow(color: Color(0x0A0B1512), blurRadius: 3, offset: Offset(0, 1)),
  BoxShadow(color: Color(0x0D0B1512), blurRadius: 12, offset: Offset(0, 4)),
];
const kShadowMd = [
  BoxShadow(color: Color(0x0D0B1512), blurRadius: 4, offset: Offset(0, 2)),
  BoxShadow(color: Color(0x140B1512), blurRadius: 24, offset: Offset(0, 10)),
];
const kShadowLg = [
  BoxShadow(color: Color(0x100B1512), blurRadius: 8, offset: Offset(0, 4)),
  BoxShadow(color: Color(0x1A0B1512), blurRadius: 40, offset: Offset(0, 20)),
];

/// Түрлі-түсті «шуақ» — басты батырма мен жасыл беттердің астында.
const kShadowGreen = [
  BoxShadow(color: Color(0x4700A862), blurRadius: 22, offset: Offset(0, 9)),
  BoxShadow(color: Color(0x140B1512), blurRadius: 3, offset: Offset(0, 1)),
];
const kShadowRed = [
  BoxShadow(color: Color(0x40F23B4F), blurRadius: 22, offset: Offset(0, 9)),
  BoxShadow(color: Color(0x140B1512), blurRadius: 3, offset: Offset(0, 1)),
];

// ── Typography ────────────────────────────────────────────────────────────────
// Атауы тарихи «manrope» болып қалды (мыңдаған шақыру орны бар), бірақ
// қаріп ІШКІ түрде Inter-ге ауыстырылды: Manrope-тің қазақ әріптері
// (ә і ң ғ ү ұ қ ө) орыс/латын әріптерімен салыстырғанда әлсіз көрінетін —
// Inter-дің кеңейтілген кириллица жиынтығы бұл әріптерді әлдеқайда сапалы
// жобалайды, ал жалпы стилі (геометриялық sans) Manrope-қа жақын қалады.
//
// letterSpacing/height берілмесе — өлшемге қарай АВТОМАТ таңдалады:
// ірі тақырыптар тығызырақ (теріс tracking), ұсақ мәтін кеңірек әрі
// жолдар арасы ауқымды. Осының арқасында 1600+ шақыру орнының бәрі
// бірден типографиялық ырғаққа түседі.
TextStyle manrope(double size, FontWeight weight,
        {Color color = cInk, double? letterSpacing, double? height}) =>
    GoogleFonts.inter(
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: letterSpacing ?? _tracking(size),
      height: height ?? _leading(size),
    );

/// Әріп аралығы: қаріп неғұрлым ірі болса, соғұрлым тығыз (оптикалық түзету).
double _tracking(double s) {
  if (s >= 26) return -0.9;
  if (s >= 21) return -0.6;
  if (s >= 17) return -0.4;
  if (s >= 14) return -0.15;
  if (s >= 12) return 0;
  return 0.1;
}

/// Жол биіктігі: ұсақ мәтінге ауқымды, тақырыпқа жинақы.
double _leading(double s) {
  if (s >= 26) return 1.16;
  if (s >= 21) return 1.2;
  if (s >= 17) return 1.24;
  if (s >= 14) return 1.28;
  if (s >= 12) return 1.3;
  return 1.26;
}

// ── Money formatter ───────────────────────────────────────────────────────────
String money(double v) {
  final s = v.toStringAsFixed(0);
  final buf = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
    buf.write(s[i]);
  }
  buf.write(' ₸');
  return buf.toString();
}

// ── Pill ──────────────────────────────────────────────────────────────────────
class QPill extends StatelessWidget {
  final String label;
  final String tone; // green|amber|red|blue|purple|gray
  final Widget? icon;

  const QPill(this.label, {super.key, this.tone = 'green', this.icon});

  static _ToneColors _colors(String t) {
    switch (t) {
      case 'amber':
        return const _ToneColors(cAmberTint, cAmberInk);
      case 'red':
        return const _ToneColors(cRedTint, cRedInk);
      case 'blue':
        return const _ToneColors(cBlueTint, cBlueInk);
      case 'purple':
        return const _ToneColors(cPurpleTint, cPurpleInk);
      case 'gray':
        return const _ToneColors(cLine2, cInk2);
      default:
        return const _ToneColors(cGreenTint, cGreenDeep);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _colors(tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: c.bg,
        // Толық дөңгелек «таблетка» — бұрышы 9px тіктөртбұрышқа қарағанда
        // жеңіл әрі заманауи көрінеді.
        borderRadius: BorderRadius.circular(kRPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[icon!, const SizedBox(width: 4)],
          Text(label,
              style: manrope(11.5, FontWeight.w700,
                  color: c.fg, letterSpacing: 0.1, height: 1.1)),
        ],
      ),
    );
  }
}

class _ToneColors {
  final Color bg, fg;
  const _ToneColors(this.bg, this.fg);
}

// ── TOP дүкен белгісі ─────────────────────────────────────────────────────────
/// Рейтингі жоғары әрі пікірі жеткілікті дүкендерге берілетін белгі
/// (шектер — StoreModel.isTopStore). Тізім, карта және дүкен бетінде
/// БІРДЕЙ көріну үшін бір ғана виджет.
class QTopStoreBadge extends StatelessWidget {
  /// true — ықшам нұсқа (тек ★ TOP), тізім карточкалары үшін.
  final bool compact;
  const QTopStoreBadge({super.key, this.compact = false});

  static const _gold = Color(0xFF9C6605);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: compact ? 7 : 10, vertical: compact ? 2.5 : 4),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [Color(0xFFFFF3D4), Color(0xFFFFE3AE)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(kRPill),
        border: Border.all(color: cAmber.withValues(alpha: 0.42)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.workspace_premium_rounded,
            size: compact ? 10.5 : 13, color: _gold),
        SizedBox(width: compact ? 2 : 4),
        Text('TOP',
            style: manrope(compact ? 9.5 : 11, FontWeight.w800,
                color: _gold, letterSpacing: 0.5, height: 1.1)),
      ]),
    );
  }
}

// ── SecLabel ──────────────────────────────────────────────────────────────────
class QSecLabel extends StatelessWidget {
  final String label;
  final Widget? action;
  const QSecLabel(this.label, {super.key, this.action});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Кішкене жасыл акцент — бөлім басы көзге бірден түседі.
          Container(
            width: 3,
            height: 13,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: cGreen,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: Text(
              label.toUpperCase(),
              style: manrope(11.5, FontWeight.w800,
                  color: cInk2, letterSpacing: 0.7, height: 1.2),
            ),
          ),
          if (action != null) action!,
        ],
      ),
    );
  }
}

// ── IconTile ──────────────────────────────────────────────────────────────────
class QIconTile extends StatelessWidget {
  final Widget icon;
  final String tone;
  final double size;

  const QIconTile(
      {super.key, required this.icon, this.tone = 'green', this.size = 44});

  static Color _bg(String t) {
    switch (t) {
      case 'amber':
        return cAmberTint;
      case 'red':
        return cRedTint;
      case 'blue':
        return cBlueTint;
      case 'purple':
        return cPurpleTint;
      case 'ink':
        return cLine2;
      default:
        return cGreenTint;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bg = _bg(tone);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        // Жеңіл градиент — жалпақ бір түстен гөрі «тірі» көрінеді.
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.lerp(bg, Colors.white, 0.45)!, bg],
        ),
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Center(child: icon),
    );
  }
}

// ── Card ──────────────────────────────────────────────────────────────────────
class QCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? color;
  final Border? border;
  final double radius;

  const QCard({
    super.key,
    required this.child,
    this.padding,
    this.color,
    this.border,
    this.radius = kR20,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color ?? cSurface,
        borderRadius: BorderRadius.circular(radius),
        border: border ?? Border.all(color: cLine),
        boxShadow: kShadowSm,
      ),
      child: child,
    );
  }
}

// ── Shoe (product image placeholder / real image) ─────────────────────────────
class QShoeImage extends StatelessWidget {
  final String? imageUrl;
  final double height;
  final int tone;

  const QShoeImage(
      {super.key, this.imageUrl, this.height = 120, this.tone = 0});

  static const _gradients = [
    LinearGradient(
        colors: [Color(0xFFE9FBF2), Color(0xFFCCF0DF)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight),
    LinearGradient(
        colors: [Color(0xFFE8F1FF), Color(0xFFD2E4FF)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight),
    LinearGradient(
        colors: [Color(0xFFFFF4DE), Color(0xFFFDE7BF)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight),
    LinearGradient(
        colors: [Color(0xFFEFEAFF), Color(0xFFDFD6FF)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight),
    LinearGradient(
        colors: [Color(0xFFFFEBEE), Color(0xFFFCD6DC)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight),
  ];

  @override
  Widget build(BuildContext context) {
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(kR16),
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Gradient background — тек жүктелу/мөлдір аймақтар үшін fallback.
              // Фото 1:1 болғандықтан cover толық толтырады, фон көрінбейді.
              Container(
                decoration: BoxDecoration(
                  gradient: _gradients[tone % _gradients.length],
                ),
              ),
              Image.network(
                imageUrl!,
                fit: BoxFit.cover,
                loadingBuilder: (_, child, progress) =>
                    progress == null ? child : const SizedBox.shrink(),
                errorBuilder: (_, __, ___) => Center(
                  child: Icon(Icons.image_not_supported_outlined,
                      color: cInk.withValues(alpha: 0.22),
                      // height=infinity (Expanded ішінде) болса — тұрақты өлшем.
                      size: height.isFinite ? height * 0.28 : 34),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return _placeholder();
  }

  Widget _placeholder() => Container(
        height: height,
        decoration: BoxDecoration(
          gradient: _gradients[tone % _gradients.length],
          borderRadius: BorderRadius.circular(kR16),
        ),
        child: Center(
          child: Icon(Icons.inventory_2_outlined,
              color: cInk.withValues(alpha: 0.22),
              // height=infinity (Expanded ішінде) болса — тұрақты өлшем.
              size: height.isFinite ? height * 0.35 : 42),
        ),
      );
}

// ── Primary Button ────────────────────────────────────────────────────────────
/// Басты әрекет батырмасы: градиент бет + түрлі-түсті шуақ көлеңке +
/// басқандағы жинақталу анимациясы. Өшірулі күйде түсі де, көлеңкесі де
/// толық басылады — «басуға болмайтыны» бірден көрінеді.
class QPrimaryButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final Widget? icon;
  final double height;

  /// Қауіпті әрекет (өшіру/бас тарту) — қызыл градиент.
  final bool danger;

  const QPrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.isLoading = false,
    this.icon,
    this.height = 52,
    this.danger = false,
  });

  @override
  State<QPrimaryButton> createState() => _QPrimaryButtonState();
}

class _QPrimaryButtonState extends State<QPrimaryButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    // Басуға болатыны мен КӨРІНІСІ бөлек: жүктелу кезінде батырма
    // «сөнбейді» (әйтпесе ақ спиннер ашық сұр фонда көрінбей қалады) —
    // тек басу ғана бұғатталады.
    final tappable = widget.onPressed != null && !widget.isLoading;
    final lit = widget.onPressed != null || widget.isLoading;
    final radius = BorderRadius.circular(kR16);
    final fg = lit ? Colors.white : cInk3;

    return SizedBox(
      width: double.infinity,
      height: widget.height,
      child: AnimatedScale(
        scale: _down ? 0.975 : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          decoration: BoxDecoration(
            gradient: lit ? (widget.danger ? kGradDanger : kGradBtn) : null,
            color: lit ? null : cLine,
            borderRadius: radius,
            // Басқан сәтте шуақ басылады — батырма «батып» кеткендей әсер.
            boxShadow: lit && !_down
                ? (widget.danger ? kShadowRed : kShadowGreen)
                : null,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: tappable
                  ? () {
                      HapticFeedback.lightImpact();
                      widget.onPressed!.call();
                    }
                  : null,
              onTapDown: tappable ? (_) => setState(() => _down = true) : null,
              onTapUp: tappable ? (_) => setState(() => _down = false) : null,
              onTapCancel:
                  tappable ? () => setState(() => _down = false) : null,
              borderRadius: radius,
              splashColor: Colors.white.withValues(alpha: 0.14),
              highlightColor: Colors.white.withValues(alpha: 0.07),
              child: Center(
                child: widget.isLoading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.2))
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.icon != null) ...[
                            IconTheme(
                              data: IconThemeData(color: fg, size: 19),
                              child: widget.icon!,
                            ),
                            const SizedBox(width: 9),
                          ],
                          Flexible(
                            child: Text(
                              widget.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: manrope(15.5, FontWeight.w700,
                                  color: fg, letterSpacing: 0.1, height: 1.1),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Soft Button ───────────────────────────────────────────────────────────────
/// Екінші дәрежелі әрекет: жасыл төсеніш + жиек, шуақ жоқ — басты
/// батырмамен бәсекелеспейді, бірақ жай мәтіннен айқын ажырайды.
class QSoftButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final Widget? icon;
  final double height;

  /// green|red|blue|amber|gray
  final String tone;

  const QSoftButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.height = 46,
    this.tone = 'green',
  });

  @override
  State<QSoftButton> createState() => _QSoftButtonState();
}

class _QSoftButtonState extends State<QSoftButton> {
  bool _down = false;

  ({Color bg, Color fg, Color line}) get _tone {
    switch (widget.tone) {
      case 'red':
        return (bg: cRedTint, fg: cRedInk, line: const Color(0xFFFAD4DA));
      case 'blue':
        return (bg: cBlueTint, fg: cBlueInk, line: const Color(0xFFD3E4FF));
      case 'amber':
        return (bg: cAmberTint, fg: cAmberInk, line: const Color(0xFFF8E3B8));
      case 'gray':
        return (bg: cLine2, fg: cInk2, line: cLine);
      default:
        return (bg: cGreenTint, fg: cGreenDeep, line: cGreenTint2);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final t = _tone;
    final radius = BorderRadius.circular(kR16);
    final fg = enabled ? t.fg : cInk3;

    return SizedBox(
      width: double.infinity,
      height: widget.height,
      child: AnimatedScale(
        scale: _down ? 0.975 : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: enabled ? t.bg : cLine2,
            borderRadius: radius,
            border: Border.all(color: enabled ? t.line : cLine),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onPressed,
              onTapDown: enabled ? (_) => setState(() => _down = true) : null,
              onTapUp: enabled ? (_) => setState(() => _down = false) : null,
              onTapCancel: enabled ? () => setState(() => _down = false) : null,
              borderRadius: radius,
              splashColor: t.fg.withValues(alpha: 0.08),
              highlightColor: t.fg.withValues(alpha: 0.05),
              child: Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.icon != null) ...[
                      IconTheme(
                        data: IconThemeData(color: fg, size: 18),
                        child: widget.icon!,
                      ),
                      const SizedBox(width: 8),
                    ],
                    Flexible(
                      child: Text(
                        widget.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: manrope(14.5, FontWeight.w700,
                            color: fg, height: 1.1),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Gradient Header ───────────────────────────────────────────────────────────
/// Экран басындағы жасыл хедер. Жаңарту: төменгі бұрыштары дөңгеленген,
/// астында жұмсақ көлеңке, оң жақ жоғарыда жарық «бликі» бар —
/// жалпақ тіктөртбұрышқа қарағанда әлдеқайда терең әрі жинақы көрінеді.
class QGradientHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool showBack;
  final VoidCallback? onBack;
  final Widget? action;
  final List<Widget>? bottom;
  final bool compact;

  const QGradientHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.showBack = false,
    this.onBack,
    this.action,
    this.bottom,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final vPad = compact
        ? const EdgeInsets.fromLTRB(20, 6, 20, 20)
        : const EdgeInsets.fromLTRB(20, 8, 20, 24);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Жасыл хедердің үстіндегі жүйелік белгішелер АҚ болуы керек.
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Container(
        // clipBehavior — жарық блигі дөңгеленген төменгі бұрыштардан
        // сыртқа шықпауы үшін.
        clipBehavior: Clip.antiAlias,
        decoration: const BoxDecoration(
          gradient: kGrad,
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(kR24)),
          boxShadow: [
            BoxShadow(
                color: Color(0x2600713F), blurRadius: 20, offset: Offset(0, 8)),
          ],
        ),
        child: Stack(
          children: [
            // Жарық блигі — градиенттің үстінен жеңіл жарқырау.
            Positioned(
              top: -70,
              right: -50,
              child: Container(
                width: 210,
                height: 210,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [
                    Colors.white.withValues(alpha: 0.18),
                    Colors.white.withValues(alpha: 0.0),
                  ]),
                ),
              ),
            ),
            SafeArea(
              bottom: false,
              child: Padding(
                padding: vPad,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      if (showBack)
                        _HeaderCircleBtn(
                          icon: Icons.arrow_back_rounded,
                          onTap: onBack ?? () => Navigator.maybePop(context),
                        ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title,
                                style: manrope(23, FontWeight.w800,
                                    color: Colors.white)),
                            if (subtitle != null) ...[
                              const SizedBox(height: 3),
                              Text(subtitle!,
                                  style: manrope(12.5, FontWeight.w600,
                                      color: Colors.white
                                          .withValues(alpha: 0.85))),
                            ],
                          ],
                        ),
                      ),
                      if (action != null) action!,
                    ]),
                    if (bottom != null) ...bottom!,
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Хедердегі дөңгелек «артқа» батырмасы — басқанда сәл қараяды.
class _HeaderCircleBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _HeaderCircleBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      margin: const EdgeInsets.only(right: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}

// ── MenuItem ──────────────────────────────────────────────────────────────────
class QMenuItem extends StatelessWidget {
  final IconData icon;
  final String tone; // green|blue|amber|red|ink|purple
  final String title;
  final String? subtitle;
  final String? value;
  final VoidCallback? onTap;
  final bool danger;

  /// Оқылмаған/күтілетін сан (мыс. жауапсыз пікір саны). null/0 — жасырын.
  /// Тізімдегі бүкіл ескерту белгілерінің БІРДЕЙ көрінуі үшін (мыс. басты
  /// беттегі «Онлайн-заказы» блогындағы дөңгелек саны) осы жерде де
  /// дәл сол қатты қызыл дөңгелек қолданылады — бұрын кейбір жерде
  /// (жеке _QMenuItem) ашық пінк «чип» болатын да, назар аудармайтын еді.
  final int? badgeCount;

  const QMenuItem({
    super.key,
    required this.icon,
    this.tone = 'green',
    required this.title,
    this.subtitle,
    this.value,
    this.onTap,
    this.danger = false,
    this.badgeCount,
  });

  Color _iconColor() {
    switch (tone) {
      case 'blue':
        return cBlue;
      case 'amber':
        return cAmber;
      case 'red':
        return cRed;
      case 'purple':
        return cPurple;
      case 'ink':
        return cInk2;
      default:
        return cGreen;
    }
  }

  @override
  Widget build(BuildContext context) {
    final iconColor = danger ? cRed : _iconColor();
    final radius = BorderRadius.circular(kR16);
    return Material(
      color: cSurface,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        splashColor: iconColor.withValues(alpha: 0.07),
        highlightColor: iconColor.withValues(alpha: 0.04),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: cLine),
          ),
          child: Row(children: [
            QIconTile(
              icon: Icon(icon, color: iconColor, size: 20),
              tone: danger ? 'red' : tone,
              size: 42,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: manrope(14.5, FontWeight.w700,
                          color: danger ? cRed : cInk)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!,
                        style: manrope(12, FontWeight.w500, color: cInk3),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                  ],
                ],
              ),
            ),
            if (value != null) ...[
              const SizedBox(width: 8),
              Text(value!, style: manrope(13, FontWeight.w700, color: cInk2)),
              const SizedBox(width: 4),
            ],
            if ((badgeCount ?? 0) > 0) ...[
              Container(
                constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                    color: cRed, borderRadius: BorderRadius.circular(kRPill)),
                child: Center(
                  child: Text('$badgeCount',
                      style: manrope(11.5, FontWeight.w800,
                          color: Colors.white, height: 1.1)),
                ),
              ),
              const SizedBox(width: 6),
            ],
            Icon(Icons.chevron_right_rounded,
                color: danger ? cRed.withValues(alpha: 0.5) : cInk3, size: 20),
          ]),
        ),
      ),
    );
  }
}

// ── Bottom-nav active pill ────────────────────────────────────────────────────
/// Төменгі навигациядағы белсенді табтың белгісі — иконканың астындағы
/// жұмсақ жасыл «таблетка». Тек түс ауысуынан гөрі, қай таб ашық екені
/// бір қарағанда көрінеді (клиент/админ/сатушы/қонақ — төртеуінде бірдей).
class QNavPill extends StatelessWidget {
  final bool active;
  final Widget child;
  const QNavPill({super.key, required this.active, required this.child});

  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        decoration: BoxDecoration(
          color: active ? cGreenTint : Colors.transparent,
          borderRadius: BorderRadius.circular(kRPill),
        ),
        child: child,
      );
}

// ── Header icon button ────────────────────────────────────────────────────────
class QHeaderBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final int badge;

  const QHeaderBtn(this.icon, {super.key, this.onTap, this.badge = 0});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.18),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
          ),
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: Icon(icon, color: Colors.white, size: 19),
            ),
          ),
        ),
        if (badge > 0)
          Positioned(
            top: -4,
            right: -4,
            child: IgnorePointer(
              child: Container(
                constraints: const BoxConstraints(minWidth: 19, minHeight: 19),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: cRed,
                  borderRadius: BorderRadius.circular(kRPill),
                  border: Border.all(color: const Color(0xFF0A8050), width: 2),
                ),
                child: Center(
                  child: Text('$badge',
                      style: manrope(10, FontWeight.w800,
                          color: Colors.white, height: 1.1)),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
