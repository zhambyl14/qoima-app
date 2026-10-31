import 'package:flutter/material.dart';

import '../../../core/lang.dart';
import '../../../data/models/category_data.dart';
import '../../../theme/qoima_design.dart';
import 'category_groups.dart';

/// Тауар қосу формасындағы категория таңдау: алдымен дүкеннің өз категориялары
/// (≤8 чип), соңында «Басқа санаттар» — барлық 29 категория топтарға бөлініп,
/// іздеумен. Таңдау семантикасы бұрынғыдай: [onSelected] кілтті қайтарады.
class CategoryPicker extends StatefulWidget {
  final String? selected;

  /// Алғашқы қатар ([primaryCategoryKeys] нәтижесі, таңдалған кілт қоса).
  final List<String> primaryKeys;
  final ValueChanged<String> onSelected;

  const CategoryPicker({
    super.key,
    required this.selected,
    required this.primaryKeys,
    required this.onSelected,
  });

  @override
  State<CategoryPicker> createState() => _CategoryPickerState();
}

class _CategoryPickerState extends State<CategoryPicker> {
  bool _expanded = false;
  String _query = '';

  Widget _chip(CategoryData c) {
    final isOn = widget.selected == c.key;
    final tone = toneFor(c.tone);
    return GestureDetector(
      onTap: () {
        // Ұзын тізімнен таңдаған соң жабамыз: таңдалғаны алғашқы қатарға шығады.
        if (_expanded) setState(() => _expanded = false);
        widget.onSelected(c.key);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.fromLTRB(10, 8, 13, 8),
        decoration: BoxDecoration(
          color: isOn ? tone.tint : Colors.white,
          border: Border.all(color: isOn ? tone.deep : cLine, width: 1.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          CategoryIcon(
              kind: c.iconKey, size: 15, color: isOn ? tone.deep : cInk3),
          const SizedBox(width: 6),
          Text(c.short,
              style: manrope(12.5, FontWeight.w700,
                  color: isOn ? tone.deep : cInk2)),
        ]),
      ),
    );
  }

  Widget _moreChip() => GestureDetector(
        onTap: () => setState(() {
          _expanded = !_expanded;
          if (!_expanded) _query = '';
        }),
        child: Container(
          padding: const EdgeInsets.fromLTRB(11, 8, 11, 8),
          decoration: BoxDecoration(
            color: _expanded ? cGreenTint : Colors.white,
            border: Border.all(
                color: _expanded ? cGreen : cLine, width: 1.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(
                _expanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.grid_view_rounded,
                size: 15,
                color: _expanded ? cGreenDeep : cInk3),
            const SizedBox(width: 6),
            Text(tr('Другие категории', 'Басқа санаттар'),
                style: manrope(12.5, FontWeight.w700,
                    color: _expanded ? cGreenDeep : cInk2)),
          ]),
        ),
      );

  Widget _buildAll() {
    final groups = <Widget>[];
    for (final g in kCategoryGroups) {
      final items = [
        for (final k in g.keys)
          if (categoryMatchesQuery(categoryByKey(k), _query)) categoryByKey(k),
      ];
      if (items.isEmpty) continue;
      groups.add(Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 6),
        child: Text(tr(g.titleRu, g.titleKk),
            style: manrope(11.5, FontWeight.w800, color: cInk3)),
      ));
      groups.add(Wrap(spacing: 8, runSpacing: 8, children: items.map(_chip).toList()));
    }
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
      decoration: BoxDecoration(
        color: cBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cLine),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextField(
          onChanged: (v) => setState(() => _query = v),
          style: const TextStyle(fontSize: 14, color: cInk),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: Colors.white,
            hintText: tr('Найти категорию', 'Санатты іздеу'),
            prefixIcon: const Icon(Icons.search_rounded, size: 18, color: cInk3),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: cLine)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: cLine)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: cGreen, width: 1.5)),
          ),
        ),
        ...groups,
        if (groups.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(tr('Ничего не найдено', 'Ештеңе табылмады'),
                style: manrope(12.5, FontWeight.w600, color: cInk3)),
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final k in widget.primaryKeys) _chip(categoryByKey(k)),
        _moreChip(),
      ]),
      if (_expanded) _buildAll(),
    ]);
  }
}
