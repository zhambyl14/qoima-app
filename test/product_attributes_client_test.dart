import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qoima/core/locale_context.dart';
import 'package:qoima/data/models/category_attributes.dart';
import 'package:qoima/data/models/product_model.dart';
import 'package:qoima/data/services/client_service.dart';
import 'package:qoima/ui/client/client_product_card.dart';
import 'package:qoima/ui/client/client_product_detail.dart';

ProductModel _p({
  String id = 'p1',
  String name = 'Товар',
  String brand = '',
  String type = '',
  String category = '',
  String categoryKey = 'books',
  String color = '',
  String material = '',
  Map<String, dynamic> attributes = const {},
}) =>
    ProductModel(
      id: id,
      name: name,
      brand: brand,
      type: type,
      material: material,
      category: category,
      categoryKey: categoryKey,
      color: color,
      articul: '',
      status: ProductModel.statusInStock,
      images: const [],
      attributes: attributes,
    );

Widget _host(Widget child, {double width = 320}) => MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: width, child: child),
        ),
      ),
    );

void main() {
  tearDown(() => LocaleContext.currentLang = 'ru');

  group('іздеу: сипаттамалар', () {
    test('мәтін өрісі: автор + белгі, екі тілде де', () {
      final p = _p(
          name: 'Қара сөздер',
          attributes: {'author': 'Абай', 'language': 'Казахский'});
      final g = ProductGroup([p]);
      for (final lang in ['ru', 'kk']) {
        LocaleContext.currentLang = lang;
        expect(productGroupMatches(g, 'Абай'), isTrue, reason: lang);
        expect(productGroupMatches(g, 'автор абай'), isTrue, reason: lang);
        expect(productGroupMatches(g, 'казахский'), isTrue, reason: lang);
        // Қазақша мән ru интерфейсінде де табылады (және керісінше).
        expect(productGroupMatches(g, 'қазақ тілі'), isTrue, reason: lang);
        expect(productGroupMatches(g, 'Достоевский'), isFalse, reason: lang);
      }
    });

    test('сан өрісі: «8 ГБ» және кепілдік табылады', () {
      final p = _p(categoryKey: 'phones', name: 'Samsung A15', attributes: {
        'ram_gb': '8 ГБ',
        'warranty_months': 12,
        'compatibility': 'iPhone 15',
      });
      final g = ProductGroup([p]);
      expect(productGroupMatches(g, '8 ГБ'), isTrue);
      expect(productGroupMatches(g, 'кепілдік 12'), isTrue);
      expect(productGroupMatches(g, 'гарантия 12'), isTrue);
      expect(productGroupMatches(g, 'iphone'), isTrue);
      expect(productGroupMatches(g, '16 ГБ'), isFalse);
    });

    test('мәтін/сан белгісі қосылады, chips белгісі қосылмайды', () {
      final t = attributeSearchText('phones', {
        'ram_gb': '8 ГБ',
        'warranty_months': 12,
      });
      expect(t, contains('Кепілдік'));
      expect(t, contains('Гарантия'));
      expect(t, contains('12 ай'));
      expect(t, contains('12 мес.'));
      expect(t, contains('8 ГБ'));
      expect(t, isNot(contains('Оперативная память')));
    });

    test('ағымдағы тіл қайтарылады, белгісіз кілт іздеуге түспейді', () {
      LocaleContext.currentLang = 'kk';
      attributeSearchText('books', {'author': 'Абай'});
      expect(LocaleContext.currentLang, 'kk');
      expect(attributeSearchText('books', const {}), '');
      expect(attributeSearchText('unknown', {'author': 'X'}), '');
      expect(attributeSearchText('books', {'secret_key': 'qwerty'}), '');
    });

    test('атрибуты жоқ тауардың іздеуі бұрынғыдай', () {
      final g =
          ProductGroup([_p(name: 'Кроссовки Nike', categoryKey: 'shoes')]);
      expect(productGroupMatches(g, 'nike'), isTrue);
      expect(productGroupMatches(g, 'абай'), isFalse);
      // Балл тек name/brand/type/color-дан — сипаттама әсер етпейді.
      final withAttr = ProductGroup([
        _p(name: 'Кроссовки Nike', categoryKey: 'shoes', attributes: {
          'sole': 'Резина',
        })
      ]);
      expect(productGroupScore(withAttr, 'nike'), productGroupScore(g, 'nike'));
    });
  });

  group('ProductSpecSection', () {
    final book = _p(
      name: 'Қара сөздер',
      brand: 'Жазушы',
      attributes: {
        'author': 'Абай',
        'language': 'Казахский',
        'pages': 320,
      },
    );

    testWidgets('сипаттамалар ортақ жолдардан кейін, схема ретімен',
        (tester) async {
      await tester.pumpWidget(_host(ProductSpecSection(product: book)));
      expect(find.text('Бренд'), findsOneWidget);
      expect(find.text('Автор'), findsOneWidget);
      expect(find.text('Абай'), findsOneWidget);
      expect(find.text('Язык'), findsOneWidget);
      expect(find.text('Казахский'), findsOneWidget);
      final brandY = tester.getTopLeft(find.text('Бренд')).dy;
      final authorY = tester.getTopLeft(find.text('Автор')).dy;
      final langY = tester.getTopLeft(find.text('Язык')).dy;
      expect(authorY, greaterThan(brandY));
      expect(langY, greaterThan(authorY));
    });

    testWidgets('тіл ауысқанда белгілер мен мәндер ауысады', (tester) async {
      LocaleContext.currentLang = 'kk';
      await tester.pumpWidget(_host(ProductSpecSection(product: book)));
      expect(find.text('Авторы'), findsOneWidget);
      expect(find.text('Тілі'), findsOneWidget);
      expect(find.text('Автор'), findsNothing);
    });

    testWidgets('атрибуты жоқ тауар: қосымша жол жоқ, бос тақырып жоқ',
        (tester) async {
      await tester.pumpWidget(_host(ProductSpecSection(
          product: _p(categoryKey: 'shoes', brand: 'Nike'))));
      expect(find.text('Бренд'), findsOneWidget);
      expect(find.text('Цвет'), findsNothing);
      expect(find.text('Автор'), findsNothing);

      // Мүлде ештеңе жоқ → блок да, тақырып та жоқ.
      await tester.pumpWidget(
          _host(ProductSpecSection(product: _p(categoryKey: 'shoes'))));
      expect(find.text('Характеристики'), findsNothing);
    });

    testWidgets('схемада жоқ кілт клиентке шықпайды', (tester) async {
      await tester.pumpWidget(_host(ProductSpecSection(
          product: _p(attributes: {'hidden_internal': 'zzz', 'author': 'A'}))));
      expect(find.text('zzz'), findsNothing);
      expect(find.text('Автор'), findsOneWidget);
    });

    testWidgets('түссіз тауарда «Цвет» жолы жоқ', (tester) async {
      await tester.pumpWidget(_host(ProductSpecSection(product: book)));
      expect(find.text('Цвет'), findsNothing);
    });

    // Ел орысша сақталады; негізгі ел қазақша интерфейсте қазақша көрінеді,
    // қолмен жазылғаны өзгеріссіз.
    testWidgets('ел ағымдағы тілде көрінеді', (tester) async {
      final china = _p(categoryKey: 'shoes').copyWith(country: 'Китай');
      LocaleContext.currentLang = 'kk';
      await tester.pumpWidget(_host(ProductSpecSection(product: china)));
      expect(find.text('Қытай'), findsOneWidget);
      expect(find.text('Китай'), findsNothing);

      LocaleContext.currentLang = 'ru';
      await tester.pumpWidget(_host(ProductSpecSection(product: china)));
      expect(find.text('Китай'), findsOneWidget);

      LocaleContext.currentLang = 'kk';
      final vn = _p(categoryKey: 'shoes').copyWith(country: 'Вьетнам');
      await tester.pumpWidget(_host(ProductSpecSection(product: vn)));
      expect(find.text('Вьетнам'), findsOneWidget);
    });
  });

  group('ProductGroupCard', () {
    Widget card(ProductGroup g, {double width = 320}) {
      final w = (width - 32 - 12) / 2;
      return MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: GridView.count(
                shrinkWrap: true,
                crossAxisCount: 2,
                childAspectRatio: 0.72,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                padding: const EdgeInsets.all(16),
                children: [
                  SizedBox(
                    width: w,
                    child: ProductGroupCard(
                      group: g,
                      batchesByProductId: const {},
                      storeByProductId: const {},
                      tone: 0,
                      quickAddEnabled: false,
                      onTap: (_, __) {},
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('showOnCard мәні 320 px-те асып кетпейді', (tester) async {
      final p = _p(
        name: 'Өте ұзақ атауы бар кітап: Абайдың қара сөздері толық жинағы',
        attributes: {
          'author': 'Мұхтар Омарханұлы Әуезов атындағы әдеби қор',
          'language': 'Казахский',
        },
      );
      await tester.pumpWidget(card(ProductGroup([p])));
      expect(tester.takeException(), isNull);
      expect(find.textContaining('Мұхтар'), findsOneWidget);
    });

    testWidgets('түссіз үш нұсқа: нүкте/«түс» бейджі жоқ, қате жоқ',
        (tester) async {
      final a = _p(id: 'a', attributes: {'author': 'А'});
      final b = _p(id: 'b', attributes: {'author': 'Б'});
      final c = _p(id: 'c', attributes: {'author': 'В'});
      await tester.pumpWidget(card(ProductGroup([a, b, c])));
      expect(tester.takeException(), isNull);
      expect(find.textContaining('цв.'), findsNothing);
    });

    testWidgets('түсті нұсқалар: бейдж сақталады', (tester) async {
      final vs = [
        for (final c in ['Белый', 'Черный', 'Красный'])
          _p(id: c, categoryKey: 'tshirt', color: c)
      ];
      await tester.pumpWidget(card(ProductGroup(vs)));
      expect(tester.takeException(), isNull);
      expect(find.text('3 цв.'), findsOneWidget);
    });

    testWidgets('сипаттамасыз ескі тауар өзгеріссіз', (tester) async {
      await tester.pumpWidget(
          card(ProductGroup([_p(categoryKey: 'shoes', color: 'Белый')])));
      expect(tester.takeException(), isNull);
    });
  });

  test('share-бет (product/index.ts) схемасы Dart схемасымен сәйкес', () {
    final ts = File('supabase/functions/product/index.ts').readAsStringSync();
    for (final e in kCategoryAttributes.entries) {
      expect(ts, contains('"${e.key}": ['), reason: 'категория ${e.key}');
      for (final d in e.value) {
        expect(ts, contains('["${d.key}", "${d.labelRu}", "${d.unitRu}"]'),
            reason: '${e.key}.${d.key}');
      }
    }
  });
}
