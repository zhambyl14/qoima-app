import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ── Color palette ─────────────────────────────────────────────────────────────
const cGreen = Color(0xFF00A862);
const cGreenDeep = Color(0xFF00713F);
const cGreenBright = Color(0xFF12C97A);
const cGreenTint = Color(0xFFE4F7EE);
const cGreenTint2 = Color(0xFFD2F0E0);

const cInk = Color(0xFF0C120F);
const cInk2 = Color(0xFF566B61);
const cInk3 = Color(0xFF93A39B);
const cLine = Color(0xFFE7ECEA);
const cLine2 = Color(0xFFF0F3F2);
const cBg = Color(0xFFF1F4F3);
const cSurface = Color(0xFFFFFFFF);

const cAmber = Color(0xFFF5A524);
const cAmberTint = Color(0xFFFEF3DC);
const cRed = Color(0xFFF0384B);
const cRedTint = Color(0xFFFDE8EB);
const cBlue = Color(0xFF2D7FF9);
const cBlueTint = Color(0xFFE4EEFE);
const cPurple = Color(0xFF7C5CFC);
const cPurpleTint = Color(0xFFECE7FE);

// ── Gradient ──────────────────────────────────────────────────────────────────
const kGrad = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF00713F), Color(0xFF00A862), Color(0xFF12C97A)],
  stops: [0.0, 0.55, 1.0],
);

// ── Shadows ───────────────────────────────────────────────────────────────────
const kShadowSm = [
  BoxShadow(color: Color(0x0D0C120F), blurRadius: 2, offset: Offset(0, 1)),
];
const kShadowMd = [
  BoxShadow(color: Color(0x120C120F), blurRadius: 16, offset: Offset(0, 4)),
];
const kShadowGreen = [
  BoxShadow(color: Color(0x5200A862), blurRadius: 24, offset: Offset(0, 8)),
];

// ── Typography ────────────────────────────────────────────────────────────────
TextStyle manrope(double size, FontWeight weight,
        {Color color = cInk, double? letterSpacing, double? height}) =>
    GoogleFonts.manrope(
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    );

// ── Money formatter ───────────────────────────────────────────────────────────
String money(double v) {
  final s = v.toStringAsFixed(0);
  final buf = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
    buf.write(s[i]);
  }
  buf.write(' ₸');
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
        return _ToneColors(cAmberTint, const Color(0xFF9A6A06));
      case 'red':
        return _ToneColors(cRedTint, const Color(0xFFB11A2B));
      case 'blue':
        return _ToneColors(cBlueTint, const Color(0xFF1A5BD0));
      case 'purple':
        return _ToneColors(cPurpleTint, const Color(0xFF5A3DD0));
      case 'gray':
        return _ToneColors(cLine2, cInk2);
      default:
        return _ToneColors(cGreenTint, cGreenDeep);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _colors(tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[icon!, const SizedBox(width: 4)],
          Text(label, style: manrope(11.5, FontWeight.w700, color: c.fg)),
        ],
      ),
    );
  }
}

class _ToneColors {
  final Color bg, fg;
  const _ToneColors(this.bg, this.fg);
}

// ── SecLabel ──────────────────────────────────────────────────────────────────
class QSecLabel extends StatelessWidget {
  final String label;
  final Widget? action;
  const QSecLabel(this.label, {super.key, this.action});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label.toUpperCase(),
              style: manrope(12, FontWeight.w800,
                  color: cInk3, letterSpacing: 0.8),
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
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: _bg(tone),
        borderRadius: BorderRadius.circular(13),
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
    this.radius = 18,
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

  const QShoeImage({super.key, this.imageUrl, this.height = 120, this.tone = 0});

  static const _gradients = [
    LinearGradient(colors: [Color(0xFFE4F7EE), Color(0xFFC8EEDB)],
        begin: Alignment.topLeft, end: Alignment.bottomRight),
    LinearGradient(colors: [Color(0xFFE4EEFE), Color(0xFFCFE0FC)],
        begin: Alignment.topLeft, end: Alignment.bottomRight),
    LinearGradient(colors: [Color(0xFFFEF3DC), Color(0xFFFCE6BC)],
        begin: Alignment.topLeft, end: Alignment.bottomRight),
    LinearGradient(colors: [Color(0xFFECE7FE), Color(0xFFDCD2FC)],
        begin: Alignment.topLeft, end: Alignment.bottomRight),
    LinearGradient(colors: [Color(0xFFFDE8EB), Color(0xFFFBD2D9)],
        begin: Alignment.topLeft, end: Alignment.bottomRight),
  ];

  @override
  Widget build(BuildContext context) {
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Image.network(
          imageUrl!,
          height: height,
          width: double.infinity,
          fit: BoxFit.cover,
          // Show placeholder while the heavy file is decoding so the
          // box is never blank — avoids the "empty square" symptom.
          loadingBuilder: (_, child, progress) =>
              progress == null ? child : _placeholder(),
          errorBuilder: (_, __, ___) => _placeholder(),
        ),
      );
    }
    return _placeholder();
  }

  Widget _placeholder() => Container(
        height: height,
        decoration: BoxDecoration(
          gradient: _gradients[tone % _gradients.length],
          borderRadius: BorderRadius.circular(14),
        ),
        child: Center(
          child: Icon(Icons.inventory_2_outlined,
              color: cInk.withValues(alpha: 0.22), size: height * 0.35),
        ),
      );
}

// ── Primary Button ────────────────────────────────────────────────────────────
class QPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final Widget? icon;
  final double height;

  const QPrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.isLoading = false,
    this.icon,
    this.height = 52,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: height,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: cGreen,
          foregroundColor: Colors.white,
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15)),
        ).copyWith(
          overlayColor: WidgetStateProperty.all(Colors.white.withValues(alpha: 0.15)),
        ),
        child: isLoading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2))
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[icon!, const SizedBox(width: 9)],
                  Text(label,
                      style: manrope(15.5, FontWeight.w700,
                          color: Colors.white, letterSpacing: 0.1)),
                ],
              ),
      ),
    );
  }
}

// ── Soft Button ───────────────────────────────────────────────────────────────
class QSoftButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final Widget? icon;
  final double height;

  const QSoftButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.height = 44,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: height,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: cGreenTint,
          foregroundColor: cGreenDeep,
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[icon!, const SizedBox(width: 8)],
            Text(label,
                style:
                    manrope(14, FontWeight.w700, color: cGreenDeep)),
          ],
        ),
      ),
    );
  }
}

// ── Gradient Header ───────────────────────────────────────────────────────────
class QGradientHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool showBack;
  final Widget? action;
  final List<Widget>? bottom;
  final bool compact;

  const QGradientHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.showBack = false,
    this.action,
    this.bottom,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final vPad = compact
        ? const EdgeInsets.fromLTRB(20, 6, 20, 18)
        : const EdgeInsets.fromLTRB(20, 8, 20, 22);

    return Container(
      decoration: const BoxDecoration(gradient: kGrad),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: vPad,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                if (showBack)
                  GestureDetector(
                    onTap: () => Navigator.maybePop(context),
                    child: Container(
                      width: 38,
                      height: 38,
                      margin: const EdgeInsets.only(right: 10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.chevron_left_rounded,
                          color: Colors.white, size: 22),
                    ),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: manrope(23, FontWeight.w800,
                              color: Colors.white, letterSpacing: -0.5)),
                      if (subtitle != null)
                        Text(subtitle!,
                            style: manrope(13, FontWeight.w500,
                                color: Colors.white.withValues(alpha: 0.78))),
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

  const QMenuItem({
    super.key,
    required this.icon,
    this.tone = 'green',
    required this.title,
    this.subtitle,
    this.value,
    this.onTap,
    this.danger = false,
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
        decoration: BoxDecoration(
          color: cSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cLine),
        ),
        child: Row(children: [
          QIconTile(
            icon: Icon(icon, color: iconColor, size: 20),
            tone: danger ? 'red' : tone,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: manrope(14.5, FontWeight.w700,
                        color: danger ? cRed : cInk)),
                if (subtitle != null)
                  Text(subtitle!,
                      style: manrope(12, FontWeight.w500, color: cInk3)),
              ],
            ),
          ),
          if (value != null) ...[
            Text(value!, style: manrope(13, FontWeight.w600, color: cInk3)),
            const SizedBox(width: 4),
          ],
          Icon(Icons.chevron_right_rounded,
              color: danger ? cRed.withValues(alpha: 0.5) : cInk3, size: 20),
        ]),
      ),
    );
  }
}

// ── Header icon button ────────────────────────────────────────────────────────
class QHeaderBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final int badge;

  const QHeaderBtn(this.icon, {super.key, this.onTap, this.badge = 0});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
          if (badge > 0)
            Positioned(
              top: -4,
              right: -4,
              child: Container(
                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: cRed,
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF0A8050), width: 2),
                ),
                child: Center(
                  child: Text('$badge',
                      style: manrope(10, FontWeight.w800, color: Colors.white)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
