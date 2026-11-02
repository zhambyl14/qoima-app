import 'package:flutter_test/flutter_test.dart';
import 'package:qoima/data/models/category_data.dart';
import 'package:qoima/ui/admin/products/keyword_suggestions.dart';

/// «Ұқсас сөздер» ұсынысы: жергілікті сөздік (желісіз, лезде) + өріс пішімі.
void main() {
  group('өріс пішімі (іздеу буфері оқитын «a, b, c»)', () {
    test('parse: үтір, нүктелі үтір, жаңа жол; қайталанбайды', () {
      expect(parseKeywordList('кросы, Кросы;  sneakers\nзалға,, '),
          ['кросы', 'sneakers', 'залға']);
      expect(parseKeywordList('   '), isEmpty);
    });

    test('merge: қосады, регистрге тәуелсіз қайталамайды, пішімді сақтайды',
        () {
      expect(mergeKeywords('кросы', ['Кросы', 'залға']), 'кросы, залға');
      expect(mergeKeywords('', ['a', ' ', 'b']), 'a, b');
      expect(mergeKeywords('a; b', ['c']), 'a, b, c');
    });

    test('remove: бір сөзді алады', () {
      expect(removeKeyword('a, b, c', 'B'), 'a, c');
    });
  });

  group('suggestKeywords', () {
    test('кроссовки: орысша, қазақша және латынша синонимдер', () {
      final r = suggestKeywords(
          name: 'Air Max', categoryKey: 'shoes', type: 'Кроссовки');
      expect(r, containsAll(['кросы', 'спорттық аяқ киім', 'sneakers']));
    });

    test('куртка/пуховик: қазақша «күртке» бар', () {
      final r =
          suggestKeywords(name: 'Zara', categoryKey: 'outer', type: 'Куртка');
      expect(r.any((w) => w.contains('күртке') || w.contains('сырт киім')),
          isTrue);
    });

    test('бренд транслитерациясы, түс, маусым, кімге сөздері қосылады', () {
      final r = suggestKeywords(
        name: 'Модель 1',
        brand: 'Nike',
        categoryKey: 'shoes',
        type: 'Кроссовки',
        audience: 'Мужские',
        colors: const ['Белый'],
        seasons: const ['Лето'],
      );
      expect(r, contains('найк'));
      expect(r.any((w) => w.contains('бел')), isTrue);
      expect(r.any((w) => w.contains('лет')), isTrue);
      expect(r.any((w) => w.contains('муж')), isTrue);
    });

    test('ең көбі 12, қайталанбайды, атаудағы және өрістегі сөз жоқ', () {
      final r = suggestKeywords(
        name: 'Кросы Nike',
        brand: 'Nike',
        categoryKey: 'shoes',
        type: 'Кроссовки',
        audience: 'Мужские',
        colors: const ['Белый', 'Чёрный'],
        seasons: const ['Лето', 'Зима'],
        existing: const ['sneakers'],
      );
      expect(r.length, lessThanOrEqualTo(12));
      final low = r.map((w) => w.toLowerCase()).toList();
      expect(low.toSet().length, low.length);
      expect(low, isNot(contains('кросы'))); // атауда бар
      expect(low, isNot(contains('sneakers'))); // өрісте бар
    });

    test('max параметрі сақталады', () {
      expect(
          suggestKeywords(
                  name: 'x', categoryKey: 'shoes', type: 'Кроссовки', max: 3)
              .length,
          lessThanOrEqualTo(3));
    });

    test('категория/түрсіз құламайды', () {
      expect(() => suggestKeywords(name: 'x'), returnsNormally);
      expect(suggestKeywords(name: 'x'), isEmpty);
    });

    test('каталогтағы әр түр үшін кемінде бір ұсыныс бар', () {
      final missing = <String>[];
      kTypesByCategory.forEach((cat, types) {
        for (final t in types) {
          final r = suggestKeywords(name: 'zzz', categoryKey: cat, type: t);
          if (r.isEmpty) missing.add('$cat/$t');
        }
      });
      expect(missing, isEmpty, reason: 'сөздігі жоқ түрлер: $missing');
    });
  });
}
