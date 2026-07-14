import 'package:flutter/material.dart';
import '../data/models/category_data.dart';
import 'qoima_design.dart';

// ── QCategoryTag — маленький тег категории товара ─────────────────────────────
class QCategoryTag extends StatelessWidget {
  final CategoryData category;
  final double fontSize;
  const QCategoryTag({super.key, required this.category, this.fontSize = 11});

  @override
  Widget build(BuildContext context) {
    final tone = toneFor(category.tone);
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 3, 8, 3),
      decoration: BoxDecoration(
        color: tone.tint,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CategoryIcon(kind: category.iconKey, size: fontSize + 2, color: tone.deep),
          const SizedBox(width: 5),
          Text(category.short,
              style: manrope(fontSize, FontWeight.w700, color: tone.deep)),
        ],
      ),
    );
  }
}

