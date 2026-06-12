import 'package:flutter/material.dart';
import '../../../theme/qoima_design.dart';

/// Segmented control
class MSSeg extends StatelessWidget {
  final List<String> options;
  final int active;
  final ValueChanged<int> onChanged;
  const MSSeg({super.key, required this.options, required this.active, required this.onChanged});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: cBg, borderRadius: BorderRadius.circular(13)),
        child: Row(
          children: options.asMap().entries.map((e) {
            final sel = e.key == active;
            return Expanded(
              child: GestureDetector(
                onTap: () => onChanged(e.key),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: sel ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: sel
                        ? [BoxShadow(color: Colors.black.withValues(alpha: 0.07), blurRadius: 6, offset: const Offset(0, 2))]
                        : [],
                  ),
                  child: Text(e.value,
                      textAlign: TextAlign.center,
                      style: manrope(13.5, FontWeight.w700, color: sel ? cInk : cInk3)),
                ),
              ),
            );
          }).toList(),
        ),
      );
}

/// Animated toggle switch
class MSToggle extends StatelessWidget {
  final bool on;
  final VoidCallback? onTap;
  const MSToggle({super.key, required this.on, this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 50,
          height: 29,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15), color: on ? cGreen : cLine),
          alignment: on ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 23,
            height: 23,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 4, offset: const Offset(0, 1))
              ],
            ),
          ),
        ),
      );
}

/// +/− counter button
class MSCounterBtn extends StatelessWidget {
  final IconData icon;
  final Color bg, fg;
  final VoidCallback onTap;
  const MSCounterBtn({super.key, required this.icon, required this.bg, required this.fg, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(11)),
          child: Icon(icon, color: fg, size: 18),
        ),
      );
}

/// Date picker button
class MSDateBtn extends StatelessWidget {
  final String label;
  final DateTime? date;
  final VoidCallback onTap;
  const MSDateBtn({super.key, required this.label, required this.date, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: cSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: date != null ? cGreen : cLine),
          ),
          child: Row(children: [
            Icon(Icons.calendar_today_outlined, size: 15, color: date != null ? cGreen : cInk3),
            const SizedBox(width: 6),
            Text(
              date != null
                  ? '${date!.day.toString().padLeft(2, '0')}.${date!.month.toString().padLeft(2, '0')}.${date!.year}'
                  : label,
              style: manrope(13, FontWeight.w600, color: date != null ? cInk : cInk3),
            ),
          ]),
        ),
      );
}

