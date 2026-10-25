import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/kz_cities.dart';
import '../../core/lang.dart';
import '../../core/phone_input.dart';
import '../../theme/qoima_design.dart';

/// Курьер деректерінің ортақ өріс виджеттері (0074): курьердің сұраныс
/// формасы да, superadmin-нің өңдеу парағы да осыны қолданады.

/// Қалып өріс: жапсырма + дөңгелек жиекті енгізу.
class CourierTextField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final int? maxLength;
  final int maxLines;
  final String? hint;
  final String? errorText;
  final ValueChanged<String>? onChanged;

  const CourierTextField({
    super.key,
    required this.label,
    required this.controller,
    this.keyboardType,
    this.inputFormatters,
    this.maxLength,
    this.maxLines = 1,
    this.hint,
    this.errorText,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          QSecLabel(label),
          Container(
            decoration: BoxDecoration(
              color: cBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: errorText == null ? cLine : cRed, width: 1.5),
            ),
            child: TextField(
              controller: controller,
              keyboardType: keyboardType,
              inputFormatters: inputFormatters,
              maxLength: maxLength,
              maxLines: maxLines,
              onChanged: onChanged,
              style: manrope(14.5, FontWeight.w600, color: cInk),
              cursorColor: cGreen,
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: manrope(14.5, FontWeight.w500, color: cInk3),
                counterText: '',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                isDense: true,
              ),
            ),
          ),
          if (errorText != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 4),
              child: Text(errorText!,
                  style: manrope(11.5, FontWeight.w600, color: cRed)),
            ),
          const SizedBox(height: 12),
        ],
      );
}

/// Телефон өрісі: `+7 (XXX) XXX-XX-XX` маскасы. Сақтау — E.164.
class CourierPhoneField extends StatelessWidget {
  final TextEditingController controller;
  final String? errorText;
  const CourierPhoneField(
      {super.key, required this.controller, this.errorText});

  /// Бастапқы E.164 мәнді маскаға салып көрсету.
  static String mask(String e164) {
    if (e164.isEmpty) return '';
    return KzPhoneInputFormatter()
        .formatEditUpdate(TextEditingValue.empty, TextEditingValue(text: e164))
        .text;
  }

  @override
  Widget build(BuildContext context) => CourierTextField(
        label: tr('Телефон (номер для входа)', 'Телефон (кіру нөмірі)'),
        controller: controller,
        keyboardType: TextInputType.phone,
        inputFormatters: [KzPhoneInputFormatter()],
        hint: '+7 (7XX) XXX-XX-XX',
        errorText: errorText,
      );
}

/// Қала таңдау өрісі (басқанда қала парағы ашылады).
class CourierCityField extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const CourierCityField(
      {super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          QSecLabel(tr('Город работы', 'Жұмыс қаласы')),
          GestureDetector(
            onTap: () async {
              final c = await showCourierCityPicker(context, current: value);
              if (c != null) onChanged(c);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: cBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: cLine, width: 1.5),
              ),
              child: Row(children: [
                const Icon(Icons.location_city_outlined,
                    size: 18, color: cInk3),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                      value.isEmpty
                          ? tr('Выберите город', 'Қаланы таңдаңыз')
                          : trValue(value),
                      style: manrope(14.5, FontWeight.w600,
                          color: value.isEmpty ? cInk3 : cInk)),
                ),
                const Icon(Icons.expand_more_rounded, color: cInk3),
              ]),
            ),
          ),
          const SizedBox(height: 12),
        ],
      );
}

/// Қала таңдау парағы: радиус 22 + тұтқа. Таңдалған қаланы қайтарады.
Future<String?> showCourierCityPicker(BuildContext context,
    {required String current}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Container(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
      decoration: const BoxDecoration(
        color: cSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 12, 20, MediaQuery.of(ctx).padding.bottom + 16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 40,
          height: 4,
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
              color: cLine, borderRadius: BorderRadius.circular(2)),
        ),
        Text(tr('Город работы', 'Жұмыс қаласы'),
            style: manrope(16, FontWeight.w800, color: cInk)),
        const SizedBox(height: 14),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            children: kzCities.map((c) {
              final selected = c == current;
              return ListTile(
                onTap: () => Navigator.pop(ctx, c),
                title: Text(trValue(c),
                    style: manrope(14.5, FontWeight.w700,
                        color: selected ? cGreenDeep : cInk)),
                trailing: selected
                    ? const Icon(Icons.check_circle_rounded,
                        color: cGreen, size: 20)
                    : null,
              );
            }).toList(),
          ),
        ),
      ]),
    ),
  );
}
