import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qoima/core/locale_context.dart';
import 'package:qoima/data/models/cart_item_model.dart';
import 'package:qoima/data/models/order_model.dart';
import 'package:qoima/data/models/return_policy.dart';
import 'package:qoima/ui/client/return_notice_sheet.dart';

const _defectFooter =
    'Если товар с браком, ваши права защищает закон о защите прав потребителей.';

CartItemModel _item(String id, String name, {bool nonReturnable = false}) =>
    CartItemModel.fromJson({
      'productId': id,
      'productName': name,
      'nonReturnable': nonReturnable,
    });

Future<void> _pump(
  WidgetTester tester,
  ReturnPolicy policy, {
  List<CartItemModel> items = const [],
  bool kazpost = false,
}) =>
    tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ReturnPolicyBody(policy, items: items, kazpost: kazpost),
        ),
      ),
    ));

void main() {
  setUpAll(() {
    // Тестте желі жоқ: manrope() шрифтті жүктеуге тырыспасын.
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  setUp(() => LocaleContext.currentLang = 'ru');

  testWidgets('без возврата: анық мәлімдеме, ескертпе, ақау жолы', (t) async {
    await _pump(
      t,
      const ReturnPolicy(
        mode: ReturnPolicy.modeNone,
        conditions: ['tags'],
        note: 'Товар штучный',
      ),
      items: [_item('p1', 'Куртка', nonReturnable: true)],
    );
    expect(find.text('Этот магазин не принимает возврат'), findsOneWidget);
    expect(find.text('Товар штучный'), findsOneWidget);
    expect(find.text(_defectFooter), findsOneWidget);
    // Мерзім мен шарттар бұл режимде мәнсіз, тауар тізімі де қайталанбайды.
    expect(find.textContaining('в течение'), findsNothing);
    expect(find.text('Сохранены бирки и ярлыки'), findsNothing);
    expect(find.textContaining('Куртка'), findsNothing);
  });

  testWidgets('шартпен: мерзім, шарттар, белгісіз код өтпейді', (t) async {
    await _pump(
      t,
      const ReturnPolicy(
        days: 14,
        conditions: ['tags', 'receipt', 'code_from_future'],
        note: 'Звоните заранее',
      ),
    );
    expect(find.text('Возврат в течение 14 дней'), findsOneWidget);
    expect(find.text('Срок считается со дня получения'), findsOneWidget);
    expect(find.text('Сохранены бирки и ярлыки'), findsOneWidget);
    expect(find.text('Есть чек или номер заказа'), findsOneWidget);
    expect(find.text('Звоните заранее'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsNWidgets(2));
    expect(find.text(_defectFooter), findsOneWidget);
    expect(find.text('Этот магазин не принимает возврат'), findsNothing);
  });

  testWidgets('орысша септік: 21 дня', (t) async {
    await _pump(t, const ReturnPolicy(days: 21));
    expect(find.text('Возврат в течение 21 дня'), findsOneWidget);
  });

  testWidgets('тауар деңгейі: қайтарылмайтыны және ескертпелері', (t) async {
    await _pump(
      t,
      const ReturnPolicy(productNotes: {
        'p1': 'Гигиена',
        'p2': 'Без коробки не принимаем',
        'gone': 'Этого товара нет в заказе',
      }),
      items: [
        _item('p1', 'Бельё', nonReturnable: true),
        _item('p1', 'Бельё', nonReturnable: true), // екінші өлшем
        _item('p2', 'Кроссовки'),
        _item('p3', 'Шапка'),
      ],
    );
    expect(find.text('«Бельё» — возврату не подлежит'), findsOneWidget);
    expect(find.text('Гигиена'), findsOneWidget);
    expect(find.text('«Кроссовки»'), findsOneWidget);
    expect(find.text('Без коробки не принимаем'), findsOneWidget);
    expect(find.textContaining('Шапка'), findsNothing);
    expect(find.text('Этого товара нет в заказе'), findsNothing);
    expect(find.text(_defectFooter), findsOneWidget);
  });

  testWidgets('Казпочта жолы тек Казпочта тапсырысында', (t) async {
    await _pump(t, const ReturnPolicy());
    expect(find.textContaining('Стоимость пересылки'), findsNothing);

    await _pump(t, const ReturnPolicy(), kazpost: true);
    expect(find.textContaining('Стоимость пересылки не возвращается'),
        findsOneWidget);
    expect(find.text(_defectFooter), findsOneWidget);
  });

  testWidgets('без возврата + Казпочта: почтамен кері жіберу туралы жол жоқ',
      (t) async {
    await _pump(t, const ReturnPolicy(mode: ReturnPolicy.modeNone),
        kazpost: true);
    expect(find.text('Этот магазин не принимает возврат'), findsOneWidget);
    expect(find.textContaining('Стоимость пересылки'), findsNothing);
    expect(find.text(_defectFooter), findsOneWidget);
  });

  testWidgets('accept, бірақ бәрі қайтарылмайды: мерзім емес, баннер шығады',
      (t) async {
    await _pump(
      t,
      const ReturnPolicy(
          days: 14, conditions: ['tags'], productNotes: {'p1': 'Гигиена'}),
      items: [_item('p1', 'Бельё', nonReturnable: true)],
      kazpost: true,
    );
    expect(
        find.text('Товары этого заказа не подлежат возврату'), findsOneWidget);
    expect(find.textContaining('в течение'), findsNothing);
    expect(find.text('Сохранены бирки и ярлыки'), findsNothing);
    expect(find.textContaining('Стоимость пересылки'), findsNothing);
    expect(find.text('«Бельё»'), findsOneWidget);
    expect(find.text('Гигиена'), findsOneWidget);
    expect(find.text(_defectFooter), findsOneWidget);
  });

  testWidgets('Казпочта: мерзім тапсырыс жабылған күннен, нақты күні көрінеді',
      (t) async {
    await _pump(t, const ReturnPolicy(), kazpost: true);
    expect(find.text('Срок считается со дня получения'), findsNothing);
    expect(find.text('Срок считается со дня, когда заказ отмечен полученным'),
        findsOneWidget);
    expect(find.textContaining('Последний день'), findsNothing);

    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ReturnPolicyBody(const ReturnPolicy(),
            kazpost: true, deadline: DateTime(2026, 11, 5, 12)),
      ),
    ));
    expect(find.text('Последний день: 05.11.2026'), findsOneWidget);
  });

  test('жүйе орындай алмайтын шарт ұсынылмайды', () {
    expect(ReturnPolicy.conditionCodes,
        ['tags', 'unused', 'packaging', 'receipt']);
    expect(ReturnPolicy.conditionLabel('exchange_only'), isEmpty);
    expect(ReturnPolicy.conditionLabel('defect_only'), isEmpty);
  });

  testWidgets('парақта қайтаруға шақыратын батырма жоқ, ack қатесі құлатпайды',
      (t) async {
    final order = OrderModel.fromMap(const {
      'id': 'o1',
      'store_name': 'Дүкен',
      'order_number': 7,
      'items': [],
      'order_type': OrderModel.typeDelivery,
      'delivery_mode': OrderModel.deliveryByKazpost,
      'status': OrderModel.statusCompleted,
      'return_policy': {'mode': 'accept', 'days': 14},
    });
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showReturnNoticeSheet(context, order),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();

    expect(find.text('Условия возврата этого магазина'), findsOneWidget);
    expect(find.text('Дүкен · Заказ №00007'), findsOneWidget);
    expect(find.textContaining('Оформить'), findsNothing);

    // Сыртын басу жаппайды.
    await t.tapAt(const Offset(10, 10));
    await t.pumpAndSettle();
    expect(find.text('Понятно'), findsOneWidget);

    // Supabase тестте жоқ, яғни ack қате береді. Парақ бәрібір жабылады.
    await t.tap(find.text('Понятно'));
    await t.pumpAndSettle();
    expect(find.text('Понятно'), findsNothing);
    expect(t.takeException(), isNull);
  });
}
