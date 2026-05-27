import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

// ─── Gradient header ─────────────────────────────────────────────────────────
class GradientHeader extends StatelessWidget {
  final String? eyebrow;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget? bottom;
  final bool back;
  final VoidCallback? onBack;
  final EdgeInsets padding;

  const GradientHeader({
    super.key,
    this.eyebrow,
    required this.title,
    this.subtitle,
    this.trailing,
    this.bottom,
    this.back = false,
    this.onBack,
    this.padding = const EdgeInsets.fromLTRB(16, 14, 16, 18),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: AppTheme.gradBrand),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (back)
                    GestureDetector(
                      onTap: onBack ?? () => Navigator.maybePop(context),
                      child: Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(11),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.18)),
                        ),
                        child: const Icon(Icons.arrow_back_ios_new_rounded,
                            color: Colors.white, size: 16),
                      ),
                    ),
                  if (back) const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (eyebrow != null)
                          Text(eyebrow!.toUpperCase(),
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.6),
                                fontSize: 11, fontWeight: FontWeight.w600,
                                letterSpacing: 0.6,
                              )),
                        Text(title,
                            style: const TextStyle(
                              color: Colors.white, fontSize: 18,
                              fontWeight: FontWeight.w800, letterSpacing: -0.3,
                            )),
                        if (subtitle != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(subtitle!,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.65),
                                  fontSize: 11,
                                )),
                          ),
                      ],
                    ),
                  ),
                  if (trailing != null) trailing!,
                ],
              ),
              if (bottom != null) ...[const SizedBox(height: 14), bottom!],
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Premium card ─────────────────────────────────────────────────────────────
class PremiumCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final EdgeInsets margin;
  final List<BoxShadow>? shadow;
  final VoidCallback? onTap;

  const PremiumCard({
    super.key, required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin = EdgeInsets.zero,
    this.shadow,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = Container(
      padding: padding, margin: margin,
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        boxShadow: shadow ?? AppTheme.shadowMd,
      ),
      child: child,
    );
    if (onTap == null) return c;
    return GestureDetector(onTap: onTap, child: c);
  }
}

// ─── Status badge ─────────────────────────────────────────────────────────────
class StatusBadge extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;
  final IconData? icon;

  const StatusBadge({
    super.key, required this.label,
    required this.bg, required this.fg, this.icon,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      if (icon != null) Padding(
        padding: const EdgeInsets.only(right: 4),
        child: Icon(icon, size: 11, color: fg),
      ),
      Text(label, style: TextStyle(
        fontSize: 9.5, fontWeight: FontWeight.w800,
        color: fg, letterSpacing: 0.3,
      )),
    ]),
  );
}

// ─── Skeleton box (shimmer-package-free) ─────────────────────────────────────
class SkeletonBox extends StatefulWidget {
  final double? width;
  final double height;
  final BorderRadius? radius;

  const SkeletonBox({super.key, this.width, required this.height, this.radius});

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this, duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (_, __) => Container(
      width: widget.width, height: widget.height,
      decoration: BoxDecoration(
        borderRadius: widget.radius ?? BorderRadius.circular(12),
        gradient: LinearGradient(
          begin: Alignment(-1 + _c.value * 2, 0),
          end:   Alignment( 1 + _c.value * 2, 0),
          colors: const [AppTheme.border, AppTheme.surface2, AppTheme.border],
          stops: const [0.0, 0.5, 1.0],
        ),
      ),
    ),
  );
}
