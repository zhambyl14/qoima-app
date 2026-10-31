import 'package:flutter/material.dart';

import '../../../core/lang.dart';
import '../../../theme/qoima_design.dart';

/// Өндірілген ел чиптері: дүкеннің өз елдері алдымен, сосын негізгілері,
/// соңында «Басқа» (мәтін өрісін ашады). Өріс міндетті емес.
///
/// Сақталатын мән — ЕЛДІҢ ОРЫСША аты (басқа канондық мәндер сияқты: түс, түр,
/// маусым); экранда [countryLabel] ағымдағы тілге аударады. Қолмен жазылған
/// мәндер өзгеріссіз сақталады.
class CountryOption {
  final String ru, kk;
  const CountryOption(this.ru, this.kk);
}

const List<CountryOption> kMainCountries = [
  CountryOption('Казахстан', 'Қазақстан'),
  CountryOption('Китай', 'Қытай'),
  CountryOption('Турция', 'Түркия'),
  CountryOption('Узбекистан', 'Өзбекстан'),
  CountryOption('Кыргызстан', 'Қырғызстан'),
  CountryOption('Россия', 'Ресей'),
  CountryOption('Италия', 'Италия'),
  CountryOption('Польша', 'Польша'),
  CountryOption('Корея', 'Корея'),
];

/// Алдыңғы елдерден ең көбі қанша чип.
const int kUsedCountryMax = 5;

String _norm(String s) => s.trim().toLowerCase();

/// Мән негізгі елдердің бірі ме (орысша НЕМЕСЕ қазақша жазылуы бойынша).
CountryOption? mainCountryOf(String stored) {
  final n = _norm(stored);
  if (n.isEmpty) return null;
  for (final c in kMainCountries) {
    if (_norm(c.ru) == n || _norm(c.kk) == n) return c;
  }
  return null;
}

/// Екі жазылу бір ел ме («Китай» = «Қытай» = «китай»).
bool sameCountry(String a, String b) {
  final na = _norm(a), nb = _norm(b);
  if (na.isEmpty || nb.isEmpty) return false;
  if (na == nb) return true;
  final ma = mainCountryOf(a), mb = mainCountryOf(b);
  return ma != null && ma == mb;
}

/// Экранда көрсетілетін аты: негізгі ел — ағымдағы тілде, басқасы — өзі.
String countryLabel(String stored) {
  final main = mainCountryOf(stored);
  return main == null ? stored.trim() : tr(main.ru, main.kk);
}

/// Чиптердің сақталатын мәндері: алдымен дүкеннің өз елдері (≤[kUsedCountryMax]),
/// сосын тізімде әлі жоқ негізгі елдер. Қайталанбайды.
List<String> countryChipValues(List<String> used) {
  final out = <String>[];
  bool has(String v) => out.any((o) => sameCountry(o, v));
  for (final u in used) {
    if (out.length >= kUsedCountryMax) break;
    if (u.trim().isEmpty || has(u)) continue;
    // Негізгі ел болса — канондық (орысша) жазылуымен, әйтпесе өз жазылуымен.
    out.add(mainCountryOf(u)?.ru ?? u.trim());
  }
  for (final c in kMainCountries) {
    if (!has(c.ru)) out.add(c.ru);
  }
  return out;
}

/// Ел таңдау блогы. Мәтін өрісін [fieldBuilder] салады (форманың өз `_Field`-і),
/// ол «Басқа» басылғанда немесе мән чиптердің бірі болмағанда ғана көрінеді.
class CountryPicker extends StatefulWidget {
  final TextEditingController controller;
  final List<String> used;
  final Widget Function() fieldBuilder;

  const CountryPicker({
    super.key,
    required this.controller,
    required this.used,
    required this.fieldBuilder,
  });

  @override
  State<CountryPicker> createState() => _CountryPickerState();
}

class _CountryPickerState extends State<CountryPicker> {
  bool _otherOpen = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onText);
  }

  @override
  void didUpdateWidget(CountryPicker old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onText);
      widget.controller.addListener(_onText);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onText);
    super.dispose();
  }

  void _onText() {
    if (mounted) setState(() {});
  }

  Widget _chip(String label, bool selected, VoidCallback onTap,
      {IconData? icon}) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? cGreen : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: selected ? cGreen : cLine, width: selected ? 1.5 : 1),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: selected ? Colors.white : cInk3),
            const SizedBox(width: 5),
          ],
          Text(label,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : cInk2)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.controller.text.trim();
    final values = countryChipValues(widget.used);
    final matchesChip = values.any((v) => sameCountry(v, text));
    // Қолмен жазылған ел чипте жоқ болса, өріс көрінеді (мән жасырылмайды).
    final showField = _otherOpen || (text.isNotEmpty && !matchesChip);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(tr('Страна производства (необязательно)',
              'Өндірілген ел (міндетті емес)'),
          style: manrope(13, FontWeight.w600, color: cInk2)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final v in values)
          _chip(countryLabel(v), sameCountry(v, text), () {
            // Таңдалғанды қайта бассаң — тазаланады.
            setState(() {
              widget.controller.text = sameCountry(v, text) ? '' : v;
              _otherOpen = false;
            });
          }),
        _chip(tr('Другая', 'Басқа'), showField, () {
          setState(() {
            _otherOpen = !showField;
            if (!_otherOpen && !matchesChip) widget.controller.clear();
          });
        }, icon: Icons.edit_outlined),
      ]),
      if (showField) ...[
        const SizedBox(height: 10),
        widget.fieldBuilder(),
      ],
    ]);
  }
}
