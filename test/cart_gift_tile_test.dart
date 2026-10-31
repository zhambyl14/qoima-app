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

/// Желісіз бэкенд: себет + сыйлық парағына керегі ғана.
class _Backend extends http.BaseClient {
  bool giftFlag = true;

  /// null емес болса create_gift_order осы кодпен құлайды.
  String? giftError;
  final giftCalls = <Map<String, dynamic>>[];
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
      return _json({FeatureFlags.giftLinks: giftFlag});
    }
    if (path.endsWith('/rpc/delivery_tariff')) return _json(const {});
    if (path.endsWith('/rpc/registry_claims_still_valid')) {
      return _json(['claim-1']);
    }
    if (path.endsWith('/rpc/create_gift_order')) {
      giftCalls.add(Map<String, dynamic>.from(
          jsonDecode((request as http.Request).body) as Map));
      if (giftError != null) return _json({'message': giftError}, 400);
      return _json({
        'id': 'order-1',
        'is_gift': true,
        'status': 'pending',
        'items': const [],
        'gift_token': '11111111-1111-1111-1111-111111111111',
      });
    }
    if (path.endsWith('/rest/v1/products')) {
      final q = request.url.queryParameters;
      // Витрина тізімі (owner_uid бойынша): сурет болмаса себеттегі жол
      // «недоступен» болады. Жеке тауар (id бойынша) сурет-сіз: парақшада желі
      // суреті жүктелмесін.
      if (q.containsKey('owner_uid')) {
        return _json([
          for (final id in const ['p1', 'p2'])
            {
              'id': id,
              'title': 'Товар $id',
              'owner_uid': 'owner-1',
              'images': ['x.png'],
            }
        ]);
      }
      final id = (q['id'] ?? '').replaceFirst('eq.', '');
      return _json([
        {'id': id, 'title': 'Товар $id', 'owner_uid': 'owner-1'}
      ]);
    }
    if (path.endsWith('/rest/v1/stores')) {
      return _json([
        {
          'admin_uid': 'owner-1',
          'store_name': 'Магазин',
          'city': 'Алматы',
          'is_published': true,
          'visible_warehouse_ids': ['w1'],
        }
      ]);
    }
    if (path.endsWith('/rest/v1/batches')) {
      return _json([
        {
          'id': 'b1',
          'product_id': 'p1',
          'warehouse_id': 'w1',
          'selling_price': 10000,
          'sizes_quantity': {'40': 3},
          'date_arrived': '2026-01-01T00:00:00Z',
        }
      ]);
    }
    return _json(const []);
  }
}

final _backend = _Backend();

CartItemModel _line(String id, {int qty = 1, String claim = ''}) =>
    CartItemModel(
      productId: id,
      productName: 'Товар $id',
      batchId: 'b1',
      size: '40',
      qty: qty,
      price: 10000,
      adminUid: 'owner-1',
      storeName: 'Магазин',
      imageUrl: '',
      warehouseId: 'w1',
      registryClaimId: claim,
    );

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 14; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

/// Себетті берілген жолдармен ашады (CartProvider SharedPreferences-тен оқиды).
Future<void> _openCart(WidgetTester t, List<CartItemModel> lines) async {
  SharedPreferences.setMockInitialValues({
    'cart_items_v1': jsonEncode(lines.map((e) => e.toJson()).toList()),
  });
  t.view.physicalSize = const Size(600, 3200);
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

List<String> _ids(WidgetTester t) =>
    _cart(t).items.map((i) => i.productId).toList();

Finder _sheetOf(String text) =>
    find.ancestor(of: find.text(text), matching: find.byType(BottomSheet));

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://localhost:54321',
      publishableKey: 'test-anon-key',
      httpClient: _backend,
      authOptions: const FlutterAuthClientOptions(
        detectSessionInUri: false,
        localStorage: EmptyLocalStorage(),
      ),
    );
  });

  setUp(() async {
    LocaleContext.currentLang = 'ru';
    _backend
      ..giftFlag = true
      ..giftError = null
      ..giftCalls.clear();
    await FeatureFlags.instance.refresh();
    AppUser().set(
      uid: 'client-1',
      ownerUid: 'client-1',
      name: 'Клиент',
      email: '',
      role: 'client',
    );
  });

  testWidgets('жалауша өшік: «Подарок» плиткасы жоқ', (t) async {
    _backend.giftFlag = false;
    await FeatureFlags.instance.refresh();
    await _openCart(t, [_line('p1')]);

    expect(find.text('Самовывоз'), findsOneWidget);
    expect(find.text('Подарок'), findsNothing);
  });

  testWidgets('жалауша қосулы: плитка бар', (t) async {
    await _openCart(t, [_line('p1')]);
    expect(find.text('Подарок'), findsOneWidget);
    expect(find.text('Получатель получит ссылку и сам выберет доставку'),
        findsOneWidget);
  });

  testWidgets('бір жол: таңдаусыз-ақ бірден сыйлық парақшасы', (t) async {
    await _openCart(t, [_line('p1')]);
    await t.tap(find.text('Подарок'));
    await _settle(t);

    expect(find.text('Какой товар подарить?'), findsNothing);
    expect(find.text('Оплатить подарок'), findsOneWidget);
    // Төменгі панель: жалпы сома емес, бөлек төлем туралы түсіндірме.
    expect(
        find.textContaining('Подарок оплачивается отдельно'), findsOneWidget);
  });

  testWidgets('бас тартса: себет пен алдыңғы тәсіл өзгермейді', (t) async {
    await _openCart(t, [_line('p1')]);
    await t.tap(find.text('Самовывоз'));
    await t.pump();
    expect(find.text('Оплатить'), findsOneWidget);

    await t.tap(find.text('Подарок'));
    await _settle(t);
    expect(find.text('Оплатить подарок'), findsOneWidget);

    // Парақшаны жабамыз (сыйлық жасалмады).
    Navigator.of(t.element(find.text('Оплатить подарок'))).pop();
    await _settle(t);

    expect(_ids(t), ['p1']);
    expect(_backend.giftCalls, isEmpty);
    // «Самовывоз» әлі таңдаулы: төлеу батырмасы бұрынғыдай.
    expect(find.text('Оплатить'), findsOneWidget);
    expect(find.textContaining('Подарок оплачивается отдельно'), findsNothing);
  });

  testWidgets('2+ жол: алдымен таңдау парағы, қалғандары қалады', (t) async {
    await _openCart(t, [_line('p1'), _line('p2')]);
    await t.tap(find.text('Подарок'));
    await _settle(t);

    expect(find.text('Какой товар подарить?'), findsOneWidget);
    expect(find.text('Оплатить подарок'), findsNothing);
    expect(
        find.text(
            'Подарок оформляется на один товар. Остальные останутся в корзине.'),
        findsOneWidget);

    final chooser = _sheetOf('Какой товар подарить?');
    await t.tap(find.descendant(of: chooser, matching: find.text('Товар p2')));
    await _settle(t);
    expect(find.text('Оплатить подарок'), findsOneWidget);
  });

  testWidgets('сәтті сыйлық: тек сол жол себеттен өшеді', (t) async {
    await _openCart(t, [_line('p1'), _line('p2')]);
    await t.tap(find.text('Подарок'));
    await _settle(t);
    await t.tap(find.descendant(
        of: _sheetOf('Какой товар подарить?'),
        matching: find.text('Товар p2')));
    await _settle(t);

    final sheet = _sheetOf('Оплатить подарок');
    await t.enterText(
        find.descendant(of: sheet, matching: find.byType(TextField)).first,
        'Айгүл');
    await t.tap(find.text('Оплатить подарок'));
    await _settle(t);

    expect(_backend.giftCalls, hasLength(1));
    expect(_backend.giftCalls.single['p_product'], 'p2');
    // Өлшем себеттегі жолдан алдын ала таңдалған.
    expect(_backend.giftCalls.single['p_size'], '40');
    expect(_ids(t), ['p1']);
  });

  testWidgets('сыйлық жолында 2 дана болса: бір данасы ғана кетеді', (t) async {
    await _openCart(t, [_line('p1', qty: 2)]);
    await t.tap(find.text('Подарок'));
    await _settle(t);
    await t.enterText(
        find
            .descendant(
                of: _sheetOf('Оплатить подарок'),
                matching: find.byType(TextField))
            .first,
        'Айгүл');
    await t.tap(find.text('Оплатить подарок'));
    await _settle(t);

    expect(_backend.giftCalls, hasLength(1));
    expect(_cart(t).items.single.qty, 1);
  });

  testWidgets('RPC қатесі: себет бүтін, қате көрсетіледі', (t) async {
    _backend.giftError = 'gift_out_of_stock';
    await _openCart(t, [_line('p1'), _line('p2')]);
    await t.tap(find.text('Подарок'));
    await _settle(t);
    await t.tap(find.descendant(
        of: _sheetOf('Какой товар подарить?'),
        matching: find.text('Товар p1')));
    await _settle(t);
    await t.enterText(
        find
            .descendant(
                of: _sheetOf('Оплатить подарок'),
                matching: find.byType(TextField))
            .first,
        'Айгүл');
    await t.tap(find.text('Оплатить подарок'));
    await _settle(t);

    expect(_backend.giftCalls, hasLength(1));
    expect(find.text('Этого товара сейчас нет в наличии'), findsWidgets);
    expect(_ids(t), ['p1', 'p2']);
  });

  testWidgets('тілек тізімінің жолы: себеттен сыйлауға болмайды', (t) async {
    await _openCart(t, [_line('p1', claim: 'claim-1')]);
    await t.tap(find.text('Подарок'));
    await _settle(t);

    expect(find.text('Подарок из списка желаний нельзя оформить из корзины'),
        findsOneWidget);
    expect(find.text('Оплатить подарок'), findsNothing);
    expect(_ids(t), ['p1']);
  });

  testWidgets('таңдалған жол жоқ: түсіндірме, ештеңе ашылмайды', (t) async {
    await _openCart(t, [_line('p1')]);
    _cart(t).setAllSelected(false);
    await t.pump();
    await t.tap(find.text('Подарок'));
    await _settle(t);

    expect(
        find.text('Выберите товар, который хотите подарить'), findsOneWidget);
    expect(find.text('Оплатить подарок'), findsNothing);
  });
}
