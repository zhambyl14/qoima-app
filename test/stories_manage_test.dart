import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image/image.dart' as img;
import 'package:qoima/core/feature_flags.dart';
import 'package:qoima/core/locale_context.dart';
import 'package:qoima/data/services/cloudinary_service.dart';
import 'package:qoima/data/services/stories_service.dart';
import 'package:qoima/l10n/app_localizations.dart';
import 'package:qoima/ui/admin/my_store/admin_my_store_hub_screen.dart';
import 'package:qoima/ui/admin/my_store/stories_manage_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/fake_backend.dart';

final _backend = FakeBackend();
late SupabaseClient _client;

class _FakeCloud extends CloudinaryService {
  final uploaded = <int>[];
  final deleted = <String>[];

  @override
  Future<String> uploadStory(Uint8List bytes) async {
    uploaded.add(bytes.length);
    return 'https://res.cloudinary.com/divynstru/image/upload/v1/qoima_stories/s.jpg';
  }

  @override
  Future<void> deleteByUrl(String url) async => deleted.add(url);
}

late _FakeCloud _cloud;

StoriesService _svc() => StoriesService(client: _client, cloudinary: _cloud);

Map<String, dynamic> _row(String id,
        {Duration left = const Duration(hours: 5, minutes: 30)}) =>
    {
      'id': id,
      'store_uid': 'owner-1',
      'image_url': 'https://x.invalid/$id.jpg',
      'caption': '',
      'created_by': 'owner-1',
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'expires_at': DateTime.now().add(left).toUtc().toIso8601String(),
    };

Uint8List _photo() =>
    Uint8List.fromList(img.encodeJpg(img.Image(width: 90, height: 160)));

Future<void> _flags(Map<String, bool> f) async {
  _backend.replies['feature_flags'] = f;
  await FeatureFlags.instance.refresh();
}

Future<void> _open(WidgetTester t,
    {StoryPhotoPicker? picker, int count = 3}) async {
  t.view.physicalSize = const Size(600, 1600);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  _backend.replies['stories_for_store'] = [
    for (var i = 1; i <= count; i++) _row('st$i')
  ];
  await t.pumpWidget(MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: StoriesManageScreen(
        service: _svc(), picker: picker, storeUid: 'owner-1'),
  ));
  await _settle(t);
}

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 10; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    await initFakeSupabase(_backend);
    _client = Supabase.instance.client;
  });

  setUp(() async {
    LocaleContext.currentLang = 'ru';
    _cloud = _FakeCloud();
    _backend.calls.clear();
    _backend.bodies.clear();
    _backend.errors.clear();
    _backend.gates.clear();
    _backend.replies.clear();
    await _flags({FeatureFlags.stories: true, FeatureFlags.storeFollow: true});
  });

  testWidgets('белсенді стористер торы: сан, қалған уақыт', (t) async {
    await _open(t);
    expect(find.byKey(const ValueKey('tile-st1')), findsOneWidget);
    expect(find.byKey(const ValueKey('tile-st3')), findsOneWidget);
    expect(find.text('Активных: 3 из 10'), findsOneWidget);
    expect(find.text('ещё 5 ч'), findsNWidgets(3));
    expect(find.byKey(const ValueKey('stories-limit-note')), findsNothing);
    expect(_backend.bodies['stories_for_store'], {'p_store': 'owner-1'});
  });

  testWidgets('өшіру: растау, RPC, тақтайша кетеді; бас тартса — қалады',
      (t) async {
    await _open(t);
    await t.tap(find.byKey(const ValueKey('delete-st2')));
    await _settle(t);
    expect(find.text('Удалить сторис?'), findsOneWidget);
    await t.tap(find.text('Отмена'));
    await _settle(t);
    expect(_backend.count('story_delete'), 0);
    expect(find.byKey(const ValueKey('tile-st2')), findsOneWidget);

    await t.tap(find.byKey(const ValueKey('delete-st2')));
    await _settle(t);
    await t.tap(find.byKey(const ValueKey('confirm-delete')));
    await _settle(t);
    expect(_backend.bodies['story_delete'], {'p_id': 'st2'});
    expect(find.byKey(const ValueKey('tile-st2')), findsNothing);
    expect(find.text('Активных: 2 из 10'), findsOneWidget);
  });

  testWidgets('өшіру қатесі: тақтайша қалады, түсінікті хабар', (t) async {
    await _open(t);
    _backend.errors['story_delete'] = 'not_authorized';
    await t.tap(find.byKey(const ValueKey('delete-st1')));
    await _settle(t);
    await t.tap(find.byKey(const ValueKey('confirm-delete')));
    await _settle(t);
    expect(find.byKey(const ValueKey('tile-st1')), findsOneWidget);
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('10 белсенді: лимит ескертуі, «Добавить» таңдау ашпайды',
      (t) async {
    var picked = 0;
    await _open(t, count: 10, picker: (_) async {
      picked++;
      return _photo();
    });
    expect(find.text('Активных: 10 из 10'), findsOneWidget);
    expect(find.byKey(const ValueKey('stories-limit-note')), findsOneWidget);
    expect(find.textContaining('до 10 сторис'), findsWidgets);

    await t.tap(find.text('Добавить'));
    await _settle(t);
    expect(find.text('Камера'), findsNothing);
    expect(picked, 0);
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('қосу: галерея → превью → жазу (≤200) → жариялау → тор жаңарады',
      (t) async {
    final picked = <dynamic>[];
    await _open(t, picker: (src) async {
      picked.add(src);
      return _photo();
    });
    _backend.replies['story_create'] = _row('new1');
    final gate = Completer<void>();
    _backend.gates['story_create'] = gate.future;

    await t.tap(find.text('Добавить'));
    await _settle(t);
    expect(find.text('Камера'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('pick-gallery')));
    await _settle(t);
    expect(picked.single.toString(), contains('gallery'));

    // Превью экраны, жазу өрісі 200 таңбаға шектелген.
    expect(find.text('Новый сторис'), findsOneWidget);
    expect(find.byKey(const ValueKey('compose-preview')), findsOneWidget);
    expect(find.text('0/200'), findsOneWidget);
    await t.enterText(
        find.byKey(const ValueKey('compose-caption')), 'Жаңа коллекция!');
    await t.pump();
    expect(find.text('15/200'), findsOneWidget);
    await t.enterText(find.byKey(const ValueKey('compose-caption')), 'a' * 250);
    await t.pump();
    expect(find.text('200/200'), findsOneWidget);
    await t.enterText(
        find.byKey(const ValueKey('compose-caption')), 'Жаңа коллекция!');
    await t.pump();

    await t.tap(find.text('Опубликовать'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    // Жүктеу кезінде прогресс көрінеді, екінші басу қайталамайды.
    expect(find.byKey(const ValueKey('compose-progress')), findsOneWidget);
    expect(find.text('Загрузка…'), findsOneWidget);
    expect(_cloud.uploaded, hasLength(1));

    gate.complete();
    await _settle(t);
    await t.pump(const Duration(seconds: 1)); // жабылу анимациясы
    expect(_backend.bodies['story_create']?['p_caption'], 'Жаңа коллекция!');
    expect(_backend.bodies['story_create']?['p_image_url'],
        contains('qoima_stories'));
    expect(find.text('Новый сторис'), findsNothing);
    expect(find.byKey(const ValueKey('tile-new1')), findsOneWidget);
    expect(find.text('Активных: 4 из 10'), findsOneWidget);
  });

  testWidgets(
      'сервер stories_limit десе: превьюде қалады, сурет тазаланады, хабар түсінікті',
      (t) async {
    await _open(t, picker: (_) async => _photo());
    _backend.errors['story_create'] = 'stories_limit';

    await t.tap(find.text('Добавить'));
    await _settle(t);
    await t.tap(find.byKey(const ValueKey('pick-camera')));
    await _settle(t);
    await t.tap(find.text('Опубликовать'));
    await _settle(t);

    expect(find.text('Новый сторис'), findsOneWidget); // қалды — қайталауға
    expect(find.textContaining('до 10 сторис'), findsOneWidget);
    expect(_cloud.deleted, hasLength(1)); // жетім сурет Cloudinary-ден өшірілді
    expect(find.byKey(const ValueKey('compose-progress')), findsNothing);
  });

  testWidgets('таңдау бас тартылса не қате болса — ештеңе жарияланбайды',
      (t) async {
    await _open(t, picker: (_) async => null);
    await t.tap(find.text('Добавить'));
    await _settle(t);
    await t.tap(find.byKey(const ValueKey('pick-gallery')));
    await _settle(t);
    expect(find.text('Новый сторис'), findsNothing);
    expect(_backend.count('story_create'), 0);

    await t.pumpWidget(const SizedBox());
    await _open(t, picker: (_) async => throw Exception('permission'));
    await t.tap(find.text('Добавить'));
    await _settle(t);
    await t.tap(find.byKey(const ValueKey('pick-camera')));
    await _settle(t);
    expect(find.text('Новый сторис'), findsNothing);
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('жалауша өшік: бет жұмыс істемейді', (t) async {
    await _flags({FeatureFlags.stories: false});
    await _open(t);
    expect(find.text('Функция временно отключена'), findsOneWidget);
    expect(find.text('Добавить'), findsNothing);
  });

  testWidgets('бос тізім: нұсқау мәтіні', (t) async {
    await _open(t, count: 0);
    expect(find.textContaining('Пока нет сторис'), findsOneWidget);
    expect(find.text('Активных: 0 из 10'), findsOneWidget);
  });

  group('HubFollowerCountLine', () {
    Future<void> pumpLine(WidgetTester t) async {
      await t.pumpWidget(MaterialApp(
        home: Scaffold(body: HubFollowerCountLine(storeUid: 'owner-1')),
      ));
      await _settle(t);
    }

    testWidgets('жазылу қосулы: «N подписчиков»', (t) async {
      _backend.replies['store_follower_count'] = 12;
      await pumpLine(t);
      expect(find.text('12 подписчиков'), findsOneWidget);
      expect(_backend.bodies['store_follower_count'], {'p_store': 'owner-1'});
    });

    testWidgets('жалауша өшік: жол да жоқ, сұраныс та жоқ', (t) async {
      await _flags({FeatureFlags.storeFollow: false});
      _backend.replies['store_follower_count'] = 12;
      await pumpLine(t);
      expect(find.textContaining('подписчик'), findsNothing);
      expect(_backend.count('store_follower_count'), 0);
    });
  });
}
