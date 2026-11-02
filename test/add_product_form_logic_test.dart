import 'package:flutter_test/flutter_test.dart';
import 'package:qoima/data/models/category_data.dart';
import 'package:qoima/data/models/product_model.dart';
import 'package:qoima/data/models/season_utils.dart';
import 'package:qoima/ui/admin/products/add_product_helpers.dart';
import 'package:qoima/ui/admin/products/category_groups.dart';
import 'package:qoima/ui/admin/products/country_chips.dart';
import 'package:qoima/ui/admin/products/store_usage.dart';

/// Форманың тазы логикасы: категория топтары, ел чиптері, дүкен әдеттері,
/// маусым көп таңдауы, түс таңдау/шешу.
void main() {
  group('категория топтары (29 категория, ешқайсысы жоғалмайды)', () {
    test('kCategories-тегі әр кілт БІР-АҚ топта', () {
      for (final c in kCategories) {
        final inGroups = kCategoryGroups.where((g) => g.keys.contains(c.key));
        expect(inGroups.length, 1,
            reason: '«${c.key}» нақты бір топқа жатуы керек '
                '(жаңа категория category_groups.dart-қа да қосылсын)');
      }
    });

    test('топтарда каталогта жоқ кілт және қайталама жоқ', () {
      final known = {for (final c in kCategories) c.key};
      final all = [for (final g in kCategoryGroups) ...g.keys];
      expect(all.toSet().length, all.length, reason: 'қайталанған кілт бар');
      expect(all.where((k) => !known.contains(k)), isEmpty);
      expect(all.length, kCategories.length);
    });

    test('топтардың атауы екі тілде де толық', () {
      for (final g in kCategoryGroups) {
        expect(g.titleRu.trim(), isNotEmpty);
        expect(g.titleKk.trim(), isNotEmpty);
        expect(g.keys, isNotEmpty);
      }
    });

    test('әдепкі тізімдер тек каталогтағы кілттер', () {
      final known = {for (final c in kCategories) c.key};
      for (final k in [
        ...kDefaultPrimaryCategories,
        for (final l in kStoreCategoryDefaults.values) ...l,
      ]) {
        expect(known, contains(k));
      }
    });
  });

  group('primaryCategoryKeys', () {
    test('жаңа дүкен: дүкен түріне сай әдепкі, min..max аралығында', () {
      final r = primaryCategoryKeys(counts: const {}, storeCategory: 'Обувь');
      expect(r.first, 'shoes');
      expect(
          r.length, inInclusiveRange(kPrimaryCategoryMin, kPrimaryCategoryMax));
      expect(r.toSet().length, r.length);
    });

    test('белгісіз дүкен түрі («Другое») қысқа әдепкі тізімге түседі', () {
      final r = primaryCategoryKeys(counts: const {}, storeCategory: 'Другое');
      expect(
          r, containsAll(kDefaultPrimaryCategories.take(kPrimaryCategoryMin)));
    });

    test('өз тауарлары: саны бойынша, соңғы қолданылғаны ең алда', () {
      final r = primaryCategoryKeys(
        counts: const {'phones': 2, 'shoes': 9, 'toys': 5},
        lastUsed: 'toys',
        storeCategory: 'Обувь',
      );
      expect(r.take(3).toList(), ['toys', 'shoes', 'phones']);
    });

    test('таңдалған категория бірінші қатарда көрінеді (тізімде жоқ болса да)',
        () {
      final r = primaryCategoryKeys(
        counts: const {
          'shoes': 9,
          'tshirt': 8,
          'outer': 7,
          'pants': 6,
          'dress': 5,
          'acc': 4,
          'caps': 3,
          'sport': 2,
        },
        selected: 'garden',
      );
      expect(r.first, 'garden');
      expect(r.length, kPrimaryCategoryMax);
      expect(r.toSet().length, r.length);
    });

    test('каталогта жоқ кілттер тасталады', () {
      final r = primaryCategoryKeys(
          counts: const {'gone_forever': 99, 'shoes': 1}, lastUsed: 'nope');
      expect(r, isNot(contains('gone_forever')));
      expect(r, isNot(contains('nope')));
    });

    test('іздеу: екі тілде, кіші әріппен, бос сұраныс = барлығы', () {
      final shoes = categoryByKey('shoes');
      expect(categoryMatchesQuery(shoes, ''), isTrue);
      expect(
          categoryMatchesQuery(
              shoes, shoes.nameRu.substring(0, 3).toUpperCase()),
          isTrue);
      expect(categoryMatchesQuery(shoes, shoes.nameKk.substring(0, 3)), isTrue);
      expect(categoryMatchesQuery(shoes, 'qwertyuiop'), isFalse);
    });
  });

  group('StoreUsage.fromRows (бір жеңіл сұраудың нәтижесі)', () {
    test('категория санағы; category_key-сіз ескі тауар = shoes', () {
      final u = StoreUsage.fromRows([
        {'category_key': 'tshirt', 'country': ''},
        {'category_key': 'tshirt', 'country': null},
        {'category_key': '', 'country': ''},
      ]);
      expect(u.categoryCounts, {'tshirt': 2, 'shoes': 1});
    });

    test('елдер: жиілігі бойынша, регистрге тәуелсіз біріктіріледі', () {
      final u = StoreUsage.fromRows([
        {'category_key': 'shoes', 'country': 'Китай'},
        {'category_key': 'shoes', 'country': 'китай'},
        {'category_key': 'shoes', 'country': 'Турция'},
        {'category_key': 'shoes', 'country': '  '},
      ], storeCategory: 'Обувь');
      expect(u.countries, ['Китай', 'Турция']);
      expect(u.storeCategory, 'Обувь');
    });

    test('AppUser құрылмаған / желі жоқ: load бос нәтиже қайтарады', () async {
      final u = await StoreUsage.load();
      expect(u.categoryCounts, isEmpty);
      expect(u.countries, isEmpty);
    });
  });

  group('ел чиптері', () {
    test('өз елдері алдымен, сосын негізгілер, қайталанбайды', () {
      final v = countryChipValues(['Вьетнам', 'китай', 'Қытай', 'Индия']);
      expect(v.take(3).toList(), ['Вьетнам', 'Китай', 'Индия']);
      // «китай» мен «Қытай» бір ел: бір рет қана.
      expect(v.where((c) => sameCountry(c, 'Китай')).length, 1);
      for (final m in kMainCountries) {
        expect(v.any((c) => sameCountry(c, m.ru)), isTrue);
      }
    });

    test('өз елдері 5-ке дейін ғана', () {
      final v = countryChipValues([for (var i = 0; i < 9; i++) 'Ел$i']);
      expect(v.where((c) => c.startsWith('Ел')).length, kUsedCountryMax);
    });

    test('негізгі ел сақтауда орысша, экранда ағымдағы тілде', () {
      expect(mainCountryOf('Қытай')?.ru, 'Китай');
      expect(sameCountry('Қытай', 'Китай'), isTrue);
      expect(sameCountry('Вьетнам', 'Китай'), isFalse);
      expect(sameCountry('', ''), isFalse);
      expect(countryLabel('Вьетнам'), 'Вьетнам'); // қолмен жазылған өзгермейді
    });
  });

  group('маусым көп таңдауы', () {
    test('toggleSeasonValue: қосады/алады, төртеуін де, канондық ретпен', () {
      var v = '';
      v = toggleSeasonValue(v, 'Зима');
      v = toggleSeasonValue(v, 'Лето');
      expect(v, 'Лето,Зима'); // kSeasons ретімен
      expect(parseSeasons(v), ['Лето', 'Зима']);
      for (final s in kSeasons) {
        if (!parseSeasons(v).contains(s)) v = toggleSeasonValue(v, s);
      }
      expect(parseSeasons(v).toSet(), kSeasons.toSet());
      v = toggleSeasonValue(v, 'Лето');
      expect(parseSeasons(v), isNot(contains('Лето')));
      expect(parseSeasons(v).length, 3);
    });

    test('біреуін қайта басса бос болады (өріс міндетті емес)', () {
      expect(toggleSeasonValue('Зима', 'Зима'), '');
    });

    test('ескі бір маусым құлап қалмайды, белгісіз мән жоғалмайды', () {
      expect(toggleSeasonValue('Зима', 'Лето'), 'Лето,Зима');
      expect(parseSeasons('Демисезон'), ['Демисезон']);
      expect(toggleSeasonValue('Демисезон', 'Лето'), contains('Демисезон'));
    });

    test('ProductModel.joinSeasons форма жиынынан DB пішімін жасайды', () {
      expect(ProductModel.joinSeasons({'Зима', 'Весна', 'Лето'}),
          'Лето,Зима,Весна'); // kSeasons ретімен
      expect(ProductModel.joinSeasons(<String>{}), '');
    });
  });

  group('түс: таңдау/шешу (дубль жоқ)', () {
    test('colorKeyFor: түс аты бойынша жалғыз сәйкестік', () {
      final colorOf = {'Белый#1': 'Белый', 'Чёрный#2': 'Чёрный'};
      final keys = ['Белый#1', 'Чёрный#2'];
      expect(colorKeyFor(keys, colorOf, 'Белый'), 'Белый#1');
      expect(colorKeyFor(keys, colorOf, 'Красный'), isNull);
      expect(colorKeyFor(const [], colorOf, 'Белый'), isNull);
    });
  });

  group('AddProductTemplate («Тағы осындайды қосу»)', () {
    test('ортақ өрістер бар, түс/размер/фото/код өрісі жоқ', () {
      const t = AddProductTemplate(
        categoryKey: 'shoes',
        name: 'Air Max',
        descriptionKk: 'Жеңіл',
        season: 'Лето,Зима',
      );
      expect(t.categoryKey, 'shoes');
      expect(t.descriptionKk, 'Жеңіл');
      expect(parseSeasons(t.season), ['Лето', 'Зима']);
    });
  });
}
