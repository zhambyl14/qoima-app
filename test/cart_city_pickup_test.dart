import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:qoima/core/app_user.dart';
import 'package:qoima/core/feature_flags.dart';
import 'package:qoima/core/locale_context.dart';
import 'package:qoima/data/models/cart_item_model.dart';
import 'package:qoima/l10n/app_localizations.dart';
import 'package:qoima/ui/client/client_cart_screen.dart';
import 'package:qoima/ui/client/client_shell.dart' show CartProvider;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Желісіз бэкенд: екі дүкен — «Алма» (Алматы) мен «Нур» (Астана).
class _Backend extends http.BaseClient {
  http.BaseRequest? _current;

  http.StreamedResponse _json(Object? body, [int status = 200]) =>
      http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(body))),
        status,
        request: _current,
        headers: {'content-type': 'application/json'},
      );

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    _current = request;
    final path = request.url.path;
    if (path.endsWith('/rpc/feature_flags')) {
      return _json({FeatureFlags.giftLinks: true});
    }
    if (path.endsWith('/rpc/delivery_tariff')) return _json(const {});
    if (path.endsWith('/rest/v1/products')) {
      final owner =
          (request.url.queryParameters['owner_uid'] ?? '').replaceFirst('eq.', '');
      return _json([
        for (final id in const ['p1', 'p2'])
          {
            'id': '$id-$owner',
            'title': 'Товар $id',
            'owner_uid': owner,
            'images': ['x.png'],
          }
      ]);
    }
    if (path.endsWith('/rest/v1/stores')) {
      return _json([
        {
          'admin_uid': 'alma',
          'store_name': 'Алма',
          'city': 'Алматы',
          'is_published': true,
          'visible_warehouse_ids': ['w-alma'],
        },
        {
          'admin_uid': 'nur',
          'store_name': 'Нур',
          'city': 'Астана',
          'is_published': true,
          'visible_warehouse_ids': ['w-nur'],
        },
      ]);
    }
    if (path.endsWith('/rest/v1/batches')) {
      return _json([
        {
          'id': 'b1',
          'product_id': 'x',
          'warehouse_id': 'w',
          'selling_price': 10000,
          'sizes_quantity': {'40': 9},
          'date_arrived': '2026-01-01T00:00:00Z',
        }
      ]);
    }
    return _json(const []);
  }
}

CartItemModel _line(String admin, String store, {bool selected = true}) =>
    CartItemModel(
      productId: 'p1-$admin',
      productName: 'Товар $store',
      batchId: 'b1',
      size: '40',
      qty: 1,
      price: 10000,
      adminUid: admin,
      storeName: store,
      imageUrl: '',
      warehouseId: 'w-$admin',
      selected: selected,
    );

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 14; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _openCart(WidgetTester t, List<CartItemModel> lines,
    {double width = 600}) async {
  SharedPreferences.setMockInitialValues({
    'cart_items_v1': jsonEncode(lines.map((e) => e.toJson()).toList()),
  });
  t.view.physicalSize = Size(width, 3600);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<AppUser>.value(value: AppUser.current),
      ChangeNotifierProvider<CartProvider>(create: (_) => CartProvider()),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const ClientCartScreen(),
    ),
  ));
  await _settle(t);
}

CartProvider _cart(WidgetTester t) =>
    t.element(find.byType(ClientCartScreen)).read<CartProvider>();

void _setUser(String city) => AppUser().set(
      uid: 'client-1',
      ownerUid: 'client-1',
      name: 'Клиент',
      email: '',
      role: 'client',
      city: city,
    );

final _note = find.byKey(const ValueKey('pickup-blocked-note'));
const _resetText =
    'Выбранный способ не подходит для этого заказа — выберите доставку';

/// Экрандағы барлық мәтінде «10%» бар ма.
bool _anyTenPercent(WidgetTester t) => t
    .widgetList<Text>(find.byType(Text))
    .any((w) => (w.data ?? w.textSpan?.toPlainText() ?? '').contains('10%'));

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://localhost:54321',
      publishableKey: 'test-anon-key',
      httpClient: _Backend(),
      authOptions: const FlutterAuthClientOptions(
        detectSessionInUri: false,
        localStorage: EmptyLocalStorage(),
      ),
    );
  });

  setUp(() async {
    LocaleContext.currentLang = 'ru';
    await FeatureFlags.instance.refresh();
  });

  testWidgets('өз қаласының дүкені: Бронь мен Самовывоз бар, түсіндірме жоқ',
      (t) async {
    _setUser('Алматы');
    await _openCart(t, [_line('alma', 'Алма')]);
    expect(find.text('Бронь'), findsOneWidget);
    expect(find.text('Самовывоз'), findsOneWidget);
    expect(find.text('Доставка'), findsOneWidget);
    expect(_note, findsNothing);
  });

  testWidgets('басқа қаладағы дүкен: тек Доставка, бір жол түсіндірме, 10% жоқ',
      (t) async {
    _setUser('Астана');
    await _openCart(t, [_line('alma', 'Алма')]);
    expect(find.text('Бронь'), findsNothing);
    expect(find.text('Самовывоз'), findsNothing);
    expect(find.text('Доставка'), findsOneWidget);
    expect(_note, findsOneWidget);
    expect(
        find.text(
            'Магазин «Алма» в другом городе (Алматы) — доступна только доставка с полной оплатой'),
        findsOneWidget);
    // Доставка мәтіні толық төлемді ашық айтады.
    expect(find.textContaining('100%'), findsWidgets);
    expect(_anyTenPercent(t), isFalse);
    // Сыйлық қалады (алушы тәсілді өзі таңдайды).
    expect(find.text('Подарок'), findsOneWidget);

    await t.tap(find.text('Доставка'));
    await t.pump();
    expect(find.text('Оплатить'), findsOneWidget);
    expect(find.text('Забронировать'), findsNothing);
    expect(_anyTenPercent(t), isFalse);
  });

  testWidgets('профильде қала жоқ: бұрынғыдай бәрі ашық', (t) async {
    _setUser('');
    await _openCart(t, [_line('nur', 'Нур')]);
    expect(find.text('Бронь'), findsOneWidget);
    expect(find.text('Самовывоз'), findsOneWidget);
    expect(_note, findsNothing);
  });

  testWidgets(
      'аралас себет: бөтен дүкеннің тауары таңдалса — тек жеткізу; '
      'алынса — тәсілдер қайтады', (t) async {
    _setUser('Алматы');
    await _openCart(t, [_line('alma', 'Алма'), _line('nur', 'Нур')]);
    expect(find.text('Бронь'), findsNothing);
    expect(
        find.text(
            'Магазин «Нур» в другом городе (Астана) — доступна только доставка с полной оплатой'),
        findsOneWidget);

    // «Нур» жолын тапсырыстан шығарамыз → тек Алматы дүкені қалды.
    _cart(t).toggleSelected(1);
    await _settle(t);
    expect(find.text('Бронь'), findsOneWidget);
    expect(find.text('Самовывоз'), findsOneWidget);
    expect(_note, findsNothing);
  });

  testWidgets(
      'Бронь таңдалып тұрғанда бөтен дүкен тауары қосылса — тәсіл алынады, '
      'белгі шығады, 10% депозит уәдесі қалмайды', (t) async {
    _setUser('Алматы');
    await _openCart(
        t, [_line('alma', 'Алма'), _line('nur', 'Нур', selected: false)]);
    await t.tap(find.text('Бронь'));
    await t.pump();
    expect(find.text('Забронировать'), findsOneWidget);
    expect(find.text('Магазину сейчас (депозит 10%)'), findsOneWidget);

    _cart(t).toggleSelected(1); // «Нур» таңдалды
    await _settle(t);

    expect(find.text('Бронь'), findsNothing);
    expect(find.text(_resetText), findsOneWidget);
    expect(find.text('Забронировать'), findsNothing);
    // Батырма тәсіл таңдауды сұрайды (басылмайды).
    expect(find.text('Выберите способ получения'), findsOneWidget);
    expect(_anyTenPercent(t), isFalse);

    // Доставканы таңдағанда белгі кетеді.
    await t.tap(find.text('Доставка'));
    await t.pump();
    expect(find.text(_resetText), findsNothing);
    expect(find.text('Оплатить'), findsOneWidget);
  });

  testWidgets('профильде қала ауысса — Самовывоз бірден алынады', (t) async {
    _setUser('Алматы');
    await _openCart(t, [_line('alma', 'Алма')]);
    await t.tap(find.text('Самовывоз'));
    await t.pump();
    expect(find.text('Оплатить'), findsOneWidget);

    // Профиль экранындағыдай: экранға берілген СОЛ инстанс жаңарады.
    AppUser.current.updateCity('Астана');
    await _settle(t);
    expect(find.text('Самовывоз'), findsNothing);
    expect(find.text(_resetText), findsOneWidget);
    expect(find.text('Оплатить'), findsNothing);
  });

  testWidgets('қазақша: түсіндірме мен белгі аударылған', (t) async {
    LocaleContext.currentLang = 'kk';
    _setUser('Алматы');
    await _openCart(
        t, [_line('alma', 'Алма'), _line('nur', 'Нур', selected: false)]);
    await t.tap(find.text('Бронь'));
    await t.pump();
    _cart(t).toggleSelected(1);
    await _settle(t);
    expect(
        find.text(
            '«Нур» дүкені басқа қалада (Астана) — тек толық төлеммен жеткізу қолжетімді'),
        findsOneWidget);
    expect(
        find.text('Таңдалған тәсіл бұл тапсырысқа келмейді — жеткізуді таңдаңыз'),
        findsOneWidget);
  });

  testWidgets('320 px: түсіндірме мен тәсілдер толып кетпейді', (t) async {
    _setUser('Алматы');
    await _openCart(
        t,
        [
          _line('alma', 'Алма'),
          _line('nur', 'Очень длинное название магазина в Астане'),
        ],
        width: 320);
    expect(_note, findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
