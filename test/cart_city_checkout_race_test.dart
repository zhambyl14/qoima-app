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

// ── Растау парағы ашық тұрғанда дүкен қаласы «басқа қала» болып шықса ─────────
//
//  Себет ашылғанда дүкен қаласы белгісіз/ескі (жүктеу кешікті немесе дүкен
//  қаласын ауыстырды) → клиент Броньді таңдап, «Забронировать» басады →
//  растау парағы ашық тұрғанда қала келеді → cart_receiving_rules бойынша
//  Бронь енді жарамсыз. Тапсырыс ЖАЗЫЛМАУЫ керек, клиент «жеткізуді таңдаңыз»
//  белгісін көруі керек — шикі/жалпы қате емес.

class _Backend extends http.BaseClient {
  String almaCity = 'Алматы';
  Duration productsDelay = Duration.zero;
  final writes = <String>[];
  final orderInserts = <Map<String, dynamic>>[];
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
    if (request.method != 'GET' && !path.contains('/rpc/feature_flags') &&
        !path.contains('/rpc/delivery_tariff') &&
        !path.contains('/rpc/kazpost')) {
      writes.add('${request.method} $path');
    }
    if (request.method == 'POST' &&
        path.endsWith('/rest/v1/orders') &&
        request is http.Request) {
      final b = jsonDecode(request.body);
      orderInserts.add(Map<String, dynamic>.from(b is List ? b.first : b));
      // Жазылды деп жауап береміз (select('id').single()).
      return _json({'id': 'o-${orderInserts.length}'}, 201);
    }
    if (path.endsWith('/rpc/next_counter')) return _json(1);
    if (path.endsWith('/rpc/feature_flags')) return _json(const {});
    if (path.endsWith('/rpc/delivery_tariff')) return _json(const {});
    if (path.endsWith('/rest/v1/products')) {
      if (productsDelay > Duration.zero) await Future.delayed(productsDelay);
      final owner = (request.url.queryParameters['owner_uid'] ?? '')
          .replaceFirst('eq.', '');
      return _json([
        {
          'id': 'p1-$owner',
          'title': 'Товар',
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
          'city': almaCity,
          'is_published': true,
          'visible_warehouse_ids': ['w-alma'],
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

String _b64(Object o) =>
    base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');

String _fakeSession() {
  const exp = 4102444800; // 2100-01-01
  final jwt = '${_b64({'alg': 'HS256', 'typ': 'JWT'})}.'
      '${_b64({'sub': 'client-1', 'exp': exp, 'role': 'authenticated'})}.sig';
  return jsonEncode({
    'access_token': jwt,
    'token_type': 'bearer',
    'expires_in': 3600,
    'expires_at': exp,
    'refresh_token': 'r',
    'user': {
      'id': 'client-1',
      'aud': 'authenticated',
      'role': 'authenticated',
      'app_metadata': {},
      'user_metadata': {},
      'created_at': '2026-01-01T00:00:00Z',
    },
  });
}

void main() {
  final backend = _Backend();

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://localhost:54321',
      publishableKey: 'test-anon-key',
      httpClient: backend,
      authOptions: const FlutterAuthClientOptions(
        detectSessionInUri: false,
        localStorage: EmptyLocalStorage(),
        autoRefreshToken: false,
      ),
    );
    await Supabase.instance.client.auth.recoverSession(_fakeSession());
  });

  setUp(() async {
    LocaleContext.currentLang = 'ru';
    await FeatureFlags.instance.refresh();
  });

  Future<void> pumpN(WidgetTester t, int n) async {
    for (var i = 0; i < n; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> openCart(WidgetTester t, String clientCity) async {
    backend
      ..almaCity = 'Алматы'
      ..productsDelay = Duration.zero
      ..writes.clear()
      ..orderInserts.clear();
    AppUser().set(
      uid: 'client-1',
      ownerUid: 'client-1',
      name: 'Клиент',
      email: '',
      role: 'client',
      city: clientCity,
    );
    const line = CartItemModel(
      productId: 'p1-alma',
      productName: 'Товар',
      batchId: 'b1',
      size: '40',
      qty: 1,
      price: 10000,
      adminUid: 'alma',
      storeName: 'Алма',
      imageUrl: '',
      warehouseId: 'w-alma',
    );
    SharedPreferences.setMockInitialValues({
      'cart_items_v1': jsonEncode([line.toJson()]),
    });
    t.view.physicalSize = const Size(600, 3600);
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
        home: const Scaffold(body: ClientCartScreen()),
      ),
    ));
    await pumpN(t, 14);
  }

  testWidgets(
      'растау кезінде дүкен басқа қалада болып шықса: тапсырыс жазылмайды, '
      'жалпы қате емес — «жеткізуді таңдаңыз» белгісі', (t) async {
    expect(Supabase.instance.client.auth.currentUser, isNotNull);
    await openCart(t, 'Алматы');

    await t.tap(find.text('Бронь'));
    await t.pump();
    await t.tap(find.text('Забронировать'));
    await pumpN(t, 10);
    expect(find.text('Продолжить к оплате'), findsOneWidget);

    // Растау парағы ашық тұрғанда: дүкен «Астанада» болып шықты, ал қайта
    // тексерудегі тауар сұраулары баяу (нақты желідегідей бірнеше кадр).
    backend.almaCity = 'Астана';
    backend.productsDelay = const Duration(milliseconds: 300);
    backend.writes.clear();

    await t.tap(find.text('Продолжить к оплате'));
    await pumpN(t, 30);

    expect(backend.writes, isEmpty, reason: 'no order/stock writes');
    expect(
        find.text(
            'Выбранный способ не подходит для этого заказа — выберите доставку'),
        findsOneWidget);
    // Шикі/жалпы қате снэкбары шықпауы керек.
    expect(find.byType(SnackBar), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('өз қаласы, Бронь: жазылатын сома = экрандағы 10% (1 000)',
      (t) async {
    await openCart(t, 'Алматы');
    await t.tap(find.text('Бронь'));
    await t.pump();
    await t.tap(find.text('Забронировать'));
    await pumpN(t, 10);
    await t.tap(find.text('Продолжить к оплате'));
    await pumpN(t, 20);
    expect(backend.orderInserts, hasLength(1));
    final o = backend.orderInserts.single;
    expect(o['order_type'], 'smart_reservation');
    expect((o['deposit_amount'] as num).toDouble(), 1000);
  });

  testWidgets('басқа қала, Доставка: жазылатын сома = 100% (10 000)',
      (t) async {
    await openCart(t, 'Астана');
    expect(find.text('Бронь'), findsNothing);
    await t.tap(find.text('Доставка'));
    await pumpN(t, 4);
    await t.enterText(
        find.byWidgetPredicate((w) =>
            w is TextField &&
            (w.decoration?.hintText ?? '').contains('улица')),
        'Абай 1');
    await pumpN(t, 4);
    await t.tap(find.text('Оплатить'));
    await pumpN(t, 10);
    await t.tap(find.text('Продолжить к оплате'));
    await pumpN(t, 20);
    expect(backend.orderInserts, hasLength(1));
    final o = backend.orderInserts.single;
    expect(o['order_type'], 'delivery');
    expect((o['deposit_amount'] as num).toDouble(), 10000);
    expect(o['client_city'], 'Астана');
  });
}
