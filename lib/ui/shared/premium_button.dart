import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_theme.dart';

enum BtnKind { brand, success, hot, ghost, danger }

enum BtnSize { sm, md, lg }

class PremiumButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final BtnKind kind;
  final BtnSize size;
  final bool loading;
  final bool expand;

  const PremiumButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.kind = BtnKind.brand,
    this.size = BtnSize.lg,
    this.loading = false,
    this.expand = true,
  });

  @override
  State<PremiumButton> createState() => _PremiumButtonState();
}

class _PremiumButtonState extends State<PremiumButton> {
  bool _pressed = false;

  ({Gradient bg, Color fg, List<BoxShadow> sh, Color? border}) _palette() {
    switch (widget.kind) {
      case BtnKind.brand:
        return (
          bg: AppTheme.gradBrand,
          fg: Colors.white,
          sh: AppTheme.shadowBrand,
          border: null
        );
      case BtnKind.success:
        return (
          bg: AppTheme.gradSuccess,
          fg: Colors.white,
          sh: AppTheme.shadowSuccess,
          border: null
        );
      case BtnKind.hot:
        return (
          bg: AppTheme.gradHot,
          fg: Colors.white,
          sh: AppTheme.shadowHot,
          border: null
        );
      case BtnKind.danger:
        return (
          bg: const LinearGradient(colors: [AppTheme.danger, AppTheme.danger]),
          fg: Colors.white,
          sh: AppTheme.shadowBrand,
          border: null
        );
      case BtnKind.ghost:
        return (
          bg: const LinearGradient(
              colors: [AppTheme.surface, AppTheme.surface]),
          fg: AppTheme.text2,
          sh: AppTheme.shadowSm,
          border: AppTheme.border
        );
    }
  }

  double get _height => switch (widget.size) {
        BtnSize.sm => 40,
        BtnSize.md => 48,
        BtnSize.lg => 54
      };
  double get _fontSize => switch (widget.size) {
        BtnSize.sm => 13,
        BtnSize.md => 14,
        BtnSize.lg => 15
      };
  double get _iconSize => switch (widget.size) {
        BtnSize.sm => 16,
        BtnSize.md => 18,
        BtnSize.lg => 18
      };

  @override
  Widget build(BuildContext context) {
    final p = _palette();
    final disabled = widget.onPressed == null || widget.loading;

    return GestureDetector(
      onTapDown: disabled
          ? null
          : (_) {
              HapticFeedback.lightImpact();
              setState(() => _pressed = true);
            },
      onTapUp: disabled ? null : (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.loading ? null : widget.onPressed,
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: AnimatedOpacity(
          opacity: disabled ? 0.6 : 1.0,
          duration: const Duration(milliseconds: 150),
          child: Container(
            height: _height,
            width: widget.expand ? double.infinity : null,
            decoration: BoxDecoration(
              gradient: p.bg,
              borderRadius: BorderRadius.circular(AppTheme.radius),
              boxShadow: disabled ? null : p.sh,
              border: p.border != null ? Border.all(color: p.border!) : null,
            ),
            child: Stack(children: [
              if (widget.kind != BtnKind.ghost)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: _height / 2,
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(AppTheme.radius)),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.white.withValues(alpha: 0.14),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              Center(
                child: widget.loading
                    ? SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: p.fg))
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (widget.icon != null) ...[
                            Icon(widget.icon, size: _iconSize, color: p.fg),
                            const SizedBox(width: 8),
                          ],
                          Text(widget.label,
                              style: TextStyle(
                                fontSize: _fontSize,
                                fontWeight: FontWeight.w700,
                                color: p.fg,
                                letterSpacing: 0.1,
                              )),
                        ],
                      ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
