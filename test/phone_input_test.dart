import 'package:flutter_test/flutter_test.dart';
import 'package:qoima/core/phone_input.dart';

void main() {
  test('толық нөмір кез келген жазылуда бір E.164 береді', () {
    for (final input in [
      '+7 (700) 123-45-67',
      '+77001234567',
      ' +7 700 123 45 67',
      '87001234567',
      '77001234567',
      '7001234567',
    ]) {
      expect(kzPhoneToE164(input), '+77001234567', reason: input);
      expect(isValidKzPhone(input), isTrue, reason: input);
    }
  });

  test('бір цифры жетпейтін маска дұрыс нөмір болып өтпейді', () {
    expect(kzPhoneToE164('+7 (700) 123-45-6'), '+7700123456');
    expect(isValidKzPhone('+7 (700) 123-45-6'), isFalse);
  });

  test('қысқа не бос енгізу жарамсыз', () {
    expect(isValidKzPhone('+7 (700) 123-45'), isFalse);
    expect(isValidKzPhone('+7'), isFalse);
    expect(isValidKzPhone(''), isFalse);
  });
}
