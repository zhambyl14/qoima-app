import 'package:flutter/material.dart';
import '../../theme/qoima_design.dart';

/// Бір чип сипаттамасы (жазуы, таңдалуы, басу әрекеті).
class HChip {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const HChip({required this.label, required this.selected, required this.onTap});
}

/// Ұсыныс чиптерін БІР жолда, ЖЫЛЖЫМАЛЫ (горизонталь скролл) рамканың ішінде
/// көрсетеді — Wrap сияқты шашылып, көп орын алмайды. Соңында [trailing]
/// (мыс. «✏️ Өз нұсқасы») болуы мүмкін.
class HScrollChips extends StatelessWidget {
  final List<HChip> chips;
  final Widget? trailing;
  const HScrollChips({super.key, required this.chips, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: cBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cLine),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        physics: const BouncingScrollPhysics(),
        children: [
          for (final c in chips) ...[
            _Chip(chip: c),
            const SizedBox(width: 6),
          ],
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final HChip chip;
  const _Chip({required this.chip});

  @override
  Widget build(BuildContext context) {
    final sel = chip.selected;
    return GestureDetector(
      onTap: chip.onTap,
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: sel ? cGreen : Colors.white,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: sel ? cGreen : cLine, width: 1.2),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (sel) ...[
            const Icon(Icons.check_rounded, size: 14, color: Colors.white),
            const SizedBox(width: 4),
          ],
          Text(chip.label,
              style: manrope(12.5, FontWeight.w700,
                  color: sel ? Colors.white : cInk2)),
        ]),
      ),
    );
  }
}

/// Скролл-рамкадағы «әрекет» чипі (мыс. «✏️ Өз нұсқасы»).
class HActionChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const HActionChip(
      {super.key, required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: cGreenTint,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: cGreen.withValues(alpha: 0.4), width: 1.2),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: cGreenDeep),
          const SizedBox(width: 4),
          Text(label,
              style: manrope(12.5, FontWeight.w700, color: cGreenDeep)),
        ]),
      ),
    );
  }
}
