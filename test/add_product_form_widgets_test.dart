import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: implementation_imports
import 'package:google_fonts/src/google_fonts_base.dart' as fonts;
import 'package:qoima/core/lang.dart';
import 'package:qoima/data/models/category_data.dart';
import 'package:qoima/ui/admin/products/add_product_helpers.dart';
import 'package:qoima/ui/admin/products/add_product_screen.dart';
import 'package:qoima/ui/admin/products/bilingual_description.dart';
import 'package:qoima/ui/admin/products/category_groups.dart';
import 'package:qoima/ui/admin/products/category_picker.dart';
import 'package:qoima/ui/admin/products/country_chips.dart';
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

/// Форманың виджет-деңгейіндегі жаңа мінез-құлқы: түс таңдау/шешу, маусым көп
/// таңдауы, екі тілді сипаттама, категория/ел чиптері, «Тағы осындайды қосу».
void main() {
  setUpAll(() async {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    fonts.assetManifest = const _FontManifest();
    binding.defaultBinaryMessenger.setMockMessageHandler(
      'flutter/assets',
      (_) async => ByteData(4),
    );
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:9',
      publishableKey: 'test',
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
    );
  });

  void bigScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(2700, 9000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  Future<void> open(WidgetTester tester,
      {AddProductTemplate? template, AddProductMemory? memory}) async {
    bigScreen(tester);
    SharedPreferences.setMockInitialValues({
      if (memory != null) AddProductMemory.prefKey: memory.encode(),
    });
    await tester.pumpWidget(MaterialApp(
        home: AddProductScreen(key: UniqueKey(), template: template)));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pump(const Duration(milliseconds: 400));
  }

  AddProductMemory shoes() => AddProductMemory().remember(
        category: 'shoes',
        audience: 'Мужские',
        type: kTypesByCategory['shoes']!.first,
      );

  Finder colorChip(String name) => find.text(trValue(name));
  final banner = find.text(tr(
      'Размеры и фото вводятся отдельно для каждого цвета.',
      'Размерлер мен фото әр түс үшін бөлек енгізіледі.'));

  group('түс: басу = таңдау, қайта басу = алу', () {
    testWidgets('бір түс бір-ақ рет; қайта басса алынады; ескі UI жоқ',
        (tester) async {
      await open(tester, memory: shoes());
      expect(find.byIcon(Icons.check_rounded), findsNothing);

      await tester.tap(colorChip('Белый'));
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);

      // Қайта басу — дубль қоспайды, түсті алады (деректі жоқ: диалогсыз).
      await tester.tap(colorChip('Белый'));
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.byIcon(Icons.check_rounded), findsNothing);

      // «Айырмашылық» өрісі мен «×2» белгісі жоқ.
      expect(find.textContaining('Айырмашылық'), findsNothing);
      expect(find.textContaining('Отличие'), findsNothing);
      expect(find.textContaining('×'), findsNothing);
    });

    testWidgets('түсіндірме жолақ тек 2+ түс болғанда көрінеді',
        (tester) async {
      await open(tester, memory: shoes());
      expect(banner, findsNothing);

      await tester.tap(colorChip('Белый'));
      await tester.pump(const Duration(milliseconds: 250));
      expect(banner, findsNothing); // 1 түс

      await tester.tap(colorChip('Черный'));
      await tester.pump(const Duration(milliseconds: 250));
      expect(banner, findsOneWidget); // 2 түс
      expect(find.byIcon(Icons.check_rounded), findsNWidgets(2));

      await tester.tap(colorChip('Черный'));
      await tester.pump(const Duration(milliseconds: 250));
      expect(banner, findsNothing);
    });

    testWidgets(
        'жылдам код бар түсті алу: «Оставить» қалдырады, «Убрать» алады',
        (tester) async {
      await open(tester, memory: shoes());
      await tester.tap(colorChip('Белый'));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.tap(find.text(tr('Дополнительно', 'Қосымша')));
      await tester.pump();

      final codeField = find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.hintText == '№ 103');
      expect(codeField, findsOneWidget);
      await tester.enterText(codeField, '103');
      await tester.pump();

      await tester.tap(colorChip('Белый').first);
      await tester.pump(const Duration(milliseconds: 250));
      final title = tr('Убрать цвет «${trValue('Белый')}»?',
          '«${trValue('Белый')}» түсін алып тастау керек пе?');
      expect(find.text(title), findsOneWidget);

      await tester.tap(find.text(tr('Оставить', 'Қалдыру')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);

      await tester.tap(colorChip('Белый').first);
      await tester.pump(const Duration(milliseconds: 250));
      await tester.tap(find.text(tr('Убрать', 'Алып тастау')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byIcon(Icons.check_rounded), findsNothing);
      expect(codeField, findsNothing); // түс жоқ — код өрісі де жоқ
    });
  });

  group('маусым: бірнешеуін таңдауға болады', () {
    testWidgets('екі-үш чип бір мезгілде таңдалады, қайта басса алынады',
        (tester) async {
      await open(tester, memory: shoes());
      await tester.tap(find.text(tr('Дополнительно', 'Қосымша')));
      await tester.pump();

      Finder chip(String s) => find.textContaining(trValue(s));
      Color? colorOf(String s) =>
          tester.widget<Text>(chip(s).first).style?.color;

      for (final s in ['Лето', 'Зима', 'Осень']) {
        await tester.tap(chip(s).first);
        await tester.pump(const Duration(milliseconds: 250));
      }
      for (final s in ['Лето', 'Зима', 'Осень']) {
        expect(colorOf(s), Colors.white, reason: '$s таңдалған');
      }
      expect(colorOf('Весна'), isNot(Colors.white));

      await tester.tap(chip('Зима').first);
      await tester.pump(const Duration(milliseconds: 250));
      expect(colorOf('Зима'), isNot(Colors.white));
      expect(colorOf('Лето'), Colors.white);
      expect(colorOf('Осень'), Colors.white);
    });
  });

  group('екі тілді сипаттама', () {
    Widget host(TextEditingController ru, TextEditingController kk, String lang,
            ValueChanged<String> onLang,
            {VoidCallback? onTranslate}) =>
        MaterialApp(
          home: Scaffold(
            body: BilingualDescriptionField(
              ruCtrl: ru,
              kkCtrl: kk,
              lang: lang,
              onLangChanged: onLang,
              onTranslate: onTranslate,
              decoration: const InputDecoration(),
            ),
          ),
        );

    testWidgets('РУС | ҚАЗ ауысқанда мәтіндер араласпайды, екеуі де сақталады',
        (tester) async {
      final ru = TextEditingController(text: 'Лёгкие кроссовки');
      final kk = TextEditingController();
      var lang = 'ru';
      late StateSetter set;
      await tester.pumpWidget(StatefulBuilder(builder: (c, s) {
        set = s;
        return host(ru, kk, lang, (l) => set(() => lang = l));
      }));

      String shown() => tester
          .widget<TextFormField>(find.byType(TextFormField))
          .controller!
          .text;
      expect(shown(), 'Лёгкие кроссовки');

      await tester.tap(find.text('ҚАЗ'));
      await tester.pump();
      expect(shown(), ''); // қазақша бос
      await tester.enterText(find.byType(TextFormField), 'Жеңіл кроссовка');
      await tester.pump();
      expect(kk.text, 'Жеңіл кроссовка');
      expect(ru.text, 'Лёгкие кроссовки'); // орысша өзгермеді

      await tester.tap(find.text('РУС'));
      await tester.pump();
      expect(shown(), 'Лёгкие кроссовки');
    });

    testWidgets('«Аудару» батырмасы onTranslate берілгенде ғана көрінеді',
        (tester) async {
      final ru = TextEditingController(text: 'Текст');
      final kk = TextEditingController();
      await tester.pumpWidget(host(ru, kk, 'kk', (_) {}));
      expect(find.byIcon(Icons.translate_rounded), findsNothing);

      var taps = 0;
      await tester
          .pumpWidget(host(ru, kk, 'kk', (_) {}, onTranslate: () => taps++));
      expect(find.byIcon(Icons.translate_rounded), findsOneWidget);
      await tester.tap(find.byIcon(Icons.translate_rounded));
      expect(taps, 1);
    });

    test('қолданба тілі = бастапқы таб; қарсы тіл', () {
      expect(otherDescriptionLang('ru'), 'kk');
      expect(otherDescriptionLang('kk'), 'ru');
      expect(['ru', 'kk'], contains(defaultDescriptionLang()));
    });

    testWidgets('форма: екі сипаттама да «Дополнительно» санына кіреді',
        (tester) async {
      await open(tester, memory: shoes());
      await tester.tap(find.text(tr('Дополнительно', 'Қосымша')));
      await tester.pump();
      await tester.tap(find.text('ҚАЗ'));
      await tester.pump();
      await tester.enterText(find.byType(TextFormField).last, 'Жеңіл');
      await tester.pump();
      // Тек қазақша мәтін де «толтырылған» болып саналады.
      await tester.tap(find.textContaining(tr('Дополнительно', 'Қосымша')));
      await tester.pump();
      expect(
        find.text(tr('Дополнительно · заполнено 1', 'Қосымша · 1 толтырылды')),
        findsOneWidget,
      );
    });
  });

  group('категория таңдағыш', () {
    testWidgets('алғашқы қатар + «Басқа санаттар»: барлық 29 категория топта',
        (tester) async {
      bigScreen(tester);
      String? picked;
      final primary = primaryCategoryKeys(counts: const {'shoes': 3});
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CategoryPicker(
                selected: null,
                primaryKeys: primary,
                onSelected: (k) => picked = k),
          ),
        ),
      ));
      // Жабық: тек алғашқы чиптер + «Другие категории».
      expect(
          find.text(tr('Другие категории', 'Басқа санаттар')), findsOneWidget);
      expect(
          find.text(
              tr(kCategoryGroups.first.titleRu, kCategoryGroups.first.titleKk)),
          findsNothing);

      await tester.tap(find.text(tr('Другие категории', 'Басқа санаттар')));
      await tester.pump();
      for (final g in kCategoryGroups) {
        expect(find.text(tr(g.titleRu, g.titleKk)), findsOneWidget);
      }
      // Іздеу
      await tester.enterText(find.byType(TextField), 'qwertyuiop');
      await tester.pump();
      expect(find.text(tr('Ничего не найдено', 'Ештеңе табылмады')),
          findsOneWidget);
      await tester.enterText(find.byType(TextField), '');
      await tester.pump();

      // Тізімнен таңдау бұрынғыдай кілтті қайтарады және тізімді жабады.
      final target = categoryByKey('garden');
      await tester.tap(find.text(target.short).last);
      await tester.pump(const Duration(milliseconds: 200));
      expect(picked, 'garden');
      expect(
          find.text(tr('Ничего не найдено', 'Ештеңе табылмады')), findsNothing);
    });

    testWidgets('форма: таңдалған категория бірінші қатарда көрінеді',
        (tester) async {
      await open(tester,
          template: const AddProductTemplate(categoryKey: 'garden'));
      expect(find.text(categoryByKey('garden').short), findsOneWidget);
    });
  });

  group('ел чиптері', () {
    testWidgets('таңдалған чипті қайта бассаң тазаланады; «Басқа» өрісті ашады',
        (tester) async {
      bigScreen(tester);
      final ctrl = TextEditingController();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CountryPicker(
              controller: ctrl,
              used: const ['Вьетнам'],
              fieldBuilder: () =>
                  TextField(controller: ctrl, key: const Key('f')),
            ),
          ),
        ),
      ));
      expect(find.byKey(const Key('f')), findsNothing);

      await tester.tap(find.text('Вьетнам'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(ctrl.text, 'Вьетнам');

      await tester.tap(find.text('Вьетнам'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(ctrl.text, '');

      // Негізгі ел орысша сақталады, экранда ағымдағы тілде.
      await tester.tap(find.text(countryLabel('Китай')));
      await tester.pump(const Duration(milliseconds: 200));
      expect(ctrl.text, 'Китай');

      await tester.tap(find.text(tr('Другая', 'Басқа')));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byKey(const Key('f')), findsOneWidget);
    });

    testWidgets('қолмен жазылған ел чипте жоқ болса — өріс көрінеді',
        (tester) async {
      final ctrl = TextEditingController(text: 'Бразилия');
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CountryPicker(
              controller: ctrl,
              used: const [],
              fieldBuilder: () =>
                  TextField(controller: ctrl, key: const Key('f')),
            ),
          ),
        ),
      ));
      expect(find.byKey(const Key('f')), findsOneWidget);
    });
  });

  group('«Тағы осындайды қосу»', () {
    testWidgets('үлгі: ортақ өрістер толады, түс/размер/код жоқ',
        (tester) async {
      final type = kTypesByCategory['shoes']!.first;
      await open(
        tester,
        template: AddProductTemplate(
          categoryKey: 'shoes',
          type: type,
          audience: 'Мужские',
          name: 'Air Max',
          brand: 'Nike',
          season: 'Лето,Зима',
          country: 'Китай',
          description: 'Описание',
          descriptionKk: 'Сипаттама',
          purchase: '10000',
          selling: '15000',
        ),
      );
      TextFormField field(String label) => tester
          .widget<TextFormField>(find.widgetWithText(TextFormField, label));
      expect(field(tr('Название товара *', 'Тауар атауы *')).controller!.text,
          'Air Max');
      expect(field(tr('Бренд *', 'Бренд *')).controller!.text, 'Nike');
      // Түс таңдалмаған: тауар жаңа, түсін иесі өзі таңдайды.
      expect(find.byIcon(Icons.check_rounded), findsNothing);
      expect(banner, findsNothing);
      // Үлгіде мәні бар «Дополнительно» өздігінен ашық (маусым, ел, сипаттама).
      expect(
          find.textContaining(tr('заполнено', 'толтырылды')), findsOneWidget);
    });

    testWidgets('жарамсыз категориялы үлгі еленбейді (құламайды)',
        (tester) async {
      await open(tester,
          template: const AddProductTemplate(categoryKey: 'gone_forever'));
      expect(
        find.text(tr('Выберите категорию — остальные поля подстроятся под неё',
            'Категорияны таңдаңыз — қалған өрістер соған бейімделеді')),
        findsOneWidget,
      );
    });
  });
}
