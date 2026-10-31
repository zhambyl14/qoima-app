import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: implementation_imports
import 'package:google_fonts/src/google_fonts_base.dart' as fonts;
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:provider/provider.dart';
import 'package:qoima/core/app_user.dart';
import 'package:qoima/core/feature_flags.dart';
import 'package:qoima/core/lang.dart';
import 'package:qoima/core/warehouse_context.dart';
import 'package:qoima/data/models/category_data.dart';
import 'package:qoima/ui/admin/products/add_product_helpers.dart';
import 'package:qoima/ui/admin/products/add_product_screen.dart';
import 'package:qoima/ui/admin/products/ai/ai_fill_card.dart';
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

/// Желісіз бэкенд: AI жауабын да, тауар жазуын да тест ұстап тұра алады.
class _Backend extends http.BaseClient {
  Map<String, dynamic> suggestion = {};
  Completer<void>? aiGate;
  Completer<void>? insertGate;
  int aiCalls = 0;
  int productInserts = 0;

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
      return _json({FeatureFlags.aiProductAssist: true});
    }
    if (path.contains('/functions/v1/')) {
      aiCalls++;
      await aiGate?.future;
      return _json(suggestion);
    }
    if (path.endsWith('/rest/v1/products') && request.method == 'POST') {
      productInserts++;
      await insertGate?.future;
      return _json({'message': 'stop here'}, 500);
    }
    return _json(const []);
  }
}

final _backend = _Backend();

Future<void> _settle(WidgetTester t,
    {bool Function()? until, int maxRounds = 150}) async {
  for (var i = 0; i < maxRounds; i++) {
    await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)));
    await t.pump(const Duration(milliseconds: 20));
    if (until != null && until()) return;
  }
  if (until != null) fail('шарт орындалмады');
}

void main() {
  late String shoesType;
  late String photoPath;
  const picker = MethodChannel('plugins.flutter.io/image_picker');
  Completer<void>? pickGate;
  var pickNothing = false;

  setUpAll(() async {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    fonts.assetManifest = const _FontManifest();
    binding.defaultBinaryMessenger.setMockMessageHandler(
      'flutter/assets',
      (_) async => ByteData(4),
    );
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://localhost:54321',
      publishableKey: 'test',
      httpClient: _backend,
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        detectSessionInUri: false,
        localStorage: EmptyLocalStorage(),
      ),
    );
    await FeatureFlags.instance.refresh();
    shoesType = kTypesByCategory['shoes']!.first;
    final dir = await Directory.systemTemp.createTemp('qoima_race');
    final file = File('${dir.path}/photo.jpg');
    await file.writeAsBytes(
        img.encodeJpg(img.Image(width: 320, height: 180), quality: 80));
    photoPath = file.path;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(picker,
        (call) async {
      await pickGate?.future;
      return pickNothing ? const <String>[] : <String>[photoPath];
    });
  });

  setUp(() {
    _backend
      ..suggestion = {
        'category_key': 'tshirt',
        'type': '',
        'category': '',
        'confidence': 'high',
      }
      ..aiGate = null
      ..insertGate = null
      ..aiCalls = 0
      ..productInserts = 0;
    pickGate = null;
    pickNothing = false;
    AppUser().set(
      uid: 'owner-1',
      ownerUid: 'owner-1',
      name: 'Иесі',
      email: '',
      role: 'seller', // әкімшіге қойма таңдау парағы шығар еді
    );
  });

  Future<void> open(WidgetTester t) async {
    t.view.physicalSize = const Size(2700, 9000);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    SharedPreferences.setMockInitialValues({
      AddProductMemory.prefKey: const AddProductMemory()
          .remember(category: 'shoes', audience: 'Мужские', type: shoesType)
          .encode(),
    });
    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AppUser>.value(value: AppUser.current),
        ChangeNotifierProvider<WarehouseContext>(
            create: (_) => WarehouseContext()),
      ],
      child: MaterialApp(
        // Тест қарпі (әр әріп — шаршы) кең: AI карточкасының тұрақты өлшемді
        // ұяшығына сыйсын. Бұл жерде орналасу тексерілмейді.
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(0.5)),
          child: child!,
        ),
        home: AddProductScreen(key: UniqueKey()),
      ),
    ));
    await _settle(t, maxRounds: 15);
  }

  Future<void> addAiPhoto(WidgetTester t) async {
    await t.tap(find.text(tr('Добавить фото', 'Фото қосу')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    await t.tap(find.text(tr('Из галереи', 'Галереядан')));
    await _settle(t,
        until: () => t.widget<AiFillCard>(find.byType(AiFillCard)).photos.isNotEmpty);
    await t.pump(const Duration(milliseconds: 400));
  }

  Future<void> tapAiFill(WidgetTester t) async {
    await t.tap(find.text(tr('Заполнить по фото', 'Суреттен толтыру')));
    await t.pump();
  }

  Future<void> fillStepZero(WidgetTester t) async {
    await t.enterText(
      find.widgetWithText(
          TextFormField, tr('Название товара *', 'Тауар атауы *')),
      'Air Max',
    );
    await t.enterText(
      find.widgetWithText(TextFormField, tr('Бренд *', 'Бренд *')),
      'Nike',
    );
    await t.pump();
    await t.tap(find.text(trValue('Белый')).first);
    await t.pump(const Duration(milliseconds: 250));
  }

  Future<void> settleStep(WidgetTester t) async {
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    await t.pump();
  }

  Future<void> next(WidgetTester t) async {
    await t.tap(find.widgetWithText(ElevatedButton, 'Далее →'));
    await settleStep(t);
  }

  Future<void> toPhotoStep(WidgetTester t) async {
    await fillStepZero(t);
    await next(t);
    await t.enterText(find.byType(TextField).at(0), '5000');
    await t.enterText(find.byType(TextField).at(1), '9000');
    await t.pump();
    await t.tap(find.text('39'));
    await t.pump(const Duration(milliseconds: 200));
    await next(t);
    expect(find.text(tr('Галерея', 'Галерея')), findsOneWidget);
  }

  Finder saveButton() => find.widgetWithText(
      ElevatedButton, tr('Сохранить товар', 'Тауарды сақтау'));

  group('AI жады мәнін қашан ауыстыра алады', () {
    testWidgets('иесі ештеңе таңдамаса, жадыдағы категория ауысады (бақылау)',
        (t) async {
      await open(t);
      await addAiPhoto(t);
      await tapAiFill(t);
      await _settle(t, until: () => _backend.aiCalls > 0);
      await _settle(t, maxRounds: 30);
      expect(find.text(trValue(shoesType)), findsNothing);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('иесі кімге-ні таңдаса, категория мен түрі өшпейді',
        (t) async {
      await open(t);
      await addAiPhoto(t);
      await t.tap(find.textContaining(trValue('Женские')));
      await t.pump(const Duration(milliseconds: 200));

      await tapAiFill(t);
      await _settle(t, until: () => _backend.aiCalls > 0);
      await _settle(t, maxRounds: 30);
      expect(find.text(trValue(shoesType)), findsWidgets);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('1-қадамнан өткен соң келген AI жауабы форманы бұзбайды',
        (t) async {
      await open(t);
      await addAiPhoto(t);

      _backend.aiGate = Completer<void>();
      await tapAiFill(t);
      await _settle(t, until: () => _backend.aiCalls > 0);

      await fillStepZero(t);
      await next(t);
      expect(find.text('39'), findsOneWidget);

      _backend.aiGate!.complete();
      await _settle(t, maxRounds: 30);
      await t.pump(const Duration(milliseconds: 400));
      // Өлшем торы аяқ киімдікі болып қалды.
      expect(find.text('39'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });
  });

  group('Сақтау мен фото', () {
    testWidgets('фото кесіліп жатқанда сақтау басталмайды, бірақ кейін өтеді',
        (t) async {
      await open(t);
      await toPhotoStep(t);

      pickGate = Completer<void>();
      pickNothing = true; // сақтауды Cloudinary-ге жеткізбеу үшін
      await t.tap(find.text(tr('Галерея', 'Галерея')));
      await t.pump();

      await t.tap(saveButton());
      await _settle(t, maxRounds: 10);
      expect(_backend.productInserts, 0);
      expect(
          find.text(tr('Фото ещё обрабатываются, подождите пару секунд',
              'Фото әлі өңделіп жатыр, бірер секунд күтіңіз')),
          findsOneWidget);
      expect(saveButton(), findsOneWidget);

      pickGate!.complete();
      await _settle(t,
          until: () =>
              find.byType(LinearProgressIndicator).evaluate().isEmpty);
      ScaffoldMessenger.of(t.element(find.byType(Scaffold).first))
          .clearSnackBars();
      await t.pump();
      await t.pump(const Duration(seconds: 1));
      await t.pump();

      await t.tap(saveButton());
      await _settle(t, until: () => _backend.productInserts == 1);
      await _settle(t, maxRounds: 10);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('сақталып жатқанда форма басылмайды', (t) async {
      await open(t);
      await toPhotoStep(t);
      Finder absorber() => find
          .ancestor(
              of: find.text(tr('Галерея', 'Галерея')),
              matching: find.byType(AbsorbPointer))
          .first;
      expect(t.widget<AbsorbPointer>(absorber()).absorbing, isFalse);

      _backend.insertGate = Completer<void>();
      await t.tap(saveButton());
      await _settle(t, until: () => _backend.productInserts == 1);

      expect(t.widget<AbsorbPointer>(absorber()).absorbing, isTrue);
      expect(
          t
              .widget<OutlinedButton>(find.byType(OutlinedButton).last)
              .onPressed,
          isNull);

      _backend.insertGate!.complete();
      await _settle(t, maxRounds: 10);
      // Сақтау қате берді: форма қайта ашылады.
      expect(t.widget<AbsorbPointer>(absorber()).absorbing, isFalse);
      await t.pumpWidget(const SizedBox());
    });
  });
}
