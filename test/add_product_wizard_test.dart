import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: implementation_imports
import 'package:google_fonts/src/google_fonts_base.dart' as fonts;
import 'package:qoima/core/lang.dart';
import 'package:qoima/data/models/category_data.dart';
import 'package:qoima/ui/admin/products/add_product_helpers.dart';
import 'package:qoima/ui/admin/products/add_product_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FontManifest implements AssetManifest {
  const _FontManifest();
  @override
  List<String> listAssets() => const [
        'fake/Inter-Regular.ttf',
        'fake/Inter-Medium.ttf',
        'fake/Inter-SemiBold.ttf',
        'fake/Inter-Bold.ttf',
        'fake/Inter-ExtraBold.ttf',
      ];
  @override
  List<AssetMetadata>? getAssetVariants(String key) => null;
}

void main() {
  late String shoesType;

  setUpAll(() async {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    fonts.assetManifest = const _FontManifest();
    binding.defaultBinaryMessenger.setMockMessageHandler(
      'flutter/assets',
      (_) async => ByteData(4),
    );
    SharedPreferences.setMockInitialValues({});
    // Форманың сервистері клиентті конструкторда алады. Желі жоқ: сұраулар
    // сәтсіз аяқталады, ал форма олсыз да жұмыс істеуі керек.
    await Supabase.initialize(
      url: 'http://127.0.0.1:9',
      publishableKey: 'test',
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
    );
    shoesType = kTypesByCategory['shoes']!.first;
  });

  Future<void> open(WidgetTester tester, {AddProductMemory? memory}) async {
    // Тест қарпі (әр әріп — шаршы) нағыз қаріптен әлдеқайда кең, сондықтан экран
    // әдейі кең: тек орналасу тестілері үшін.
    tester.view.physicalSize = const Size(2700, 9000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({
      if (memory != null) AddProductMemory.prefKey: memory.encode(),
    });
    await tester
        .pumpWidget(MaterialApp(home: AddProductScreen(key: UniqueKey())));
    // SharedPreferences + сәтсіз желі сұраулары бітуі үшін.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pump(const Duration(milliseconds: 400));
  }

  // AnimatedSwitcher ескі қадамды келесі кадрда ғана алып тастайды.
  Future<void> settleStep(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
  }

  Future<void> next(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(ElevatedButton, 'Далее →'));
    await settleStep(tester);
  }

  Future<void> fillStepZero(WidgetTester tester) async {
    await tester.enterText(
      find.widgetWithText(
          TextFormField, tr('Название товара *', 'Тауар атауы *')),
      'Air Max',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, tr('Бренд *', 'Бренд *')),
      'Nike',
    );
    await tester.pump();
    await tester.tap(find.text(trValue('Белый')).first);
    await tester.pump(const Duration(milliseconds: 250));
  }

  void expectSnack(String text) => expect(find.text(text), findsOneWidget);

  Future<void> clearSnack(WidgetTester tester) async {
    ScaffoldMessenger.of(tester.element(find.byType(Scaffold).first))
        .clearSnackBars();
    // Snackbar төменгі батырманы жауып тұрады: толық кеткенше күтеміз.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
  }

  AddProductMemory shoes({double? purchase, double? selling}) =>
      const AddProductMemory().remember(
        category: 'shoes',
        audience: 'Мужские',
        type: shoesType,
        purchase: purchase,
        selling: selling,
      );

  testWidgets('жады жоқ: ештеңе алдын ала таңдалмайды, 3 қадам',
      (tester) async {
    await open(tester);
    expect(find.text(tr('Цена и размеры', 'Баға мен өлшем')), findsOneWidget);
    expect(find.text(tr('Цены', 'Бағалар')), findsNothing);
    expect(find.text(tr('Размеры', 'Өлшемдер')), findsNothing);
    expect(
      find.text(tr('Выберите категорию — остальные поля подстроятся под неё',
          'Категорияны таңдаңыз — қалған өрістер соған бейімделеді')),
      findsOneWidget,
    );
  });

  testWidgets('жады: категория/кімге/түр қойылады, каталогта жоғы қойылмайды',
      (tester) async {
    await open(tester, memory: shoes());
    expect(find.text(trValue(shoesType)), findsWidgets);
    expect(
      find.text(tr('Выберите категорию — остальные поля подстроятся под неё',
          'Категорияны таңдаңыз — қалған өрістер соған бейімделеді')),
      findsNothing,
    );

    await open(
      tester,
      memory: AddProductMemory.parse(jsonEncode({'category': 'gone_forever'})),
    );
    expect(
      find.text(tr('Выберите категорию — остальные поля подстроятся под неё',
          'Категорияны таңдаңыз — қалған өрістер соған бейімделеді')),
      findsOneWidget,
    );
  });

  testWidgets('«Дополнительно» жабық, міндетті өрістер көрінеді, ашылады',
      (tester) async {
    await open(tester, memory: shoes());
    final country = find.widgetWithText(
      TextFormField,
      tr('Страна производства (необязательно)',
          'Өндірілген ел (міндетті емес)'),
    );
    expect(country, findsNothing);
    expect(
      find.widgetWithText(
          TextFormField, tr('Название товара *', 'Тауар атауы *')),
      findsOneWidget,
    );

    await tester.tap(find.text(tr('Дополнительно', 'Қосымша')));
    await tester.pump();
    // Ел — чиптер; мәтін өрісі «Басқа» басылғанда ғана ашылады.
    expect(country, findsNothing);
    await tester.tap(find.text(tr('Другая', 'Басқа')));
    await tester.pump();
    expect(country, findsOneWidget);

    await tester.enterText(country, 'Вьетнам');
    await tester.pump();
    // Мәні бар: жауып, қайта кіргенде жасырылмайды (қадам ауысқанда құрылады).
    await tester.tap(find.textContaining(tr('Дополнительно', 'Қосымша')));
    await tester.pump();
    expect(country, findsNothing);
    expect(
      find.text(tr('Дополнительно · заполнено 1', 'Қосымша · 1 толтырылды')),
      findsOneWidget,
    );
  });

  testWidgets('атау ұсынысы: түрі мен бренді бар, атау бос', (tester) async {
    await open(tester, memory: shoes());
    final expected = '${trValue(shoesType)} Nike';
    expect(find.text(expected), findsNothing);

    await tester.enterText(
      find.widgetWithText(TextFormField, tr('Бренд *', 'Бренд *')),
      'Nike',
    );
    await tester.pump();
    expect(find.text(expected), findsOneWidget);

    await tester.tap(find.text(expected));
    await tester.pump();
    expect(find.text(expected), findsOneWidget); // енді өрістің мәні
    final name = tester.widget<TextFormField>(
      find.widgetWithText(
          TextFormField, tr('Название товара *', 'Тауар атауы *')),
    );
    expect(name.controller!.text, expected);
    // Атау толды: чип кетті, тек өріс қалды.
    expect(find.byIcon(Icons.auto_fix_high_rounded), findsNothing);
  });

  testWidgets('шебер: баға мен размер бір қадамда, тексеру реті, +1 / минус',
      (tester) async {
    await open(tester, memory: shoes());
    await fillStepZero(tester);
    await next(tester);

    // Екеуі де бір экранда.
    final purchase = find.byType(TextField).at(0);
    final selling = find.byType(TextField).at(1);
    expect(
        find.text(tr('Закупочная цена', 'Сатып алу бағасы')), findsOneWidget);
    expect(find.text(tr('Размеры и количество', 'Өлшемдер мен саны')),
        findsOneWidget);

    // Бос баға.
    await next(tester);
    expectSnack(tr('Введите закупочную цену', 'Сатып алу бағасын енгізіңіз'));
    await clearSnack(tester);

    // "." сан емес.
    await tester.enterText(purchase, '.');
    await tester.pump();
    await next(tester);
    expectSnack(tr(
        'Закупочная цена указана неверно', 'Сатып алу бағасы қате жазылған'));
    await clearSnack(tester);

    // Закуп 0 болуы мүмкін, сату 0 болмайды.
    await tester.enterText(purchase, '0');
    await tester.enterText(selling, '0');
    await tester.pump();
    await next(tester);
    expectSnack(tr('Цена продажи должна быть больше нуля',
        'Сату бағасы нөлден үлкен болуы керек'));
    await clearSnack(tester);

    await tester.enterText(selling, '15000');
    await tester.pump();

    // Баға дұрыс, размер жоқ.
    await next(tester);
    expect(find.textContaining(tr('Укажите количество', 'нұсқасына сан')),
        findsOneWidget);
    await clearSnack(tester);

    // Басу = +1, минус азайтады, 0-де минус жоқ.
    const size = '39'; // `Мужские` торындағы бірінші размер
    final cell = find.text(size);
    await tester.tap(cell);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(cell);
    await tester.pump(const Duration(milliseconds: 200));
    expect(
        find.text(tr('2 шт.', '2 дана')), findsNWidgets(2)); // ұяшық + «Итого»
    final minus = find.byIcon(Icons.remove_rounded);
    expect(minus, findsOneWidget);
    await tester.tap(minus);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text(tr('1 шт.', '1 дана')), findsNWidgets(2));

    // Ұзақ басу = нақты сан парақшасы.
    await tester.longPress(cell);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text(tr('Размер $size', 'Өлшем $size')), findsOneWidget);
    await tester.tap(find.text(tr('Готово', 'Дайын')));
    await tester.pump(const Duration(milliseconds: 400));

    // Соңғы қадам: екі тікелей батырма, ескі «Добавить фото» жоқ.
    await next(tester);
    expect(find.text(tr('Камера', 'Камера')), findsOneWidget);
    expect(find.text(tr('Галерея', 'Галерея')), findsOneWidget);
    expect(find.text(tr('Добавить фото', 'Фото қосу')), findsNothing);
    expect(
      find.widgetWithText(
          ElevatedButton, tr('Сохранить товар', 'Тауарды сақтау')),
      findsOneWidget,
    );

    // Жүйелік «артқа» алдыңғы қадамға апарады, форманы жаппайды.
    await tester.binding.handlePopRoute();
    await settleStep(tester);
    expect(find.text(tr('Размеры и количество', 'Өлшемдер мен саны')),
        findsOneWidget);
    await tester.binding.handlePopRoute();
    await settleStep(tester);
    expect(find.text(tr('Информация о товаре', 'Тауар туралы ақпарат')),
        findsOneWidget);
  });

  testWidgets('өткен баға чип болып тұрады, өзі толмайды', (tester) async {
    await open(tester, memory: shoes(purchase: 8000, selling: 12000));
    await fillStepZero(tester);
    await next(tester);

    final purchase = find.byType(TextField).at(0);
    final selling = find.byType(TextField).at(1);
    final sellChip = find.text(tr('Прошлая: 12 000 ₸', 'Соңғы: 12 000 ₸'));
    expect(find.text(tr('Прошлая: 8 000 ₸', 'Соңғы: 8 000 ₸')), findsOneWidget);
    expect(sellChip, findsOneWidget);
    // Үнсіз толтырылмаған.
    expect(tester.widget<TextField>(purchase).controller!.text, isEmpty);
    expect(tester.widget<TextField>(selling).controller!.text, isEmpty);

    await tester.tap(sellChip);
    await tester.pump();
    expect(tester.widget<TextField>(selling).controller!.text, '12000');
    expect(sellChip, findsNothing);
  });
}
