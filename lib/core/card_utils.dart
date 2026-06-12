import 'package:flutter/services.dart';

/// Төлем картасының номерімен жұмыс — бірнеше экран қолданады (заявка, дүкен
/// мәліметтері, өңдеу). Сақтағанда бос орынсыз (16 сан), көрсеткенде топтап.

/// Тек цифрларды қалдырады.
String cardDigitsOnly(String s) => s.replaceAll(RegExp(r'\D'), '');

/// '4400 4302 1183 5577' — 4 саннан топтап бос орын қояды.
String formatCardDisplay(String digits) {
  final d = cardDigitsOnly(digits);
  final buf = StringBuffer();
  for (int i = 0; i < d.length; i++) {
    if (i > 0 && i % 4 == 0) buf.write(' ');
    buf.write(d[i]);
  }
  return buf.toString();
}

/// '•••• •••• •••• 5577' — соңғы 4 саннан басқасын жасырады.
String maskCardDisplay(String digits) {
  final d = cardDigitsOnly(digits);
  if (d.length < 4) return d.isEmpty ? '•••• •••• •••• ••••' : d;
  final last4 = d.substring(d.length - 4);
  return '•••• •••• •••• $last4';
}

/// Luhn алгоритмі — карта номерінің бақылау санын тексереді.
bool luhnCheck(String digits) {
  final d = cardDigitsOnly(digits);
  if (d.isEmpty) return false;
  int sum = 0;
  bool alternate = false;
  for (int i = d.length - 1; i >= 0; i--) {
    int n = int.parse(d[i]);
    if (alternate) {
      n *= 2;
      if (n > 9) n -= 9;
    }
    sum += n;
    alternate = !alternate;
  }
  return sum % 10 == 0;
}

/// Маркетплейс картасы — дәл 16 сан + Luhn.
bool isCardValid(String input) {
  final d = cardDigitsOnly(input);
  return d.length == 16 && luhnCheck(d);
}

/// Енгізу форматтаушысы: макс 16 сан, әр 4 саннан кейін бос орын.
class CardNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = cardDigitsOnly(newValue.text);
    final capped = digits.length > 16 ? digits.substring(0, 16) : digits;
    final formatted = formatCardDisplay(capped);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
