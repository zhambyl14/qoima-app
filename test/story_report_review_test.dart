import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:qoima/core/app_user.dart';
import 'package:qoima/core/locale_context.dart';
import 'package:qoima/data/models/report_model.dart';
import 'package:qoima/data/models/story_model.dart';
import 'package:qoima/data/services/stories_service.dart';
import 'package:qoima/ui/client/stories/story_viewer_screen.dart';
import 'package:qoima/ui/superadmin/reports_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_backend.dart';

/// Шағым парағы жіберу кезінде жабылып қалса (свайп/фонды басу), жауап
/// келгенде ол АСТЫНДАҒЫ экранды (сторис көрермені) жаппауы керек.
final _backend = FakeBackend();
final _t0 = DateTime.utc(2026, 11, 2, 10);

StoryModel _story() => StoryModel.fromMap({
      'id': 'st1',
      'store_uid': 's1',
      'image_url': 'https://example.invalid/st1.jpg',
      'caption': 'Жаңа коллекция',
      'created_at': _t0.subtract(const Duration(minutes: 5)).toIso8601String(),
      'expires_at': _t0.add(const Duration(hours: 20)).toIso8601String(),
    });

Widget _fakeImage(BuildContext context, String url, VoidCallback onReady) {
  WidgetsBinding.instance.addPostFrameCallback((_) => onReady());
  return const ColoredBox(color: Colors.grey);
}

/// pumpAndSettle емес: сторис прогресі үздіксіз жүреді (ешқашан «тынбайды»).
Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 8; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _openViewerAndSend(WidgetTester t) async {
  t.view.physicalSize = const Size(400, 800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(ChangeNotifierProvider<AppUser>.value(
    value: AppUser.current,
    child: MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(ctx).push(MaterialPageRoute<void>(
                builder: (_) => StoryViewerScreen(
                  groups: [
                    StoryViewerGroup(
                        storeUid: 's1',
                        storeName: 'Aru Shoes',
                        stories: [_story()]),
                  ],
                  service: StoriesService(hiddenStoreIds: () async => {}),
                  imageBuilder: _fakeImage,
                  now: () => _t0,
                  // Сторис өзі жабылып кетпесін — тек парақ әрекеті тексеріледі.
                  storyDuration: const Duration(hours: 1),
                ),
              )),
              child: const Text('HOME'),
            ),
          ),
        ),
      ),
    ),
  ));
  await t.tap(find.text('HOME'));
  await _settle(t);
  expect(find.byType(StoryViewerScreen), findsOneWidget);

  await t.tap(find.byKey(const ValueKey('story-report')));
  await _settle(t);
  await t.tap(find.text('Другое'));
  await t.pump();
  await t.tap(find.text('Отправить жалобу'));
  await t.pump();
  // Жіберу жүріп жатқанда қолданушы парақты жабады (фонды басу).
  await t.tapAt(const Offset(200, 40));
  await _settle(t);
  expect(find.text('Отправить жалобу'), findsNothing);
  expect(find.byType(StoryViewerScreen), findsOneWidget);
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    await initFakeSupabase(_backend);
  });

  setUp(() {
    LocaleContext.currentLang = 'ru';
    _backend.calls.clear();
    _backend.bodies.clear();
    _backend.errors.clear();
    _backend.replies.clear();
    _backend.gates.clear();
    _backend.handler = null;
    AppUser().set(
        uid: 'client-1',
        ownerUid: 'client-1',
        name: 'Айгерім',
        email: '',
        phone: '+77010000000',
        role: 'client');
  });

  testWidgets('сәтті жауап: жабылған парақтан кейін көрермен орнында',
      (t) async {
    final gate = Completer<void>();
    _backend.gates['content_reports'] = gate.future;
    await _openViewerAndSend(t);
    gate.complete();
    await _settle(t);
    expect(find.byType(StoryViewerScreen), findsOneWidget,
        reason: 'кеш келген жауап астындағы экранды жаппауы керек');
    expect(find.textContaining('Жалоба отправлена'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('«бұрын шағымданған» жауабы: көрермен орнында', (t) async {
    final gate = Completer<void>();
    _backend.gates['content_reports'] = gate.future;
    _backend.errors['content_reports'] = 'already_reported';
    await _openViewerAndSend(t);
    gate.complete();
    await _settle(t);
    expect(find.byType(StoryViewerScreen), findsOneWidget,
        reason: 'кеш келген қате астындағы экранды жаппауы керек');
    expect(find.text('Вы уже отправили жалобу. Мы её рассмотрим.'),
        findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('модератор карточкасы 320px: ұзын дүкен атауы толып кетпейді',
      (t) async {
    t.view.physicalSize = const Size(320, 640);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final r = ReportModel.fromMap({
      'id': 'r1',
      'reporter_uid': 'c1',
      'reporter_name': 'Айгерім Нұрсұлтанқызы Байтұрсынова',
      'reporter_phone': '+77010000000',
      'target_type': 'story',
      'target_id': 'st1',
      'target_name': 'Өте ұзын сторис жазуы ' * 4,
      'target_image': 'https://example.invalid/a.jpg',
      'admin_uid': 's1',
      'store_name': 'Өте ұзын дүкен атауы Aru Shoes Almaty Mega Center 2026',
      'reason': 'offensive',
      'status': 'new',
      'created_at': '2026-11-02T10:00:00Z',
    });
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView(padding: const EdgeInsets.all(16), children: [
          ReportCard(
            report: r,
            onResolve: () {},
            onDismiss: () {},
            onDeleteReview: () {},
            onDeleteStory: () {},
            onBlockStore: () {},
          ),
        ]),
      ),
    ));
    await t.pump();
    expect(t.takeException(), isNull);
  });
}
