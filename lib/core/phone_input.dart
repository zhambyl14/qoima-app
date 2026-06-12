import 'package:flutter/services.dart';

/// Телефон нөмірін енгізу маскасы: `+7 (XXX) XXX-XX-XX` — тек КӨРСЕТУ үшін.
/// Сақтау әрқашан E.164 форматында: `+7XXXXXXXXXX` ([kzPhoneToE164] қара).
class KzPhoneInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    var digits = newValue.text.replaceAll(RegExp(r'\D'), '');

    // Форматтаушының шығысы '+7 (…' — '+7'-дегі '7' цифры Flutter қайта
    // жіберген мәтінге кіріп, абоненттік цифрлармен аралас болады.
    // Мәтін '+7'-ден басталса, бастапқы '7'-ні (ел кодын) алып тастаймыз.
    if (newValue.text.startsWith('+7') && digits.startsWith('7')) {
      digits = digits.substring(1);
    }

    // Қоя салынған толық нөмір: 11 цифр, 7/8-ден басталады (77..., 87...).
    if (digits.length == 11 && (digits.startsWith('7') || digits.startsWith('8'))) {
      digits = digits.substring(1);
    }
    if (digits.length > 10) digits = digits.substring(0, 10);

    if (digits.isEmpty) {
      return const TextEditingValue(text: '');
    }

    final buf = StringBuffer('+7');
    for (var i = 0; i < digits.length; i++) {
      if (i == 0) buf.write(' (');
      if (i == 3) buf.write(') ');
      if (i == 6) buf.write('-');
      if (i == 8) buf.write('-');
      buf.write(digits[i]);
    }
    final text = buf.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

/// Маскаланған/еркін енгізілген нөмірді E.164-ке (`+7XXXXXXXXXX`) түрлендіреді.
String kzPhoneToE164(String input) {
  var d = input.replaceAll(RegExp(r'\D'), '');
  if (d.length == 11 && (d.startsWith('7') || d.startsWith('8'))) {
    d = d.substring(1);
  }
  return '+7$d';
}

/// E.164 KZ нөмірі дұрыс па: `+7` + дәл 10 цифр.
bool isValidKzPhone(String input) =>
    RegExp(r'^\+7\d{10}$').hasMatch(kzPhoneToE164(input));
