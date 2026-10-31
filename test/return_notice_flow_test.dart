import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:qoima/core/app_user.dart';
import 'package:qoima/core/feature_flags.dart';
import 'package:qoima/core/locale_context.dart';
import 'package:qoima/data/models/order_model.dart';
import 'package:qoima/l10n/app_localizations.dart';
import 'package:qoima/ui/admin/my_store/return_policy_settings_screen.dart';
import 'package:qoima/ui/client/return_notice_gate.dart';
import 'package:qoima/ui/client/returns/client_return_form_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Желісіз PostgREST: хабарлама ағынына қажет сұраныстарды ғана білетін жалған
/// бэкенд. Realtime тексерілмейді (тестте сокет жоқ) — тек сұрақ/кезек логикасы.
class _Backend extends http.BaseClient {
  Map<String, bool> flags = {};
  List<Map<String, dynamic>> orders = [];
  Map<String, dynamic> store = {};
  bool failAck = false;

  final acks = <String>[];
  int orderReads = 0;
  final policySaves = <Map<String, dynamic>>[];
  final returnInserts = <Map<String, dynamic>>[];

  void reset() {
    flags = {};
    orders = [];
    store = {};
    failAck = false;
    acks.clear();
    orderReads = 0;
    policySaves.clear();
    returnInserts.clear();
  }

  // Postgrest жауаптан response.request-ті оқиды, сондықтан ол міндетті.
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
    final body = request is http.Request ? request.body : '';
    if (path.endsWith('/rpc/feature_flags')) return _json(flags);
    if (path.endsWith('/rpc/delivery_tariff')) return _json(const {});
    if (path.endsWith('/rpc/next_counter')) return _json(1);
    if (path.endsWith('/rpc/ack_return_notice')) {
      if (failAck) return _json({'message': 'boom'}, 500);
      final id = (jsonDecode(body) as Map)['p_order'] as String;
      acks.add(id);
      orders.removeWhere((o) => o['id'] == id);
      return _json(null);
    }
    if (path.endsWith('/rpc/set_store_return_policy')) {
      policySaves.add(Map<String, dynamic>.from(jsonDecode(body) as Map));
      return _json(null);
    }
    if (path.endsWith('/rest/v1/orders')) {
      orderReads++;
      return _json(orders);
    }
    if (path.endsWith('/rest/v1/stores')) return _json([store]);
    if (path.endsWith('/rest/v1/returns')) {
      if (request.method != 'POST') return _json(const []);
      returnInserts.add(Map<String, dynamic>.from(jsonDecode(body) as Map));
      return _json(null, 201);
    }
    return _json(const []);
  }
}

final _backend = _Backend();

Map<String, dynamic> _order(String id, {int number = 1}) => {
      'id': id,
      'store_name': 'Дүкен',
      'order_number': number,
      'items': const [],
      'order_type': OrderModel.typeClickCollect,
      'delivery_mode': 'courier',
      'status': OrderModel.statusCompleted,
      'return_policy': {'mode': 'accept', 'days': 14, 'conditions': const []},
    };

void _lifecycleResume(WidgetTester t) {
  t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
}

Widget _app(Widget home) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    );

Future<void> _settle(WidgetTester t) async {
  // Жалған HTTP жауаптары микротапсырмалармен келеді, бірнеше кадр жеткілікті.
  for (var i = 0; i < 12; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _endRealtime(WidgetTester t) async {
  await t.pumpWidget(const SizedBox.shrink());
  // await жасамаймыз: FakeAsync ішінде сокет жабылуы ешқашан аяқталмайды.
  Supabase.instance.client.realtime.disconnect();
  // Имитацияланған resume кезінде SupabaseAuth қосқан таймер.
  Supabase.instance.client.auth.stopAutoRefresh();
  await t.pump(const Duration(seconds: 5));
}

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

  setUp(() {
    LocaleContext.currentLang = 'ru';
    _backend.reset();
    AppUser().set(
      uid: 'client-1',
      ownerUid: 'owner-1',
      name: 'Клиент',
      email: '',
      role: 'client',
    );
  });

  group('ReturnNoticeGate', () {
    // Бұл тест бірінші тұруы керек: жалауша әлі жүктелмеген.
    testWidgets('жүктелмеген жалауша біржола «өшік» деп саналмайды', (t) async {
      expect(FeatureFlags.instance.isLoaded, isFalse);
      _backend.flags = {FeatureFlags.returnNotice: true};
      _backend.orders = [_order('a')];

      await t.pumpWidget(_app(const ReturnNoticeGate(child: SizedBox())));
      await _settle(t);

      expect(find.text('Понятно'), findsOneWidget);
      await t.tap(find.text('Понятно'));
      await _settle(t);
      await _endRealtime(t);
    });

    testWidgets('әр тапсырыс бір рет, бір-бірден, resume қайталамайды',
        (t) async {
      _backend.flags = {FeatureFlags.returnNotice: true};
      await t.runAsync(FeatureFlags.instance.refresh);
      _backend.orders = [_order('a', number: 1), _order('b', number: 2)];

      await t.pumpWidget(_app(const ReturnNoticeGate(child: SizedBox())));
      await _settle(t);

      // Екі тапсырыс бар, бірақ парақ біреу ғана.
      expect(find.text('Понятно'), findsOneWidget);
      expect(find.text('Дүкен · Заказ №00001'), findsOneWidget);

      // Парақ ашық тұрғанда resume екінші парақ ашпайды.
      _lifecycleResume(t);
      await _settle(t);
      expect(find.text('Понятно'), findsOneWidget);
      expect(find.text('Дүкен · Заказ №00001'), findsOneWidget);

      await t.tap(find.text('Понятно'));
      await _settle(t);
      expect(_backend.acks, ['a']);
      expect(find.text('Дүкен · Заказ №00002'), findsOneWidget);

      await t.tap(find.text('Понятно'));
      await _settle(t);
      expect(_backend.acks, ['a', 'b']);
      expect(find.text('Понятно'), findsNothing);

      // Енді шығатын ештеңе жоқ.
      _lifecycleResume(t);
      await _settle(t);
      expect(find.text('Понятно'), findsNothing);
      await _endRealtime(t);
    });

    testWidgets('үстінде басқа бет ашық: парақ күтеді, бет жабылғанда шығады',
        (t) async {
      _backend.flags = {FeatureFlags.returnNotice: true};
      await t.runAsync(FeatureFlags.instance.refresh);
      _backend.orders = [];

      await t.pumpWidget(_app(const ReturnNoticeGate(child: SizedBox())));
      await _settle(t);

      final navigator = t.state<NavigatorState>(find.byType(Navigator));
      unawaited(navigator.push(MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Форма')))));
      await _settle(t);
      await t.pump(const Duration(milliseconds: 400));

      // Форма ашық тұрғанда келген тапсырыс оның үстіне шықпайды.
      _backend.orders = [_order('a')];
      _lifecycleResume(t);
      await _settle(t);
      expect(find.text('Форма'), findsOneWidget);
      expect(find.text('Понятно'), findsNothing);
      expect(_backend.acks, isEmpty);

      navigator.pop();
      await _settle(t);
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('Форма'), findsNothing);
      expect(find.text('Понятно'), findsOneWidget);

      await t.tap(find.text('Понятно'));
      await _settle(t);
      expect(_backend.acks, ['a']);
      await _endRealtime(t);
    });

    testWidgets('жалауша өшік — сұраныс та, парақ та жоқ', (t) async {
      _backend.flags = {FeatureFlags.returnNotice: false};
      await t.runAsync(FeatureFlags.instance.refresh);
      _backend.orders = [_order('a')];

      await t.pumpWidget(_app(const ReturnNoticeGate(child: SizedBox())));
      await _settle(t);

      expect(_backend.orderReads, 0);
      expect(find.text('Понятно'), findsNothing);
      await _endRealtime(t);
    });

    testWidgets('клиент емес — сұраныс та, парақ та жоқ', (t) async {
      _backend.flags = {FeatureFlags.returnNotice: true};
      await t.runAsync(FeatureFlags.instance.refresh);
      _backend.orders = [_order('a')];
      AppUser.current.clear();

      await t.pumpWidget(_app(const ReturnNoticeGate(child: SizedBox())));
      await _settle(t);

      expect(_backend.orderReads, 0);
      expect(find.text('Понятно'), findsNothing);
      await _endRealtime(t);
    });

    testWidgets('ack қатесі: парақ жабылады, сессияда қайта шықпайды',
        (t) async {
      _backend.flags = {FeatureFlags.returnNotice: true};
      await t.runAsync(FeatureFlags.instance.refresh);
      _backend.orders = [_order('a')];
      _backend.failAck = true;

      await t.pumpWidget(_app(const ReturnNoticeGate(child: SizedBox())));
      await _settle(t);
      await t.tap(find.text('Понятно'));
      await _settle(t);
      expect(find.text('Понятно'), findsNothing);

      _lifecycleResume(t);
      await _settle(t);
      expect(find.text('Понятно'), findsNothing);

      // Жаңа сессия: ack өтпегендіктен қайта шығады.
      await t.pumpWidget(const SizedBox.shrink());
      await t.pumpWidget(_app(const ReturnNoticeGate(child: SizedBox())));
      await _settle(t);
      expect(find.text('Понятно'), findsOneWidget);
      await t.tap(find.text('Понятно'));
      await _settle(t);
      await _endRealtime(t);
    });
  });

  group('ReturnPolicySettingsScreen', () {
    Future<void> open(WidgetTester t) async {
      t.view.physicalSize = const Size(1800, 9000);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      await t.pumpWidget(_app(const ReturnPolicySettingsScreen()));
      await _settle(t);
    }

    Map<String, dynamic> row(Map<String, dynamic> extra) => {
          'admin_uid': 'owner-1',
          'store_name': 'Дүкен',
          'return_policy_mode': 'accept',
          'return_days': 14,
          'return_conditions': <String>[],
          'return_policy_note': '',
          ...extra,
        };

    testWidgets('рұқсатсыз: «Без возврата» өшік, шарттар сақталады', (t) async {
      _backend.flags = {FeatureFlags.returnNotice: true};
      await t.runAsync(FeatureFlags.instance.refresh);
      _backend.store = row({'allow_non_returnable': false});
      await open(t);

      expect(find.textContaining('выдаёт модератор'), findsOneWidget);
      await t.tap(find.text('Без возврата'));
      await _settle(t);
      // Режим ауыспады: мерзім чиптері орнында.
      expect(find.text('21 день'), findsOneWidget);
      expect(find.text('КАК ОТМЕТИТЬ ТОВАР'), findsNothing);

      await t.tap(find.text('21 день'));
      await t.tap(find.text('Сохранены бирки и ярлыки').first);
      await t.pump();
      // Алдын ала көрініс бірден жаңарады.
      expect(find.text('Возврат в течение 21 дня'), findsOneWidget);

      await t.tap(find.text('Сохранить'));
      await _settle(t);
      expect(_backend.policySaves.single, {
        'p_mode': 'accept',
        'p_days': 21,
        'p_conditions': ['tags'],
        'p_note': '',
      });
    });

    testWidgets('рұқсатпен: «Без возврата» таңдалады, мерзім жасырылады',
        (t) async {
      _backend.flags = {
        FeatureFlags.returnNotice: true,
        FeatureFlags.nonReturnable: true,
      };
      await t.runAsync(FeatureFlags.instance.refresh);
      _backend.store = row({'allow_non_returnable': true});
      await open(t);

      expect(find.textContaining('выдаёт модератор'), findsNothing);
      expect(find.text('КАК ОТМЕТИТЬ ТОВАР'), findsOneWidget);
      await t.tap(find.text('Без возврата'));
      await _settle(t);
      expect(find.text('21 день'), findsNothing);
      expect(find.text('Этот магазин не принимает возврат'), findsOneWidget);

      await t.tap(find.text('Сохранить'));
      await _settle(t);
      expect(_backend.policySaves.single['p_mode'], 'none');
    });

    testWidgets('екі жалауша да өшік: өңдеу жабық', (t) async {
      _backend.flags = {
        FeatureFlags.returnNotice: false,
        FeatureFlags.nonReturnable: false,
      };
      await t.runAsync(FeatureFlags.instance.refresh);
      _backend.store = row({});
      await open(t);
      expect(find.textContaining('отключена платформой'), findsOneWidget);
    });
  });

  group('ClientReturnFormScreen', () {
    OrderModel order({required bool kazpost}) => OrderModel.fromMap({
          'id': 'o1',
          'admin_uid': 'owner-1',
          'store_name': 'Дүкен',
          'store_phone': '+77001112233',
          'order_number': 7,
          'status': OrderModel.statusCompleted,
          'order_type': OrderModel.typeDelivery,
          'delivery_mode': kazpost
              ? OrderModel.deliveryByKazpost
              : OrderModel.deliveryByStore,
          'kazpost_fee': kazpost ? 2500 : 0,
          'completed_at': DateTime.now().toIso8601String(),
          'return_policy': {'mode': 'accept', 'days': 21},
          'items': [
            {
              'productId': 'p1',
              'productName': 'Кроссовки',
              'batchId': 'b1',
              'size': '42',
              'qty': 1,
              'price': 20000,
            },
          ],
        });

    Future<void> toDeliveryPage(WidgetTester t) async {
      await t.tap(find.text('Далее'));
      await _settle(t);
      await t.tap(find.text('Далее'));
      await _settle(t);
    }

    testWidgets('Казпочта: почта таңдаулы, курьер жоқ, сома почтасыз',
        (t) async {
      _backend.flags = {FeatureFlags.returnNotice: true};
      _backend.store = {'city': 'Тараз', 'address': 'Абай 1'};
      t.view.physicalSize = const Size(1800, 6000);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      await t.pumpWidget(
          _app(ClientReturnFormScreen(order: order(kazpost: true))));
      await _settle(t);

      // Шарттар снапшоттан.
      expect(find.text('Возврат в течение 21 дня'), findsOneWidget);
      await toDeliveryPage(t);

      expect(find.text('Отправлю Казпочтой'), findsOneWidget);
      expect(find.text('Пересылку оплачиваете вы'), findsOneWidget);
      expect(find.text('Тараз, Абай 1'), findsOneWidget);
      expect(find.textContaining('курьерской службы'), findsNothing);
      expect(find.textContaining('Курьер'), findsNothing);

      await t.enterText(find.byType(TextField), 'rr123456789kz');
      await t.tap(find.text('Далее'));
      await _settle(t);
      expect(find.text('Трек-номер: RR123456789KZ'), findsOneWidget);
      expect(find.text('За ваш счёт'), findsOneWidget);

      await t.tap(find.byType(ElevatedButton));
      await _settle(t);
      final row = _backend.returnInserts.single;
      expect(row['pickup'], 'post');
      expect(row['post_tracking'], 'RR123456789KZ');
      expect(row['pickup_address'], '');
      expect(row['total_amount'], 20000); // kazpost_fee кірмейді
      await _endRealtime(t);
    });

    testWidgets('Казпочта + брак: пересылка клиент есебінен деп жазылмайды',
        (t) async {
      _backend.flags = {FeatureFlags.returnNotice: true};
      _backend.store = {'city': 'Тараз', 'address': 'Абай 1'};
      t.view.physicalSize = const Size(1800, 6000);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      await t.pumpWidget(
          _app(ClientReturnFormScreen(order: order(kazpost: true))));
      await _settle(t);

      await t.tap(find.text('Далее'));
      await _settle(t);
      final l10n =
          AppLocalizations.of(t.element(find.byType(ClientReturnFormScreen)))!;
      await t.tap(find.text(l10n.returnReasonQualityBad));
      await _settle(t);
      await t.tap(find.text('Далее'));
      await _settle(t);

      expect(find.text('Пересылку оплачиваете вы'), findsNothing);
      expect(find.text('При браке пересылку оплачивает магазин'),
          findsOneWidget);

      await t.tap(find.text('Далее'));
      await _settle(t);
      expect(find.text('За ваш счёт'), findsNothing);
      expect(find.text('При браке — за счёт магазина'), findsOneWidget);
      await _endRealtime(t);
    });

    testWidgets('кәдімгі тапсырыста почта ұсынылмайды', (t) async {
      _backend.store = {'city': 'Тараз', 'address': 'Абай 1'};
      t.view.physicalSize = const Size(1800, 6000);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      await t.pumpWidget(
          _app(ClientReturnFormScreen(order: order(kazpost: false))));
      await _settle(t);
      await toDeliveryPage(t);

      expect(find.text('Отправлю Казпочтой'), findsNothing);
      expect(find.text('Куда отправить'), findsNothing);
      expect(find.textContaining('Бесплатно'), findsOneWidget);
    });
  });
}
