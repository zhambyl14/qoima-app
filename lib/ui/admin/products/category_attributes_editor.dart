import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/lang.dart';
import '../../../data/models/category_attributes.dart';
import '../../../theme/qoima_design.dart';

/// Категория сипаттамаларының ортақ редакторы: қосу формасы, өңдеу парақшасы
/// және жылдам қосу — бәрі осы бір виджетті қолданады, сондықтан өріс түрлері,
/// тексеріс және бірліктер бір жерде.
///
/// Мәндерді өзі сақтамайды: әр өзгерісте ЖАҢА Map-ты [onChanged]-ке береді,
/// иесі (State) сақтайды. Категория ауысса өрістер қайта құрылады; сырттан
/// мән тазаланса (мыс. категория ауысқанда), өрістер де тазарады.
class CategoryAttributesEditor extends StatefulWidget {
  final String? categoryKey;
  final Map<String, dynamic> values;
  final ValueChanged<Map<String, dynamic>> onChanged;

  /// true — толтырылмаған міндетті өрістердің астында қызыл жазу.
  final bool showErrors;

  /// true — «Характеристики» тақырыбы бар карточка (қосу формасы);
  /// false — тек өрістер (өңдеу парақшасы, жылдам қосу парақшасы).
  final bool framed;

  const CategoryAttributesEditor({
    super.key,
    required this.categoryKey,
    required this.values,
    required this.onChanged,
    this.showErrors = false,
    this.framed = true,
  });

  @override
  State<CategoryAttributesEditor> createState() =>
      _CategoryAttributesEditorState();
}

class _CategoryAttributesEditorState extends State<CategoryAttributesEditor> {
  final Map<String, TextEditingController> _ctrls = {};

  List<AttrDef> get _defs => attributesFor(widget.categoryKey);

  @override
  void initState() {
    super.initState();
    _buildControllers();
  }

  @override
  void didUpdateWidget(covariant CategoryAttributesEditor old) {
    super.didUpdateWidget(old);
    if (old.categoryKey != widget.categoryKey) {
      _disposeControllers();
      _buildControllers();
      return;
    }
    // Сырттан өзгерген мән (тазалау, шаблон) өріске түседі. Иесі теріп
    // жатқанда мән бірдей болады — курсор секірмейді.
    for (final d in _defs) {
      final c = _ctrls[d.key];
      if (c == null) continue;
      final external = _textOf(d, widget.values[d.key]);
      if (!_sameText(d, c.text, external)) c.text = external;
    }
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  void _buildControllers() {
    for (final d in _defs) {
      if (d.kind == AttrKind.text || d.kind == AttrKind.number) {
        _ctrls[d.key] =
            TextEditingController(text: _textOf(d, widget.values[d.key]));
      }
    }
  }

  void _disposeControllers() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    _ctrls.clear();
  }

  static String _textOf(AttrDef d, Object? v) {
    final n = normalizeAttrValue(d, v);
    if (n == null) return '';
    return n is num ? formatAttrNumber(n) : n.toString();
  }

  static bool _sameText(AttrDef d, String current, String external) {
    if (d.kind == AttrKind.number) {
      return parseAttrNumber(current, decimal: d.decimal) ==
          parseAttrNumber(external, decimal: d.decimal);
    }
    return current.trim() == external.trim();
  }

  void _set(String key, Object? value) {
    final next = Map<String, dynamic>.of(widget.values);
    if (hasAttrValue(value)) {
      next[key] = value;
    } else {
      next.remove(key);
    }
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final defs = _defs;
    if (defs.isEmpty) return const SizedBox.shrink();
    final fields = <Widget>[];
    for (var i = 0; i < defs.length; i++) {
      if (i > 0) fields.add(const SizedBox(height: 14));
      fields.add(_field(defs[i]));
    }
    if (!widget.framed) {
      return Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: fields);
    }
    final filled =
        defs.where((d) => normalizeAttrValue(d, widget.values[d.key]) != null);
    return QCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      radius: 16,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.fact_check_outlined, size: 18, color: cGreen),
          const SizedBox(width: 8),
          Expanded(
            child: Text(tr('Характеристики', 'Сипаттамалары'),
                style: manrope(14, FontWeight.w800, color: cInk)),
          ),
          if (filled.isNotEmpty)
            Text('${filled.length}/${defs.length}',
                style: manrope(12, FontWeight.w700, color: cGreenDeep)),
        ]),
        const SizedBox(height: 2),
        Text(
            tr('Покупатели выбирают по ним. Поля со * обязательны.',
                'Сатып алушылар осыған қарап таңдайды. * белгісі барлары міндетті.'),
            style: manrope(11, FontWeight.w500, color: cInk3)),
        const SizedBox(height: 12),
        ...fields,
      ]),
    );
  }

  Widget _field(AttrDef d) {
    final value = widget.values[d.key];
    final missing = d.required && normalizeAttrValue(d, value) == null;
    return Column(
      key: ValueKey('attr-${widget.categoryKey}-${d.key}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(d.required ? '${d.label} *' : d.label,
            style: manrope(12.5, FontWeight.w700, color: cInk2)),
        if (d.hint.isNotEmpty && d.isChoice) ...[
          const SizedBox(height: 2),
          Text(d.hint, style: manrope(11, FontWeight.w500, color: cInk3)),
        ],
        const SizedBox(height: 7),
        switch (d.kind) {
          AttrKind.chips => _chips(d, value, multi: false),
          AttrKind.multiChips => _chips(d, value, multi: true),
          AttrKind.text => _textField(d),
          AttrKind.number => _numberField(d),
        },
        if (widget.showErrors && missing)
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Text(tr('Обязательное поле', 'Міндетті өріс'),
                style: manrope(11.5, FontWeight.w700, color: cRed)),
          ),
      ],
    );
  }

  Widget _chips(AttrDef d, Object? raw, {required bool multi}) {
    final norm = normalizeAttrValue(d, raw);
    final selected = <String>{
      if (norm is String) norm,
      if (norm is List<String>) ...norm,
    };
    // Схемада жоқ ескі мән жоғалмасын: таңдалған чип болып тұрады.
    final options = [
      ...d.options,
      for (final s in selected)
        if (!d.options.contains(s)) s,
    ];
    return Wrap(spacing: 7, runSpacing: 7, children: [
      for (final o in options)
        AttrChip(
          label: d.optionLabel(o),
          selected: selected.contains(o),
          onTap: () {
            if (multi) {
              final next = [
                for (final s in options)
                  if (s == o ? !selected.contains(o) : selected.contains(s)) s
              ];
              _set(d.key, next);
            } else {
              _set(d.key, selected.contains(o) ? null : o);
            }
          },
        ),
    ]);
  }

  InputDecoration _deco(AttrDef d, {String? suffix}) => InputDecoration(
        hintText: d.hint.isEmpty ? null : d.hint,
        hintStyle: manrope(13, FontWeight.w500, color: cInk3),
        suffixText: suffix,
        suffixStyle: manrope(13, FontWeight.w700, color: cInk2),
        counterText: '',
        isDense: true,
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: cLine)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: cLine)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: cGreen, width: 1.5)),
      );

  Widget _textField(AttrDef d) => TextField(
        controller: _ctrls[d.key],
        maxLength: d.maxLength,
        textCapitalization: TextCapitalization.sentences,
        style: manrope(14, FontWeight.w600, color: cInk),
        decoration: _deco(d),
        onChanged: (v) => _set(d.key, normalizeAttrValue(d, v)),
      );

  Widget _numberField(AttrDef d) => SizedBox(
        width: d.hint.isEmpty ? 170 : double.infinity,
        child: TextField(
          controller: _ctrls[d.key],
          keyboardType: TextInputType.numberWithOptions(decimal: d.decimal),
          inputFormatters: [
            d.decimal
                ? FilteringTextInputFormatter.allow(RegExp(r'^\d*[.,]?\d{0,2}'))
                : FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(d.maxDigits + (d.decimal ? 1 : 0)),
          ],
          style: manrope(14, FontWeight.w700, color: cInk),
          decoration: _deco(d, suffix: d.unit.isEmpty ? null : d.unit),
          onChanged: (v) => _set(d.key, parseAttrNumber(v, decimal: d.decimal)),
        ),
      );
}

/// Сипаттама чипі (бір/көп таңдау). Қосу формасының _SelectChip-імен бірдей
/// көрініс, бірақ ықшамырақ — өрістер көп болғанда форма ұзармасын.
class AttrChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const AttrChip(
      {super.key,
      required this.label,
      required this.selected,
      required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? cGreen : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: selected ? cGreen : cLine, width: selected ? 1.5 : 1),
          ),
          child: Text(label,
              style: manrope(12.5, FontWeight.w600,
                  color: selected ? Colors.white : cInk2)),
        ),
      );
}
