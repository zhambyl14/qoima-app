import 'package:flutter/material.dart';
import '../../core/banks.dart';
import '../../core/lang.dart';
import '../../theme/qoima_design.dart';

/// Банк QR сілтемелерін енгізу редакторы (дүкен өтінімі, дүкен өңдеу, модератор
/// реквизиттері — үшеуіне ортақ). Әр банктің QR сілтемесін (міндетті емес)
/// енгізеді; өзгергенде [onChanged] бос емес жазбалардың картасын береді.
class BankQrEditor extends StatefulWidget {
  final Map<String, String> initial;
  final ValueChanged<Map<String, String>> onChanged;
  const BankQrEditor({super.key, required this.initial, required this.onChanged});

  @override
  State<BankQrEditor> createState() => _BankQrEditorState();
}

class _BankQrEditorState extends State<BankQrEditor> {
  late final Map<String, TextEditingController> _ctrls = {
    for (final b in kBanks)
      b.id: TextEditingController(text: widget.initial[b.id] ?? ''),
  };

  void _emit() {
    final map = <String, String>{};
    _ctrls.forEach((id, c) {
      final v = c.text.trim();
      if (v.isNotEmpty) map[id] = v;
    });
    widget.onChanged(map);
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
            color: cGreenTint, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          const Icon(Icons.qr_code_2_rounded, color: cGreenDeep, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              tr('Вставьте ссылку на QR каждого вашего банка. Клиент увидит QR-код и оплатит любым банком.',
                  'Әр банкіңіздің QR сілтемесін қойыңыз. Клиент QR-кодты көріп, кез келген банкпен төлейді.'),
              style: manrope(11.5, FontWeight.w600, color: cGreenDeep),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 10),
      for (final b in kBanks)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            SizedBox(
              width: 82,
              child: Text(b.name,
                  style: manrope(12.5, FontWeight.w700, color: cInk)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _ctrls[b.id],
                keyboardType: TextInputType.url,
                onChanged: (_) => _emit(),
                style: manrope(13, FontWeight.w600, color: cInk),
                decoration: InputDecoration(
                  hintText: tr('Ссылка QR (необязательно)', 'QR сілтемесі (міндетті емес)'),
                  hintStyle: manrope(12.5, FontWeight.w500, color: cInk3),
                  isDense: true,
                  filled: true,
                  fillColor: cBg,
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
                ),
              ),
            ),
          ]),
        ),
    ]);
  }
}
