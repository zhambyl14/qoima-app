import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: implementation_imports
import 'package:google_fonts/src/google_fonts_base.dart' as fonts;
import 'package:qoima/core/lang.dart';
import 'package:qoima/data/models/category_data.dart';
import 'package:qoima/ui/admin/products/add_product_helpers.dart';
import 'package:qoima/ui/admin/products/add_product_screen.dart';
import 'package:qoima/ui/admin/products/category_attributes_editor.dart';
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

/// Қосу формасы категорияға бейімделеді: өз сипаттамалары, түссіз категорияда
/// түс жоқ (жасырын нұсқа), маусым тек киімге, міндетті сипаттама тексерісі.
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

  Future<void> open(WidgetTester tester, AddProductTemplate template) async {
    tester.view.physicalSize = const Size(2700, 9000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(MaterialApp(
        home: AddProductScreen(key: UniqueKey(), template: template)));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> next(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(ElevatedButton, 'Далее →'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
  }

  Future<void> clearSnack(WidgetTester tester) async {
    ScaffoldMessenger.of(tester.element(find.byType(Scaffold).first))
        .clearSnackBars();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
  }

  AddProductTemplate book({Map<String, dynamic> attributes = const {}}) =>
      AddProductTemplate(
        categoryKey: 'books',
        type: kTypesByCategory['books']!.first,
        name: 'Абай жолы',
        brand: 'Фолиант',
        attributes: attributes,
      );

  final colorLabel = find.text(tr('Цвет *', 'Түсі *'));

  testWidgets('кітап: түс жоқ, сипаттама бар, тіл міндетті, размер «Один»',
      (tester) async {
    await open(tester, book());
    expect(colorLabel, findsNothing);
    expect(find.byType(CategoryAttributesEditor), findsOneWidget);
    expect(find.text(tr('Язык *', 'Тілі *')), findsOneWidget);
    expect(find.text(tr('Автор', 'Авторы')), findsOneWidget);

    // Тіл таңдалмаған — әрі қарай өтпейді, нақты өрісті атайды.
    await next(tester);
    expect(
        find.text(tr('Укажите «Язык» в характеристиках',
            'Сипаттамада «Тілі» көрсетіңіз')),
        findsOneWidget);
    expect(find.text(tr('Обязательное поле', 'Міндетті өріс')), findsOneWidget);
    await clearSnack(tester);

    await tester.tap(find.text(trValue('Русский')));
    await tester.pump();
    await next(tester);
    // 2-қадам: түс табтары жоқ, жалғыз нұсқаның «Один размер» торы.
    expect(find.text('Один размер'), findsOneWidget);
    expect(
        find.text(tr('Итого в партии:', 'Партияда барлығы:')), findsOneWidget);
  });

  testWidgets('кітап: «Дополнительно» ішінде маусым мен материал жоқ',
      (tester) async {
    await open(tester, book(attributes: {'language': 'Русский'}));
    await tester.tap(find.textContaining(tr('Дополнительно', 'Қосымша')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(tr('Сезон (необязательно)', 'Сезон (міндетті емес)')),
        findsNothing);
    expect(
        find.text(tr('Материал (необязательно)', 'Материал (міндетті емес)')),
        findsNothing);
    // Жылдам нөмір — жалғыз тауарға, түс атауынсыз.
    expect(find.text(tr('Этот товар', 'Осы тауар')), findsOneWidget);
  });

  testWidgets('аяқ киім: түс пен маусым бұрынғыдай, өз сипаттамалары',
      (tester) async {
    await open(
        tester,
        AddProductTemplate(
          categoryKey: 'shoes',
          type: kTypesByCategory['shoes']!.first,
          audience: 'Мужские',
          name: 'Air Max',
          brand: 'Nike',
        ));
    expect(colorLabel, findsOneWidget);
    expect(find.text(tr('Каблук', 'Өкшесі')), findsOneWidget);
    expect(find.text(tr('Язык *', 'Тілі *')), findsNothing);
    // Түс таңдалмаса өтпейді (түсті категория).
    await next(tester);
    expect(
        find.text(tr('Выберите хотя бы один цвет', 'Кемінде бір түс таңдаңыз')),
        findsWidgets);
  });

  testWidgets('сипаттама толы — категория ауысқанда сұрайды, бас тартса қалады',
      (tester) async {
    await open(tester, book(attributes: {'language': 'Русский'}));
    final shoesChip = find.text(categoryByKey('shoes').short);
    expect(shoesChip, findsWidgets);
    await tester.tap(shoesChip.first);
    await tester.pump(const Duration(milliseconds: 300));
    expect(
        find.text(tr('Сменить категорию?', 'Категорияны ауыстыру керек пе?')),
        findsOneWidget);
    await tester.tap(find.text(tr('Отмена', 'Болдырмау')));
    await tester.pump(const Duration(milliseconds: 300));
    // Бас тартты: кітап күйінде, тіл таңдалған қалпы.
    expect(colorLabel, findsNothing);
    expect(find.text(tr('Язык *', 'Тілі *')), findsOneWidget);

    await tester.tap(shoesChip.first);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text(tr('Сменить', 'Ауыстыру')));
    await tester.pump(const Duration(milliseconds: 300));
    // Аяқ киімге ауысты: түс қайта шықты, кітап өрістері жоқ.
    expect(colorLabel, findsOneWidget);
    expect(find.text(tr('Язык *', 'Тілі *')), findsNothing);
    expect(find.text(tr('Каблук', 'Өкшесі')), findsOneWidget);
  });
}
