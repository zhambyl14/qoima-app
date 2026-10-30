import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:qoima/core/app_user.dart';
import 'package:qoima/core/feature_flags.dart';
import 'package:qoima/core/locale_context.dart';
import 'package:qoima/data/models/order_model.dart';
import 'package:qoima/data/models/product_model.dart';
import 'package:qoima/data/models/return_model.dart';
import 'package:qoima/data/models/store_model.dart';
import 'package:qoima/l10n/app_localizations.dart';
import 'package:qoima/ui/client/gift/gift_create_sheet.dart';
import 'package:qoima/ui/seller/returns/seller_return_receive_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Желісіз бэкенд: сыйлық парағына керегі ғана (жалауша, партия, тілек RPC).
class _Backend extends http.BaseClient {
  final registryCalls = <Map<String, dynamic>>[];
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
      return _json(
          {FeatureFlags.giftLinks: true, FeatureFlags.nonReturnable: true});
    }
    if (path.endsWith('/rpc/delivery_tariff')) return _json(const {});
    if (path.endsWith('/rpc/create_registry_gift_order')) {
      registryCalls.add(Map<String, dynamic>.from(
          jsonDecode((request as http.Request).body) as Map));
      // Жауап форматы бұл тестке керек емес: сұраныс жеткені жеткілікті.
      return _json({'message': 'stop_here'}, 400);
    }
    if (path.endsWith('/rest/v1/batches')) {
      return _json([
        {
          'id': 'b1',
          'product_id': 'p1',
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

StoreModel _store(String mode) => StoreModel.fromMap({
      'admin_uid': 'owner-1',
      'city': 'Алматы',
      'return_policy_mode': mode,
      'allow_non_returnable': mode == 'none',
    });

final _product = ProductModel.fromMap(const {'id': 'p1', 'title': 'Кроссовки'});

/// Парақты батырмамен ашады: showGiftSheet Navigator мен AppUser провайдерін қажет етеді.
Widget _sheetHost(StoreModel store, {String? claim, String? fixedSize}) =>
    ChangeNotifierProvider<AppUser>.value(
      value: AppUser.current,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showGiftSheet(context,
                  product: _product,
                  store: store,
                  registryClaimId: claim,
                  fixedSize: fixedSize,
                  recipientName: claim == null ? null : 'Айгүл'),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 12; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _open(WidgetTester t, Widget host) async {
  t.view.physicalSize = const Size(600, 3200);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(host);
  await t.tap(find.text('open'));
  await _settle(t);
}

OrderModel _giftOrder({required bool nonReturnable}) => OrderModel.fromMap({
      'id': 'o1',
      'is_gift': true,
      'status': OrderModel.statusCompleted,
      'items': [
        {
          'productId': 'p1',
          'size': '40',
          'quantity': 1,
          if (nonReturnable) 'nonReturnable': true,
        }
      ],
    });

ReturnModel _postReturn({String tracking = ''}) => ReturnModel.fromMap({
      'pickup': 'post',
      'post_tracking': tracking,
      'status': 'approved',
      'items': const [],
    }, 'r1');

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
    await FeatureFlags.instance.refresh();
  });

  setUp(() {
    LocaleContext.currentLang = 'ru';
    _backend.registryCalls.clear();
    AppUser().set(
      uid: 'client-1',
      ownerUid: 'client-1',
      name: 'Клиент',
      email: '',
      role: 'client',
    );
  });

  // 0082: дүкен режимі сыйлыққа таралмайды — сыйлықта өз ережесі бар (0070).
  group('сыйлық: дүкен режимі none әсер етпейді', () {
    const notice = 'Этот товар нельзя обменять — подарите, зная размер.';

    testWidgets('none дүкенінде ескерту жоқ', (t) async {
      await _open(t, _sheetHost(_store('none')));
      expect(find.text('Оплатить подарок'), findsOneWidget);
      expect(find.text(notice), findsNothing);
    });

    testWidgets('accept дүкенінде де ескерту жоқ', (t) async {
      await _open(t, _sheetHost(_store('accept')));
      expect(find.text('Оплатить подарок'), findsOneWidget);
      expect(find.text(notice), findsNothing);
    });

    testWidgets('тілек тізімі, өлшем бос: RPC-ге жетеді', (t) async {
      await _open(t, _sheetHost(_store('none'), claim: 'c1', fixedSize: ''));

      expect(find.text('Этот товар нельзя обменять.'), findsNothing);
      await t.tap(find.text('Оплатить подарок'));
      await _settle(t);

      expect(find.text('Выберите размер'), findsNothing);
      expect(_backend.registryCalls.single['p_claim'], 'c1');
    });
  });

  group('OrderModel.isGiftLocked', () {
    test('снапшот белгісі оқылады', () {
      expect(_giftOrder(nonReturnable: true).isGiftLocked, isTrue);
      expect(_giftOrder(nonReturnable: false).isGiftLocked, isFalse);
    });
  });

  group('почтамен қайтару: қабылдау экраны', () {
    Widget host(ReturnModel r) => MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MediaQuery(
            data: const MediaQueryData(size: Size(320, 800)),
            child: SellerReturnReceiveScreen(ret: r),
          ),
        );

    testWidgets('трек көрінеді және көшіріледі', (t) async {
      final copied = <String>[];
      t.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      });
      addTearDown(() => t.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));

      await t.pumpWidget(host(_postReturn(tracking: 'RR123456789KZ')));
      await t.pump();

      expect(find.text('Клиент отправит Казпочтой'), findsOneWidget);
      await t.tap(find.text('RR123456789KZ'));
      await t.pump();
      expect(copied, ['RR123456789KZ']);
      expect(find.text('Скопировано'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('трек жоқ болса ашық айтылады', (t) async {
      await t.pumpWidget(host(_postReturn()));
      await t.pump();
      expect(find.text('Трек-номер не указан'), findsOneWidget);
    });
  });
}
