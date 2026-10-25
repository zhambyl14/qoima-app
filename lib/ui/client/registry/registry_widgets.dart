import 'package:flutter/material.dart';

import '../../../theme/qoima_design.dart';

/// Мереке түрін таңдау чипі (тізім формасы мен «Тізімге қосу» парағында ортақ).
class RegistryOccasionChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const RegistryOccasionChip(
      {super.key,
      required this.label,
      required this.selected,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? cGreenTint : cSurface,
          borderRadius: BorderRadius.circular(kRPill),
          border: Border.all(
              color: selected ? cGreen : cLine, width: selected ? 1.5 : 1),
        ),
        child: Text(label,
            style: manrope(13, FontWeight.w700,
                color: selected ? cGreenDeep : cInk2)),
      ),
    );
  }
}
