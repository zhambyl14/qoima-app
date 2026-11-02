import 'package:flutter_test/flutter_test.dart';
import 'package:qoima/core/lang.dart';
import 'package:qoima/core/locale_context.dart';
import 'package:qoima/data/models/category_attributes.dart';
import 'package:qoima/data/models/category_data.dart';
import 'package:qoima/data/models/product_model.dart';
import 'package:qoima/data/services/firestore_service.dart';
import 'package:qoima/ui/admin/products/add_product_helpers.dart';

/// Категория сипаттамалары (0085): схеманың толықтығы, аудармалар, форма
/// ережелері, мәндерді келтіру, модельдің сериализациясы, түссіз тауар логикасы.
void main() {
  final cyrillic = RegExp('[А-Яа-яЁёӘәҒғҚқҢңӨөҰұҮүҺһІі]');
  final keys = kCategories.map((c) => c.key).toSet();

  tearDown(() => LocaleContext.currentLang = 'ru');

  group('схема', () {
    test('29 категорияның бәрі бар, артық кілт жоқ', () {
      expect(keys.length, 29);
      expect(kCategoryAttributes.keys.toSet(), keys);
      expect(kCategoryVisibility.keys.toSet(), keys);
    });

    test('әр категорияда 2–6 сипаттама, кілттер бірегей snake_case', () {
      final snake = RegExp(r'^[a-z][a-z0-9_]*$');
      for (final k in keys) {
        final defs = attributesFor(k);
        expect(defs.length, inInclusiveRange(2, 6), reason: k);
        final seen = <String>{};
        for (final d in defs) {
          expect(snake.hasMatch(d.key), isTrue, reason: '$k/${d.key}');
          expect(seen.add(d.key), isTrue, reason: 'қайталанды: $k/${d.key}');
        }
      }
    });

    test('чиптердің опциясы бар, бос/қайталанған жоқ', () {
      for (final k in keys) {
        for (final d in attributesFor(k)) {
          if (!d.isChoice) {
            expect(d.options, isEmpty, reason: '$k/${d.key}');
            continue;
          }
          expect(d.options, isNotEmpty, reason: '$k/${d.key}');
          expect(d.options.toSet().length, d.options.length,
              reason: '$k/${d.key}');
          for (final o in d.options) {
            expect(o.trim(), isNotEmpty, reason: '$k/${d.key}');
            expect(o.length, lessThanOrEqualTo(60), reason: '$k/${d.key}/$o');
          }
        }
      }
    });

    test('жапсырмалар мен бірліктер екі тілде', () {
      for (final k in keys) {
        for (final d in attributesFor(k)) {
          final id = '$k/${d.key}';
          expect(d.labelRu.trim(), isNotEmpty, reason: id);
          expect(d.labelKk.trim(), isNotEmpty, reason: id);
          expect(d.hintRu.isEmpty, d.hintKk.isEmpty, reason: '$id hint');
          expect(d.unitRu.isEmpty, d.unitKk.isEmpty, reason: '$id unit');
          if (d.kind != AttrKind.number) {
            expect(d.unitRu, isEmpty, reason: '$id: бірлік тек санға');
          }
        }
      }
    });

    test('аударылатын әр опцияның қазақшасы бар (trValue)', () {
      final missing = <String>[];
      for (final k in keys) {
        for (final d in attributesFor(k)) {
          if (!d.translateOptions) continue;
          for (final o in d.options) {
            if (cyrillic.hasMatch(o) && !hasKkTranslation(o)) {
              missing.add('$k/${d.key}/$o');
            }
          }
        }
      }
      expect(missing, isEmpty, reason: 'аудармасы жоқ: $missing');
    });

    test('тілге тәуелсіз опциялар шынымен аудармасыз жарайды', () {
      for (final k in keys) {
        for (final d in attributesFor(k)) {
          if (d.translateOptions) continue;
          for (final o in d.options) {
            // '8 ГБ', 'A4', '585' — кириллицада тек ГБ/ТБ қысқартуы рұқсат.
            final stripped = o.replaceAll(RegExp('ГБ|ТБ'), '');
            expect(cyrillic.hasMatch(stripped), isFalse, reason: '$k/$o');
          }
        }
      }
    });

    test('міндетті өріс категорияда ≤2, дәріханада жоқ; карточкада ≤1', () {
      for (final k in keys) {
        final defs = attributesFor(k);
        expect(defs.where((d) => d.required).length, lessThanOrEqualTo(2),
            reason: k);
        expect(defs.where((d) => d.showOnCard).length, lessThanOrEqualTo(1),
            reason: k);
      }
      expect(attributesFor('pharmacy').where((d) => d.required), isEmpty);
    });

    test('телефонда жады өлшем осі — сипаттамада қайталанбайды', () {
      expect(categoryByKey('phones').sizes, contains('128 ГБ'));
      final phoneKeys = attributesFor('phones').map((d) => d.key);
      expect(phoneKeys, isNot(contains('storage')));
      expect(phoneKeys, containsAll(['condition', 'ram_gb', 'sim']));
    });

    test('белгісіз категория — бос тізім, құламайды', () {
      expect(attributesFor(null), isEmpty);
      expect(attributesFor('gone_forever'), isEmpty);
      expect(attrDefFor('books', 'language')?.required, isTrue);
      expect(attrDefFor('books', 'nope'), isNull);
    });
  });

  group('түрлер (kTypesByCategory)', () {
    test('әр түрдің қазақша аудармасы бар', () {
      final missing = <String>[];
      kTypesByCategory.forEach((cat, types) {
        for (final t in types) {
          if (!hasKkTranslation(t)) missing.add('$cat/$t');
        }
      });
      expect(missing, isEmpty, reason: 'аудармасы жоқ түрлер: $missing');
    });

    test('әр категорияда 8–14 түр, ішінде қайталанбайды', () {
      expect(kTypesByCategory.keys.toSet(), keys);
      kTypesByCategory.forEach((cat, types) {
        expect(types.length, inInclusiveRange(8, 14), reason: cat);
        expect(types.toSet().length, types.length, reason: cat);
      });
    });

    test('ескі түрлер орнында (сақталған тауарлар сілтейді)', () {
      // 0085-ке дейінгі тізімнің бірнеше үлгісі — ешқайсысы өшпеуі керек.
      const legacy = {
        'shoes': ['Туфли', 'Лоферы'],
        'dress': ['Платье', 'Юбка', 'Сарафан', 'Костюм'],
        'books': ['Художественная', 'Комиксы'],
        'grocery': ['Бакалея', 'Чай и кофе'],
      };
      legacy.forEach((cat, types) {
        for (var i = 0; i < types.length; i++) {
          expect(kTypesByCategory[cat], contains(types[i]), reason: cat);
        }
      });
      expect(kTypesByCategory['shoes']!.first, 'Туфли');
    });
  });

  group('форма ережесі (visibilityFor)', () {
    const wear = {
      'shoes', 'tshirt', 'outer', 'pants', 'dress', 'caps', 'underwear', //
      'acc', 'sport', 'kids',
    };
    const colorless = {
      'books', 'grocery', 'pharmacy', 'stationery', 'auto', 'tools', //
      'garden', 'pets', 'jewelry', 'toys', 'beauty',
    };

    test('маусым тек киім/спорт/балаларда', () {
      for (final k in keys) {
        expect(visibilityFor(k).needsSeason, wear.contains(k), reason: k);
      }
    });

    test('түс: киімде міндетті, кітап/тағам/дәрі т.б. түссіз', () {
      for (final k in keys) {
        expect(visibilityFor(k).needsColor, !colorless.contains(k), reason: k);
      }
      for (final k in wear) {
        expect(visibilityFor(k).needsColor, isTrue, reason: k);
      }
    });

    test('материал тек тізімі бар жерде', () {
      for (final k in keys) {
        if ((kMaterialsByCategory[k] ?? const []).isEmpty) {
          expect(visibilityFor(k).needsMaterial, isFalse, reason: k);
        }
      }
      expect(visibilityFor('grocery').needsMaterial, isFalse);
      expect(visibilityFor('shoes').needsMaterial, isTrue);
    });

    test('белгісіз/таңдалмаған категория — бұрынғыдай бәрі көрінеді', () {
      for (final k in [null, 'gone_forever']) {
        final v = visibilityFor(k);
        expect(v.needsColor, isTrue);
        expect(v.needsSeason, isTrue);
      }
    });
  });

  group('мәндерді келтіру', () {
    final pages = attrDefFor('books', 'pages')!;
    final screen = attrDefFor('computers', 'screen_inch')!;
    final author = attrDefFor('books', 'author')!;
    final room = attrDefFor('furniture', 'room')!;

    test('сан: бүтін/бөлшек, үтір, теріс пен бос жарамсыз', () {
      expect(normalizeAttrValue(pages, '320'), 320);
      expect(normalizeAttrValue(pages, 320.7), 321);
      expect(normalizeAttrValue(screen, '15,6'), 15.6);
      expect(normalizeAttrValue(screen, '14'), 14);
      expect(normalizeAttrValue(screen, '15.666'), 15.67);
      expect(normalizeAttrValue(pages, '-3'), isNull);
      expect(normalizeAttrValue(pages, ''), isNull);
      expect(normalizeAttrValue(pages, 'abc'), isNull);
      expect(formatAttrNumber(15.6), '15.6');
      expect(formatAttrNumber(14.0), '14');
    });

    test('мәтін қиылады, бос → null', () {
      expect(normalizeAttrValue(author, '  Абай  '), 'Абай');
      expect(normalizeAttrValue(author, '   '), isNull);
      expect((normalizeAttrValue(author, 'я' * 500) as String).length,
          author.maxLength);
    });

    test('көп таңдау: опциялар ретімен, қайталанбайды, белгісізі соңында', () {
      expect(normalizeAttrValue(room, ['Офис', 'Спальня', 'Офис', 'Чердак']),
          ['Спальня', 'Офис', 'Чердак']);
      expect(normalizeAttrValue(room, 'Спальня'), ['Спальня']);
      expect(normalizeAttrValue(room, <String>[]), isNull);
    });

    test('sanitize: бос алынады, түрі келтіріледі, белгісіз кілт сақталады',
        () {
      final out = sanitizeAttributes('books', {
        'author': ' Абай ',
        'language': 'Казахский',
        'pages': '320',
        'publisher': '',
        'legacy_key': 'ескі мән',
        'junk': null,
      });
      expect(out, {
        'author': 'Абай',
        'language': 'Казахский',
        'pages': 320,
        'legacy_key': 'ескі мән',
      });
      expect(sanitizeAttributes('books', null), isEmpty);
      expect(sanitizeAttributes('books', {}), isEmpty);
    });

    test('sanitize: шектен асса алдымен белгісіз кілттер түседі', () {
      final raw = <String, dynamic>{'language': 'Русский'};
      for (var i = 0; i < 40; i++) {
        raw['x$i'] = 'я' * 80;
      }
      final out = sanitizeAttributes('books', raw);
      expect(attributesByteSize(out), lessThanOrEqualTo(kAttributesMaxBytes));
      expect(out['language'], 'Русский');
    });

    test('міндетті өрістер', () {
      expect(missingRequiredAttributes('books', {}).map((d) => d.key),
          ['language']);
      expect(
          missingRequiredAttributes('books', {'language': 'Русский'}), isEmpty);
      expect(missingRequiredAttributes('pharmacy', {}), isEmpty);
      expect(missingRequiredAttributes(null, {}), isEmpty);
    });
  });

  group('көрсетілім', () {
    final attrs = <String, dynamic>{
      'language': 'Казахский',
      'author': 'Абай',
      'pages': 320,
      'unknown': 'x',
    };

    test('орысша: схема ретімен, бірлігімен, белгісіз кілтсіз', () {
      final rows = displayAttributes('books', attrs);
      expect(rows.map((r) => r.def.key), ['author', 'language', 'pages']);
      expect(rows.map((r) => r.value), ['Абай', 'Казахский', '320 стр.']);
      expect(rows.first.label, 'Автор');
      expect(cardAttributeLabel('books', attrs), 'Абай');
    });

    test('қазақша: опция мен бірлік аударылады, мәтін өзгермейді', () {
      LocaleContext.currentLang = 'kk';
      final rows = displayAttributes('books', attrs);
      expect(rows.map((r) => r.value), ['Абай', 'Қазақ тілі', '320 бет']);
      expect(rows[1].label, 'Тілі');
      expect(attrDefFor('phones', 'ram_gb')!.valueLabel('8 ГБ'), '8 ГБ');
    });

    test('бос сипаттама — бос тізім, карточка белгісі жоқ', () {
      expect(displayAttributes('books', {}), isEmpty);
      expect(cardAttributeLabel('books', {'language': 'Русский'}), isNull);
      expect(cardAttributeLabel('tshirt', {'fit': 'Обычный'}), isNull);
    });

    test('AI/іздеу үшін орысша қысқа жол', () {
      expect(attributesSummaryRu('books', attrs),
          'Автор: Абай; Язык: Казахский; Страниц: 320 стр.');
    });
  });

  group('ProductModel.attributes', () {
    ProductModel base({Map<String, dynamic> attributes = const {}}) =>
        ProductModel(
          id: 'p1',
          name: 'Абай жолы',
          brand: 'Фолиант',
          type: 'Художественная',
          material: '',
          category: '',
          categoryKey: 'books',
          color: '',
          articul: 'QM-1',
          status: ProductModel.statusInStock,
          images: const [],
          attributes: attributes,
        );

    test('бос болса toMap/toJson-да кілт ЖОҚ (0085-сіз БД үшін)', () {
      expect(base().toMap().containsKey('attributes'), isFalse);
      expect(base().toJson().containsKey('attributes'), isFalse);
    });

    test('толы болса жазылады және оқылғанда қайтады', () {
      final p = base(attributes: {'language': 'Русский', 'pages': 320});
      final row = {...p.toMap(), 'id': 'p1'};
      expect(row['attributes'], {'language': 'Русский', 'pages': 320});
      final back = ProductModel.fromMap(row);
      expect(back.attributes, {'language': 'Русский', 'pages': 320});
      expect(back.color, '');
      final json = ProductModel.fromJson(p.toJson());
      expect(json.attributes, p.attributes);
    });

    test('ескі жол (бағансыз) не бүлінген мән → бос', () {
      expect(ProductModel.fromMap({'id': 'x'}).attributes, isEmpty);
      expect(ProductModel.fromMap({'attributes': null}).attributes, isEmpty);
      expect(ProductModel.fromMap({'attributes': '[1,2]'}).attributes, isEmpty);
      expect(
          ProductModel.fromMap({'attributes': '{"a":1}'}).attributes, {'a': 1});
      expect(
          ProductModel.fromMap({'attributes': 'not json'}).attributes, isEmpty);
    });

    test('copyWith және UPDATE патчы', () {
      final p = base().copyWith(attributes: {'language': 'Русский'});
      expect(p.attributes, {'language': 'Русский'});
      expect(p.copyWith(name: 'x').attributes, {'language': 'Русский'});
      expect(ProductModel.attributesPatch({}, {}), isNull);
      expect(ProductModel.attributesPatch({'a': 1}, {}), isEmpty);
      expect(ProductModel.attributesPatch({}, {'a': 1}), {'a': 1});
    });
  });

  group('түссіз тауар (жасырын нұсқа)', () {
    test('түссіз категория → дәл бір жасырын нұсқа', () {
      expect(planVariantsFor(needsColor: false, colors: []),
          VariantPlan.makeImplicit);
      expect(planVariantsFor(needsColor: false, colors: ['Белый', 'Черный']),
          VariantPlan.makeImplicit);
      expect(planVariantsFor(needsColor: false, colors: [kNoColor]),
          VariantPlan.keep);
    });

    test('түсті категорияға ауысса жасырын нұсқа алынады', () {
      expect(planVariantsFor(needsColor: true, colors: [kNoColor]),
          VariantPlan.dropImplicit);
      expect(planVariantsFor(needsColor: true, colors: ['Белый']),
          VariantPlan.keep);
      expect(planVariantsFor(needsColor: true, colors: []), VariantPlan.keep);
    });

    test('түс талабы', () {
      expect(colorsSatisfied(needsColor: true, colors: []), isFalse);
      expect(colorsSatisfied(needsColor: true, colors: ['Белый']), isTrue);
      expect(colorsSatisfied(needsColor: true, colors: [kNoColor]), isFalse);
      expect(colorsSatisfied(needsColor: false, colors: [kNoColor]), isTrue);
      expect(colorsSatisfied(needsColor: false, colors: []), isFalse);
      expect(colorsSatisfied(needsColor: false, colors: [kNoColor, kNoColor]),
          isFalse);
    });

    test('«Тағы осындайды қосу» үлгісі сипаттаманы алып жүреді', () {
      const t = AddProductTemplate(
          categoryKey: 'books', attributes: {'language': 'Русский'});
      expect(t.attributes['language'], 'Русский');
      expect(const AddProductTemplate(categoryKey: 'x').attributes, isEmpty);
    });
  });

  group('ұқсас тауар (rankSimilarProducts)', () {
    ProductModel p(String id, String name,
            {String color = '', String brand = '', String cat = 'books'}) =>
        ProductModel(
          id: id,
          name: name,
          brand: brand,
          type: '',
          material: '',
          category: '',
          categoryKey: cat,
          color: color,
          articul: '',
          status: ProductModel.statusInStock,
          images: const [],
        );

    test('түссіз: атау бойынша табылады, бос түс «бірдей» деп саналмайды', () {
      final all = [
        p('a', 'Абай жолы'),
        p('b', 'Қан мен тер'),
        p('c', 'Абай жолы 2 том'),
      ];
      final r = FirestoreService.rankSimilarProducts(all,
          name: 'Абай жолы', categoryKey: 'books');
      expect(r.map((e) => e.id), containsAll(['a', 'c']));
      expect(r.map((e) => e.id), isNot(contains('b')));
    });

    test('түс ұпайы тек екі жақта да түс болып, бірдей болса', () {
      final all = [
        p('white', 'Air Max', color: 'Белый', cat: 'shoes'),
        p('none', 'Air Max', cat: 'shoes'),
      ];
      final r = FirestoreService.rankSimilarProducts(all,
          name: 'Air Max', color: 'Белый', categoryKey: 'shoes');
      expect(r.first.id, 'white');
      // Түссіз сұрау түсті тауарды да, түссізді де табады, ешқайсысына бонус жоқ.
      final r2 = FirestoreService.rankSimilarProducts(all,
          name: 'Air Max', categoryKey: 'shoes');
      expect(r2.map((e) => e.id).toSet(), {'white', 'none'});
    });

    test('басқа категория мен қысқа атау еленбейді', () {
      final all = [p('a', 'Абай жолы', cat: 'grocery')];
      expect(
          FirestoreService.rankSimilarProducts(all,
              name: 'Абай жолы', categoryKey: 'books'),
          isEmpty);
      expect(FirestoreService.rankSimilarProducts(all, name: 'Аб'), isEmpty);
    });
  });
}
